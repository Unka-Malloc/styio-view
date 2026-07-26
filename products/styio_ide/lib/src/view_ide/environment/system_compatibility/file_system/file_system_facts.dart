enum FileSystemFactCertainty {
  confirmed,
  inferred,
  unknown,
  unsupported,
  stale,
}

enum FileSystemProviderKind {
  local,
  remote,
  browserSandbox,
  virtual,
  hosted,
  unknown,
}

enum FileSystemPathStyle {
  posix,
  windows,
  unknown,
}

enum FileSystemWatchSupport {
  none,
  directory,
  recursive,
  polling,
  unknown,
}

extension FileSystemFactCertaintyX on FileSystemFactCertainty {
  String get wireValue => switch (this) {
    FileSystemFactCertainty.confirmed => 'confirmed',
    FileSystemFactCertainty.inferred => 'inferred',
    FileSystemFactCertainty.unknown => 'unknown',
    FileSystemFactCertainty.unsupported => 'unsupported',
    FileSystemFactCertainty.stale => 'stale',
  };
}

extension FileSystemProviderKindX on FileSystemProviderKind {
  String get wireValue => switch (this) {
    FileSystemProviderKind.local => 'local',
    FileSystemProviderKind.remote => 'remote',
    FileSystemProviderKind.browserSandbox => 'browser-sandbox',
    FileSystemProviderKind.virtual => 'virtual',
    FileSystemProviderKind.hosted => 'hosted',
    FileSystemProviderKind.unknown => 'unknown',
  };
}

extension FileSystemPathStyleX on FileSystemPathStyle {
  String get wireValue => switch (this) {
    FileSystemPathStyle.posix => 'posix',
    FileSystemPathStyle.windows => 'windows',
    FileSystemPathStyle.unknown => 'unknown',
  };
}

extension FileSystemWatchSupportX on FileSystemWatchSupport {
  String get wireValue => switch (this) {
    FileSystemWatchSupport.none => 'none',
    FileSystemWatchSupport.directory => 'directory',
    FileSystemWatchSupport.recursive => 'recursive',
    FileSystemWatchSupport.polling => 'polling',
    FileSystemWatchSupport.unknown => 'unknown',
  };
}

class PlatformContextFact {
  const PlatformContextFact({
    required this.key,
    required this.value,
    required this.source,
    required this.scope,
    required this.certainty,
    this.targetId,
    this.detectedAt,
    this.expiresAt,
  });

  final String key;
  final Object? value;
  final String source;
  final String scope;
  final FileSystemFactCertainty certainty;
  final String? targetId;
  final DateTime? detectedAt;
  final DateTime? expiresAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key,
      'value': value,
      'source': source,
      'scope': scope,
      'certainty': certainty.wireValue,
      if (targetId != null) 'targetId': targetId,
      if (detectedAt != null) 'detectedAt': detectedAt!.toIso8601String(),
      if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
    };
  }
}

class FileSystemFacts {
  const FileSystemFacts({
    required this.targetId,
    required this.operatingSystem,
    required this.distributionId,
    required this.distributionName,
    required this.architecture,
    required this.pathStyle,
    required this.pathSeparator,
    required this.providerKind,
    required this.watchSupport,
    required this.caseSensitive,
    required this.supportsFileUri,
    required this.supportsSymbolicLinks,
    required this.supportsAtomicWrite,
    this.detectedAt,
    this.entries = const <String, PlatformContextFact>{},
  });

  factory FileSystemFacts.linuxDebianArm({
    String targetId = 'local',
    String architecture = 'aarch64',
    DateTime? detectedAt,
  }) {
    return FileSystemFacts(
      targetId: targetId,
      operatingSystem: 'linux',
      distributionId: 'debian',
      distributionName: 'Debian GNU/Linux',
      architecture: architecture,
      pathStyle: FileSystemPathStyle.posix,
      pathSeparator: '/',
      providerKind: FileSystemProviderKind.local,
      watchSupport: FileSystemWatchSupport.directory,
      caseSensitive: true,
      supportsFileUri: true,
      supportsSymbolicLinks: true,
      supportsAtomicWrite: true,
      detectedAt: detectedAt,
      entries: buildEntries(
        targetId: targetId,
        operatingSystem: 'linux',
        distributionId: 'debian',
        distributionName: 'Debian GNU/Linux',
        architecture: architecture,
        pathStyle: FileSystemPathStyle.posix,
        pathSeparator: '/',
        providerKind: FileSystemProviderKind.local,
        watchSupport: FileSystemWatchSupport.directory,
        caseSensitive: true,
        supportsFileUri: true,
        supportsSymbolicLinks: true,
        supportsAtomicWrite: true,
        detectedAt: detectedAt,
        source: 'fixture',
      ),
    );
  }

  factory FileSystemFacts.windowsX64({
    String targetId = 'local',
    String architecture = 'x64',
    DateTime? detectedAt,
  }) {
    return FileSystemFacts(
      targetId: targetId,
      operatingSystem: 'windows',
      distributionId: 'windows',
      distributionName: 'Windows',
      architecture: architecture,
      pathStyle: FileSystemPathStyle.windows,
      pathSeparator: r'\',
      providerKind: FileSystemProviderKind.local,
      watchSupport: FileSystemWatchSupport.recursive,
      caseSensitive: false,
      supportsFileUri: true,
      supportsSymbolicLinks: false,
      supportsAtomicWrite: true,
      detectedAt: detectedAt,
      entries: buildEntries(
        targetId: targetId,
        operatingSystem: 'windows',
        distributionId: 'windows',
        distributionName: 'Windows',
        architecture: architecture,
        pathStyle: FileSystemPathStyle.windows,
        pathSeparator: r'\',
        providerKind: FileSystemProviderKind.local,
        watchSupport: FileSystemWatchSupport.recursive,
        caseSensitive: false,
        supportsFileUri: true,
        supportsSymbolicLinks: false,
        supportsAtomicWrite: true,
        detectedAt: detectedAt,
        source: 'fixture',
      ),
    );
  }

  final String targetId;
  final String operatingSystem;
  final String distributionId;
  final String distributionName;
  final String architecture;
  final FileSystemPathStyle pathStyle;
  final String pathSeparator;
  final FileSystemProviderKind providerKind;
  final FileSystemWatchSupport watchSupport;
  final bool caseSensitive;
  final bool supportsFileUri;
  final bool supportsSymbolicLinks;
  final bool supportsAtomicWrite;
  final DateTime? detectedAt;
  final Map<String, PlatformContextFact> entries;

  bool get isLinux => operatingSystem == 'linux';

  bool get isDebianLike {
    final id = distributionId.toLowerCase();
    return id == 'debian' || id == 'raspbian';
  }

  bool get isArmArchitecture {
    final arch = architecture.toLowerCase();
    return arch == 'aarch64' ||
        arch == 'arm64' ||
        arch.startsWith('armv') ||
        arch == 'arm';
  }

  bool get supportsLinuxDebianArmTarget {
    return isLinux && isDebianLike && isArmArchitecture;
  }

  String get compatibilityTarget {
    if (supportsLinuxDebianArmTarget) {
      return 'linux-debian-arm';
    }
    if (isLinux && isDebianLike) {
      return 'linux-debian';
    }
    if (isLinux && isArmArchitecture) {
      return 'linux-arm';
    }
    if (isLinux) {
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

  FileSystemFacts copyWith({
    String? targetId,
    String? operatingSystem,
    String? distributionId,
    String? distributionName,
    String? architecture,
    FileSystemPathStyle? pathStyle,
    String? pathSeparator,
    FileSystemProviderKind? providerKind,
    FileSystemWatchSupport? watchSupport,
    bool? caseSensitive,
    bool? supportsFileUri,
    bool? supportsSymbolicLinks,
    bool? supportsAtomicWrite,
    DateTime? detectedAt,
    Map<String, PlatformContextFact>? entries,
  }) {
    return FileSystemFacts(
      targetId: targetId ?? this.targetId,
      operatingSystem: operatingSystem ?? this.operatingSystem,
      distributionId: distributionId ?? this.distributionId,
      distributionName: distributionName ?? this.distributionName,
      architecture: architecture ?? this.architecture,
      pathStyle: pathStyle ?? this.pathStyle,
      pathSeparator: pathSeparator ?? this.pathSeparator,
      providerKind: providerKind ?? this.providerKind,
      watchSupport: watchSupport ?? this.watchSupport,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      supportsFileUri: supportsFileUri ?? this.supportsFileUri,
      supportsSymbolicLinks:
          supportsSymbolicLinks ?? this.supportsSymbolicLinks,
      supportsAtomicWrite: supportsAtomicWrite ?? this.supportsAtomicWrite,
      detectedAt: detectedAt ?? this.detectedAt,
      entries: entries ?? this.entries,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'targetId': targetId,
      'operatingSystem': operatingSystem,
      'distributionId': distributionId,
      'distributionName': distributionName,
      'architecture': architecture,
      'pathStyle': pathStyle.wireValue,
      'pathSeparator': pathSeparator,
      'providerKind': providerKind.wireValue,
      'watchSupport': watchSupport.wireValue,
      'caseSensitive': caseSensitive,
      'supportsFileUri': supportsFileUri,
      'supportsSymbolicLinks': supportsSymbolicLinks,
      'supportsAtomicWrite': supportsAtomicWrite,
      'compatibilityTarget': compatibilityTarget,
      if (detectedAt != null) 'detectedAt': detectedAt!.toIso8601String(),
      'entries': entries.map(
        (key, value) => MapEntry<String, Object?>(key, value.toJson()),
      ),
    };
  }

  static Map<String, PlatformContextFact> buildEntries({
    required String targetId,
    required String operatingSystem,
    required String distributionId,
    required String distributionName,
    required String architecture,
    required FileSystemPathStyle pathStyle,
    required String pathSeparator,
    required FileSystemProviderKind providerKind,
    required FileSystemWatchSupport watchSupport,
    required bool caseSensitive,
    required bool supportsFileUri,
    required bool supportsSymbolicLinks,
    required bool supportsAtomicWrite,
    required String source,
    DateTime? detectedAt,
  }) {
    PlatformContextFact fact(
      String key,
      Object? value, {
      FileSystemFactCertainty certainty = FileSystemFactCertainty.confirmed,
    }) {
      return PlatformContextFact(
        key: key,
        value: value,
        source: source,
        scope: 'filesystem',
        certainty: certainty,
        targetId: targetId,
        detectedAt: detectedAt,
      );
    }

    return <String, PlatformContextFact>{
      'host.operatingSystem': fact('host.operatingSystem', operatingSystem),
      'host.distributionId': fact('host.distributionId', distributionId),
      'host.distributionName': fact(
        'host.distributionName',
        distributionName,
        certainty: distributionName.isEmpty
            ? FileSystemFactCertainty.unknown
            : FileSystemFactCertainty.confirmed,
      ),
      'host.architecture': fact('host.architecture', architecture),
      'filesystem.pathStyle': fact('filesystem.pathStyle', pathStyle.wireValue),
      'filesystem.pathSeparator': fact('filesystem.pathSeparator', pathSeparator),
      'filesystem.providerKind': fact(
        'filesystem.providerKind',
        providerKind.wireValue,
      ),
      'filesystem.watchSupport': fact(
        'filesystem.watchSupport',
        watchSupport.wireValue,
      ),
      'filesystem.caseSensitivityHint': fact(
        'filesystem.caseSensitivityHint',
        caseSensitive,
        certainty: FileSystemFactCertainty.inferred,
      ),
      'filesystem.supportsFileUri': fact(
        'filesystem.supportsFileUri',
        supportsFileUri,
      ),
      'filesystem.supportsSymbolicLinks': fact(
        'filesystem.supportsSymbolicLinks',
        supportsSymbolicLinks,
      ),
      'filesystem.supportsAtomicWrite': fact(
        'filesystem.supportsAtomicWrite',
        supportsAtomicWrite,
      ),
    };
  }
}
