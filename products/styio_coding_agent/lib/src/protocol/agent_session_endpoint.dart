library;

import 'dart:async';

import 'package:styio_agent_protocol/styio_agent_protocol.dart';

import '../application/agent_runtime.dart';
import '../application/agent_session_service.dart';

abstract interface class AgentServerTransport {
  Stream<JsonRpcMessage> get incoming;

  Future<void> send(JsonRpcMessage message);

  Future<void> close();
}

abstract interface class McpSessionAttachmentHandler {
  Future<void> attach({
    required String sessionId,
    required List<Map<String, Object?>> servers,
  });
}

final class AgentEndpointPolicy {
  const AgentEndpointPolicy({
    required this.maxConcurrentSessions,
    required this.maxPendingRequests,
    required this.maxSessions,
    required this.maxPromptCharacters,
    this.maxMcpServersPerSession = 8,
    this.permissionResponseTimeout = const Duration(seconds: 30),
  }) : _validation =
           1 ~/
           ((maxConcurrentSessions > 0 &&
                   maxPendingRequests > 0 &&
                   maxSessions > 0 &&
                   maxPromptCharacters > 0 &&
                   maxMcpServersPerSession > 0)
               ? 1
               : 0);

  final int maxConcurrentSessions;
  final int maxPendingRequests;
  final int maxSessions;
  final int maxPromptCharacters;
  final int maxMcpServersPerSession;
  final Duration permissionResponseTimeout;
  final int _validation;

  bool get isValid =>
      _validation == 1 &&
      maxConcurrentSessions > 0 &&
      maxPendingRequests > 0 &&
      maxSessions > 0 &&
      maxPromptCharacters > 0 &&
      maxMcpServersPerSession > 0 &&
      permissionResponseTimeout > Duration.zero;
}

final class AgentSessionEndpoint {
  AgentSessionEndpoint({
    required this.runtime,
    required this.defaultRootId,
    required this.policy,
    String Function(int)? sessionIdFactory,
    this.mcpAttachments,
  }) : _sessionIdFactory =
           sessionIdFactory ?? ((sequence) => 'styio-session-$sequence') {
    if (!policy.isValid || defaultRootId.trim().isEmpty) {
      throw ArgumentError('Agent endpoint configuration is invalid.');
    }
  }

  final AgentRuntime runtime;
  final String defaultRootId;
  final AgentEndpointPolicy policy;
  final McpSessionAttachmentHandler? mcpAttachments;
  final String Function(int) _sessionIdFactory;
  final Map<String, _ProtocolSession> _sessions = <String, _ProtocolSession>{};
  final Set<Future<void>> _pending = <Future<void>>{};
  final Map<JsonRpcId, _PendingPermission> _permissions =
      <JsonRpcId, _PendingPermission>{};
  Set<String> _capabilities = const <String>{};
  AgentServerTransport? _transport;
  Future<void> _sendLane = Future<void>.value();
  var _initialized = false;
  var _activePrompts = 0;
  var _sessionSequence = 0;
  var _requestSequence = 0;

  Future<void> serve(AgentServerTransport transport) async {
    if (_transport != null) {
      throw StateError('Agent endpoint is already serving a transport.');
    }
    _transport = transport;
    try {
      await for (final message in transport.incoming) {
        switch (message) {
          case JsonRpcRequest():
            if (_pending.length >= policy.maxPendingRequests) {
              await _sendError(message.id, -32000, 'request limit exceeded');
              continue;
            }
            late final Future<void> operation;
            operation = _handleRequest(
              message,
            ).whenComplete(() => _pending.remove(operation));
            _pending.add(operation);
          case JsonRpcNotification():
            await _handleNotification(message);
          case JsonRpcSuccessResponse():
            _resolvePermission(message);
          case JsonRpcErrorResponse():
            _rejectPermission(message);
        }
      }
      await Future.wait<void>(_pending.toList(growable: false));
    } finally {
      for (final permission in _permissions.values) {
        if (!permission.completer.isCompleted) {
          permission.completer.completeError(
            StateError('Agent transport closed during permission request.'),
          );
        }
      }
      _permissions.clear();
      await transport.close();
      _transport = null;
    }
  }

  Future<String> requestPermission({
    required String sessionId,
    required Set<String> options,
  }) async {
    if (!_sessions.containsKey(sessionId) ||
        options.isEmpty ||
        options.any((option) => option.trim().isEmpty) ||
        _permissions.length >= policy.maxPendingRequests) {
      throw StateError('Permission request is invalid or over budget.');
    }
    final id = JsonRpcId.string('agent-permission-${++_requestSequence}');
    final pending = _PendingPermission(
      options: Set<String>.unmodifiable(options),
    );
    _permissions[id] = pending;
    final ordered = options.toList(growable: false)..sort();
    try {
      await _sendMessage(
        JsonRpcRequest(
          id: id,
          method: AcpMethod.sessionRequestPermission,
          params: <String, Object?>{
            'sessionId': sessionId,
            'options': <Map<String, Object?>>[
              for (final option in ordered)
                <String, Object?>{
                  'optionId': option,
                  'name': option,
                  'kind': option.startsWith('allow')
                      ? 'allow_once'
                      : 'reject_once',
                },
            ],
          },
        ),
      );
      return await pending.completer.future.timeout(
        policy.permissionResponseTimeout,
      );
    } finally {
      _permissions.remove(id);
    }
  }

  Future<void> updateCapabilities(Set<String> capabilities) async {
    if (capabilities.any(
      (capability) =>
          capability != AcpCapability.loadSession &&
          !capability.startsWith('styio/'),
    )) {
      throw ArgumentError('Agent capability is not namespaced.');
    }
    _capabilities = Set<String>.unmodifiable(capabilities);
    final transport = _transport;
    if (transport != null && _initialized) {
      final ordered = _capabilities.toList(growable: false)..sort();
      await _sendMessage(
        JsonRpcNotification(
          method: AcpMethod.capabilitiesChanged,
          params: <String, Object?>{'capabilities': ordered},
        ),
      );
    }
  }

  Future<void> _handleRequest(JsonRpcRequest request) async {
    try {
      switch (request.method) {
        case AcpMethod.initialize:
          await _initialize(request);
        case AcpMethod.sessionNew:
          await _newSession(request);
        case AcpMethod.sessionLoad:
          await _loadSession(request);
        case AcpMethod.sessionPrompt:
          await _prompt(request);
        default:
          await _sendError(request.id, -32601, 'method not found');
      }
    } on AgentProtocolException {
      await _sendError(request.id, -32602, 'invalid request');
    } on Object {
      await _sendError(request.id, -32000, 'agent request failed');
    }
  }

  Future<void> _initialize(JsonRpcRequest request) async {
    final version = request.params['protocolVersion'];
    if (version != acpProtocolVersion) {
      await _sendError(request.id, -32001, 'unsupported protocol version');
      return;
    }
    _initialized = true;
    final extensions =
        _capabilities
            .where((capability) => capability.startsWith('styio/'))
            .toList(growable: false)
          ..sort();
    await _sendSuccess(request.id, <String, Object?>{
      'protocolVersion': acpProtocolVersion,
      'agentInfo': const <String, Object?>{
        'name': 'styio-coding-agent',
        'version': '0.1.0',
      },
      'agentCapabilities': <String, Object?>{
        'loadSession': _capabilities.contains(AcpCapability.loadSession),
        'styioExtensions': extensions,
      },
      '_meta': const <String, Object?>{'transport': 'acp-jsonrpc'},
    });
  }

  Future<void> _newSession(JsonRpcRequest request) async {
    if (!_initialized) {
      await _sendError(request.id, -32002, 'initialize required');
      return;
    }
    if (_sessions.length >= policy.maxSessions) {
      await _sendError(request.id, -32000, 'session limit exceeded');
      return;
    }
    final cwd = requireJsonString(request.params, 'cwd');
    if (cwd.length > 4096) {
      throw const AgentProtocolException(
        'invalid_identifier',
        'cwd is too long',
      );
    }
    final id = _sessionIdFactory(++_sessionSequence);
    if (id.trim().isEmpty || id.length > 256 || _sessions.containsKey(id)) {
      await _sendError(request.id, -32000, 'session allocation failed');
      return;
    }
    final rawServers = request.params['mcpServers'];
    if (rawServers is! List<Object?> ||
        rawServers.length > policy.maxMcpServersPerSession ||
        rawServers.any((server) => server is! Map<String, Object?>)) {
      await _sendError(request.id, -32602, 'invalid MCP attachments');
      return;
    }
    final servers = <Map<String, Object?>>[
      for (final server in rawServers)
        Map<String, Object?>.unmodifiable(server! as Map<String, Object?>),
    ];
    if (servers.isNotEmpty) {
      final handler = mcpAttachments;
      if (handler == null) {
        await _sendError(request.id, -32003, 'MCP capability unavailable');
        return;
      }
      await handler.attach(sessionId: id, servers: servers);
    }
    _sessions[id] = _ProtocolSession(id: id, rootId: defaultRootId);
    await _sendSuccess(request.id, <String, Object?>{'sessionId': id});
  }

  Future<void> _loadSession(JsonRpcRequest request) async {
    if (!_capabilities.contains(AcpCapability.loadSession)) {
      await _sendError(request.id, -32003, 'capability unavailable');
      return;
    }
    final id = requireJsonString(request.params, 'sessionId');
    if (!_sessions.containsKey(id)) {
      await _sendError(request.id, -32602, 'unknown session');
      return;
    }
    await _sendSuccess(request.id, <String, Object?>{'sessionId': id});
  }

  Future<void> _prompt(JsonRpcRequest request) async {
    final id = requireJsonString(request.params, 'sessionId');
    final session = _sessions[id];
    if (session == null) {
      await _sendError(request.id, -32602, 'unknown session');
      return;
    }
    if (session.promptActive) {
      await _sendError(request.id, -32000, 'prompt already active');
      return;
    }
    if (_activePrompts >= policy.maxConcurrentSessions) {
      await _sendError(request.id, -32000, 'session concurrency exceeded');
      return;
    }
    final prompt = _decodePrompt(request.params['prompt']);
    session.promptActive = true;
    _activePrompts += 1;
    try {
      final receipt = await runtime.run(
        AgentRunRequest(
          sessionId: session.id,
          goal: prompt,
          rootId: session.rootId,
        ),
      );
      await _sendMessage(
        JsonRpcNotification(
          method: AcpMethod.sessionUpdate,
          params: <String, Object?>{
            'sessionId': session.id,
            'update': <String, Object?>{
              'sessionUpdate': 'terminal',
              'content': <String, Object?>{
                'type': 'text',
                'text': receipt.state.name,
              },
              'receipt': receipt.toJson(),
            },
          },
        ),
      );
      final stopReason = switch (receipt.state) {
        AgentSessionState.completed => AcpStopReason.endTurn,
        AgentSessionState.cancelled => AcpStopReason.cancelled,
        AgentSessionState.failed => AcpStopReason.refusal,
        AgentSessionState.idle ||
        AgentSessionState.running => AcpStopReason.refusal,
      };
      await _sendSuccess(request.id, <String, Object?>{
        'stopReason': stopReason,
      });
    } finally {
      session.promptActive = false;
      _activePrompts -= 1;
    }
  }

  String _decodePrompt(Object? raw) {
    if (raw is! List<Object?> || raw.isEmpty) {
      throw const AgentProtocolException(
        'malformed_message',
        'prompt must be a non-empty array',
      );
    }
    final parts = <String>[];
    var characters = 0;
    for (final item in raw) {
      if (item is! Map<String, Object?> ||
          item['type'] != 'text' ||
          item['text'] is! String) {
        throw const AgentProtocolException(
          'malformed_message',
          'only text prompt parts are supported',
        );
      }
      final text = item['text']! as String;
      characters += text.length;
      if (text.isEmpty || characters > policy.maxPromptCharacters) {
        throw const AgentProtocolException(
          'message_too_large',
          'prompt exceeds its configured bound',
        );
      }
      parts.add(text);
    }
    return parts.join('\n');
  }

  Future<void> _handleNotification(JsonRpcNotification notification) async {
    if (notification.method != AcpMethod.sessionCancel) return;
    final rawId = notification.params['sessionId'];
    if (rawId is String && _sessions.containsKey(rawId)) {
      runtime.cancel(rawId);
    }
  }

  void _resolvePermission(JsonRpcSuccessResponse response) {
    final pending = _permissions[response.id];
    if (pending == null || pending.completer.isCompleted) return;
    try {
      final result = requireJsonObject(response.result, 'permission result');
      final option = requireJsonString(result, 'optionId');
      if (result['outcome'] != 'selected' ||
          !pending.options.contains(option)) {
        throw const AgentProtocolException(
          'malformed_message',
          'invalid permission decision',
        );
      }
      pending.completer.complete(option);
    } on Object catch (error, stackTrace) {
      pending.completer.completeError(error, stackTrace);
    }
  }

  void _rejectPermission(JsonRpcErrorResponse response) {
    final pending = _permissions[response.id];
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(
        StateError('Permission request was rejected by the client.'),
      );
    }
  }

  Future<void> _sendSuccess(JsonRpcId id, Object? result) =>
      _sendMessage(JsonRpcSuccessResponse(id: id, result: result));

  Future<void> _sendError(JsonRpcId id, int code, String message) =>
      _sendMessage(
        JsonRpcErrorResponse(
          id: id,
          error: JsonRpcError(code: code, message: message),
        ),
      );

  Future<void> _sendMessage(JsonRpcMessage message) {
    final transport = _transport;
    if (transport == null) {
      return Future<void>.error(StateError('Agent endpoint is not serving.'));
    }
    final operation = _sendLane.then((_) => transport.send(message));
    _sendLane = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }
}

final class _ProtocolSession {
  _ProtocolSession({required this.id, required this.rootId});

  final String id;
  final String rootId;
  bool promptActive = false;
}

final class _PendingPermission {
  _PendingPermission({required this.options});

  final Set<String> options;
  final Completer<String> completer = Completer<String>();
}
