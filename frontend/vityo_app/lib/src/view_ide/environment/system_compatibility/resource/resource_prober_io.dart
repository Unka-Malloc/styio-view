import 'dart:async';
import 'dart:io';

import '../host_platform_io.dart';
import 'resource_facts.dart';
import 'resource_prober.dart';

class LocalResourceProber implements ResourceProber {
  const LocalResourceProber({
    this.targetId = 'local',
    this.operatingSystem,
    this.architectureReader,
    this.osReleaseReader,
    this.environment,
    this.clock,
  });

  final String targetId;
  final String? operatingSystem;
  final Future<String?> Function()? architectureReader;
  final Future<Map<String, String>> Function()? osReleaseReader;
  final Map<String, String>? environment;
  final DateTime Function()? clock;

  @override
  Future<ResourceFacts> probe() async {
    final detectedAt = (clock ?? DateTime.now)().toUtc();
    final env = environment ?? Platform.environment;
    final os = localOperatingSystem(operatingSystem);
    final release = await readHostOsRelease(
      operatingSystem: operatingSystem,
      osReleaseReader: osReleaseReader,
    );
    final architecture =
        (await readHostArchitecture(
          operatingSystem: operatingSystem,
          architectureReader: architectureReader,
          environment: env,
        )) ??
        'unknown';
    return ResourceFacts(
      targetId: targetId,
      operatingSystem: os,
      distributionId: release['ID']?.toLowerCase() ?? 'unknown',
      architecture: architecture,
      providerKind: ResourceProviderKind.local,
      processorCount: Platform.numberOfProcessors,
      systemTempPath: Directory.systemTemp.path,
      homePath: env['HOME'] ?? env['USERPROFILE'],
      supportsTempDirectory: true,
      supportsHomeDirectory: (env['HOME'] ?? env['USERPROFILE']) != null,
      supportsStorageProbe: true,
      detectedAt: detectedAt,
    );
  }

}
