// ignore_for_file: use_super_parameters

import 'dart:async';

import 'process_facts.dart';
import 'process_prober.dart';

class UnsupportedProcessProber implements ProcessProber {
  const UnsupportedProcessProber({this.targetId = 'unsupported'});
  final String targetId;
  @override
  Future<ProcessFacts> probe() async => ProcessFacts(
    targetId: targetId,
    operatingSystem: 'unknown',
    distributionId: 'unknown',
    distributionName: 'Unknown',
    architecture: 'unknown',
    providerKind: ProcessProviderKind.unknown,
    supportsSpawn: false,
    supportsSignals: false,
    supportsProcessGroups: false,
    supportsEnvironmentOverlay: false,
    supportsWorkingDirectory: false,
    detectedAt: DateTime.now().toUtc(),
  );
}

class LocalProcessProber extends UnsupportedProcessProber {
  const LocalProcessProber({
    String targetId = 'local',
    String? operatingSystem,
    Future<String?> Function()? architectureReader,
    Future<Map<String, String>> Function()? osReleaseReader,
    DateTime Function()? clock,
  }) : super(targetId: targetId);
}
