use std::collections::{HashMap, VecDeque};
use std::io::{Read, Write};
use std::path::PathBuf;
use std::process::{Child as OsChild, Command, Stdio};
use std::sync::{Arc, Mutex};

use portable_pty::{Child, CommandBuilder, MasterPty, PtySize, native_pty_system};

use vityod_agent_host::{AcpRuntime, AgentHost};
use vityod_kernel::BoundedEventJournal;
use vityod_workspace::WorkspaceActor;

pub struct ServiceRuntime {
    pub workspace: WorkspaceActor,
    pub agent_host: AgentHost,
    pub acp_agents: AcpRuntime,
    pub events: BoundedEventJournal<String>,
    pub jobs: ManagedJobRegistry,
    pub ptys: ManagedPtyRegistry,
    pub tasks: ManagedTaskRegistry,
    pub protocol_processes: ManagedByteProcessRegistry,
}

impl Default for ServiceRuntime {
    fn default() -> Self {
        Self {
            workspace: WorkspaceActor::default(),
            agent_host: AgentHost::default(),
            acp_agents: AcpRuntime::default(),
            events: BoundedEventJournal::new(4096),
            jobs: ManagedJobRegistry::new(128, 1024 * 1024),
            ptys: ManagedPtyRegistry::new(128, 1024 * 1024),
            tasks: ManagedTaskRegistry::new(128, 1024 * 1024),
            protocol_processes: ManagedByteProcessRegistry::new(64, 8 * 1024 * 1024),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JobKind {
    Pty,
    Task,
    LanguageServer,
    DebugAdapter,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JobState {
    Running,
    Terminated,
}

#[derive(Debug)]
pub struct ManagedJob {
    pub kind: JobKind,
    pub state: JobState,
    output: VecDeque<u8>,
}

#[derive(Debug)]
pub struct ManagedJobRegistry {
    maximum_active_jobs: usize,
    maximum_output_bytes: usize,
    jobs: HashMap<String, ManagedJob>,
}

impl ManagedJobRegistry {
    pub fn new(maximum_active_jobs: usize, maximum_output_bytes: usize) -> Self {
        Self {
            maximum_active_jobs,
            maximum_output_bytes,
            jobs: HashMap::new(),
        }
    }

    pub fn start(&mut self, id: String, kind: JobKind) -> Result<(), JobError> {
        if id.is_empty() || self.jobs.contains_key(&id) {
            return Err(JobError::InvalidIdentity);
        }
        let active = self
            .jobs
            .values()
            .filter(|job| job.state == JobState::Running)
            .count();
        if active >= self.maximum_active_jobs {
            return Err(JobError::CapacityExceeded);
        }
        self.jobs.insert(
            id,
            ManagedJob {
                kind,
                state: JobState::Running,
                output: VecDeque::new(),
            },
        );
        Ok(())
    }

    pub fn append_output(&mut self, id: &str, bytes: &[u8]) -> Result<(), JobError> {
        let job = self.jobs.get_mut(id).ok_or(JobError::UnknownJob)?;
        if job.state != JobState::Running {
            return Err(JobError::NotRunning);
        }
        for byte in bytes {
            if job.output.len() == self.maximum_output_bytes {
                job.output.pop_front();
            }
            job.output.push_back(*byte);
        }
        Ok(())
    }

    pub fn terminate(&mut self, id: &str) -> Result<(), JobError> {
        let job = self.jobs.get_mut(id).ok_or(JobError::UnknownJob)?;
        job.state = JobState::Terminated;
        Ok(())
    }

    pub fn output(&self, id: &str) -> Result<Vec<u8>, JobError> {
        let job = self.jobs.get(id).ok_or(JobError::UnknownJob)?;
        Ok(job.output.iter().copied().collect())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum JobError {
    InvalidIdentity,
    CapacityExceeded,
    UnknownJob,
    NotRunning,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PtyLaunch {
    pub id: String,
    pub executable: String,
    pub arguments: Vec<String>,
    pub working_directory: Option<PathBuf>,
    pub environment: HashMap<String, String>,
    pub rows: u16,
    pub cols: u16,
}

pub struct ManagedPtyRegistry {
    maximum_active_sessions: usize,
    maximum_output_bytes: usize,
    next_stream_id: u32,
    sessions: HashMap<u32, ManagedPtySession>,
    streams_by_id: HashMap<String, u32>,
}

struct ManagedPtySession {
    id: String,
    stream_id: u32,
    master: Box<dyn MasterPty + Send>,
    child: Box<dyn Child + Send + Sync>,
    writer: Box<dyn Write + Send>,
    output: Arc<Mutex<PtyOutput>>,
    next_output_sequence: u64,
    exit_code: Option<u32>,
}

#[derive(Debug, Default)]
struct PtyOutput {
    bytes: VecDeque<u8>,
    truncated: bool,
    closed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct PtyOutputChunk {
    pub stream_id: u32,
    pub sequence: u64,
    pub payload: Vec<u8>,
    pub truncated: bool,
    pub closed: bool,
    pub exit_code: Option<u32>,
}

impl ManagedPtyRegistry {
    pub fn new(maximum_active_sessions: usize, maximum_output_bytes: usize) -> Self {
        assert!(maximum_active_sessions > 0);
        assert!(maximum_output_bytes > 0);
        Self {
            maximum_active_sessions,
            maximum_output_bytes,
            next_stream_id: 1,
            sessions: HashMap::new(),
            streams_by_id: HashMap::new(),
        }
    }

    pub fn start(&mut self, launch: PtyLaunch) -> Result<u32, PtyRuntimeError> {
        self.reap_exited();
        if launch.id.is_empty()
            || launch.executable.is_empty()
            || launch.arguments.len() > 256
            || self.streams_by_id.contains_key(&launch.id)
        {
            return Err(PtyRuntimeError::InvalidRequest);
        }
        if self.sessions.len() >= self.maximum_active_sessions {
            return Err(PtyRuntimeError::CapacityExceeded);
        }
        let pty_system = native_pty_system();
        let pair = pty_system
            .openpty(PtySize {
                rows: launch.rows.max(1),
                cols: launch.cols.max(1),
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|_| PtyRuntimeError::StartFailed)?;
        let mut command = CommandBuilder::new(&launch.executable);
        command.args(launch.arguments);
        if let Some(directory) = launch.working_directory {
            command.cwd(directory);
        }
        command.env_clear();
        for (key, value) in launch.environment {
            if is_safe_environment_key(&key) {
                command.env(key, value);
            }
        }
        let child = pair
            .slave
            .spawn_command(command)
            .map_err(|_| PtyRuntimeError::StartFailed)?;
        drop(pair.slave);
        let mut reader = pair
            .master
            .try_clone_reader()
            .map_err(|_| PtyRuntimeError::StartFailed)?;
        let writer = pair
            .master
            .take_writer()
            .map_err(|_| PtyRuntimeError::StartFailed)?;
        let output = Arc::new(Mutex::new(PtyOutput::default()));
        let reader_output = Arc::clone(&output);
        let maximum_output_bytes = self.maximum_output_bytes;
        std::thread::spawn(move || {
            let mut buffer = [0_u8; 8192];
            loop {
                match reader.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(read) => {
                        let Ok(mut output) = reader_output.lock() else {
                            break;
                        };
                        for byte in &buffer[..read] {
                            if output.bytes.len() == maximum_output_bytes {
                                output.bytes.pop_front();
                                output.truncated = true;
                            }
                            output.bytes.push_back(*byte);
                        }
                    }
                    Err(_) => break,
                }
            }
            if let Ok(mut output) = reader_output.lock() {
                output.closed = true;
            }
        });
        let stream_id = self.allocate_stream_id()?;
        let id = launch.id;
        self.streams_by_id.insert(id.clone(), stream_id);
        self.sessions.insert(
            stream_id,
            ManagedPtySession {
                id,
                stream_id,
                master: pair.master,
                child,
                writer,
                output,
                next_output_sequence: 1,
                exit_code: None,
            },
        );
        Ok(stream_id)
    }

    pub fn write(&mut self, stream_id: u32, payload: &[u8]) -> Result<(), PtyRuntimeError> {
        let session = self
            .sessions
            .get_mut(&stream_id)
            .ok_or(PtyRuntimeError::UnknownSession)?;
        session
            .writer
            .write_all(payload)
            .and_then(|()| session.writer.flush())
            .map_err(|_| PtyRuntimeError::WriteFailed)
    }

    pub fn resize(&mut self, stream_id: u32, rows: u16, cols: u16) -> Result<(), PtyRuntimeError> {
        let session = self
            .sessions
            .get_mut(&stream_id)
            .ok_or(PtyRuntimeError::UnknownSession)?;
        session
            .master
            .resize(PtySize {
                rows: rows.max(1),
                cols: cols.max(1),
                pixel_width: 0,
                pixel_height: 0,
            })
            .map_err(|_| PtyRuntimeError::ResizeFailed)
    }

    pub fn drain(
        &mut self,
        stream_id: u32,
        credit: usize,
    ) -> Result<PtyOutputChunk, PtyRuntimeError> {
        let session = self
            .sessions
            .get_mut(&stream_id)
            .ok_or(PtyRuntimeError::UnknownSession)?;
        if session.exit_code.is_none() {
            session.exit_code = session
                .child
                .try_wait()
                .map_err(|_| PtyRuntimeError::OutputUnavailable)?
                .map(|status| status.exit_code());
        }
        let mut output = session
            .output
            .lock()
            .map_err(|_| PtyRuntimeError::OutputUnavailable)?;
        let accepted = credit.min(output.bytes.len()).min(256 * 1024);
        let payload = output.bytes.drain(..accepted).collect();
        let truncated = std::mem::take(&mut output.truncated);
        let closed = output.closed && output.bytes.is_empty() && session.exit_code.is_some();
        let sequence = session.next_output_sequence;
        session.next_output_sequence = session.next_output_sequence.saturating_add(1);
        Ok(PtyOutputChunk {
            stream_id: session.stream_id,
            sequence,
            payload,
            truncated,
            closed,
            exit_code: session.exit_code,
        })
    }

    pub fn terminate(&mut self, stream_id: u32) -> Result<u32, PtyRuntimeError> {
        let mut session = self
            .sessions
            .remove(&stream_id)
            .ok_or(PtyRuntimeError::UnknownSession)?;
        self.streams_by_id.remove(&session.id);
        if let Some(status) = session
            .child
            .try_wait()
            .map_err(|_| PtyRuntimeError::TerminateFailed)?
        {
            return Ok(status.exit_code());
        }
        session
            .child
            .kill()
            .map_err(|_| PtyRuntimeError::TerminateFailed)?;
        let status = session
            .child
            .wait()
            .map_err(|_| PtyRuntimeError::TerminateFailed)?;
        Ok(status.exit_code())
    }

    pub fn active_ids(&self) -> Vec<String> {
        let mut ids = self
            .sessions
            .values()
            .map(|session| session.id.clone())
            .collect::<Vec<_>>();
        ids.sort_unstable();
        ids
    }

    fn allocate_stream_id(&mut self) -> Result<u32, PtyRuntimeError> {
        for _ in 0..u32::MAX {
            let candidate = self.next_stream_id;
            self.next_stream_id = self.next_stream_id.wrapping_add(1).max(1);
            if !self.sessions.contains_key(&candidate) {
                return Ok(candidate);
            }
        }
        Err(PtyRuntimeError::CapacityExceeded)
    }

    fn reap_exited(&mut self) {
        let completed = self
            .sessions
            .iter_mut()
            .filter_map(|(stream_id, session)| {
                session
                    .child
                    .try_wait()
                    .ok()
                    .flatten()
                    .map(|_| (*stream_id, session.id.clone()))
            })
            .collect::<Vec<_>>();
        for (stream_id, id) in completed {
            self.sessions.remove(&stream_id);
            self.streams_by_id.remove(&id);
        }
    }
}

fn is_safe_environment_key(key: &str) -> bool {
    !key.is_empty()
        && key.len() <= 128
        && key
            .bytes()
            .all(|byte| byte == b'_' || byte.is_ascii_alphanumeric())
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PtyRuntimeError {
    InvalidRequest,
    CapacityExceeded,
    StartFailed,
    UnknownSession,
    WriteFailed,
    ResizeFailed,
    OutputUnavailable,
    TerminateFailed,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TaskLaunch {
    pub id: String,
    pub executable: PathBuf,
    pub arguments: Vec<String>,
    pub working_directory: Option<PathBuf>,
    pub environment: HashMap<String, String>,
    pub standard_input: Option<Vec<u8>>,
    pub timeout: std::time::Duration,
}

pub struct ManagedTaskRegistry {
    maximum_active_tasks: usize,
    maximum_output_bytes: usize,
    tasks: HashMap<String, ManagedTask>,
}

struct ManagedTask {
    child: OsChild,
    #[cfg(not(windows))]
    process_group_id: Option<u32>,
    #[cfg(windows)]
    job: WindowsJob,
    output: Arc<Mutex<TaskOutput>>,
    started: std::time::Instant,
    timeout: std::time::Duration,
    exit_code: Option<i32>,
    timed_out: bool,
}

#[derive(Debug, Default)]
struct TaskOutput {
    stdout: Vec<u8>,
    stderr: Vec<u8>,
    stdout_truncated: bool,
    stderr_truncated: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TaskSnapshot {
    pub running: bool,
    pub timed_out: bool,
    pub exit_code: Option<i32>,
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub stdout_truncated: bool,
    pub stderr_truncated: bool,
    pub duration_millis: u64,
}

impl ManagedTaskRegistry {
    pub fn new(maximum_active_tasks: usize, maximum_output_bytes: usize) -> Self {
        assert!(maximum_active_tasks > 0);
        assert!(maximum_output_bytes > 0);
        Self {
            maximum_active_tasks,
            maximum_output_bytes,
            tasks: HashMap::new(),
        }
    }

    pub fn start(&mut self, launch: TaskLaunch) -> Result<(), TaskRuntimeError> {
        if launch.id.is_empty()
            || launch.id.len() > 256
            || launch.arguments.len() > 256
            || launch.timeout.is_zero()
            || self.tasks.contains_key(&launch.id)
            || !launch.executable.is_absolute()
            || launch
                .working_directory
                .as_ref()
                .is_some_and(|path| !path.is_absolute())
        {
            return Err(TaskRuntimeError::InvalidRequest);
        }
        if self
            .tasks
            .values()
            .filter(|task| task.exit_code.is_none())
            .count()
            >= self.maximum_active_tasks
        {
            return Err(TaskRuntimeError::CapacityExceeded);
        }
        let executable = launch
            .executable
            .canonicalize()
            .map_err(|_| TaskRuntimeError::InvalidRequest)?;
        let working_directory = launch
            .working_directory
            .map(|path| path.canonicalize())
            .transpose()
            .map_err(|_| TaskRuntimeError::InvalidRequest)?;
        let mut command = Command::new(executable);
        command
            .args(launch.arguments)
            .env_clear()
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        if let Some(working_directory) = working_directory {
            command.current_dir(working_directory);
        }
        for (key, value) in launch.environment {
            if is_safe_environment_key(&key) {
                command.env(key, value);
            }
        }
        #[cfg(unix)]
        {
            use std::os::unix::process::CommandExt;
            command.process_group(0);
        }
        let mut child = command.spawn().map_err(|_| TaskRuntimeError::StartFailed)?;
        #[cfg(windows)]
        let job = WindowsJob::assign(&child).map_err(|_| TaskRuntimeError::StartFailed)?;
        #[cfg(unix)]
        let process_group_id = Some(child.id());
        #[cfg(all(not(unix), not(windows)))]
        let process_group_id = None;
        if let Some(input) = launch.standard_input {
            let mut stdin = child.stdin.take().ok_or(TaskRuntimeError::StartFailed)?;
            stdin
                .write_all(&input)
                .and_then(|()| stdin.flush())
                .map_err(|_| TaskRuntimeError::WriteFailed)?;
        }
        drop(child.stdin.take());
        let mut stdout = child.stdout.take().ok_or(TaskRuntimeError::StartFailed)?;
        let mut stderr = child.stderr.take().ok_or(TaskRuntimeError::StartFailed)?;
        let output = Arc::new(Mutex::new(TaskOutput::default()));
        let stdout_output = Arc::clone(&output);
        let stderr_output = Arc::clone(&output);
        let maximum_output_bytes = self.maximum_output_bytes;
        std::thread::spawn(move || {
            let mut buffer = [0_u8; 8192];
            loop {
                match stdout.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(read) => {
                        let Ok(mut output) = stdout_output.lock() else {
                            break;
                        };
                        let remaining = maximum_output_bytes.saturating_sub(output.stdout.len());
                        let accepted = remaining.min(read);
                        output.stdout.extend_from_slice(&buffer[..accepted]);
                        if accepted != read {
                            output.stdout_truncated = true;
                        }
                    }
                    Err(_) => break,
                }
            }
        });
        std::thread::spawn(move || {
            let mut buffer = [0_u8; 8192];
            loop {
                match stderr.read(&mut buffer) {
                    Ok(0) => break,
                    Ok(read) => {
                        let Ok(mut output) = stderr_output.lock() else {
                            break;
                        };
                        let remaining = maximum_output_bytes.saturating_sub(output.stderr.len());
                        let accepted = remaining.min(read);
                        output.stderr.extend_from_slice(&buffer[..accepted]);
                        if accepted != read {
                            output.stderr_truncated = true;
                        }
                    }
                    Err(_) => break,
                }
            }
        });
        self.tasks.insert(
            launch.id,
            ManagedTask {
                child,
                #[cfg(not(windows))]
                process_group_id,
                #[cfg(windows)]
                job,
                output,
                started: std::time::Instant::now(),
                timeout: launch.timeout,
                exit_code: None,
                timed_out: false,
            },
        );
        Ok(())
    }

    pub fn snapshot(&mut self, id: &str) -> Result<TaskSnapshot, TaskRuntimeError> {
        let task = self
            .tasks
            .get_mut(id)
            .ok_or(TaskRuntimeError::UnknownTask)?;
        if task.exit_code.is_none() && task.started.elapsed() >= task.timeout {
            task.timed_out = true;
            #[cfg(windows)]
            task.job.terminate();
            #[cfg(not(windows))]
            terminate_process_tree(&mut task.child, task.process_group_id);
            task.exit_code = task
                .child
                .wait()
                .ok()
                .map(|status| status.code().unwrap_or(1));
        } else if task.exit_code.is_none() {
            task.exit_code = task
                .child
                .try_wait()
                .map_err(|_| TaskRuntimeError::PollFailed)?
                .map(|status| status.code().unwrap_or(1));
        }
        let output = task
            .output
            .lock()
            .map_err(|_| TaskRuntimeError::PollFailed)?;
        Ok(TaskSnapshot {
            running: task.exit_code.is_none(),
            timed_out: task.timed_out,
            exit_code: task.exit_code,
            stdout: output.stdout.clone(),
            stderr: output.stderr.clone(),
            stdout_truncated: output.stdout_truncated,
            stderr_truncated: output.stderr_truncated,
            duration_millis: task
                .started
                .elapsed()
                .as_millis()
                .try_into()
                .unwrap_or(u64::MAX),
        })
    }

    pub fn cancel(&mut self, id: &str) -> Result<i32, TaskRuntimeError> {
        let task = self
            .tasks
            .get_mut(id)
            .ok_or(TaskRuntimeError::UnknownTask)?;
        if let Some(exit_code) = task.exit_code {
            return Ok(exit_code);
        }
        #[cfg(windows)]
        task.job.terminate();
        #[cfg(not(windows))]
        terminate_process_tree(&mut task.child, task.process_group_id);
        let status = task
            .child
            .wait()
            .map_err(|_| TaskRuntimeError::TerminateFailed)?;
        let exit_code = status.code().unwrap_or(1);
        task.exit_code = Some(exit_code);
        Ok(exit_code)
    }

    pub fn remove(&mut self, id: &str) -> Result<(), TaskRuntimeError> {
        let task = self.tasks.get(id).ok_or(TaskRuntimeError::UnknownTask)?;
        if task.exit_code.is_none() {
            return Err(TaskRuntimeError::TaskRunning);
        }
        self.tasks.remove(id);
        Ok(())
    }

    pub fn active_ids(&self) -> Vec<String> {
        let mut ids = self
            .tasks
            .iter()
            .filter(|(_, task)| task.exit_code.is_none())
            .map(|(id, _)| id.clone())
            .collect::<Vec<_>>();
        ids.sort_unstable();
        ids
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TaskRuntimeError {
    InvalidRequest,
    CapacityExceeded,
    StartFailed,
    UnknownTask,
    WriteFailed,
    PollFailed,
    TerminateFailed,
    TaskRunning,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ByteProcessLaunch {
    pub id: String,
    pub executable: PathBuf,
    pub arguments: Vec<String>,
    pub working_directory: Option<PathBuf>,
    pub environment: HashMap<String, String>,
}

pub struct ManagedByteProcessRegistry {
    maximum_active_processes: usize,
    maximum_buffered_bytes: usize,
    processes: HashMap<String, ManagedByteProcess>,
}

struct ManagedByteProcess {
    child: OsChild,
    #[cfg(not(windows))]
    process_group_id: Option<u32>,
    #[cfg(windows)]
    job: WindowsJob,
    stdin: std::process::ChildStdin,
    output: Arc<Mutex<ByteProcessOutput>>,
    exit_code: Option<i32>,
}

#[derive(Debug, Default)]
struct ByteProcessOutput {
    stdout: VecDeque<u8>,
    stderr: VecDeque<u8>,
    overflowed: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ByteProcessPoll {
    pub stdout: Vec<u8>,
    pub stderr: Vec<u8>,
    pub exit_code: Option<i32>,
    pub overflowed: bool,
}

impl ManagedByteProcessRegistry {
    pub fn new(maximum_active_processes: usize, maximum_buffered_bytes: usize) -> Self {
        assert!(maximum_active_processes > 0);
        assert!(maximum_buffered_bytes > 0);
        Self {
            maximum_active_processes,
            maximum_buffered_bytes,
            processes: HashMap::new(),
        }
    }

    pub fn start(&mut self, launch: ByteProcessLaunch) -> Result<(), ByteProcessError> {
        self.reap_exited();
        if launch.id.is_empty()
            || launch.id.len() > 256
            || launch.arguments.len() > 256
            || self.processes.contains_key(&launch.id)
            || !launch.executable.is_absolute()
            || launch
                .working_directory
                .as_ref()
                .is_some_and(|path| !path.is_absolute())
        {
            return Err(ByteProcessError::InvalidRequest);
        }
        if self.processes.len() >= self.maximum_active_processes {
            return Err(ByteProcessError::CapacityExceeded);
        }
        let executable = launch
            .executable
            .canonicalize()
            .map_err(|_| ByteProcessError::InvalidRequest)?;
        let working_directory = launch
            .working_directory
            .map(|path| path.canonicalize())
            .transpose()
            .map_err(|_| ByteProcessError::InvalidRequest)?;
        let mut command = Command::new(executable);
        command
            .args(launch.arguments)
            .env_clear()
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        if let Some(working_directory) = working_directory {
            command.current_dir(working_directory);
        }
        for (key, value) in launch.environment {
            if is_safe_environment_key(&key) {
                command.env(key, value);
            }
        }
        #[cfg(unix)]
        {
            use std::os::unix::process::CommandExt;
            command.process_group(0);
        }
        let mut child = command.spawn().map_err(|_| ByteProcessError::StartFailed)?;
        #[cfg(windows)]
        let job = WindowsJob::assign(&child).map_err(|_| ByteProcessError::StartFailed)?;
        #[cfg(unix)]
        let process_group_id = Some(child.id());
        #[cfg(all(not(unix), not(windows)))]
        let process_group_id = None;
        let stdin = child.stdin.take().ok_or(ByteProcessError::StartFailed)?;
        let mut stdout = child.stdout.take().ok_or(ByteProcessError::StartFailed)?;
        let mut stderr = child.stderr.take().ok_or(ByteProcessError::StartFailed)?;
        let output = Arc::new(Mutex::new(ByteProcessOutput::default()));
        let stdout_output = Arc::clone(&output);
        let stderr_output = Arc::clone(&output);
        let maximum_buffered_bytes = self.maximum_buffered_bytes;
        std::thread::spawn(move || {
            drain_byte_stream(&mut stdout, stdout_output, maximum_buffered_bytes, true);
        });
        std::thread::spawn(move || {
            drain_byte_stream(&mut stderr, stderr_output, maximum_buffered_bytes, false);
        });
        self.processes.insert(
            launch.id,
            ManagedByteProcess {
                child,
                #[cfg(not(windows))]
                process_group_id,
                #[cfg(windows)]
                job,
                stdin,
                output,
                exit_code: None,
            },
        );
        Ok(())
    }

    pub fn write(&mut self, id: &str, bytes: &[u8]) -> Result<(), ByteProcessError> {
        if bytes.is_empty() || bytes.len() > 1024 * 1024 {
            return Err(ByteProcessError::InvalidRequest);
        }
        let process = self
            .processes
            .get_mut(id)
            .ok_or(ByteProcessError::UnknownProcess)?;
        if process.exit_code.is_some() {
            return Err(ByteProcessError::NotRunning);
        }
        process
            .stdin
            .write_all(bytes)
            .and_then(|()| process.stdin.flush())
            .map_err(|_| ByteProcessError::WriteFailed)
    }

    pub fn poll(
        &mut self,
        id: &str,
        maximum_bytes: usize,
    ) -> Result<ByteProcessPoll, ByteProcessError> {
        let process = self
            .processes
            .get_mut(id)
            .ok_or(ByteProcessError::UnknownProcess)?;
        if process.exit_code.is_none() {
            process.exit_code = process
                .child
                .try_wait()
                .map_err(|_| ByteProcessError::PollFailed)?
                .map(|status| status.code().unwrap_or(1));
        }
        let mut output = process
            .output
            .lock()
            .map_err(|_| ByteProcessError::PollFailed)?;
        let maximum_bytes = maximum_bytes.clamp(1, 1024 * 1024);
        let stdout_take = maximum_bytes.min(output.stdout.len());
        let stdout = output.stdout.drain(..stdout_take).collect();
        let remaining = maximum_bytes.saturating_sub(stdout_take);
        let stderr_take = remaining.min(output.stderr.len());
        let stderr = output.stderr.drain(..stderr_take).collect();
        Ok(ByteProcessPoll {
            stdout,
            stderr,
            exit_code: process.exit_code,
            overflowed: output.overflowed,
        })
    }

    pub fn stop(&mut self, id: &str) -> Result<i32, ByteProcessError> {
        let mut process = self
            .processes
            .remove(id)
            .ok_or(ByteProcessError::UnknownProcess)?;
        if let Some(exit_code) = process.exit_code {
            return Ok(exit_code);
        }
        if let Some(status) = process
            .child
            .try_wait()
            .map_err(|_| ByteProcessError::PollFailed)?
        {
            return Ok(status.code().unwrap_or(1));
        }
        #[cfg(windows)]
        process.job.terminate();
        #[cfg(not(windows))]
        terminate_process_tree(&mut process.child, process.process_group_id);
        process
            .child
            .wait()
            .map(|status| status.code().unwrap_or(1))
            .map_err(|_| ByteProcessError::TerminateFailed)
    }

    pub fn active_ids(&self) -> Vec<String> {
        let mut ids = self.processes.keys().cloned().collect::<Vec<_>>();
        ids.sort_unstable();
        ids
    }

    fn reap_exited(&mut self) {
        self.processes
            .retain(|_, process| process.child.try_wait().ok().flatten().is_none());
    }
}

fn drain_byte_stream(
    reader: &mut impl Read,
    output: Arc<Mutex<ByteProcessOutput>>,
    maximum_buffered_bytes: usize,
    stdout: bool,
) {
    let mut buffer = [0_u8; 8192];
    loop {
        let Ok(read) = reader.read(&mut buffer) else {
            break;
        };
        if read == 0 {
            break;
        }
        let Ok(mut output) = output.lock() else {
            break;
        };
        for byte in &buffer[..read] {
            let overflowed = if stdout {
                if output.stdout.len() == maximum_buffered_bytes {
                    output.stdout.pop_front();
                    true
                } else {
                    false
                }
            } else if output.stderr.len() == maximum_buffered_bytes {
                output.stderr.pop_front();
                true
            } else {
                false
            };
            if overflowed {
                output.overflowed = true;
            }
            if stdout {
                output.stdout.push_back(*byte);
            } else {
                output.stderr.push_back(*byte);
            }
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ByteProcessError {
    InvalidRequest,
    CapacityExceeded,
    StartFailed,
    UnknownProcess,
    NotRunning,
    WriteFailed,
    PollFailed,
    TerminateFailed,
}

#[cfg(windows)]
struct WindowsJob(windows_sys::Win32::Foundation::HANDLE);

#[cfg(windows)]
unsafe impl Send for WindowsJob {}

#[cfg(windows)]
impl WindowsJob {
    fn assign(child: &OsChild) -> Result<Self, ()> {
        use windows_sys::Win32::System::JobObjects::{
            AssignProcessToJobObject, CreateJobObjectW, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
            JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JobObjectExtendedLimitInformation,
            SetInformationJobObject,
        };
        let handle = unsafe { CreateJobObjectW(std::ptr::null(), std::ptr::null()) };
        if handle.is_null() {
            return Err(());
        }
        let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = unsafe { std::mem::zeroed() };
        limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        let configured = unsafe {
            SetInformationJobObject(
                handle,
                JobObjectExtendedLimitInformation,
                (&limits as *const JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast(),
                std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
            )
        };
        let assigned = configured != 0
            && unsafe {
                AssignProcessToJobObject(
                    handle,
                    std::os::windows::io::AsRawHandle::as_raw_handle(child) as _,
                )
            } != 0;
        if !assigned {
            unsafe {
                windows_sys::Win32::Foundation::CloseHandle(handle);
            }
            return Err(());
        }
        Ok(Self(handle))
    }

    fn terminate(&self) {
        unsafe {
            windows_sys::Win32::System::JobObjects::TerminateJobObject(self.0, 1);
        }
    }
}

#[cfg(windows)]
impl Drop for WindowsJob {
    fn drop(&mut self) {
        unsafe {
            windows_sys::Win32::Foundation::CloseHandle(self.0);
        }
    }
}

#[cfg(not(windows))]
fn terminate_process_tree(child: &mut OsChild, process_group_id: Option<u32>) {
    #[cfg(unix)]
    if let Some(process_group_id) = process_group_id {
        let process_group_id = i32::try_from(process_group_id).unwrap_or(i32::MAX);
        // SAFETY: a negative pid targets only the dedicated child process group.
        unsafe {
            libc::kill(-process_group_id, libc::SIGKILL);
        }
        return;
    }
    #[cfg(not(unix))]
    let _ = process_group_id;
    let _ = child.kill();
}

impl ServiceRuntime {
    pub fn health(&self) -> ServiceHealth {
        ServiceHealth {
            protocol_version: 1,
            workspace_revision: self.workspace.revision(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ServiceHealth {
    pub protocol_version: u16,
    pub workspace_revision: u64,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn managed_jobs_bound_output_and_reject_post_termination_writes() {
        let mut jobs = ManagedJobRegistry::new(1, 4);
        jobs.start("terminal".into(), JobKind::Pty).unwrap();
        jobs.append_output("terminal", b"abcdef").unwrap();
        assert_eq!(jobs.output("terminal").unwrap(), b"cdef");
        jobs.terminate("terminal").unwrap();
        assert_eq!(
            jobs.append_output("terminal", b"late"),
            Err(JobError::NotRunning)
        );
    }

    #[cfg(unix)]
    #[test]
    fn managed_pty_preserves_input_output_and_resize_order() {
        let mut ptys = ManagedPtyRegistry::new(2, 1024);
        let stream = ptys
            .start(PtyLaunch {
                id: "terminal".into(),
                executable: "/bin/sh".into(),
                arguments: vec![
                    "-c".into(),
                    "read value; printf 'seen:%s' \"$value\"".into(),
                ],
                working_directory: None,
                environment: HashMap::new(),
                rows: 24,
                cols: 80,
            })
            .unwrap();
        ptys.resize(stream, 30, 100).unwrap();
        ptys.write(stream, b"hello\n").unwrap();
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3);
        let mut all = Vec::new();
        while std::time::Instant::now() < deadline {
            let chunk = ptys.drain(stream, 1024).unwrap();
            all.extend(chunk.payload);
            if String::from_utf8_lossy(&all).contains("seen:hello") {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        assert!(String::from_utf8_lossy(&all).contains("seen:hello"));
        ptys.terminate(stream).unwrap();
    }

    #[cfg(unix)]
    #[test]
    fn managed_task_bounds_output_and_reports_completion() {
        let mut tasks = ManagedTaskRegistry::new(2, 4);
        tasks
            .start(TaskLaunch {
                id: "task".into(),
                executable: PathBuf::from("/bin/sh"),
                arguments: vec!["-c".into(), "printf abcdef".into()],
                working_directory: None,
                environment: HashMap::new(),
                standard_input: None,
                timeout: std::time::Duration::from_secs(3),
            })
            .unwrap();
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3);
        let snapshot = loop {
            let snapshot = tasks.snapshot("task").unwrap();
            if !snapshot.running || std::time::Instant::now() >= deadline {
                break snapshot;
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        };
        assert_eq!(snapshot.exit_code, Some(0));
        assert_eq!(snapshot.stdout, b"abcd");
        assert!(snapshot.stdout_truncated);
        tasks.remove("task").unwrap();
    }
}
