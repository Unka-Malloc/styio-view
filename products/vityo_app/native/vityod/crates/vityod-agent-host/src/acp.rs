use std::collections::{HashMap, HashSet, VecDeque};
use std::time::{Duration, Instant};

use serde_json::{Map, Value, json};

use crate::{AgentProcessError, AgentProcessLaunch, SupervisedAgentRegistry};

const ACP_PROTOCOL_VERSION: u64 = 1;
const MAX_EVENTS_PER_SESSION: usize = 4096;

#[derive(Debug, Clone, PartialEq)]
pub struct AcpConnectionSnapshot {
    pub agent_id: String,
    pub protocol_version: u64,
    pub generation: u64,
    pub capabilities: Vec<String>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AcpSessionSnapshot {
    pub session_id: String,
    pub agent_id: String,
    pub generation: u64,
    pub remote_session_id: String,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AcpEvent {
    pub sequence: u64,
    pub kind: String,
    pub text: Option<String>,
    pub payload: Value,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AcpPermissionRequest {
    pub permission_id: String,
    pub agent_id: String,
    pub session_id: String,
    pub tool_call_id: String,
    pub tool_call_title: Option<String>,
    pub tool_call_kind: Option<String>,
    pub options: Vec<String>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct AcpPollResult {
    pub events: Vec<AcpEvent>,
    pub permissions: Vec<AcpPermissionRequest>,
    pub prompt_result: Option<Value>,
    pub process_exit_code: Option<i32>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum AcpError {
    InvalidRequest,
    WorkspaceMismatch,
    CapacityExceeded,
    StartFailed,
    UnknownAgent,
    UnknownSession,
    UnknownPermission,
    PermissionAlreadyResolved,
    UnsupportedProtocol,
    CapabilityDenied,
    SessionCollision,
    PromptInProgress,
    NoPromptInProgress,
    MessageTooLarge,
    MalformedMessage,
    RemoteError,
    TimedOut,
    ProcessExited,
    TransportFailed,
    ResumeGap,
}

pub struct AcpRuntime {
    processes: SupervisedAgentRegistry,
    connections: HashMap<String, AcpConnection>,
    sessions: HashMap<String, AcpSession>,
    permissions: HashMap<String, PendingPermission>,
    next_generation: u64,
    next_session: u64,
}

struct AcpConnection {
    generation: u64,
    next_request: u64,
    maximum_message_bytes: usize,
    capabilities: HashSet<String>,
    allowed_extensions: HashSet<String>,
}

struct AcpSession {
    session_id: String,
    agent_id: String,
    generation: u64,
    remote_session_id: String,
    workspace_path: String,
    next_sequence: u64,
    events: VecDeque<AcpEvent>,
    prompt_request_id: Option<String>,
    prompt_result: Option<Value>,
}

struct PendingPermission {
    permission_id: String,
    agent_id: String,
    session_id: String,
    rpc_id: Value,
    tool_call_id: String,
    tool_call_title: Option<String>,
    tool_call_kind: Option<String>,
    option_ids: HashMap<String, String>,
}

impl Default for AcpRuntime {
    fn default() -> Self {
        Self::new(64, 8 * 1024 * 1024, 1024 * 1024)
    }
}

impl AcpRuntime {
    pub fn new(
        maximum_processes: usize,
        maximum_buffered_bytes: usize,
        maximum_message_bytes: usize,
    ) -> Self {
        Self {
            processes: SupervisedAgentRegistry::new(
                maximum_processes,
                maximum_buffered_bytes,
                maximum_message_bytes,
            ),
            connections: HashMap::new(),
            sessions: HashMap::new(),
            permissions: HashMap::new(),
            next_generation: 1,
            next_session: 1,
        }
    }

    pub fn connect(
        &mut self,
        launch: AgentProcessLaunch,
        allowed_extensions: impl IntoIterator<Item = String>,
        maximum_message_bytes: usize,
        timeout: Duration,
    ) -> Result<AcpConnectionSnapshot, AcpError> {
        if timeout.is_zero()
            || maximum_message_bytes == 0
            || maximum_message_bytes > 1024 * 1024
            || self.connections.contains_key(&launch.agent_id)
        {
            return Err(AcpError::InvalidRequest);
        }
        let agent_id = launch.agent_id.clone();
        self.processes.start(launch).map_err(map_process_error)?;
        let generation = self.next_generation;
        self.next_generation = self.next_generation.saturating_add(1);
        let allowed_extensions = allowed_extensions
            .into_iter()
            .filter(|capability| capability.starts_with("_vityo.dev/") && capability.len() <= 256)
            .collect::<HashSet<_>>();
        self.connections.insert(
            agent_id.clone(),
            AcpConnection {
                generation,
                next_request: 1,
                maximum_message_bytes,
                capabilities: HashSet::new(),
                allowed_extensions,
            },
        );
        let result = self.request_and_wait(
            &agent_id,
            "initialize",
            json!({
                "protocolVersion": ACP_PROTOCOL_VERSION,
                "clientInfo": {"name": "vityod", "version": "0.1.0"},
                "clientCapabilities": {
                    "fs": {"readTextFile": false, "writeTextFile": false},
                    "terminal": false
                }
            }),
            timeout,
        );
        let result = match result {
            Ok(result) => result,
            Err(error) => {
                self.connections.remove(&agent_id);
                let _ = self.processes.close(&agent_id);
                return Err(error);
            }
        };
        if result.get("protocolVersion").and_then(Value::as_u64) != Some(ACP_PROTOCOL_VERSION) {
            self.connections.remove(&agent_id);
            let _ = self.processes.close(&agent_id);
            return Err(AcpError::UnsupportedProtocol);
        }
        let capabilities = decode_capabilities(
            &result,
            &self
                .connections
                .get(&agent_id)
                .expect("connection inserted before initialize")
                .allowed_extensions,
        );
        self.connections
            .get_mut(&agent_id)
            .expect("connection inserted before initialize")
            .capabilities = capabilities;
        self.connection(&agent_id)
    }

    pub fn connection(&self, agent_id: &str) -> Result<AcpConnectionSnapshot, AcpError> {
        let connection = self
            .connections
            .get(agent_id)
            .ok_or(AcpError::UnknownAgent)?;
        let mut capabilities = connection.capabilities.iter().cloned().collect::<Vec<_>>();
        capabilities.sort_unstable();
        Ok(AcpConnectionSnapshot {
            agent_id: agent_id.to_owned(),
            protocol_version: ACP_PROTOCOL_VERSION,
            generation: connection.generation,
            capabilities,
        })
    }

    pub fn new_session(
        &mut self,
        agent_id: &str,
        workspace_path: &str,
        timeout: Duration,
    ) -> Result<AcpSessionSnapshot, AcpError> {
        validate_workspace_path(workspace_path)?;
        let result = self.request_and_wait(
            agent_id,
            "session/new",
            json!({"cwd": workspace_path, "mcpServers": []}),
            timeout,
        )?;
        let remote_session_id = required_bounded_string(&result, "sessionId", 256)?;
        let generation = self
            .connections
            .get(agent_id)
            .ok_or(AcpError::UnknownAgent)?
            .generation;
        if self.sessions.values().any(|session| {
            session.agent_id == agent_id
                && session.generation == generation
                && session.remote_session_id == remote_session_id
        }) {
            return Err(AcpError::SessionCollision);
        }
        let session_id = format!("agent-session-{}", self.next_session);
        self.next_session = self.next_session.saturating_add(1);
        self.sessions.insert(
            session_id.clone(),
            AcpSession {
                session_id: session_id.clone(),
                agent_id: agent_id.to_owned(),
                generation,
                remote_session_id,
                workspace_path: workspace_path.to_owned(),
                next_sequence: 1,
                events: VecDeque::with_capacity(MAX_EVENTS_PER_SESSION),
                prompt_request_id: None,
                prompt_result: None,
            },
        );
        self.session(&session_id)
    }

    pub fn load_session(
        &mut self,
        session_id: &str,
        workspace_path: &str,
        timeout: Duration,
    ) -> Result<AcpSessionSnapshot, AcpError> {
        validate_workspace_path(workspace_path)?;
        let (agent_id, remote_session_id, expected_workspace_path) = {
            let session = self
                .sessions
                .get(session_id)
                .ok_or(AcpError::UnknownSession)?;
            (
                session.agent_id.clone(),
                session.remote_session_id.clone(),
                session.workspace_path.clone(),
            )
        };
        if workspace_path != expected_workspace_path {
            return Err(AcpError::WorkspaceMismatch);
        }
        let connection = self
            .connections
            .get(&agent_id)
            .ok_or(AcpError::UnknownAgent)?;
        if !connection.capabilities.contains("loadSession") {
            return Err(AcpError::CapabilityDenied);
        }
        let current_generation = connection.generation;
        if self.sessions.values().any(|session| {
            session.session_id != session_id
                && session.agent_id == agent_id
                && session.generation == current_generation
                && session.remote_session_id == remote_session_id
        }) {
            return Err(AcpError::SessionCollision);
        }
        let previous_generation = self
            .sessions
            .get(session_id)
            .expect("session checked before load")
            .generation;
        self.sessions
            .get_mut(session_id)
            .expect("session checked before load")
            .generation = current_generation;
        let result = self.request_and_wait(
            &agent_id,
            "session/load",
            json!({
                "sessionId": remote_session_id,
                "cwd": workspace_path,
                "mcpServers": []
            }),
            timeout,
        );
        let result = match result {
            Ok(result) => result,
            Err(error) => {
                self.sessions
                    .get_mut(session_id)
                    .expect("session retained after failed load")
                    .generation = previous_generation;
                return Err(error);
            }
        };
        if !result.is_null() {
            self.sessions
                .get_mut(session_id)
                .expect("session retained after malformed load")
                .generation = previous_generation;
            return Err(AcpError::MalformedMessage);
        }
        self.append_event(
            session_id,
            "session_state".to_owned(),
            None,
            json!({"status": "active", "restored": true}),
        )?;
        self.session(session_id)
    }

    pub fn session(&self, session_id: &str) -> Result<AcpSessionSnapshot, AcpError> {
        let session = self
            .sessions
            .get(session_id)
            .ok_or(AcpError::UnknownSession)?;
        Ok(AcpSessionSnapshot {
            session_id: session.session_id.clone(),
            agent_id: session.agent_id.clone(),
            generation: session.generation,
            remote_session_id: session.remote_session_id.clone(),
        })
    }

    pub fn start_prompt(&mut self, session_id: &str, text: &str) -> Result<(), AcpError> {
        if text.trim().is_empty() || text.len() > 1024 * 1024 {
            return Err(AcpError::MessageTooLarge);
        }
        let (agent_id, remote_session_id, generation) = {
            let session = self
                .sessions
                .get(session_id)
                .ok_or(AcpError::UnknownSession)?;
            if session.prompt_request_id.is_some() {
                return Err(AcpError::PromptInProgress);
            }
            (
                session.agent_id.clone(),
                session.remote_session_id.clone(),
                session.generation,
            )
        };
        if self
            .connections
            .get(&agent_id)
            .is_none_or(|connection| connection.generation != generation)
        {
            return Err(AcpError::UnknownAgent);
        }
        let request_id = self.allocate_request_id(&agent_id)?;
        self.send_json(
            &agent_id,
            json!({
                "jsonrpc": "2.0",
                "id": request_id,
                "method": "session/prompt",
                "params": {
                    "sessionId": remote_session_id,
                    "prompt": [{"type": "text", "text": text}]
                }
            }),
        )?;
        let session = self
            .sessions
            .get_mut(session_id)
            .expect("session checked before prompt send");
        session.prompt_request_id = Some(request_id);
        session.prompt_result = None;
        Ok(())
    }

    pub fn poll(
        &mut self,
        session_id: &str,
        after_sequence: u64,
    ) -> Result<AcpPollResult, AcpError> {
        let agent_id = self
            .sessions
            .get(session_id)
            .ok_or(AcpError::UnknownSession)?
            .agent_id
            .clone();
        let poll = self
            .processes
            .poll(&agent_id, 128)
            .map_err(map_process_error)?;
        if poll.message_too_large {
            return Err(AcpError::MessageTooLarge);
        }
        if poll.protocol_failed {
            return Err(AcpError::MalformedMessage);
        }
        let maximum_message_bytes = self
            .connections
            .get(&agent_id)
            .ok_or(AcpError::UnknownAgent)?
            .maximum_message_bytes;
        for message in poll.messages {
            if message.len() > maximum_message_bytes {
                return Err(AcpError::MessageTooLarge);
            }
            self.route_message(&agent_id, &message)?;
        }
        let session = self
            .sessions
            .get(session_id)
            .ok_or(AcpError::UnknownSession)?;
        if let Some(first) = session.events.front()
            && after_sequence.saturating_add(1) < first.sequence
        {
            return Err(AcpError::ResumeGap);
        }
        let events = session
            .events
            .iter()
            .filter(|event| event.sequence > after_sequence)
            .cloned()
            .collect();
        let mut permissions = self
            .permissions
            .values()
            .filter(|permission| permission.session_id == session_id)
            .map(PendingPermission::snapshot)
            .collect::<Vec<_>>();
        permissions.sort_unstable_by(|left, right| left.permission_id.cmp(&right.permission_id));
        Ok(AcpPollResult {
            events,
            permissions,
            prompt_result: session.prompt_result.clone(),
            process_exit_code: poll.exit_code,
        })
    }

    pub fn cancel_prompt(&mut self, session_id: &str) -> Result<bool, AcpError> {
        let (agent_id, remote_session_id, active) = {
            let session = self
                .sessions
                .get(session_id)
                .ok_or(AcpError::UnknownSession)?;
            (
                session.agent_id.clone(),
                session.remote_session_id.clone(),
                session.prompt_request_id.is_some(),
            )
        };
        if !active {
            return Ok(false);
        }
        self.send_json(
            &agent_id,
            json!({
                "jsonrpc": "2.0",
                "method": "session/cancel",
                "params": {"sessionId": remote_session_id}
            }),
        )?;
        let permission_ids = self
            .permissions
            .values()
            .filter(|permission| permission.session_id == session_id)
            .map(|permission| permission.permission_id.clone())
            .collect::<Vec<_>>();
        for permission_id in permission_ids {
            let permission = self
                .permissions
                .remove(&permission_id)
                .expect("permission selected from the same map");
            self.send_json(
                &agent_id,
                json!({
                    "jsonrpc": "2.0",
                    "id": permission.rpc_id,
                    "result": {"outcome": {"outcome": "cancelled"}}
                }),
            )?;
        }
        Ok(true)
    }

    pub fn resolve_permission(
        &mut self,
        permission_id: &str,
        decision: &str,
    ) -> Result<(), AcpError> {
        let permission = self
            .permissions
            .remove(permission_id)
            .ok_or(AcpError::UnknownPermission)?;
        let option_kind = match decision {
            "allow_once" => "allow_once",
            "reject_once" | "deny" => "reject_once",
            _ => {
                self.permissions
                    .insert(permission_id.to_owned(), permission);
                return Err(AcpError::InvalidRequest);
            }
        };
        let Some(option_id) = permission.option_ids.get(option_kind) else {
            self.permissions
                .insert(permission_id.to_owned(), permission);
            return Err(AcpError::CapabilityDenied);
        };
        self.send_json(
            &permission.agent_id,
            json!({
                "jsonrpc": "2.0",
                "id": permission.rpc_id,
                "result": {
                    "outcome": {"outcome": "selected", "optionId": option_id}
                }
            }),
        )
    }

    pub fn invoke_extension(
        &mut self,
        agent_id: &str,
        method: &str,
        params: Value,
        timeout: Duration,
    ) -> Result<Value, AcpError> {
        let connection = self
            .connections
            .get(agent_id)
            .ok_or(AcpError::UnknownAgent)?;
        if !method.starts_with("_vityo.dev/") || !connection.capabilities.contains(method) {
            return Err(AcpError::CapabilityDenied);
        }
        self.request_and_wait(agent_id, method, params, timeout)
    }

    pub fn disconnect(&mut self, agent_id: &str) -> Result<i32, AcpError> {
        self.connections
            .remove(agent_id)
            .ok_or(AcpError::UnknownAgent)?;
        self.permissions
            .retain(|_, permission| permission.agent_id != agent_id);
        self.processes.close(agent_id).map_err(map_process_error)
    }

    pub fn active_connection_count(&self) -> usize {
        self.connections.len()
    }

    fn request_and_wait(
        &mut self,
        agent_id: &str,
        method: &str,
        params: Value,
        timeout: Duration,
    ) -> Result<Value, AcpError> {
        if timeout.is_zero() {
            return Err(AcpError::TimedOut);
        }
        let request_id = self.allocate_request_id(agent_id)?;
        self.send_json(
            agent_id,
            json!({
                "jsonrpc": "2.0",
                "id": request_id,
                "method": method,
                "params": params
            }),
        )?;
        let deadline = Instant::now() + timeout;
        loop {
            let poll = self
                .processes
                .poll(agent_id, 128)
                .map_err(map_process_error)?;
            if poll.message_too_large {
                return Err(AcpError::MessageTooLarge);
            }
            if poll.protocol_failed {
                return Err(AcpError::MalformedMessage);
            }
            let maximum_message_bytes = self
                .connections
                .get(agent_id)
                .ok_or(AcpError::UnknownAgent)?
                .maximum_message_bytes;
            for message in poll.messages {
                if message.len() > maximum_message_bytes {
                    return Err(AcpError::MessageTooLarge);
                }
                let value = decode_message(&message)?;
                if value.get("id") == Some(&Value::String(request_id.clone()))
                    && value.get("method").is_none()
                {
                    if let Some(result) = value.get("result") {
                        return Ok(result.clone());
                    }
                    if value.get("error").is_some() {
                        return Err(AcpError::RemoteError);
                    }
                    return Err(AcpError::MalformedMessage);
                }
                self.route_value(agent_id, value)?;
            }
            if poll.exit_code.is_some() {
                return Err(AcpError::ProcessExited);
            }
            if Instant::now() >= deadline {
                return Err(AcpError::TimedOut);
            }
            std::thread::sleep(Duration::from_millis(5));
        }
    }

    fn allocate_request_id(&mut self, agent_id: &str) -> Result<String, AcpError> {
        let connection = self
            .connections
            .get_mut(agent_id)
            .ok_or(AcpError::UnknownAgent)?;
        let request_id = format!(
            "vityod-{}-{}",
            connection.generation, connection.next_request
        );
        connection.next_request = connection.next_request.saturating_add(1);
        Ok(request_id)
    }

    fn send_json(&mut self, agent_id: &str, value: Value) -> Result<(), AcpError> {
        let encoded = serde_json::to_vec(&value).map_err(|_| AcpError::MalformedMessage)?;
        if encoded.len()
            > self
                .connections
                .get(agent_id)
                .ok_or(AcpError::UnknownAgent)?
                .maximum_message_bytes
        {
            return Err(AcpError::MessageTooLarge);
        }
        self.processes
            .send(agent_id, &encoded)
            .map_err(map_process_error)
    }

    fn route_message(&mut self, agent_id: &str, message: &[u8]) -> Result<(), AcpError> {
        self.route_value(agent_id, decode_message(message)?)
    }

    fn route_value(&mut self, agent_id: &str, value: Value) -> Result<(), AcpError> {
        let object = value.as_object().ok_or(AcpError::MalformedMessage)?;
        if object.get("jsonrpc").and_then(Value::as_str) != Some("2.0") {
            return Err(AcpError::MalformedMessage);
        }
        if let Some(method) = object.get("method").and_then(Value::as_str) {
            let params = object.get("params").cloned().unwrap_or_else(|| json!({}));
            if object.contains_key("id") {
                return self.route_inbound_request(agent_id, method, object, params);
            }
            return self.route_notification(agent_id, method, params);
        }
        let Some(id) = object.get("id") else {
            return Err(AcpError::MalformedMessage);
        };
        let id = id.as_str().ok_or(AcpError::MalformedMessage)?;
        let session_id = self
            .sessions
            .values()
            .find(|session| {
                session.agent_id == agent_id && session.prompt_request_id.as_deref() == Some(id)
            })
            .map(|session| session.session_id.clone());
        let Some(session_id) = session_id else {
            return Ok(());
        };
        let result = if let Some(result) = object.get("result") {
            result.clone()
        } else if object.get("error").is_some() {
            json!({"errorCode": "remote_error"})
        } else {
            return Err(AcpError::MalformedMessage);
        };
        let session = self
            .sessions
            .get_mut(&session_id)
            .expect("prompt session selected from the same map");
        session.prompt_result = Some(result);
        session.prompt_request_id = None;
        Ok(())
    }

    fn route_notification(
        &mut self,
        agent_id: &str,
        method: &str,
        params: Value,
    ) -> Result<(), AcpError> {
        match method {
            "session/update" => {
                let remote_session_id = required_bounded_string(&params, "sessionId", 256)?;
                let update = params
                    .get("update")
                    .cloned()
                    .ok_or(AcpError::MalformedMessage)?;
                let kind = required_bounded_string(&update, "sessionUpdate", 256)?;
                let text = update
                    .get("content")
                    .and_then(Value::as_object)
                    .and_then(|content| content.get("text"))
                    .and_then(Value::as_str)
                    .map(str::to_owned);
                let session_id = self.session_id_for_remote(agent_id, &remote_session_id)?;
                self.append_event(&session_id, kind, text, update)
            }
            "_vityo.dev/workspace-change-proposal" => {
                let remote_session_id = required_bounded_string(&params, "sessionId", 256)?;
                let session_id = self.session_id_for_remote(agent_id, &remote_session_id)?;
                self.append_event(&session_id, method.to_owned(), None, params)
            }
            "_vityo.dev/capabilities_changed" => {
                let values = params
                    .get("capabilities")
                    .and_then(Value::as_array)
                    .ok_or(AcpError::MalformedMessage)?;
                let connection = self
                    .connections
                    .get_mut(agent_id)
                    .ok_or(AcpError::UnknownAgent)?;
                let mut capabilities = HashSet::new();
                for value in values {
                    let capability = value.as_str().ok_or(AcpError::MalformedMessage)?;
                    if capability == "loadSession"
                        || connection.allowed_extensions.contains(capability)
                    {
                        capabilities.insert(capability.to_owned());
                    }
                }
                connection.capabilities = capabilities;
                Ok(())
            }
            _ => Ok(()),
        }
    }

    fn route_inbound_request(
        &mut self,
        agent_id: &str,
        method: &str,
        object: &Map<String, Value>,
        params: Value,
    ) -> Result<(), AcpError> {
        let rpc_id = object
            .get("id")
            .cloned()
            .ok_or(AcpError::MalformedMessage)?;
        if method != "session/request_permission" {
            return self.send_json(
                agent_id,
                json!({
                    "jsonrpc": "2.0",
                    "id": rpc_id,
                    "error": {"code": -32601, "message": "method not found"}
                }),
            );
        }
        let remote_session_id = required_bounded_string(&params, "sessionId", 256)?;
        let session_id = self.session_id_for_remote(agent_id, &remote_session_id)?;
        let tool_call = params
            .get("toolCall")
            .and_then(Value::as_object)
            .ok_or(AcpError::MalformedMessage)?;
        let tool_call_id = required_bounded_string_object(tool_call, "toolCallId", 256)?;
        let tool_call_title = optional_bounded_string_object(tool_call, "title", 512)?;
        let tool_call_kind = optional_bounded_string_object(tool_call, "kind", 256)?;
        let options = params
            .get("options")
            .and_then(Value::as_array)
            .filter(|options| !options.is_empty() && options.len() <= 16)
            .ok_or(AcpError::MalformedMessage)?;
        let mut option_ids = HashMap::new();
        for option in options {
            let option = option.as_object().ok_or(AcpError::MalformedMessage)?;
            let kind = required_bounded_string_object(option, "kind", 64)?;
            let option_id = required_bounded_string_object(option, "optionId", 256)?;
            if matches!(kind.as_str(), "allow_once" | "reject_once") {
                option_ids.insert(kind, option_id);
            }
        }
        if option_ids.is_empty() {
            return Err(AcpError::MalformedMessage);
        }
        let permission_id = format!("permission:{}:{}", agent_id, rpc_id);
        if self.permissions.contains_key(&permission_id) {
            return Err(AcpError::MalformedMessage);
        }
        self.permissions.insert(
            permission_id.clone(),
            PendingPermission {
                permission_id,
                agent_id: agent_id.to_owned(),
                session_id,
                rpc_id,
                tool_call_id,
                tool_call_title,
                tool_call_kind,
                option_ids,
            },
        );
        Ok(())
    }

    fn session_id_for_remote(
        &self,
        agent_id: &str,
        remote_session_id: &str,
    ) -> Result<String, AcpError> {
        let generation = self
            .connections
            .get(agent_id)
            .ok_or(AcpError::UnknownAgent)?
            .generation;
        self.sessions
            .values()
            .find(|session| {
                session.agent_id == agent_id
                    && session.generation == generation
                    && session.remote_session_id == remote_session_id
            })
            .map(|session| session.session_id.clone())
            .ok_or(AcpError::UnknownSession)
    }

    fn append_event(
        &mut self,
        session_id: &str,
        kind: String,
        text: Option<String>,
        payload: Value,
    ) -> Result<(), AcpError> {
        if kind.is_empty() {
            return Err(AcpError::MalformedMessage);
        }
        let session = self
            .sessions
            .get_mut(session_id)
            .ok_or(AcpError::UnknownSession)?;
        let event = AcpEvent {
            sequence: session.next_sequence,
            kind,
            text,
            payload,
        };
        session.next_sequence = session.next_sequence.saturating_add(1);
        if session.events.len() == MAX_EVENTS_PER_SESSION {
            session.events.pop_front();
        }
        session.events.push_back(event);
        Ok(())
    }
}

impl PendingPermission {
    fn snapshot(&self) -> AcpPermissionRequest {
        let mut options = self.option_ids.keys().cloned().collect::<Vec<_>>();
        options.sort_unstable();
        AcpPermissionRequest {
            permission_id: self.permission_id.clone(),
            agent_id: self.agent_id.clone(),
            session_id: self.session_id.clone(),
            tool_call_id: self.tool_call_id.clone(),
            tool_call_title: self.tool_call_title.clone(),
            tool_call_kind: self.tool_call_kind.clone(),
            options,
        }
    }
}

fn decode_capabilities(result: &Value, allowed_extensions: &HashSet<String>) -> HashSet<String> {
    let mut capabilities = HashSet::new();
    let Some(agent_capabilities) = result.get("agentCapabilities") else {
        return capabilities;
    };
    if agent_capabilities
        .get("loadSession")
        .and_then(Value::as_bool)
        == Some(true)
    {
        capabilities.insert("loadSession".to_owned());
    }
    let extensions = agent_capabilities
        .pointer("/_meta/vityo.dev/extensions")
        .and_then(Value::as_array)
        .into_iter()
        .flatten()
        .filter_map(Value::as_str)
        .filter(|capability| allowed_extensions.contains(*capability));
    capabilities.extend(extensions.map(str::to_owned));
    capabilities
}

fn decode_message(bytes: &[u8]) -> Result<Value, AcpError> {
    if bytes.is_empty() || bytes.len() > 1024 * 1024 {
        return Err(AcpError::MessageTooLarge);
    }
    let value: Value = serde_json::from_slice(bytes).map_err(|_| AcpError::MalformedMessage)?;
    value.as_object().ok_or(AcpError::MalformedMessage)?;
    Ok(value)
}

fn required_bounded_string(value: &Value, key: &str, maximum: usize) -> Result<String, AcpError> {
    let object = value.as_object().ok_or(AcpError::MalformedMessage)?;
    required_bounded_string_object(object, key, maximum)
}

fn required_bounded_string_object(
    object: &Map<String, Value>,
    key: &str,
    maximum: usize,
) -> Result<String, AcpError> {
    object
        .get(key)
        .and_then(Value::as_str)
        .filter(|value| !value.is_empty() && value.len() <= maximum)
        .map(str::to_owned)
        .ok_or(AcpError::MalformedMessage)
}

fn optional_bounded_string_object(
    object: &Map<String, Value>,
    key: &str,
    maximum: usize,
) -> Result<Option<String>, AcpError> {
    let Some(value) = object.get(key) else {
        return Ok(None);
    };
    value
        .as_str()
        .filter(|value| !value.is_empty() && value.len() <= maximum)
        .map(str::to_owned)
        .map(Some)
        .ok_or(AcpError::MalformedMessage)
}

fn validate_workspace_path(workspace_path: &str) -> Result<(), AcpError> {
    if workspace_path.is_empty() || workspace_path.len() > 32 * 1024 {
        return Err(AcpError::InvalidRequest);
    }
    Ok(())
}

fn map_process_error(error: AgentProcessError) -> AcpError {
    match error {
        AgentProcessError::InvalidLaunch | AgentProcessError::InvalidMessage => {
            AcpError::InvalidRequest
        }
        AgentProcessError::CapacityExceeded => AcpError::CapacityExceeded,
        AgentProcessError::StartFailed => AcpError::StartFailed,
        AgentProcessError::UnknownAgent => AcpError::UnknownAgent,
        AgentProcessError::WriteFailed
        | AgentProcessError::PollFailed
        | AgentProcessError::TerminateFailed => AcpError::TransportFailed,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn daemon_routes_updates_and_permissions_without_client_side_correlation() {
        let mut runtime = AcpRuntime::default();
        runtime.connections.insert(
            "agent".to_owned(),
            AcpConnection {
                generation: 1,
                next_request: 1,
                maximum_message_bytes: 1024 * 1024,
                capabilities: HashSet::new(),
                allowed_extensions: HashSet::new(),
            },
        );
        runtime.sessions.insert(
            "session".to_owned(),
            AcpSession {
                session_id: "session".to_owned(),
                agent_id: "agent".to_owned(),
                generation: 1,
                remote_session_id: "remote".to_owned(),
                workspace_path: "/workspace".to_owned(),
                next_sequence: 1,
                events: VecDeque::new(),
                prompt_request_id: None,
                prompt_result: None,
            },
        );
        runtime
            .route_value(
                "agent",
                json!({
                    "jsonrpc": "2.0",
                    "method": "session/update",
                    "params": {
                        "sessionId": "remote",
                        "update": {
                            "sessionUpdate": "agent_message_chunk",
                            "content": {"text": "bounded"}
                        }
                    }
                }),
            )
            .unwrap();
        runtime
            .route_value(
                "agent",
                json!({
                    "jsonrpc": "2.0",
                    "id": "permission-1",
                    "method": "session/request_permission",
                    "params": {
                        "sessionId": "remote",
                        "toolCall": {"toolCallId": "tool-1"},
                        "options": [
                            {"optionId": "yes", "kind": "allow_once"},
                            {"optionId": "no", "kind": "reject_once"}
                        ]
                    }
                }),
            )
            .unwrap();

        let session = runtime.sessions.get("session").unwrap();
        assert_eq!(session.events.len(), 1);
        assert_eq!(
            session.events.front().unwrap().text.as_deref(),
            Some("bounded")
        );
        let permission = runtime.permissions.values().next().unwrap().snapshot();
        assert_eq!(permission.session_id, "session");
        assert_eq!(permission.options, vec!["allow_once", "reject_once"]);
    }
}
