// ignore_for_file: use_super_parameters

import '../platform_context/platform_context.dart';
import 'notification_adapter.dart';
import 'notification_facts.dart';
import 'notification_manager.dart';
import 'notification_prober.dart';
import 'notification_prober_stub.dart';

Future<NotificationManager> createPlatformNotificationManager({
  NotificationProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  if (platformContext != null) {
    return UnsupportedNotificationManager(facts: platformContext.notification);
  }
  final facts = await (prober ?? const UnsupportedNotificationProber()).probe();
  return UnsupportedNotificationManager(facts: facts);
}

class LocalNotificationManager extends UnsupportedNotificationManager {
  LocalNotificationManager({
    required NotificationFacts facts,
    NotificationAdapter? adapter,
  }) : super(facts: facts);

  final List<NotificationRequest> deliveredRequests = <NotificationRequest>[];

  factory LocalNotificationManager.linuxDebianArmForTest() {
    return LocalNotificationManager(facts: NotificationFacts.linuxDebianArm());
  }
}
