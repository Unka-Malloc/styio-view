import 'dart:async';
import 'dart:io';

import '../host_platform_io.dart';
import 'local_service_facts.dart';
import 'local_service_prober.dart';

class LocalLoopbackServiceProber implements LocalServiceProber {
  const LocalLoopbackServiceProber({
    this.targetId = 'local',
    this.operatingSystem,
    this.environment,
    this.architectureReader,
    this.osReleaseReader,
    this.clock,
  });

  final String targetId;
  final String? operatingSystem;
  final Map<String, String>? environment;
  final Future<String?> Function()? architectureReader;
  final Future<Map<String, String>> Function()? osReleaseReader;
  final DateTime Function()? clock;

  @override
  Future<LocalServiceFacts> probe() async {
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
    return LocalServiceFacts(
      targetId: targetId,
      operatingSystem: os,
      distributionId: release['ID']?.toLowerCase() ?? 'unknown',
      architecture: architecture,
      providerKind: LocalServiceProviderKind.loopback,
      supportsLoopbackHttpServer: true,
      supportsEphemeralPort: true,
      detectedAt: (clock ?? DateTime.now)().toUtc(),
    );
  }
}
