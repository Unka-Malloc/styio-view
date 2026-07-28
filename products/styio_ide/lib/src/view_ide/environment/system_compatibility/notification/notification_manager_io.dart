import '../platform_adapter/platform_adapter.dart';
import '../platform_context/platform_context.dart';
import 'notification_adapter.dart';
import 'notification_facts.dart';
import 'notification_manager.dart';
import 'notification_prober.dart';
import 'notification_prober_io.dart';

Future<NotificationManager> createPlatformNotificationManager({
  NotificationProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  final adapter = platformContext == null ? null : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.notification ?? await (prober ?? const LocalNotificationProber()).probe();
  return LocalNotificationManager(facts: facts, adapter: adapter?.notificationAdapter);
}

class LocalNotificationManager implements NotificationManager {
  LocalNotificationManager({required this.facts, NotificationAdapter? adapter}) : compatibility = (adapter ?? NotificationAdapter(facts)).adapt();
  factory LocalNotificationManager.linuxDebianArmForTest() => LocalNotificationManager(facts: NotificationFacts.linuxDebianArm());
  @override
  final NotificationFacts facts;
  @override
  final NotificationCompatibility compatibility;
  final List<NotificationRequest> deliveredRequests = <NotificationRequest>[];
  @override
  NotificationOperationFailure? failureFor(
    NotificationResult result, {
    String operation = 'notification.notify',
    String? recoveryHint,
  }) {
    return const NotificationFailureClassifier(
      sourceManager: 'LocalNotificationManager',
    ).classify(
      result,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }

  @override
  Future<NotificationResult> notify(NotificationRequest request) async {
    if (!compatibility.supportsDesktopNotifications && !compatibility.supportsInAppFallback) {
      return NotificationResult(status: NotificationStatus.blocked, request: request, message: 'Notifications are not available.');
    }
    deliveredRequests.add(request);
    return NotificationResult(status: NotificationStatus.delivered, request: request, message: compatibility.supportsDesktopNotifications ? 'Desktop notification requested.' : 'In-app fallback notification recorded.');
  }
}
