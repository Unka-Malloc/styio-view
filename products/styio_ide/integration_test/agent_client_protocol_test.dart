import 'dart:io';

import 'package:styio_ide/src/ide/agent_client/agent_client.dart';

Future<void> main() async {
  final fixture = File.fromUri(
    Platform.script.resolve(
      '../../../tests/acceptance/fixtures/styio_ide/agent_client/'
      'fake_agent.dart',
    ),
  );
  final registry = AgentClientRegistry(
    descriptors: <String, AgentLaunchDescriptor>{
      'fixture': AgentLaunchDescriptor(
        id: 'fixture',
        executable: Platform.resolvedExecutable,
        arguments: <String>['run', fixture.path, 'normal'],
        workingDirectory: Directory.current.path,
      ),
    },
    policy: const AgentClientPolicy(
      requestTimeout: Duration(seconds: 3),
      allowedExtensions: <String>{'styio/test/write', 'styio/test/status'},
    ),
  );
  try {
    final connection = await registry.connect('fixture');
    if (connection.protocolVersion != 1) {
      throw StateError('ACP v1 negotiation failed');
    }
    if (registry.activeConnectionCount != 1) {
      throw StateError('connection was not retained after initialize');
    }
    final session = await registry.newSession(
      agentId: 'fixture',
      cwd: Directory.current.uri,
    );
    final prompt = session.prompt('integration');
    final permission = await registry.permissionRequests.first.timeout(
      const Duration(seconds: 3),
    );
    await registry.resolvePermission(
      permission.id,
      AgentPermissionDecision.allowOnce,
    );
    if ((await prompt).stopReason != 'end_turn') {
      throw StateError('stdio prompt did not complete');
    }
    if (registry.activeConnectionCount != 1) {
      throw StateError('connection was not retained after prompt');
    }
  } finally {
    final activeBeforeClose = registry.activeConnectionCount;
    final receipts = await registry.close();
    if (activeBeforeClose == 1 &&
        (receipts.length != 1 || !receipts.single.terminated)) {
      throw StateError(
        'supervised process was not reaped '
        '(receipts=${receipts.length}, '
        'terminated=${receipts.firstOrNull?.terminated})',
      );
    }
  }
}
