import '../event_bus/event_bus.dart';

enum FoundationDiagnosticSeverity {
  info,
  warning,
  error,
}

class FoundationDiagnosticEvent {
  FoundationDiagnosticEvent({
    required this.component,
    required this.message,
    this.severity = FoundationDiagnosticSeverity.info,
    this.metadata = const <String, Object?>{},
    DateTime? emittedAt,
  }) : emittedAt = emittedAt ?? DateTime.now().toUtc();

  final String component;
  final String message;
  final FoundationDiagnosticSeverity severity;
  final Map<String, Object?> metadata;
  final DateTime emittedAt;
}

class FoundationDiagnosticsSink {
  FoundationDiagnosticsSink({FoundationEventBus? eventBus})
      : _eventBus = eventBus;

  final FoundationEventBus? _eventBus;
  final List<FoundationDiagnosticEvent> _events =
      <FoundationDiagnosticEvent>[];

  void emit(FoundationDiagnosticEvent event) {
    _events.add(event);
    _eventBus?.publish(
      FoundationEvent(
        topic: 'foundation.diagnostics',
        owner: event.component,
        payload: <String, Object?>{
          'severity': event.severity.name,
          'message': event.message,
          'metadata': event.metadata,
        },
        emittedAt: event.emittedAt,
      ),
    );
  }

  List<FoundationDiagnosticEvent> list({
    FoundationDiagnosticSeverity? severity,
    String? component,
  }) {
    return _events.where((event) {
      return (severity == null || event.severity == severity) &&
          (component == null || event.component == component);
    }).toList(growable: false);
  }

  void clear() {
    _events.clear();
  }
}
