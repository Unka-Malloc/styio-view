import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';

import 'agent_client_models.dart';

final class AgentLaunchDescriptor {
  AgentLaunchDescriptor({
    required this.id,
    required this.executable,
    required List<String> arguments,
    required this.workingDirectory,
  }) : arguments = List<String>.unmodifiable(arguments) {
    if (id.isEmpty || id.length > 256) {
      throw ArgumentError.value(id, 'id', 'must be a bounded identifier');
    }
    if (executable.isEmpty) {
      throw ArgumentError.value(executable, 'executable', 'must not be empty');
    }
  }

  final String id;
  final String executable;
  final List<String> arguments;
  final String workingDirectory;
}

final class AgentShutdownReceipt {
  const AgentShutdownReceipt({
    required this.agentId,
    required this.terminated,
    required this.forced,
    required this.exitCode,
  });

  final String agentId;
  final bool terminated;
  final bool forced;
  final int? exitCode;
}

abstract interface class AgentClientTransport {
  Stream<JsonRpcMessage> get incoming;

  Future<int> get exitCode;

  Future<void> send(JsonRpcMessage message);

  Future<AgentShutdownReceipt> close();
}

final class AgentProcessSupervisor {
  const AgentProcessSupervisor();

  Future<AgentClientTransport> launch({
    required AgentLaunchDescriptor descriptor,
    required AgentClientPolicy policy,
  }) async {
    final launchCommand = _resolveLaunchCommand(descriptor);
    final process = await Process.start(
      launchCommand.executable,
      launchCommand.arguments,
      workingDirectory: descriptor.workingDirectory,
      mode: ProcessStartMode.normal,
      includeParentEnvironment: false,
      environment: _minimalProcessEnvironment(),
      runInShell: false,
    );
    return _StdioAgentClientTransport(
      descriptor: descriptor,
      process: process,
      policy: policy,
    );
  }
}

_LaunchCommand _resolveLaunchCommand(AgentLaunchDescriptor descriptor) {
  final executableName = descriptor.executable
      .split(Platform.pathSeparator)
      .last
      .toLowerCase();
  final isFlutterTestHost =
      executableName == 'flutter_tester' ||
      executableName == 'flutter_tester.exe';
  final launchesDartSource =
      descriptor.arguments.length >= 2 &&
      descriptor.arguments.first == 'run' &&
      descriptor.arguments[1].toLowerCase().endsWith('.dart');
  if (!isFlutterTestHost || !launchesDartSource) {
    return _LaunchCommand(descriptor.executable, descriptor.arguments);
  }

  final engineDirectory = File(descriptor.executable).parent;
  final cacheDirectory = engineDirectory.parent.parent.parent;
  final dartExecutable = File(
    '${cacheDirectory.path}${Platform.pathSeparator}dart-sdk'
    '${Platform.pathSeparator}bin${Platform.pathSeparator}'
    '${Platform.isWindows ? 'dart.exe' : 'dart'}',
  );
  if (!dartExecutable.existsSync()) {
    return _LaunchCommand(descriptor.executable, descriptor.arguments);
  }
  return _LaunchCommand(dartExecutable.path, descriptor.arguments);
}

final class _LaunchCommand {
  const _LaunchCommand(this.executable, this.arguments);

  final String executable;
  final List<String> arguments;
}

final class _StdioAgentClientTransport implements AgentClientTransport {
  _StdioAgentClientTransport({
    required AgentLaunchDescriptor descriptor,
    required Process process,
    required AgentClientPolicy policy,
  }) : _descriptor = descriptor,
       _process = process,
       _policy = policy {
    _stdoutSubscription = _boundedLines(process.stdout, policy.maxMessageBytes)
        .listen(
          _decodeLine,
          onError: _onFrameError,
          onDone: _onStdoutDone,
          cancelOnError: true,
        );
    _stderrSubscription = process.stderr.listen((_) {
      // Deliberately drain and discard Agent stderr. Runtime data and secrets
      // never become protocol diagnostics.
    });
    unawaited(
      process.exitCode.then((code) {
        _exitCompleter.complete(code);
        if (!_closing && !_incoming.isClosed) {
          _incoming.addError(
            AgentClientFailure(
              'process_failed',
              'Agent process exited before a supervised shutdown',
            ),
          );
        }
        unawaited(_finishStreams());
      }),
    );
  }

  final AgentLaunchDescriptor _descriptor;
  final Process _process;
  final AgentClientPolicy _policy;
  final StreamController<JsonRpcMessage> _incoming =
      StreamController<JsonRpcMessage>.broadcast(sync: true);
  final Completer<int> _exitCompleter = Completer<int>();
  late final StreamSubscription<String> _stdoutSubscription;
  late final StreamSubscription<List<int>> _stderrSubscription;
  Future<void> _writeLane = Future<void>.value();
  Future<AgentShutdownReceipt>? _shutdown;
  bool _closing = false;
  bool _protocolFailurePending = false;

  @override
  Stream<JsonRpcMessage> get incoming => _incoming.stream;

  @override
  Future<int> get exitCode => _exitCompleter.future;

  @override
  Future<void> send(JsonRpcMessage message) {
    if (_closing || _incoming.isClosed) {
      return Future<void>.error(
        AgentClientFailure('transport_closed', 'Agent transport is closed'),
      );
    }
    final operation = _writeLane.then((_) => _sendNow(message));
    _writeLane = operation.then<void>((_) {}, onError: (_, __) {});
    return operation;
  }

  Future<void> _sendNow(JsonRpcMessage message) async {
    if (_closing || _incoming.isClosed) {
      throw AgentClientFailure('transport_closed', 'Agent transport is closed');
    }
    final encoded = JsonRpcCodec.encode(
      message,
      maxMessageBytes: _policy.maxMessageBytes,
    );
    _process.stdin.writeln(encoded);
    await _process.stdin.flush();
  }

  @override
  Future<AgentShutdownReceipt> close() => _shutdown ??= _closeProcess();

  void _decodeLine(String line) {
    try {
      _incoming.add(
        JsonRpcCodec.decode(line, maxMessageBytes: _policy.maxMessageBytes),
      );
    } on AgentProtocolException catch (error) {
      if (_protocolFailurePending) {
        return;
      }
      _protocolFailurePending = true;
      unawaited(_classifyProtocolFailure(error));
    }
  }

  Future<void> _classifyProtocolFailure(AgentProtocolException error) async {
    try {
      await exitCode.timeout(const Duration(milliseconds: 75));
      // The exit-code listener reports process_failed. This gives a child that
      // exits during startup precedence over incidental toolchain output.
      return;
    } on TimeoutException {
      if (!_incoming.isClosed) {
        _incoming.addError(AgentClientFailure(error.code, error.message));
      }
      await close();
    }
  }

  void _onFrameError(Object error, StackTrace stackTrace) {
    final failure = error is AgentClientFailure
        ? error
        : AgentClientFailure(
            'malformed_message',
            'Agent stdout framing failed',
          );
    _incoming.addError(failure, stackTrace);
    unawaited(close());
  }

  void _onStdoutDone() {
    if (!_closing && !_exitCompleter.isCompleted) {
      // exitCode supplies the correlated process failure after stdout closes.
      return;
    }
    unawaited(_finishStreams());
  }

  Future<AgentShutdownReceipt> _closeProcess() async {
    _closing = true;
    await _writeLane;
    try {
      await _process.stdin.close();
    } on Object {
      // The child may have already closed stdin.
    }
    var forced = false;
    int? code;
    try {
      code = await exitCode.timeout(_policy.shutdownTimeout);
    } on TimeoutException {
      forced = _process.kill();
      try {
        code = await exitCode.timeout(_policy.shutdownTimeout);
      } on TimeoutException {
        code = null;
      }
    }
    await _finishStreams();
    return AgentShutdownReceipt(
      agentId: _descriptor.id,
      terminated: code != null,
      forced: forced,
      exitCode: code,
    );
  }

  Future<void> _finishStreams() async {
    await _stdoutSubscription.cancel();
    await _stderrSubscription.cancel();
    if (!_incoming.isClosed) {
      await _incoming.close();
    }
  }
}

Map<String, String> _minimalProcessEnvironment() {
  if (!Platform.isWindows) {
    return const <String, String>{};
  }
  const allowed = <String>{'SYSTEMROOT', 'WINDIR', 'TEMP', 'TMP'};
  return <String, String>{
    for (final entry in Platform.environment.entries)
      if (allowed.contains(entry.key.toUpperCase())) entry.key: entry.value,
  };
}

Stream<String> _boundedLines(
  Stream<List<int>> bytes,
  int maxMessageBytes,
) async* {
  final buffer = BytesBuilder(copy: false);
  await for (final chunk in bytes) {
    var start = 0;
    for (var index = 0; index < chunk.length; index += 1) {
      if (chunk[index] != 0x0a) {
        continue;
      }
      if (index > start) {
        buffer.add(chunk.sublist(start, index));
      }
      final lineBytes = buffer.takeBytes();
      if (lineBytes.length > maxMessageBytes) {
        throw AgentClientFailure(
          'message_too_large',
          'Agent protocol frame exceeds the configured byte limit',
        );
      }
      var end = lineBytes.length;
      if (end > 0 && lineBytes[end - 1] == 0x0d) {
        end -= 1;
      }
      if (end > 0) {
        try {
          yield utf8.decode(Uint8List.sublistView(lineBytes, 0, end));
        } on FormatException {
          throw AgentClientFailure(
            'malformed_message',
            'Agent protocol frame is not valid UTF-8',
          );
        }
      }
      start = index + 1;
    }
    if (start < chunk.length) {
      buffer.add(chunk.sublist(start));
      if (buffer.length > maxMessageBytes) {
        throw AgentClientFailure(
          'message_too_large',
          'Agent protocol frame exceeds the configured byte limit',
        );
      }
    }
  }
  if (buffer.length != 0) {
    throw AgentClientFailure(
      'malformed_message',
      'Agent protocol stream ended with an incomplete frame',
    );
  }
}
