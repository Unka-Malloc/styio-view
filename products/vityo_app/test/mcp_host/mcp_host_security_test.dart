import 'dart:async';
import 'dart:convert';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';
import 'package:vityo_app/src/ide/agent_client/mcp/ide_mcp_server.dart';
import 'package:vityo_app/src/ide/agent_client/mcp/workspace_root_registry.dart';
import 'package:vityo_app/src/ide/agent_client/tools/ide_tool_catalog.dart';
import 'package:vityo_app/src/ide/agent_client/tools/tool_security_policy.dart';
import 'package:test/test.dart';

void main() {
  test('authoritative risk consumes an allow-once grant once', () async {
    final adapter = _Adapter(
      name: 'ide.fixture.mutate',
      risks: const <IdeToolRisk>{IdeToolRisk.mutating},
    );
    final grants = ToolGrantRegistry();
    final server = _server(adapter, grants: grants);
    await _initialize(server);

    expect(
      _code(await _call(server, adapter.descriptor.name)),
      'permission_required',
    );
    expect(adapter.callCount, 0);
    grants.grant(
      ToolPermissionGrant(
        id: 'once',
        sessionId: 'session',
        toolName: adapter.descriptor.name,
        risks: const <IdeToolRisk>{IdeToolRisk.mutating},
        scope: ToolGrantScope.once,
      ),
    );
    expect((await _call(server, adapter.descriptor.name))['isError'], isFalse);
    expect(
      _code(await _call(server, adapter.descriptor.name)),
      'permission_required',
    );
    expect(adapter.callCount, 1);
    await server.close();
  });

  test('credentials and unexpected failures fail closed', () async {
    final adapter = _Adapter(
      name: 'ide.fixture.failure',
      risks: const <IdeToolRisk>{IdeToolRisk.readOnly},
      failure: StateError('private failure detail'),
    );
    final server = _server(adapter);
    await _initialize(server);

    expect(
      _code(
        await _call(server, adapter.descriptor.name, const <String, Object?>{
          'authorization': 'Bearer fixture-token',
        }),
      ),
      'credential_passthrough_denied',
    );
    expect(adapter.callCount, 0);
    final failed = await _call(server, adapter.descriptor.name);
    expect(_code(failed), 'tool_failed');
    expect(jsonEncode(failed), isNot(contains('private failure detail')));
    await server.close();
  });

  test('grant storage and credential sanitization remain bounded', () {
    final sensitiveValues = <String>{'private-value'};
    final sanitizer = McpPayloadSanitizer.withSensitiveValues(sensitiveValues);
    sensitiveValues.clear();

    expect(
      sanitizer.containsCredentialInput(const <String, Object?>{
        'clientSecret': 'credential',
      }),
      isTrue,
    );
    expect(
      sanitizer.sanitize(const <String, Object?>{
        'clientSecret': 'credential',
        'url': 'https://example.invalid/?access_token=value',
        'message': 'private-value',
      }),
      <String, Object?>{
        'clientSecret': '[REDACTED]',
        'url': 'https://example.invalid/?access_token=[REDACTED]',
        'message': '[REDACTED]',
      },
    );

    final grants = ToolGrantRegistry(maxGrants: 1);
    grants.grant(_grant('first', 'session-a'));
    expect(() => grants.grant(_grant('second', 'session-b')), throwsStateError);
    grants.revokeSession('session-a');
    expect(() => grants.grant(_grant('second', 'session-b')), returnsNormally);
  });

  test('credential sanitization is cycle and depth bounded', () {
    const sanitizer = McpPayloadSanitizer();
    final cyclic = <String, Object?>{};
    cyclic['self'] = cyclic;

    expect(sanitizer.containsCredentialInput(cyclic), isTrue);
    expect(sanitizer.sanitize(cyclic), <String, Object?>{'self': '[REDACTED]'});

    Object? nested = 'safe';
    for (var depth = 0; depth < 70; depth += 1) {
      nested = <Object?>[nested];
    }
    expect(sanitizer.containsCredentialInput(nested), isTrue);
    expect(jsonEncode(sanitizer.sanitize(nested)), contains('[REDACTED]'));
  });

  test(
    'MCP sessions are bounded and duplicate initialize is rejected',
    () async {
      final adapter = _Adapter(
        name: 'ide.fixture.session-limit',
        risks: const <IdeToolRisk>{IdeToolRisk.readOnly},
      );
      final server = _server(adapter, maxSessions: 1);
      await _initialize(server);

      final duplicate = await server.handle(
        sessionId: 'session',
        message: JsonRpcRequest(
          id: const JsonRpcId.integer(3),
          method: 'initialize',
          params: const <String, Object?>{
            'protocolVersion': mcpProtocolVersion,
            'capabilities': <String, Object?>{},
          },
        ),
      );
      final limited = await server.handle(
        sessionId: 'session-2',
        message: JsonRpcRequest(
          id: const JsonRpcId.integer(4),
          method: 'initialize',
          params: const <String, Object?>{
            'protocolVersion': mcpProtocolVersion,
            'capabilities': <String, Object?>{},
          },
        ),
      );

      expect(_rpcErrorCode(duplicate), 'already_initialized');
      expect(_rpcErrorCode(limited), 'session_limit_exceeded');
      await server.close();
    },
  );

  test('MCP negotiates versions and permits lifecycle pings', () async {
    final server = _server(
      _Adapter(
        name: 'ide.fixture.lifecycle',
        risks: const <IdeToolRisk>{IdeToolRisk.readOnly},
      ),
    );
    final initialized = await server.handle(
      sessionId: 'session',
      message: JsonRpcRequest(
        id: const JsonRpcId.integer(1),
        method: 'initialize',
        params: const <String, Object?>{
          'protocolVersion': '2099-01-01',
          'capabilities': <String, Object?>{},
        },
      ),
    );
    expect(
      (initialized as JsonRpcSuccessResponse).result,
      containsPair('protocolVersion', mcpProtocolVersion),
    );
    final ping = await server.handle(
      sessionId: 'session',
      message: JsonRpcRequest(id: const JsonRpcId.integer(2), method: 'ping'),
    );
    expect((ping as JsonRpcSuccessResponse).result, isEmpty);
    final tooEarly = await server.handle(
      sessionId: 'session',
      message: JsonRpcRequest(
        id: const JsonRpcId.integer(3),
        method: 'tools/list',
      ),
    );
    expect(_rpcErrorCode(tooEarly), 'not_initialized');
    await server.close();
  });

  test(
    'workspace root slots are reserved before canonical resolution',
    () async {
      final resolver = _BlockingCanonicalPathResolver();
      final roots = WorkspaceRootRegistry(resolver: resolver, maxSessions: 1);
      final first = roots.replaceRoots(
        sessionId: 'session-a',
        proposals: const <WorkspaceRootProposal>[
          WorkspaceRootProposal(path: '/workspace', displayName: 'workspace'),
        ],
        consentReceiptId: 'consent-a',
      );
      await resolver.started.future;

      await expectLater(
        roots.replaceRoots(
          sessionId: 'session-b',
          proposals: const <WorkspaceRootProposal>[],
          consentReceiptId: 'consent-b',
        ),
        throwsStateError,
      );
      resolver.release.complete();
      await first;
      await roots.close();
    },
  );

  test('workspace path resolution is deadline bounded', () async {
    final roots = WorkspaceRootRegistry(
      resolver: _NeverCanonicalPathResolver(),
      resolutionTimeout: const Duration(milliseconds: 20),
    );
    await expectLater(
      roots.replaceRoots(
        sessionId: 'session',
        proposals: const <WorkspaceRootProposal>[
          WorkspaceRootProposal(path: '/workspace', displayName: 'workspace'),
        ],
        consentReceiptId: 'consent',
      ),
      throwsA(isA<TimeoutException>()),
    );
    await roots.close();
  });

  test(
    'tool execution concurrency is bounded before adapter effects',
    () async {
      final adapter = _BlockingAdapter();
      final server = _server(adapter, maxConcurrentToolCallsPerSession: 1);
      await _initialize(server);

      final first = _call(server, adapter.descriptor.name);
      await adapter.started.future;
      final denied = await _call(server, adapter.descriptor.name);
      expect(_code(denied), 'tool_concurrency_limit');
      expect(adapter.callCount, 1);

      adapter.release.complete();
      expect((await first)['isError'], isFalse);
      await server.close();
    },
  );
}

ToolPermissionGrant _grant(String id, String sessionId) => ToolPermissionGrant(
  id: id,
  sessionId: sessionId,
  toolName: 'ide.fixture.mutate',
  risks: const <IdeToolRisk>{IdeToolRisk.mutating},
  scope: ToolGrantScope.session,
);

IdeMcpServer _server(
  IdeToolAdapter adapter, {
  ToolGrantRegistry? grants,
  int maxSessions = 64,
  int maxConcurrentToolCallsPerSession = 16,
}) {
  final catalog = IdeToolCatalog(adapters: <IdeToolAdapter>[adapter]);
  catalog.replaceCapabilities('session', <String>{
    adapter.descriptor.requiredCapabilityId,
  });
  return IdeMcpServer(
    roots: WorkspaceRootRegistry(),
    tools: catalog,
    security: ToolSecurityPolicy(
      grants: grants ?? ToolGrantRegistry(),
      auditLog: ToolAuditLog(maxEntries: 8),
      sanitizer: const McpPayloadSanitizer(),
      maxResultBytes: 2048,
    ),
    maxSessions: maxSessions,
    maxConcurrentToolCallsPerSession: maxConcurrentToolCallsPerSession,
  );
}

Future<void> _initialize(IdeMcpServer server) async {
  await server.handle(
    sessionId: 'session',
    message: JsonRpcRequest(
      id: const JsonRpcId.integer(1),
      method: 'initialize',
      params: const <String, Object?>{
        'protocolVersion': mcpProtocolVersion,
        'capabilities': <String, Object?>{},
      },
    ),
  );
  await server.handle(
    sessionId: 'session',
    message: JsonRpcNotification(method: 'notifications/initialized'),
  );
}

Future<Map<String, Object?>> _call(
  IdeMcpServer server, [
  String name = 'ide.fixture.failure',
  Map<String, Object?> arguments = const <String, Object?>{},
]) async {
  final response = await server.handle(
    sessionId: 'session',
    message: JsonRpcRequest(
      id: const JsonRpcId.integer(2),
      method: 'tools/call',
      params: <String, Object?>{'name': name, 'arguments': arguments},
    ),
  );
  final success = response as JsonRpcSuccessResponse;
  return success.result as Map<String, Object?>;
}

String? _code(Map<String, Object?> result) =>
    (result['structuredContent'] as Map<String, Object?>)['code'] as String?;

String? _rpcErrorCode(JsonRpcMessage? response) {
  if (response is! JsonRpcErrorResponse) {
    return null;
  }
  final data = response.error.data;
  return data is Map<String, Object?> ? data['code'] as String? : null;
}

final class _Adapter implements IdeToolAdapter {
  _Adapter({
    required String name,
    required Set<IdeToolRisk> risks,
    this.failure,
  }) : descriptor = IdeToolDescriptor(
         name: name,
         title: name,
         description: 'Security fixture tool.',
         requiredCapabilityId: name,
         inputSchema: const <String, Object?>{
           'type': 'object',
           'additionalProperties': true,
         },
         outputSchema: const <String, Object?>{'type': 'object'},
         risks: risks,
         annotations: const <String, Object?>{'readOnlyHint': true},
       );

  @override
  final IdeToolDescriptor descriptor;
  final Object? failure;
  int callCount = 0;

  @override
  Future<IdeToolResult> invoke(IdeToolInvocation invocation) async {
    callCount += 1;
    if (failure case final failure?) {
      throw failure;
    }
    return IdeToolResult(
      structuredContent: const <String, Object?>{'changed': true},
      workspaceRevision: 1,
      provenance: 'fixture',
      sensitivity: ContextSensitivity.internal,
    );
  }
}

final class _BlockingCanonicalPathResolver implements CanonicalPathResolver {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();

  @override
  Future<CanonicalPath> resolve(String path) async {
    if (!started.isCompleted) {
      started.complete();
    }
    await release.future;
    return CanonicalPath(path: path);
  }
}

final class _NeverCanonicalPathResolver implements CanonicalPathResolver {
  @override
  Future<CanonicalPath> resolve(String path) =>
      Completer<CanonicalPath>().future;
}

final class _BlockingAdapter implements IdeToolAdapter {
  final Completer<void> started = Completer<void>();
  final Completer<void> release = Completer<void>();
  int callCount = 0;

  @override
  final IdeToolDescriptor descriptor = IdeToolDescriptor(
    name: 'ide.fixture.blocking',
    title: 'blocking fixture',
    description: 'Blocks until the acceptance fixture releases it.',
    requiredCapabilityId: 'ide.fixture.blocking',
    inputSchema: const <String, Object?>{
      'type': 'object',
      'additionalProperties': true,
    },
    outputSchema: const <String, Object?>{'type': 'object'},
    risks: const <IdeToolRisk>{IdeToolRisk.readOnly},
  );

  @override
  Future<IdeToolResult> invoke(IdeToolInvocation invocation) async {
    callCount += 1;
    if (!started.isCompleted) {
      started.complete();
    }
    await release.future;
    return IdeToolResult(
      structuredContent: const <String, Object?>{'completed': true},
      workspaceRevision: 1,
      provenance: 'fixture',
      sensitivity: ContextSensitivity.internal,
    );
  }
}
