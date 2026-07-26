enum ResourceProviderKind { local, hosted, virtual, unknown }

extension ResourceProviderKindX on ResourceProviderKind {
  String get wireValue => switch (this) {
    ResourceProviderKind.local => 'local',
    ResourceProviderKind.hosted => 'hosted',
    ResourceProviderKind.virtual => 'virtual',
    ResourceProviderKind.unknown => 'unknown',
  };
}

class ResourceFacts {
  const ResourceFacts({
    required this.targetId,
    required this.operatingSystem,
    required this.distributionId,
    required this.architecture,
    required this.providerKind,
    required this.processorCount,
    required this.systemTempPath,
    required this.supportsTempDirectory,
    required this.supportsHomeDirectory,
    required this.supportsStorageProbe,
    this.homePath,
    this.detectedAt,
  });

  factory ResourceFacts.linuxDebianArm({
    String targetId = 'local',
    String architecture = 'aarch64',
    String systemTempPath = '/tmp',
    String? homePath,
    int processorCount = 1,
    DateTime? detectedAt,
  }) => ResourceFacts(
    targetId: targetId,
    operatingSystem: 'linux',
    distributionId: 'debian',
    architecture: architecture,
    providerKind: ResourceProviderKind.local,
    processorCount: processorCount,
    systemTempPath: systemTempPath,
    homePath: homePath,
    supportsTempDirectory: true,
    supportsHomeDirectory: homePath != null,
    supportsStorageProbe: true,
    detectedAt: detectedAt,
  );

  final String targetId;
  final String operatingSystem;
  final String distributionId;
  final String architecture;
  final ResourceProviderKind providerKind;
  final int processorCount;
  final String systemTempPath;
  final String? homePath;
  final bool supportsTempDirectory;
  final bool supportsHomeDirectory;
  final bool supportsStorageProbe;
  final DateTime? detectedAt;

  bool get supportsLinuxDebianArmTarget =>
      operatingSystem == 'linux' &&
      (distributionId == 'debian' || distributionId == 'raspbian') &&
      (architecture == 'aarch64' || architecture == 'arm64' || architecture.startsWith('armv') || architecture == 'arm');

  String get compatibilityTarget {
    if (supportsLinuxDebianArmTarget) return 'linux-debian-arm';
    if (operatingSystem == 'linux') return 'linux-generic';
    if (operatingSystem == 'windows') {
      final arch = architecture.toLowerCase();
      if (arch == 'amd64' || arch == 'x64' || arch == 'x86_64') return 'windows-x64';
      if (arch == 'arm64' || arch == 'aarch64') return 'windows-arm64';
      return 'windows-generic';
    }
    return 'unsupported';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'targetId': targetId,
    'operatingSystem': operatingSystem,
    'distributionId': distributionId,
    'architecture': architecture,
    'providerKind': providerKind.wireValue,
    'processorCount': processorCount,
    'systemTempPath': systemTempPath,
    if (homePath != null) 'homePath': homePath,
    'supportsTempDirectory': supportsTempDirectory,
    'supportsHomeDirectory': supportsHomeDirectory,
    'supportsStorageProbe': supportsStorageProbe,
    'compatibilityTarget': compatibilityTarget,
    if (detectedAt != null) 'detectedAt': detectedAt!.toIso8601String(),
  };
}
