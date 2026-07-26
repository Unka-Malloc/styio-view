enum NetworkProviderKind { local, hosted, virtual, unknown }

extension NetworkProviderKindX on NetworkProviderKind {
  String get wireValue => switch (this) {
    NetworkProviderKind.local => 'local',
    NetworkProviderKind.hosted => 'hosted',
    NetworkProviderKind.virtual => 'virtual',
    NetworkProviderKind.unknown => 'unknown',
  };
}

class NetworkFacts {
  const NetworkFacts({
    required this.targetId,
    required this.operatingSystem,
    required this.distributionId,
    required this.architecture,
    required this.providerKind,
    required this.supportsHttpClient,
    required this.supportsLoopback,
    required this.proxyEnvironment,
    this.detectedAt,
  });

  factory NetworkFacts.linuxDebianArm({
    String targetId = 'local',
    String architecture = 'aarch64',
    Map<String, String> proxyEnvironment = const <String, String>{},
    DateTime? detectedAt,
  }) => NetworkFacts(
    targetId: targetId,
    operatingSystem: 'linux',
    distributionId: 'debian',
    architecture: architecture,
    providerKind: NetworkProviderKind.local,
    supportsHttpClient: true,
    supportsLoopback: true,
    proxyEnvironment: proxyEnvironment,
    detectedAt: detectedAt,
  );

  factory NetworkFacts.webHosted({
    String targetId = 'web',
    DateTime? detectedAt,
  }) => NetworkFacts(
    targetId: targetId,
    operatingSystem: 'web',
    distributionId: 'browser',
    architecture: 'wasm-js',
    providerKind: NetworkProviderKind.hosted,
    supportsHttpClient: true,
    supportsLoopback: false,
    proxyEnvironment: const <String, String>{},
    detectedAt: detectedAt,
  );

  final String targetId;
  final String operatingSystem;
  final String distributionId;
  final String architecture;
  final NetworkProviderKind providerKind;
  final bool supportsHttpClient;
  final bool supportsLoopback;
  final Map<String, String> proxyEnvironment;
  final DateTime? detectedAt;

  bool get supportsLinuxDebianArmTarget => operatingSystem == 'linux' && (distributionId == 'debian' || distributionId == 'raspbian') && (architecture == 'aarch64' || architecture == 'arm64' || architecture.startsWith('armv') || architecture == 'arm');
  String get compatibilityTarget => operatingSystem == 'web'
      ? 'web-hosted'
      : supportsLinuxDebianArmTarget
      ? 'linux-debian-arm'
      : operatingSystem == 'linux'
      ? 'linux-generic'
      : operatingSystem == 'windows'
      ? 'windows-generic'
      : 'unsupported';
}
