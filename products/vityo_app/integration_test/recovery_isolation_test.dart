import 'dart:io';

import 'package:vityo_app/src/ide/agent_client/agent_client.dart';

import '../test/support/vityod_test_harness.dart';

Future<void> main() async {
  if (!VityodTestHarness.isSupported) return;
  final fixture = File.fromUri(
    Platform.script.resolve(
      '../../../tests/acceptance/fixtures/vityo_app/agent_client/'
      'fake_agent.dart',
    ),
  );
  final harness = await VityodTestHarness.start(
    clientId: 'agent-isolation-integration',
  );
  final registry = AgentClientRegistry(
    descriptors: <String, AgentLaunchDescriptor>{
      'healthy': AgentLaunchDescriptor(
        id: 'healthy',
        executable: Platform.resolvedExecutable,
        arguments: <String>['run', fixture.path, 'normal'],
        workingDirectory: Directory.current.path,
      ),
      'crash': AgentLaunchDescriptor(
        id: 'crash',
        executable: Platform.resolvedExecutable,
        arguments: <String>['run', fixture.path, 'crash'],
        workingDirectory: Directory.current.path,
      ),
    },
    client: harness.client,
    policy: const AgentClientPolicy(
      requestTimeout: Duration(seconds: 3),
      shutdownTimeout: Duration(seconds: 2),
    ),
  );
  try {
    await registry.connect('healthy');
    try {
      await registry.connect('crash');
      throw StateError('crashing Agent unexpectedly connected');
    } on AgentClientFailure catch (failure) {
      if (failure.code != 'process_failed') {
        rethrow;
      }
    }
    final session = await registry.newSession(
      agentId: 'healthy',
      cwd: Directory.current.uri,
    );
    if (session.agentId != 'healthy' || registry.activeConnectionCount != 1) {
      throw StateError('sibling Agent failure was not isolated');
    }
  } finally {
    await registry.close();
    await harness.close();
  }
}
