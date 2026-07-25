import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

import 'package:pty2/pty2.dart' as native;

import '../platform_adapter/platform_adapter.dart';
import '../platform_context/platform_context.dart';
import 'pty_adapter.dart';
import 'pty_facts.dart';
import 'pty_manager.dart';
import 'pty_prober.dart';
import 'pty_prober_io.dart';

Future<PtyManager> createPlatformPtyManager({
  PtyProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  final adapter = platformContext == null
      ? null
      : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.pty ?? await (prober ?? const LocalPtyProber()).probe();
  return LocalPtyManager(facts: facts, adapter: adapter?.ptyAdapter);
}

class LocalPtyManager implements PtyManager {
  LocalPtyManager({required this.facts, PtyAdapter? adapter})
    : _adapter = adapter ?? PtyAdapter(facts),
      compatibility = (adapter ?? PtyAdapter(facts)).adapt();

  factory LocalPtyManager.linuxDebianArmForTest() =>
      LocalPtyManager(facts: PtyFacts.linuxDebianArm());

  final PtyAdapter _adapter;

  @override
  final PtyFacts facts;

  @override
  final PtyCompatibility compatibility;

  @override
  PtyOperationFailure? failureForSession(
    PtySession session, {
    String operation = 'pty.start',
    String? recoveryHint,
  }) => const PtyFailureClassifier(
    sourceManager: 'LocalPtyManager',
  ).classifySession(session, operation: operation, recoveryHint: recoveryHint);

  @override
  PtyOperationFailure? failureForResize(
    PtyResizeResult result, {
    String operation = 'pty.resize',
    String target = 'pty',
    String? recoveryHint,
  }) => const PtyFailureClassifier(sourceManager: 'LocalPtyManager')
      .classifyResize(
        result,
        operation: operation,
        target: target,
        recoveryHint: recoveryHint,
      );

  @override
  Future<PtySession> start(PtySessionRequest request) async {
    final plan = _adapter.plan(request);
    if (!plan.supported) {
      return UnsupportedPtySession(
        request: request,
        message:
            plan.unsupportedMessage ?? 'Native PTY sessions are not available.',
      );
    }
    try {
      final launch = io.Platform.isWindows
          ? _windowsFailClosedLaunch(plan)
          : _NativeLaunch(
              executable: plan.backendExecutablePath,
              arguments: plan.backendArguments,
              environment: plan.environment,
            );
      final process = native.PseudoTerminal.start(
        launch.executable,
        launch.arguments,
        workingDirectory: plan.workingDirectory,
        environment: launch.environment.isEmpty ? null : launch.environment,
        raw: true,
      );
      process.resize(request.cols, request.rows);
      return NativePtySession(
        id: 'pty-${DateTime.now().microsecondsSinceEpoch}',
        process: process,
        providerKind: plan.providerKind,
      );
    } on Object catch (error) {
      return FailedPtySession(request: request, error: error);
    }
  }

  _NativeLaunch _windowsFailClosedLaunch(PtyExecutionPlan plan) {
    const payloadKey = 'VITYO_CONPTY_LAUNCH_REQUEST';
    final payload = base64Encode(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'executable': plan.backendExecutablePath,
          'arguments': plan.backendArguments,
        }),
      ),
    );
    const script = r'''
$payload = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($env:VITYO_CONPTY_LAUNCH_REQUEST))
Remove-Item Env:VITYO_CONPTY_LAUNCH_REQUEST
$request = $payload | ConvertFrom-Json
if ([Console]::IsInputRedirected -or [Console]::IsOutputRedirected) {
  [Console]::Error.WriteLine('Vityo refused a non-ConPTY terminal backend.')
  exit 125
}
& $request.executable @($request.arguments)
if ($null -eq $LASTEXITCODE) { exit 0 }
exit $LASTEXITCODE
''';
    final encodedScript = base64Encode(const Utf16Encoder().convert(script));
    return _NativeLaunch(
      executable: 'powershell.exe',
      arguments: <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-EncodedCommand',
        encodedScript,
      ],
      environment: <String, String>{...plan.environment, payloadKey: payload},
    );
  }
}

class _NativeLaunch {
  const _NativeLaunch({
    required this.executable,
    required this.arguments,
    required this.environment,
  });

  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;
}

class NativePtySession implements PtySession {
  NativePtySession({
    required this.id,
    required native.PseudoTerminal process,
    required this.providerKind,
  }) : _process = process {
    _outputController = StreamController<String>();
    _process.out.listen(
      _outputController.add,
      onError: _outputController.addError,
      onDone: () {
        if (!_outputController.isClosed) unawaited(_outputController.close());
      },
    );
    _exitCode = _process.exitCode.then((code) {
      if (_state != PtySessionState.closed) {
        _state = code == 0 ? PtySessionState.exited : PtySessionState.failed;
      }
      return code;
    });
  }

  final native.PseudoTerminal _process;
  final PtyProviderKind providerKind;
  late final StreamController<String> _outputController;
  late final Future<int> _exitCode;
  PtySessionState _state = PtySessionState.running;

  @override
  final String id;

  @override
  PtySessionState get state => _state;

  @override
  Stream<String> get output => _outputController.stream;

  @override
  Future<int?> get exitCode => _exitCode;

  @override
  Future<void> write(String input) async => _process.write(input);

  @override
  Future<PtyResizeResult> resize({required int rows, required int cols}) async {
    try {
      _process.resize(cols, rows);
      return PtyResizeResult(
        status: PtyResizeStatus.applied,
        rows: rows,
        cols: cols,
      );
    } on Object catch (error) {
      return PtyResizeResult(
        status: PtyResizeStatus.failed,
        rows: rows,
        cols: cols,
        message: 'Native PTY resize failed: $error',
      );
    }
  }

  @override
  Future<PtySignalResult> sendSignal(PtySignal signal) async {
    try {
      if (signal == PtySignal.eof) {
        _process.write(io.Platform.isWindows ? '\u001a\r\n' : '\u0004');
      } else {
        _process.kill(switch (signal) {
          PtySignal.interrupt => io.ProcessSignal.sigint,
          PtySignal.terminate => io.ProcessSignal.sigterm,
          PtySignal.kill => io.ProcessSignal.sigkill,
          PtySignal.eof => io.ProcessSignal.sigterm,
        });
      }
      return PtySignalResult(signal: signal, status: PtySignalStatus.sent);
    } on Object catch (error) {
      return PtySignalResult(
        signal: signal,
        status: PtySignalStatus.failed,
        message: 'Native PTY signal failed: $error',
      );
    }
  }

  @override
  Future<int?> close({bool force = false}) async {
    if (_state == PtySessionState.closed || _state == PtySessionState.exited) {
      return _exitCode;
    }
    _process.kill(force ? io.ProcessSignal.sigkill : io.ProcessSignal.sigterm);
    final code = await _exitCode.timeout(const Duration(seconds: 3));
    _state = PtySessionState.closed;
    return code;
  }
}

class FailedPtySession implements PtySession {
  FailedPtySession({required this.request, required this.error});

  final PtySessionRequest request;
  final Object error;

  @override
  String get id => 'failed-pty';
  @override
  PtySessionState get state => PtySessionState.failed;
  @override
  Stream<String> get output => Stream<String>.value(error.toString());
  @override
  Future<int?> get exitCode async => null;
  @override
  Future<void> write(String input) async {}
  @override
  Future<PtyResizeResult> resize({
    required int rows,
    required int cols,
  }) async => PtyResizeResult(
    status: PtyResizeStatus.failed,
    rows: rows,
    cols: cols,
    message: error.toString(),
  );
  @override
  Future<PtySignalResult> sendSignal(PtySignal signal) async => PtySignalResult(
    signal: signal,
    status: PtySignalStatus.failed,
    message: error.toString(),
  );
  @override
  Future<int?> close({bool force = false}) async => null;
}

class Utf16Encoder extends Converter<String, List<int>> {
  const Utf16Encoder();

  @override
  List<int> convert(String input) => <int>[
    for (final unit in input.codeUnits) ...<int>[unit & 0xff, unit >> 8],
  ];
}
