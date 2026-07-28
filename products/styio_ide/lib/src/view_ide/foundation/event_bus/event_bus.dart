import 'dart:async';

class FoundationEvent {
  FoundationEvent({
    required this.topic,
    required this.owner,
    required this.payload,
    DateTime? emittedAt,
  }) : emittedAt = emittedAt ?? DateTime.now().toUtc();

  final String topic;
  final String owner;
  final Map<String, Object?> payload;
  final DateTime emittedAt;
}

class FoundationEventBus {
  final StreamController<FoundationEvent> _controller =
      StreamController<FoundationEvent>.broadcast(sync: true);

  Stream<FoundationEvent> subscribe({String? topic}) {
    if (topic == null) {
      return _controller.stream;
    }
    return _controller.stream.where((event) => event.topic == topic);
  }

  void publish(FoundationEvent event) {
    if (_controller.isClosed) {
      throw StateError('Foundation event bus is closed.');
    }
    _controller.add(event);
  }

  Future<void> close() {
    return _controller.close();
  }
}
