import 'network_facts.dart';

class NetworkAdapter {
  const NetworkAdapter(this.facts);
  final NetworkFacts facts;
  NetworkCompatibility adapt() => NetworkCompatibility(
    targetId: facts.targetId,
    compatibilityTarget: facts.compatibilityTarget,
    supportsHttpClient: facts.supportsHttpClient,
    supportsLoopback: facts.supportsLoopback,
    proxyEnvironment: facts.proxyEnvironment,
  );
}

class NetworkCompatibility {
  const NetworkCompatibility({required this.targetId, required this.compatibilityTarget, required this.supportsHttpClient, required this.supportsLoopback, required this.proxyEnvironment});
  final String targetId;
  final String compatibilityTarget;
  final bool supportsHttpClient;
  final bool supportsLoopback;
  final Map<String, String> proxyEnvironment;
  bool get isLinuxDebianArm => compatibilityTarget == 'linux-debian-arm';
}
