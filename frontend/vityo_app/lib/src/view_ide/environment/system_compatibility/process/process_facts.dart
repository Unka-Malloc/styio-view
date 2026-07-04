enum ProcessProviderKind { local, hosted, virtual, unknown }

enum ProcessFactCertainty { confirmed, inferred, unknown, unsupported, stale }

extension ProcessProviderKindX on ProcessProviderKind {
  String get wireValue => switch (this) {
    ProcessProviderKind.local => 'local',
    ProcessProviderKind.hosted => 'hosted',
    ProcessProviderKind.virtual => 'virtual',
    ProcessProviderKind.unknown => 'unknown',
  };
}

extension ProcessFactCertaintyX on ProcessFactCertainty {
  String get wireValue => switch (this) {
    ProcessFactCertainty.confirmed => 'confirmed',
    ProcessFactCertainty.inferred => 'inferred',
    ProcessFactCertainty.unknown => 'unknown',
    ProcessFactCertainty.unsupported => 'unsupported',
    ProcessFactCertainty.stale => 'stale',
  };
}

class ProcessContextFact {
  const ProcessContextFact({
    required this.key,
    required this.value,
    required this.source,
    required this.scope,
    required this.certainty,
    this.targetId,
    this.detectedAt,
  });

  final String key;
  final Object? value;
  final String source;
  final String scope;
  final ProcessFactCertainty certainty;
  final String? targetId;
  final DateTime? detectedAt;

  Map<String, Object?> toJson() => <String, Object?>{
    'key': key,
    'value': value,
    'source': source,
    'scope': scope,
    'certainty': certainty.wireValue,
    if (targetId != null) 'targetId': targetId,
    if (detectedAt != null) 'detectedAt': detectedAt!.toIso8601String(),
  };
}

class ProcessFacts {
  const ProcessFacts({
    required this.targetId,
    required this.operatingSystem,
    required this.distributionId,
    required this.distributionName,
    required this.architecture,
    required this.providerKind,
    required this.supportsSpawn,
    required this.supportsSignals,
    required this.supportsProcessGroups,
    required this.supportsEnvironmentOverlay,
    required this.supportsWorkingDirectory,
    this.detectedAt,
    this.entries = const <String, ProcessContextFact>{},
  });

  factory ProcessFacts.linuxDebianArm({
    String targetId = 'local',
    String architecture = 'aarch64',
    DateTime? detectedAt,
  }) {
    return ProcessFacts(
      targetId: targetId,
      operatingSystem: 'linux',
      distributionId: 'debian',
      distributionName: 'Debian GNU/Linux',
      architecture: architecture,
      providerKind: ProcessProviderKind.local,
      supportsSpawn: true,
      supportsSignals: true,
      supportsProcessGroups: true,
      supportsEnvironmentOverlay: true,
      supportsWorkingDirectory: true,
      detectedAt: detectedAt,
      entries: buildEntries(
        targetId: targetId,
        operatingSystem: 'linux',
        distributionId: 'debian',
        distributionName: 'Debian GNU/Linux',
        architecture: architecture,
        providerKind: ProcessProviderKind.local,
        supportsSpawn: true,
        supportsSignals: true,
        supportsProcessGroups: true,
        supportsEnvironmentOverlay: true,
        supportsWorkingDirectory: true,
        source: 'fixture',
        detectedAt: detectedAt,
      ),
    );
  }

  factory ProcessFacts.windowsX64({
    String targetId = 'local',
    String architecture = 'x64',
    DateTime? detectedAt,
  }) {
    return ProcessFacts(
      targetId: targetId,
      operatingSystem: 'windows',
      distributionId: 'windows',
      distributionName: 'Windows',
      architecture: architecture,
      providerKind: ProcessProviderKind.local,
      supportsSpawn: true,
      supportsSignals: false,
      supportsProcessGroups: false,
      supportsEnvironmentOverlay: true,
      supportsWorkingDirectory: true,
      detectedAt: detectedAt,
      entries: buildEntries(
        targetId: targetId,
        operatingSystem: 'windows',
        distributionId: 'windows',
        distributionName: 'Windows',
        architecture: architecture,
        providerKind: ProcessProviderKind.local,
        supportsSpawn: true,
        supportsSignals: false,
        supportsProcessGroups: false,
        supportsEnvironmentOverlay: true,
        supportsWorkingDirectory: true,
        source: 'fixture',
        detectedAt: detectedAt,
      ),
    );
  }

  final String targetId;
  final String operatingSystem;
  final String distributionId;
  final String distributionName;
  final String architecture;
  final ProcessProviderKind providerKind;
  final bool supportsSpawn;
  final bool supportsSignals;
  final bool supportsProcessGroups;
  final bool supportsEnvironmentOverlay;
  final bool supportsWorkingDirectory;
  final DateTime? detectedAt;
  final Map<String, ProcessContextFact> entries;

  bool get supportsLinuxDebianArmTarget =>
      operatingSystem == 'linux' &&
      (distributionId == 'debian' || distributionId == 'raspbian') &&
      (architecture == 'aarch64' ||
          architecture == 'arm64' ||
          architecture.startsWith('armv') ||
          architecture == 'arm');

  String get compatibilityTarget {
    if (supportsLinuxDebianArmTarget) return 'linux-debian-arm';
    if (operatingSystem == 'linux') return 'linux-generic';
    if (operatingSystem == 'windows') {
      final arch = architecture.toLowerCase();
      if (arch == 'amd64' || arch == 'x64' || arch == 'x86_64') {
        return 'windows-x64';
      }
      if (arch == 'arm64' || arch == 'aarch64') return 'windows-arm64';
      return 'windows-generic';
    }
    return 'unsupported';
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'targetId': targetId,
    'operatingSystem': operatingSystem,
    'distributionId': distributionId,
    'distributionName': distributionName,
    'architecture': architecture,
    'providerKind': providerKind.wireValue,
    'supportsSpawn': supportsSpawn,
    'supportsSignals': supportsSignals,
    'supportsProcessGroups': supportsProcessGroups,
    'supportsEnvironmentOverlay': supportsEnvironmentOverlay,
    'supportsWorkingDirectory': supportsWorkingDirectory,
    'compatibilityTarget': compatibilityTarget,
    if (detectedAt != null) 'detectedAt': detectedAt!.toIso8601String(),
    'entries': entries.map(
      (key, value) => MapEntry<String, Object?>(key, value.toJson()),
    ),
  };

  static Map<String, ProcessContextFact> buildEntries({
    required String targetId,
    required String operatingSystem,
    required String distributionId,
    required String distributionName,
    required String architecture,
    required ProcessProviderKind providerKind,
    required bool supportsSpawn,
    required bool supportsSignals,
    required bool supportsProcessGroups,
    required bool supportsEnvironmentOverlay,
    required bool supportsWorkingDirectory,
    required String source,
    DateTime? detectedAt,
  }) {
    ProcessContextFact fact(String key, Object? value) => ProcessContextFact(
      key: key,
      value: value,
      source: source,
      scope: 'process',
      certainty: ProcessFactCertainty.confirmed,
      targetId: targetId,
      detectedAt: detectedAt,
    );
    return <String, ProcessContextFact>{
      'host.operatingSystem': fact('host.operatingSystem', operatingSystem),
      'host.distributionId': fact('host.distributionId', distributionId),
      'host.architecture': fact('host.architecture', architecture),
      'process.providerKind': fact(
        'process.providerKind',
        providerKind.wireValue,
      ),
      'process.spawnSupported': fact('process.spawnSupported', supportsSpawn),
      'process.signalsSupported': fact(
        'process.signalsSupported',
        supportsSignals,
      ),
      'process.processGroupsSupported': fact(
        'process.processGroupsSupported',
        supportsProcessGroups,
      ),
      'process.environmentOverlaySupported': fact(
        'process.environmentOverlaySupported',
        supportsEnvironmentOverlay,
      ),
      'process.workingDirectorySupported': fact(
        'process.workingDirectorySupported',
        supportsWorkingDirectory,
      ),
    };
  }
}
