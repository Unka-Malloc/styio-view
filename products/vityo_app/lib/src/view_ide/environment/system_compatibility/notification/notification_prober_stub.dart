import 'dart:async';

import 'notification_facts.dart';
import 'notification_prober.dart';

class UnsupportedNotificationProber implements NotificationProber {
  const UnsupportedNotificationProber();
  @override
  Future<NotificationFacts> probe() async => NotificationFacts(
    targetId: 'unsupported',
    operatingSystem: 'unknown',
    distributionId: 'unknown',
    architecture: 'unknown',
    providerKind: NotificationProviderKind.unsupported,
    supportsDesktopNotifications: false,
    supportsInAppFallback: false,
    detectedAt: DateTime.now().toUtc(),
  );
}

class LocalNotificationProber extends UnsupportedNotificationProber {
  const LocalNotificationProber({
    String targetId = 'local',
    String? operatingSystem,
    Map<String, String>? environment,
    Future<String?> Function()? architectureReader,
    Future<Map<String, String>> Function()? osReleaseReader,
    DateTime Function()? clock,
  });
}
