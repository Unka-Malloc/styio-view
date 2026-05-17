import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/shell_runtime.dart';

void main() {
  test('shell prober classifies linux debian arm target facts', () async {
    final prober = LocalShellProber(
      operatingSystem: 'linux',
      environment: const <String, String>{'SHELL': '/bin/bash'},
      architectureReader: () async => 'aarch64',
      osReleaseReader: () async => const <String, String>{
        'ID': 'debian',
        'PRETTY_NAME': 'Debian GNU/Linux 12 (bookworm)',
      },
      executableExists: (path) async => path == '/bin/bash' || path == '/bin/sh',
      clock: () => DateTime.utc(2026, 5, 16),
    );

    final facts = await prober.probe();

    expect(facts.supportsLinuxDebianArmTarget, isTrue);
    expect(facts.compatibilityTarget, 'linux-debian-arm');
    expect(facts.defaultShellPath, '/bin/bash');
    expect(facts.availableShells.map((shell) => shell.path), contains('/bin/bash'));
    expect(facts.entries['shell.availableShells']?.value, isA<List<Object?>>());
  });

  test('local shell prober recognizes this host when it is debian arm', () async {
    final facts = await const LocalShellProber().probe();
    final machine = await Process.run('uname', const <String>['-m']);
    final osRelease = await File('/etc/os-release').readAsString();
    final isDebianArmHost =
        Platform.isLinux &&
        osRelease.contains('ID=debian') &&
        machine.stdout.toString().trim().toLowerCase() == 'aarch64';

    if (isDebianArmHost) {
      expect(facts.supportsLinuxDebianArmTarget, isTrue);
      expect(facts.compatibilityTarget, 'linux-debian-arm');
      expect(facts.availableShells, isNotEmpty);
    }
  });

  test('shell configuration selects default profile from facts', () {
    final facts = ShellFacts.linuxDebianArm(
      defaultShellPath: '/bin/bash',
      availableShells: const <ShellExecutableFact>[
        ShellExecutableFact(
          path: '/bin/bash',
          family: ShellFamily.bash,
          isDefault: true,
        ),
      ],
    );

    final configuration = ShellConfiguration.fromFacts(facts);

    expect(configuration.defaultProfile?.executablePath, '/bin/bash');
    expect(configuration.defaultProfile?.family, ShellFamily.bash);
  });

  test('shell adapter creates bash execution plan', () {
    final facts = ShellFacts.linuxDebianArm(
      defaultShellPath: '/bin/bash',
      availableShells: const <ShellExecutableFact>[
        ShellExecutableFact(
          path: '/bin/bash',
          family: ShellFamily.bash,
          isDefault: true,
        ),
      ],
    );
    final adapter = ShellAdapter(facts);
    final plan = adapter.plan(
      const ShellCommandRequest(
        command: 'printf',
        arguments: <String>['hello shell'],
      ),
    );

    expect(adapter.adapt().isLinuxDebianArm, isTrue);
    expect(plan.executablePath, '/bin/bash');
    expect(plan.arguments.first, '-c');
    expect(plan.arguments.last, "printf 'hello shell'");
  });

  test('local shell manager executes command through shell adapter', () async {
    final manager = LocalShellManager.linuxDebianArmForTest(shellPath: '/bin/sh');

    final result = await manager.run(
      const ShellCommandRequest(command: 'printf vityo-shell'),
    );

    expect(result.succeeded, isTrue);
    expect(result.stdout, 'vityo-shell');
    expect(result.executablePath, '/bin/sh');
  });

  test('shell manager classifies command failures structurally', () async {
    final manager = LocalShellManager.linuxDebianArmForTest(shellPath: '/bin/sh');
    const failed = ShellCommandResult(
      status: ShellCommandStatus.failed,
      command: 'bad-command',
      executablePath: '/bin/sh',
      arguments: <String>['-c', 'bad-command'],
      exitCode: 127,
      stdout: '',
      stderr: 'not found',
      duration: Duration(milliseconds: 2),
    );
    final nonZeroFailure = manager.failureFor(
      failed,
      operation: 'toolchain.shell',
    );
    final blockedResult = await UnsupportedShellManager(
      facts: ShellFacts.linuxDebianArm(defaultShellPath: '/bin/sh'),
    ).run(const ShellCommandRequest(command: 'printf ok'));
    final blockedFailure = UnsupportedShellManager(
      facts: ShellFacts.linuxDebianArm(defaultShellPath: '/bin/sh'),
    ).failureFor(blockedResult);

    expect(nonZeroFailure, isNotNull);
    expect(nonZeroFailure!.kind, ShellFailureKind.nonZeroExit);
    expect(nonZeroFailure.sourceManager, 'LocalShellManager');
    expect(nonZeroFailure.toJson()['operation'], 'toolchain.shell');
    expect(blockedFailure!.kind, ShellFailureKind.unsupported);
    expect(blockedFailure.sourceManager, 'UnsupportedShellManager');
  });

  test('toolchain shell runtime provides upper-level shell abstraction', () async {
    final runtime = ToolchainShellRuntime(
      shellManager: LocalShellManager.linuxDebianArmForTest(shellPath: '/bin/sh'),
      configuration: ShellConfiguration.fromFacts(
        ShellFacts.linuxDebianArm(defaultShellPath: '/bin/sh'),
      ),
    );

    final result = await runtime.run(
      'printf',
      arguments: const <String>['runtime-ok'],
    );

    expect(runtime.compatibility.isLinuxDebianArm, isTrue);
    expect(result.succeeded, isTrue);
    expect(result.stdout, 'runtime-ok');
  });
}
