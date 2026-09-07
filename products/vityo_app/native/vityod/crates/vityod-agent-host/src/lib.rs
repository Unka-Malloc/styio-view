use std::collections::{HashMap, HashSet, VecDeque};
use std::io::{BufRead, BufReader, Write};
use std::path::PathBuf;
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::{Arc, Mutex};

mod acp;

pub use acp::{
    AcpConnectionSnapshot, AcpError, AcpEvent, AcpPermissionRequest, AcpPollResult, AcpRuntime,
    AcpSessionSnapshot,
};

#[derive(Debug, Clone)]
pub struct CapabilityGrant {
    pub workspace_id: String,
    pub workspace_revision: u64,
    pub capabilities: HashSet<String>,
    revoked: bool,
}

#[derive(Debug, Default)]
pub struct AgentHost {
    grants: HashMap<String, CapabilityGrant>,
    sessions: HashMap<String, AgentSessionProjection>,
}

impl AgentHost {
    pub fn grant(&mut self, session_id: String, grant: CapabilityGrant) {
        self.grants.insert(session_id, grant);
    }

    pub fn revoke(&mut self, session_id: &str) {
        if let Some(grant) = self.grants.get_mut(session_id) {
            grant.revoked = true;
        }
    }

    pub fn authorize(
        &self,
        session_id: &str,
        workspace_id: &str,
        revision: u64,
        capability: &str,
    ) -> Result<(), AuthorizationError> {
        let grant = self
            .grants
            .get(session_id)
            .ok_or(AuthorizationError::UnknownSession)?;
        if grant.revoked {
            return Err(AuthorizationError::Revoked);
        }
        if grant.workspace_id != workspace_id || grant.workspace_revision != revision {
            return Err(AuthorizationError::StaleScope);
        }
        if !grant.capabilities.contains(capability) {
            return Err(AuthorizationError::MissingCapability);
        }
        Ok(())
    }

    pub fn start_session(&mut self, session_id: String, event_capacity: usize) {
        self.sessions
            .entry(session_id.clone())
            .or_insert_with(|| AgentSessionProjection::new(session_id, event_capacity));
    }

    pub fn append_event(
        &mut self,
        session_id: &str,
        kind: impl Into<String>,
    ) -> Result<SessionEvent, SessionError> {
        self.sessions
            .get_mut(session_id)
            .ok_or(SessionError::UnknownSession)?
            .append(kind.into())
    }

    pub fn resume_events(
        &self,
        session_id: &str,
        after_sequence: u64,
    ) -> Result<Vec<SessionEvent>, SessionError> {
        self.sessions
            .get(session_id)
            .ok_or(SessionError::UnknownSession)?
            .resume_after(after_sequence)
    }

    pub fn request_permission(
        &mut self,
        session_id: &str,
        request_id: String,
    ) -> Result<(), SessionError> {
        let session = self
            .sessions
            .get_mut(session_id)
            .ok_or(SessionError::UnknownSession)?;
        if session.permissions.contains_key(&request_id) {
            return Err(SessionError::DuplicatePermissionRequest);
        }
        session.permissions.insert(request_id, None);
        Ok(())
    }

    pub fn resolve_permission(
        &mut self,
        session_id: &str,
        request_id: &str,
        decision: PermissionDecision,
    ) -> Result<(), SessionError> {
        let session = self
            .sessions
            .get_mut(session_id)
            .ok_or(SessionError::UnknownSession)?;
        let current = session
            .permissions
            .get_mut(request_id)
            .ok_or(SessionError::UnknownPermissionRequest)?;
        if current.is_some() {
            return Err(SessionError::PermissionAlreadyResolved);
        }
        *current = Some(decision);
        Ok(())
    }
}

impl CapabilityGrant {
    pub fn new(
        workspace_id: impl Into<String>,
        workspace_revision: u64,
        capabilities: impl IntoIterator<Item = String>,
    ) -> Self {
        Self {
            workspace_id: workspace_id.into(),
            workspace_revision,
            capabilities: capabilities.into_iter().collect(),
            revoked: false,
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AuthorizationError {
    UnknownSession,
    Revoked,
    StaleScope,
    MissingCapability,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct SessionEvent {
    pub sequence: u64,
    pub kind: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PermissionDecision {
    AllowOnce,
    Deny,
}

#[derive(Debug)]
struct AgentSessionProjection {
    _session_id: String,
    capacity: usize,
    next_sequence: u64,
    events: VecDeque<SessionEvent>,
    permissions: HashMap<String, Option<PermissionDecision>>,
}

impl AgentSessionProjection {
    fn new(session_id: String, capacity: usize) -> Self {
        Self {
            _session_id: session_id,
            capacity: capacity.max(1),
            next_sequence: 1,
            events: VecDeque::with_capacity(capacity.max(1)),
            permissions: HashMap::new(),
        }
    }

    fn append(&mut self, kind: String) -> Result<SessionEvent, SessionError> {
        if kind.is_empty() {
            return Err(SessionError::InvalidEvent);
        }
        let event = SessionEvent {
            sequence: self.next_sequence,
            kind,
        };
        self.next_sequence += 1;
        if self.events.len() == self.capacity {
            self.events.pop_front();
        }
        self.events.push_back(event.clone());
        Ok(event)
    }

    fn resume_after(&self, sequence: u64) -> Result<Vec<SessionEvent>, SessionError> {
        if let Some(first) = self.events.front()
            && sequence.saturating_add(1) < first.sequence
        {
            return Err(SessionError::ResumeGap);
        }
        Ok(self
            .events
            .iter()
            .filter(|event| event.sequence > sequence)
            .cloned()
            .collect())
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SessionError {
    UnknownSession,
    InvalidEvent,
    ResumeGap,
    DuplicatePermissionRequest,
    UnknownPermissionRequest,
    PermissionAlreadyResolved,
}

pub struct SupervisedAgentRegistry {
    maximum_sessions: usize,
    maximum_buffered_bytes: usize,
    maximum_message_bytes: usize,
    sessions: HashMap<String, SupervisedAgentProcess>,
}

impl Drop for SupervisedAgentRegistry {
    fn drop(&mut self) {
        let agent_ids = self.active_ids();
        for agent_id in agent_ids {
            let _ = self.close(&agent_id);
        }
    }
}

struct SupervisedAgentProcess {
    child: Child,
    #[cfg(not(windows))]
    process_group_id: Option<u32>,
    #[cfg(windows)]
    job: WindowsJob,
    stdin: ChildStdin,
    output: Arc<Mutex<AgentOutputBuffer>>,
}

#[derive(Debug, Default)]
struct AgentOutputBuffer {
    messages: VecDeque<Vec<u8>>,
    buffered_bytes: usize,
    protocol_failed: bool,
    message_too_large: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentProcessLaunch {
    pub agent_id: String,
    pub executable: PathBuf,
    pub arguments: Vec<String>,
    pub working_directory: PathBuf,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AgentPollResult {
    pub messages: Vec<Vec<u8>>,
    pub exit_code: Option<i32>,
    pub protocol_failed: bool,
    pub message_too_large: bool,
}

impl SupervisedAgentRegistry {
    pub fn new(
        maximum_sessions: usize,
        maximum_buffered_bytes: usize,
        maximum_message_bytes: usize,
    ) -> Self {
        assert!(maximum_sessions > 0);
        assert!(maximum_buffered_bytes > 0);
        assert!(maximum_message_bytes > 0);
        Self {
            maximum_sessions,
            maximum_buffered_bytes,
            maximum_message_bytes,
            sessions: HashMap::new(),
        }
    }

    pub fn start(&mut self, launch: AgentProcessLaunch) -> Result<(), AgentProcessError> {
        self.reap_exited();
        if launch.agent_id.is_empty()
            || launch.agent_id.len() > 256
            || launch.arguments.len() > 256
            || self.sessions.contains_key(&launch.agent_id)
            || !launch.executable.is_absolute()
            || !launch.working_directory.is_absolute()
        {
            return Err(AgentProcessError::InvalidLaunch);
        }
        let executable = launch
            .executable
            .canonicalize()
            .map_err(|_| AgentProcessError::InvalidLaunch)?;
        let working_directory = launch
            .working_directory
            .canonicalize()
            .map_err(|_| AgentProcessError::InvalidLaunch)?;
        if self.sessions.len() >= self.maximum_sessions {
            return Err(AgentProcessError::CapacityExceeded);
        }
        let mut command = Command::new(executable);
        command
            .args(launch.arguments)
            .current_dir(working_directory)
            .env_clear()
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped());
        #[cfg(unix)]
        {
            use std::os::unix::process::CommandExt;
            command.process_group(0);
        }
        let mut child = command
            .spawn()
            .map_err(|_| AgentProcessError::StartFailed)?;
        #[cfg(windows)]
        let job = WindowsJob::assign(&child).map_err(|_| AgentProcessError::StartFailed)?;
        #[cfg(unix)]
        let process_group_id = Some(child.id());
        #[cfg(all(not(unix), not(windows)))]
        let process_group_id = None;
        let stdin = child.stdin.take().ok_or(AgentProcessError::StartFailed)?;
        let stdout = child.stdout.take().ok_or(AgentProcessError::StartFailed)?;
        let stderr = child.stderr.take().ok_or(AgentProcessError::StartFailed)?;
        let output = Arc::new(Mutex::new(AgentOutputBuffer::default()));
        let reader_output = Arc::clone(&output);
        let maximum_message_bytes = self.maximum_message_bytes;
        let maximum_buffered_bytes = self.maximum_buffered_bytes;
        std::thread::spawn(move || {
            let mut reader = BufReader::new(stdout);
            loop {
                let mut message = Vec::new();
                match reader.read_until(b'\n', &mut message) {
                    Ok(0) => break,
                    Ok(_) => {
                        if message.last() == Some(&b'\n') {
                            message.pop();
                        }
                        if message.last() == Some(&b'\r') {
                            message.pop();
                        }
                        let Ok(mut output) = reader_output.lock() else {
                            break;
                        };
                        if message.is_empty() || message.len() > maximum_message_bytes {
                            output.protocol_failed = true;
                            output.message_too_large = message.len() > maximum_message_bytes;
                            break;
                        }
                        while output.buffered_bytes + message.len() > maximum_buffered_bytes {
                            let Some(removed) = output.messages.pop_front() else {
                                output.protocol_failed = true;
                                break;
                            };
                            output.buffered_bytes -= removed.len();
                        }
                        if output.protocol_failed {
                            break;
                        }
                        output.buffered_bytes += message.len();
                        output.messages.push_back(message);
                    }
                    Err(_) => {
                        if let Ok(mut output) = reader_output.lock() {
                            output.protocol_failed = true;
                        }
                        break;
                    }
                }
            }
        });
        std::thread::spawn(move || {
            for _ in BufReader::new(stderr).split(b'\n') {
                // Drain Agent stderr without serializing provider or environment data.
            }
        });
        self.sessions.insert(
            launch.agent_id,
            SupervisedAgentProcess {
                child,
                #[cfg(not(windows))]
                process_group_id,
                #[cfg(windows)]
                job,
                stdin,
                output,
            },
        );
        Ok(())
    }

    pub fn send(&mut self, agent_id: &str, message: &[u8]) -> Result<(), AgentProcessError> {
        if message.is_empty()
            || message.len() > self.maximum_message_bytes
            || message.contains(&b'\n')
        {
            return Err(AgentProcessError::InvalidMessage);
        }
        let process = self
            .sessions
            .get_mut(agent_id)
            .ok_or(AgentProcessError::UnknownAgent)?;
        process
            .stdin
            .write_all(message)
            .and_then(|()| process.stdin.write_all(b"\n"))
            .and_then(|()| process.stdin.flush())
            .map_err(|_| AgentProcessError::WriteFailed)
    }

    pub fn poll(
        &mut self,
        agent_id: &str,
        maximum_messages: usize,
    ) -> Result<AgentPollResult, AgentProcessError> {
        let process = self
            .sessions
            .get_mut(agent_id)
            .ok_or(AgentProcessError::UnknownAgent)?;
        let exit_code = process
            .child
            .try_wait()
            .map_err(|_| AgentProcessError::PollFailed)?
            .map(|status| status.code().unwrap_or(1));
        let mut output = process
            .output
            .lock()
            .map_err(|_| AgentProcessError::PollFailed)?;
        let take = maximum_messages.clamp(1, 128).min(output.messages.len());
        let messages = output.messages.drain(..take).collect::<Vec<_>>();
        output.buffered_bytes = output
            .buffered_bytes
            .saturating_sub(messages.iter().map(Vec::len).sum());
        Ok(AgentPollResult {
            messages,
            exit_code,
            protocol_failed: output.protocol_failed,
            message_too_large: output.message_too_large,
        })
    }

    pub fn close(&mut self, agent_id: &str) -> Result<i32, AgentProcessError> {
        let mut process = self
            .sessions
            .remove(agent_id)
            .ok_or(AgentProcessError::UnknownAgent)?;
        if let Some(status) = process
            .child
            .try_wait()
            .map_err(|_| AgentProcessError::PollFailed)?
        {
            return Ok(status.code().unwrap_or(1));
        }
        #[cfg(windows)]
        process.job.terminate();
        #[cfg(not(windows))]
        terminate_process_tree(&mut process.child, process.process_group_id);
        let status = process
            .child
            .wait()
            .map_err(|_| AgentProcessError::TerminateFailed)?;
        Ok(status.code().unwrap_or(1))
    }

    pub fn active_ids(&self) -> Vec<String> {
        let mut ids = self.sessions.keys().cloned().collect::<Vec<_>>();
        ids.sort_unstable();
        ids
    }

    fn reap_exited(&mut self) {
        let completed = self
            .sessions
            .iter_mut()
            .filter_map(|(id, process)| process.child.try_wait().ok().flatten().map(|_| id.clone()))
            .collect::<Vec<_>>();
        for id in completed {
            self.sessions.remove(&id);
        }
    }
}

#[cfg(windows)]
struct WindowsJob(windows_sys::Win32::Foundation::HANDLE);

#[cfg(windows)]
unsafe impl Send for WindowsJob {}

#[cfg(windows)]
impl WindowsJob {
    fn assign(child: &Child) -> Result<Self, ()> {
        use std::os::windows::io::AsRawHandle;
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
            && unsafe { AssignProcessToJobObject(handle, child.as_raw_handle() as _) } != 0;
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
fn terminate_process_tree(child: &mut Child, process_group_id: Option<u32>) {
    #[cfg(unix)]
    if let Some(process_group_id) = process_group_id {
        let process_group_id = i32::try_from(process_group_id).unwrap_or(i32::MAX);
        // SAFETY: a negative pid targets only the dedicated Agent process group.
        unsafe {
            libc::kill(-process_group_id, libc::SIGKILL);
        }
        return;
    }
    #[cfg(not(unix))]
    let _ = process_group_id;
    let _ = child.kill();
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AgentProcessError {
    InvalidLaunch,
    CapacityExceeded,
    StartFailed,
    UnknownAgent,
    InvalidMessage,
    WriteFailed,
    PollFailed,
    TerminateFailed,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn revocation_prevents_next_effect() {
        let mut host = AgentHost::default();
        host.grant(
            "session".into(),
            CapabilityGrant::new("workspace", 4, ["workspace.read".into()]),
        );
        assert!(
            host.authorize("session", "workspace", 4, "workspace.read")
                .is_ok()
        );
        host.revoke("session");
        assert_eq!(
            host.authorize("session", "workspace", 4, "workspace.read"),
            Err(AuthorizationError::Revoked)
        );
    }

    #[test]
    fn session_resume_and_permission_are_ordered_and_exactly_once() {
        let mut host = AgentHost::default();
        host.start_session("session".into(), 2);
        host.append_event("session", "started").unwrap();
        host.append_event("session", "tool.proposed").unwrap();
        host.request_permission("session", "permission-1".into())
            .unwrap();
        host.resolve_permission("session", "permission-1", PermissionDecision::AllowOnce)
            .unwrap();
        assert_eq!(host.resume_events("session", 1).unwrap().len(), 1);
        assert_eq!(
            host.resolve_permission("session", "permission-1", PermissionDecision::Deny),
            Err(SessionError::PermissionAlreadyResolved)
        );
    }

    #[cfg(unix)]
    #[test]
    fn supervised_agent_process_uses_bounded_json_line_transport() {
        let mut registry = SupervisedAgentRegistry::new(2, 4096, 1024);
        registry
            .start(AgentProcessLaunch {
                agent_id: "fixture".into(),
                executable: PathBuf::from("/bin/sh"),
                arguments: vec![
                    "-c".into(),
                    "IFS= read -r line; printf '%s\\n' \"$line\"".into(),
                ],
                working_directory: std::env::current_dir().unwrap(),
            })
            .unwrap();
        registry.send("fixture", br#"{"jsonrpc":"2.0"}"#).unwrap();
        let deadline = std::time::Instant::now() + std::time::Duration::from_secs(3);
        let mut messages = Vec::new();
        while std::time::Instant::now() < deadline {
            let poll = registry.poll("fixture", 8).unwrap();
            messages.extend(poll.messages);
            if !messages.is_empty() {
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        assert_eq!(messages, vec![br#"{"jsonrpc":"2.0"}"#.to_vec()]);
    }
}
