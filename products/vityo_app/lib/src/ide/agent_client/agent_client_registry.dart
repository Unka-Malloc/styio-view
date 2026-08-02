import 'dart:async';
import 'dart:convert';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';

import 'agent_client_models.dart';
import 'agent_process_supervisor.dart';
import 'agent_session_reducer.dart';

final class AgentClientRegistry {
  AgentClientRegistry({
    required Map<String, AgentLaunchDescriptor> descriptors,
    AgentClientPolicy policy = const AgentClientPolicy(),
    AgentProcessSupervisor supervisor = const AgentProcessSupervisor(),
  }) : _descriptors = Map<String, AgentLaunchDescriptor>.unmodifiable(
         descriptors,
       ),
       policy = AgentClientPolicy(
         maxMessageBytes: policy.maxMessageBytes,
         maxBufferedUpdatesPerSession: policy.maxBufferedUpdatesPerSession,
         maxBufferedUpdateBytesPerSession:
             policy.maxBufferedUpdateBytesPerSession,
         maxQueuedUpdatesPerSession: policy.maxQueuedUpdatesPerSession,
         maxQueuedUpdateBytesPerSession: policy.maxQueuedUpdateBytesPerSession,
         maxSessions: policy.maxSessions,
         maxPendingRequests: policy.maxPendingRequests,
         requestTimeout: policy.requestTimeout,
         shutdownTimeout: policy.shutdownTimeout,
         allowedExtensions: Set<String>.unmodifiable(policy.allowedExtensions),
       ),
       _supervisor = supervisor,
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
    if (this.policy.maxMessageBytes <= 0 ||
        this.policy.maxBufferedUpdatesPerSession <= 0 ||
        this.policy.maxBufferedUpdateBytesPerSession <= 0 ||
        this.policy.maxQueuedUpdatesPerSession <= 0 ||
        this.policy.maxQueuedUpdateBytesPerSession <= 0 ||
        this.policy.maxSessions <= 0 ||
        this.policy.maxPendingRequests <= 0 ||
        this.policy.requestTimeout <= Duration.zero ||
        this.policy.shutdownTimeout <= Duration.zero) {
      throw ArgumentError.value(
        policy,
        'policy',
        'all limits and timeouts must be positive',
      );
    }
    for (final extension in this.policy.allowedExtensions) {
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

  final Map<String, AgentLaunchDescriptor> _descriptors;
  final AgentProcessSupervisor _supervisor;
  final AgentClientPolicy policy;
  final Map<String, _ConnectionState> _connections =
      <String, _ConnectionState>{};
  final Map<String, Future<AgentConnectionSnapshot>> _connectionOperations =
      <String, Future<AgentConnectionSnapshot>>{};
  final Map<String, Future<AgentClientSession>> _reconnectOperations =
      <String, Future<AgentClientSession>>{};
  final Map<String, AgentClientSession> _sessions =
      <String, AgentClientSession>{};
  final Map<(String, int, String), AgentClientSession> _sessionsByRemote =
      <(String, int, String), AgentClientSession>{};
  final Map<String, (String, String, String)> _sessionRecoveryRoutes =
      <String, (String, String, String)>{};
  final Map<String, AgentSessionSnapshot> _sessionRecoverySnapshots =
      <String, AgentSessionSnapshot>{};
  final Map<String, int> _generations = <String, int>{};
  final Map<String, _InboundPermission> _inboundPermissions =
      <String, _InboundPermission>{};
  final PermissionRequestQueue _permissionQueue;
  int _requestSequence = 0;
  int _sessionSequence = 0;
  int _permissionSequence = 0;
  int _pendingNewSessions = 0;
  bool _closed = false;
  Future<List<AgentShutdownReceipt>>? _shutdown;

  Stream<AgentPermissionRequest> get permissionRequests =>
      _permissionQueue.stream();

  int get activeConnectionCount =>
      _connections.values.where((state) => state.failure == null).length;

  Future<AgentConnectionSnapshot> connect(String agentId) async {
    _ensureOpen();
    final existing = _connections[agentId];
    if (existing != null && existing.failure == null) {
      return existing.snapshot;
    }
    final inFlight = _connectionOperations[agentId];
    if (inFlight != null) {
      return inFlight;
    }
    final operation = _connect(agentId);
    _connectionOperations[agentId] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_connectionOperations[agentId], operation)) {
        _connectionOperations.remove(agentId);
      }
    }
  }

  Future<AgentConnectionSnapshot> _connect(String agentId) async {
    final existing = _connections[agentId];
    if (existing != null) {
      if (identical(_connections[agentId], existing)) {
        _connections.remove(agentId);
      }
      await _disconnectState(existing);
    }
    final descriptor = _descriptors[agentId];
    if (descriptor == null) {
      throw AgentClientFailure(
        'unknown_agent',
        'No Agent descriptor is registered for $agentId',
      );
    }
    final generation = (_generations[agentId] ?? 0) + 1;
    _generations[agentId] = generation;
    final AgentClientTransport transport;
    try {
      transport = await _supervisor.launch(
        descriptor: descriptor,
        policy: policy,
      );
    } on Object {
      throw AgentClientFailure(
        'process_failed',
        'Agent process could not be started',
      );
    }
    if (_closed) {
      await transport.close();
      throw AgentClientFailure(
        'registry_closed',
        'Agent Client registry is closed',
      );
    }
    final state = _ConnectionState(
      agentId: agentId,
      generation: generation,
      transport: transport,
    );
    _connections[agentId] = state;
    state.subscription = transport.incoming.listen(
      (message) => _routeMessage(state, message),
      onError: (Object error, StackTrace stackTrace) {
        _failConnection(
          state,
          error is AgentClientFailure
              ? error
              : AgentClientFailure(
                  'transport_closed',
                  'Agent transport failed',
                ),
        );
      },
      onDone: () {
        if (!state.closing && state.failure == null) {
          _failConnection(
            state,
            AgentClientFailure(
              'process_failed',
              'Agent process closed its protocol stream',
            ),
          );
        }
      },
    );

    try {
      final result = requireJsonObject(
        await _request(state, AcpMethod.initialize, <String, Object?>{
          'protocolVersion': acpProtocolVersion,
          'clientInfo': const <String, Object?>{
            'name': 'vityo',
            'version': '0.1.0',
          },
          'clientCapabilities': const <String, Object?>{
            'fs': <String, Object?>{
              'readTextFile': false,
              'writeTextFile': false,
            },
            'terminal': false,
          },
        }),
        'initialize result',
      );
      final version = result['protocolVersion'];
      if (version != acpProtocolVersion) {
        throw AgentClientFailure(
          'unsupported_version',
          'Agent selected unsupported protocol version',
        );
      }
      state.protocolVersion = version as int;
      state.capabilities = _decodeCapabilities(result['agentCapabilities']);
      final metadata = result['_meta'];
      state.metadata = metadata is Map<String, Object?>
          ? Map<String, Object?>.unmodifiable(metadata)
          : const <String, Object?>{};
      return state.snapshot;
    } on Object catch (error) {
      final failure = _asClientFailure(error);
      _failConnection(state, failure);
      await state.transport.close();
      throw failure;
    }
  }

  AgentConnectionSnapshot connection(String agentId) {
    final state = _connections[agentId];
    if (state == null || state.failure != null) {
      throw AgentClientFailure('transport_closed', 'Agent is not connected');
    }
    return state.snapshot;
  }

  Future<AgentClientSession> newSession({
    required String agentId,
    required Uri cwd,
  }) async {
    _ensureOpen();
    final workspacePath = _workspacePath(cwd);
    if (_sessionRecoveryRoutes.length + _pendingNewSessions >=
        policy.maxSessions) {
      throw AgentClientFailure(
        'session_limit_exceeded',
        'Agent Client session limit was reached',
      );
    }
    _pendingNewSessions += 1;
    try {
      final state = await _connectedState(agentId);
      final result = requireJsonObject(
        await _request(state, AcpMethod.sessionNew, <String, Object?>{
          'cwd': workspacePath,
          'mcpServers': const <Object?>[],
        }),
        'session/new result',
      );
      final sessionId = _requireBoundedString(result, 'sessionId');
      return _createSession(state, sessionId, workspacePath: workspacePath);
    } finally {
      _pendingNewSessions -= 1;
    }
  }

  Future<AgentClientSession> reconnectSession({
    required String agentId,
    required String sessionId,
    required Uri cwd,
  }) async {
    _ensureOpen();
    final workspacePath = _workspacePath(cwd);
    final recoveryRoute = _sessionRecoveryRoutes[sessionId];
    if (recoveryRoute == null || recoveryRoute.$1 != agentId) {
      throw AgentClientFailure(
        'unknown_session',
        'Session is not available for reconnect',
      );
    }
    if (recoveryRoute.$3 != workspacePath) {
      throw AgentClientFailure(
        'session_workspace_mismatch',
        'Session cannot be reconnected in a different workspace',
      );
    }
    final inFlight = _reconnectOperations[sessionId];
    if (inFlight != null) {
      return inFlight;
    }
    final operation = _reconnectSession(
      agentId: agentId,
      sessionId: sessionId,
      workspacePath: workspacePath,
    );
    _reconnectOperations[sessionId] = operation;
    try {
      return await operation;
    } finally {
      if (identical(_reconnectOperations[sessionId], operation)) {
        _reconnectOperations.remove(sessionId);
      }
    }
  }

  Future<AgentClientSession> _reconnectSession({
    required String agentId,
    required String sessionId,
    required String workspacePath,
  }) async {
    final recoveryRoute = _sessionRecoveryRoutes[sessionId];
    if (recoveryRoute == null ||
        recoveryRoute.$1 != agentId ||
        recoveryRoute.$3 != workspacePath) {
      throw AgentClientFailure(
        'unknown_session',
        'Session is not available for reconnect',
      );
    }
    final remoteSessionId = recoveryRoute.$2;
    final state = await _connectedState(agentId);
    if (!state.capabilities.contains(AcpCapability.loadSession)) {
      throw AgentClientFailure(
        'capability_revoked',
        'Agent does not currently support session/load',
      );
    }
    final recoverySnapshot = _sessionRecoverySnapshots[sessionId];
    final session = await _createSession(
      state,
      remoteSessionId,
      clientSessionId: sessionId,
      workspacePath: workspacePath,
      markRestored: false,
    );
    try {
      final result =
          await _request(state, AcpMethod.sessionLoad, <String, Object?>{
            'sessionId': remoteSessionId,
            'cwd': workspacePath,
            'mcpServers': const <Object?>[],
          });
      if (result != null) {
        throw AgentClientFailure(
          'malformed_message',
          'session/load must return the ACP null result',
        );
      }
      await session._markRestored();
      return session;
    } on Object {
      if (identical(_sessions[sessionId], session)) {
        _sessions.remove(sessionId);
      }
      _sessionsByRemote.remove((
        session.agentId,
        session.generation,
        session.remoteId,
      ));
      await session._close();
      if (!_closed && recoverySnapshot != null) {
        _sessionRecoverySnapshots[sessionId] = recoverySnapshot;
      }
      rethrow;
    }
  }

  Future<Object?> invokeExtension({
    required String agentId,
    required String method,
    Map<String, Object?> params = const <String, Object?>{},
  }) async {
    _ensureOpen();
    final state = await _connectedState(agentId);
    try {
      validateVityoExtensionMethod(method, state.capabilities);
    } on AgentProtocolException catch (error) {
      throw AgentClientFailure(error.code, error.message);
    }
    return _request(state, method, params);
  }

  Future<void> resolvePermission(
    String permissionId,
    AgentPermissionDecision decision,
  ) async {
    final inbound = _inboundPermissions[permissionId];
    if (inbound == null) {
      throw AgentClientFailure(
        'unknown_permission',
        'Permission request is no longer pending',
      );
    }
    final optionId = inbound.optionIds[decision];
    if (optionId == null) {
      throw AgentClientFailure(
        'invalid_permission_decision',
        'Permission option was not offered by the Agent',
      );
    }
    if (inbound.resolving) {
      throw AgentClientFailure(
        'permission_resolution_in_progress',
        'Permission request is already being resolved',
      );
    }
    if (inbound.state.failure != null || inbound.state.closing) {
      throw AgentClientFailure(
        'transport_closed',
        'Permission owner is no longer connected',
      );
    }
    inbound.resolving = true;
    try {
      final resolution = inbound.state.transport.send(
        JsonRpcSuccessResponse(
          id: inbound.rpcId,
          result: <String, Object?>{
            'outcome': <String, Object?>{
              'outcome': 'selected',
              'optionId': optionId,
            },
          },
        ),
      );
      inbound.resolution = resolution;
      await resolution;
      if (identical(_inboundPermissions[permissionId], inbound)) {
        _inboundPermissions.remove(permissionId);
        _permissionQueue.removeWhere((request) => request.id == permissionId);
      }
    } on Object catch (error) {
      inbound.resolving = false;
      inbound.resolution = null;
      throw _outboundFailure(error);
    }
  }

  Future<AgentShutdownReceipt> disconnect(String agentId) async {
    AgentShutdownReceipt? receipt;
    final state = _connections.remove(agentId);
    if (state != null) {
      receipt = await _disconnectState(state);
    }
    final connectionOperation = _connectionOperations[agentId];
    if (connectionOperation != null) {
      try {
        await connectionOperation;
      } on Object {
        // The failed connection owns its own bounded diagnostic.
      }
      final lateState = _connections.remove(agentId);
      if (lateState != null && !identical(lateState, state)) {
        receipt = await _disconnectState(lateState);
      }
    }
    return receipt ??
        AgentShutdownReceipt(
          agentId: agentId,
          terminated: true,
          forced: false,
          exitCode: 0,
        );
  }

  Future<AgentShutdownReceipt> _disconnectState(_ConnectionState state) async {
    if (state.closing) {
      return state.transport.close();
    }
    state.closing = true;
    _completePending(
      state,
      AgentClientFailure('transport_closed', 'Agent connection was closed'),
    );
    await state.subscription.cancel();
    final ownedSessions = _sessions.values
        .where(
          (session) =>
              session.agentId == state.agentId &&
              session.generation == state.generation,
        )
        .toList(growable: false);
    for (final session in ownedSessions) {
      _sessionRecoverySnapshots[session.id] = session.snapshot;
      _sessions.remove(session.id);
      _sessionsByRemote.remove((
        session.agentId,
        session.generation,
        session.remoteId,
      ));
      await session._close();
    }
    _discardPermissionsOwnedBy(state);
    return state.transport.close();
  }

  Future<List<AgentShutdownReceipt>> close() {
    return _shutdown ??= _closeAll();
  }

  Future<List<AgentShutdownReceipt>> _closeAll() async {
    _closed = true;
    final reconnects = _reconnectOperations.values.toList(growable: false);
    final agentIds = <String>{
      ..._connections.keys,
      ..._connectionOperations.keys,
    }.toList(growable: false);
    try {
      final receipts = await Future.wait<AgentShutdownReceipt>(
        agentIds.map(disconnect),
        eagerError: false,
      );
      return List<AgentShutdownReceipt>.unmodifiable(receipts);
    } finally {
      for (final reconnect in reconnects) {
        try {
          await reconnect;
        } on Object {
          // Disconnect supplies the typed failure to the reconnect caller.
        }
      }
      _sessions.clear();
      _sessionsByRemote.clear();
      _sessionRecoveryRoutes.clear();
      _sessionRecoverySnapshots.clear();
      _inboundPermissions.clear();
      _connectionOperations.clear();
      _reconnectOperations.clear();
      _permissionQueue.close();
    }
  }

  Future<_ConnectionState> _connectedState(String agentId) async {
    _ensureOpen();
    final current = _connections[agentId];
    if (current != null && current.failure == null && !current.closing) {
      return current;
    }
    final connected = await connect(agentId);
    final state = _connections[agentId];
    if (state == null ||
        state.failure != null ||
        state.closing ||
        state.generation != connected.generation) {
      throw AgentClientFailure(
        'transport_closed',
        'Agent connection closed before it became usable',
      );
    }
    return state;
  }

  Future<AgentClientSession> _createSession(
    _ConnectionState state,
    String remoteSessionId, {
    required String workspacePath,
    String? clientSessionId,
    bool markRestored = true,
  }) async {
    _ensureStateActive(state);
    final resolvedClientSessionId =
        clientSessionId ?? 'vityo-session-${++_sessionSequence}';
    if (clientSessionId == null &&
        _sessionRecoveryRoutes.length >= policy.maxSessions) {
      throw AgentClientFailure(
        'session_limit_exceeded',
        'Agent Client session limit was reached',
      );
    }
    final remoteKey = (state.agentId, state.generation, remoteSessionId);
    final former = _sessions[resolvedClientSessionId];
    final remoteOwner = _sessionsByRemote[remoteKey];
    if (remoteOwner != null && !identical(remoteOwner, former)) {
      throw AgentClientFailure(
        'session_collision',
        'Agent reused an active remote session identifier',
      );
    }
    final savedSnapshot = _sessionRecoverySnapshots.remove(
      resolvedClientSessionId,
    );
    final initialSnapshot = former?.snapshot ?? savedSnapshot;
    _sessions.remove(resolvedClientSessionId);
    if (former != null) {
      _sessionsByRemote.remove((
        former.agentId,
        former.generation,
        former.remoteId,
      ));
      await former._close();
    }
    try {
      _ensureStateActive(state);
    } on Object {
      if (initialSnapshot != null && !_closed) {
        _sessionRecoverySnapshots[resolvedClientSessionId] = initialSnapshot;
      }
      rethrow;
    }
    final reducer = AgentSessionReducer(
      sessionId: resolvedClientSessionId,
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
      agentId: state.agentId,
      generation: state.generation,
      id: resolvedClientSessionId,
      remoteId: remoteSessionId,
      reducer: reducer,
    );
    _sessions[resolvedClientSessionId] = session;
    _sessionsByRemote[remoteKey] = session;
    _sessionRecoveryRoutes[resolvedClientSessionId] = (
      state.agentId,
      remoteSessionId,
      workspacePath,
    );
    if (clientSessionId != null && markRestored) {
      await session._markRestored();
    }
    if (_closed || state.failure != null || state.closing) {
      if (!_closed) {
        _sessionRecoverySnapshots[resolvedClientSessionId] = session.snapshot;
      }
      _sessions.remove(resolvedClientSessionId);
      _sessionsByRemote.remove(remoteKey);
      await session._close();
      throw AgentClientFailure(
        'transport_closed',
        'Agent connection closed while restoring the session',
      );
    }
    return session;
  }

  Future<Object?> _request(
    _ConnectionState state,
    String method,
    Map<String, Object?> params,
  ) async {
    if (state.failure != null || state.closing) {
      throw state.failure ??
          AgentClientFailure('transport_closed', 'Agent transport is closed');
    }
    if (state.pending.length >= policy.maxPendingRequests) {
      throw AgentClientFailure(
        'request_limit_exceeded',
        'Agent request concurrency limit was reached',
      );
    }
    _requestSequence += 1;
    final id = JsonRpcId.string('vityo-${state.generation}-$_requestSequence');
    final completer = Completer<Object?>();
    state.pending[id] = completer;
    try {
      await state.transport.send(
        JsonRpcRequest(id: id, method: method, params: params),
      );
      return await completer.future.timeout(policy.requestTimeout);
    } on TimeoutException {
      throw AgentClientFailure(
        'request_timeout',
        'Agent request exceeded the configured deadline',
      );
    } on AgentClientFailure {
      rethrow;
    } on Object catch (error) {
      throw _outboundFailure(error);
    } finally {
      state.pending.remove(id);
    }
  }

  Future<void> _notify(
    _ConnectionState state,
    String method,
    Map<String, Object?> params,
  ) async {
    try {
      await state.transport.send(
        JsonRpcNotification(method: method, params: params),
      );
    } on AgentClientFailure {
      rethrow;
    } on Object catch (error) {
      throw _outboundFailure(error);
    }
  }

  void _routeMessage(_ConnectionState state, JsonRpcMessage message) {
    if (state.failure != null || state.closing) {
      return;
    }
    switch (message) {
      case JsonRpcSuccessResponse():
        state.pending.remove(message.id)?.complete(message.result);
      case JsonRpcErrorResponse():
        state.pending
            .remove(message.id)
            ?.completeError(
              AgentClientFailure(
                'remote_error',
                'Agent request failed with code ${message.error.code}',
              ),
            );
      case JsonRpcNotification():
        unawaited(_routeNotificationSafely(state, message));
      case JsonRpcRequest():
        unawaited(_routeInboundRequestSafely(state, message));
    }
  }

  Future<void> _routeNotificationSafely(
    _ConnectionState state,
    JsonRpcNotification notification,
  ) async {
    try {
      await _routeNotification(state, notification);
    } on Object catch (error) {
      _failConnection(state, _asClientFailure(error));
    }
  }

  Future<void> _routeInboundRequestSafely(
    _ConnectionState state,
    JsonRpcRequest request,
  ) async {
    try {
      await _routeInboundRequest(state, request);
    } on Object {
      try {
        await state.transport.send(
          JsonRpcErrorResponse(
            id: request.id,
            error: const JsonRpcError(code: -32602, message: 'invalid request'),
          ),
        );
      } on Object {
        _failConnection(
          state,
          AgentClientFailure(
            'transport_closed',
            'Agent transport failed while rejecting an invalid request',
          ),
        );
      }
    }
  }

  Future<void> _routeNotification(
    _ConnectionState state,
    JsonRpcNotification notification,
  ) async {
    if (notification.method == AcpMethod.sessionUpdate) {
      final sessionId = _requireBoundedString(notification.params, 'sessionId');
      final session =
          _sessionsByRemote[(state.agentId, state.generation, sessionId)];
      if (session == null) {
        return;
      }
      final update = requireJsonObject(
        notification.params['update'],
        'session update',
      );
      final kind = _requireBoundedString(update, 'sessionUpdate');
      final content = update['content'];
      final text = content is Map<String, Object?> && content['text'] is String
          ? content['text'] as String
          : null;
      await session._reducer.reduce(
        AgentSessionUpdate(
          sessionId: session.id,
          kind: kind,
          text: text,
          payload: Map<String, Object?>.unmodifiable(update),
        ),
      );
      return;
    }
    if (notification.method == VityoCapability.workspaceChangeProposal) {
      if (!state.capabilities.contains(
        VityoCapability.workspaceChangeProposal,
      )) {
        throw const AgentProtocolException(
          'capability_revoked',
          'workspace change proposals are not currently negotiated',
        );
      }
      final sessionId = _requireBoundedString(notification.params, 'sessionId');
      final session =
          _sessionsByRemote[(state.agentId, state.generation, sessionId)];
      if (session == null) {
        return;
      }
      final proposal = VityoWorkspaceChangeProposal.fromNotificationParams(
        notification.params,
      );
      await session._reducer.reduce(
        AgentSessionUpdate(
          sessionId: session.id,
          kind: VityoCapability.workspaceChangeProposal,
          payload: <String, Object?>{'proposal': proposal.toJson()},
        ),
      );
      return;
    }
    if (notification.method == AcpMethod.capabilitiesChanged) {
      final raw = notification.params['capabilities'];
      if (raw is! List<Object?> || raw.any((item) => item is! String)) {
        _failConnection(
          state,
          AgentClientFailure(
            'malformed_message',
            'Dynamic capabilities must be a list of strings',
          ),
        );
        return;
      }
      final capabilities = <String>{};
      for (final capability in raw.cast<String>()) {
        if (capability.trim().isEmpty || capability.length > 256) {
          throw const AgentProtocolException(
            'malformed_message',
            'dynamic capability identifiers must be non-empty and bounded',
          );
        }
        if (capability == AcpCapability.loadSession ||
            capability.startsWith(vityoAcpExtensionPrefix) &&
                policy.allowedExtensions.contains(capability)) {
          capabilities.add(capability);
        }
      }
      state.capabilities = Set<String>.unmodifiable(capabilities);
    }
  }

  Future<void> _routeInboundRequest(
    _ConnectionState state,
    JsonRpcRequest request,
  ) async {
    if (request.method != AcpMethod.sessionRequestPermission) {
      await state.transport.send(
        JsonRpcErrorResponse(
          id: request.id,
          error: const JsonRpcError(code: -32601, message: 'method not found'),
        ),
      );
      return;
    }
    if (_inboundPermissions.length >= policy.maxPendingRequests) {
      await state.transport.send(
        JsonRpcErrorResponse(
          id: request.id,
          error: const JsonRpcError(
            code: -32000,
            message: 'permission request limit exceeded',
          ),
        ),
      );
      return;
    }
    final sessionId = _requireBoundedString(request.params, 'sessionId');
    final session =
        _sessionsByRemote[(state.agentId, state.generation, sessionId)];
    if (session == null) {
      await state.transport.send(
        JsonRpcErrorResponse(
          id: request.id,
          error: const JsonRpcError(code: -32602, message: 'unknown session'),
        ),
      );
      return;
    }
    final duplicateRequestId = _inboundPermissions.values.any(
      (permission) =>
          permission.state == state && permission.rpcId == request.id,
    );
    if (duplicateRequestId) {
      _failConnection(
        state,
        AgentClientFailure(
          'duplicate_request_id',
          'Agent reused a pending JSON-RPC request identifier',
        ),
      );
      return;
    }
    final toolCall = requireJsonObject(
      request.params['toolCall'],
      'permission tool call',
    );
    final toolCallId = _requireBoundedString(toolCall, 'toolCallId');
    final toolCallTitle = toolCall['title'] == null
        ? null
        : _requireBoundedString(toolCall, 'title', maxLength: 512);
    final toolCallKind = toolCall['kind'] == null
        ? null
        : _requireBoundedString(toolCall, 'kind');
    final rawOptions = request.params['options'];
    if (rawOptions is! List<Object?> ||
        rawOptions.isEmpty ||
        rawOptions.length > 16) {
      await state.transport.send(
        JsonRpcErrorResponse(
          id: request.id,
          error: const JsonRpcError(
            code: -32602,
            message: 'invalid permission options',
          ),
        ),
      );
      return;
    }
    final optionIds = <AgentPermissionDecision, String>{};
    final seenOptionIds = <String>{};
    for (final rawOption in rawOptions) {
      if (rawOption is! Map<String, Object?>) {
        throw const AgentProtocolException(
          'malformed_message',
          'permission options must be objects',
        );
      }
      final optionId = _requireBoundedString(rawOption, 'optionId');
      _requireBoundedString(rawOption, 'name', maxLength: 512);
      final kind = _requireBoundedString(rawOption, 'kind');
      if (!seenOptionIds.add(optionId)) {
        throw const AgentProtocolException(
          'malformed_message',
          'permission option identifiers must be unique',
        );
      }
      final decision = switch (kind) {
        'allow_once' => AgentPermissionDecision.allowOnce,
        'reject_once' => AgentPermissionDecision.rejectOnce,
        _ => null,
      };
      if (decision != null && optionIds.containsKey(decision)) {
        throw const AgentProtocolException(
          'malformed_message',
          'permission option kinds must be unambiguous',
        );
      }
      if (decision != null) {
        optionIds[decision] = optionId;
      }
    }
    if (optionIds.isEmpty) {
      await state.transport.send(
        JsonRpcErrorResponse(
          id: request.id,
          error: const JsonRpcError(
            code: -32602,
            message: 'no usable permission option',
          ),
        ),
      );
      return;
    }
    final permissionId = 'vityo-permission-${++_permissionSequence}';
    _inboundPermissions[permissionId] = _InboundPermission(
      rpcId: request.id,
      state: state,
      sessionId: session.id,
      optionIds: Map<AgentPermissionDecision, String>.unmodifiable(optionIds),
    );
    final optionKinds = <String>{
      for (final decision in optionIds.keys)
        switch (decision) {
          AgentPermissionDecision.allowOnce => 'allow_once',
          AgentPermissionDecision.rejectOnce => 'reject_once',
        },
    };
    final queued = _permissionQueue.add(
      AgentPermissionRequest(
        id: permissionId,
        agentId: state.agentId,
        sessionId: session.id,
        toolCallId: toolCallId,
        toolCallTitle: toolCallTitle,
        toolCallKind: toolCallKind,
        options: Set<String>.unmodifiable(optionKinds),
      ),
    );
    if (!queued) {
      _inboundPermissions.remove(permissionId);
      await state.transport.send(
        JsonRpcErrorResponse(
          id: request.id,
          error: const JsonRpcError(
            code: -32000,
            message: 'permission request limit exceeded',
          ),
        ),
      );
    }
  }

  Set<String> _decodeCapabilities(Object? value) {
    final json = requireJsonObject(value, 'agentCapabilities');
    final capabilities = <String>{};
    if (json['loadSession'] == true) {
      capabilities.add(AcpCapability.loadSession);
    }
    final metadata = json['_meta'];
    if (metadata != null && metadata is! Map<String, Object?>) {
      throw AgentClientFailure(
        'malformed_message',
        'agentCapabilities._meta must be an object',
      );
    }
    final vityoMetadata = metadata is Map<String, Object?>
        ? metadata[vityoAcpMetadataKey]
        : null;
    if (vityoMetadata != null && vityoMetadata is! Map<String, Object?>) {
      throw AgentClientFailure(
        'malformed_message',
        'Vityo capability metadata must be an object',
      );
    }
    final extensions = vityoMetadata is Map<String, Object?>
        ? vityoMetadata['extensions']
        : null;
    if (extensions != null) {
      if (extensions is! List<Object?> ||
          extensions.any((item) => item is! String)) {
        throw AgentClientFailure(
          'malformed_message',
          'Vityo extension metadata must be a list of strings',
        );
      }
      for (final extension in extensions.cast<String>()) {
        if (!extension.startsWith(vityoAcpExtensionPrefix) ||
            extension.length <= vityoAcpExtensionPrefix.length) {
          throw AgentClientFailure(
            'invalid_extension_namespace',
            'Agent advertised a Vityo extension outside the ACP namespace',
          );
        }
        if (extension.length > 256) {
          throw AgentClientFailure(
            'malformed_message',
            'Agent advertised an oversized Vityo extension identifier',
          );
        }
        if (policy.allowedExtensions.contains(extension)) {
          capabilities.add(extension);
        }
      }
    }
    return Set<String>.unmodifiable(capabilities);
  }

  void _failConnection(_ConnectionState state, AgentClientFailure failure) {
    if (state.failure != null || state.closing) {
      return;
    }
    state.failure = failure;
    _completePending(state, failure);
    _discardPermissionsOwnedBy(state);
    for (final session in _sessions.values.where(
      (session) =>
          session.agentId == state.agentId &&
          session.generation == state.generation,
    )) {
      unawaited(session._fail(failure));
    }
    unawaited(state.transport.close());
  }

  void _completePending(_ConnectionState state, AgentClientFailure failure) {
    final pending = state.pending.values.toList(growable: false);
    state.pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) {
        completer.completeError(failure);
      }
    }
  }

  AgentClientFailure _asClientFailure(Object error) {
    if (error is AgentClientFailure) {
      return error;
    }
    if (error is AgentProtocolException) {
      return AgentClientFailure(error.code, error.message);
    }
    return AgentClientFailure(
      'malformed_message',
      'Agent returned an invalid protocol payload',
    );
  }

  AgentClientFailure _outboundFailure(Object error) {
    if (error is AgentClientFailure) {
      return error;
    }
    if (error is AgentProtocolException) {
      return AgentClientFailure(error.code, error.message);
    }
    return AgentClientFailure(
      'transport_closed',
      'Agent protocol message could not be sent',
    );
  }

  String _requireBoundedString(
    Map<String, Object?> json,
    String key, {
    int maxLength = 256,
  }) {
    try {
      final value = requireJsonString(json, key);
      if (value.trim().isEmpty || value.length > maxLength) {
        throw AgentProtocolException(
          'malformed_message',
          '$key exceeds its character limit',
        );
      }
      return value;
    } on AgentProtocolException catch (error) {
      throw AgentClientFailure(error.code, error.message);
    }
  }

  String _workspacePath(Uri cwd) {
    if (!cwd.isAbsolute || cwd.scheme != 'file') {
      throw AgentClientFailure(
        'invalid_workspace',
        'Agent workspace must be an absolute file URI',
      );
    }
    final String path;
    try {
      path = cwd.normalizePath().toFilePath();
    } on Object {
      throw AgentClientFailure(
        'invalid_workspace',
        'Agent workspace URI could not be converted to a local path',
      );
    }
    if (path.trim().isEmpty || path.length > 32768) {
      throw AgentClientFailure(
        'invalid_workspace',
        'Agent workspace path is outside supported bounds',
      );
    }
    return path;
  }

  void _discardPermissionsOwnedBy(_ConnectionState state) {
    final permissionIds = _inboundPermissions.entries
        .where((entry) => entry.value.state == state)
        .map((entry) => entry.key)
        .toSet();
    if (permissionIds.isEmpty) {
      return;
    }
    _inboundPermissions.removeWhere(
      (id, permission) => permissionIds.contains(id),
    );
    _permissionQueue.removeWhere(
      (request) => permissionIds.contains(request.id),
    );
  }

  Future<void> _cancelPermissionsForSession(
    _ConnectionState state,
    String sessionId,
  ) async {
    final entries = _inboundPermissions.entries
        .where(
          (entry) =>
              entry.value.state == state && entry.value.sessionId == sessionId,
        )
        .toList(growable: false);
    for (final entry in entries) {
      final permission = entry.value;
      final inFlight = permission.resolution;
      if (permission.resolving && inFlight != null) {
        try {
          await inFlight;
        } on Object {
          // The cancelled response below is still required if selection failed.
        }
      }
      if (!identical(_inboundPermissions[entry.key], permission)) {
        continue;
      }
      permission.resolving = true;
      final resolution = state.transport.send(
        JsonRpcSuccessResponse(
          id: permission.rpcId,
          result: const <String, Object?>{
            'outcome': <String, Object?>{'outcome': 'cancelled'},
          },
        ),
      );
      permission.resolution = resolution;
      try {
        await resolution;
      } on Object catch (error) {
        permission.resolving = false;
        permission.resolution = null;
        throw _outboundFailure(error);
      }
      _inboundPermissions.remove(entry.key);
      _permissionQueue.removeWhere((request) => request.id == entry.key);
    }
  }

  void _ensureStateActive(_ConnectionState state) {
    _ensureOpen();
    if (state.failure != null ||
        state.closing ||
        !identical(_connections[state.agentId], state)) {
      throw AgentClientFailure(
        'transport_closed',
        'Agent connection is no longer active',
      );
    }
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
    required this.agentId,
    required this.generation,
    required this.id,
    required this.remoteId,
    required AgentSessionReducer reducer,
  }) : _registry = registry,
       _reducer = reducer;

  final AgentClientRegistry _registry;
  final AgentSessionReducer _reducer;
  final String agentId;
  final int generation;
  final String id;
  final String remoteId;
  bool _activePrompt = false;
  bool _cancelSent = false;
  bool _closed = false;

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
    if (text.length > _registry.policy.maxMessageBytes ||
        utf8.encode(text).length > _registry.policy.maxMessageBytes) {
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
    final state = await _registry._connectedState(agentId);
    if (state.generation != generation) {
      throw AgentClientFailure(
        'session_disconnected',
        'Session belongs to a previous Agent process generation',
      );
    }
    _activePrompt = true;
    _cancelSent = false;
    try {
      final result = await _registry._request(
        state,
        AcpMethod.sessionPrompt,
        <String, Object?>{
          'sessionId': remoteId,
          'prompt': <Map<String, Object?>>[
            <String, Object?>{'type': 'text', 'text': text},
          ],
        },
      );
      return AcpPromptResult.fromJson(result);
    } finally {
      _activePrompt = false;
    }
  }

  Future<bool> cancel() async {
    if (!_activePrompt || _cancelSent || _closed) {
      return false;
    }
    final state = await _registry._connectedState(agentId);
    if (state.generation != generation) {
      return false;
    }
    _cancelSent = true;
    await _registry._notify(state, AcpMethod.sessionCancel, <String, Object?>{
      'sessionId': remoteId,
    });
    await _registry._cancelPermissionsForSession(state, id);
    return true;
  }

  Future<void> _close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _reducer.close();
  }

  Future<void> _markRestored() => _reducer.reducePriority(
    AgentSessionUpdate(
      sessionId: id,
      kind: 'session_state',
      payload: <String, Object?>{
        'id': 'connection-restored-$generation',
        'status': 'active',
      },
    ),
  );

  Future<void> _fail(AgentClientFailure failure) {
    if (_closed) {
      return Future<void>.value();
    }
    return _reducer.reducePriority(
      AgentSessionUpdate(
        sessionId: id,
        kind: 'session_state',
        payload: <String, Object?>{
          'id': 'connection-failure-$generation',
          'status': 'failed',
          'failureCode': failure.code,
        },
      ),
    );
  }
}

final class _ConnectionState {
  _ConnectionState({
    required this.agentId,
    required this.generation,
    required this.transport,
  });

  final String agentId;
  final int generation;
  final AgentClientTransport transport;
  final Map<JsonRpcId, Completer<Object?>> pending =
      <JsonRpcId, Completer<Object?>>{};
  late final StreamSubscription<JsonRpcMessage> subscription;
  int protocolVersion = 0;
  Set<String> capabilities = const <String>{};
  Map<String, Object?> metadata = const <String, Object?>{};
  AgentClientFailure? failure;
  bool closing = false;

  AgentConnectionSnapshot get snapshot => AgentConnectionSnapshot(
    agentId: agentId,
    protocolVersion: protocolVersion,
    generation: generation,
    capabilities: Set<String>.unmodifiable(capabilities),
    metadata: Map<String, Object?>.unmodifiable(metadata),
  );
}

final class _InboundPermission {
  _InboundPermission({
    required this.rpcId,
    required this.state,
    required this.sessionId,
    required this.optionIds,
  });

  final JsonRpcId rpcId;
  final _ConnectionState state;
  final String sessionId;
  final Map<AgentPermissionDecision, String> optionIds;
  bool resolving = false;
  Future<void>? resolution;
}
