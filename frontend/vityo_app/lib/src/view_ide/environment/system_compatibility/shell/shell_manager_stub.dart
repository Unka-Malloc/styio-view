// ignore_for_file: use_super_parameters

import '../platform_context/platform_context.dart';
import 'shell_adapter.dart';
import 'shell_facts.dart';
import 'shell_manager.dart';
import 'shell_prober.dart';

Future<ShellManager> createPlatformShellManager({
  ShellProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  if (platformContext != null) {
    return UnsupportedShellManager(facts: platformContext.shell);
  }
  final facts = prober == null
      ? ShellFacts(
          targetId: 'unsupported',
          operatingSystem: 'unknown',
          distributionId: 'unknown',
          distributionName: 'Unknown',
          architecture: 'unknown',
          providerKind: ShellProviderKind.unknown,
          availableShells: const <ShellExecutableFact>[],
          defaultShellPath: null,
          supportsPty: false,
          supportsLoginShell: false,
          supportsInteractiveShell: false,
          scriptExtension: '.sh',
          detectedAt: DateTime.now().toUtc(),
        )
      : await prober.probe();
  return UnsupportedShellManager(facts: facts);
}

class LocalShellManager extends UnsupportedShellManager {
  LocalShellManager({required ShellFacts facts, ShellAdapter? adapter})
    : super(facts: facts);

  factory LocalShellManager.linuxDebianArmForTest({
    String shellPath = '/bin/sh',
  }) {
    return LocalShellManager(
      facts: ShellFacts.linuxDebianArm(defaultShellPath: shellPath),
    );
  }
}
