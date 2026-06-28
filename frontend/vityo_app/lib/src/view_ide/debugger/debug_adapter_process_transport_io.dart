import 'dart:async';
import 'dart:io';

import 'debug_adapter_launcher.dart';
import 'debug_adapter_transport.dart';
import 'debug_launch_contract.dart';
import 'debug_launch_readiness_io.dart';

class DapProcessTransport implements DapByteTransport {
  DapProcessTransport({
    required this.executable,
    this.arguments = const <String>[],
    this.workingDirectory,
    this.environment = const <String, String>{},
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;

  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  Process? _process;
  Future<int>? _exitCode;

  bool get started => _process != null;

  Future<int> get exitCode {
    final exitCode = _exitCode;
    if (exitCode == null) {
      throw StateError('DAP process transport has not been started.');
    }
    return exitCode;
  }

  @override
  Stream<List<int>> get incomingBytes => _incoming.stream;

  Future<void> start() async {
    if (_process != null) {
      return;
    }
    final process = await Process.start(
      executable,
      arguments,
      workingDirectory: workingDirectory,
      environment: environment.isEmpty ? null : environment,
    );
    _process = process;
    process.stdout.listen(
      (chunk) {
        if (!_incoming.isClosed) {
          _incoming.add(chunk);
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        if (!_incoming.isClosed) {
          _incoming.addError(error, stackTrace);
        }
      },
    );
    process.stderr.drain<void>();
    _exitCode = process.exitCode.whenComplete(() async {
      if (!_incoming.isClosed) {
        await _incoming.close();
      }
    });
  }

  @override
  Future<void> send(List<int> bytes) async {
    final process = _process;
    if (process == null) {
      throw StateError('DAP process transport has not been started.');
    }
    process.stdin.add(bytes);
    await process.stdin.flush();
  }

  @override
  Future<void> close() async {
    final process = _process;
    final exitCode = _exitCode;
    _process = null;
    if (process != null) {
      process.kill();
      try {
        await exitCode?.timeout(const Duration(seconds: 2));
      } on Object {
        // Best-effort shutdown; callers still need the transport stream closed.
      }
    }
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}

Future<DapByteTransport> startDapProcessTransport(
  DebugLaunchConfiguration launch,
) async {
  const readinessProbe = DebugLaunchIoReadinessProbe();
  final readiness = await readinessProbe.check(launch);
  if (!readiness.ready) {
    throw StateError(readiness.reason);
  }
  final transport = DapProcessTransport(
    executable:
        readiness.resolvedDebuggerExecutablePath ??
        launch.debuggerExecutablePath,
    arguments: launch.debuggerArguments,
    workingDirectory: launch.cwd,
    environment: launch.environment,
  );
  await transport.start();
  return transport;
}

DapDebugAdapterLauncher createIoDapDebugAdapterLauncher() {
  return const DapDebugAdapterLauncher(
    transportFactory: startDapProcessTransport,
  );
}
