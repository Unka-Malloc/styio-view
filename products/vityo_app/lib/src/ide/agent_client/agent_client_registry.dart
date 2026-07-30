import 'dart:async';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';

import 'agent_client_models.dart';
import 'agent_process_supervisor.dart';
import 'agent_session_reducer.dart';

final class AgentClientRegistry {
  AgentClientRegistry({
    required Map<String, AgentLaunchDescriptor> descriptors,
    this.policy = const AgentClientPolicy(),
    AgentProcessSupervisor supervisor = const AgentProcessSupervisor(),
  }) : _descriptors = Map<String, AgentLaunchDescriptor>.unmodifiable(
         descriptors,
       ),
       _supervisor = supervisor {
    if (_descriptors.isEmpty) {
      throw ArgumentError.value(
        descriptors,
        'descriptors',
        'must contain at least one Agent',
      );
    }
    for (final extension in policy.allowedExtensions) {
      if (!extension.startsWith('vityo/')) {
        throw ArgumentError.value(
          extension,
          'allowedExtensions',
          'must use the vityo/ namespace',
        );
      }
    }
  }

  final Map<String, AgentLaunchDescriptor> _descriptors;
  final AgentProcessSupervisor _supervisor;
  final AgentClientPolicy policy;
  final Map<String, _ConnectionState> _connections =
      <String, _ConnectionState>{};
  final Map<String, AgentClientSession> _sessions =
      <String, AgentClientSession>{};
  final Map<String, int> _generations = <String, int>{};
  final Map<String, _InboundPermission> _inboundPermissions =
      <String, _InboundPermission>{};
  final PermissionRequestQueue _permissionQueue = PermissionRequestQueue();
  int _requestSequence = 0;
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
    if (existing != null) {
      existing.closing = true;
      await existing.transport.close();
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
    final state = await _connectedState(agentId);
    final result = requireJsonObject(
      await _request(state, AcpMethod.sessionNew, <String, Object?>{
        'cwd': cwd.toFilePath(),
        'mcpServers': const <Object?>[],
      }),
      'session/new result',
    );
    final sessionId = requireJsonString(result, 'sessionId');
    return _createSession(state, sessionId);
  }

  Future<AgentClientSession> reconnectSession({
    required String agentId,
    required String sessionId,
    required Uri cwd,
  }) async {
    final state = await _connectedState(agentId);
    if (!state.capabilities.contains(AcpCapability.loadSession)) {
      throw AgentClientFailure(
        'capability_revoked',
        'Agent does not currently support session/load',
      );
    }
    final result = requireJsonObject(
      await _request(state, AcpMethod.sessionLoad, <String, Object?>{
        'sessionId': sessionId,
        'cwd': cwd.toFilePath(),
        'mcpServers': const <Object?>[],
      }),
      'session/load result',
    );
    final loadedId = requireJsonString(result, 'sessionId');
    if (loadedId != sessionId) {
      throw AgentClientFailure(
        'session_mismatch',
        'Agent loaded a different session',
      );
    }
    return _createSession(state, loadedId);
  }

  Future<Object?> invokeExtension({
    required String agentId,
    required String method,
    Map<String, Object?> params = const <String, Object?>{},
  }) async {
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
    final inbound = _inboundPermissions.remove(permissionId);
    if (inbound == null) {
      throw AgentClientFailure(
        'unknown_permission',
        'Permission request is no longer pending',
      );
    }
    final optionId = switch (decision) {
      AgentPermissionDecision.allowOnce => 'allow_once',
      AgentPermissionDecision.rejectOnce => 'reject_once',
    };
    if (!inbound.options.contains(optionId)) {
      throw AgentClientFailure(
        'invalid_permission_decision',
        'Permission option was not offered by the Agent',
      );
    }
    await inbound.state.transport.send(
      JsonRpcSuccessResponse(
        id: inbound.rpcId,
        result: <String, Object?>{'outcome': 'selected', 'optionId': optionId},
      ),
    );
  }

  Future<AgentShutdownReceipt> disconnect(String agentId) async {
    final state = _connections.remove(agentId);
    if (state == null) {
      return AgentShutdownReceipt(
        agentId: agentId,
        terminated: true,
        forced: false,
        exitCode: 0,
      );
    }
    state.closing = true;
    _completePending(
      state,
      AgentClientFailure('transport_closed', 'Agent connection was closed'),
    );
    await state.subscription.cancel();
    final ownedSessions = _sessions.values
        .where((session) => session.agentId == agentId)
        .toList(growable: false);
    for (final session in ownedSessions) {
      _sessions.remove(session.id);
      await session._close();
    }
    _inboundPermissions.removeWhere(
      (_, permission) => permission.state == state,
    );
    return state.transport.close();
  }

  Future<List<AgentShutdownReceipt>> close() {
    return _shutdown ??= _closeAll();
  }

  Future<List<AgentShutdownReceipt>> _closeAll() async {
    _closed = true;
    final agentIds = _connections.keys.toList(growable: false);
    final receipts = <AgentShutdownReceipt>[];
    for (final agentId in agentIds) {
      receipts.add(await disconnect(agentId));
    }
    _permissionQueue.close();
    return List<AgentShutdownReceipt>.unmodifiable(receipts);
  }

  Future<_ConnectionState> _connectedState(String agentId) async {
    final current = _connections[agentId];
    if (current != null && current.failure == null) {
      return current;
    }
    await connect(agentId);
    return _connections[agentId]!;
  }

  AgentClientSession _createSession(_ConnectionState state, String sessionId) {
    final former = _sessions.remove(sessionId);
    if (former != null) {
      unawaited(former._close());
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
    );
    final session = AgentClientSession._(
      registry: this,
      agentId: state.agentId,
      generation: state.generation,
      id: sessionId,
      reducer: reducer,
    );
    _sessions[sessionId] = session;
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
    final id = JsonRpcId.string('styio-${state.generation}-$_requestSequence');
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
    } finally {
      state.pending.remove(id);
    }
  }

  Future<void> _notify(
    _ConnectionState state,
    String method,
    Map<String, Object?> params,
  ) =>
      state.transport.send(JsonRpcNotification(method: method, params: params));

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
        unawaited(_routeNotification(state, message));
      case JsonRpcRequest():
        unawaited(_routeInboundRequest(state, message));
    }
  }

  Future<void> _routeNotification(
    _ConnectionState state,
    JsonRpcNotification notification,
  ) async {
    if (notification.method == AcpMethod.sessionUpdate) {
      final sessionId = requireJsonString(notification.params, 'sessionId');
      final session = _sessions[sessionId];
      if (session == null ||
          session.agentId != state.agentId ||
          session.generation != state.generation) {
        return;
      }
      final update = requireJsonObject(
        notification.params['update'],
        'session update',
      );
      final kind = requireJsonString(update, 'sessionUpdate');
      final content = update['content'];
      final text = content is Map<String, Object?> && content['text'] is String
          ? content['text'] as String
          : null;
      await session._reducer.reduce(
        AgentSessionUpdate(
          sessionId: sessionId,
          kind: kind,
          text: text,
          payload: Map<String, Object?>.unmodifiable(update),
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
      state.capabilities = Set<String>.unmodifiable(
        raw.cast<String>().where(
          (capability) =>
              capability == AcpCapability.loadSession ||
              policy.allowedExtensions.contains(capability),
        ),
      );
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
    final sessionId = requireJsonString(request.params, 'sessionId');
    final session = _sessions[sessionId];
    if (session == null ||
        session.agentId != state.agentId ||
        session.generation != state.generation) {
      await state.transport.send(
        JsonRpcErrorResponse(
          id: request.id,
          error: const JsonRpcError(code: -32602, message: 'unknown session'),
        ),
      );
      return;
    }
    final rawOptions = request.params['options'];
    if (rawOptions is! List<Object?>) {
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
    final options = <String>{};
    for (final rawOption in rawOptions) {
      if (rawOption is! Map<String, Object?> ||
          rawOption['optionId'] is! String) {
        continue;
      }
      options.add(rawOption['optionId'] as String);
    }
    if (options.isEmpty) {
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
    final permissionId = request.id.toString();
    _inboundPermissions[permissionId] = _InboundPermission(
      rpcId: request.id,
      state: state,
      options: Set<String>.unmodifiable(options),
    );
    _permissionQueue.add(
      AgentPermissionRequest(
        id: permissionId,
        agentId: state.agentId,
        sessionId: sessionId,
        options: Set<String>.unmodifiable(options),
      ),
    );
  }

  Set<String> _decodeCapabilities(Object? value) {
    final json = requireJsonObject(value, 'agentCapabilities');
    final capabilities = <String>{};
    if (json['loadSession'] == true) {
      capabilities.add(AcpCapability.loadSession);
    }
    final extensions = json['vityoExtensions'];
    if (extensions != null) {
      if (extensions is! List<Object?> ||
          extensions.any((item) => item is! String)) {
        throw AgentClientFailure(
          'malformed_message',
          'vityoExtensions must be a list of strings',
        );
      }
      for (final extension in extensions.cast<String>()) {
        if (!extension.startsWith('vityo/')) {
          throw AgentClientFailure(
            'invalid_extension_namespace',
            'Agent advertised a non-namespaced Vityo extension',
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
    required AgentSessionReducer reducer,
  }) : _registry = registry,
       _reducer = reducer;

  final AgentClientRegistry _registry;
  final AgentSessionReducer _reducer;
  final String agentId;
  final int generation;
  final String id;
  bool _activePrompt = false;
  bool _cancelSent = false;
  bool _closed = false;

  Stream<AgentSessionUpdate> get updates => _reducer.updates;

  AgentSessionSnapshot get snapshot => _reducer.snapshot;

  Future<AcpPromptResult> prompt(String text) async {
    if (_closed) {
      throw AgentClientFailure('session_closed', 'Agent session is closed');
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
          'sessionId': id,
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
      'sessionId': id,
    });
    return true;
  }

  Future<void> _close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _reducer.close();
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
  const _InboundPermission({
    required this.rpcId,
    required this.state,
    required this.options,
  });

  final JsonRpcId rpcId;
  final _ConnectionState state;
  final Set<String> options;
}
