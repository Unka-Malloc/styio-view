enum NotificationProviderKind { desktop, inAppFallback, unsupported }

extension NotificationProviderKindX on NotificationProviderKind {
  String get wireValue => switch (this) {
    NotificationProviderKind.desktop => 'desktop',
    NotificationProviderKind.inAppFallback => 'in-app-fallback',
    NotificationProviderKind.unsupported => 'unsupported',
  };
}

class NotificationFacts {
  const NotificationFacts({required this.targetId, required this.operatingSystem, required this.distributionId, required this.architecture, required this.providerKind, required this.supportsDesktopNotifications, required this.supportsInAppFallback, this.detectedAt});
  factory NotificationFacts.linuxDebianArm({String targetId = 'local', String architecture = 'aarch64', bool supportsDesktopNotifications = false, DateTime? detectedAt}) => NotificationFacts(targetId: targetId, operatingSystem: 'linux', distributionId: 'debian', architecture: architecture, providerKind: supportsDesktopNotifications ? NotificationProviderKind.desktop : NotificationProviderKind.inAppFallback, supportsDesktopNotifications: supportsDesktopNotifications, supportsInAppFallback: true, detectedAt: detectedAt);
  final String targetId;
  final String operatingSystem;
  final String distributionId;
  final String architecture;
  final NotificationProviderKind providerKind;
  final bool supportsDesktopNotifications;
  final bool supportsInAppFallback;
  final DateTime? detectedAt;
  bool get supportsLinuxDebianArmTarget => operatingSystem == 'linux' && (distributionId == 'debian' || distributionId == 'raspbian') && (architecture == 'aarch64' || architecture == 'arm64' || architecture.startsWith('armv') || architecture == 'arm');
  String get compatibilityTarget => supportsLinuxDebianArmTarget ? 'linux-debian-arm' : operatingSystem == 'linux' ? 'linux-generic' : operatingSystem == 'windows' ? 'windows-generic' : 'unsupported';
}
