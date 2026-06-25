import 'dart:async';

import '../host_platform_io.dart';
import 'process_facts.dart';
import 'process_prober.dart';

class LocalProcessProber implements ProcessProber {
  const LocalProcessProber({
    this.targetId = 'local',
    this.operatingSystem,
    this.architectureReader,
    this.osReleaseReader,
    this.clock,
  });

  final String targetId;
  final String? operatingSystem;
  final Future<String?> Function()? architectureReader;
  final Future<Map<String, String>> Function()? osReleaseReader;
  final DateTime Function()? clock;

  @override
  Future<ProcessFacts> probe() async {
    final detectedAt = (clock ?? DateTime.now)().toUtc();
    final os = localOperatingSystem(operatingSystem);
    final release = await readHostOsRelease(
      operatingSystem: operatingSystem,
      osReleaseReader: osReleaseReader,
    );
    final architecture =
        (await readHostArchitecture(
          operatingSystem: operatingSystem,
          architectureReader: architectureReader,
        )) ??
        'unknown';
    final distributionId = release['ID']?.toLowerCase() ?? 'unknown';
    final distributionName = release['PRETTY_NAME'] ?? distributionId;
    final supportsSpawn = os == 'linux' || os == 'macos' || os == 'windows';
    return ProcessFacts(
      targetId: targetId,
      operatingSystem: os,
      distributionId: distributionId,
      distributionName: distributionName,
      architecture: architecture,
      providerKind: ProcessProviderKind.local,
      supportsSpawn: supportsSpawn,
      supportsSignals: os == 'linux' || os == 'macos',
      supportsProcessGroups: os == 'linux' || os == 'macos',
      supportsEnvironmentOverlay: supportsSpawn,
      supportsWorkingDirectory: supportsSpawn,
      detectedAt: detectedAt,
      entries: ProcessFacts.buildEntries(
        targetId: targetId,
        operatingSystem: os,
        distributionId: distributionId,
        distributionName: distributionName,
        architecture: architecture,
        providerKind: ProcessProviderKind.local,
        supportsSpawn: supportsSpawn,
        supportsSignals: os == 'linux' || os == 'macos',
        supportsProcessGroups: os == 'linux' || os == 'macos',
        supportsEnvironmentOverlay: supportsSpawn,
        supportsWorkingDirectory: supportsSpawn,
        source: 'prober',
        detectedAt: detectedAt,
      ),
    );
  }

}
