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
}

IdeMcpServer _server(IdeToolAdapter adapter, {ToolGrantRegistry? grants}) {
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
