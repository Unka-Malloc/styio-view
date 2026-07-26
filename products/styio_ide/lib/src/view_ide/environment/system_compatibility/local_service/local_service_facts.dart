enum LocalServiceProviderKind { loopback, hosted, unsupported }

extension LocalServiceProviderKindX on LocalServiceProviderKind {
  String get wireValue => switch (this) {
    LocalServiceProviderKind.loopback => 'loopback',
    LocalServiceProviderKind.hosted => 'hosted',
    LocalServiceProviderKind.unsupported => 'unsupported',
  };
}

class LocalServiceFacts {
  const LocalServiceFacts({required this.targetId, required this.operatingSystem, required this.distributionId, required this.architecture, required this.providerKind, required this.supportsLoopbackHttpServer, required this.supportsEphemeralPort, this.detectedAt});
  factory LocalServiceFacts.linuxDebianArm({String targetId = 'local', String architecture = 'aarch64', DateTime? detectedAt}) => LocalServiceFacts(targetId: targetId, operatingSystem: 'linux', distributionId: 'debian', architecture: architecture, providerKind: LocalServiceProviderKind.loopback, supportsLoopbackHttpServer: true, supportsEphemeralPort: true, detectedAt: detectedAt);
  final String targetId;
  final String operatingSystem;
  final String distributionId;
  final String architecture;
  final LocalServiceProviderKind providerKind;
  final bool supportsLoopbackHttpServer;
  final bool supportsEphemeralPort;
  final DateTime? detectedAt;
  bool get supportsLinuxDebianArmTarget => operatingSystem == 'linux' && (distributionId == 'debian' || distributionId == 'raspbian') && (architecture == 'aarch64' || architecture == 'arm64' || architecture.startsWith('armv') || architecture == 'arm');
  String get compatibilityTarget => supportsLinuxDebianArmTarget ? 'linux-debian-arm' : operatingSystem == 'linux' ? 'linux-generic' : operatingSystem == 'windows' ? 'windows-generic' : 'unsupported';
}
