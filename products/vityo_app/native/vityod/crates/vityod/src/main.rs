use std::collections::HashSet;
use std::env;
use std::io::{Read, Write};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};

use serde_json::{Value, json};
use vityod_agent_host::{AcpError, AgentProcessLaunch, CapabilityGrant, PermissionDecision};
use vityod_kernel::{
    DurableDocumentChange, DurableFsTransactionBinding, DurableRenameDocument, DurableStateError,
    DurableStateStore,
};
use vityod_protocol::{
    ControlEnvelope, FRAME_HEADER_BYTES, FrameHeader, FrameKind, PROTOCOL_VERSION,
    SUPPORTED_CAPABILITIES, is_known_method,
};
use vityod_runtime::{ByteProcessLaunch, PtyLaunch, ServiceRuntime, TaskLaunch};
use vityod_workspace::{
    FileEntry, FileEventKind, FileKind, FileServiceError, WorkspaceFileService,
};

struct DaemonState {
    runtime: ServiceRuntime,
    durable: DurableStateStore,
    files: WorkspaceFileService,
}

static NEXT_WORKSPACE_TRANSACTION_ID: AtomicU64 = AtomicU64::new(1);

fn main() {
    let mut arguments = env::args().skip(1);
    match arguments.next().as_deref() {
        Some("--serve") => {
            let mut endpoint = None;
            let mut state_directory = None;
            let mut event_capacity = 4096_usize;
            while let Some(flag) = arguments.next() {
                let value = arguments.next();
                match flag.as_str() {
                    "--endpoint" => endpoint = value,
                    "--state-dir" => state_directory = value,
                    "--event-capacity" => {
                        event_capacity = value
                            .and_then(|value| value.parse::<usize>().ok())
                            .filter(|value| (8..=4096).contains(value))
                            .unwrap_or_else(|| {
                                eprintln!("event capacity must be between 8 and 4096");
                                std::process::exit(2);
                            });
                    }
                    _ => {
                        eprintln!("unsupported vityod service argument");
                        std::process::exit(2);
                    }
                }
            }
            if endpoint.is_none() {
                eprintln!(
                    "usage: vityod --serve --endpoint <private-local-endpoint> [--state-dir <private-state-directory>] [--event-capacity <8..4096>]"
                );
                std::process::exit(2);
            }
            if let Err(error) = serve(
                endpoint.as_deref().expect("checked endpoint"),
                state_directory.as_deref(),
                event_capacity,
            ) {
                eprintln!("vityod service failed: {error}");
                std::process::exit(1);
            }
        }
        Some("--health") | None => print_health(),
        Some(_) => {
            eprintln!("unsupported vityod argument");
            std::process::exit(2);
        }
    }
}

fn print_health() {
    let health = ServiceRuntime::default().health();
    let output = json!({
        "component": "vityod",
        "status": "ready",
        "protocolVersion": health.protocol_version,
        "workspaceRevision": health.workspace_revision,
    });
    println!("{output}");
}

#[cfg(unix)]
fn serve(
    endpoint: &str,
    state_directory: Option<&str>,
    event_capacity: usize,
) -> Result<(), String> {
    use std::fs::{self, File, OpenOptions};
    use std::io::ErrorKind;
    use std::os::unix::fs::{MetadataExt, PermissionsExt};
    use std::os::unix::net::{UnixListener, UnixStream};
    use std::path::{Path, PathBuf};

    struct EndpointGuard {
        endpoint: PathBuf,
        lock_path: PathBuf,
        _lock: File,
    }

    impl Drop for EndpointGuard {
        fn drop(&mut self) {
            let _ = fs::remove_file(&self.endpoint);
            let _ = fs::remove_file(&self.lock_path);
        }
    }

    let endpoint = Path::new(endpoint);
    if endpoint.as_os_str().is_empty() || endpoint.parent().is_none() {
        return Err("endpoint must be an explicit private path".into());
    }
    let endpoint_parent = endpoint.parent().expect("validated endpoint parent");
    fs::create_dir_all(endpoint_parent).map_err(|error| error.to_string())?;
    let parent_metadata =
        fs::symlink_metadata(endpoint_parent).map_err(|error| error.to_string())?;
    if !parent_metadata.is_dir() || parent_metadata.uid() != unsafe { libc::geteuid() } {
        return Err("endpoint parent must be an owner-controlled directory".into());
    }
    fs::set_permissions(endpoint_parent, fs::Permissions::from_mode(0o700))
        .map_err(|error| error.to_string())?;
    let lock_path = PathBuf::from(format!("{}.lock", endpoint.display()));
    let create_lock = || {
        let mut lock = OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&lock_path)?;
        lock.write_all(std::process::id().to_string().as_bytes())?;
        lock.flush()?;
        fs::set_permissions(&lock_path, fs::Permissions::from_mode(0o600))?;
        Ok::<File, std::io::Error>(lock)
    };
    let lock = match create_lock() {
        Ok(lock) => lock,
        Err(error) if error.kind() == ErrorKind::AlreadyExists => {
            if UnixStream::connect(endpoint).is_ok() {
                return Err("a healthy vityod instance already owns the endpoint".into());
            }
            let owner_pid = fs::read_to_string(&lock_path)
                .ok()
                .and_then(|value| value.parse::<u32>().ok());
            if owner_pid.is_some_and(process_is_alive) {
                return Err("a live vityod owner has not published a healthy endpoint".into());
            }
            fs::remove_file(&lock_path).map_err(|error| error.to_string())?;
            if endpoint.exists() {
                fs::remove_file(endpoint).map_err(|error| error.to_string())?;
            }
            create_lock().map_err(|error| error.to_string())?
        }
        Err(error) => return Err(error.to_string()),
    };
    if endpoint.exists() {
        fs::remove_file(endpoint).map_err(|error| error.to_string())?;
    }
    let listener = UnixListener::bind(endpoint).map_err(|error| error.to_string())?;
    fs::set_permissions(endpoint, fs::Permissions::from_mode(0o600))
        .map_err(|error| error.to_string())?;
    let _guard = EndpointGuard {
        endpoint: endpoint.to_path_buf(),
        lock_path,
        _lock: lock,
    };
    let state_path = state_directory
        .map(PathBuf::from)
        .unwrap_or_else(|| endpoint_parent.to_path_buf())
        .join("state.sqlite3");
    let durable = DurableStateStore::open(&state_path, event_capacity)
        .map_err(|error| format!("durable state unavailable: {error:?}"))?;
    fs::set_permissions(&state_path, fs::Permissions::from_mode(0o600))
        .map_err(|error| error.to_string())?;
    let runtime = Arc::new(Mutex::new(recover_daemon_state(durable)?));
    for connection in listener.incoming() {
        match connection {
            Ok(mut stream) => {
                let runtime = Arc::clone(&runtime);
                std::thread::spawn(move || {
                    if let Err(error) = handle_unix_connection(&mut stream, &runtime) {
                        eprintln!("vityod rejected connection: {error}");
                    }
                });
            }
            Err(error) => return Err(error.to_string()),
        }
    }
    Ok(())
}

#[cfg(unix)]
fn handle_unix_connection(
    stream: &mut std::os::unix::net::UnixStream,
    runtime: &Arc<Mutex<DaemonState>>,
) -> Result<(), String> {
    if !peer_identity_matches(stream)? {
        return Err("peer identity does not match the daemon owner".into());
    }
    handle_connection(stream, runtime)
}

fn handle_connection<Connection: Read + Write>(
    stream: &mut Connection,
    runtime: &Arc<Mutex<DaemonState>>,
) -> Result<(), String> {
    let mut negotiated = false;
    let mut cancelled = HashSet::<String>::new();
    loop {
        let mut header_bytes = [0_u8; FRAME_HEADER_BYTES];
        match stream.read_exact(&mut header_bytes) {
            Ok(()) => {}
            Err(error) if error.kind() == std::io::ErrorKind::UnexpectedEof => return Ok(()),
            Err(error) => return Err(error.to_string()),
        }
        let header = FrameHeader::decode(&header_bytes).map_err(|error| format!("{error:?}"))?;
        let mut payload = vec![0_u8; header.payload_length as usize];
        stream
            .read_exact(&mut payload)
            .map_err(|error| error.to_string())?;
        if header.kind == FrameKind::Pty {
            let mut state = runtime
                .lock()
                .map_err(|_| "service runtime lock is poisoned".to_string())?;
            state
                .runtime
                .ptys
                .write(header.stream_id, &payload)
                .map_err(|error| format!("PTY input rejected: {error:?}"))?;
            continue;
        }
        if header.kind == FrameKind::Credit {
            if payload.len() != 4 {
                return Err("credit payload must be one unsigned 32-bit value".into());
            }
            let credit = u32::from_be_bytes(payload.try_into().expect("checked credit payload"));
            let chunk = {
                let mut state = runtime
                    .lock()
                    .map_err(|_| "service runtime lock is poisoned".to_string())?;
                state
                    .runtime
                    .ptys
                    .drain(header.stream_id, credit as usize)
                    .map_err(|error| format!("PTY credit rejected: {error:?}"))?
            };
            let mut flags = 0;
            if chunk.truncated {
                flags |= 1;
            }
            let mut output_payload = chunk.payload;
            if chunk.closed {
                flags |= 2;
                if let Some(exit_code) = chunk.exit_code {
                    flags |= 4;
                    let mut framed = Vec::with_capacity(output_payload.len() + 4);
                    framed.extend_from_slice(&exit_code.to_be_bytes());
                    framed.extend_from_slice(&output_payload);
                    output_payload = framed;
                }
            }
            let output_header = FrameHeader {
                version: PROTOCOL_VERSION,
                kind: FrameKind::Pty,
                flags,
                stream_id: chunk.stream_id,
                sequence: chunk.sequence,
                payload_length: output_payload.len() as u32,
            };
            stream
                .write_all(
                    &output_header
                        .encode()
                        .map_err(|error| format!("{error:?}"))?,
                )
                .and_then(|()| stream.write_all(&output_payload))
                .and_then(|()| stream.flush())
                .map_err(|error| error.to_string())?;
            continue;
        }
        let request = ControlEnvelope::decode(&payload).map_err(|error| format!("{error:?}"))?;
        let response = if !negotiated && request.method != "handshake.negotiate" {
            error_response(request, "handshake_required", false, 0)
        } else if request.deadline_unix_millis < unix_time_millis() {
            error_response(request, "deadline_exceeded", false, 0)
        } else if request.method == "handshake.negotiate" {
            let unsupported = required_capabilities(&request)
                .into_iter()
                .filter(|capability| !SUPPORTED_CAPABILITIES.contains(&capability.as_str()))
                .collect::<Vec<_>>();
            if unsupported.is_empty() {
                negotiated = true;
                handshake_response(request)
            } else {
                error_response(request, "required_capability_unsupported", false, 0)
            }
        } else if contains_sensitive_input(&request.params) {
            error_response(request, "credential_passthrough_denied", false, 0)
        } else if request.method == "cancellation.cancel" {
            if let Some(identifier) = request.params.get("cancellationId").and_then(Value::as_str) {
                cancelled.insert(identifier.to_owned());
            }
            success_response(request, json!({"cancelled": true}), 0)
        } else if request
            .cancellation_id
            .as_ref()
            .is_some_and(|identifier| cancelled.contains(identifier))
        {
            error_response(request, "cancelled", false, 0)
        } else {
            let mut runtime = runtime
                .lock()
                .map_err(|_| "service runtime lock is poisoned".to_string())?;
            response_for(&mut runtime, request)
        };
        let response_payload = response.encode().map_err(|error| format!("{error:?}"))?;
        let response_header = FrameHeader {
            version: PROTOCOL_VERSION,
            kind: FrameKind::Control,
            flags: 0,
            stream_id: header.stream_id,
            sequence: header.sequence,
            payload_length: response_payload.len() as u32,
        };
        stream
            .write_all(
                &response_header
                    .encode()
                    .map_err(|error| format!("{error:?}"))?,
            )
            .and_then(|()| stream.write_all(&response_payload))
            .and_then(|()| stream.flush())
            .map_err(|error| error.to_string())?;
    }
}

#[cfg(all(unix, target_os = "macos"))]
fn peer_identity_matches(stream: &std::os::unix::net::UnixStream) -> Result<bool, String> {
    use std::os::fd::AsRawFd;

    let mut effective_user = 0;
    let mut effective_group = 0;
    let result = unsafe {
        libc::getpeereid(
            stream.as_raw_fd(),
            &mut effective_user,
            &mut effective_group,
        )
    };
    if result != 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    Ok(peer_user_is_owner(
        unsafe { libc::geteuid() },
        effective_user,
    ))
}

#[cfg(all(unix, target_os = "linux"))]
fn peer_identity_matches(stream: &std::os::unix::net::UnixStream) -> Result<bool, String> {
    use std::mem::{size_of, zeroed};
    use std::os::fd::AsRawFd;

    let mut credentials: libc::ucred = unsafe { zeroed() };
    let mut length = size_of::<libc::ucred>() as libc::socklen_t;
    let result = unsafe {
        libc::getsockopt(
            stream.as_raw_fd(),
            libc::SOL_SOCKET,
            libc::SO_PEERCRED,
            &mut credentials as *mut libc::ucred as *mut libc::c_void,
            &mut length,
        )
    };
    if result != 0 {
        return Err(std::io::Error::last_os_error().to_string());
    }
    Ok(peer_user_is_owner(
        unsafe { libc::geteuid() },
        credentials.uid,
    ))
}

#[cfg(unix)]
fn peer_user_is_owner(owner: libc::uid_t, peer: libc::uid_t) -> bool {
    owner == peer
}

#[cfg(all(unix, not(any(target_os = "macos", target_os = "linux"))))]
fn peer_identity_matches(_stream: &std::os::unix::net::UnixStream) -> Result<bool, String> {
    Err("peer credential validation is unavailable on this Unix target".into())
}

#[cfg(windows)]
fn serve(
    endpoint: &str,
    state_directory: Option<&str>,
    event_capacity: usize,
) -> Result<(), String> {
    use std::fs::File;
    use std::os::windows::io::FromRawHandle;
    use std::path::PathBuf;
    use windows_sys::Win32::Foundation::{
        ERROR_PIPE_CONNECTED, GetLastError, INVALID_HANDLE_VALUE, LocalFree,
    };
    use windows_sys::Win32::Security::Authorization::{
        ConvertStringSecurityDescriptorToSecurityDescriptorW, SDDL_REVISION_1,
    };
    use windows_sys::Win32::Security::{PSECURITY_DESCRIPTOR, SECURITY_ATTRIBUTES};
    use windows_sys::Win32::Storage::FileSystem::{
        FILE_FLAG_FIRST_PIPE_INSTANCE, PIPE_ACCESS_DUPLEX,
    };
    use windows_sys::Win32::System::Pipes::{
        ConnectNamedPipe, CreateNamedPipeW, PIPE_READMODE_BYTE, PIPE_TYPE_BYTE,
        PIPE_UNLIMITED_INSTANCES, PIPE_WAIT,
    };

    if !endpoint.starts_with(r"\\.\pipe\vityo-") || endpoint.len() > 256 || endpoint.contains('/') {
        return Err("named pipe must use the private Vityo namespace".into());
    }
    let state_directory = state_directory
        .map(PathBuf::from)
        .filter(|path| path.is_absolute())
        .ok_or_else(|| "Windows vityod requires an explicit state directory".to_string())?;
    std::fs::create_dir_all(&state_directory).map_err(|error| error.to_string())?;
    let state_path = state_directory.join("state.sqlite3");
    let durable = DurableStateStore::open(&state_path, event_capacity)
        .map_err(|error| format!("durable state unavailable: {error:?}"))?;
    let runtime = Arc::new(Mutex::new(recover_daemon_state(durable)?));

    let pipe_name = endpoint
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect::<Vec<_>>();
    let descriptor_text = "D:P(A;;GA;;;OW)"
        .encode_utf16()
        .chain(std::iter::once(0))
        .collect::<Vec<_>>();
    let mut descriptor: PSECURITY_DESCRIPTOR = std::ptr::null_mut();
    let converted = unsafe {
        ConvertStringSecurityDescriptorToSecurityDescriptorW(
            descriptor_text.as_ptr(),
            SDDL_REVISION_1,
            &mut descriptor,
            std::ptr::null_mut(),
        )
    };
    if converted == 0 || descriptor.is_null() {
        return Err("failed to create the owner-only pipe descriptor".into());
    }
    struct DescriptorGuard(PSECURITY_DESCRIPTOR);
    impl Drop for DescriptorGuard {
        fn drop(&mut self) {
            unsafe {
                LocalFree(self.0.cast());
            }
        }
    }
    let _descriptor_guard = DescriptorGuard(descriptor);
    let security = SECURITY_ATTRIBUTES {
        nLength: std::mem::size_of::<SECURITY_ATTRIBUTES>() as u32,
        lpSecurityDescriptor: descriptor,
        bInheritHandle: 0,
    };
    let mut first_instance = true;
    loop {
        let open_mode = PIPE_ACCESS_DUPLEX
            | if first_instance {
                FILE_FLAG_FIRST_PIPE_INSTANCE
            } else {
                0
            };
        let handle = unsafe {
            CreateNamedPipeW(
                pipe_name.as_ptr(),
                open_mode,
                PIPE_TYPE_BYTE | PIPE_READMODE_BYTE | PIPE_WAIT,
                PIPE_UNLIMITED_INSTANCES,
                1024 * 1024,
                1024 * 1024,
                0,
                &security,
            )
        };
        if handle == INVALID_HANDLE_VALUE {
            return Err("another vityod instance owns the named pipe".into());
        }
        first_instance = false;
        let connected = unsafe { ConnectNamedPipe(handle, std::ptr::null_mut()) };
        if connected == 0 && unsafe { GetLastError() } != ERROR_PIPE_CONNECTED {
            unsafe {
                windows_sys::Win32::Foundation::CloseHandle(handle);
            }
            continue;
        }
        let peer_matches = match windows_peer_identity_matches(handle) {
            Ok(matches) => matches,
            Err(error) => {
                unsafe {
                    windows_sys::Win32::Foundation::CloseHandle(handle);
                }
                eprintln!("vityod rejected named-pipe peer: {error}");
                continue;
            }
        };
        if !peer_matches {
            unsafe {
                windows_sys::Win32::Foundation::CloseHandle(handle);
            }
            continue;
        }
        let runtime = Arc::clone(&runtime);
        let raw_handle = handle as usize;
        std::thread::spawn(move || {
            let mut pipe = unsafe { File::from_raw_handle(raw_handle as _) };
            if let Err(error) = handle_connection(&mut pipe, &runtime) {
                eprintln!("vityod rejected connection: {error}");
            }
        });
    }
}

#[cfg(windows)]
fn windows_peer_identity_matches(
    pipe: windows_sys::Win32::Foundation::HANDLE,
) -> Result<bool, String> {
    use windows_sys::Win32::Foundation::{CloseHandle, HANDLE};
    use windows_sys::Win32::Security::{EqualSid, TOKEN_USER};
    use windows_sys::Win32::System::Pipes::GetNamedPipeClientProcessId;
    use windows_sys::Win32::System::Threading::{
        GetCurrentProcess, OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION,
    };

    struct OwnedHandle(HANDLE);

    impl Drop for OwnedHandle {
        fn drop(&mut self) {
            unsafe {
                CloseHandle(self.0);
            }
        }
    }

    fn token_user(process: HANDLE) -> Result<(OwnedHandle, Vec<u8>), String> {
        use windows_sys::Win32::Security::{GetTokenInformation, TOKEN_QUERY, TokenUser};
        use windows_sys::Win32::System::Threading::OpenProcessToken;
        let mut peer_token_handle = std::ptr::null_mut();
        if unsafe { OpenProcessToken(process, TOKEN_QUERY, &mut peer_token_handle) } == 0 {
            return Err("failed to query the pipe peer token".into());
        }
        let mut length = 0;
        unsafe {
            GetTokenInformation(
                peer_token_handle,
                TokenUser,
                std::ptr::null_mut(),
                0,
                &mut length,
            );
        }
        if length == 0 {
            unsafe {
                CloseHandle(peer_token_handle);
            }
            return Err("pipe peer token identity is unavailable".into());
        }
        let mut buffer = vec![0_u8; length as usize];
        if unsafe {
            GetTokenInformation(
                peer_token_handle,
                TokenUser,
                buffer.as_mut_ptr().cast(),
                length,
                &mut length,
            )
        } == 0
        {
            unsafe {
                CloseHandle(peer_token_handle);
            }
            return Err("failed to read the pipe peer identity".into());
        }
        Ok((OwnedHandle(peer_token_handle), buffer))
    }

    let mut client_process_id = 0;
    if unsafe { GetNamedPipeClientProcessId(pipe, &mut client_process_id) } == 0 {
        return Err("named pipe peer process identity is unavailable".into());
    }
    let client_process =
        unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, client_process_id) };
    if client_process.is_null() {
        return Err("named pipe peer process cannot be inspected".into());
    }
    let client_process = OwnedHandle(client_process);
    let (_client_token, client_user) = token_user(client_process.0)?;
    let (_owner_token, owner_user) = token_user(unsafe { GetCurrentProcess() })?;
    let client_sid = unsafe { (*(client_user.as_ptr() as *const TOKEN_USER)).User.Sid };
    let owner_sid = unsafe { (*(owner_user.as_ptr() as *const TOKEN_USER)).User.Sid };
    let matches = unsafe { EqualSid(client_sid, owner_sid) } != 0;
    Ok(matches)
}

#[cfg(not(any(unix, windows)))]
fn serve(
    _endpoint: &str,
    _state_directory: Option<&str>,
    _event_capacity: usize,
) -> Result<(), String> {
    Err("this build does not provide its platform local endpoint yet".into())
}

fn recover_daemon_state(durable: DurableStateStore) -> Result<DaemonState, String> {
    let mut runtime = ServiceRuntime::default();
    for session in durable
        .list_agent_sessions()
        .map_err(|error| format!("agent session recovery failed: {error:?}"))?
    {
        runtime
            .agent_host
            .start_session(session.session_id.clone(), 4096);
        runtime.agent_host.grant(
            session.session_id.clone(),
            CapabilityGrant::new(
                session.workspace_id,
                session.workspace_revision,
                session.capabilities,
            ),
        );
        if session.revoked {
            runtime.agent_host.revoke(&session.session_id);
        }
    }
    Ok(DaemonState {
        runtime,
        durable,
        files: WorkspaceFileService::default(),
    })
}

fn response_for(state: &mut DaemonState, request: ControlEnvelope) -> ControlEnvelope {
    let health = state.runtime.health();
    let durable_workspace_id = request
        .workspace_id
        .as_deref()
        .unwrap_or("default")
        .to_owned();
    let workspace_revision = state
        .durable
        .workspace_revision(&durable_workspace_id)
        .unwrap_or(health.workspace_revision);
    let durable_receipt_key = receipt_key(&request);
    match method_uses_durable_receipt(&request.method)
        .then(|| state.durable.receipt(&durable_receipt_key))
        .transpose()
    {
        Ok(Some(Some(receipt))) => {
            return match ControlEnvelope::decode(&receipt) {
                Ok(mut response) => {
                    response.request_id = request.request_id;
                    response.deadline_unix_millis = request.deadline_unix_millis;
                    response.cancellation_id = request.cancellation_id;
                    response
                }
                Err(_) => error_response(
                    request,
                    "idempotency_receipt_invalid",
                    false,
                    workspace_revision,
                ),
            };
        }
        Ok(Some(None)) | Ok(None) => {}
        Err(_) => {
            return error_response(
                request,
                "idempotency_store_unavailable",
                true,
                workspace_revision,
            );
        }
    }
    let params = match request.method.as_str() {
        "event.resume" => {
            let after_cursor = request
                .params
                .get("afterCursor")
                .and_then(Value::as_u64)
                .unwrap_or(0);
            match state.durable.resume_events_after(after_cursor) {
                Ok(events) => {
                    let event_cursor = events.last().map_or(after_cursor, |event| event.cursor);
                    let event_digest = ordered_event_digest(&events);
                    json!({
                        "eventCursor": event_cursor,
                        "eventDigest": event_digest,
                        "events": events.into_iter().map(|event| json!({
                            "cursor": event.cursor,
                            "kind": event.kind,
                            "workspaceRevision": event.workspace_revision,
                            "payloadBase64": base64_encode(&event.payload),
                        })).collect::<Vec<_>>(),
                        "workspaceRevision": workspace_revision,
                        "capabilities": ["event.resume", "workspace.snapshot"],
                        "activeTerminalIds": state.runtime.ptys.active_ids(),
                        "activeTaskIds": state.runtime.tasks.active_ids(),
                        "activeAgentSessionIds": state.durable.list_agent_sessions()
                            .unwrap_or_default()
                            .into_iter()
                            .filter(|session| !session.revoked)
                            .map(|session| session.session_id)
                            .collect::<Vec<_>>(),
                        "dirtyBuffers": state.durable.list_dirty_buffers(&durable_workspace_id)
                            .unwrap_or_default()
                            .into_iter()
                            .map(|buffer| json!({
                                "documentId": buffer.document_id,
                                "revision": buffer.revision,
                                "contents": buffer.contents,
                            }))
                            .collect::<Vec<_>>(),
                    })
                }
                Err(DurableStateError::ResumeGap(gap)) => {
                    return error_response_with_context(
                        request,
                        "event_cursor_pruned",
                        true,
                        workspace_revision,
                        json!({
                            "oldestAvailableCursor": gap.oldest_available_cursor,
                            "resyncMode": "full_snapshot",
                            "gapReason": "event_cursor_pruned",
                        }),
                    );
                }
                Err(_) => {
                    return error_response(
                        request,
                        "durable_state_unavailable",
                        true,
                        workspace_revision,
                    );
                }
            }
        }
        "snapshot.get" => {
            let event_cursor = match state.durable.latest_event_cursor() {
                Ok(cursor) => cursor,
                Err(_) => {
                    return error_response(
                        request,
                        "durable_state_unavailable",
                        true,
                        workspace_revision,
                    );
                }
            };
            json!({
                "eventCursor": event_cursor,
                "eventDigest": ordered_event_digest(&[]),
                "events": [],
                "workspaceRevision": workspace_revision,
                "capabilities": ["event.resume", "workspace.snapshot"],
                "activeTerminalIds": state.runtime.ptys.active_ids(),
                "activeTaskIds": state.runtime.tasks.active_ids(),
                "activeAgentSessionIds": state.durable.list_agent_sessions()
                    .unwrap_or_default()
                    .into_iter()
                    .filter(|session| !session.revoked)
                    .map(|session| session.session_id)
                    .collect::<Vec<_>>(),
                "dirtyBuffers": state.durable.list_dirty_buffers(&durable_workspace_id)
                    .unwrap_or_default()
                    .into_iter()
                    .map(|buffer| json!({
                        "documentId": buffer.document_id,
                        "revision": buffer.revision,
                        "contents": buffer.contents,
                    }))
                    .collect::<Vec<_>>(),
                "resyncMode": "full_snapshot",
            })
        }
        "buffer.delta" => {
            let Some(document_id) = required_string_param(&request, "documentId") else {
                return error_response(request, "invalid_buffer_delta", false, workspace_revision);
            };
            let Some(base_revision) = request.params.get("baseRevision").and_then(Value::as_u64)
            else {
                return error_response(request, "invalid_buffer_delta", false, workspace_revision);
            };
            let Some(target_revision) =
                request.params.get("targetRevision").and_then(Value::as_u64)
            else {
                return error_response(request, "invalid_buffer_delta", false, workspace_revision);
            };
            let Some(start_offset) = request
                .params
                .get("startOffset")
                .and_then(Value::as_u64)
                .and_then(|value| usize::try_from(value).ok())
            else {
                return error_response(request, "invalid_buffer_delta", false, workspace_revision);
            };
            let Some(deleted_length) = request
                .params
                .get("deletedLength")
                .and_then(Value::as_u64)
                .and_then(|value| usize::try_from(value).ok())
            else {
                return error_response(request, "invalid_buffer_delta", false, workspace_revision);
            };
            let Some(inserted_text) = request.params.get("insertedText").and_then(Value::as_str)
            else {
                return error_response(request, "invalid_buffer_delta", false, workspace_revision);
            };
            match state.durable.apply_buffer_delta(
                &durable_workspace_id,
                &document_id,
                base_revision,
                target_revision,
                start_offset,
                deleted_length,
                inserted_text,
            ) {
                Ok(buffer) => json!({
                    "documentId": buffer.document_id,
                    "acknowledgedRevision": buffer.revision,
                }),
                Err(DurableStateError::BufferConflict { actual, .. }) => {
                    return error_response_with_context(
                        request,
                        "buffer_revision_conflict",
                        true,
                        workspace_revision,
                        json!({"actualRevision": actual}),
                    );
                }
                Err(DurableStateError::InvalidBufferDelta) => {
                    return error_response(
                        request,
                        "invalid_buffer_delta",
                        false,
                        workspace_revision,
                    );
                }
                Err(_) => {
                    return error_response(
                        request,
                        "durable_state_unavailable",
                        true,
                        workspace_revision,
                    );
                }
            }
        }
        "health.get" => json!({
            "status": "ready",
            "protocolVersion": health.protocol_version,
            "workspaceRevision": workspace_revision,
        }),
        "fs.scope.open" | "workspace.open" => {
            let scope_id = request
                .workspace_id
                .clone()
                .or_else(|| required_string_param(&request, "scopeId"));
            let root_path = required_string_param(&request, "rootPath");
            let (Some(scope_id), Some(root_path)) = (scope_id, root_path) else {
                return error_response(request, "invalid_file_scope", false, workspace_revision);
            };
            match state
                .files
                .open_scope(&scope_id, std::path::Path::new(&root_path))
            {
                Ok(()) => {
                    if request.method == "workspace.open"
                        && recover_pending_workspace_transactions(state, &scope_id).is_err()
                    {
                        let _ = state.files.close_scope(&scope_id);
                        return error_response(
                            request,
                            "workspace_recovery_failed",
                            true,
                            workspace_revision,
                        );
                    }
                    let scope_revision = if request.method == "workspace.open" {
                        state
                            .durable
                            .workspace_revision(&scope_id)
                            .unwrap_or(workspace_revision)
                    } else {
                        workspace_revision
                    };
                    json!({
                        "scopeId": scope_id,
                        "ready": true,
                        "workspaceRevision": scope_revision,
                    })
                }
                Err(error) => {
                    return file_error_response(request, error, workspace_revision);
                }
            }
        }
        "fs.scope.close" => {
            let Some(scope_id) = required_string_param(&request, "scopeId") else {
                return error_response(request, "invalid_file_scope", false, workspace_revision);
            };
            match state.files.close_scope(&scope_id) {
                Ok(()) => json!({"scopeId": scope_id, "closed": true}),
                Err(error) => {
                    return file_error_response(request, error, workspace_revision);
                }
            }
        }
        "fs.stat" => {
            let Some((scope_id, relative_path)) = file_target_params(&request) else {
                return error_response(request, "invalid_file_request", false, workspace_revision);
            };
            match state.files.stat(&scope_id, &relative_path) {
                Ok(entry) => json!({"entry": file_entry_json(entry)}),
                Err(error) => {
                    return file_error_response(request, error, workspace_revision);
                }
            }
        }
        "fs.read" => {
            let Some((scope_id, relative_path)) = file_target_params(&request) else {
                return error_response(request, "invalid_file_request", false, workspace_revision);
            };
            match state.files.read(&scope_id, &relative_path) {
                Ok(contents) => json!({
                    "relativePath": relative_path,
                    "contentsBase64": base64_encode(&contents),
                    "byteLength": contents.len(),
                }),
                Err(error) => {
                    return file_error_response(request, error, workspace_revision);
                }
            }
        }
        "fs.write" => {
            let Some((scope_id, relative_path)) = file_target_params(&request) else {
                return error_response(request, "invalid_file_request", false, workspace_revision);
            };
            let Some(encoded) =
                required_string_param_with_limit(&request, "contentsBase64", 768 * 1024)
            else {
                return error_response(request, "invalid_file_contents", false, workspace_revision);
            };
            let Ok(contents) = base64_decode(&encoded) else {
                return error_response(request, "invalid_file_contents", false, workspace_revision);
            };
            let create_parents = request
                .params
                .get("createParents")
                .and_then(Value::as_bool)
                .unwrap_or(true);
            let atomic = request
                .params
                .get("atomic")
                .and_then(Value::as_bool)
                .unwrap_or(true);
            match state
                .files
                .write(&scope_id, &relative_path, &contents, create_parents, atomic)
            {
                Ok(()) => json!({"written": true, "byteLength": contents.len()}),
                Err(error) => {
                    return file_error_response(request, error, workspace_revision);
                }
            }
        }
        "fs.createDirectory" => {
            let Some((scope_id, relative_path)) = file_target_params(&request) else {
                return error_response(request, "invalid_file_request", false, workspace_revision);
            };
            let recursive = request
                .params
                .get("recursive")
                .and_then(Value::as_bool)
                .unwrap_or(true);
            match state
                .files
                .create_directory(&scope_id, &relative_path, recursive)
            {
                Ok(()) => json!({"created": true}),
                Err(error) => {
                    return file_error_response(request, error, workspace_revision);
                }
            }
        }
        "fs.delete" => {
            let Some((scope_id, relative_path)) = file_target_params(&request) else {
                return error_response(request, "invalid_file_request", false, workspace_revision);
            };
            let recursive = request
                .params
                .get("recursive")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            match state.files.delete(&scope_id, &relative_path, recursive) {
                Ok(()) => json!({"deleted": true}),
                Err(error) => {
                    return file_error_response(request, error, workspace_revision);
                }
            }
        }
        "fs.copy" | "fs.move" => {
            let Some(scope_id) = required_string_param(&request, "scopeId") else {
                return error_response(request, "invalid_file_scope", false, workspace_revision);
            };
            let source = required_string_param(&request, "sourceRelativePath");
            let target = required_string_param(&request, "targetRelativePath");
            let (Some(source), Some(target)) = (source, target) else {
                return error_response(request, "invalid_file_request", false, workspace_revision);
            };
            let overwrite = request
                .params
                .get("overwrite")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            if request.method == "fs.copy" {
                match state.files.copy(&scope_id, &source, &target, overwrite) {
                    Ok(()) => json!({"completed": true}),
                    Err(error) => {
                        return file_error_response(request, error, workspace_revision);
                    }
                }
            } else {
                let source_contents = match state.files.read(&scope_id, &source) {
                    Ok(contents) => contents,
                    Err(FileServiceError::NotFile) => {
                        match state
                            .files
                            .move_entity(&scope_id, &source, &target, overwrite)
                        {
                            Ok(()) => {
                                return success_response(
                                    request,
                                    json!({"completed": true, "durableRevision": false}),
                                    workspace_revision,
                                );
                            }
                            Err(error) => {
                                return file_error_response(request, error, workspace_revision);
                            }
                        }
                    }
                    Err(error) => return file_error_response(request, error, workspace_revision),
                };
                if !overwrite && file_exists(&state.files, &scope_id, &target).unwrap_or(false) {
                    return file_error_response(
                        request,
                        FileServiceError::AlreadyExists,
                        workspace_revision,
                    );
                }
                if state
                    .durable
                    .import_document_if_missing(&scope_id, &source, &source_contents, Some("utf-8"))
                    .is_err()
                {
                    return error_response(
                        request,
                        "durable_state_unavailable",
                        true,
                        workspace_revision,
                    );
                }
                if let Ok(target_contents) = state.files.read(&scope_id, &target) {
                    if state
                        .durable
                        .import_document_if_missing(
                            &scope_id,
                            &target,
                            &target_contents,
                            Some("utf-8"),
                        )
                        .is_err()
                    {
                        return error_response(
                            request,
                            "durable_state_unavailable",
                            true,
                            workspace_revision,
                        );
                    }
                }
                let source_record = match state.durable.read_document(&scope_id, &source) {
                    Ok(Some(record)) => record,
                    _ => {
                        return error_response(
                            request,
                            "durable_state_unavailable",
                            true,
                            workspace_revision,
                        );
                    }
                };
                let target_revision = state
                    .durable
                    .read_document(&scope_id, &target)
                    .ok()
                    .flatten()
                    .map_or(0, |record| record.revision);
                let expected_workspace_revision = state
                    .durable
                    .workspace_revision(&scope_id)
                    .unwrap_or(workspace_revision);
                let payload =
                    match rename_recovery_payload(&state.files, &scope_id, &source, &target) {
                        Ok(payload) => payload,
                        Err(error) => {
                            return file_error_response(request, error, workspace_revision);
                        }
                    };
                let transaction_id = next_workspace_transaction_id();
                if let Err(error) =
                    stage_workspace_intent(&state.files, &scope_id, &transaction_id, 0)
                {
                    return file_error_response(request, error, workspace_revision);
                }
                let recovery_payload = serde_json::to_vec(&payload)
                    .expect("workspace recovery payload is JSON-compatible");
                if state
                    .durable
                    .prepare_workspace_fs_transaction(
                        &transaction_id,
                        &scope_id,
                        expected_workspace_revision,
                        &recovery_payload,
                    )
                    .is_err()
                {
                    let _ = cleanup_workspace_transaction(&state.files, &scope_id, &transaction_id);
                    return error_response(
                        request,
                        "durable_state_unavailable",
                        true,
                        workspace_revision,
                    );
                }
                if let Err(error) =
                    apply_workspace_transaction(&state.files, &scope_id, &transaction_id, &payload)
                {
                    let _ = rollback_workspace_transaction(
                        &state.files,
                        &scope_id,
                        &transaction_id,
                        &payload,
                    );
                    let _ = state
                        .durable
                        .discard_workspace_fs_transaction(&transaction_id, &scope_id);
                    return file_error_response(request, error, workspace_revision);
                }
                let receipt_request = request.clone();
                let build_response = |receipt: &vityod_kernel::DurableCommitReceipt| {
                    Ok(success_response(
                        receipt_request.clone(),
                        json!({
                            "completed": true,
                            "workspaceRevision": receipt.workspace_revision,
                            "documentRevisions": receipt.document_revisions,
                            "eventCursor": receipt.event_cursor,
                        }),
                        receipt.workspace_revision,
                    )
                    .encode()
                    .expect("workspace rename response is protocol-valid"))
                };
                let rename = state
                    .durable
                    .rename_document_with_receipt_and_fs_transaction(
                        &scope_id,
                        DurableRenameDocument {
                            expected_workspace_revision,
                            source_relative_path: &source,
                            expected_source_revision: source_record.revision,
                            target_relative_path: &target,
                            expected_target_revision: target_revision,
                        },
                        DurableFsTransactionBinding {
                            idempotency_key: &durable_receipt_key,
                            transaction_id: &transaction_id,
                        },
                        &build_response,
                    );
                let journal_pending = state
                    .durable
                    .pending_workspace_fs_transactions(&scope_id)
                    .map(|pending| {
                        pending
                            .iter()
                            .any(|pending| pending.transaction_id == transaction_id)
                    })
                    .unwrap_or(true);
                if rename.is_err() && journal_pending {
                    let _ = rollback_workspace_transaction(
                        &state.files,
                        &scope_id,
                        &transaction_id,
                        &payload,
                    );
                    let _ = state
                        .durable
                        .discard_workspace_fs_transaction(&transaction_id, &scope_id);
                } else {
                    let _ = cleanup_workspace_transaction(&state.files, &scope_id, &transaction_id);
                }
                match rename {
                    Ok((receipt, _)) => json!({
                        "completed": true,
                        "workspaceRevision": receipt.workspace_revision,
                        "documentRevisions": receipt.document_revisions,
                        "eventCursor": receipt.event_cursor,
                    }),
                    Err(DurableStateError::WorkspaceConflict { .. }) => {
                        return error_response(
                            request,
                            "workspace_revision_conflict",
                            true,
                            workspace_revision,
                        );
                    }
                    Err(DurableStateError::DocumentConflict { .. }) => {
                        return error_response(
                            request,
                            "document_revision_conflict",
                            true,
                            workspace_revision,
                        );
                    }
                    Err(_) => {
                        return error_response(
                            request,
                            "transaction_failed",
                            true,
                            workspace_revision,
                        );
                    }
                }
            }
        }
        "fs.list" | "workspace.files.list" => {
            let scope_id = request
                .workspace_id
                .clone()
                .or_else(|| required_string_param(&request, "scopeId"));
            let Some(scope_id) = scope_id else {
                return error_response(request, "invalid_file_scope", false, workspace_revision);
            };
            let relative_path = request
                .params
                .get("relativePath")
                .and_then(Value::as_str)
                .unwrap_or(".");
            let recursive = request
                .params
                .get("recursive")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            let cursor = request
                .params
                .get("cursor")
                .and_then(Value::as_u64)
                .and_then(|value| usize::try_from(value).ok())
                .unwrap_or(0);
            let limit = request
                .params
                .get("limit")
                .and_then(Value::as_u64)
                .and_then(|value| usize::try_from(value).ok())
                .unwrap_or(500)
                .clamp(1, 1_000);
            match state.files.list(&scope_id, relative_path, recursive) {
                Ok(entries) => {
                    let total = entries.len();
                    let page = entries
                        .into_iter()
                        .skip(cursor)
                        .take(limit)
                        .map(file_entry_json)
                        .collect::<Vec<_>>();
                    let next_cursor = (cursor + page.len() < total).then_some(cursor + page.len());
                    json!({"entries": page, "nextCursor": next_cursor, "overflowed": false})
                }
                Err(error) => {
                    return file_error_response(request, error, workspace_revision);
                }
            }
        }
        "fs.isExecutable" => {
            let Some((scope_id, relative_path)) = file_target_params(&request) else {
                return error_response(request, "invalid_file_request", false, workspace_revision);
            };
            match state.files.is_executable(&scope_id, &relative_path) {
                Ok(executable) => json!({"executable": executable}),
                Err(error) => {
                    return file_error_response(request, error, workspace_revision);
                }
            }
        }
        "fs.setExecutable" => {
            let Some((scope_id, relative_path)) = file_target_params(&request) else {
                return error_response(request, "invalid_file_request", false, workspace_revision);
            };
            let executable = request
                .params
                .get("executable")
                .and_then(Value::as_bool)
                .unwrap_or(true);
            match state
                .files
                .set_executable(&scope_id, &relative_path, executable)
            {
                Ok(()) => json!({"updated": true}),
                Err(error) => {
                    return file_error_response(request, error, workspace_revision);
                }
            }
        }
        "fs.watch.start" | "workspace.watch" => {
            let scope_id = request
                .workspace_id
                .clone()
                .or_else(|| required_string_param(&request, "scopeId"));
            let watch_id = required_string_param(&request, "watchId");
            let (Some(scope_id), Some(watch_id)) = (scope_id, watch_id) else {
                return error_response(request, "invalid_watch_request", false, workspace_revision);
            };
            let relative_path = request
                .params
                .get("relativePath")
                .and_then(Value::as_str)
                .unwrap_or(".");
            let recursive = request
                .params
                .get("recursive")
                .and_then(Value::as_bool)
                .unwrap_or(false);
            match state
                .files
                .start_watch(&watch_id, &scope_id, relative_path, recursive)
            {
                Ok(()) => json!({"watchId": watch_id, "started": true}),
                Err(error) => {
                    return file_error_response(request, error, workspace_revision);
                }
            }
        }
        "fs.watch.poll" => {
            let Some(watch_id) = required_string_param(&request, "watchId") else {
                return error_response(request, "invalid_watch_request", false, workspace_revision);
            };
            match state.files.poll_watch(&watch_id) {
                Ok(poll) => json!({
                    "events": poll.events.into_iter().map(|event| json!({
                        "kind": match event.kind {
                            FileEventKind::Created => "created",
                            FileEventKind::Modified => "modified",
                            FileEventKind::Deleted => "deleted",
                        },
                        "relativePath": event.relative_path,
                        "isDirectory": event.is_directory,
                    })).collect::<Vec<_>>(),
                    "overflowed": poll.overflowed,
                }),
                Err(error) => {
                    return file_error_response(request, error, workspace_revision);
                }
            }
        }
        "fs.watch.stop" => {
            let Some(watch_id) = required_string_param(&request, "watchId") else {
                return error_response(request, "invalid_watch_request", false, workspace_revision);
            };
            match state.files.stop_watch(&watch_id) {
                Ok(()) => json!({"watchId": watch_id, "stopped": true}),
                Err(error) => {
                    return file_error_response(request, error, workspace_revision);
                }
            }
        }
        "workspace.read" => {
            let Some(relative_path) = required_string_param(&request, "relativePath") else {
                return error_response(
                    request,
                    "invalid_workspace_path",
                    false,
                    workspace_revision,
                );
            };
            if vityod_workspace::validate_relative_path(&relative_path).is_err() {
                return error_response(request, "workspace_root_escape", false, workspace_revision);
            }
            let workspace_scope = request
                .workspace_id
                .as_ref()
                .filter(|scope_id| state.files.has_scope(scope_id))
                .cloned();
            let mut durable_document = match state
                .durable
                .read_document(&durable_workspace_id, &relative_path)
            {
                Ok(document) => document,
                Err(_) => {
                    return error_response(
                        request,
                        "durable_state_unavailable",
                        true,
                        workspace_revision,
                    );
                }
            };
            if durable_document.is_none()
                && let Some(scope_id) = workspace_scope
            {
                let contents = match state.files.read(&scope_id, &relative_path) {
                    Ok(contents) => contents,
                    Err(FileServiceError::NotFound) => {
                        return error_response(
                            request,
                            "document_missing",
                            false,
                            workspace_revision,
                        );
                    }
                    Err(error) => {
                        return file_error_response(request, error, workspace_revision);
                    }
                };
                if state
                    .durable
                    .import_document_if_missing(
                        &durable_workspace_id,
                        &relative_path,
                        &contents,
                        Some("utf-8"),
                    )
                    .is_err()
                {
                    return error_response(
                        request,
                        "durable_state_unavailable",
                        true,
                        workspace_revision,
                    );
                }
                durable_document = state
                    .durable
                    .read_document(&durable_workspace_id, &relative_path)
                    .ok()
                    .flatten();
            }
            match durable_document {
                Some(document) => match String::from_utf8(document.contents) {
                    Ok(contents) => json!({
                        "relativePath": document.relative_path,
                        "documentRevision": document.revision,
                        "workspaceRevision": workspace_revision,
                        "contents": contents,
                        "encoding": document.encoding,
                    }),
                    Err(_) => {
                        return error_response(
                            request,
                            "document_not_utf8",
                            false,
                            workspace_revision,
                        );
                    }
                },
                None => {
                    return error_response(request, "document_missing", false, workspace_revision);
                }
            }
        }
        "workspace.search" => {
            let query = request
                .params
                .get("query")
                .and_then(Value::as_str)
                .unwrap_or("");
            let limit = request
                .params
                .get("limit")
                .and_then(Value::as_u64)
                .and_then(|value| usize::try_from(value).ok())
                .unwrap_or(100)
                .clamp(1, 1000);
            let cursor = request
                .params
                .get("cursor")
                .and_then(Value::as_u64)
                .and_then(|value| usize::try_from(value).ok())
                .unwrap_or(0);
            if let Some(scope_id) = request
                .workspace_id
                .as_ref()
                .filter(|scope_id| state.files.has_scope(scope_id))
            {
                match state.files.search(scope_id, query, cursor, limit) {
                    Ok(page) => json!({
                        "matches": page.matches.into_iter().map(|entry| json!({
                            "relativePath": entry.relative_path,
                            "line": entry.line,
                            "column": entry.column,
                            "startOffset": entry.start_offset,
                            "endOffset": entry.end_offset,
                            "text": entry.text,
                            "lineText": entry.line_text,
                        })).collect::<Vec<_>>(),
                        "nextCursor": page.next_cursor,
                        "skippedLargeFiles": page.skipped_large_files,
                        "workspaceRevision": workspace_revision,
                    }),
                    Err(error) => {
                        return file_error_response(request, error, workspace_revision);
                    }
                }
            } else {
                let mut documents = match state.durable.list_documents(&durable_workspace_id) {
                    Ok(documents) => documents,
                    Err(_) => {
                        return error_response(
                            request,
                            "durable_state_unavailable",
                            true,
                            workspace_revision,
                        );
                    }
                };
                documents
                    .sort_unstable_by(|left, right| left.relative_path.cmp(&right.relative_path));
                let mut matches = Vec::<Value>::new();
                let mut matched = 0_usize;
                let mut has_more = false;
                let query_utf16_length = query.encode_utf16().count();
                if !query.is_empty() {
                    'documents: for document in documents {
                        let Ok(contents) = String::from_utf8(document.contents) else {
                            continue;
                        };
                        let mut line_utf16_offset = 0_usize;
                        for (line_index, segment) in contents.split_inclusive('\n').enumerate() {
                            let line_without_newline =
                                segment.strip_suffix('\n').unwrap_or(segment);
                            let line = line_without_newline
                                .strip_suffix('\r')
                                .unwrap_or(line_without_newline);
                            for (column, _) in line.match_indices(query) {
                                if matched < cursor {
                                    matched += 1;
                                    continue;
                                }
                                if matches.len() == limit {
                                    has_more = true;
                                    break 'documents;
                                }
                                let column_utf16 = line[..column].encode_utf16().count();
                                let start_offset = line_utf16_offset + column_utf16;
                                matches.push(json!({
                                    "relativePath": document.relative_path,
                                    "line": line_index + 1,
                                    "column": column_utf16 + 1,
                                    "startOffset": start_offset,
                                    "endOffset": start_offset + query_utf16_length,
                                    "text": query,
                                    "lineText": line,
                                    "documentRevision": document.revision,
                                }));
                                matched += 1;
                            }
                            line_utf16_offset += segment.encode_utf16().count();
                        }
                    }
                }
                let next_cursor = has_more.then_some(cursor + matches.len());
                json!({
                    "matches": matches,
                    "nextCursor": next_cursor,
                    "workspaceRevision": workspace_revision,
                })
            }
        }
        "workspace.transaction.commit" => {
            let expected = request
                .params
                .get("expectedWorkspaceRevision")
                .and_then(Value::as_u64);
            let Some(expected) = expected else {
                return error_response(
                    request,
                    "invalid_workspace_revision",
                    false,
                    workspace_revision,
                );
            };
            let changes = request.params.get("changes").and_then(Value::as_array);
            let Some(changes) = changes else {
                return error_response(request, "invalid_transaction", false, workspace_revision);
            };
            let mut decoded = Vec::with_capacity(changes.len());
            for change in changes {
                let Some(change) = change.as_object() else {
                    return error_response(
                        request,
                        "invalid_transaction",
                        false,
                        workspace_revision,
                    );
                };
                let relative_path = change.get("relativePath").and_then(Value::as_str);
                let expected_document_revision = change
                    .get("expectedDocumentRevision")
                    .and_then(Value::as_u64);
                let contents = change.get("contents").and_then(Value::as_str);
                let (Some(relative_path), Some(expected_document_revision), Some(contents)) =
                    (relative_path, expected_document_revision, contents)
                else {
                    return error_response(
                        request,
                        "invalid_transaction",
                        false,
                        workspace_revision,
                    );
                };
                if vityod_workspace::validate_relative_path(relative_path).is_err() {
                    return error_response(
                        request,
                        "workspace_root_escape",
                        false,
                        workspace_revision,
                    );
                }
                decoded.push(DurableDocumentChange {
                    relative_path: relative_path.to_owned(),
                    expected_document_revision,
                    contents: contents.as_bytes().to_vec(),
                    encoding: change
                        .get("encoding")
                        .and_then(Value::as_str)
                        .map(str::to_owned),
                });
            }
            let workspace_scope = request
                .workspace_id
                .as_ref()
                .filter(|scope_id| state.files.has_scope(scope_id))
                .cloned();
            let disk_transaction = if let Some(scope_id) = workspace_scope.as_deref() {
                let payload = match write_recovery_payload(&state.files, scope_id, &decoded) {
                    Ok(payload) => payload,
                    Err(error) => return file_error_response(request, error, workspace_revision),
                };
                let transaction_id = next_workspace_transaction_id();
                if let Err(error) =
                    stage_workspace_writes(&state.files, scope_id, &transaction_id, &decoded)
                {
                    let _ = cleanup_workspace_transaction(&state.files, scope_id, &transaction_id);
                    return file_error_response(request, error, workspace_revision);
                }
                let recovery_payload = serde_json::to_vec(&payload)
                    .expect("workspace recovery payload is JSON-compatible");
                if let Err(error) = state.durable.prepare_workspace_fs_transaction(
                    &transaction_id,
                    &durable_workspace_id,
                    expected,
                    &recovery_payload,
                ) {
                    let _ = cleanup_workspace_transaction(&state.files, scope_id, &transaction_id);
                    return match error {
                        DurableStateError::WorkspaceConflict { .. } => error_response(
                            request,
                            "workspace_revision_conflict",
                            true,
                            workspace_revision,
                        ),
                        _ => error_response(
                            request,
                            "durable_state_unavailable",
                            true,
                            workspace_revision,
                        ),
                    };
                }
                if let Err(error) =
                    apply_workspace_transaction(&state.files, scope_id, &transaction_id, &payload)
                {
                    let _ = rollback_workspace_transaction(
                        &state.files,
                        scope_id,
                        &transaction_id,
                        &payload,
                    );
                    let _ = state
                        .durable
                        .discard_workspace_fs_transaction(&transaction_id, &durable_workspace_id);
                    return file_error_response(request, error, workspace_revision);
                }
                Some((transaction_id, payload))
            } else {
                None
            };
            let receipt_request = request.clone();
            let build_response = |receipt: &vityod_kernel::DurableCommitReceipt| {
                Ok(success_response(
                    receipt_request.clone(),
                    json!({
                        "workspaceRevision": receipt.workspace_revision,
                        "documentRevisions": receipt.document_revisions,
                        "eventCursor": receipt.event_cursor,
                    }),
                    receipt.workspace_revision,
                )
                .encode()
                .expect("workspace commit response is protocol-valid"))
            };
            let commit = match disk_transaction.as_ref() {
                Some((transaction_id, _)) => state
                    .durable
                    .commit_documents_with_receipt_and_fs_transaction(
                        &durable_workspace_id,
                        expected,
                        &decoded,
                        b"workspace-commit",
                        DurableFsTransactionBinding {
                            idempotency_key: &durable_receipt_key,
                            transaction_id,
                        },
                        &build_response,
                    ),
                None => state.durable.commit_documents_with_receipt(
                    &durable_workspace_id,
                    expected,
                    &decoded,
                    b"workspace-commit",
                    &durable_receipt_key,
                    &build_response,
                ),
            };
            if let (Some(scope_id), Some((transaction_id, payload))) =
                (workspace_scope.as_deref(), disk_transaction.as_ref())
            {
                let journal_pending = state
                    .durable
                    .pending_workspace_fs_transactions(&durable_workspace_id)
                    .map(|pending| {
                        pending
                            .iter()
                            .any(|pending| pending.transaction_id == *transaction_id)
                    })
                    .unwrap_or(true);
                if commit.is_err() && journal_pending {
                    let _ = rollback_workspace_transaction(
                        &state.files,
                        scope_id,
                        transaction_id,
                        payload,
                    );
                    let _ = state
                        .durable
                        .discard_workspace_fs_transaction(transaction_id, &durable_workspace_id);
                } else {
                    let _ = cleanup_workspace_transaction(&state.files, scope_id, transaction_id);
                }
            }
            match commit {
                Ok((receipt, _)) => json!({
                    "workspaceRevision": receipt.workspace_revision,
                    "documentRevisions": receipt.document_revisions,
                    "eventCursor": receipt.event_cursor,
                }),
                Err(DurableStateError::WorkspaceConflict { .. }) => {
                    return error_response(
                        request,
                        "workspace_revision_conflict",
                        true,
                        workspace_revision,
                    );
                }
                Err(DurableStateError::DocumentConflict { .. }) => {
                    return error_response(
                        request,
                        "document_revision_conflict",
                        true,
                        workspace_revision,
                    );
                }
                Err(DurableStateError::EmptyTransaction) => {
                    return error_response(request, "empty_transaction", false, workspace_revision);
                }
                Err(_) => {
                    return error_response(request, "transaction_failed", true, workspace_revision);
                }
            }
        }
        "workspace.delete" => {
            let Some(relative_path) = required_string_param(&request, "relativePath") else {
                return error_response(
                    request,
                    "invalid_workspace_path",
                    false,
                    workspace_revision,
                );
            };
            if vityod_workspace::validate_relative_path(&relative_path).is_err() {
                return error_response(request, "workspace_root_escape", false, workspace_revision);
            }
            let expected_workspace_revision = request
                .params
                .get("expectedWorkspaceRevision")
                .and_then(Value::as_u64);
            let expected_document_revision = request
                .params
                .get("expectedDocumentRevision")
                .and_then(Value::as_u64);
            let (Some(expected_workspace_revision), Some(expected_document_revision)) =
                (expected_workspace_revision, expected_document_revision)
            else {
                return error_response(
                    request,
                    "invalid_workspace_revision",
                    false,
                    workspace_revision,
                );
            };
            let workspace_scope = request
                .workspace_id
                .as_ref()
                .filter(|scope_id| state.files.has_scope(scope_id))
                .cloned();
            if let Some(scope_id) = workspace_scope.as_deref() {
                match state.files.read(scope_id, &relative_path) {
                    Ok(contents) => {
                        if state
                            .durable
                            .import_document_if_missing(
                                &durable_workspace_id,
                                &relative_path,
                                &contents,
                                Some("utf-8"),
                            )
                            .is_err()
                        {
                            return error_response(
                                request,
                                "durable_state_unavailable",
                                true,
                                workspace_revision,
                            );
                        }
                    }
                    Err(FileServiceError::NotFound) => {}
                    Err(error) => {
                        return file_error_response(request, error, workspace_revision);
                    }
                }
            }
            let disk_transaction = if let Some(scope_id) = workspace_scope.as_deref() {
                let payload = match delete_recovery_payload(&state.files, scope_id, &relative_path)
                {
                    Ok(payload) => payload,
                    Err(error) => return file_error_response(request, error, workspace_revision),
                };
                let transaction_id = next_workspace_transaction_id();
                if let Err(error) =
                    stage_workspace_intent(&state.files, scope_id, &transaction_id, 0)
                {
                    return file_error_response(request, error, workspace_revision);
                }
                let recovery_payload = serde_json::to_vec(&payload)
                    .expect("workspace recovery payload is JSON-compatible");
                if let Err(error) = state.durable.prepare_workspace_fs_transaction(
                    &transaction_id,
                    &durable_workspace_id,
                    expected_workspace_revision,
                    &recovery_payload,
                ) {
                    let _ = cleanup_workspace_transaction(&state.files, scope_id, &transaction_id);
                    return match error {
                        DurableStateError::WorkspaceConflict { .. } => error_response(
                            request,
                            "workspace_revision_conflict",
                            true,
                            workspace_revision,
                        ),
                        _ => error_response(
                            request,
                            "durable_state_unavailable",
                            true,
                            workspace_revision,
                        ),
                    };
                }
                if let Err(error) =
                    apply_workspace_transaction(&state.files, scope_id, &transaction_id, &payload)
                {
                    let _ = rollback_workspace_transaction(
                        &state.files,
                        scope_id,
                        &transaction_id,
                        &payload,
                    );
                    let _ = state
                        .durable
                        .discard_workspace_fs_transaction(&transaction_id, &durable_workspace_id);
                    return file_error_response(request, error, workspace_revision);
                }
                Some((transaction_id, payload))
            } else {
                None
            };
            let receipt_request = request.clone();
            let build_response = |receipt: Option<&vityod_kernel::DurableCommitReceipt>,
                                  current_revision: u64| {
                let params = match receipt {
                    Some(receipt) => json!({
                        "deleted": true,
                        "workspaceRevision": receipt.workspace_revision,
                        "eventCursor": receipt.event_cursor,
                    }),
                    None => json!({
                        "deleted": false,
                        "workspaceRevision": current_revision,
                    }),
                };
                Ok(
                    success_response(receipt_request.clone(), params, current_revision)
                        .encode()
                        .expect("workspace delete response is protocol-valid"),
                )
            };
            let deletion = match disk_transaction.as_ref() {
                Some((transaction_id, _)) => state
                    .durable
                    .delete_document_with_receipt_and_fs_transaction(
                        &durable_workspace_id,
                        expected_workspace_revision,
                        &relative_path,
                        expected_document_revision,
                        DurableFsTransactionBinding {
                            idempotency_key: &durable_receipt_key,
                            transaction_id,
                        },
                        &build_response,
                    ),
                None => state.durable.delete_document_with_receipt(
                    &durable_workspace_id,
                    expected_workspace_revision,
                    &relative_path,
                    expected_document_revision,
                    &durable_receipt_key,
                    &build_response,
                ),
            };
            if let (Some(scope_id), Some((transaction_id, payload))) =
                (workspace_scope.as_deref(), disk_transaction.as_ref())
            {
                let journal_pending = state
                    .durable
                    .pending_workspace_fs_transactions(&durable_workspace_id)
                    .map(|pending| {
                        pending
                            .iter()
                            .any(|pending| pending.transaction_id == *transaction_id)
                    })
                    .unwrap_or(true);
                if deletion.is_err() && journal_pending {
                    let _ = rollback_workspace_transaction(
                        &state.files,
                        scope_id,
                        transaction_id,
                        payload,
                    );
                    let _ = state
                        .durable
                        .discard_workspace_fs_transaction(transaction_id, &durable_workspace_id);
                } else {
                    let _ = cleanup_workspace_transaction(&state.files, scope_id, transaction_id);
                }
            }
            match deletion {
                Ok((Some(receipt), _)) => json!({
                    "deleted": true,
                    "workspaceRevision": receipt.workspace_revision,
                    "eventCursor": receipt.event_cursor,
                }),
                Ok((None, _)) => json!({
                    "deleted": false,
                    "workspaceRevision": workspace_revision,
                }),
                Err(DurableStateError::WorkspaceConflict { .. }) => {
                    return error_response(
                        request,
                        "workspace_revision_conflict",
                        true,
                        workspace_revision,
                    );
                }
                Err(DurableStateError::DocumentConflict { .. }) => {
                    return error_response(
                        request,
                        "document_revision_conflict",
                        true,
                        workspace_revision,
                    );
                }
                Err(_) => {
                    return error_response(request, "transaction_failed", true, workspace_revision);
                }
            }
        }
        "pty.start" => {
            let terminal_id = required_string_param(&request, "terminalId");
            let executable = required_string_param(&request, "executable");
            let Some(terminal_id) = terminal_id else {
                return error_response(request, "invalid_terminal_id", false, workspace_revision);
            };
            let Some(executable) = executable else {
                return error_response(request, "invalid_executable", false, workspace_revision);
            };
            let arguments = string_list_param(&request, "arguments").unwrap_or_default();
            let environment = string_map_param(&request, "environment").unwrap_or_default();
            let working_directory = request
                .params
                .get("workingDirectory")
                .and_then(Value::as_str)
                .map(std::path::PathBuf::from);
            let rows = bounded_u16_param(&request, "rows").unwrap_or(24);
            let cols = bounded_u16_param(&request, "cols").unwrap_or(80);
            match state.runtime.ptys.start(PtyLaunch {
                id: terminal_id,
                executable,
                arguments,
                working_directory,
                environment,
                rows,
                cols,
            }) {
                Ok(stream_id) => json!({
                    "streamId": stream_id,
                    "state": "running",
                    "outputCreditBytes": 262144,
                }),
                Err(error) => {
                    return error_response(
                        request,
                        pty_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "styio.request" | "pafio.request" => {
            let prefix = request.method.split('.').next().unwrap_or("tool");
            match tool_process_response(&mut state.runtime.tasks, &request, prefix) {
                Ok(response) => response,
                Err(error_code) => {
                    return error_response(request, error_code, false, workspace_revision);
                }
            }
        }
        "git.start" => {
            let Some(task_id) = required_string_param(&request, "taskId") else {
                return error_response(request, "invalid_git_task", false, workspace_revision);
            };
            let Some(workspace_id) = request.workspace_id.as_deref() else {
                return error_response(request, "invalid_git_workspace", false, workspace_revision);
            };
            let working_directory = match state.files.scope_root(workspace_id) {
                Ok(root) => root,
                Err(_) => {
                    return error_response(
                        request,
                        "unknown_git_workspace",
                        false,
                        workspace_revision,
                    );
                }
            };
            let Some((arguments, standard_input)) = git_launch_params(&request) else {
                return error_response(request, "invalid_git_request", false, workspace_revision);
            };
            let Some(executable) = resolve_path_executable("git") else {
                return error_response(request, "git_unavailable", false, workspace_revision);
            };
            let internal_task_id = format!("git:{task_id}");
            match state.runtime.tasks.start(TaskLaunch {
                id: internal_task_id,
                executable,
                arguments,
                working_directory: Some(working_directory),
                environment: std::collections::HashMap::new(),
                standard_input,
                timeout: std::time::Duration::from_secs(30),
            }) {
                Ok(()) => json!({"state": "running", "taskId": task_id}),
                Err(error) => {
                    return error_response(
                        request,
                        task_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "git.output" => {
            let Some(task_id) = required_string_param(&request, "taskId") else {
                return error_response(request, "invalid_git_task", false, workspace_revision);
            };
            match state.runtime.tasks.snapshot(&format!("git:{task_id}")) {
                Ok(snapshot) => {
                    let stdout = String::from_utf8(snapshot.stdout);
                    let stderr = String::from_utf8(snapshot.stderr);
                    let (Ok(stdout), Ok(stderr)) = (stdout, stderr) else {
                        return error_response(
                            request,
                            "git_output_not_utf8",
                            false,
                            workspace_revision,
                        );
                    };
                    json!({
                        "running": snapshot.running,
                        "timedOut": snapshot.timed_out,
                        "exitCode": snapshot.exit_code,
                        "stdout": stdout,
                        "stderr": stderr,
                        "stdoutTruncated": snapshot.stdout_truncated,
                        "stderrTruncated": snapshot.stderr_truncated,
                        "durationMillis": snapshot.duration_millis,
                    })
                }
                Err(error) => {
                    return error_response(
                        request,
                        task_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "git.close" => {
            let Some(task_id) = required_string_param(&request, "taskId") else {
                return error_response(request, "invalid_git_task", false, workspace_revision);
            };
            match state.runtime.tasks.remove(&format!("git:{task_id}")) {
                Ok(()) => json!({"state": "closed"}),
                Err(error) => {
                    return error_response(
                        request,
                        task_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "task.start" => {
            let Some(task_id) = required_string_param(&request, "taskId") else {
                return error_response(request, "invalid_task_id", false, workspace_revision);
            };
            let Some(executable) = required_string_param(&request, "executable") else {
                return error_response(request, "invalid_executable", false, workspace_revision);
            };
            let arguments = string_list_param(&request, "arguments").unwrap_or_default();
            let environment = string_map_param(&request, "environment").unwrap_or_default();
            let working_directory = request
                .params
                .get("workingDirectory")
                .and_then(Value::as_str)
                .map(std::path::PathBuf::from);
            let standard_input = request
                .params
                .get("standardInput")
                .and_then(Value::as_str)
                .map(|value| value.as_bytes().to_vec());
            let timeout_millis = request
                .params
                .get("timeoutMillis")
                .and_then(Value::as_u64)
                .unwrap_or(30_000)
                .clamp(1, 30 * 60 * 1000);
            match state.runtime.tasks.start(TaskLaunch {
                id: task_id,
                executable: std::path::PathBuf::from(executable),
                arguments,
                working_directory,
                environment,
                standard_input,
                timeout: std::time::Duration::from_millis(timeout_millis),
            }) {
                Ok(()) => json!({"state": "running"}),
                Err(error) => {
                    return error_response(
                        request,
                        task_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "task.output" => {
            let Some(task_id) = required_string_param(&request, "taskId") else {
                return error_response(request, "invalid_task_id", false, workspace_revision);
            };
            match state.runtime.tasks.snapshot(&task_id) {
                Ok(snapshot) => {
                    let stdout = String::from_utf8(snapshot.stdout);
                    let stderr = String::from_utf8(snapshot.stderr);
                    let (Ok(stdout), Ok(stderr)) = (stdout, stderr) else {
                        return error_response(
                            request,
                            "task_output_not_utf8",
                            false,
                            workspace_revision,
                        );
                    };
                    json!({
                        "running": snapshot.running,
                        "timedOut": snapshot.timed_out,
                        "exitCode": snapshot.exit_code,
                        "stdout": stdout,
                        "stderr": stderr,
                        "stdoutTruncated": snapshot.stdout_truncated,
                        "stderrTruncated": snapshot.stderr_truncated,
                        "durationMillis": snapshot.duration_millis,
                    })
                }
                Err(error) => {
                    return error_response(
                        request,
                        task_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "task.cancel" => {
            let Some(task_id) = required_string_param(&request, "taskId") else {
                return error_response(request, "invalid_task_id", false, workspace_revision);
            };
            match state.runtime.tasks.cancel(&task_id) {
                Ok(exit_code) => json!({"state": "cancelled", "exitCode": exit_code}),
                Err(error) => {
                    return error_response(
                        request,
                        task_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "task.close" => {
            let Some(task_id) = required_string_param(&request, "taskId") else {
                return error_response(request, "invalid_task_id", false, workspace_revision);
            };
            match state.runtime.tasks.remove(&task_id) {
                Ok(()) => json!({"state": "closed"}),
                Err(error) => {
                    return error_response(
                        request,
                        task_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "pty.resize" => {
            let Some(stream_id) = u32_param(&request, "streamId") else {
                return error_response(request, "invalid_stream_id", false, workspace_revision);
            };
            let Some(rows) = bounded_u16_param(&request, "rows") else {
                return error_response(request, "invalid_pty_size", false, workspace_revision);
            };
            let Some(cols) = bounded_u16_param(&request, "cols") else {
                return error_response(request, "invalid_pty_size", false, workspace_revision);
            };
            if let Err(error) = state.runtime.ptys.resize(stream_id, rows, cols) {
                return error_response(request, pty_error_code(error), false, workspace_revision);
            }
            json!({"state": "resized", "rows": rows, "cols": cols})
        }
        "pty.close" => {
            let Some(stream_id) = u32_param(&request, "streamId") else {
                return error_response(request, "invalid_stream_id", false, workspace_revision);
            };
            match state.runtime.ptys.terminate(stream_id) {
                Ok(exit_code) => json!({"state": "closed", "exitCode": exit_code}),
                Err(error) => {
                    return error_response(
                        request,
                        pty_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "dap.start" | "lsp.start" => {
            let kind = request.method.split('.').next().unwrap_or("protocol");
            let Some(process_id) = required_string_param(&request, "processId") else {
                return error_response(request, "invalid_process_id", false, workspace_revision);
            };
            let Some(executable) = required_string_param(&request, "executable") else {
                return error_response(request, "invalid_executable", false, workspace_revision);
            };
            let arguments = string_list_param(&request, "arguments").unwrap_or_default();
            let environment = string_map_param(&request, "environment").unwrap_or_default();
            let working_directory = request
                .params
                .get("workingDirectory")
                .and_then(Value::as_str)
                .map(std::path::PathBuf::from);
            let internal_id = format!("{kind}:{process_id}");
            match state.runtime.protocol_processes.start(ByteProcessLaunch {
                id: internal_id,
                executable: std::path::PathBuf::from(executable),
                arguments,
                working_directory,
                environment,
            }) {
                Ok(()) => json!({"state": "running", "processId": process_id}),
                Err(error) => {
                    return error_response(
                        request,
                        byte_process_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "dap.request" | "lsp.request" => {
            let kind = request.method.split('.').next().unwrap_or("protocol");
            let Some(process_id) = required_string_param(&request, "processId") else {
                return error_response(request, "invalid_process_id", false, workspace_revision);
            };
            let internal_id = format!("{kind}:{process_id}");
            match request.params.get("action").and_then(Value::as_str) {
                Some("write") => {
                    let Some(bytes) = byte_list_param(&request, "bytes") else {
                        return error_response(
                            request,
                            "invalid_protocol_bytes",
                            false,
                            workspace_revision,
                        );
                    };
                    match state.runtime.protocol_processes.write(&internal_id, &bytes) {
                        Ok(()) => json!({"accepted": true}),
                        Err(error) => {
                            return error_response(
                                request,
                                byte_process_error_code(error),
                                false,
                                workspace_revision,
                            );
                        }
                    }
                }
                Some("poll") => {
                    let maximum_bytes = request
                        .params
                        .get("maximumBytes")
                        .and_then(Value::as_u64)
                        .and_then(|value| usize::try_from(value).ok())
                        .unwrap_or(64 * 1024);
                    match state
                        .runtime
                        .protocol_processes
                        .poll(&internal_id, maximum_bytes)
                    {
                        Ok(poll) => json!({
                            "stdout": poll.stdout,
                            "stderr": poll.stderr,
                            "exitCode": poll.exit_code,
                            "overflowed": poll.overflowed,
                        }),
                        Err(error) => {
                            return error_response(
                                request,
                                byte_process_error_code(error),
                                false,
                                workspace_revision,
                            );
                        }
                    }
                }
                _ => {
                    return error_response(
                        request,
                        "invalid_protocol_action",
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "dap.stop" | "lsp.stop" => {
            let kind = request.method.split('.').next().unwrap_or("protocol");
            let Some(process_id) = required_string_param(&request, "processId") else {
                return error_response(request, "invalid_process_id", false, workspace_revision);
            };
            let internal_id = format!("{kind}:{process_id}");
            match state.runtime.protocol_processes.stop(&internal_id) {
                Ok(exit_code) => json!({"state": "closed", "exitCode": exit_code}),
                Err(error) => {
                    return error_response(
                        request,
                        byte_process_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "agent.connection.open" => {
            let Some(agent_id) = required_string_param(&request, "agentId") else {
                return error_response(request, "invalid_agent_id", false, workspace_revision);
            };
            let Some(executable) = required_string_param(&request, "executable") else {
                return error_response(request, "invalid_executable", false, workspace_revision);
            };
            let Some(working_directory) = required_string_param(&request, "workingDirectory")
            else {
                return error_response(
                    request,
                    "invalid_working_directory",
                    false,
                    workspace_revision,
                );
            };
            let arguments = string_list_param(&request, "arguments").unwrap_or_default();
            let allowed_extensions =
                string_list_param(&request, "allowedExtensions").unwrap_or_default();
            let maximum_message_bytes = request
                .params
                .get("maximumMessageBytes")
                .and_then(Value::as_u64)
                .and_then(|value| usize::try_from(value).ok())
                .unwrap_or(1024 * 1024);
            match state.runtime.acp_agents.connect(
                AgentProcessLaunch {
                    agent_id,
                    executable: std::path::PathBuf::from(executable),
                    arguments,
                    working_directory: std::path::PathBuf::from(working_directory),
                },
                allowed_extensions,
                maximum_message_bytes,
                bounded_request_timeout(&request),
            ) {
                Ok(connection) => json!({
                    "agentId": connection.agent_id,
                    "protocolVersion": connection.protocol_version,
                    "generation": connection.generation,
                    "capabilities": connection.capabilities,
                    "metadata": {},
                }),
                Err(error) => {
                    return error_response(
                        request,
                        acp_error_code(error),
                        matches!(error, AcpError::TimedOut | AcpError::TransportFailed),
                        workspace_revision,
                    );
                }
            }
        }
        "agent.connection.close" => {
            let Some(agent_id) = required_string_param(&request, "agentId") else {
                return error_response(request, "invalid_agent_id", false, workspace_revision);
            };
            match state.runtime.acp_agents.disconnect(&agent_id) {
                Ok(exit_code) => json!({
                    "agentId": agent_id,
                    "terminated": true,
                    "forced": true,
                    "exitCode": exit_code,
                }),
                Err(AcpError::UnknownAgent) => json!({
                    "agentId": agent_id,
                    "terminated": true,
                    "forced": false,
                    "exitCode": 0,
                }),
                Err(error) => {
                    return error_response(
                        request,
                        acp_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "agent.session.new" => {
            let Some(agent_id) = required_string_param(&request, "agentId") else {
                return error_response(request, "invalid_agent_id", false, workspace_revision);
            };
            let Some(workspace_path) = required_string_param(&request, "workspacePath") else {
                return error_response(
                    request,
                    "invalid_workspace_path",
                    false,
                    workspace_revision,
                );
            };
            let workspace_id = required_string_param(&request, "workspaceId")
                .or_else(|| request.workspace_id.clone())
                .unwrap_or_else(|| workspace_path.clone());
            let revision = request
                .params
                .get("workspaceRevision")
                .and_then(Value::as_u64)
                .unwrap_or(workspace_revision);
            match state.runtime.acp_agents.new_session(
                &agent_id,
                &workspace_path,
                bounded_request_timeout(&request),
            ) {
                Ok(session) => {
                    let capabilities = state
                        .runtime
                        .acp_agents
                        .connection(&agent_id)
                        .map(|connection| connection.capabilities)
                        .unwrap_or_default();
                    if state
                        .durable
                        .upsert_agent_session(
                            &session.session_id,
                            &workspace_id,
                            revision,
                            &capabilities,
                        )
                        .and_then(|()| {
                            state
                                .durable
                                .append_agent_session_event(&session.session_id, "started")
                                .map(|_| ())
                        })
                        .is_err()
                    {
                        return error_response(
                            request,
                            "agent_projection_unavailable",
                            true,
                            workspace_revision,
                        );
                    }
                    json!({
                        "sessionId": session.session_id,
                        "agentId": session.agent_id,
                        "generation": session.generation,
                        "remoteSessionId": session.remote_session_id,
                    })
                }
                Err(error) => {
                    return error_response(
                        request,
                        acp_error_code(error),
                        matches!(error, AcpError::TimedOut | AcpError::TransportFailed),
                        workspace_revision,
                    );
                }
            }
        }
        "agent.session.load" => {
            let Some(session_id) = required_string_param(&request, "sessionId") else {
                return error_response(request, "invalid_agent_session", false, workspace_revision);
            };
            let Some(workspace_path) = required_string_param(&request, "workspacePath") else {
                return error_response(
                    request,
                    "invalid_workspace_path",
                    false,
                    workspace_revision,
                );
            };
            match state.runtime.acp_agents.load_session(
                &session_id,
                &workspace_path,
                bounded_request_timeout(&request),
            ) {
                Ok(session) => {
                    let _ = state
                        .durable
                        .append_agent_session_event(&session_id, "restored");
                    json!({
                        "sessionId": session.session_id,
                        "agentId": session.agent_id,
                        "generation": session.generation,
                        "remoteSessionId": session.remote_session_id,
                    })
                }
                Err(error) => {
                    return error_response(
                        request,
                        acp_error_code(error),
                        matches!(error, AcpError::TimedOut | AcpError::TransportFailed),
                        workspace_revision,
                    );
                }
            }
        }
        "agent.session.prompt" => {
            let Some(session_id) = required_string_param(&request, "sessionId") else {
                return error_response(request, "invalid_agent_session", false, workspace_revision);
            };
            let Some(text) = required_string_param_with_limit(&request, "text", 1024 * 1024) else {
                return error_response(request, "invalid_prompt", false, workspace_revision);
            };
            match state.runtime.acp_agents.start_prompt(&session_id, &text) {
                Ok(()) => json!({"sessionId": session_id, "state": "running"}),
                Err(error) => {
                    return error_response(
                        request,
                        acp_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "agent.session.poll" => {
            let Some(session_id) = required_string_param(&request, "sessionId") else {
                return error_response(request, "invalid_agent_session", false, workspace_revision);
            };
            let after_sequence = request
                .params
                .get("afterSequence")
                .and_then(Value::as_u64)
                .unwrap_or(0);
            match state.runtime.acp_agents.poll(&session_id, after_sequence) {
                Ok(poll) => {
                    let connection = state
                        .runtime
                        .acp_agents
                        .session(&session_id)
                        .and_then(|session| state.runtime.acp_agents.connection(&session.agent_id));
                    let (connection_capabilities, connection_generation) = connection
                        .map(|snapshot| (snapshot.capabilities, snapshot.generation))
                        .unwrap_or_default();
                    json!({
                        "sessionId": session_id,
                        "events": poll.events.into_iter().map(|event| json!({
                            "sequence": event.sequence,
                            "kind": event.kind,
                            "text": event.text,
                            "payload": event.payload,
                        })).collect::<Vec<_>>(),
                        "permissions": poll.permissions.into_iter().map(|permission| json!({
                            "permissionId": permission.permission_id,
                            "agentId": permission.agent_id,
                            "sessionId": permission.session_id,
                            "toolCallId": permission.tool_call_id,
                            "toolCallTitle": permission.tool_call_title,
                            "toolCallKind": permission.tool_call_kind,
                            "options": permission.options,
                        })).collect::<Vec<_>>(),
                        "promptResult": poll.prompt_result,
                        "processExitCode": poll.process_exit_code,
                        "connectionCapabilities": connection_capabilities,
                        "connectionGeneration": connection_generation,
                    })
                }
                Err(error) => {
                    return error_response(
                        request,
                        acp_error_code(error),
                        matches!(error, AcpError::TransportFailed),
                        workspace_revision,
                    );
                }
            }
        }
        "agent.acp.session.cancel" => {
            let Some(session_id) = required_string_param(&request, "sessionId") else {
                return error_response(request, "invalid_agent_session", false, workspace_revision);
            };
            match state.runtime.acp_agents.cancel_prompt(&session_id) {
                Ok(cancelled) => {
                    if cancelled {
                        let _ = state
                            .durable
                            .append_agent_session_event(&session_id, "prompt.cancelled");
                    }
                    json!({"sessionId": session_id, "cancelled": cancelled})
                }
                Err(error) => {
                    return error_response(
                        request,
                        acp_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "agent.acp.permission.decide" => {
            let Some(permission_id) = required_string_param(&request, "permissionId") else {
                return error_response(request, "invalid_permission", false, workspace_revision);
            };
            let Some(decision) = required_string_param(&request, "decision") else {
                return error_response(
                    request,
                    "invalid_permission_decision",
                    false,
                    workspace_revision,
                );
            };
            match state
                .runtime
                .acp_agents
                .resolve_permission(&permission_id, &decision)
            {
                Ok(()) => json!({"permissionId": permission_id, "resolved": true}),
                Err(error) => {
                    return error_response(
                        request,
                        acp_error_code(error),
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "agent.extension.invoke" => {
            let Some(agent_id) = required_string_param(&request, "agentId") else {
                return error_response(request, "invalid_agent_id", false, workspace_revision);
            };
            let Some(method) = required_string_param(&request, "extensionMethod") else {
                return error_response(request, "invalid_extension", false, workspace_revision);
            };
            let params = request
                .params
                .get("extensionParams")
                .cloned()
                .unwrap_or_else(|| json!({}));
            match state.runtime.acp_agents.invoke_extension(
                &agent_id,
                &method,
                params,
                bounded_request_timeout(&request),
            ) {
                Ok(result) => json!({"result": result}),
                Err(error) => {
                    return error_response(
                        request,
                        acp_error_code(error),
                        matches!(error, AcpError::TimedOut | AcpError::TransportFailed),
                        workspace_revision,
                    );
                }
            }
        }
        "agent.session.start" => {
            let Some(session_id) = required_string_param(&request, "sessionId") else {
                return error_response(request, "invalid_agent_session", false, workspace_revision);
            };
            let Some(workspace_id) = required_string_param(&request, "workspaceId") else {
                return error_response(request, "invalid_workspace_id", false, workspace_revision);
            };
            let revision = request
                .params
                .get("workspaceRevision")
                .and_then(Value::as_u64)
                .unwrap_or(workspace_revision);
            let capabilities = string_list_param(&request, "capabilities").unwrap_or_default();
            if state
                .durable
                .upsert_agent_session(&session_id, &workspace_id, revision, &capabilities)
                .and_then(|()| {
                    state
                        .durable
                        .append_agent_session_event(&session_id, "started")
                        .map(|_| ())
                })
                .is_err()
            {
                return error_response(
                    request,
                    "agent_projection_unavailable",
                    true,
                    workspace_revision,
                );
            }
            state
                .runtime
                .agent_host
                .start_session(session_id.clone(), 4096);
            state.runtime.agent_host.grant(
                session_id.clone(),
                CapabilityGrant::new(workspace_id, revision, capabilities),
            );
            json!({"sessionId": session_id, "state": "running"})
        }
        "agent.session.resume" => {
            let Some(session_id) = required_string_param(&request, "sessionId") else {
                return error_response(request, "invalid_agent_session", false, workspace_revision);
            };
            let after_sequence = request
                .params
                .get("afterSequence")
                .and_then(Value::as_u64)
                .unwrap_or(0);
            let session = state
                .durable
                .list_agent_sessions()
                .ok()
                .and_then(|sessions| {
                    sessions
                        .into_iter()
                        .find(|session| session.session_id == session_id)
                });
            let Some(session) = session else {
                return error_response(request, "unknown_agent_session", false, workspace_revision);
            };
            match state
                .durable
                .resume_agent_session_events(&session_id, after_sequence)
            {
                Ok(events) => json!({
                    "sessionId": session_id,
                    "workspaceId": session.workspace_id,
                    "workspaceRevision": session.workspace_revision,
                    "capabilities": session.capabilities,
                    "revoked": session.revoked,
                    "events": events.into_iter().map(|event| json!({
                        "sequence": event.sequence,
                        "kind": event.kind,
                    })).collect::<Vec<_>>(),
                }),
                Err(DurableStateError::ResumeGap(gap)) => {
                    return error_response_with_context(
                        request,
                        "agent_event_cursor_pruned",
                        true,
                        workspace_revision,
                        json!({"oldestAvailableSequence": gap.oldest_available_cursor}),
                    );
                }
                Err(_) => {
                    return error_response(
                        request,
                        "agent_projection_unavailable",
                        true,
                        workspace_revision,
                    );
                }
            }
        }
        "agent.session.cancel" => {
            let Some(session_id) = required_string_param(&request, "sessionId") else {
                return error_response(request, "invalid_agent_session", false, workspace_revision);
            };
            if state
                .durable
                .revoke_agent_session(&session_id)
                .and_then(|()| {
                    state
                        .durable
                        .append_agent_session_event(&session_id, "revoked")
                        .map(|_| ())
                })
                .is_err()
            {
                return error_response(
                    request,
                    "agent_projection_unavailable",
                    true,
                    workspace_revision,
                );
            }
            state.runtime.agent_host.revoke(&session_id);
            json!({"sessionId": session_id, "state": "revoked"})
        }
        "agent.permission.request" => {
            let Some(session_id) = required_string_param(&request, "sessionId") else {
                return error_response(request, "invalid_agent_session", false, workspace_revision);
            };
            let Some(permission_id) = required_string_param(&request, "permissionId") else {
                return error_response(request, "invalid_permission", false, workspace_revision);
            };
            if state
                .runtime
                .agent_host
                .request_permission(&session_id, permission_id)
                .is_err()
            {
                return error_response(
                    request,
                    "permission_request_rejected",
                    false,
                    workspace_revision,
                );
            }
            if state
                .durable
                .append_agent_session_event(&session_id, "permission.requested")
                .is_err()
            {
                return error_response(
                    request,
                    "agent_projection_unavailable",
                    true,
                    workspace_revision,
                );
            }
            json!({"pending": true})
        }
        "agent.permission.decide" => {
            let Some(session_id) = required_string_param(&request, "sessionId") else {
                return error_response(request, "invalid_agent_session", false, workspace_revision);
            };
            let Some(permission_id) = required_string_param(&request, "permissionId") else {
                return error_response(request, "invalid_permission", false, workspace_revision);
            };
            let decision = match request.params.get("decision").and_then(Value::as_str) {
                Some("allow_once") => PermissionDecision::AllowOnce,
                Some("deny") => PermissionDecision::Deny,
                _ => {
                    return error_response(
                        request,
                        "invalid_permission_decision",
                        false,
                        workspace_revision,
                    );
                }
            };
            match state
                .runtime
                .agent_host
                .resolve_permission(&session_id, &permission_id, decision)
            {
                Ok(()) => {
                    let event_kind = match decision {
                        PermissionDecision::AllowOnce => "permission.allowed_once",
                        PermissionDecision::Deny => "permission.denied",
                    };
                    if state
                        .durable
                        .append_agent_session_event(&session_id, event_kind)
                        .is_err()
                    {
                        return error_response(
                            request,
                            "agent_projection_unavailable",
                            true,
                            workspace_revision,
                        );
                    }
                    json!({"resolved": true})
                }
                Err(_) => {
                    return error_response(
                        request,
                        "permission_not_pending",
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        "agent.mcp.invoke" => {
            let Some(session_id) = required_string_param(&request, "sessionId") else {
                return error_response(request, "invalid_agent_session", false, workspace_revision);
            };
            let Some(workspace_id) = required_string_param(&request, "workspaceId") else {
                return error_response(request, "invalid_workspace_id", false, workspace_revision);
            };
            let Some(tool) = required_string_param(&request, "tool") else {
                return error_response(request, "invalid_mcp_tool", false, workspace_revision);
            };
            let revision = request
                .params
                .get("workspaceRevision")
                .and_then(Value::as_u64)
                .unwrap_or(workspace_revision);
            if state
                .runtime
                .agent_host
                .authorize(&session_id, &workspace_id, revision, &tool)
                .is_err()
            {
                return error_response(request, "capability_denied", false, workspace_revision);
            }
            if state
                .durable
                .append_agent_session_event(&session_id, &format!("mcp.{tool}"))
                .is_err()
            {
                return error_response(
                    request,
                    "agent_projection_unavailable",
                    true,
                    workspace_revision,
                );
            }
            match tool.as_str() {
                "workspace.read" => {
                    let Some(relative_path) = required_string_param(&request, "relativePath")
                    else {
                        return error_response(
                            request,
                            "invalid_workspace_path",
                            false,
                            workspace_revision,
                        );
                    };
                    if vityod_workspace::validate_relative_path(&relative_path).is_err() {
                        return error_response(
                            request,
                            "workspace_root_escape",
                            false,
                            workspace_revision,
                        );
                    }
                    match state.durable.read_document(&workspace_id, &relative_path) {
                        Ok(Some(document)) => match String::from_utf8(document.contents) {
                            Ok(contents) => json!({
                                "contents": contents,
                                "documentRevision": document.revision,
                                "workspaceRevision": workspace_revision,
                                "encoding": document.encoding,
                            }),
                            Err(_) => {
                                return error_response(
                                    request,
                                    "document_not_utf8",
                                    false,
                                    workspace_revision,
                                );
                            }
                        },
                        Ok(None) => {
                            return error_response(
                                request,
                                "document_missing",
                                false,
                                workspace_revision,
                            );
                        }
                        Err(_) => {
                            return error_response(
                                request,
                                "durable_state_unavailable",
                                true,
                                workspace_revision,
                            );
                        }
                    }
                }
                "workspace.proposeEdit" => {
                    let Some(relative_path) = required_string_param(&request, "relativePath")
                    else {
                        return error_response(
                            request,
                            "invalid_workspace_path",
                            false,
                            workspace_revision,
                        );
                    };
                    if vityod_workspace::validate_relative_path(&relative_path).is_err() {
                        return error_response(
                            request,
                            "workspace_root_escape",
                            false,
                            workspace_revision,
                        );
                    }
                    json!({
                        "proposal": {
                            "relativePath": relative_path,
                            "expectedWorkspaceRevision": revision,
                            "requiresPreview": true,
                            "requiresTransactionCommit": true,
                        }
                    })
                }
                _ => {
                    return error_response(
                        request,
                        "mcp_tool_not_declared",
                        false,
                        workspace_revision,
                    );
                }
            }
        }
        method if is_known_method(method) => {
            return error_response(request, "method_not_implemented", false, workspace_revision);
        }
        _ => {
            return error_response(request, "unknown_method", false, workspace_revision);
        }
    };
    let response_workspace_revision = state
        .durable
        .workspace_revision(&durable_workspace_id)
        .unwrap_or(workspace_revision);
    let response = success_response(request.clone(), params, response_workspace_revision);
    let encoded = match response.encode() {
        Ok(encoded) => encoded,
        Err(_) => {
            return error_response(
                request,
                "response_encoding_failed",
                false,
                workspace_revision,
            );
        }
    };
    if !method_uses_durable_receipt(&request.method) {
        return response;
    }
    match state
        .durable
        .record_receipt_once(&durable_receipt_key, None, &encoded)
    {
        Ok(original) => ControlEnvelope::decode(&original).unwrap_or(response),
        Err(_) => error_response(
            request,
            "idempotency_store_unavailable",
            true,
            workspace_revision,
        ),
    }
}

fn handshake_response(request: ControlEnvelope) -> ControlEnvelope {
    success_response(
        request,
        json!({
            "selectedProtocolVersion": PROTOCOL_VERSION,
            "capabilities": SUPPORTED_CAPABILITIES,
        }),
        0,
    )
}

fn required_capabilities(request: &ControlEnvelope) -> Vec<String> {
    request
        .params
        .get("requiredCapabilities")
        .and_then(Value::as_array)
        .map(|values| {
            values
                .iter()
                .filter_map(Value::as_str)
                .map(str::to_owned)
                .collect()
        })
        .unwrap_or_default()
}

fn success_response(
    request: ControlEnvelope,
    params: Value,
    workspace_revision: u64,
) -> ControlEnvelope {
    response_envelope(request, "result", params, workspace_revision)
}

fn error_response(
    request: ControlEnvelope,
    code: &str,
    retryable: bool,
    workspace_revision: u64,
) -> ControlEnvelope {
    error_response_with_context(request, code, retryable, workspace_revision, json!({}))
}

fn error_response_with_context(
    request: ControlEnvelope,
    code: &str,
    retryable: bool,
    workspace_revision: u64,
    context: Value,
) -> ControlEnvelope {
    response_envelope(
        request,
        "error",
        json!({
            "errorCode": code,
            "retryable": retryable,
            "context": context,
            "workspaceRevision": workspace_revision,
        }),
        workspace_revision,
    )
}

fn response_envelope(
    request: ControlEnvelope,
    suffix: &str,
    params: Value,
    workspace_revision: u64,
) -> ControlEnvelope {
    ControlEnvelope {
        protocol_version: PROTOCOL_VERSION,
        method: format!("{}.{}", request.method, suffix),
        request_id: request.request_id,
        client_instance_id: "vityod".into(),
        idempotency_key: request.idempotency_key,
        workspace_id: request.workspace_id,
        workspace_revision: Some(workspace_revision),
        deadline_unix_millis: request.deadline_unix_millis,
        cancellation_id: request.cancellation_id,
        params: params
            .as_object()
            .expect("response params object")
            .clone()
            .into_iter()
            .collect(),
        capabilities: SUPPORTED_CAPABILITIES
            .iter()
            .map(|value| (*value).into())
            .collect(),
        unknown_fields: Default::default(),
    }
}

fn receipt_key(request: &ControlEnvelope) -> String {
    format!(
        "{}\u{1f}{}\u{1f}{}\u{1f}{}",
        request.client_instance_id,
        request.workspace_id.as_deref().unwrap_or("default"),
        request.method,
        request.idempotency_key
    )
}

fn method_uses_durable_receipt(method: &str) -> bool {
    matches!(
        method,
        "workspace.transaction.commit"
            | "workspace.delete"
            | "fs.write"
            | "fs.createDirectory"
            | "fs.delete"
            | "fs.copy"
            | "fs.move"
            | "fs.setExecutable"
            | "buffer.delta"
            | "agent.session.start"
            | "agent.session.revoke"
            | "agent.permission.decide"
    )
}

fn unix_time_millis() -> u64 {
    std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_millis()
        .try_into()
        .unwrap_or(u64::MAX)
}

#[cfg(unix)]
fn process_is_alive(process_id: u32) -> bool {
    let Ok(process_id) = i32::try_from(process_id) else {
        return true;
    };
    // SAFETY: signal 0 performs only an existence/permission check.
    let result = unsafe { libc::kill(process_id, 0) };
    if result == 0 {
        return true;
    }
    std::io::Error::last_os_error().raw_os_error() == Some(libc::EPERM)
}

fn required_string_param(request: &ControlEnvelope, key: &str) -> Option<String> {
    required_string_param_with_limit(request, key, 4096)
}

fn required_string_param_with_limit(
    request: &ControlEnvelope,
    key: &str,
    maximum_bytes: usize,
) -> Option<String> {
    request
        .params
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty() && value.len() <= maximum_bytes)
        .map(str::to_owned)
}

fn file_target_params(request: &ControlEnvelope) -> Option<(String, String)> {
    Some((
        required_string_param(request, "scopeId")?,
        request
            .params
            .get("relativePath")
            .and_then(Value::as_str)
            .filter(|value| value.len() <= 4096)?
            .to_owned(),
    ))
}

fn file_entry_json(entry: FileEntry) -> Value {
    json!({
        "relativePath": entry.relative_path,
        "kind": match entry.kind {
            FileKind::File => "file",
            FileKind::Directory => "directory",
            FileKind::Link => "link",
            FileKind::NotFound => "notFound",
            FileKind::Other => "other",
        },
        "size": entry.size,
        "modifiedUnixMillis": entry.modified_unix_millis,
    })
}

fn file_error_response(
    request: ControlEnvelope,
    error: FileServiceError,
    workspace_revision: u64,
) -> ControlEnvelope {
    let (code, retryable) = match error {
        FileServiceError::InvalidRequest | FileServiceError::InvalidPath => {
            ("invalid_file_request", false)
        }
        FileServiceError::UnknownScope => ("file_scope_unknown", false),
        FileServiceError::UnknownWatch => ("file_watch_unknown", false),
        FileServiceError::RootUnavailable => ("file_scope_unavailable", true),
        FileServiceError::RootEscape => ("workspace_root_escape", false),
        FileServiceError::RootMutationDenied => ("workspace_root_mutation_denied", false),
        FileServiceError::NotFound => ("file_not_found", false),
        FileServiceError::NotFile => ("file_expected", false),
        FileServiceError::NotDirectory => ("directory_expected", false),
        FileServiceError::AlreadyExists => ("file_conflict", false),
        FileServiceError::CapacityExceeded => ("file_capacity_exceeded", true),
        FileServiceError::Unsupported => ("file_operation_unsupported", false),
        FileServiceError::Io => ("file_io_failed", true),
    };
    error_response(request, code, retryable, workspace_revision)
}

fn next_workspace_transaction_id() -> String {
    let sequence = NEXT_WORKSPACE_TRANSACTION_ID.fetch_add(1, Ordering::Relaxed);
    format!("{:x}-{:x}", unix_time_millis(), sequence)
}

fn workspace_transaction_artifact(transaction_id: &str, ordinal: usize, suffix: &str) -> String {
    format!(".vityo/transactions/{transaction_id}/{ordinal}.{suffix}")
}

fn file_exists(
    files: &WorkspaceFileService,
    scope_id: &str,
    relative_path: &str,
) -> Result<bool, FileServiceError> {
    Ok(files.stat(scope_id, relative_path)?.kind != FileKind::NotFound)
}

fn write_recovery_payload(
    files: &WorkspaceFileService,
    scope_id: &str,
    changes: &[DurableDocumentChange],
) -> Result<Value, FileServiceError> {
    let mut seen = HashSet::new();
    let mut mutations = Vec::with_capacity(changes.len());
    for (ordinal, change) in changes.iter().enumerate() {
        if !seen.insert(change.relative_path.as_str()) {
            return Err(FileServiceError::InvalidRequest);
        }
        mutations.push(json!({
            "kind": "write",
            "ordinal": ordinal,
            "relativePath": change.relative_path,
            "previousExisted": file_exists(files, scope_id, &change.relative_path)?,
        }));
    }
    Ok(json!({"schemaVersion": 1, "mutations": mutations}))
}

fn delete_recovery_payload(
    files: &WorkspaceFileService,
    scope_id: &str,
    relative_path: &str,
) -> Result<Value, FileServiceError> {
    Ok(json!({
        "schemaVersion": 1,
        "mutations": [{
            "kind": "delete",
            "ordinal": 0,
            "relativePath": relative_path,
            "previousExisted": file_exists(files, scope_id, relative_path)?,
        }],
    }))
}

fn rename_recovery_payload(
    files: &WorkspaceFileService,
    scope_id: &str,
    source_relative_path: &str,
    target_relative_path: &str,
) -> Result<Value, FileServiceError> {
    Ok(json!({
        "schemaVersion": 1,
        "mutations": [{
            "kind": "rename",
            "ordinal": 0,
            "relativePath": source_relative_path,
            "targetRelativePath": target_relative_path,
            "previousExisted": file_exists(files, scope_id, source_relative_path)?,
            "targetPreviousExisted": file_exists(files, scope_id, target_relative_path)?,
        }],
    }))
}

fn stage_workspace_writes(
    files: &WorkspaceFileService,
    scope_id: &str,
    transaction_id: &str,
    changes: &[DurableDocumentChange],
) -> Result<(), FileServiceError> {
    for (ordinal, change) in changes.iter().enumerate() {
        files.write(
            scope_id,
            &workspace_transaction_artifact(transaction_id, ordinal, "stage"),
            &change.contents,
            true,
            true,
        )?;
    }
    Ok(())
}

fn stage_workspace_intent(
    files: &WorkspaceFileService,
    scope_id: &str,
    transaction_id: &str,
    ordinal: usize,
) -> Result<(), FileServiceError> {
    files.write(
        scope_id,
        &workspace_transaction_artifact(transaction_id, ordinal, "intent"),
        b"prepared",
        true,
        true,
    )
}

fn apply_workspace_transaction(
    files: &WorkspaceFileService,
    scope_id: &str,
    transaction_id: &str,
    recovery_payload: &Value,
) -> Result<(), FileServiceError> {
    let mutations = recovery_payload
        .get("mutations")
        .and_then(Value::as_array)
        .ok_or(FileServiceError::InvalidRequest)?;
    for mutation in mutations {
        let kind = mutation
            .get("kind")
            .and_then(Value::as_str)
            .ok_or(FileServiceError::InvalidRequest)?;
        let ordinal = mutation
            .get("ordinal")
            .and_then(Value::as_u64)
            .and_then(|value| usize::try_from(value).ok())
            .ok_or(FileServiceError::InvalidRequest)?;
        let relative_path = mutation
            .get("relativePath")
            .and_then(Value::as_str)
            .ok_or(FileServiceError::InvalidRequest)?;
        let previous_existed = mutation
            .get("previousExisted")
            .and_then(Value::as_bool)
            .ok_or(FileServiceError::InvalidRequest)?;
        let backup = workspace_transaction_artifact(transaction_id, ordinal, "backup");
        match kind {
            "write" => {
                if previous_existed && file_exists(files, scope_id, relative_path)? {
                    files.move_entity(scope_id, relative_path, &backup, false)?;
                } else if !previous_existed && file_exists(files, scope_id, relative_path)? {
                    return Err(FileServiceError::AlreadyExists);
                }
                files.move_entity(
                    scope_id,
                    &workspace_transaction_artifact(transaction_id, ordinal, "stage"),
                    relative_path,
                    false,
                )?;
            }
            "delete" => {
                if previous_existed && file_exists(files, scope_id, relative_path)? {
                    files.move_entity(scope_id, relative_path, &backup, false)?;
                }
                let intent = workspace_transaction_artifact(transaction_id, ordinal, "intent");
                if file_exists(files, scope_id, &intent)? {
                    files.delete(scope_id, &intent, false)?;
                }
            }
            "rename" => {
                let target_relative_path = mutation
                    .get("targetRelativePath")
                    .and_then(Value::as_str)
                    .ok_or(FileServiceError::InvalidRequest)?;
                let target_previous_existed = mutation
                    .get("targetPreviousExisted")
                    .and_then(Value::as_bool)
                    .ok_or(FileServiceError::InvalidRequest)?;
                let target_backup =
                    workspace_transaction_artifact(transaction_id, ordinal, "target-backup");
                if target_previous_existed && file_exists(files, scope_id, target_relative_path)? {
                    files.move_entity(scope_id, target_relative_path, &target_backup, false)?;
                } else if !target_previous_existed
                    && file_exists(files, scope_id, target_relative_path)?
                {
                    return Err(FileServiceError::AlreadyExists);
                }
                files.move_entity(scope_id, relative_path, target_relative_path, false)?;
                let intent = workspace_transaction_artifact(transaction_id, ordinal, "intent");
                if file_exists(files, scope_id, &intent)? {
                    files.delete(scope_id, &intent, false)?;
                }
            }
            _ => return Err(FileServiceError::InvalidRequest),
        }
    }
    Ok(())
}

fn rollback_workspace_transaction(
    files: &WorkspaceFileService,
    scope_id: &str,
    transaction_id: &str,
    recovery_payload: &Value,
) -> Result<(), FileServiceError> {
    let mutations = recovery_payload
        .get("mutations")
        .and_then(Value::as_array)
        .ok_or(FileServiceError::InvalidRequest)?;
    for mutation in mutations.iter().rev() {
        let kind = mutation
            .get("kind")
            .and_then(Value::as_str)
            .ok_or(FileServiceError::InvalidRequest)?;
        let ordinal = mutation
            .get("ordinal")
            .and_then(Value::as_u64)
            .and_then(|value| usize::try_from(value).ok())
            .ok_or(FileServiceError::InvalidRequest)?;
        let relative_path = mutation
            .get("relativePath")
            .and_then(Value::as_str)
            .ok_or(FileServiceError::InvalidRequest)?;
        let previous_existed = mutation
            .get("previousExisted")
            .and_then(Value::as_bool)
            .ok_or(FileServiceError::InvalidRequest)?;
        let backup = workspace_transaction_artifact(transaction_id, ordinal, "backup");
        let stage = workspace_transaction_artifact(transaction_id, ordinal, "stage");
        if kind == "rename" {
            let target_relative_path = mutation
                .get("targetRelativePath")
                .and_then(Value::as_str)
                .ok_or(FileServiceError::InvalidRequest)?;
            let target_backup =
                workspace_transaction_artifact(transaction_id, ordinal, "target-backup");
            if !file_exists(files, scope_id, relative_path)?
                && file_exists(files, scope_id, target_relative_path)?
            {
                files.move_entity(scope_id, target_relative_path, relative_path, false)?;
            }
            if file_exists(files, scope_id, &target_backup)? {
                if file_exists(files, scope_id, target_relative_path)? {
                    files.delete(scope_id, target_relative_path, true)?;
                }
                files.move_entity(scope_id, &target_backup, target_relative_path, false)?;
            }
        }
        if file_exists(files, scope_id, &backup)? {
            if file_exists(files, scope_id, relative_path)? {
                files.delete(scope_id, relative_path, true)?;
            }
            files.move_entity(scope_id, &backup, relative_path, false)?;
        } else if kind == "write"
            && !previous_existed
            && !file_exists(files, scope_id, &stage)?
            && file_exists(files, scope_id, relative_path)?
        {
            files.delete(scope_id, relative_path, true)?;
        }
        if file_exists(files, scope_id, &stage)? {
            files.delete(scope_id, &stage, false)?;
        }
        let intent = workspace_transaction_artifact(transaction_id, ordinal, "intent");
        if file_exists(files, scope_id, &intent)? {
            files.delete(scope_id, &intent, false)?;
        }
    }
    cleanup_workspace_transaction(files, scope_id, transaction_id)
}

fn cleanup_workspace_transaction(
    files: &WorkspaceFileService,
    scope_id: &str,
    transaction_id: &str,
) -> Result<(), FileServiceError> {
    let directory = format!(".vityo/transactions/{transaction_id}");
    if file_exists(files, scope_id, &directory)? {
        files.delete(scope_id, &directory, true)?;
    }
    Ok(())
}

fn recover_pending_workspace_transactions(
    state: &mut DaemonState,
    workspace_id: &str,
) -> Result<(), String> {
    let pending = state
        .durable
        .pending_workspace_fs_transactions(workspace_id)
        .map_err(|error| format!("workspace journal unavailable: {error:?}"))?;
    for transaction in pending {
        let transaction_directory = format!(".vityo/transactions/{}", transaction.transaction_id);
        if !file_exists(&state.files, workspace_id, &transaction_directory)
            .map_err(|error| format!("workspace recovery scan failed: {error:?}"))?
        {
            return Err("workspace recovery artifacts are unavailable for this root".into());
        }
        let payload: Value = serde_json::from_slice(&transaction.recovery_payload)
            .map_err(|_| "workspace recovery payload is invalid".to_string())?;
        if payload.get("schemaVersion").and_then(Value::as_u64) != Some(1) {
            return Err("workspace recovery payload version is unsupported".into());
        }
        rollback_workspace_transaction(
            &state.files,
            workspace_id,
            &transaction.transaction_id,
            &payload,
        )
        .map_err(|error| format!("workspace rollback failed: {error:?}"))?;
        state
            .durable
            .discard_workspace_fs_transaction(&transaction.transaction_id, workspace_id)
            .map_err(|error| format!("workspace journal cleanup failed: {error:?}"))?;
    }
    if file_exists(&state.files, workspace_id, ".vityo/transactions")
        .map_err(|error| format!("workspace recovery scan failed: {error:?}"))?
    {
        state
            .files
            .delete(workspace_id, ".vityo/transactions", true)
            .map_err(|error| format!("workspace artifact cleanup failed: {error:?}"))?;
    }
    Ok(())
}

fn base64_encode(bytes: &[u8]) -> String {
    const ALPHABET: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut output = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let first = chunk[0];
        let second = chunk.get(1).copied().unwrap_or(0);
        let third = chunk.get(2).copied().unwrap_or(0);
        output.push(ALPHABET[(first >> 2) as usize] as char);
        output.push(ALPHABET[(((first & 0x03) << 4) | (second >> 4)) as usize] as char);
        output.push(if chunk.len() > 1 {
            ALPHABET[(((second & 0x0f) << 2) | (third >> 6)) as usize] as char
        } else {
            '='
        });
        output.push(if chunk.len() > 2 {
            ALPHABET[(third & 0x3f) as usize] as char
        } else {
            '='
        });
    }
    output
}

fn base64_decode(value: &str) -> Result<Vec<u8>, ()> {
    let bytes = value.as_bytes();
    if bytes.len() % 4 != 0 {
        return Err(());
    }
    let mut output = Vec::with_capacity(bytes.len() / 4 * 3);
    for (index, chunk) in bytes.chunks_exact(4).enumerate() {
        let is_last = index + 1 == bytes.len() / 4;
        let first = base64_value(chunk[0]).ok_or(())?;
        let second = base64_value(chunk[1]).ok_or(())?;
        let third = if chunk[2] == b'=' {
            if !is_last || chunk[3] != b'=' {
                return Err(());
            }
            None
        } else {
            Some(base64_value(chunk[2]).ok_or(())?)
        };
        let fourth = if chunk[3] == b'=' {
            if !is_last {
                return Err(());
            }
            None
        } else {
            Some(base64_value(chunk[3]).ok_or(())?)
        };
        if third.is_none() && fourth.is_some() {
            return Err(());
        }
        output.push((first << 2) | (second >> 4));
        if let Some(third) = third {
            output.push((second << 4) | (third >> 2));
            if let Some(fourth) = fourth {
                output.push((third << 6) | fourth);
            }
        }
    }
    Ok(output)
}

fn base64_value(byte: u8) -> Option<u8> {
    match byte {
        b'A'..=b'Z' => Some(byte - b'A'),
        b'a'..=b'z' => Some(byte - b'a' + 26),
        b'0'..=b'9' => Some(byte - b'0' + 52),
        b'+' => Some(62),
        b'/' => Some(63),
        _ => None,
    }
}

fn ordered_event_digest(events: &[vityod_kernel::DurableEventRecord]) -> String {
    const OFFSET_BASIS: u64 = 14_695_981_039_346_656_037;
    const PRIME: u64 = 1_099_511_628_211;
    let mut digest = OFFSET_BASIS;
    for event in events {
        for byte in event.cursor.to_le_bytes() {
            digest = (digest ^ u64::from(byte)).wrapping_mul(PRIME);
        }
        for byte in (event.kind.len() as u64).to_le_bytes() {
            digest = (digest ^ u64::from(byte)).wrapping_mul(PRIME);
        }
        for byte in event.kind.as_bytes() {
            digest = (digest ^ u64::from(*byte)).wrapping_mul(PRIME);
        }
        for byte in event.workspace_revision.to_le_bytes() {
            digest = (digest ^ u64::from(byte)).wrapping_mul(PRIME);
        }
        for byte in (event.payload.len() as u64).to_le_bytes() {
            digest = (digest ^ u64::from(byte)).wrapping_mul(PRIME);
        }
        for byte in &event.payload {
            digest = (digest ^ u64::from(*byte)).wrapping_mul(PRIME);
        }
    }
    format!("{digest:016x}")
}

fn string_list_param(request: &ControlEnvelope, key: &str) -> Option<Vec<String>> {
    let values = request.params.get(key)?.as_array()?;
    if values.len() > 256 {
        return None;
    }
    values
        .iter()
        .map(|value| {
            value
                .as_str()
                .filter(|value| value.len() <= 16 * 1024)
                .map(str::to_owned)
        })
        .collect()
}

fn git_launch_params(request: &ControlEnvelope) -> Option<(Vec<String>, Option<Vec<u8>>)> {
    let operation = required_string_param(request, "operation")?;
    let paths = git_paths_param(request)?;
    let launch = match operation.as_str() {
        "status" if paths.is_empty() => (
            vec![
                "status".to_owned(),
                "--porcelain=v1".to_owned(),
                "--branch".to_owned(),
            ],
            None,
        ),
        "diff" if paths.is_empty() => {
            let path = required_git_path_param(request, "path")?;
            (vec!["diff".to_owned(), "--".to_owned(), path], None)
        }
        "stage" if !paths.is_empty() => {
            let mut arguments = vec!["add".to_owned(), "--".to_owned()];
            arguments.extend(paths);
            (arguments, None)
        }
        "unstage" if !paths.is_empty() => {
            let mut arguments = vec!["restore".to_owned(), "--staged".to_owned(), "--".to_owned()];
            arguments.extend(paths);
            (arguments, None)
        }
        "discard" if !paths.is_empty() => {
            let mut arguments = vec!["restore".to_owned(), "--".to_owned()];
            arguments.extend(paths);
            (arguments, None)
        }
        "commit" => {
            let message = required_string_param_with_limit(request, "message", 64 * 1024)?;
            let mut arguments = vec![
                "commit".to_owned(),
                "--file=-".to_owned(),
                "--cleanup=strip".to_owned(),
            ];
            if !paths.is_empty() {
                arguments.push("--".to_owned());
                arguments.extend(paths);
            }
            (arguments, Some(format!("{message}\n").into_bytes()))
        }
        "patch" if paths.is_empty() => {
            let action = required_string_param(request, "action")?;
            let patch = required_string_param_with_limit(request, "patch", 1024 * 1024)?;
            let arguments = match action.as_str() {
                "stage" => vec![
                    "apply".to_owned(),
                    "--cached".to_owned(),
                    "--whitespace=nowarn".to_owned(),
                    "-".to_owned(),
                ],
                "unstage" => vec![
                    "apply".to_owned(),
                    "--cached".to_owned(),
                    "--reverse".to_owned(),
                    "--whitespace=nowarn".to_owned(),
                    "-".to_owned(),
                ],
                "discard" => vec![
                    "apply".to_owned(),
                    "--reverse".to_owned(),
                    "--whitespace=nowarn".to_owned(),
                    "-".to_owned(),
                ],
                _ => return None,
            };
            (arguments, Some(patch.into_bytes()))
        }
        "branchCurrent" if paths.is_empty() => {
            (vec!["branch".to_owned(), "--show-current".to_owned()], None)
        }
        "branches" if paths.is_empty() => (
            vec!["branch".to_owned(), "--format=%(refname:short)".to_owned()],
            None,
        ),
        "switch" if paths.is_empty() => {
            let branch = required_string_param(request, "branch")?;
            if branch.starts_with('-') || branch.contains(['\r', '\n', '\0']) {
                return None;
            }
            (vec!["switch".to_owned(), branch], None)
        }
        "history" if paths.is_empty() => {
            let limit = request
                .params
                .get("limit")
                .and_then(Value::as_u64)
                .filter(|limit| (1..=1000).contains(limit))?;
            (
                vec![
                    "log".to_owned(),
                    "--date=iso-strict".to_owned(),
                    "-n".to_owned(),
                    limit.to_string(),
                    "--format=%H%x1f%h%x1f%an%x1f%ad%x1f%s".to_owned(),
                ],
                None,
            )
        }
        _ => return None,
    };
    Some(launch)
}

fn tool_process_response(
    tasks: &mut vityod_runtime::ManagedTaskRegistry,
    request: &ControlEnvelope,
    prefix: &str,
) -> Result<Value, &'static str> {
    let action = required_string_param(request, "action").ok_or("invalid_tool_request")?;
    let task_id = required_string_param(request, "taskId").ok_or("invalid_tool_task")?;
    let internal_task_id = format!("{prefix}:{task_id}");
    match action.as_str() {
        "start" => {
            let executable =
                required_string_param(request, "executable").ok_or("invalid_tool_executable")?;
            let arguments = string_list_param(request, "arguments").unwrap_or_default();
            let environment = string_map_param(request, "environment").unwrap_or_default();
            let working_directory = request
                .params
                .get("workingDirectory")
                .and_then(Value::as_str)
                .map(std::path::PathBuf::from);
            let standard_input = request
                .params
                .get("standardInput")
                .and_then(Value::as_str)
                .map(|value| value.as_bytes().to_vec());
            let timeout_millis = request
                .params
                .get("timeoutMillis")
                .and_then(Value::as_u64)
                .unwrap_or(30_000)
                .clamp(1, 30 * 60 * 1000);
            tasks
                .start(TaskLaunch {
                    id: internal_task_id,
                    executable: std::path::PathBuf::from(executable),
                    arguments,
                    working_directory,
                    environment,
                    standard_input,
                    timeout: std::time::Duration::from_millis(timeout_millis),
                })
                .map_err(task_error_code)?;
            Ok(json!({"state": "running", "taskId": task_id}))
        }
        "output" => {
            let snapshot = tasks.snapshot(&internal_task_id).map_err(task_error_code)?;
            let stdout = String::from_utf8(snapshot.stdout).map_err(|_| "tool_output_not_utf8")?;
            let stderr = String::from_utf8(snapshot.stderr).map_err(|_| "tool_output_not_utf8")?;
            Ok(json!({
                "running": snapshot.running,
                "timedOut": snapshot.timed_out,
                "exitCode": snapshot.exit_code,
                "stdout": stdout,
                "stderr": stderr,
                "stdoutTruncated": snapshot.stdout_truncated,
                "stderrTruncated": snapshot.stderr_truncated,
                "durationMillis": snapshot.duration_millis,
            }))
        }
        "close" => {
            tasks.remove(&internal_task_id).map_err(task_error_code)?;
            Ok(json!({"state": "closed"}))
        }
        _ => Err("invalid_tool_request"),
    }
}

fn git_paths_param(request: &ControlEnvelope) -> Option<Vec<String>> {
    let Some(values) = request.params.get("paths") else {
        return Some(Vec::new());
    };
    let values = values.as_array()?;
    if values.len() > 256 {
        return None;
    }
    values
        .iter()
        .map(|value| {
            value
                .as_str()
                .filter(|value| {
                    !value.starts_with('-')
                        && value.len() <= 4096
                        && vityod_workspace::validate_relative_path(value).is_ok()
                })
                .map(str::to_owned)
        })
        .collect()
}

fn required_git_path_param(request: &ControlEnvelope, key: &str) -> Option<String> {
    required_string_param(request, key).filter(|value| {
        !value.starts_with('-') && vityod_workspace::validate_relative_path(value).is_ok()
    })
}

fn resolve_path_executable(name: &str) -> Option<std::path::PathBuf> {
    if name.is_empty() || name.contains(std::path::MAIN_SEPARATOR) {
        return None;
    }
    let executable_name = if cfg!(windows) {
        format!("{name}.exe")
    } else {
        name.to_owned()
    };
    env::var_os("PATH")
        .into_iter()
        .flat_map(|value| env::split_paths(&value).collect::<Vec<_>>())
        .map(|directory| directory.join(&executable_name))
        .find_map(|candidate| {
            candidate
                .is_file()
                .then(|| candidate.canonicalize().ok())
                .flatten()
        })
}

fn string_map_param(
    request: &ControlEnvelope,
    key: &str,
) -> Option<std::collections::HashMap<String, String>> {
    let values = request.params.get(key)?.as_object()?;
    if values.len() > 256 {
        return None;
    }
    values
        .iter()
        .map(|(key, value)| {
            value
                .as_str()
                .filter(|value| value.len() <= 64 * 1024)
                .map(|value| (key.clone(), value.to_owned()))
        })
        .collect()
}

fn u32_param(request: &ControlEnvelope, key: &str) -> Option<u32> {
    request
        .params
        .get(key)
        .and_then(Value::as_u64)
        .and_then(|value| u32::try_from(value).ok())
}

fn byte_list_param(request: &ControlEnvelope, key: &str) -> Option<Vec<u8>> {
    let values = request.params.get(key)?.as_array()?;
    if values.is_empty() || values.len() > 1024 * 1024 {
        return None;
    }
    values
        .iter()
        .map(|value| value.as_u64().and_then(|value| u8::try_from(value).ok()))
        .collect()
}

fn bounded_u16_param(request: &ControlEnvelope, key: &str) -> Option<u16> {
    request
        .params
        .get(key)
        .and_then(Value::as_u64)
        .filter(|value| *value > 0)
        .and_then(|value| u16::try_from(value).ok())
}

fn pty_error_code(error: vityod_runtime::PtyRuntimeError) -> &'static str {
    use vityod_runtime::PtyRuntimeError;
    match error {
        PtyRuntimeError::InvalidRequest => "invalid_pty_request",
        PtyRuntimeError::CapacityExceeded => "pty_capacity_exceeded",
        PtyRuntimeError::StartFailed => "pty_start_failed",
        PtyRuntimeError::UnknownSession => "unknown_pty_session",
        PtyRuntimeError::WriteFailed => "pty_write_failed",
        PtyRuntimeError::ResizeFailed => "pty_resize_failed",
        PtyRuntimeError::OutputUnavailable => "pty_output_unavailable",
        PtyRuntimeError::TerminateFailed => "pty_terminate_failed",
    }
}

fn task_error_code(error: vityod_runtime::TaskRuntimeError) -> &'static str {
    use vityod_runtime::TaskRuntimeError;
    match error {
        TaskRuntimeError::InvalidRequest => "invalid_task_request",
        TaskRuntimeError::CapacityExceeded => "task_capacity_exceeded",
        TaskRuntimeError::StartFailed => "task_start_failed",
        TaskRuntimeError::UnknownTask => "unknown_task",
        TaskRuntimeError::WriteFailed => "task_input_failed",
        TaskRuntimeError::PollFailed => "task_poll_failed",
        TaskRuntimeError::TerminateFailed => "task_terminate_failed",
        TaskRuntimeError::TaskRunning => "task_still_running",
    }
}

fn acp_error_code(error: AcpError) -> &'static str {
    match error {
        AcpError::InvalidRequest => "invalid_agent_request",
        AcpError::WorkspaceMismatch => "session_workspace_mismatch",
        AcpError::CapacityExceeded => "agent_capacity_exceeded",
        AcpError::StartFailed => "agent_start_failed",
        AcpError::UnknownAgent => "unknown_agent",
        AcpError::UnknownSession => "unknown_agent_session",
        AcpError::UnknownPermission => "unknown_permission",
        AcpError::PermissionAlreadyResolved => "permission_already_resolved",
        AcpError::UnsupportedProtocol => "unsupported_version",
        AcpError::CapabilityDenied => "capability_revoked",
        AcpError::SessionCollision => "session_collision",
        AcpError::PromptInProgress => "prompt_in_progress",
        AcpError::NoPromptInProgress => "no_prompt_in_progress",
        AcpError::MessageTooLarge => "message_too_large",
        AcpError::MalformedMessage => "malformed_message",
        AcpError::RemoteError => "remote_error",
        AcpError::TimedOut => "request_timeout",
        AcpError::ProcessExited => "process_failed",
        AcpError::TransportFailed => "transport_closed",
        AcpError::ResumeGap => "agent_event_cursor_pruned",
    }
}

fn bounded_request_timeout(request: &ControlEnvelope) -> std::time::Duration {
    let remaining = request
        .deadline_unix_millis
        .saturating_sub(unix_time_millis())
        .clamp(1, 30_000);
    std::time::Duration::from_millis(remaining)
}

fn byte_process_error_code(error: vityod_runtime::ByteProcessError) -> &'static str {
    use vityod_runtime::ByteProcessError;
    match error {
        ByteProcessError::InvalidRequest => "invalid_protocol_process_request",
        ByteProcessError::CapacityExceeded => "protocol_process_capacity_exceeded",
        ByteProcessError::StartFailed => "protocol_process_start_failed",
        ByteProcessError::UnknownProcess => "unknown_protocol_process",
        ByteProcessError::NotRunning => "protocol_process_not_running",
        ByteProcessError::WriteFailed => "protocol_process_write_failed",
        ByteProcessError::PollFailed => "protocol_process_poll_failed",
        ByteProcessError::TerminateFailed => "protocol_process_terminate_failed",
    }
}

fn contains_sensitive_input(values: &std::collections::BTreeMap<String, Value>) -> bool {
    values
        .iter()
        .any(|(key, value)| is_sensitive_key(key) || contains_sensitive_value(value, 0))
}

fn contains_sensitive_value(value: &Value, depth: usize) -> bool {
    if depth >= 32 {
        return true;
    }
    match value {
        Value::Object(values) => values.iter().any(|(key, value)| {
            is_sensitive_key(key) || contains_sensitive_value(value, depth + 1)
        }),
        Value::Array(values) => values
            .iter()
            .any(|value| contains_sensitive_value(value, depth + 1)),
        Value::String(value) => {
            let lower = value.to_ascii_lowercase();
            lower.starts_with("bearer ") || lower.contains("access_token=")
        }
        _ => false,
    }
}

fn is_sensitive_key(key: &str) -> bool {
    let lower = key.to_ascii_lowercase();
    [
        "authorization",
        "cookie",
        "credential",
        "password",
        "secret",
        "token",
    ]
    .iter()
    .any(|fragment| lower.contains(fragment))
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::io::Cursor;
    use std::path::PathBuf;

    struct TestDirectory(PathBuf);

    impl TestDirectory {
        fn new(label: &str) -> Self {
            let path = std::env::temp_dir().join(format!(
                "vityod-crash-recovery-{label}-{}-{}",
                std::process::id(),
                NEXT_WORKSPACE_TRANSACTION_ID.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir(&path).unwrap();
            Self(path)
        }
    }

    impl Drop for TestDirectory {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn recovery_state(root: &TestDirectory) -> DaemonState {
        recovery_state_with_store(root, DurableStateStore::open_in_memory(16).unwrap())
    }

    fn recovery_state_with_store(root: &TestDirectory, durable: DurableStateStore) -> DaemonState {
        let mut state = DaemonState {
            runtime: ServiceRuntime::default(),
            durable,
            files: WorkspaceFileService::default(),
        };
        state.files.open_scope("workspace", &root.0).unwrap();
        state
    }

    struct ScriptedConnection {
        input: Cursor<Vec<u8>>,
        output: Vec<u8>,
    }

    impl Read for ScriptedConnection {
        fn read(&mut self, buffer: &mut [u8]) -> std::io::Result<usize> {
            self.input.read(buffer)
        }
    }

    impl Write for ScriptedConnection {
        fn write(&mut self, buffer: &[u8]) -> std::io::Result<usize> {
            self.output.extend_from_slice(buffer);
            Ok(buffer.len())
        }

        fn flush(&mut self) -> std::io::Result<()> {
            Ok(())
        }
    }

    fn control_request(
        method: &str,
        sequence: u64,
        cancellation_id: Option<&str>,
        params: Value,
    ) -> Vec<u8> {
        let envelope = ControlEnvelope {
            protocol_version: PROTOCOL_VERSION,
            method: method.to_owned(),
            request_id: Some(format!("request-{sequence}")),
            client_instance_id: "conformance-client".into(),
            idempotency_key: format!("key-{sequence}"),
            workspace_id: None,
            workspace_revision: None,
            deadline_unix_millis: u64::MAX,
            cancellation_id: cancellation_id.map(str::to_owned),
            params: params.as_object().unwrap().clone().into_iter().collect(),
            capabilities: vec![],
            unknown_fields: Default::default(),
        };
        let payload = envelope.encode().unwrap();
        let header = FrameHeader {
            version: PROTOCOL_VERSION,
            kind: FrameKind::Control,
            flags: 0,
            stream_id: 0,
            sequence,
            payload_length: payload.len() as u32,
        }
        .encode()
        .unwrap();
        [header.as_slice(), payload.as_slice()].concat()
    }

    fn response_methods(bytes: &[u8]) -> Vec<ControlEnvelope> {
        let mut cursor = 0;
        let mut responses = vec![];
        while cursor < bytes.len() {
            let header = FrameHeader::decode(&bytes[cursor..cursor + FRAME_HEADER_BYTES]).unwrap();
            cursor += FRAME_HEADER_BYTES;
            let end = cursor + header.payload_length as usize;
            responses.push(ControlEnvelope::decode(&bytes[cursor..end]).unwrap());
            cursor = end;
        }
        responses
    }

    #[test]
    fn malformed_and_partial_peers_do_not_block_a_healthy_sibling() {
        let root = TestDirectory::new("peer-isolation");
        let runtime = Arc::new(Mutex::new(recovery_state(&root)));
        let mut malformed_header = FrameHeader {
            version: PROTOCOL_VERSION,
            kind: FrameKind::Control,
            flags: 0,
            stream_id: 0,
            sequence: 1,
            payload_length: 0,
        }
        .encode()
        .unwrap();
        malformed_header[0] = 0;
        malformed_header[1] = 2;
        let mut malformed = ScriptedConnection {
            input: Cursor::new(malformed_header.to_vec()),
            output: vec![],
        };
        assert!(handle_connection(&mut malformed, &runtime).is_err());

        let mut partial = ScriptedConnection {
            input: Cursor::new(vec![0, 1, 1]),
            output: vec![],
        };
        assert!(handle_connection(&mut partial, &runtime).is_ok());

        let mut healthy = ScriptedConnection {
            input: Cursor::new(control_request(
                "handshake.negotiate",
                1,
                None,
                json!({
                    "minimumProtocolVersion": 1,
                    "maximumProtocolVersion": 1,
                    "requiredCapabilities": ["event.resume"]
                }),
            )),
            output: vec![],
        };
        handle_connection(&mut healthy, &runtime).unwrap();
        let responses = response_methods(&healthy.output);
        assert_eq!(responses.len(), 1);
        assert_eq!(responses[0].method, "handshake.negotiate.result");
    }

    #[test]
    fn cancellation_is_connection_scoped_and_checked_before_effect() {
        let root = TestDirectory::new("cancellation");
        let runtime = Arc::new(Mutex::new(recovery_state(&root)));
        let mut input = control_request("handshake.negotiate", 1, None, json!({}));
        input.extend(control_request(
            "cancellation.cancel",
            2,
            None,
            json!({"cancellationId": "cancel-me"}),
        ));
        input.extend(control_request(
            "health.get",
            3,
            Some("cancel-me"),
            json!({}),
        ));
        let mut connection = ScriptedConnection {
            input: Cursor::new(input),
            output: vec![],
        };
        handle_connection(&mut connection, &runtime).unwrap();
        let responses = response_methods(&connection.output);
        assert_eq!(responses.len(), 3);
        assert_eq!(responses[1].method, "cancellation.cancel.result");
        assert_eq!(responses[2].method, "health.get.error");
        assert_eq!(
            responses[2].params.get("errorCode"),
            Some(&json!("cancelled"))
        );
    }

    #[cfg(unix)]
    #[test]
    fn wrong_user_peer_is_rejected_before_request_acceptance() {
        let owner = unsafe { libc::geteuid() };
        assert!(peer_user_is_owner(owner, owner));
        assert!(!peer_user_is_owner(owner, owner.wrapping_add(1)));
    }

    #[test]
    fn pending_write_rolls_disk_back_before_journal_is_discarded() {
        let root = TestDirectory::new("write");
        let state_root = TestDirectory::new("write-state");
        let state_path = state_root.0.join("state.sqlite3");
        let mut state =
            recovery_state_with_store(&root, DurableStateStore::open(&state_path, 16).unwrap());
        state
            .files
            .write("workspace", "main.styio", b"before", true, true)
            .unwrap();
        let changes = vec![DurableDocumentChange {
            relative_path: "main.styio".into(),
            expected_document_revision: 0,
            contents: b"after".to_vec(),
            encoding: Some("utf-8".into()),
        }];
        let payload = write_recovery_payload(&state.files, "workspace", &changes).unwrap();
        stage_workspace_writes(&state.files, "workspace", "write-tx", &changes).unwrap();
        state
            .durable
            .prepare_workspace_fs_transaction(
                "write-tx",
                "workspace",
                0,
                &serde_json::to_vec(&payload).unwrap(),
            )
            .unwrap();
        apply_workspace_transaction(&state.files, "workspace", "write-tx", &payload).unwrap();
        assert_eq!(
            state.files.read("workspace", "main.styio").unwrap(),
            b"after"
        );

        drop(state);
        let mut state =
            recovery_state_with_store(&root, DurableStateStore::open(&state_path, 16).unwrap());

        recover_pending_workspace_transactions(&mut state, "workspace").unwrap();

        assert_eq!(
            state.files.read("workspace", "main.styio").unwrap(),
            b"before"
        );
        assert!(
            state
                .durable
                .pending_workspace_fs_transactions("workspace")
                .unwrap()
                .is_empty()
        );
    }

    #[test]
    fn pending_delete_restores_the_fsynced_backup() {
        let root = TestDirectory::new("delete");
        let mut state = recovery_state(&root);
        state
            .files
            .write("workspace", "remove.styio", b"keep", true, true)
            .unwrap();
        let payload = delete_recovery_payload(&state.files, "workspace", "remove.styio").unwrap();
        stage_workspace_intent(&state.files, "workspace", "delete-tx", 0).unwrap();
        state
            .durable
            .prepare_workspace_fs_transaction(
                "delete-tx",
                "workspace",
                0,
                &serde_json::to_vec(&payload).unwrap(),
            )
            .unwrap();
        apply_workspace_transaction(&state.files, "workspace", "delete-tx", &payload).unwrap();
        assert!(!file_exists(&state.files, "workspace", "remove.styio").unwrap());

        recover_pending_workspace_transactions(&mut state, "workspace").unwrap();

        assert_eq!(
            state.files.read("workspace", "remove.styio").unwrap(),
            b"keep"
        );
    }

    #[test]
    fn pending_rename_restores_source_and_overwritten_target() {
        let root = TestDirectory::new("rename");
        let mut state = recovery_state(&root);
        state
            .files
            .write("workspace", "old.styio", b"source", true, true)
            .unwrap();
        state
            .files
            .write("workspace", "new.styio", b"target", true, true)
            .unwrap();
        let payload =
            rename_recovery_payload(&state.files, "workspace", "old.styio", "new.styio").unwrap();
        stage_workspace_intent(&state.files, "workspace", "rename-tx", 0).unwrap();
        state
            .durable
            .prepare_workspace_fs_transaction(
                "rename-tx",
                "workspace",
                0,
                &serde_json::to_vec(&payload).unwrap(),
            )
            .unwrap();
        apply_workspace_transaction(&state.files, "workspace", "rename-tx", &payload).unwrap();
        assert_eq!(
            state.files.read("workspace", "new.styio").unwrap(),
            b"source"
        );

        recover_pending_workspace_transactions(&mut state, "workspace").unwrap();

        assert_eq!(
            state.files.read("workspace", "old.styio").unwrap(),
            b"source"
        );
        assert_eq!(
            state.files.read("workspace", "new.styio").unwrap(),
            b"target"
        );
    }

    #[test]
    fn ordered_event_digest_matches_the_client_fixture() {
        let events = vec![vityod_kernel::DurableEventRecord {
            cursor: 1,
            kind: "workspace.transaction.committed".to_owned(),
            workspace_revision: 2,
            payload: b"workspace-commit".to_vec(),
        }];
        assert_eq!(ordered_event_digest(&events), "bf3851d909f822ed");
        assert_eq!(ordered_event_digest(&[]), "cbf29ce484222325");
    }
}
