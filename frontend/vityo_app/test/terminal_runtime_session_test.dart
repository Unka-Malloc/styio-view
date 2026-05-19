import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test('terminal interaction controller records output input and resize', () async {
    final session = _FakePtySession();
    final runtime = TerminalRuntime(
      ptyManager: _FakePtyManager(session),
      shellConfiguration: const ShellConfiguration(
        defaultProfileId: 'sh',
        profiles: <ShellProfileConfiguration>[
          ShellProfileConfiguration(
            id: 'sh',
            executablePath: '/bin/sh',
            family: ShellFamily.sh,
          ),
        ],
      ),
    );
    final controller = TerminalInteractionController(runtime: runtime);
    addTearDown(controller.dispose);

    final started = await controller.start(rows: 30, cols: 100);
    session.emit('hello\n');
    await Future<void>.delayed(Duration.zero);
    await controller.sendInput('echo ok\n');
    final resize = await controller.resize(rows: 40, cols: 120);

    expect(started.sessionId, 'fake-pty');
    expect(controller.snapshot?.state, PtySessionState.running);
    expect(controller.snapshot?.outputLines, <String>['hello\n']);
    expect(controller.snapshot?.lastInput, 'echo ok\n');
    expect(session.writes, <String>['echo ok\n']);
    expect(resize?.applied, isTrue);
    expect(controller.snapshot?.lastResize?.cols, 120);
    expect(controller.snapshot?.toJson()['state'], 'running');
  });
}

class _FakePtyManager implements PtyManager {
  const _FakePtyManager(this.session);

  final _FakePtySession session;

  @override
  PtyCompatibility get compatibility => PtyAdapter(facts).adapt();

  @override
  PtyFacts get facts => PtyFacts.linuxDebianArm(scriptUtilityPath: '/script');

  @override
  Future<PtySession> start(PtySessionRequest request) async => session;

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
  final StreamController<String> _output = StreamController<String>.broadcast();
  final List<String> writes = <String>[];

  void emit(String value) {
    _output.add(value);
  }

  @override
  String get id => 'fake-pty';

  @override
  PtySessionState get state => PtySessionState.running;

  @override
  Stream<String> get output => _output.stream;

  @override
  Future<int?> get exitCode async => null;

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
    );
  }

  @override
  Future<int?> close({bool force = false}) async {
    await _output.close();
    return 0;
  }
}
