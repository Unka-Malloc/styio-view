import 'dart:async';
import 'dart:io';

import '../host_platform_io.dart';
import 'network_facts.dart';
import 'network_prober.dart';

class LocalNetworkProber implements NetworkProber {
  const LocalNetworkProber({
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
  Future<NetworkFacts> probe() async {
    final env = environment ?? Platform.environment;
    final os = localOperatingSystem(operatingSystem);
    final release = await readHostOsRelease(
      operatingSystem: operatingSystem,
      osReleaseReader: osReleaseReader,
    );
    final proxy = <String, String>{};
    for (final key in const <String>[
      'HTTP_PROXY',
      'HTTPS_PROXY',
      'NO_PROXY',
      'http_proxy',
      'https_proxy',
      'no_proxy',
    ]) {
      final value = env[key];
      if (value != null && value.isNotEmpty) {
        proxy[key] = value;
      }
    }
    final architecture =
        (await readHostArchitecture(
          operatingSystem: operatingSystem,
          architectureReader: architectureReader,
          environment: env,
        )) ??
        'unknown';
    return NetworkFacts(
      targetId: targetId,
      operatingSystem: os,
      distributionId: release['ID']?.toLowerCase() ?? 'unknown',
      architecture: architecture,
      providerKind: NetworkProviderKind.local,
      supportsHttpClient: true,
      supportsLoopback: true,
      proxyEnvironment: proxy,
      detectedAt: (clock ?? DateTime.now)().toUtc(),
    );
  }
}
