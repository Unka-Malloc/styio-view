import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';

void main() {
  test('pty prober classifies linux debian arm script backend facts', () async {
    final facts = await LocalPtyProber(
      operatingSystem: 'linux',
      architectureReader: () async => 'aarch64',
      osReleaseReader: () async => const <String, String>{
        'ID': 'debian',
        'PRETTY_NAME': 'Debian GNU/Linux',
      },
      scriptPathReader: () async => '/usr/bin/script',
      clock: () => DateTime.utc(2026, 5, 16),
    ).probe();

    expect(facts.supportsLinuxDebianArmTarget, isTrue);
    expect(facts.compatibilityTarget, 'linux-debian-arm');
    expect(facts.providerKind, PtyProviderKind.scriptUtility);
    expect(facts.supportsPty, isTrue);
    expect(facts.supportsResize, isFalse);
    expect(facts.entries['pty.scriptUtilityPath']?.value, '/usr/bin/script');
  });

  test('pty adapter creates script utility execution plan', () {
    final facts = PtyFacts.linuxDebianArm(scriptUtilityPath: '/usr/bin/script');
    final adapter = PtyAdapter(facts);
    final plan = adapter.plan(
      const PtySessionRequest(
        executablePath: '/bin/sh',
        arguments: <String>['-c', 'printf adapter-ok'],
      ),
    );

    expect(adapter.adapt().isLinuxDebianArm, isTrue);
    expect(plan.supported, isTrue);
    expect(plan.backendExecutablePath, '/usr/bin/script');
    expect(plan.backendArguments, contains('-qfec'));
    expect(plan.backendArguments.join(' '), contains('/bin/sh'));
  });

  test(
    'pty manager runs command inside a real tty on linux script backend',
    () async {
      final facts = await const LocalPtyProber().probe();
      final manager = LocalPtyManager(facts: facts);

      expect(facts.supportsPty, isTrue);
      expect(manager.compatibility.providerKind, PtyProviderKind.scriptUtility);

      final session = await manager.start(
        const PtySessionRequest(
          executablePath: '/bin/sh',
          arguments: <String>[
            '-c',
            'test -t 1 && printf tty-ok || printf no-tty',
          ],
        ),
      );
      final outputFuture = session.output.join();
      final exitCode = await session.exitCode.timeout(
        const Duration(seconds: 5),
      );
      final output = await outputFuture.timeout(const Duration(seconds: 5));

      expect(session.state, PtySessionState.exited);
      expect(exitCode, 0);
      expect(output, contains('tty-ok'));
      expect(output, isNot(contains('no-tty')));
    },
    skip: !Platform.isLinux ? 'Linux script PTY backend only.' : false,
  );

  test('pty manager exposes structured resize degradation', () async {
    final manager = LocalPtyManager.linuxDebianArmForTest(
      scriptUtilityPath: '/usr/bin/script',
    );
    final session = await manager.start(
      const PtySessionRequest(
        executablePath: '/usr/bin/printf',
        arguments: <String>['resize-test'],
      ),
    );
    final outputFuture = session.output.join();
    final resize = await session.resize(rows: 40, cols: 120);
    final exitCode = await session.exitCode.timeout(const Duration(seconds: 5));
    final output = await outputFuture.timeout(const Duration(seconds: 5));

    expect(resize.status, PtyResizeStatus.unsupported);
    final resizeFailure = manager.failureForResize(resize, target: session.id);
    expect(resizeFailure, isNotNull);
    expect(resizeFailure!.kind, PtyFailureKind.resizeUnsupported);
    expect(exitCode, 0);
    expect(output, contains('resize-test'));
  }, skip: !Platform.isLinux ? 'Linux script PTY backend only.' : false);

  test('pty manager delegates native resize and signal backends', () async {
    final resizeRequests = <PtyNativeResizeRequest>[];
    final signalRequests = <PtyNativeSignalRequest>[];
    final manager = LocalPtyManager.linuxDebianArmForTest(
      scriptUtilityPath: '/usr/bin/script',
      nativeOperations: PtyNativeOperationBackendRegistry(
        backends: <PtyNativeOperationBackend>[
          PtyNativeOperationBackend(
            backendId: 'native-fixture',
            label: 'Native Fixture',
            resize: (request) async {
              resizeRequests.add(request);
              return PtyResizeResult(
                status: PtyResizeStatus.applied,
                rows: request.rows,
                cols: request.cols,
                message: 'native resize applied',
              );
            },
            signal: (request) async {
              signalRequests.add(request);
              return PtySignalResult(
                signal: request.signal,
                status: PtySignalStatus.sent,
                message: 'native signal sent',
              );
            },
          ),
        ],
      ),
    );
    final session = await manager.start(
      const PtySessionRequest(
        executablePath: '/usr/bin/printf',
        arguments: <String>['native-ops'],
      ),
    );
    final outputFuture = session.output.join();

    final resize = await session.resize(rows: 42, cols: 132);
    final signal = await session.sendSignal(PtySignal.interrupt);
    final exitCode = await session.exitCode.timeout(const Duration(seconds: 5));
    final output = await outputFuture.timeout(const Duration(seconds: 5));

    expect(resize.applied, isTrue);
    expect(signal.sent, isTrue);
    expect(resizeRequests.single.rows, 42);
    expect(resizeRequests.single.processId, isNotNull);
    expect(signalRequests.single.signal, PtySignal.interrupt);
    expect(signalRequests.single.processId, isNotNull);
    expect(exitCode, 0);
    expect(output, contains('native-ops'));
  }, skip: !Platform.isLinux ? 'Linux script PTY backend only.' : false);

  test(
    'pty manager merges backend stdout and stderr into terminal output',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_fake_script_pty_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final fakeScript = File('${tempRoot.path}/fake-script.sh');
      await fakeScript.writeAsString('''
#!/bin/sh
printf "fake-stdout\\n"
printf "fake-stderr\\n" >&2
''');
      await Process.run('chmod', <String>['+x', fakeScript.path]);
      final manager = LocalPtyManager.linuxDebianArmForTest(
        scriptUtilityPath: fakeScript.path,
      );

      final session = await manager.start(
        const PtySessionRequest(
          executablePath: '/bin/echo',
          arguments: <String>['ignored'],
        ),
      );
      final outputFuture = session.output.join();
      final exitCode = await session.exitCode.timeout(
        const Duration(seconds: 5),
      );
      final output = await outputFuture.timeout(const Duration(seconds: 5));

      expect(exitCode, 0);
      expect(output, contains('fake-stdout'));
      expect(output, contains('fake-stderr'));
    },
    skip: !Platform.isLinux ? 'Linux script PTY backend only.' : false,
  );

  test('pty manager classifies unsupported sessions structurally', () async {
    final manager = UnsupportedPtyManager(
      facts: PtyFacts.linuxDebianArm(scriptUtilityPath: '/usr/bin/script'),
    );
    final session = await manager.start(
      const PtySessionRequest(executablePath: '/bin/sh'),
    );
    final sessionFailure = manager.failureForSession(session);
    final resizeFailure = manager.failureForResize(
      await session.resize(rows: 40, cols: 120),
      target: session.id,
    );

    expect(sessionFailure, isNotNull);
    expect(sessionFailure!.kind, PtyFailureKind.unsupported);
    expect(sessionFailure.sourceManager, 'UnsupportedPtyManager');
    expect(resizeFailure!.kind, PtyFailureKind.resizeUnsupported);
    expect(resizeFailure.toJson()['target'], 'unsupported-pty');
  });

  test('local host remains debian arm for pty prober target', () async {
    if (!Platform.isLinux) {
      return;
    }

    final machine = await Process.run('uname', const <String>['-m']);
    final osRelease = await File('/etc/os-release').readAsString();
    final isDebianArmHost =
        Platform.isLinux &&
        osRelease.contains('ID=debian') &&
        machine.stdout.toString().trim().toLowerCase() == 'aarch64';

    if (isDebianArmHost) {
      final facts = await const LocalPtyProber().probe();
      expect(facts.supportsLinuxDebianArmTarget, isTrue);
      expect(facts.supportsScriptUtility, isTrue);
      expect(facts.scriptUtilityPath, isNotNull);
    }
  });
}
