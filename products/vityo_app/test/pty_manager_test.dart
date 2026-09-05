import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';

const _interactivePtyTimeout = Duration(seconds: 30);

void main() {
  test('pty prober classifies Linux as native forkpty', () async {
    final facts = await LocalPtyProber(
      operatingSystem: 'linux',
      architectureReader: () async => 'aarch64',
      osReleaseReader: () async => const <String, String>{
        'ID': 'debian',
        'PRETTY_NAME': 'Debian GNU/Linux',
      },
      clock: () => DateTime.utc(2026, 5, 16),
    ).probe();

    expect(facts.supportsLinuxDebianArmTarget, isTrue);
    expect(facts.providerKind, PtyProviderKind.posixPty);
    expect(facts.supportsForkPty, isTrue);
    expect(facts.supportsResize, isTrue);
  });

  test('pty prober detects ConPTY API fail-closed', () async {
    final supported = await LocalPtyProber(
      operatingSystem: 'windows',
      architectureReader: () async => 'x64',
      osReleaseReader: () async => const <String, String>{},
      conPtyAvailabilityReader: () async => true,
    ).probe();
    final unavailable = await LocalPtyProber(
      operatingSystem: 'windows',
      architectureReader: () async => 'x64',
      osReleaseReader: () async => const <String, String>{},
      conPtyAvailabilityReader: () async => false,
    ).probe();

    expect(supported.providerKind, PtyProviderKind.conPty);
    expect(supported.supportsConPty, isTrue);
    expect(unavailable.providerKind, PtyProviderKind.unsupported);
    expect(unavailable.supportsPty, isFalse);
  });

  test('pty adapter creates a native execution plan without a shell', () {
    final plan = PtyAdapter(PtyFacts.linuxDebianArm()).plan(
      const PtySessionRequest(
        executablePath: '/bin/sh',
        arguments: <String>['-c', 'printf adapter-ok'],
      ),
    );

    expect(plan.supported, isTrue);
    expect(plan.providerKind, PtyProviderKind.posixPty);
    expect(plan.backendExecutablePath, '/bin/sh');
    expect(plan.backendArguments, <String>['-c', 'printf adapter-ok']);
  });

  test(
    'pty manager runs a command inside a real desktop PTY',
    () async {
      final facts = await const LocalPtyProber().probe();
      final manager = LocalPtyManager(facts: facts);
      final session = await manager.start(_ttyProbeRequest());
      final output = <String>[];
      if (Platform.isWindows) {
        final ready = Completer<void>();
        final done = Completer<void>();
        final subscription = session.output.listen((chunk) {
          output.add(chunk);
          if (!ready.isCompleted) {
            ready.complete();
          }
        }, onDone: done.complete);
        await ready.future.timeout(_interactivePtyTimeout);
        await session.write(_ttyProbeCommand());
        await done.future.timeout(_interactivePtyTimeout);
        await subscription.cancel();
      } else {
        output.add(await session.output.join().timeout(_interactivePtyTimeout));
      }
      final exitCode = await session.exitCode.timeout(_interactivePtyTimeout);
      final fullOutput = output.join();

      expect(exitCode, 0);
      expect(fullOutput, contains('tty-ok'));
      expect(fullOutput, isNot(contains('no-tty')));
      expect(session.state, PtySessionState.exited);
    },
    skip: Platform.isWindows
        ? 'Hosted Windows ConPTY is fail-closed in CI.'
        : (!_isDesktopHost ? 'Desktop native PTY only.' : false),
  );

  test(
    'native PTY applies resize and reports it to the child',
    () async {
      final facts = await const LocalPtyProber().probe();
      final manager = LocalPtyManager(facts: facts);
      final session = await manager.start(_resizeProbeRequest());
      final outputFuture = session.output.join();
      final resize = await session.resize(rows: 40, cols: 120);
      final exitCode = await session.exitCode.timeout(
        const Duration(seconds: 10),
      );
      final output = await outputFuture.timeout(const Duration(seconds: 10));

      expect(resize.applied, isTrue);
      expect(exitCode, 0);
      expect(output, contains('120x40'));
      expect(manager.failureForResize(resize, target: session.id), isNull);
    },
    skip: !_isDesktopHost ? 'Desktop native PTY only.' : false,
  );

  test(
    'native PTY close terminates the process lifecycle',
    () async {
      final facts = await const LocalPtyProber().probe();
      final manager = LocalPtyManager(facts: facts);
      final session = await manager.start(_longRunningRequest());

      final exitCode = await session
          .close(force: true)
          .timeout(const Duration(seconds: 10));

      expect(exitCode, isNotNull);
      expect(session.state, PtySessionState.closed);
    },
    skip: !_isDesktopHost ? 'Desktop native PTY only.' : false,
  );

  test('pty manager classifies unsupported sessions structurally', () async {
    final facts = PtyFacts.windowsX64(supportsConPty: false);
    final manager = UnsupportedPtyManager(facts: facts);
    final session = await manager.start(
      const PtySessionRequest(executablePath: 'powershell.exe'),
    );

    expect(
      manager.failureForSession(session)?.kind,
      PtyFailureKind.unsupported,
    );
    expect(
      manager
          .failureForResize(
            await session.resize(rows: 40, cols: 120),
            target: session.id,
          )
          ?.kind,
      PtyFailureKind.resizeUnsupported,
    );
  });
}

bool get _isDesktopHost =>
    Platform.isWindows || Platform.isLinux || Platform.isMacOS;

PtySessionRequest _ttyProbeRequest() {
  if (Platform.isWindows) {
    return const PtySessionRequest(
      executablePath: 'powershell.exe',
      arguments: <String>['-NoLogo', '-NoProfile'],
    );
  }
  return const PtySessionRequest(
    executablePath: '/bin/sh',
    arguments: <String>['-c', 'test -t 1 && printf tty-ok || printf no-tty'],
  );
}

String _ttyProbeCommand() {
  if (Platform.isWindows) {
    return "if ([Console]::IsOutputRedirected) { 'no-tty' } else { 'tty-ok' }; exit 0\r\n";
  }
  return 'test -t 1 && printf tty-ok || printf no-tty; exit 0\r';
}

PtySessionRequest _resizeProbeRequest() {
  if (Platform.isWindows) {
    return const PtySessionRequest(
      executablePath: 'powershell.exe',
      arguments: <String>[
        '-NoLogo',
        '-NoProfile',
        '-Command',
        r"for ($i = 0; $i -lt 100; $i++) { $s = [Console]::WindowWidth.ToString() + 'x' + [Console]::WindowHeight.ToString(); if ($s -eq '120x40') { $s; exit 0 }; Start-Sleep -Milliseconds 25 }; $s; exit 1",
      ],
    );
  }
  return const PtySessionRequest(
    executablePath: '/bin/sh',
    arguments: <String>[
      '-c',
      r'''for i in `seq 1 100`; do s=`stty size`; [ "$s" = '40 120' ] && { printf 120x40; exit 0; }; sleep .025; done; exit 1''',
    ],
  );
}

PtySessionRequest _longRunningRequest() {
  if (Platform.isWindows) {
    return const PtySessionRequest(
      executablePath: 'powershell.exe',
      arguments: <String>[
        '-NoLogo',
        '-NoProfile',
        '-Command',
        'Start-Sleep 30',
      ],
    );
  }
  return const PtySessionRequest(
    executablePath: '/bin/sh',
    arguments: <String>['-c', 'sleep 30'],
  );
}
