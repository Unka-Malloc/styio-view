import 'dart:io';

import 'package:vityo_app/src/ide/agent_client/agent_client.dart';

Future<void> main() async {
  final storage = MemoryAgentSessionRecoveryStorage();
  final recovery = AgentSessionRecoveryStore(
    storage: storage,
    maxSessions: 4,
    maxTimelineEntriesPerSession: 8,
    maxEncodedBytes: 16 * 1024,
  );
  await recovery.save(
    AgentRecoveryCheckpoint(
      sessionId: 'recoverable',
      agentId: 'healthy',
      processGeneration: 1,
      protocolVersion: 1,
      workspaceRevision: 7,
      status: 'active',
      droppedUpdateCount: 0,
      timeline: const <AgentSessionUpdate>[],
    ),
  );
  final restored = await AgentSessionRecoveryStore(
    storage: storage,
    maxSessions: 4,
    maxTimelineEntriesPerSession: 8,
    maxEncodedBytes: 16 * 1024,
  ).loadAll();
  if (restored.single.sessionId != 'recoverable' ||
      restored.single.workspaceRevision != 7) {
    throw StateError('session checkpoint did not survive reconstruction');
  }

  final fixture = File.fromUri(
    Platform.script.resolve(
      '../../../tests/acceptance/fixtures/vityo_app/agent_client/'
      'fake_agent.dart',
    ),
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
      throw StateError('sibling Agent connection was not isolated');
    }
  } finally {
    await registry.close();
  }
}
