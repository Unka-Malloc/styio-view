enum ShellFactCertainty {
  confirmed,
  inferred,
  unknown,
  unsupported,
  stale,
}

enum ShellFamily {
  bash,
  sh,
  zsh,
  fish,
  powershell,
  cmd,
  unknown,
}

enum ShellProviderKind {
  local,
  hosted,
  virtual,
  unknown,
}

extension ShellFactCertaintyX on ShellFactCertainty {
  String get wireValue => switch (this) {
    ShellFactCertainty.confirmed => 'confirmed',
    ShellFactCertainty.inferred => 'inferred',
    ShellFactCertainty.unknown => 'unknown',
    ShellFactCertainty.unsupported => 'unsupported',
    ShellFactCertainty.stale => 'stale',
  };
}

extension ShellFamilyX on ShellFamily {
  String get wireValue => switch (this) {
    ShellFamily.bash => 'bash',
    ShellFamily.sh => 'sh',
    ShellFamily.zsh => 'zsh',
    ShellFamily.fish => 'fish',
    ShellFamily.powershell => 'powershell',
    ShellFamily.cmd => 'cmd',
    ShellFamily.unknown => 'unknown',
  };
}

extension ShellProviderKindX on ShellProviderKind {
  String get wireValue => switch (this) {
    ShellProviderKind.local => 'local',
    ShellProviderKind.hosted => 'hosted',
    ShellProviderKind.virtual => 'virtual',
    ShellProviderKind.unknown => 'unknown',
  };
}

class ShellContextFact {
  const ShellContextFact({
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
  final ShellFactCertainty certainty;
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

class ShellExecutableFact {
  const ShellExecutableFact({
    required this.path,
    required this.family,
    this.version,
    this.isDefault = false,
  });

  final String path;
  final ShellFamily family;
  final String? version;
  final bool isDefault;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'path': path,
      'family': family.wireValue,
      if (version != null) 'version': version,
      'isDefault': isDefault,
    };
  }
}

class ShellFacts {
  const ShellFacts({
    required this.targetId,
    required this.operatingSystem,
    required this.distributionId,
    required this.distributionName,
    required this.architecture,
    required this.providerKind,
    required this.availableShells,
    required this.defaultShellPath,
    required this.supportsPty,
    required this.supportsLoginShell,
    required this.supportsInteractiveShell,
    required this.scriptExtension,
    this.detectedAt,
    this.entries = const <String, ShellContextFact>{},
  });

  factory ShellFacts.linuxDebianArm({
    String targetId = 'local',
    String defaultShellPath = '/bin/sh',
    String architecture = 'aarch64',
    List<ShellExecutableFact>? availableShells,
    DateTime? detectedAt,
  }) {
    final shells = availableShells ??
        <ShellExecutableFact>[
          ShellExecutableFact(
            path: defaultShellPath,
            family: defaultShellPath.endsWith('bash')
                ? ShellFamily.bash
                : ShellFamily.sh,
            isDefault: true,
          ),
        ];
    return ShellFacts(
      targetId: targetId,
      operatingSystem: 'linux',
      distributionId: 'debian',
      distributionName: 'Debian GNU/Linux',
      architecture: architecture,
      providerKind: ShellProviderKind.local,
      availableShells: shells,
      defaultShellPath: defaultShellPath,
      supportsPty: true,
      supportsLoginShell: true,
      supportsInteractiveShell: true,
      scriptExtension: '.sh',
      detectedAt: detectedAt,
      entries: buildEntries(
        targetId: targetId,
        operatingSystem: 'linux',
        distributionId: 'debian',
        distributionName: 'Debian GNU/Linux',
        architecture: architecture,
        providerKind: ShellProviderKind.local,
        availableShells: shells,
        defaultShellPath: defaultShellPath,
        supportsPty: true,
        supportsLoginShell: true,
        supportsInteractiveShell: true,
        scriptExtension: '.sh',
        source: 'fixture',
        detectedAt: detectedAt,
      ),
    );
  }


  factory ShellFacts.windowsX64({
    String targetId = 'local',
    String defaultShellPath = 'powershell.exe',
    String architecture = 'x64',
    List<ShellExecutableFact>? availableShells,
    DateTime? detectedAt,
  }) {
    final shells = availableShells ??
        <ShellExecutableFact>[
          ShellExecutableFact(
            path: defaultShellPath,
            family: ShellFamily.powershell,
            isDefault: true,
          ),
          const ShellExecutableFact(
            path: r'C:\Windows\System32\cmd.exe',
            family: ShellFamily.cmd,
          ),
        ];
    return ShellFacts(
      targetId: targetId,
      operatingSystem: 'windows',
      distributionId: 'windows',
      distributionName: 'Windows',
      architecture: architecture,
      providerKind: ShellProviderKind.local,
      availableShells: shells,
      defaultShellPath: defaultShellPath,
      supportsPty: false,
      supportsLoginShell: false,
      supportsInteractiveShell: true,
      scriptExtension: '.ps1',
      detectedAt: detectedAt,
      entries: buildEntries(
        targetId: targetId,
        operatingSystem: 'windows',
        distributionId: 'windows',
        distributionName: 'Windows',
        architecture: architecture,
        providerKind: ShellProviderKind.local,
        availableShells: shells,
        defaultShellPath: defaultShellPath,
        supportsPty: false,
        supportsLoginShell: false,
        supportsInteractiveShell: true,
        scriptExtension: '.ps1',
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
  final ShellProviderKind providerKind;
  final List<ShellExecutableFact> availableShells;
  final String? defaultShellPath;
  final bool supportsPty;
  final bool supportsLoginShell;
  final bool supportsInteractiveShell;
  final String scriptExtension;
  final DateTime? detectedAt;
  final Map<String, ShellContextFact> entries;

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

  bool get hasExecutableShell => availableShells.isNotEmpty;

  ShellExecutableFact? get defaultShell {
    for (final shell in availableShells) {
      if (shell.path == defaultShellPath || shell.isDefault) {
        return shell;
      }
    }
    return availableShells.isEmpty ? null : availableShells.first;
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'targetId': targetId,
      'operatingSystem': operatingSystem,
      'distributionId': distributionId,
      'distributionName': distributionName,
      'architecture': architecture,
      'providerKind': providerKind.wireValue,
      'availableShells': availableShells
          .map((shell) => shell.toJson())
          .toList(growable: false),
      if (defaultShellPath != null) 'defaultShellPath': defaultShellPath,
      'supportsPty': supportsPty,
      'supportsLoginShell': supportsLoginShell,
      'supportsInteractiveShell': supportsInteractiveShell,
      'scriptExtension': scriptExtension,
      'compatibilityTarget': compatibilityTarget,
      if (detectedAt != null) 'detectedAt': detectedAt!.toIso8601String(),
      'entries': entries.map(
        (key, value) => MapEntry<String, Object?>(key, value.toJson()),
      ),
    };
  }

  static Map<String, ShellContextFact> buildEntries({
    required String targetId,
    required String operatingSystem,
    required String distributionId,
    required String distributionName,
    required String architecture,
    required ShellProviderKind providerKind,
    required List<ShellExecutableFact> availableShells,
    required String? defaultShellPath,
    required bool supportsPty,
    required bool supportsLoginShell,
    required bool supportsInteractiveShell,
    required String scriptExtension,
    required String source,
    DateTime? detectedAt,
  }) {
    ShellContextFact fact(
      String key,
      Object? value, {
      ShellFactCertainty certainty = ShellFactCertainty.confirmed,
    }) {
      return ShellContextFact(
        key: key,
        value: value,
        source: source,
        scope: 'shell',
        certainty: certainty,
        targetId: targetId,
        detectedAt: detectedAt,
      );
    }

    return <String, ShellContextFact>{
      'host.operatingSystem': fact('host.operatingSystem', operatingSystem),
      'host.distributionId': fact('host.distributionId', distributionId),
      'host.distributionName': fact(
        'host.distributionName',
        distributionName,
        certainty: distributionName.isEmpty
            ? ShellFactCertainty.unknown
            : ShellFactCertainty.confirmed,
      ),
      'host.architecture': fact('host.architecture', architecture),
      'shell.providerKind': fact('shell.providerKind', providerKind.wireValue),
      'shell.availableShells': fact(
        'shell.availableShells',
        availableShells.map((shell) => shell.toJson()).toList(growable: false),
      ),
      'shell.defaultShellPath': fact(
        'shell.defaultShellPath',
        defaultShellPath,
        certainty: defaultShellPath == null
            ? ShellFactCertainty.unknown
            : ShellFactCertainty.confirmed,
      ),
      'shell.ptySupported': fact('shell.ptySupported', supportsPty),
      'shell.loginShellSupported': fact(
        'shell.loginShellSupported',
        supportsLoginShell,
      ),
      'shell.interactiveSupported': fact(
        'shell.interactiveSupported',
        supportsInteractiveShell,
      ),
      'shell.scriptExtension': fact('shell.scriptExtension', scriptExtension),
    };
  }
}
