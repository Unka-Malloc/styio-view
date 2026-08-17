import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'platform/platform_policy.dart';
import 'vityod_client.dart';
import 'transport/windows_named_pipe.dart';

Future<VityodClient?> createPlatformVityodClient() async {
  if (!VityodPlatformPolicy.supportsLocalDaemon) return null;
  final support = await getApplicationSupportDirectory();
  final serviceDirectory = Directory('${support.path}/vityod');
  await serviceDirectory.create(recursive: true);
  final endpoint = Platform.isWindows
      ? r'\\.\pipe\vityo-vityod'
      : '${serviceDirectory.path}/service.sock';
  final client = VityodClient(
    transport: SocketVityodTransport(endpointPath: endpoint),
    clientInstanceId: 'vityo-${DateTime.now().microsecondsSinceEpoch}',
  );
  try {
    await client.connect();
    return client;
  } on SocketException {
    await _startPackagedVityod(endpoint, serviceDirectory.path);
    await _waitForEndpoint(endpoint);
    await client.connect();
    return client;
  } on WindowsNamedPipeUnavailable {
    await _startPackagedVityod(endpoint, serviceDirectory.path);
    await _waitForEndpoint(endpoint);
    await client.connect();
    return client;
  }
}

Future<void> _startPackagedVityod(
  String endpoint,
  String stateDirectory,
) async {
  final executable = _packagedVityodExecutable();
  if (!executable.existsSync()) {
    throw StateError('The packaged vityod component is missing.');
  }
  await Process.start(executable.path, <String>[
    '--serve',
    '--endpoint',
    endpoint,
    '--state-dir',
    stateDirectory,
  ], mode: ProcessStartMode.detached);
}

File _packagedVityodExecutable() {
  final applicationBinary = File(Platform.resolvedExecutable);
  if (Platform.isMacOS) {
    return File('${applicationBinary.parent.parent.path}/Helpers/vityod');
  }
  if (Platform.isWindows) {
    return File('${applicationBinary.parent.path}/components/vityod.exe');
  }
  return File('${applicationBinary.parent.path}/components/vityod');
}

Future<void> _waitForEndpoint(String endpoint) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  if (Platform.isWindows) {
    while (true) {
      try {
        final pipe = await WindowsNamedPipeConnection.connect(endpoint);
        await pipe.close();
        return;
      } on WindowsNamedPipeUnavailable {
        if (DateTime.now().isAfter(deadline)) {
          throw TimeoutException(
            'The packaged vityod endpoint did not become ready.',
          );
        }
        await Future<void>.delayed(const Duration(milliseconds: 25));
      }
    }
  }
  while (!File(endpoint).existsSync()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException(
        'The packaged vityod endpoint did not become ready.',
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 25));
  }
}
