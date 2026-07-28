import 'notification_adapter.dart';
import 'notification_facts.dart';

enum NotificationStatus { delivered, blocked }

enum NotificationFailureKind {
  unsupported,
  blocked,
  unknownFailure,
}

class NotificationRequest {
  const NotificationRequest({required this.title, required this.body});
  final String title;
  final String body;
}

class NotificationOperationFailure {
  const NotificationOperationFailure({
    required this.kind,
    required this.operation,
    required this.sourceManager,
    required this.message,
    this.recoveryHint,
  });

  final NotificationFailureKind kind;
  final String operation;
  final String sourceManager;
  final String message;
  final String? recoveryHint;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'operation': operation,
      'sourceManager': sourceManager,
      'message': message,
      if (recoveryHint != null) 'recoveryHint': recoveryHint,
    };
  }
}

class NotificationResult {
  const NotificationResult({required this.status, required this.request, this.message});
  final NotificationStatus status;
  final NotificationRequest request;
  final String? message;
  bool get delivered => status == NotificationStatus.delivered;
}

class NotificationFailureClassifier {
  const NotificationFailureClassifier({required this.sourceManager});

  final String sourceManager;

  NotificationOperationFailure? classify(
    NotificationResult result, {
    String operation = 'notification.notify',
    String? recoveryHint,
  }) {
    if (result.delivered) {
      return null;
    }
    return NotificationOperationFailure(
      kind: result.status == NotificationStatus.blocked
          ? NotificationFailureKind.blocked
          : NotificationFailureKind.unknownFailure,
      operation: operation,
      sourceManager: sourceManager,
      message: result.message ?? 'Notification operation failed.',
      recoveryHint: recoveryHint,
    );
  }
}

abstract class NotificationManager {
  NotificationFacts get facts;
  NotificationCompatibility get compatibility;
  Future<NotificationResult> notify(NotificationRequest request);
  NotificationOperationFailure? failureFor(
    NotificationResult result, {
    String operation = 'notification.notify',
    String? recoveryHint,
  });
}

class UnsupportedNotificationManager implements NotificationManager {
  UnsupportedNotificationManager({required this.facts}) : compatibility = NotificationAdapter(facts).adapt();
  @override
  final NotificationFacts facts;
  @override
  final NotificationCompatibility compatibility;
  @override
  Future<NotificationResult> notify(NotificationRequest request) async => NotificationResult(status: NotificationStatus.blocked, request: request, message: 'Notifications are not available.');
  @override
  NotificationOperationFailure? failureFor(
    NotificationResult result, {
    String operation = 'notification.notify',
    String? recoveryHint,
  }) {
    return const NotificationFailureClassifier(
      sourceManager: 'UnsupportedNotificationManager',
    ).classify(
      result,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }
}
