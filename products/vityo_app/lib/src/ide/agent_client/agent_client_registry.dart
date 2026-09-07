import 'dart:async';
import 'dart:convert';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';
import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

import '../local_service/vityod_client.dart';
import 'agent_client_models.dart';
import 'agent_session_reducer.dart';

/// Thin Flutter gateway and immutable projection for daemon-owned ACP state.
///
/// Process supervision, JSON-RPC correlation, session identity, permission
/// authority, and resumable event ordering live in `vityod`. This class only
/// turns typed service snapshots into Workbench-facing projections.
final class AgentClientRegistry {
  AgentClientRegistry({
    required Map<String, AgentLaunchDescriptor> descriptors,
    required VityodClient client,
    AgentClientPolicy policy = const AgentClientPolicy(),
  }) : _descriptors = Map<String, AgentLaunchDescriptor>.unmodifiable(
         descriptors,
       ),
       _client = client,
       policy = _freezePolicy(policy),
       _permissionQueue = PermissionRequestQueue(
         maxItems: policy.maxPendingRequests,
       ) {
    if (_descriptors.isEmpty) {
      throw ArgumentError.value(
        descriptors,
        'descriptors',
        'must contain at least one Agent',
      );
    }
    for (final entry in _descriptors.entries) {
      if (entry.key != entry.value.id) {
        throw ArgumentError.value(
          entry.key,
          'descriptors',
          'map keys must match descriptor identifiers',
        );
      }
    }
    _validatePolicy(this.policy);
  }

  final Map<String, AgentLaunchDescriptor> _descriptors;
  final VityodClient _client;
  final Map<String, AgentConnectionSnapshot> _connections =
      <String, AgentConnectionSnapshot>{};
  final Map<String, Future<AgentConnectionSnapshot>> _connecting =
      <String, Future<AgentConnectionSnapshot>>{};
  final Map<String, Future<AgentClientSession>> _reconnecting =
      <String, Future<AgentClientSession>>{};
  final Map<String, AgentClientSession> _sessions =
      <String, AgentClientSession>{};
  final Map<String, _RecoveryRoute> _recoveryRoutes =
      <String, _RecoveryRoute>{};
  final Map<String, AgentPermissionRequest> _pendingPermissions =
      <String, AgentPermissionRequest>{};
  final PermissionRequestQueue _permissionQueue;
  final AgentClientPolicy policy;
  var _requestSequence = 0;
  var _closed = false;
  Future<List<AgentShutdownReceipt>>? _shutdown;

  Stream<AgentPermissionRequest> get permissionRequests =>
      _permissionQueue.stream();

  int get activeConnectionCount => _connections.length;

  Future<AgentConnectionSnapshot> connect(String agentId) {
    _ensureOpen();
    final current = _connections[agentId];
    if (current != null) return Future<AgentConnectionSnapshot>.value(current);
    final pending = _connecting[agentId];
    if (pending != null) return pending;
    final operation = _connect(agentId);
    _connecting[agentId] = operation;
    return operation.whenComplete(() {
      if (identical(_connecting[agentId], operation)) {
        _connecting.remove(agentId);
      }
    });
  }

  Future<AgentConnectionSnapshot> _connect(String agentId) async {
    final descriptor = _descriptors[agentId];
    if (descriptor == null) {
      throw AgentClientFailure(
        'unknown_agent',
        'No Agent descriptor is registered for $agentId',
      );
    }
    final response = await _request(
      method: 'agent.connection.open',
      params: <String, Object?>{
        'agentId': descriptor.id,
        'executable': descriptor.executable,
        'arguments': descriptor.arguments,
        'workingDirectory': descriptor.workingDirectory,
        'allowedExtensions': policy.allowedExtensions.toList(growable: false),
        'maximumMessageBytes': policy.maxMessageBytes,
      },
      deadline: policy.requestTimeout,
    );
    final capabilities = _stringSet(response.params, 'capabilities');
    final snapshot = AgentConnectionSnapshot(
      agentId: _requiredString(response.params, 'agentId'),
      protocolVersion: _requiredInt(response.params, 'protocolVersion'),
      generation: _requiredInt(response.params, 'generation'),
      capabilities: capabilities,
      // Daemon intentionally does not serialize provider or environment data.
      metadata: const <String, Object?>{},
    );
    if (snapshot.agentId != agentId ||
        snapshot.protocolVersion != acpProtocolVersion) {
      throw AgentClientFailure(
        'unsupported_version',
        'Agent selected an unsupported protocol version',
      );
    }
    _connections[agentId] = snapshot;
    return snapshot;
  }

  AgentConnectionSnapshot connection(String agentId) {
    final snapshot = _connections[agentId];
    if (snapshot == null) {
      throw AgentClientFailure('transport_closed', 'Agent is not connected');
    }
    return snapshot;
  }

  Future<AgentClientSession> newSession({
    required String agentId,
    required Uri cwd,
  }) async {
    _ensureOpen();
    final workspacePath = _workspacePath(cwd);
    if (_sessions.length >= policy.maxSessions) {
      throw AgentClientFailure(
        'session_limit_exceeded',
        'Agent Client session limit was reached',
      );
    }
    await connect(agentId);
    final response = await _request(
      method: 'agent.session.new',
      params: <String, Object?>{
        'agentId': agentId,
        'workspaceId': cwd.toString(),
        'workspacePath': workspacePath,
        'workspaceRevision': 0,
      },
      deadline: policy.requestTimeout,
    );
    return _createSession(
      agentId: agentId,
      generation: _requiredInt(response.params, 'generation'),
      sessionId: _requiredString(response.params, 'sessionId'),
      remoteSessionId: _requiredString(response.params, 'remoteSessionId'),
      workspacePath: workspacePath,
    );
  }

  Future<AgentClientSession> reconnectSession({
    required String agentId,
    required String sessionId,
    required Uri cwd,
  }) {
    _ensureOpen();
    final pending = _reconnecting[sessionId];
    if (pending != null) return pending;
    final operation = _reconnectSession(
      agentId: agentId,
      sessionId: sessionId,
      cwd: cwd,
    );
    _reconnecting[sessionId] = operation;
    return operation.whenComplete(() {
      if (identical(_reconnecting[sessionId], operation)) {
        _reconnecting.remove(sessionId);
      }
    });
  }

  Future<AgentClientSession> _reconnectSession({
    required String agentId,
    required String sessionId,
    required Uri cwd,
  }) async {
    final workspacePath = _workspacePath(cwd);
    final route = _recoveryRoutes[sessionId];
    if (route == null || route.agentId != agentId) {
      throw AgentClientFailure(
        'unknown_session',
        'Session is not available for reconnect',
      );
    }
    if (route.workspacePath != workspacePath) {
      throw AgentClientFailure(
        'session_workspace_mismatch',
        'Session belongs to a different workspace',
      );
    }
    final connection = await connect(agentId);
    final response = await _request(
      method: 'agent.session.load',
      params: <String, Object?>{
        'sessionId': sessionId,
        'workspacePath': workspacePath,
      },
      deadline: policy.requestTimeout,
    );
    final former = _sessions.remove(sessionId);
    final initialSnapshot = former?.snapshot;
    await former?._close();
    final restored = _createSession(
      agentId: agentId,
      generation: _requiredInt(response.params, 'generation'),
      sessionId: sessionId,
      remoteSessionId: _requiredString(response.params, 'remoteSessionId'),
      workspacePath: workspacePath,
      initialSnapshot: initialSnapshot,
      restoredGeneration: connection.generation,
    );
    await _poll(restored);
    return restored;
  }

  Future<Object?> invokeExtension({
    required String agentId,
    required String method,
    Map<String, Object?> params = const <String, Object?>{},
  }) async {
    final connection = await connect(agentId);
    try {
      validateVityoExtensionMethod(method, connection.capabilities);
    } on AgentProtocolException catch (error) {
      throw AgentClientFailure(error.code, error.message);
    }
    final response = await _request(
      method: 'agent.extension.invoke',
      params: <String, Object?>{
        'agentId': agentId,
        'extensionMethod': method,
        'extensionParams': params,
      },
      deadline: policy.requestTimeout,
    );
    return response.params['result'];
  }

  Future<void> resolvePermission(
    String permissionId,
    AgentPermissionDecision decision,
  ) async {
    final pending = _pendingPermissions[permissionId];
    if (pending == null) {
      throw AgentClientFailure(
        'unknown_permission',
        'Permission request is no longer pending',
      );
    }
    final option = switch (decision) {
      AgentPermissionDecision.allowOnce => 'allow_once',
      AgentPermissionDecision.rejectOnce => 'reject_once',
    };
    if (!pending.options.contains(option)) {
      throw AgentClientFailure(
        'invalid_permission_decision',
        'Permission option was not offered by the Agent',
      );
    }
    await _request(
      method: 'agent.acp.permission.decide',
      params: <String, Object?>{
        'permissionId': permissionId,
        'decision': option,
      },
      deadline: policy.requestTimeout,
    );
    _pendingPermissions.remove(permissionId);
    _permissionQueue.removeWhere((request) => request.id == permissionId);
  }

  Future<AgentShutdownReceipt> disconnect(String agentId) async {
    _connections.remove(agentId);
    final response = await _request(
      method: 'agent.connection.close',
      params: <String, Object?>{'agentId': agentId},
      deadline: policy.shutdownTimeout,
    );
    _pendingPermissions.removeWhere(
      (_, permission) => permission.agentId == agentId,
    );
    _permissionQueue.removeWhere((permission) => permission.agentId == agentId);
    return AgentShutdownReceipt(
      agentId: agentId,
      terminated: response.params['terminated'] == true,
      forced: response.params['forced'] == true,
      exitCode: response.params['exitCode'] as int?,
    );
  }

  Future<List<AgentShutdownReceipt>> close() => _shutdown ??= _closeAll();

  Future<List<AgentShutdownReceipt>> _closeAll() async {
    if (_closed) return const <AgentShutdownReceipt>[];
    _closed = true;
    final agentIds = <String>{
      ..._connections.keys,
      ..._connecting.keys,
    }.toList(growable: false);
    for (final operation in _connecting.values.toList(growable: false)) {
      try {
        await operation;
      } on Object {
        // The connection caller owns its bounded failure.
      }
    }
    for (final operation in _reconnecting.values.toList(growable: false)) {
      try {
        await operation;
      } on Object {
        // The reconnect caller owns its bounded failure.
      }
    }
    final receipts = <AgentShutdownReceipt>[];
    for (final agentId in agentIds) {
      try {
        receipts.add(await disconnect(agentId));
      } on AgentClientFailure {
        receipts.add(
          AgentShutdownReceipt(
            agentId: agentId,
            terminated: false,
            forced: false,
            exitCode: null,
          ),
        );
      }
    }
    for (final session in _sessions.values.toList(growable: false)) {
      await session._close();
    }
    _sessions.clear();
    _recoveryRoutes.clear();
    _reconnecting.clear();
    _pendingPermissions.clear();
    _permissionQueue.close();
    return List<AgentShutdownReceipt>.unmodifiable(receipts);
  }

  AgentClientSession _createSession({
    required String agentId,
    required int generation,
    required String sessionId,
    required String remoteSessionId,
    required String workspacePath,
    AgentSessionSnapshot? initialSnapshot,
    int? restoredGeneration,
  }) {
    if (_sessions.containsKey(sessionId)) {
      throw AgentClientFailure(
        'session_collision',
        'Agent reused an active session identifier',
      );
    }
    final reducer = AgentSessionReducer(
      sessionId: sessionId,
      maxBufferedUpdates: policy.maxBufferedUpdatesPerSession,
      backpressurePolicy: AgentEventBackpressurePolicy(
        maxQueuedEvents: policy.maxQueuedUpdatesPerSession,
        maxQueuedBytes: policy.maxQueuedUpdateBytesPerSession,
        maxHotHistoryEvents: policy.maxBufferedUpdatesPerSession,
        maxHotHistoryBytes: policy.maxBufferedUpdateBytesPerSession,
      ),
      initialSnapshot: initialSnapshot,
    );
    final session = AgentClientSession._(
      registry: this,
      reducer: reducer,
      agentId: agentId,
      generation: generation,
      id: sessionId,
      remoteId: remoteSessionId,
    );
    _sessions[sessionId] = session;
    _recoveryRoutes[sessionId] = _RecoveryRoute(
      agentId: agentId,
      workspacePath: workspacePath,
    );
    if (restoredGeneration != null) {
      unawaited(
        reducer.reducePriority(
          AgentSessionUpdate(
            sessionId: sessionId,
            kind: 'session_state',
            payload: <String, Object?>{
              'id': 'connection-restored-$restoredGeneration',
              'status': 'active',
            },
          ),
        ),
      );
    }
    return session;
  }

  Future<VityodControlEnvelope> _request({
    required String method,
    required Map<String, Object?> params,
    required Duration deadline,
  }) async {
    if (!_client.state.canDispatch) {
      throw AgentClientFailure(
        'local_service_required',
        'Agent operations require the local service gateway',
      );
    }
    final response = await _client.request(
      method: method,
      idempotencyKey: 'agent-${++_requestSequence}-$method',
      params: params,
      deadline: deadline,
    );
    if (response.method.endsWith('.error')) {
      final code = response.params['errorCode'];
      throw AgentClientFailure(
        code is String ? code : 'service_error',
        'vityod rejected the Agent operation',
      );
    }
    return response;
  }

  Future<Object?> _prompt(AgentClientSession session, String text) async {
    await _request(
      method: 'agent.session.prompt',
      params: <String, Object?>{'sessionId': session.id, 'text': text},
      deadline: policy.requestTimeout,
    );
    final deadline = DateTime.now().add(policy.requestTimeout);
    while (true) {
      final result = await _poll(session);
      if (result != null) return result;
      if (DateTime.now().isAfter(deadline)) {
        throw AgentClientFailure(
          'request_timeout',
          'Agent prompt exceeded the configured deadline',
        );
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  Future<Object?> _poll(AgentClientSession session) async {
    final response = await _request(
      method: 'agent.session.poll',
      params: <String, Object?>{
        'sessionId': session.id,
        'afterSequence': session._eventCursor,
      },
      deadline: const Duration(seconds: 2),
    );
    final events = response.params['events'];
    if (events is! List<Object?>) {
      throw AgentClientFailure(
        'malformed_message',
        'vityod returned an invalid Agent event projection',
      );
    }
    for (final raw in events) {
      if (raw is! Map<Object?, Object?>) {
        throw AgentClientFailure(
          'malformed_message',
          'vityod returned an invalid Agent event projection',
        );
      }
      final event = Map<String, Object?>.from(raw);
      final sequence = _requiredInt(event, 'sequence');
      if (sequence != session._eventCursor + 1) {
        throw AgentClientFailure(
          'agent_event_cursor_mismatch',
          'Agent events are not contiguous',
        );
      }
      final payload = event['payload'];
      if (payload is! Map<Object?, Object?>) {
        throw AgentClientFailure(
          'malformed_message',
          'Agent event payload must be an object',
        );
      }
      session._eventCursor = sequence;
      await session._reducer.reduce(
        AgentSessionUpdate(
          sessionId: session.id,
          kind: _requiredString(event, 'kind'),
          text: event['text'] as String?,
          payload: Map<String, Object?>.unmodifiable(
            Map<String, Object?>.from(payload),
          ),
        ),
      );
    }
    final permissions = response.params['permissions'];
    if (permissions is! List<Object?>) {
      throw AgentClientFailure(
        'malformed_message',
        'vityod returned an invalid permission projection',
      );
    }
    for (final raw in permissions) {
      if (raw is! Map<Object?, Object?>) continue;
      final value = Map<String, Object?>.from(raw);
      final permissionId = _requiredString(value, 'permissionId');
      if (_pendingPermissions.containsKey(permissionId)) continue;
      final permission = AgentPermissionRequest(
        id: permissionId,
        agentId: _requiredString(value, 'agentId'),
        sessionId: _requiredString(value, 'sessionId'),
        toolCallId: _requiredString(value, 'toolCallId'),
        toolCallTitle: value['toolCallTitle'] as String?,
        toolCallKind: value['toolCallKind'] as String?,
        options: _stringSet(value, 'options'),
      );
      if (_pendingPermissions.length >= policy.maxPendingRequests ||
          !_permissionQueue.add(permission)) {
        throw AgentClientFailure(
          'permission_request_limit_exceeded',
          'Agent permission projection is full',
        );
      }
      _pendingPermissions[permissionId] = permission;
    }
    final capabilities = response.params['connectionCapabilities'];
    final connectionGeneration = response.params['connectionGeneration'];
    final currentConnection = _connections[session.agentId];
    if (capabilities is List &&
        capabilities.every((item) => item is String) &&
        connectionGeneration is int &&
        connectionGeneration >= 0 &&
        currentConnection != null) {
      _connections[session.agentId] = AgentConnectionSnapshot(
        agentId: currentConnection.agentId,
        protocolVersion: currentConnection.protocolVersion,
        generation: connectionGeneration,
        capabilities: Set<String>.unmodifiable(capabilities.cast<String>()),
        metadata: const <String, Object?>{},
      );
    }
    final exitCode = response.params['processExitCode'];
    final promptResult = response.params['promptResult'];
    if (promptResult != null) return promptResult;
    if (exitCode is int) {
      throw AgentClientFailure(
        'process_failed',
        'Agent process exited before the prompt completed',
      );
    }
    return null;
  }

  Future<bool> _cancel(AgentClientSession session) async {
    final response = await _request(
      method: 'agent.acp.session.cancel',
      params: <String, Object?>{'sessionId': session.id},
      deadline: policy.requestTimeout,
    );
    _pendingPermissions.removeWhere(
      (_, permission) => permission.sessionId == session.id,
    );
    _permissionQueue.removeWhere(
      (permission) => permission.sessionId == session.id,
    );
    return response.params['cancelled'] == true;
  }

  Future<void> _markSessionFailed(
    AgentClientSession session,
    AgentClientFailure failure,
  ) async {
    _pendingPermissions.removeWhere(
      (_, permission) => permission.sessionId == session.id,
    );
    _permissionQueue.removeWhere(
      (permission) => permission.sessionId == session.id,
    );
    await session._reducer.reducePriority(
      AgentSessionUpdate(
        sessionId: session.id,
        kind: 'session_state',
        payload: <String, Object?>{
          'id': 'failure-${session.snapshot.revision + 1}',
          'status': 'failed',
          'failureCode': failure.code,
        },
      ),
    );
  }

  void _ensureOpen() {
    if (_closed) {
      throw AgentClientFailure(
        'registry_closed',
        'Agent Client registry is closed',
      );
    }
  }
}

final class AgentClientSession {
  AgentClientSession._({
    required AgentClientRegistry registry,
    required AgentSessionReducer reducer,
    required this.agentId,
    required this.generation,
    required this.id,
    required this.remoteId,
  }) : _registry = registry,
       _reducer = reducer;

  final AgentClientRegistry _registry;
  final AgentSessionReducer _reducer;
  final String agentId;
  final int generation;
  final String id;
  final String remoteId;
  var _eventCursor = 0;
  var _activePrompt = false;
  var _cancelSent = false;
  var _closed = false;

  Stream<AgentSessionUpdate> get updates => _reducer.updates;

  AgentSessionSnapshot get snapshot => _reducer.snapshot;

  Future<AcpPromptResult> prompt(String text) async {
    if (_closed) {
      throw AgentClientFailure('session_closed', 'Agent session is closed');
    }
    if (text.trim().isEmpty) {
      throw AgentClientFailure(
        'invalid_prompt',
        'Agent prompt must not be empty',
      );
    }
    if (utf8.encode(text).length > _registry.policy.maxMessageBytes) {
      throw AgentClientFailure(
        'message_too_large',
        'Agent prompt exceeds the configured protocol byte limit',
      );
    }
    if (_activePrompt) {
      throw AgentClientFailure(
        'prompt_in_progress',
        'Only one prompt may run per session',
      );
    }
    _activePrompt = true;
    _cancelSent = false;
    try {
      return AcpPromptResult.fromJson(await _registry._prompt(this, text));
    } on AgentClientFailure catch (failure) {
      await _registry._markSessionFailed(this, failure);
      rethrow;
    } finally {
      _activePrompt = false;
    }
  }

  Future<bool> cancel() async {
    if (!_activePrompt || _cancelSent || _closed) return false;
    _cancelSent = true;
    return _registry._cancel(this);
  }

  Future<void> _close() async {
    if (_closed) return;
    _closed = true;
    await _reducer.close();
  }
}

final class _RecoveryRoute {
  const _RecoveryRoute({required this.agentId, required this.workspacePath});

  final String agentId;
  final String workspacePath;
}

AgentClientPolicy _freezePolicy(AgentClientPolicy policy) => AgentClientPolicy(
  maxMessageBytes: policy.maxMessageBytes,
  maxBufferedUpdatesPerSession: policy.maxBufferedUpdatesPerSession,
  maxBufferedUpdateBytesPerSession: policy.maxBufferedUpdateBytesPerSession,
  maxQueuedUpdatesPerSession: policy.maxQueuedUpdatesPerSession,
  maxQueuedUpdateBytesPerSession: policy.maxQueuedUpdateBytesPerSession,
  maxSessions: policy.maxSessions,
  maxPendingRequests: policy.maxPendingRequests,
  requestTimeout: policy.requestTimeout,
  shutdownTimeout: policy.shutdownTimeout,
  allowedExtensions: Set<String>.unmodifiable(policy.allowedExtensions),
);

void _validatePolicy(AgentClientPolicy policy) {
  if (policy.requestTimeout <= Duration.zero ||
      policy.shutdownTimeout <= Duration.zero) {
    throw ArgumentError.value(policy, 'policy', 'timeouts must be positive');
  }
  for (final extension in policy.allowedExtensions) {
    if (!extension.startsWith(vityoAcpExtensionPrefix) ||
        extension.length <= vityoAcpExtensionPrefix.length ||
        extension.length > 256) {
      throw ArgumentError.value(
        extension,
        'allowedExtensions',
        'must be a bounded _vityo.dev/ capability',
      );
    }
  }
}

String _workspacePath(Uri cwd) {
  if (cwd.scheme != 'file' || cwd.path.isEmpty || !cwd.path.startsWith('/')) {
    throw AgentClientFailure(
      'invalid_workspace',
      'Agent sessions require an absolute file workspace URI',
    );
  }
  return cwd.toFilePath(windows: false);
}

String _requiredString(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is String && value.isNotEmpty) return value;
  throw AgentClientFailure('malformed_message', '$key must be a string');
}

int _requiredInt(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is int && value >= 0) return value;
  throw AgentClientFailure('malformed_message', '$key must be an integer');
}

Set<String> _stringSet(Map<String, Object?> source, String key) {
  final value = source[key];
  if (value is List && value.every((item) => item is String)) {
    return Set<String>.unmodifiable(value.cast<String>());
  }
  throw AgentClientFailure('malformed_message', '$key must contain strings');
}
