import 'dart:async';

import 'package:vityo_app/src/view_ide/environment/system_compatibility/pty/pty_adapter.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/pty/pty_facts.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/pty/pty_manager.dart';
import 'package:vityo_app/src/view_ide/toolchain/terminal_runtime_registry.dart';

Future<void> main() async {
  await _runOperationScenario();
  await _runRestoreScenario();
  // ignore: avoid_print
  print('terminal_runtime_registry_test passed');
}

Future<void> _runOperationScenario() async {
  final session = _FakePtySession('pty-1');
  final registry = TerminalRuntimeRegistry(
    ptyManager: _FakePtyManager(session),
    stdoutCapBytes: 16,
    stdoutCapDeltas: 2,
    clock: () => DateTime.utc(2026, 6, 29, 12, 30, 0),
  );

  final started = await registry.start(
    operationId: 'terminal.run',
    sessionId: 'terminal.1',
    request: const PtySessionRequest(
      executablePath: '/bin/bash',
      arguments: <String>['-lc', 'echo hi'],
      environment: <String, String>{'TOKEN': 'secret-value'},
      workingDirectory: '/workspace',
      rows: 24,
      cols: 80,
    ),
  );
  session.emit('one\n');
  session.emit('two\n');
  session.emit('three\n');
  await Future<void>.delayed(Duration.zero);

  final listed = registry.list();
  final snapshot = registry.snapshotFor('terminal.1')!;
  final writeResult = await registry.write(
    sessionId: 'terminal.1',
    input: 'help\n',
  );
  final resizeResult = await registry.resize(
    sessionId: 'terminal.1',
    rows: 40,
    cols: 120,
  );
  final exitCode = await registry.kill(sessionId: 'terminal.1');
  final cleaned = await registry.cleanup(sessionId: 'terminal.1');
  final restorePlan = registry.restorePlan('terminal.1');

  _expect(started.sessionId == 'terminal.1', 'started session id');
  _expect(started.state == PtySessionState.running, 'started state');
  _expect(listed.length == 1, 'list length');
  _expect(snapshot.record.stdoutDeltas.length == 2, 'stdout cap');
  _expect(snapshot.outputTruncated, 'output truncated');
  _expect(
    writeResult?.record.runtimeEvents.any(
          (event) => event.message == 'Terminal input written.',
        ) ==
        true,
    'write event',
  );
  _expect(resizeResult?.applied == true, 'resize applied');
  _expect(exitCode == 0, 'kill exit code');
  _expect(cleaned?.cleanedUp == true, 'cleanup flag');
  _expect(
    restorePlan.mode == TerminalRuntimeRestoreMode.blocked,
    'blocked restore plan',
  );
  _expect(restorePlan.requiresConfirmation, 'blocked restore confirmation');
}

Future<void> _runRestoreScenario() async {
  final session = _FakePtySession('pty-2');
  final registry = TerminalRuntimeRegistry(
    ptyManager: _FakePtyManager(session),
    clock: () => DateTime.utc(2026, 6, 29, 12, 45, 0),
  );

  await registry.start(
    operationId: 'terminal.replay',
    sessionId: 'terminal.2',
    request: const PtySessionRequest(
      executablePath: '/bin/bash',
      arguments: <String>['-lc', 'printf hello'],
      workingDirectory: '/workspace',
      rows: 24,
      cols: 80,
    ),
  );
  await registry.cleanup(sessionId: 'terminal.2', force: true);
  final restorePlan = registry.restorePlan('terminal.2');

  _expect(
    restorePlan.mode == TerminalRuntimeRestoreMode.replay,
    'replay restore mode',
  );
  _expect(restorePlan.safeToRestore, 'safe restore');
  _expect(!restorePlan.outputTruncated, 'restore output truncation');
}

void _expect(bool condition, String label) {
  if (!condition) {
    throw StateError('terminal_runtime_registry_test failed: $label');
  }
}

class _FakePtyManager implements PtyManager {
  _FakePtyManager(this.session);

  final _FakePtySession session;
  @override
  final PtyFacts facts = PtyFacts.linuxDebianArm(scriptUtilityPath: '/script');
  @override
  late final PtyCompatibility compatibility = PtyAdapter(facts).adapt();

  @override
  Future<PtySession> start(PtySessionRequest request) async {
    session.lastRequest = request;
    return session;
  }

  @override
  PtyOperationFailure? failureForResize(
    PtyResizeResult result, {
    String operation = 'pty.resize',
    String target = 'pty',
    String? recoveryHint,
  }) {
    return null;
  }

  @override
  PtyOperationFailure? failureForSession(
    PtySession session, {
    String operation = 'pty.start',
    String? recoveryHint,
  }) {
    return null;
  }
}

class _FakePtySession implements PtySession {
  _FakePtySession(this.id) {
    _exitCodeCompleter = Completer<int?>();
  }

  @override
  final String id;
  final StreamController<String> _outputController =
      StreamController<String>.broadcast(sync: true);
  late final Completer<int?> _exitCodeCompleter;
  PtySessionState _state = PtySessionState.running;
  PtySessionRequest? lastRequest;
  final List<String> writes = <String>[];

  void emit(String chunk) {
    _outputController.add(chunk);
  }

  @override
  PtySessionState get state => _state;

  @override
  Stream<String> get output => _outputController.stream;

  @override
  Future<int?> get exitCode => _exitCodeCompleter.future;

  @override
  Future<void> write(String input) async {
    writes.add(input);
  }

  @override
  Future<PtyResizeResult> resize({required int rows, required int cols}) async {
    return PtyResizeResult(
      status: PtyResizeStatus.applied,
      rows: rows,
      cols: cols,
      message: 'Resized to $rows x $cols.',
    );
  }

  @override
  Future<PtySignalResult> sendSignal(PtySignal signal) async {
    return PtySignalResult(
      signal: signal,
      status: PtySignalStatus.sent,
      message: 'Sent ${signal.name}.',
    );
  }

  @override
  Future<int?> close({bool force = false}) async {
    if (_state == PtySessionState.closed) {
      return _exitCodeCompleter.future;
    }
    if (!_exitCodeCompleter.isCompleted) {
      _exitCodeCompleter.complete(0);
    }
    _state = PtySessionState.closed;
    if (!_outputController.isClosed) {
      await _outputController.close();
    }
    return 0;
  }
}
