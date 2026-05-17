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

  test('pty manager runs command inside a real tty on linux script backend', () async {
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
    final exitCode = await session.exitCode.timeout(const Duration(seconds: 5));
    final output = await outputFuture.timeout(const Duration(seconds: 5));

    expect(session.state, PtySessionState.exited);
    expect(exitCode, 0);
    expect(output, contains('tty-ok'));
    expect(output, isNot(contains('no-tty')));
  });

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
  });

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
