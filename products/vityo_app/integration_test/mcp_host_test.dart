import 'dart:io';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';
import 'package:vityo_app/src/ide/agent_client/mcp/ide_mcp_server.dart';
import 'package:vityo_app/src/ide/agent_client/mcp/workspace_root_registry.dart';
import 'package:vityo_app/src/ide/agent_client/tools/context_export_service.dart';
import 'package:vityo_app/src/ide/agent_client/tools/ide_tool_catalog.dart';
import 'package:vityo_app/src/ide/agent_client/tools/tool_security_policy.dart';

Future<void> main() async {
  final temporary = await Directory.systemTemp.createTemp('vityo-mcp-smoke-');
  final file = File('${temporary.path}${Platform.pathSeparator}fixture.txt');
  await file.writeAsString('bounded workspace evidence');
  final roots = WorkspaceRootRegistry();
  await roots.replaceRoots(
    sessionId: 'integration',
    proposals: <WorkspaceRootProposal>[
      WorkspaceRootProposal(path: temporary.path, displayName: 'fixture'),
    ],
    consentReceiptId: 'integration-consent',
  );
  final catalog = IdeToolCatalog(
    adapters: <IdeToolAdapter>[
      WorkspaceReadTextToolAdapter(
        roots: roots,
        maxCodeUnits: 64,
        sanitizer: const McpPayloadSanitizer(),
      ),
    ],
  );
  catalog.replaceCapabilities('integration', const <String>{
    'ide.workspace.read_text',
  });
  final server = IdeMcpServer(
    roots: roots,
    tools: catalog,
    security: ToolSecurityPolicy(
      grants: ToolGrantRegistry(),
      auditLog: ToolAuditLog(maxEntries: 8),
      sanitizer: const McpPayloadSanitizer(),
      maxResultBytes: 2048,
    ),
  );
  try {
    await _request(server, 'initialize', <String, Object?>{
      'protocolVersion': mcpProtocolVersion,
      'capabilities': const <String, Object?>{},
    });
    await server.handle(
      sessionId: 'integration',
      message: JsonRpcNotification(method: 'notifications/initialized'),
    );
    final listed = await _request(server, 'tools/list');
    if (!listed.toString().contains('ide.workspace.read_text')) {
      throw StateError('root-scoped tool was not discovered');
    }
    final result = await _request(server, 'tools/call', <String, Object?>{
      'name': 'ide.workspace.read_text',
      'arguments': <String, Object?>{'path': file.path},
    });
    if (result['isError'] == true ||
        !result.toString().contains('bounded workspace evidence')) {
      throw StateError('approved workspace evidence was not returned');
    }
  } finally {
    await server.close();
    await roots.close();
    await catalog.close();
    await temporary.delete(recursive: true);
  }
}

Future<Map<String, Object?>> _request(
  IdeMcpServer server,
  String method, [
  Map<String, Object?> params = const <String, Object?>{},
]) async {
  final response = await server.handle(
    sessionId: 'integration',
    message: JsonRpcRequest(
      id: JsonRpcId.string(method),
      method: method,
      params: params,
    ),
  );
  if (response is! JsonRpcSuccessResponse) {
    throw StateError('$method failed');
  }
  return response.result as Map<String, Object?>;
}
