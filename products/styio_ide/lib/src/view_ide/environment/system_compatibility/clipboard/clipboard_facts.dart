enum ClipboardProviderKind { system, memoryFallback, unsupported }

extension ClipboardProviderKindX on ClipboardProviderKind {
  String get wireValue => switch (this) {
    ClipboardProviderKind.system => 'system',
    ClipboardProviderKind.memoryFallback => 'memory-fallback',
    ClipboardProviderKind.unsupported => 'unsupported',
  };
}

class ClipboardFacts {
  const ClipboardFacts({
    required this.targetId,
    required this.operatingSystem,
    required this.distributionId,
    required this.architecture,
    required this.providerKind,
    required this.supportsText,
    required this.supportsSystemClipboard,
    required this.supportsMemoryFallback,
    this.detectedAt,
  });

  factory ClipboardFacts.linuxDebianArm({
    String targetId = 'local',
    String architecture = 'aarch64',
    bool supportsSystemClipboard = false,
    DateTime? detectedAt,
  }) => ClipboardFacts(
    targetId: targetId,
    operatingSystem: 'linux',
    distributionId: 'debian',
    architecture: architecture,
    providerKind: supportsSystemClipboard ? ClipboardProviderKind.system : ClipboardProviderKind.memoryFallback,
    supportsText: true,
    supportsSystemClipboard: supportsSystemClipboard,
    supportsMemoryFallback: true,
    detectedAt: detectedAt,
  );

  final String targetId;
  final String operatingSystem;
  final String distributionId;
  final String architecture;
  final ClipboardProviderKind providerKind;
  final bool supportsText;
  final bool supportsSystemClipboard;
  final bool supportsMemoryFallback;
  final DateTime? detectedAt;

  bool get supportsLinuxDebianArmTarget => operatingSystem == 'linux' && (distributionId == 'debian' || distributionId == 'raspbian') && (architecture == 'aarch64' || architecture == 'arm64' || architecture.startsWith('armv') || architecture == 'arm');
  String get compatibilityTarget => supportsLinuxDebianArmTarget ? 'linux-debian-arm' : operatingSystem == 'linux' ? 'linux-generic' : operatingSystem == 'windows' ? 'windows-generic' : 'unsupported';
}
