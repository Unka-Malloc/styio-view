import 'dart:async';
import 'dart:io';

import 'package:vityo_app/src/ide/local_service/vityod_client.dart';

class VityodTestHarness {
  VityodTestHarness._({
    required this.client,
    required Process daemon,
    required Directory directory,
  }) : _daemon = daemon,
       _directory = directory;

  final VityodClient client;
  final Process _daemon;
  final Directory _directory;

  static bool get isSupported => Platform.isLinux || Platform.isMacOS;

  static Future<VityodTestHarness> start({required String clientId}) async {
    final executable = _findExecutable();
    if (!executable.existsSync()) {
      throw StateError(
        'Build the focused vityod Cargo target before running this test.',
      );
    }
    final directory = await Directory.systemTemp.createTemp('vd-test-');
    final endpoint = '${directory.path}/service.sock';
    final daemon = await Process.start(executable.path, <String>[
      '--serve',
      '--endpoint',
      endpoint,
    ]);
    unawaited(daemon.stdout.drain<void>());
    unawaited(daemon.stderr.drain<void>());
    try {
      await _waitForEndpoint(endpoint);
      final client = VityodClient(
        transport: SocketVityodTransport(endpointPath: endpoint),
        clientInstanceId: clientId,
      );
      await client.connect();
      return VityodTestHarness._(
        client: client,
        daemon: daemon,
        directory: directory,
      );
    } on Object {
      daemon.kill();
      await daemon.exitCode.timeout(const Duration(seconds: 5));
      await directory.delete(recursive: true);
      rethrow;
    }
  }

  Future<void> close() async {
    await client.dispose();
    _daemon.kill();
    await _daemon.exitCode.timeout(const Duration(seconds: 5));
    await _directory.delete(recursive: true);
  }
}

File _findExecutable() {
  final bundled = File(
    '${File(Platform.resolvedExecutable).parent.parent.path}/Helpers/vityod',
  );
  if (bundled.existsSync()) return bundled;
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
      if (DateTime.now().isAfter(deadline)) {
        throw TimeoutException('vityod test endpoint was not created');
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }
}
