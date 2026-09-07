import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/local_service/vityod_client.dart';
import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

void main() {
  test(
    'real vityod resumes live state, full-resyncs a pruned cursor, and reports restart loss',
    () async {
      if (!Platform.isLinux && !Platform.isMacOS) return;
      final executable = _findVityodExecutable();
      expect(
        executable.existsSync(),
        isTrue,
        reason: 'Run the focused Cargo workspace tests before this matrix.',
      );
      final temporary = await Directory.systemTemp.createTemp('vd-reconnect-');
      final endpoint = '${temporary.path}/service.sock';
      final stateDirectory = '${temporary.path}/state';
      var daemon = await _startDaemon(
        executable: executable,
        endpoint: endpoint,
        stateDirectory: stateDirectory,
      );
      final clients = <VityodClient>[];
      addTearDown(() async {
        for (final client in clients.reversed) {
          await client.dispose();
        }
        daemon.kill();
        await daemon.exitCode.timeout(const Duration(seconds: 5));
        await temporary.delete(recursive: true);
      });

      final first = await _connect(
        clients,
        endpoint: endpoint,
        clientId: 'reconnect-first',
      );
      await _expectResult(
        first,
        method: 'buffer.delta',
        key: 'dirty-1',
        params: const <String, Object?>{
          'documentId': 'main.styio',
          'baseRevision': 0,
          'targetRevision': 1,
          'startOffset': 0,
          'deletedLength': 0,
          'insertedText': 'unsaved',
        },
      );
      final terminal = await _expectResult(
        first,
        method: 'pty.start',
        key: 'terminal-start',
        params: const <String, Object?>{
          'terminalId': 'terminal-live',
          'executable': '/bin/cat',
          'rows': 24,
          'cols': 80,
        },
      );
      expect(terminal.params['state'], 'running');
      await _expectResult(
        first,
        method: 'task.start',
        key: 'task-start',
        params: const <String, Object?>{
          'taskId': 'task-live',
          'executable': '/usr/bin/yes',
          'timeoutMillis': 30000,
        },
      );
      await _expectResult(
        first,
        method: 'agent.session.start',
        key: 'agent-start',
        params: const <String, Object?>{
          'sessionId': 'agent-live',
          'workspaceId': 'default',
          'workspaceRevision': 0,
          'capabilities': <String>['workspace.read'],
        },
      );
      await _expectResult(
        first,
        method: 'event.resume',
        key: 'first-snapshot',
        params: const <String, Object?>{'afterCursor': 0},
      );
      await _waitForSnapshot(
        first,
        minimumCursor: 1,
        label: 'first acknowledged',
      );
      final acknowledged = first.snapshot!;
      expect(acknowledged.dirtyBuffers.single.contents, 'unsaved');
      await first.dispose();
      clients.remove(first);

      final reconnect = VityodClient(
        transport: SocketVityodTransport(endpointPath: endpoint),
        clientInstanceId: 'reconnect-second',
      );
      reconnect.acceptSnapshot(acknowledged);
      clients.add(reconnect);
      await reconnect.connect();
      await _expectResult(
        reconnect,
        method: 'event.resume',
        key: 'live-reconnect-snapshot',
        params: const <String, Object?>{'afterCursor': 1},
      );
      await _waitForSnapshot(
        reconnect,
        minimumCursor: 1,
        label: 'live reconnect',
      );
      expect(reconnect.snapshot!.activeTerminalIds, contains('terminal-live'));
      expect(reconnect.snapshot!.activeTaskIds, contains('task-live'));
      expect(reconnect.snapshot!.activeAgentSessionIds, contains('agent-live'));
      expect(reconnect.snapshot!.dirtyBuffers.single.revision, 1);

      for (var revision = 1; revision <= 9; revision += 1) {
        await _expectResult(
          reconnect,
          method: 'buffer.delta',
          key: 'dirty-${revision + 1}',
          params: <String, Object?>{
            'documentId': 'main.styio',
            'baseRevision': revision,
            'targetRevision': revision + 1,
            'startOffset': 7 + revision - 1,
            'deletedLength': 0,
            'insertedText': 'x',
          },
        );
      }

      final pruned = await _connect(
        clients,
        endpoint: endpoint,
        clientId: 'reconnect-pruned',
      );
      await _waitForSnapshot(
        pruned,
        minimumCursor: 10,
        label: 'pruned full resync',
      );
      expect(pruned.state.phase, VityodConnectionPhase.connected);
      expect(pruned.snapshot!.events, isEmpty);
      expect(pruned.snapshot!.dirtyBuffers.single.revision, 10);
      final restartBaseline = pruned.snapshot!;

      await reconnect.dispose();
      clients.remove(reconnect);
      await pruned.dispose();
      clients.remove(pruned);
      daemon.kill();
      await daemon.exitCode.timeout(const Duration(seconds: 5));
      daemon = await _startDaemon(
        executable: executable,
        endpoint: endpoint,
        stateDirectory: stateDirectory,
      );

      final restarted = VityodClient(
        transport: SocketVityodTransport(endpointPath: endpoint),
        clientInstanceId: 'reconnect-after-daemon-restart',
      );
      restarted.acceptSnapshot(restartBaseline);
      clients.add(restarted);
      await restarted.connect();
      await _expectResult(
        restarted,
        method: 'event.resume',
        key: 'restart-snapshot',
        params: const <String, Object?>{'afterCursor': 10},
      );
      await _waitForSnapshot(
        restarted,
        minimumCursor: 10,
        label: 'daemon restart',
      );
      expect(
        restarted.snapshot!.dirtyBuffers.single.contents,
        'unsavedxxxxxxxxx',
      );
      expect(restarted.snapshot!.activeAgentSessionIds, contains('agent-live'));
      expect(restarted.snapshot!.activeTerminalIds, isEmpty);
      expect(restarted.snapshot!.activeTaskIds, isEmpty);
    },
  );
}

Future<Process> _startDaemon({
  required File executable,
  required String endpoint,
  required String stateDirectory,
}) async {
  await Directory(stateDirectory).create(recursive: true);
  final daemon = await Process.start(executable.path, <String>[
    '--serve',
    '--endpoint',
    endpoint,
    '--state-dir',
    stateDirectory,
    '--event-capacity',
    '8',
  ]);
  unawaited(daemon.stdout.drain<void>());
  unawaited(daemon.stderr.drain<void>());
  await _waitForEndpoint(endpoint);
  return daemon;
}

Future<VityodClient> _connect(
  List<VityodClient> clients, {
  required String endpoint,
  required String clientId,
}) async {
  final client = VityodClient(
    transport: SocketVityodTransport(endpointPath: endpoint),
    clientInstanceId: clientId,
  );
  clients.add(client);
  await client.connect();
  await _waitForSnapshot(client, label: 'initial $clientId');
  return client;
}

Future<VityodControlEnvelope> _expectResult(
  VityodClient client, {
  required String method,
  required String key,
  required Map<String, Object?> params,
}) async {
  final response = await client.request(
    method: method,
    idempotencyKey: key,
    params: params,
  );
  expect(response.method, '$method.result', reason: response.params.toString());
  return response;
}

File _findVityodExecutable() {
  final bundled = File(
    '${File(Platform.resolvedExecutable).parent.parent.path}/Helpers/vityod',
  );
  if (bundled.existsSync()) return bundled;
  for (final origin in <Directory>[
    Directory.current,
    File(Platform.resolvedExecutable).parent,
  ]) {
    var directory = origin.absolute;
    for (var depth = 0; depth < 12; depth += 1) {
      final candidate = File(
        '${directory.path}/native/vityod/target/debug/vityod',
      );
      if (candidate.existsSync()) return candidate;
      final parent = directory.parent;
      if (parent.path == directory.path) break;
      directory = parent;
    }
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
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('vityod endpoint was not created');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}

Future<void> _waitForSnapshot(
  VityodClient client, {
  int minimumCursor = 0,
  required String label,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while ((client.snapshot?.eventCursor ?? -1) < minimumCursor) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'vityod snapshot was not received for $label '
        '(phase: ${client.state.phase}, reason: ${client.state.reasonCode})',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}
