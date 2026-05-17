// ignore_for_file: use_super_parameters

import 'dart:async';

import 'pty_facts.dart';
import 'pty_prober.dart';

class UnsupportedPtyProber implements PtyProber {
  const UnsupportedPtyProber({this.targetId = 'unsupported'});

  final String targetId;

  @override
  Future<PtyFacts> probe() async {
    return PtyFacts(
      targetId: targetId,
      operatingSystem: 'unknown',
      distributionId: 'unknown',
      distributionName: 'Unknown',
      architecture: 'unknown',
      providerKind: PtyProviderKind.unsupported,
      supportsPty: false,
      supportsResize: false,
      supportsRawMode: false,
      supportsSignals: false,
      supportsProcessGroup: false,
      supportsConPty: false,
      supportsForkPty: false,
      supportsScriptUtility: false,
      detectedAt: DateTime.now().toUtc(),
    );
  }
}

class LocalPtyProber extends UnsupportedPtyProber {
  const LocalPtyProber({
    String targetId = 'local',
    String? operatingSystem,
    Future<String?> Function()? architectureReader,
    Future<Map<String, String>> Function()? osReleaseReader,
    Future<String?> Function()? scriptPathReader,
    DateTime Function()? clock,
  }) : super(targetId: targetId);
}
