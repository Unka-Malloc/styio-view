import 'dart:async';
import 'dart:io';

import 'package:test/test.dart';
import 'package:vityo_app/src/ide/agent_client/mcp/vityod_mcp_gateway.dart';
import 'package:vityo_app/src/ide/local_service/vityod_client.dart';

void main() {
  test(
    'vityod MCP enforces roots, revisions, capabilities, preview, and revocation',
    () async {
      if (Platform.isWindows) return;
      final executable = _findVityodExecutable();
      expect(
        executable.existsSync(),
        isTrue,
        reason: 'Run the focused Cargo workspace tests before this suite.',
      );
      final temporary = await Directory.systemTemp.createTemp('vd-mcp-');
      final endpoint = '${temporary.path}/service.sock';
      var daemon = await Process.start(executable.path, <String>[
        '--serve',
        '--endpoint',
        endpoint,
      ]);
      addTearDown(() async {
        daemon.kill();
        await daemon.exitCode.timeout(const Duration(seconds: 5));
        await temporary.delete(recursive: true);
      });
      await _waitForEndpoint(endpoint);

      var client = VityodClient(
        transport: SocketVityodTransport(endpointPath: endpoint),
        clientInstanceId: 'mcp-security-test',
      );
      await client.connect();
      addTearDown(() => client.dispose());
      final seed = await client.request(
        method: 'workspace.transaction.commit',
        idempotencyKey: 'seed-workspace',
        workspaceId: 'workspace',
        params: const <String, Object?>{
          'expectedWorkspaceRevision': 0,
          'changes': <Object?>[
            <String, Object?>{
              'relativePath': 'lib/main.styio',
              'expectedDocumentRevision': 0,
              'contents': 'before',
            },
          ],
        },
      );
      expect(seed.method, 'workspace.transaction.commit.result');
      expect(seed.params['workspaceRevision'], 1);

      var gateway = VityodMcpGateway(client: client);
      await gateway.startSession(
        sessionId: 'session',
        workspaceId: 'workspace',
        workspaceRevision: 1,
        capabilities: const <String>{'workspace.read', 'workspace.proposeEdit'},
      );

      final read = await gateway.invoke(
        sessionId: 'session',
        workspaceId: 'workspace',
        workspaceRevision: 1,
        tool: 'workspace.read',
        arguments: const <String, Object?>{'relativePath': 'lib/main.styio'},
      );
      expect(read['contents'], 'before');
      expect(read['documentRevision'], 1);

      await expectLater(
        gateway.invoke(
          sessionId: 'session',
          workspaceId: 'workspace',
          workspaceRevision: 1,
          tool: 'workspace.read',
          arguments: const <String, Object?>{'relativePath': '../secret'},
        ),
        _failsWith('workspace_root_escape'),
      );
      await expectLater(
        gateway.invoke(
          sessionId: 'session',
          workspaceId: 'workspace',
          workspaceRevision: 1,
          tool: 'task.start',
        ),
        _failsWith('capability_denied'),
      );
      await expectLater(
        gateway.invoke(
          sessionId: 'session',
          workspaceId: 'workspace',
          workspaceRevision: 1,
          tool: 'workspace.read',
          arguments: const <String, Object?>{
            'relativePath': 'lib/main.styio',
            'authorization': 'Bearer fixture-token',
          },
        ),
        _failsWith('credential_passthrough_denied'),
      );

      final proposal = await gateway.invoke(
        sessionId: 'session',
        workspaceId: 'workspace',
        workspaceRevision: 1,
        tool: 'workspace.proposeEdit',
        arguments: const <String, Object?>{
          'relativePath': 'lib/main.styio',
          'contents': 'after',
        },
      );
      expect(
        (proposal['proposal'] as Map<String, Object?>)['requiresPreview'],
        isTrue,
      );
      expect(
        (proposal['proposal']
            as Map<String, Object?>)['requiresTransactionCommit'],
        isTrue,
      );
      final unchanged = await gateway.invoke(
        sessionId: 'session',
        workspaceId: 'workspace',
        workspaceRevision: 1,
        tool: 'workspace.read',
        arguments: const <String, Object?>{'relativePath': 'lib/main.styio'},
      );
      expect(unchanged['contents'], 'before');

      await gateway.requestPermission(
        sessionId: 'session',
        permissionId: 'permission-1',
      );
      await gateway.decidePermission(
        sessionId: 'session',
        permissionId: 'permission-1',
        allowOnce: false,
      );
      await client.dispose();
      daemon.kill();
      await daemon.exitCode.timeout(const Duration(seconds: 5));
      daemon = await Process.start(executable.path, <String>[
        '--serve',
        '--endpoint',
        endpoint,
      ]);
      await _waitForEndpoint(endpoint);
      client = VityodClient(
        transport: SocketVityodTransport(endpointPath: endpoint),
        clientInstanceId: 'mcp-security-reconnected',
      );
      await client.connect();
      gateway = VityodMcpGateway(client: client);
      final resumed = await gateway.resumeSession('session');
      expect(resumed['revoked'], isFalse);
      expect(
        (resumed['events'] as List<Object?>).cast<Map<String, Object?>>().map(
          (event) => event['kind'],
        ),
        containsAll(<String>[
          'started',
          'permission.requested',
          'permission.denied',
        ]),
      );
      expect(
        (await gateway.invoke(
          sessionId: 'session',
          workspaceId: 'workspace',
          workspaceRevision: 1,
          tool: 'workspace.read',
          arguments: const <String, Object?>{'relativePath': 'lib/main.styio'},
        ))['contents'],
        'before',
      );

      final commit = await client.request(
        method: 'workspace.transaction.commit',
        idempotencyKey: 'commit-previewed-edit',
        workspaceId: 'workspace',
        params: const <String, Object?>{
          'expectedWorkspaceRevision': 1,
          'changes': <Object?>[
            <String, Object?>{
              'relativePath': 'lib/main.styio',
              'expectedDocumentRevision': 1,
              'contents': 'after',
            },
          ],
        },
      );
      expect(commit.params['workspaceRevision'], 2);

      await expectLater(
        gateway.invoke(
          sessionId: 'session',
          workspaceId: 'workspace',
          workspaceRevision: 2,
          tool: 'workspace.read',
          arguments: const <String, Object?>{'relativePath': 'lib/main.styio'},
        ),
        _failsWith('capability_denied'),
      );
      await gateway.revokeSession('session');
      await expectLater(
        gateway.invoke(
          sessionId: 'session',
          workspaceId: 'workspace',
          workspaceRevision: 1,
          tool: 'workspace.read',
          arguments: const <String, Object?>{'relativePath': 'lib/main.styio'},
        ),
        _failsWith('capability_denied'),
      );
    },
    skip: !(Platform.isMacOS || Platform.isLinux)
        ? 'Unix local-service transport only.'
        : false,
  );
}

Matcher _failsWith(String code) => throwsA(
  isA<VityodMcpFailure>().having((failure) => failure.code, 'code', code),
);

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
      final probe = await Socket.connect(
        InternetAddress(endpoint, type: InternetAddressType.unix),
        0,
      );
      probe.destroy();
      return;
    } on SocketException {
      // The previous daemon may have left an endpoint until its guard ran.
    }
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('vityod MCP endpoint was not created');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
