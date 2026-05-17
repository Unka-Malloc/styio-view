// ignore_for_file: use_super_parameters

import 'dart:async';

import 'shell_facts.dart';
import 'shell_prober.dart';

class UnsupportedShellProber implements ShellProber {
  const UnsupportedShellProber({this.targetId = 'unsupported'});

  final String targetId;

  @override
  Future<ShellFacts> probe() async {
    return ShellFacts(
      targetId: targetId,
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
    );
  }
}

class LocalShellProber extends UnsupportedShellProber {
  const LocalShellProber({
    String targetId = 'local',
    String? operatingSystem,
    Map<String, String>? environment,
    Future<String?> Function()? architectureReader,
    Future<Map<String, String>> Function()? osReleaseReader,
    Future<bool> Function(String path)? executableExists,
    DateTime Function()? clock,
  }) : super(targetId: targetId);
}
