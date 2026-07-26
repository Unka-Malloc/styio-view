import 'dart:async';

import 'network_facts.dart';
import 'network_prober.dart';

class UnsupportedNetworkProber implements NetworkProber {
  const UnsupportedNetworkProber();
  @override
  Future<NetworkFacts> probe() async => NetworkFacts(
    targetId: 'unsupported',
    operatingSystem: 'unknown',
    distributionId: 'unknown',
    architecture: 'unknown',
    providerKind: NetworkProviderKind.unknown,
    supportsHttpClient: false,
    supportsLoopback: false,
    proxyEnvironment: const <String, String>{},
    detectedAt: DateTime.now().toUtc(),
  );
}

class LocalNetworkProber extends UnsupportedNetworkProber {
  const LocalNetworkProber({
    String targetId = 'local',
    String? operatingSystem,
    Map<String, String>? environment,
    Future<String?> Function()? architectureReader,
    Future<Map<String, String>> Function()? osReleaseReader,
    DateTime Function()? clock,
  });
}
