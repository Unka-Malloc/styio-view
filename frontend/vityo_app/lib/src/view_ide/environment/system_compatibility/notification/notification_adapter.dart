import 'notification_facts.dart';

class NotificationAdapter {
  const NotificationAdapter(this.facts);
  final NotificationFacts facts;
  NotificationCompatibility adapt() => NotificationCompatibility(targetId: facts.targetId, compatibilityTarget: facts.compatibilityTarget, supportsDesktopNotifications: facts.supportsDesktopNotifications, supportsInAppFallback: facts.supportsInAppFallback);
}

class NotificationCompatibility {
  const NotificationCompatibility({required this.targetId, required this.compatibilityTarget, required this.supportsDesktopNotifications, required this.supportsInAppFallback});
  final String targetId;
  final String compatibilityTarget;
  final bool supportsDesktopNotifications;
  final bool supportsInAppFallback;
  bool get isLinuxDebianArm => compatibilityTarget == 'linux-debian-arm';
}
