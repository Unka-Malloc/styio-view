import 'dart:collection';

import '../backend_toolchain/execution_adapter.dart';
import 'runtime_event_vocabulary.dart';

sealed class TypedRuntimeEvent {
  const TypedRuntimeEvent(this.envelope);

  final RuntimeEventEnvelope envelope;
  String get family;
  String get summary;
}

final class RuntimePhaseEvent extends TypedRuntimeEvent {
  const RuntimePhaseEvent(
    super.envelope, {
    required this.phase,
    required this.state,
  });

  final String phase;
  final String state;

  @override
  String get family => phase;

  @override
  String get summary => '${envelope.eventKind} from ${envelope.origin}';
}

final class RuntimeTransitionEvent extends TypedRuntimeEvent {
  const RuntimeTransitionEvent(
    super.envelope, {
    required this.from,
    required this.to,
  });

  final String? from;
  final String? to;

  @override
  String get family => 'transition';

  @override
  String get summary => '${envelope.eventKind} from ${envelope.origin}';
}

final class RuntimeObservationEvent extends TypedRuntimeEvent {
  const RuntimeObservationEvent(super.envelope, {required this.observation});

  final String observation;

  @override
  String get family => runtimeEventFamily(envelope.eventKind);

  @override
  String get summary => '${envelope.eventKind} from ${envelope.origin}';
}

final class RuntimeEventCapabilityGap extends TypedRuntimeEvent {
  const RuntimeEventCapabilityGap(super.envelope, {required this.reason});

  final String reason;

  @override
  String get family => 'unsupported';

  @override
  String get summary => 'capability-gap: $reason';
}

TypedRuntimeEvent decodeTypedRuntimeEvent(RuntimeEventEnvelope envelope) {
  if (envelope.schemaVersion != 1) {
    return RuntimeEventCapabilityGap(
      envelope,
      reason: 'runtime event schema ${envelope.schemaVersion} is unsupported',
    );
  }
  if (!isKnownRuntimeEventKind(envelope.eventKind)) {
    return RuntimeEventCapabilityGap(
      envelope,
      reason: 'runtime event kind ${envelope.eventKind} is unsupported',
    );
  }
  final segments = envelope.eventKind.split('.');
  final family = runtimeEventFamily(envelope.eventKind);
  final state = segments.last;
  if (family == 'compile' ||
      family == 'run' ||
      family == 'unit' ||
      family == 'unit.test') {
    return RuntimePhaseEvent(envelope, phase: family, state: state);
  }
  if (family == 'transition') {
    return RuntimeTransitionEvent(
      envelope,
      from: _payloadString(envelope.payload, const <String>['from', 'source']),
      to: _payloadString(envelope.payload, const <String>['to', 'target']),
    );
  }
  return RuntimeObservationEvent(envelope, observation: state);
}

String? _payloadString(Map<String, Object?> payload, List<String> keys) {
  for (final key in keys) {
    final value = payload[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

final class TypedRuntimeEventStream {
  TypedRuntimeEventStream({required this.capacity}) : assert(capacity > 0);

  final int capacity;
  final Queue<TypedRuntimeEvent> _events = Queue<TypedRuntimeEvent>();
  final Map<String, int> _latestSequenceBySession = <String, int>{};
  int _droppedEventCount = 0;
  bool _closed = false;

  List<TypedRuntimeEvent> get events =>
      List<TypedRuntimeEvent>.unmodifiable(_events);
  int get droppedEventCount => _droppedEventCount;
  bool get isClosed => _closed;

  bool add(RuntimeEventEnvelope envelope) {
    if (_closed || envelope.sessionId.isEmpty || envelope.sequence <= 0) {
      return false;
    }
    final previous = _latestSequenceBySession[envelope.sessionId];
    if (previous != null && envelope.sequence <= previous) return false;
    _latestSequenceBySession[envelope.sessionId] = envelope.sequence;
    if (_events.length == capacity) {
      _events.removeFirst();
      _droppedEventCount += 1;
    }
    _events.addLast(decodeTypedRuntimeEvent(envelope));
    return true;
  }

  void close() {
    _closed = true;
  }
}
