enum PtyProviderKind {
  posixPty,
  conPty,
  scriptUtility,
  hosted,
  unsupported,
  unknown,
}

enum PtyFactCertainty { confirmed, inferred, unknown, unsupported, stale }

extension PtyProviderKindX on PtyProviderKind {
  String get wireValue => switch (this) {
    PtyProviderKind.posixPty => 'posix-pty',
    PtyProviderKind.conPty => 'conpty',
    PtyProviderKind.scriptUtility => 'script-utility',
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
    required this.supportsScriptUtility,
    this.scriptUtilityPath,
    this.detectedAt,
    this.entries = const <String, PtyContextFact>{},
  });

  factory PtyFacts.linuxDebianArm({
    String targetId = 'local',
    String architecture = 'aarch64',
    String? scriptUtilityPath = '/usr/bin/script',
    DateTime? detectedAt,
  }) {
    final supportsScriptUtility = scriptUtilityPath != null;
    return PtyFacts(
      targetId: targetId,
      operatingSystem: 'linux',
      distributionId: 'debian',
      distributionName: 'Debian GNU/Linux',
      architecture: architecture,
      providerKind: supportsScriptUtility
          ? PtyProviderKind.scriptUtility
          : PtyProviderKind.unsupported,
      supportsPty: supportsScriptUtility,
      supportsResize: false,
      supportsRawMode: supportsScriptUtility,
      supportsSignals: supportsScriptUtility,
      supportsProcessGroup: false,
      supportsConPty: false,
      supportsForkPty: false,
      supportsScriptUtility: supportsScriptUtility,
      scriptUtilityPath: scriptUtilityPath,
      detectedAt: detectedAt,
      entries: buildEntries(
        targetId: targetId,
        operatingSystem: 'linux',
        distributionId: 'debian',
        distributionName: 'Debian GNU/Linux',
        architecture: architecture,
        providerKind: supportsScriptUtility
            ? PtyProviderKind.scriptUtility
            : PtyProviderKind.unsupported,
        supportsPty: supportsScriptUtility,
        supportsResize: false,
        supportsRawMode: supportsScriptUtility,
        supportsSignals: supportsScriptUtility,
        supportsProcessGroup: false,
        supportsConPty: false,
        supportsForkPty: false,
        supportsScriptUtility: supportsScriptUtility,
        scriptUtilityPath: scriptUtilityPath,
        source: 'fixture',
        detectedAt: detectedAt,
      ),
    );
  }

  factory PtyFacts.windowsX64({
    String targetId = 'local',
    String architecture = 'x64',
    DateTime? detectedAt,
  }) {
    return PtyFacts(
      targetId: targetId,
      operatingSystem: 'windows',
      distributionId: 'windows',
      distributionName: 'Windows',
      architecture: architecture,
      providerKind: PtyProviderKind.unsupported,
      supportsPty: false,
      supportsResize: false,
      supportsRawMode: false,
      supportsSignals: false,
      supportsProcessGroup: false,
      supportsConPty: false,
      supportsForkPty: false,
      supportsScriptUtility: false,
      detectedAt: detectedAt,
      entries: buildEntries(
        targetId: targetId,
        operatingSystem: 'windows',
        distributionId: 'windows',
        distributionName: 'Windows',
        architecture: architecture,
        providerKind: PtyProviderKind.unsupported,
        supportsPty: false,
        supportsResize: false,
        supportsRawMode: false,
        supportsSignals: false,
        supportsProcessGroup: false,
        supportsConPty: false,
        supportsForkPty: false,
        supportsScriptUtility: false,
        scriptUtilityPath: null,
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
  final PtyProviderKind providerKind;
  final bool supportsPty;
  final bool supportsResize;
  final bool supportsRawMode;
  final bool supportsSignals;
  final bool supportsProcessGroup;
  final bool supportsConPty;
  final bool supportsForkPty;
  final bool supportsScriptUtility;
  final String? scriptUtilityPath;
  final DateTime? detectedAt;
  final Map<String, PtyContextFact> entries;

  bool get supportsLinuxDebianArmTarget {
    return operatingSystem == 'linux' &&
        (distributionId == 'debian' || distributionId == 'raspbian') &&
        (architecture == 'aarch64' ||
            architecture == 'arm64' ||
            architecture.startsWith('armv') ||
            architecture == 'arm');
  }

  String get compatibilityTarget {
    if (supportsLinuxDebianArmTarget) {
      return 'linux-debian-arm';
    }
    if (operatingSystem == 'linux') {
      return 'linux-generic';
    }
    if (operatingSystem == 'windows') {
      final arch = architecture.toLowerCase();
      if (arch == 'amd64' || arch == 'x64' || arch == 'x86_64') {
        return 'windows-x64';
      }
      if (arch == 'arm64' || arch == 'aarch64') {
        return 'windows-arm64';
      }
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
    'supportsScriptUtility': supportsScriptUtility,
    if (scriptUtilityPath != null) 'scriptUtilityPath': scriptUtilityPath,
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
    required bool supportsScriptUtility,
    required String? scriptUtilityPath,
    required String source,
    DateTime? detectedAt,
  }) {
    PtyContextFact fact(
      String key,
      Object? value, {
      PtyFactCertainty certainty = PtyFactCertainty.confirmed,
    }) {
      return PtyContextFact(
        key: key,
        value: value,
        source: source,
        scope: 'pty',
        certainty: certainty,
        targetId: targetId,
        detectedAt: detectedAt,
      );
    }

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
      'pty.scriptUtilitySupported': fact(
        'pty.scriptUtilitySupported',
        supportsScriptUtility,
      ),
      'pty.scriptUtilityPath': fact(
        'pty.scriptUtilityPath',
        scriptUtilityPath,
        certainty: scriptUtilityPath == null
            ? PtyFactCertainty.unknown
            : PtyFactCertainty.confirmed,
      ),
    };
  }
}
