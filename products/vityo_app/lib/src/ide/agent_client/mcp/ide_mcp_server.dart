import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';

import '../../workbench/ide_fact_provider.dart';
import '../tools/ide_tool_catalog.dart';
import '../tools/tool_security_policy.dart';
import 'workspace_root_registry.dart';

const mcpProtocolVersion = '2025-11-25';
const mcpCompatibleProtocolVersions = <String>{
  mcpProtocolVersion,
  '2025-06-18',
};

final class IdeMcpServer {
  IdeMcpServer({
    required WorkspaceRootRegistry roots,
    required IdeToolCatalog tools,
    required ToolSecurityPolicy security,
  }) : _roots = roots,
       _tools = tools,
       _security = security {
    _rootSubscription = roots.changes.listen(_onRootChange);
    _toolSubscription = tools.changes.listen(_onToolChange);
  }

  final WorkspaceRootRegistry _roots;
  final IdeToolCatalog _tools;
  final ToolSecurityPolicy _security;
  final Map<String, _McpSessionState> _sessions = <String, _McpSessionState>{};
  final Map<String, StreamController<JsonRpcNotification>> _notifications =
      <String, StreamController<JsonRpcNotification>>{};
  late final StreamSubscription<WorkspaceRootChange> _rootSubscription;
  late final StreamSubscription<ToolCatalogChange> _toolSubscription;
  int _callSequence = 0;
  bool _closed = false;

  Stream<JsonRpcNotification> notificationsFor(String sessionId) =>
      _notificationController(sessionId).stream;

  Future<JsonRpcMessage?> handle({
    required String sessionId,
    required JsonRpcMessage message,
  }) async {
    if (_closed) {
      throw StateError('IDE MCP server is closed');
    }
    if (message is JsonRpcNotification) {
      if (message.method == 'notifications/initialized') {
        final session = _sessions[sessionId];
        if (session != null) {
          session.ready = true;
        }
      }
      return null;
    }
    if (message is! JsonRpcRequest) {
      return null;
    }
    try {
      final result = await _routeRequest(sessionId, message);
      return JsonRpcSuccessResponse(id: message.id, result: result);
    } on _McpFailure catch (error) {
      return JsonRpcErrorResponse(
        id: message.id,
        error: JsonRpcError(
          code: error.rpcCode,
          message: error.message,
          data: <String, Object?>{'code': error.code},
        ),
      );
    } on AgentProtocolException catch (error) {
      return JsonRpcErrorResponse(
        id: message.id,
        error: JsonRpcError(
          code: -32602,
          message: 'invalid MCP request',
          data: <String, Object?>{'code': error.code},
        ),
      );
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _rootSubscription.cancel();
    await _toolSubscription.cancel();
    for (final controller in _notifications.values) {
      await controller.close();
    }
    _notifications.clear();
  }

  Future<Map<String, Object?>> _routeRequest(
    String sessionId,
    JsonRpcRequest request,
  ) async {
    if (request.method == 'initialize') {
      return _initialize(sessionId, request.params);
    }
    final session = _sessions[sessionId];
    if (session == null || !session.ready) {
      throw const _McpFailure(
        rpcCode: -32002,
        code: 'not_initialized',
        message: 'MCP session is not initialized',
      );
    }
    return switch (request.method) {
      'tools/list' => _listTools(sessionId),
      'tools/call' => await _callTool(sessionId, request.params),
      'resources/list' => _listResources(sessionId),
      'resources/read' => await _readResource(sessionId, request.params),
      'prompts/list' => _listPrompts(sessionId),
      'prompts/get' => _getPrompt(sessionId, request.params),
      _ => throw const _McpFailure(
        rpcCode: -32601,
        code: 'method_not_found',
        message: 'MCP method is not supported',
      ),
    };
  }

  Map<String, Object?> _initialize(
    String sessionId,
    Map<String, Object?> params,
  ) {
    final requested = params['protocolVersion'];
    if (requested is! String ||
        !mcpCompatibleProtocolVersions.contains(requested)) {
      throw const _McpFailure(
        rpcCode: -32602,
        code: 'unsupported_version',
        message: 'MCP protocol version is not supported',
      );
    }
    final capabilities = params['capabilities'];
    if (capabilities is! Map<String, Object?>) {
      throw const _McpFailure(
        rpcCode: -32602,
        code: 'invalid_capabilities',
        message: 'MCP client capabilities must be an object',
      );
    }
    _sessions[sessionId] = _McpSessionState(
      protocolVersion: requested,
      clientCapabilities: Map<String, Object?>.unmodifiable(capabilities),
    );
    _notificationController(sessionId);
    return <String, Object?>{
      'protocolVersion': requested,
      'capabilities': const <String, Object?>{
        'tools': <String, Object?>{'listChanged': true},
        'resources': <String, Object?>{'subscribe': false, 'listChanged': true},
        'prompts': <String, Object?>{'listChanged': true},
      },
      'serverInfo': const <String, Object?>{
        'name': 'vityo-mcp-host',
        'version': '0.1.0',
      },
      'instructions':
          'IDE facts and workspace resources are revision and root scoped.',
    };
  }

  Map<String, Object?> _listTools(String sessionId) {
    final roots = _roots.snapshot(sessionId);
    return <String, Object?>{
      'tools': _tools
          .visibleTools(sessionId, hasRoots: roots.roots.isNotEmpty)
          .map((descriptor) => descriptor.toMcpJson())
          .toList(growable: false),
      '_meta': <String, Object?>{'vityo/rootRevision': roots.revision},
    };
  }

  Future<Map<String, Object?>> _callTool(
    String sessionId,
    Map<String, Object?> params,
  ) async {
    final name = params['name'];
    final rawArguments = params['arguments'];
    if (name is! String ||
        name.isEmpty ||
        rawArguments != null && rawArguments is! Map<String, Object?>) {
      throw const _McpFailure(
        rpcCode: -32602,
        code: 'schema_validation_failed',
        message: 'tool name and object arguments are required',
      );
    }
    final arguments = rawArguments is Map<String, Object?>
        ? Map<String, Object?>.unmodifiable(rawArguments)
        : const <String, Object?>{};
    final rootSnapshot = _roots.snapshot(sessionId);
    final lookup = _tools.lookup(
      sessionId,
      name,
      hasRoots: rootSnapshot.roots.isNotEmpty,
    );
    if (!lookup.visible) {
      final descriptor = _tools.descriptorFor(name);
      final receipt = _record(
        sessionId: sessionId,
        toolName: name,
        outcome: ToolAuditOutcome.denied,
        code: lookup.code,
        risks: descriptor?.risks ?? const <IdeToolRisk>{},
        rootRevision: rootSnapshot.revision,
      );
      return _toolError(
        lookup.code,
        'tool is not currently available',
        receipt,
      );
    }
    final adapter = lookup.adapter!;
    final descriptor = adapter.descriptor;
    final schemaFailure = _validateArguments(descriptor, arguments);
    if (schemaFailure != null) {
      final receipt = _record(
        sessionId: sessionId,
        toolName: name,
        outcome: ToolAuditOutcome.denied,
        code: schemaFailure,
        risks: descriptor.risks,
        rootRevision: rootSnapshot.revision,
      );
      return _toolError(
        schemaFailure,
        'tool arguments do not match the declared schema',
        receipt,
      );
    }

    RootAuthorization? rootAuthorization;
    if (descriptor.requiresWorkspacePath) {
      final path = arguments['path'];
      if (path is! String || path.isEmpty) {
        final receipt = _record(
          sessionId: sessionId,
          toolName: name,
          outcome: ToolAuditOutcome.denied,
          code: 'schema_validation_failed',
          risks: descriptor.risks,
          rootRevision: rootSnapshot.revision,
        );
        return _toolError(
          'schema_validation_failed',
          'workspace path is required',
          receipt,
        );
      }
      rootAuthorization = await _roots.authorize(
        sessionId: sessionId,
        candidate: path,
      );
      if (!rootAuthorization.allowed) {
        final receipt = _record(
          sessionId: sessionId,
          toolName: name,
          outcome: ToolAuditOutcome.denied,
          code: rootAuthorization.code,
          risks: descriptor.risks,
          rootRevision: rootAuthorization.rootRevision,
        );
        return _toolError(
          rootAuthorization.code,
          'workspace path is not authorized',
          receipt,
        );
      }
    }

    final authorization = _security.authorize(
      sessionId: sessionId,
      descriptor: descriptor,
      arguments: arguments,
      rootId: rootAuthorization?.rootId,
    );
    if (!authorization.allowed) {
      final receipt = _record(
        sessionId: sessionId,
        toolName: name,
        outcome: ToolAuditOutcome.denied,
        code: authorization.code,
        risks: descriptor.risks,
        rootRevision: rootAuthorization?.rootRevision ?? rootSnapshot.revision,
      );
      return _toolError(
        authorization.code,
        'tool authorization was denied',
        receipt,
      );
    }

    _callSequence += 1;
    try {
      final result = await adapter.invoke(
        IdeToolInvocation(
          callId: 'mcp-tool-$_callSequence',
          sessionId: sessionId,
          arguments: arguments,
          expectedWorkspaceRevision:
              arguments['expectedWorkspaceRevision'] as int?,
        ),
      );
      final sanitized =
          _security.sanitizer.sanitize(<String, Object?>{
                ...result.structuredContent,
                '_meta': <String, Object?>{
                  'workspaceRevision': result.workspaceRevision,
                  'provenance': result.provenance,
                  'sensitivity': result.sensitivity.name,
                  'rootRevision':
                      rootAuthorization?.rootRevision ?? rootSnapshot.revision,
                },
              })
              as Map<String, Object?>;
      if (!_security.resultWithinLimit(sanitized)) {
        final receipt = _record(
          sessionId: sessionId,
          toolName: name,
          outcome: ToolAuditOutcome.failed,
          code: 'result_limit_exceeded',
          risks: descriptor.risks,
          rootRevision:
              rootAuthorization?.rootRevision ?? rootSnapshot.revision,
          workspaceRevision: result.workspaceRevision,
          provenance: result.provenance,
        );
        return _toolError(
          'result_limit_exceeded',
          'tool result exceeds the configured byte limit',
          receipt,
        );
      }
      final receipt = _record(
        sessionId: sessionId,
        toolName: name,
        outcome: ToolAuditOutcome.succeeded,
        code: 'succeeded',
        risks: descriptor.risks,
        rootRevision: rootAuthorization?.rootRevision ?? rootSnapshot.revision,
        workspaceRevision: result.workspaceRevision,
        provenance: result.provenance,
      );
      sanitized['_meta'] = <String, Object?>{
        ...(sanitized['_meta'] as Map<String, Object?>),
        'auditReceipt': receipt.toJson(),
      };
      if (!_security.resultWithinLimit(sanitized)) {
        _security.auditLog.discardLast(receipt);
        final failedReceipt = _record(
          sessionId: sessionId,
          toolName: name,
          outcome: ToolAuditOutcome.failed,
          code: 'result_limit_exceeded',
          risks: descriptor.risks,
          rootRevision:
              rootAuthorization?.rootRevision ?? rootSnapshot.revision,
          workspaceRevision: result.workspaceRevision,
          provenance: result.provenance,
        );
        return _toolError(
          'result_limit_exceeded',
          'tool result exceeds the configured byte limit',
          failedReceipt,
        );
      }
      return <String, Object?>{
        'content': <Map<String, Object?>>[
          <String, Object?>{'type': 'text', 'text': jsonEncode(sanitized)},
        ],
        'structuredContent': sanitized,
        'isError': false,
      };
    } on IdeToolFailure catch (error) {
      final receipt = _record(
        sessionId: sessionId,
        toolName: name,
        outcome: ToolAuditOutcome.failed,
        code: error.code,
        risks: descriptor.risks,
        rootRevision: rootAuthorization?.rootRevision ?? rootSnapshot.revision,
      );
      return _toolError(error.code, error.message, receipt);
    } on StaleIdeFactRevision {
      final receipt = _record(
        sessionId: sessionId,
        toolName: name,
        outcome: ToolAuditOutcome.failed,
        code: 'stale_workspace_revision',
        risks: descriptor.risks,
        rootRevision: rootAuthorization?.rootRevision ?? rootSnapshot.revision,
      );
      return _toolError(
        'stale_workspace_revision',
        'requested IDE facts are stale',
        receipt,
      );
    } on FileSystemException {
      final receipt = _record(
        sessionId: sessionId,
        toolName: name,
        outcome: ToolAuditOutcome.failed,
        code: 'resource_unavailable',
        risks: descriptor.risks,
        rootRevision: rootAuthorization?.rootRevision ?? rootSnapshot.revision,
      );
      return _toolError(
        'resource_unavailable',
        'workspace resource is unavailable',
        receipt,
      );
    } on Object {
      final receipt = _record(
        sessionId: sessionId,
        toolName: name,
        outcome: ToolAuditOutcome.failed,
        code: 'tool_failed',
        risks: descriptor.risks,
        rootRevision: rootAuthorization?.rootRevision ?? rootSnapshot.revision,
      );
      return _toolError('tool_failed', 'tool execution failed', receipt);
    }
  }

  Map<String, Object?> _listResources(String sessionId) {
    final roots = _roots.snapshot(sessionId);
    final contextVisible = _tools
        .lookup(sessionId, 'ide.context.read', hasRoots: roots.roots.isNotEmpty)
        .visible;
    return <String, Object?>{
      'resources': <Map<String, Object?>>[
        if (contextVisible)
          <String, Object?>{
            'uri': 'ide://context/facts',
            'name': 'Revision-bound IDE facts',
            'description': 'Bounded facts shared with IDE surfaces.',
            'mimeType': 'application/json',
          },
        for (final root in roots.roots)
          <String, Object?>{
            'uri': root.resourceUri,
            'name': root.displayName,
            'description': 'Consented IDE workspace root.',
            'mimeType': 'application/json',
            '_meta': <String, Object?>{'vityo/rootRevision': roots.revision},
          },
      ],
      '_meta': <String, Object?>{'vityo/rootRevision': roots.revision},
    };
  }

  Future<Map<String, Object?>> _readResource(
    String sessionId,
    Map<String, Object?> params,
  ) async {
    final uri = params['uri'];
    if (uri is! String || uri.isEmpty) {
      throw const _McpFailure(
        rpcCode: -32602,
        code: 'schema_validation_failed',
        message: 'resource URI is required',
      );
    }
    if (uri == 'ide://context/facts') {
      final metadata = params['_meta'];
      if (metadata is! Map<String, Object?>) {
        throw const _McpFailure(
          rpcCode: -32602,
          code: 'schema_validation_failed',
          message: 'context resource budget metadata is required',
        );
      }
      final call = await _callTool(sessionId, <String, Object?>{
        'name': 'ide.context.read',
        'arguments': metadata,
      });
      if (call['isError'] == true) {
        throw _McpFailure(
          rpcCode: -32000,
          code: _toolErrorCode(call) ?? 'resource_unavailable',
          message: 'context resource could not be read',
        );
      }
      return <String, Object?>{
        'contents': <Map<String, Object?>>[
          <String, Object?>{
            'uri': uri,
            'mimeType': 'application/json',
            'text': jsonEncode(call['structuredContent']),
          },
        ],
      };
    }
    final roots = _roots.snapshot(sessionId);
    final root = roots.roots
        .where((candidate) => candidate.resourceUri == uri)
        .firstOrNull;
    if (root == null) {
      throw const _McpFailure(
        rpcCode: -32602,
        code: 'root_revoked',
        message: 'workspace root resource is not available',
      );
    }
    return <String, Object?>{
      'contents': <Map<String, Object?>>[
        <String, Object?>{
          'uri': uri,
          'mimeType': 'application/json',
          'text': jsonEncode(<String, Object?>{
            'rootId': root.id,
            'displayName': root.displayName,
            'rootRevision': roots.revision,
            'provenance': 'user-consented-workspace-root',
          }),
        },
      ],
    };
  }

  Map<String, Object?> _listPrompts(String sessionId) {
    final roots = _roots.snapshot(sessionId);
    return <String, Object?>{
      'prompts': <Map<String, Object?>>[
        if (roots.roots.isNotEmpty)
          const <String, Object?>{
            'name': 'ide.review_workspace',
            'title': 'Review approved workspace',
            'description':
                'Review revision-bound facts for consented workspace roots.',
            'arguments': <Map<String, Object?>>[
              <String, Object?>{
                'name': 'focus',
                'description': 'Optional review focus.',
                'required': false,
              },
            ],
          },
      ],
      '_meta': <String, Object?>{'vityo/rootRevision': roots.revision},
    };
  }

  Map<String, Object?> _getPrompt(
    String sessionId,
    Map<String, Object?> params,
  ) {
    if (params['name'] != 'ide.review_workspace') {
      throw const _McpFailure(
        rpcCode: -32602,
        code: 'prompt_not_found',
        message: 'prompt is not available',
      );
    }
    final roots = _roots.snapshot(sessionId);
    if (roots.roots.isEmpty) {
      throw const _McpFailure(
        rpcCode: -32602,
        code: 'root_revoked',
        message: 'prompt requires an approved workspace root',
      );
    }
    final arguments = params['arguments'];
    final focus =
        arguments is Map<String, Object?> && arguments['focus'] is String
        ? arguments['focus'] as String
        : 'current changes';
    return <String, Object?>{
      'description': 'Review only user-consented workspace evidence.',
      'messages': <Map<String, Object?>>[
        <String, Object?>{
          'role': 'user',
          'content': <String, Object?>{
            'type': 'text',
            'text':
                'Review $focus across ${roots.roots.length} approved root(s) '
                'at root revision ${roots.revision}.',
          },
        },
      ],
    };
  }

  String? _validateArguments(
    IdeToolDescriptor descriptor,
    Map<String, Object?> arguments,
  ) {
    final required = descriptor.inputSchema['required'];
    if (required is List<Object?>) {
      for (final key in required) {
        if (key is! String || !arguments.containsKey(key)) {
          return 'schema_validation_failed';
        }
      }
    }
    if (descriptor.inputSchema['additionalProperties'] == false) {
      final properties = descriptor.inputSchema['properties'];
      final allowed = <String>{
        if (properties is Map<String, Object?>) ...properties.keys,
        if (required is List<Object?>) ...required.whereType<String>(),
        'capabilityIds',
        'cursor',
      };
      if (arguments.keys.any((key) => !allowed.contains(key))) {
        return 'schema_validation_failed';
      }
    }
    return null;
  }

  ToolAuditReceipt _record({
    required String sessionId,
    required String toolName,
    required ToolAuditOutcome outcome,
    required String code,
    required Set<IdeToolRisk> risks,
    required int rootRevision,
    int workspaceRevision = 0,
    String provenance = 'vityo-mcp-policy',
  }) => _security.auditLog.add(
    sessionId: sessionId,
    toolName: toolName,
    outcome: outcome,
    code: code,
    risks: risks,
    rootRevision: rootRevision,
    workspaceRevision: workspaceRevision,
    provenance: provenance,
  );

  Map<String, Object?> _toolError(
    String code,
    String message,
    ToolAuditReceipt receipt,
  ) {
    final sanitizedMessage = _security.sanitizer.sanitize(message) as String;
    return <String, Object?>{
      'content': <Map<String, Object?>>[
        <String, Object?>{'type': 'text', 'text': sanitizedMessage},
      ],
      'structuredContent': <String, Object?>{
        'code': code,
        'auditReceipt': receipt.toJson(),
      },
      'isError': true,
    };
  }

  void _onRootChange(WorkspaceRootChange change) {
    if (_sessions[change.sessionId]?.ready != true) {
      return;
    }
    _notify(change.sessionId, 'notifications/tools/list_changed');
    _notify(change.sessionId, 'notifications/resources/list_changed');
    _notify(change.sessionId, 'notifications/prompts/list_changed');
  }

  void _onToolChange(ToolCatalogChange change) {
    if (_sessions[change.sessionId]?.ready == true) {
      _notify(change.sessionId, 'notifications/tools/list_changed');
      _notify(change.sessionId, 'notifications/resources/list_changed');
    }
  }

  void _notify(String sessionId, String method) {
    _notificationController(sessionId).add(JsonRpcNotification(method: method));
  }

  StreamController<JsonRpcNotification> _notificationController(
    String sessionId,
  ) => _notifications.putIfAbsent(
    sessionId,
    () => StreamController<JsonRpcNotification>.broadcast(sync: true),
  );
}

final class _McpSessionState {
  _McpSessionState({
    required this.protocolVersion,
    required this.clientCapabilities,
  });

  final String protocolVersion;
  final Map<String, Object?> clientCapabilities;
  bool ready = false;
}

final class _McpFailure implements Exception {
  const _McpFailure({
    required this.rpcCode,
    required this.code,
    required this.message,
  });

  final int rpcCode;
  final String code;
  final String message;
}

String? _toolErrorCode(Map<String, Object?> result) {
  final structured = result['structuredContent'];
  return structured is Map<String, Object?>
      ? structured['code'] as String?
      : null;
}
