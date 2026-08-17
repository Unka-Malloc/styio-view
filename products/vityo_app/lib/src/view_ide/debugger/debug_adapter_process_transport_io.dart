import 'dart:async';

import '../../ide/local_service/vityod_client.dart';
import 'debug_adapter_launcher.dart';
import 'debug_adapter_transport.dart';
import 'debug_launch_contract.dart';

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

var _dapProcessSequence = 0;

final class _VityodDapManagedProcess implements DapManagedProcess {
  _VityodDapManagedProcess._({
    required VityodClient client,
    required String processId,
  }) : _client = client,
       _processId = processId,
       pid = processId.hashCode & 0x7fffffff {
    unawaited(_poll());
  }

  static Future<DapManagedProcess> start(
    VityodClient client,
    DapProcessStartRequest request,
  ) async {
    final processId = 'dap-${client.clientInstanceId}-${++_dapProcessSequence}';
    final response = await client.request(
      method: 'dap.start',
      idempotencyKey: 'dap-start-$processId',
      params: <String, Object?>{
        'processId': processId,
        'executable': request.executable,
        'arguments': request.arguments,
        'workingDirectory': request.workingDirectory,
        'environment': request.environment,
      },
    );
    _throwIfError(response);
    return _VityodDapManagedProcess._(client: client, processId: processId);
  }

  final VityodClient _client;
  final String _processId;
  final StreamController<List<int>> _stdout =
      StreamController<List<int>>.broadcast();
  final StreamController<List<int>> _stderr =
      StreamController<List<int>>.broadcast();
  final Completer<int> _exit = Completer<int>();
  Future<void> _writeTail = Future<void>.value();
  Future<int>? _stopFuture;
  var _pollSequence = 0;

  @override
  final int pid;

  @override
  Stream<List<int>> get stdoutBytes => _stdout.stream;

  @override
  Stream<List<int>> get stderrBytes => _stderr.stream;

  @override
  Future<int> get exitCode => _exit.future;

  @override
  void write(List<int> bytes) {
    final payload = List<int>.unmodifiable(bytes);
    _writeTail = _writeTail.then((_) async {
      final response = await _client.request(
        method: 'dap.request',
        idempotencyKey: 'dap-write-$_processId-${++_pollSequence}',
        params: <String, Object?>{
          'processId': _processId,
          'action': 'write',
          'bytes': payload,
        },
      );
      _throwIfError(response);
    });
  }

  @override
  Future<void> flush() => _writeTail;

  @override
  Future<void> closeInput() => flush();

  @override
  bool terminate() {
    unawaited(_stop());
    return true;
  }

  @override
  bool kill() {
    unawaited(_stop());
    return true;
  }

  Future<int> _stop() => _stopFuture ??= () async {
    final response = await _client.request(
      method: 'dap.stop',
      idempotencyKey: 'dap-stop-$_processId',
      params: <String, Object?>{'processId': _processId},
    );
    _throwIfError(response);
    final exitCode = response.params['exitCode'];
    final resolved = exitCode is int ? exitCode : 1;
    if (!_exit.isCompleted) _exit.complete(resolved);
    await _closeStreams();
    return resolved;
  }();

  Future<void> _poll() async {
    try {
      while (!_exit.isCompleted) {
        final response = await _client.request(
          method: 'dap.request',
          idempotencyKey: 'dap-poll-$_processId-${++_pollSequence}',
          params: <String, Object?>{
            'processId': _processId,
            'action': 'poll',
            'maximumBytes': 64 * 1024,
          },
          deadline: const Duration(seconds: 5),
        );
        _throwIfError(response);
        final stdout = _byteList(response.params['stdout']);
        final stderr = _byteList(response.params['stderr']);
        if (stdout.isNotEmpty && !_stdout.isClosed) _stdout.add(stdout);
        if (stderr.isNotEmpty && !_stderr.isClosed) _stderr.add(stderr);
        if (response.params['overflowed'] == true) {
          throw StateError('DAP output exceeded the bounded daemon buffer.');
        }
        final exitCode = response.params['exitCode'];
        if (exitCode is int) {
          if (!_exit.isCompleted) _exit.complete(exitCode);
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    } on Object catch (error, stackTrace) {
      if (_stopFuture == null && !_exit.isCompleted) {
        _exit.completeError(error, stackTrace);
        if (!_stdout.isClosed) _stdout.addError(error, stackTrace);
      }
    } finally {
      await _closeStreams();
    }
  }

  Future<void> _closeStreams() async {
    if (!_stdout.isClosed) await _stdout.close();
    if (!_stderr.isClosed) await _stderr.close();
  }
}

List<int> _byteList(Object? value) {
  if (value is List && value.every((item) => item is int)) {
    return List<int>.unmodifiable(value.cast<int>());
  }
  throw StateError('vityod returned invalid DAP bytes.');
}

void _throwIfError(dynamic response) {
  if (!response.method.endsWith('.error')) return;
  final code = response.params['errorCode'];
  throw StateError(code is String ? code : 'dap_service_error');
}

class DapProcessTransport implements DapByteTransport {
  DapProcessTransport({
    required this.executable,
    this.arguments = const <String>[],
    this.workingDirectory,
    this.environment = const <String, String>{},
    VityodClient? client,
    DapManagedProcessStarter? processStarter,
    this.terminateGrace = const Duration(seconds: 2),
    this.killGrace = const Duration(seconds: 2),
  }) : processStarter =
           processStarter ??
           (client == null
               ? _unavailableDapProcessStarter
               : (request) => _VityodDapManagedProcess.start(client, request));

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
  VityodClient client,
) async {
  if (!launch.ready) {
    throw StateError(launch.reason);
  }
  final transport = DapProcessTransport(
    executable: launch.debuggerExecutablePath,
    arguments: launch.debuggerArguments,
    workingDirectory: launch.cwd,
    environment: launch.environment,
    client: client,
  );
  await transport.start();
  return transport;
}

DapDebugAdapterLauncher createIoDapDebugAdapterLauncher(VityodClient client) {
  return DapDebugAdapterLauncher(
    transportFactory: (launch) => startDapProcessTransport(launch, client),
  );
}

Future<DapManagedProcess> _unavailableDapProcessStarter(
  DapProcessStartRequest request,
) => throw StateError('vityod DAP client is required.');
