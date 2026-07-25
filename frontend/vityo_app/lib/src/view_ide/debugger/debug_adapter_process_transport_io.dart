import 'dart:async';
import 'dart:io';

import 'debug_adapter_launcher.dart';
import 'debug_adapter_transport.dart';
import 'debug_launch_contract.dart';
import 'debug_launch_readiness_io.dart';

enum DapProcessShutdownStatus {
  notStarted,
  exitedAfterTerminate,
  exitedAfterKill,
  orphaned,
}

class DapProcessShutdownResult {
  const DapProcessShutdownResult({
    required this.status,
    required this.message,
    this.processId,
    this.exitCode,
    this.terminateAccepted = false,
    this.killAccepted = false,
  });

  final DapProcessShutdownStatus status;
  final String message;
  final int? processId;
  final int? exitCode;
  final bool terminateAccepted;
  final bool killAccepted;

  bool get processTerminated =>
      status == DapProcessShutdownStatus.exitedAfterTerminate ||
      status == DapProcessShutdownStatus.exitedAfterKill;
  bool get orphanDetected => status == DapProcessShutdownStatus.orphaned;

  Map<String, Object?> toJson() => <String, Object?>{
    'status': status.name,
    'processTerminated': processTerminated,
    'orphanDetected': orphanDetected,
    'message': message,
    if (processId != null) 'processId': processId,
    if (exitCode != null) 'exitCode': exitCode,
    'terminateAccepted': terminateAccepted,
    'killAccepted': killAccepted,
  };
}

class DapProcessStartRequest {
  const DapProcessStartRequest({
    required this.executable,
    required this.arguments,
    required this.workingDirectory,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
}

abstract interface class DapManagedProcess {
  int get pid;
  Stream<List<int>> get stdoutBytes;
  Stream<List<int>> get stderrBytes;
  Future<int> get exitCode;
  void write(List<int> bytes);
  Future<void> flush();
  Future<void> closeInput();
  bool terminate();
  bool kill();
}

typedef DapManagedProcessStarter =
    Future<DapManagedProcess> Function(DapProcessStartRequest request);

final class _IoDapManagedProcess implements DapManagedProcess {
  const _IoDapManagedProcess(this.process);

  final Process process;

  @override
  int get pid => process.pid;
  @override
  Stream<List<int>> get stdoutBytes => process.stdout;
  @override
  Stream<List<int>> get stderrBytes => process.stderr;
  @override
  Future<int> get exitCode => process.exitCode;
  @override
  void write(List<int> bytes) => process.stdin.add(bytes);
  @override
  Future<void> flush() => process.stdin.flush();
  @override
  Future<void> closeInput() => process.stdin.close();
  @override
  bool terminate() => process.kill(ProcessSignal.sigterm);
  @override
  bool kill() => process.kill(ProcessSignal.sigkill);
}

Future<DapManagedProcess> _startIoDapManagedProcess(
  DapProcessStartRequest request,
) async {
  final process = await Process.start(
    request.executable,
    request.arguments,
    workingDirectory: request.workingDirectory,
    environment: request.environment.isEmpty ? null : request.environment,
  );
  return _IoDapManagedProcess(process);
}

class DapProcessTransport implements DapByteTransport {
  DapProcessTransport({
    required this.executable,
    this.arguments = const <String>[],
    this.workingDirectory,
    this.environment = const <String, String>{},
    this.processStarter = _startIoDapManagedProcess,
    this.terminateGrace = const Duration(seconds: 2),
    this.killGrace = const Duration(seconds: 2),
  });

  final String executable;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final DapManagedProcessStarter processStarter;
  final Duration terminateGrace;
  final Duration killGrace;

  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  DapManagedProcess? _process;
  Future<int>? _exitCode;
  Future<DapProcessShutdownResult>? _shutdownFuture;
  DapProcessShutdownResult? _lastShutdownResult;

  bool get started => _process != null;
  DapProcessShutdownResult? get lastShutdownResult => _lastShutdownResult;

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
    final process = await processStarter(
      DapProcessStartRequest(
        executable: executable,
        arguments: arguments,
        workingDirectory: workingDirectory,
        environment: environment,
      ),
    );
    _process = process;
    process.stdoutBytes.listen(
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
    process.stderrBytes.drain<void>();
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
    process.write(bytes);
    await process.flush();
  }

  @override
  Future<void> close() async {
    await shutdown();
  }

  Future<DapProcessShutdownResult> shutdown() {
    return _shutdownFuture ??= _shutdown();
  }

  Future<DapProcessShutdownResult> _shutdown() async {
    final process = _process;
    final exitCode = _exitCode;
    _process = null;
    if (process == null || exitCode == null) {
      final result = const DapProcessShutdownResult(
        status: DapProcessShutdownStatus.notStarted,
        message: 'DAP process was not started.',
      );
      _lastShutdownResult = result;
      if (!_incoming.isClosed) {
        await _incoming.close();
      }
      return result;
    }

    await process.closeInput();
    final terminateAccepted = process.terminate();
    int? resolvedExitCode;
    try {
      resolvedExitCode = await exitCode.timeout(terminateGrace);
      final result = DapProcessShutdownResult(
        status: DapProcessShutdownStatus.exitedAfterTerminate,
        processId: process.pid,
        exitCode: resolvedExitCode,
        terminateAccepted: terminateAccepted,
        message: 'DAP process exited after terminate.',
      );
      _lastShutdownResult = result;
      return result;
    } on TimeoutException {
      final killAccepted = process.kill();
      try {
        resolvedExitCode = await exitCode.timeout(killGrace);
        final result = DapProcessShutdownResult(
          status: DapProcessShutdownStatus.exitedAfterKill,
          processId: process.pid,
          exitCode: resolvedExitCode,
          terminateAccepted: terminateAccepted,
          killAccepted: killAccepted,
          message: 'DAP process required forced termination.',
        );
        _lastShutdownResult = result;
        return result;
      } on TimeoutException {
        final result = DapProcessShutdownResult(
          status: DapProcessShutdownStatus.orphaned,
          processId: process.pid,
          terminateAccepted: terminateAccepted,
          killAccepted: killAccepted,
          message: 'DAP process did not exit after terminate and kill.',
        );
        _lastShutdownResult = result;
        return result;
      }
    } finally {
      if (!_incoming.isClosed) {
        await _incoming.close();
      }
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
