enum PtyProviderKind { posixPty, conPty, hosted, unsupported, unknown }

enum PtyFactCertainty { confirmed, inferred, unknown, unsupported, stale }

extension PtyProviderKindX on PtyProviderKind {
  String get wireValue => switch (this) {
    PtyProviderKind.posixPty => 'posix-pty',
    PtyProviderKind.conPty => 'conpty',
    PtyProviderKind.hosted => 'hosted',
    PtyProviderKind.unsupported => 'unsupported',
    PtyProviderKind.unknown => 'unknown',
  };
}

extension PtyFactCertaintyX on PtyFactCertainty {
  String get wireValue => switch (this) {
    PtyFactCertainty.confirmed => 'confirmed',
    PtyFactCertainty.inferred => 'inferred',
    PtyFactCertainty.unknown => 'unknown',
    PtyFactCertainty.unsupported => 'unsupported',
    PtyFactCertainty.stale => 'stale',
  };
}

class PtyContextFact {
  const PtyContextFact({
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
  final PtyFactCertainty certainty;
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

class PtyFacts {
  const PtyFacts({
    required this.targetId,
    required this.operatingSystem,
    required this.distributionId,
    required this.distributionName,
    required this.architecture,
    required this.providerKind,
    required this.supportsPty,
    required this.supportsResize,
    required this.supportsRawMode,
    required this.supportsSignals,
    required this.supportsProcessGroup,
    required this.supportsConPty,
    required this.supportsForkPty,
    this.detectedAt,
    this.entries = const <String, PtyContextFact>{},
  });

  factory PtyFacts.linuxDebianArm({
    String targetId = 'local',
    String architecture = 'aarch64',
    DateTime? detectedAt,
  }) => PtyFacts.native(
    targetId: targetId,
    operatingSystem: 'linux',
    distributionId: 'debian',
    distributionName: 'Debian GNU/Linux',
    architecture: architecture,
    detectedAt: detectedAt,
    source: 'fixture',
  );

  factory PtyFacts.windowsX64({
    String targetId = 'local',
    String architecture = 'x64',
    bool supportsConPty = true,
    DateTime? detectedAt,
  }) => PtyFacts.native(
    targetId: targetId,
    operatingSystem: 'windows',
    distributionId: 'windows',
    distributionName: 'Windows',
    architecture: architecture,
    available: supportsConPty,
    detectedAt: detectedAt,
    source: 'fixture',
  );

  factory PtyFacts.native({
    required String targetId,
    required String operatingSystem,
    required String distributionId,
    required String distributionName,
    required String architecture,
    bool available = true,
    DateTime? detectedAt,
    String source = 'prober',
  }) {
    final isWindows = operatingSystem == 'windows';
    final isPosixDesktop =
        operatingSystem == 'linux' || operatingSystem == 'macos';
    final supported = available && (isWindows || isPosixDesktop);
    final providerKind = !supported
        ? PtyProviderKind.unsupported
        : isWindows
        ? PtyProviderKind.conPty
        : PtyProviderKind.posixPty;
    return PtyFacts(
      targetId: targetId,
      operatingSystem: operatingSystem,
      distributionId: distributionId,
      distributionName: distributionName,
      architecture: architecture,
      providerKind: providerKind,
      supportsPty: supported,
      supportsResize: supported,
      supportsRawMode: supported,
      supportsSignals: supported,
      supportsProcessGroup: isPosixDesktop && supported,
      supportsConPty: isWindows && supported,
      supportsForkPty: isPosixDesktop && supported,
      detectedAt: detectedAt,
      entries: buildEntries(
        targetId: targetId,
        operatingSystem: operatingSystem,
        distributionId: distributionId,
        distributionName: distributionName,
        architecture: architecture,
        providerKind: providerKind,
        supportsPty: supported,
        supportsResize: supported,
        supportsRawMode: supported,
        supportsSignals: supported,
        supportsProcessGroup: isPosixDesktop && supported,
        supportsConPty: isWindows && supported,
        supportsForkPty: isPosixDesktop && supported,
        source: source,
        detectedAt: detectedAt,
      ),
    );
  }

  final String targetId;
  final String operatingSystem;
  final String distributionId;
  final String distributionName;
  final String architecture;
  final PtyProviderKind providerKind;
  final bool supportsPty;
  final bool supportsResize;
  final bool supportsRawMode;
  final bool supportsSignals;
  final bool supportsProcessGroup;
  final bool supportsConPty;
  final bool supportsForkPty;
  final DateTime? detectedAt;
  final Map<String, PtyContextFact> entries;

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
    if (operatingSystem == 'macos') return 'macos';
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
    'supportsPty': supportsPty,
    'supportsResize': supportsResize,
    'supportsRawMode': supportsRawMode,
    'supportsSignals': supportsSignals,
    'supportsProcessGroup': supportsProcessGroup,
    'supportsConPty': supportsConPty,
    'supportsForkPty': supportsForkPty,
    'compatibilityTarget': compatibilityTarget,
    if (detectedAt != null) 'detectedAt': detectedAt!.toIso8601String(),
    'entries': entries.map(
      (key, value) => MapEntry<String, Object?>(key, value.toJson()),
    ),
  };

  static Map<String, PtyContextFact> buildEntries({
    required String targetId,
    required String operatingSystem,
    required String distributionId,
    required String distributionName,
    required String architecture,
    required PtyProviderKind providerKind,
    required bool supportsPty,
    required bool supportsResize,
    required bool supportsRawMode,
    required bool supportsSignals,
    required bool supportsProcessGroup,
    required bool supportsConPty,
    required bool supportsForkPty,
    required String source,
    DateTime? detectedAt,
  }) {
    PtyContextFact fact(String key, Object? value) => PtyContextFact(
      key: key,
      value: value,
      source: source,
      scope: 'pty',
      certainty: supportsPty
          ? PtyFactCertainty.confirmed
          : PtyFactCertainty.unsupported,
      targetId: targetId,
      detectedAt: detectedAt,
    );

    return <String, PtyContextFact>{
      'host.operatingSystem': fact('host.operatingSystem', operatingSystem),
      'host.distributionId': fact('host.distributionId', distributionId),
      'host.distributionName': fact('host.distributionName', distributionName),
      'host.architecture': fact('host.architecture', architecture),
      'pty.providerKind': fact('pty.providerKind', providerKind.wireValue),
      'pty.supported': fact('pty.supported', supportsPty),
      'pty.resizeSupported': fact('pty.resizeSupported', supportsResize),
      'pty.rawModeSupported': fact('pty.rawModeSupported', supportsRawMode),
      'pty.signalsSupported': fact('pty.signalsSupported', supportsSignals),
      'pty.processGroupSupported': fact(
        'pty.processGroupSupported',
        supportsProcessGroup,
      ),
      'pty.conPtySupported': fact('pty.conPtySupported', supportsConPty),
      'pty.forkPtySupported': fact('pty.forkPtySupported', supportsForkPty),
    };
  }
}
