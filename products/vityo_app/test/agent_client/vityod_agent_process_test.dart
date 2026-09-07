import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/agent_client/agent_client.dart';

import '../support/vityod_test_harness.dart';

void main() {
  test(
    'vityod supervises the standalone Coding Agent ACP handshake',
    () async {
      if (Platform.isWindows) return;
      final daemonExecutable = _findDaemonExecutable();
      final codingAgentDirectory = _findCodingAgentDirectory();
      final dartExecutable = _findDartExecutable();
      expect(daemonExecutable.existsSync(), isTrue);
      expect(codingAgentDirectory.existsSync(), isTrue);
      expect(dartExecutable.existsSync(), isTrue);

      final harness = await VityodTestHarness.start(
        clientId: 'agent-supervision-test',
      );
      addTearDown(harness.close);
      final registry = AgentClientRegistry(
        descriptors: <String, AgentLaunchDescriptor>{
          'coding-agent': AgentLaunchDescriptor(
            id: 'coding-agent',
            executable: dartExecutable.path,
            arguments: const <String>[
              'run',
              'bin/vityo_coding_agent.dart',
              '--stdio-agent',
            ],
            workingDirectory: codingAgentDirectory.path,
          ),
        },
        client: harness.client,
      );
      addTearDown(() async {
        await registry.close();
      });

      final connection = await registry
          .connect('coding-agent')
          .timeout(const Duration(seconds: 10));

      expect(connection.agentId, 'coding-agent');
      expect(connection.protocolVersion, 1);
      expect(registry.activeConnectionCount, 1);
    },
    skip: !(Platform.isMacOS || Platform.isLinux)
        ? 'Unix local-service transport only.'
        : false,
  );
}

File _findDaemonExecutable() {
  final app = _findAppDirectory();
  return File('${app.path}/native/vityod/target/debug/vityod');
}

Directory _findCodingAgentDirectory() {
  final app = _findAppDirectory();
  return Directory('${app.parent.path}/vityo_coding_agent');
}

Directory _findAppDirectory() {
  var directory = Directory.current.absolute;
  for (var depth = 0; depth < 12; depth += 1) {
    if (File('${directory.path}/pubspec.yaml').existsSync() &&
        directory.path.endsWith('vityo_app')) {
      return directory;
    }
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return Directory.current.absolute;
}

File _findDartExecutable() {
  final engineDirectory = File(Platform.resolvedExecutable).parent;
  final cacheDirectory = engineDirectory.parent.parent.parent;
  return File(
    '${cacheDirectory.path}/dart-sdk/bin/${Platform.isWindows ? 'dart.exe' : 'dart'}',
  );
}
