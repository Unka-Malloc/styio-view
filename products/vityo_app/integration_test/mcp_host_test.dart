import 'dart:async';
import 'dart:io';

import 'package:vityo_app/src/ide/agent_client/mcp/vityod_mcp_gateway.dart';
import 'package:vityo_app/src/ide/local_service/vityod_client.dart';

Future<void> main() async {
  if (!Platform.isLinux && !Platform.isMacOS) return;
  final executable = _findVityodExecutable();
  if (!executable.existsSync()) {
    throw StateError('Build the focused vityod target before this smoke test.');
  }
  final temporary = await Directory.systemTemp.createTemp('vd-mcp-smoke-');
  final endpoint = '${temporary.path}/service.sock';
  final daemon = await Process.start(executable.path, <String>[
    '--serve',
    '--endpoint',
    endpoint,
  ]);
  VityodClient? client;
  try {
    await _waitForEndpoint(endpoint);
    client = VityodClient(
      transport: SocketVityodTransport(endpointPath: endpoint),
      clientInstanceId: 'mcp-integration-smoke',
    );
    await client.connect();
    final seed = await client.request(
      method: 'workspace.transaction.commit',
      idempotencyKey: 'mcp-integration-seed',
      workspaceId: 'integration',
      params: const <String, Object?>{
        'expectedWorkspaceRevision': 0,
        'changes': <Object?>[
          <String, Object?>{
            'relativePath': 'fixture.styio',
            'expectedDocumentRevision': 0,
            'contents': 'bounded workspace evidence',
          },
        ],
      },
    );
    if (seed.method != 'workspace.transaction.commit.result') {
      throw StateError('workspace seed failed');
    }
    final gateway = VityodMcpGateway(client: client);
    await gateway.startSession(
      sessionId: 'integration-session',
      workspaceId: 'integration',
      workspaceRevision: 1,
      capabilities: const <String>{'workspace.read'},
    );
    final result = await gateway.invoke(
      sessionId: 'integration-session',
      workspaceId: 'integration',
      workspaceRevision: 1,
      tool: 'workspace.read',
      arguments: const <String, Object?>{'relativePath': 'fixture.styio'},
    );
    if (result['contents'] != 'bounded workspace evidence') {
      throw StateError('bounded workspace evidence was not returned');
    }
    await gateway.revokeSession('integration-session');
  } finally {
    await client?.dispose();
    daemon.kill();
    await daemon.exitCode.timeout(const Duration(seconds: 5));
    await temporary.delete(recursive: true);
  }
}

File _findVityodExecutable() {
  var directory = Directory.current.absolute;
  for (var depth = 0; depth < 12; depth += 1) {
    final candidate = File(
      '${directory.path}/native/vityod/target/debug/vityod',
    );
    if (candidate.existsSync()) return candidate;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return File('native/vityod/target/debug/vityod');
}

Future<void> _waitForEndpoint(String endpoint) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (true) {
    try {
      final socket = await Socket.connect(
        InternetAddress(endpoint, type: InternetAddressType.unix),
        0,
      );
      socket.destroy();
      return;
    } on SocketException {
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('vityod endpoint was not created');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}
