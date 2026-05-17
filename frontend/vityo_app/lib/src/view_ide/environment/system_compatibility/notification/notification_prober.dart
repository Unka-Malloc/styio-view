import 'notification_facts.dart';

abstract class NotificationProber {
  Future<NotificationFacts> probe();
}

class StaticNotificationProber implements NotificationProber {
  const StaticNotificationProber(this.facts);
  final NotificationFacts facts;
  @override
  Future<NotificationFacts> probe() async => facts;
}
