import 'dart:async';
import 'dart:convert';
import 'dart:io' as io;

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
  final adapter = platformContext == null ? null : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.pty ?? await (prober ?? const LocalPtyProber()).probe();
  return LocalPtyManager(facts: facts, adapter: adapter?.ptyAdapter);
}

class LocalPtyManager implements PtyManager {
  LocalPtyManager({required this.facts, PtyAdapter? adapter})
    : _adapter = adapter ?? PtyAdapter(facts),
      compatibility = (adapter ?? PtyAdapter(facts)).adapt();

  factory LocalPtyManager.linuxDebianArmForTest({
    String scriptUtilityPath = '/usr/bin/script',
  }) {
    return LocalPtyManager(
      facts: PtyFacts.linuxDebianArm(scriptUtilityPath: scriptUtilityPath),
    );
  }

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
  }) {
    return const PtyFailureClassifier(
      sourceManager: 'LocalPtyManager',
    ).classifySession(
      session,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }

  @override
  PtyOperationFailure? failureForResize(
    PtyResizeResult result, {
    String operation = 'pty.resize',
    String target = 'pty',
    String? recoveryHint,
  }) {
    return const PtyFailureClassifier(
      sourceManager: 'LocalPtyManager',
    ).classifyResize(
      result,
      operation: operation,
      target: target,
      recoveryHint: recoveryHint,
    );
  }

  @override
  Future<PtySession> start(PtySessionRequest request) async {
    final plan = _adapter.plan(request);
    if (!plan.supported) {
      return UnsupportedPtySession(
        request: request,
        message: plan.unsupportedMessage ?? 'PTY sessions are not available.',
      );
    }
    try {
      final process = await io.Process.start(
        plan.backendExecutablePath,
        plan.backendArguments,
        workingDirectory: plan.workingDirectory,
        environment: plan.environment.isEmpty ? null : plan.environment,
      );
      return ScriptUtilityPtySession(
        id: 'pty-${DateTime.now().microsecondsSinceEpoch}',
        process: process,
        supportsResize: compatibility.supportsResize,
      );
    } on Object catch (error) {
      return FailedPtySession(request: request, error: error);
    }
  }
}

class ScriptUtilityPtySession implements PtySession {
  ScriptUtilityPtySession({
    required this.id,
    required io.Process process,
    required this.supportsResize,
  }) : _process = process {
    _output = _process.stdout.transform(utf8.decoder).asBroadcastStream();
    _exitCode = _process.exitCode.then((code) {
      if (_state != PtySessionState.closed) {
        _state = code == 0 ? PtySessionState.exited : PtySessionState.failed;
      }
      return code;
    });
  }

  final io.Process _process;
  final bool supportsResize;
  late final Stream<String> _output;
  late final Future<int> _exitCode;
  PtySessionState _state = PtySessionState.running;

  @override
  final String id;

  @override
  PtySessionState get state => _state;

  @override
  Stream<String> get output => _output;

  @override
  Future<int?> get exitCode => _exitCode;

  @override
  Future<void> write(String input) async {
    _process.stdin.write(input);
    await _process.stdin.flush();
  }

  @override
  Future<PtyResizeResult> resize({required int rows, required int cols}) async {
    if (!supportsResize) {
      return PtyResizeResult(
        status: PtyResizeStatus.unsupported,
        rows: rows,
        cols: cols,
        message: 'The script utility PTY backend does not expose resize.',
      );
    }
    return PtyResizeResult(
      status: PtyResizeStatus.failed,
      rows: rows,
      cols: cols,
      message: 'PTY resize backend is not wired yet.',
    );
  }

  @override
  Future<int?> close({bool force = false}) async {
    if (_state == PtySessionState.closed || _state == PtySessionState.exited) {
      return _exitCode;
    }
    if (force) {
      _process.kill();
    } else {
      await _process.stdin.close();
    }
    final code = await _exitCode;
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
  Future<PtyResizeResult> resize({required int rows, required int cols}) async {
    return PtyResizeResult(
      status: PtyResizeStatus.failed,
      rows: rows,
      cols: cols,
      message: error.toString(),
    );
  }

  @override
  Future<int?> close({bool force = false}) async {
    return null;
  }
}
