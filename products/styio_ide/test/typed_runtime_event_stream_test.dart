import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/execution_adapter.dart';
import 'package:styio_ide/src/view_ide/runtime/typed_runtime_event_stream.dart';

void main() {
  test('decodes only published runtime event vocabulary', () {
    final phase = decodeTypedRuntimeEvent(_event(1, 'run.started'));
    final transition = decodeTypedRuntimeEvent(
      _event(
        2,
        'transition.fired',
        payload: const <String, Object?>{'from': 'idle', 'to': 'running'},
      ),
    );
    final unsupported = decodeTypedRuntimeEvent(_event(3, 'pulse.emitted'));

    expect(phase, isA<RuntimePhaseEvent>());
    expect((phase as RuntimePhaseEvent).state, 'started');
    expect(transition, isA<RuntimeTransitionEvent>());
    expect((transition as RuntimeTransitionEvent).to, 'running');
    expect(unsupported, isA<RuntimeEventCapabilityGap>());
    expect(unsupported.summary, contains('capability-gap'));
  });

  test('fails closed on unknown schema versions', () {
    final event = RuntimeEventEnvelope(
      schemaVersion: 2,
      sessionId: 'session',
      sequence: 1,
      timestamp: DateTime.utc(2026),
      eventKind: 'run.started',
      origin: 'fixture',
      payload: const <String, Object?>{},
    );

    expect(decodeTypedRuntimeEvent(event), isA<RuntimeEventCapabilityGap>());
  });

  test('bounds memory, counts drops, orders per session, and closes once', () {
    final stream = TypedRuntimeEventStream(capacity: 2);

    expect(stream.add(_event(1, 'run.started')), isTrue);
    expect(stream.add(_event(1, 'run.finished')), isFalse);
    expect(stream.add(_event(2, 'state.changed')), isTrue);
    expect(stream.add(_event(3, 'run.finished')), isTrue);
    expect(stream.events.length, 2);
    expect(stream.droppedEventCount, 1);
    expect(stream.events.first.envelope.sequence, 2);

    stream.close();
    stream.close();
    expect(stream.isClosed, isTrue);
    expect(stream.add(_event(4, 'log.emitted')), isFalse);
  });
}

RuntimeEventEnvelope _event(
  int sequence,
  String kind, {
  Map<String, Object?> payload = const <String, Object?>{},
}) {
  return RuntimeEventEnvelope(
    schemaVersion: 1,
    sessionId: 'session',
    sequence: sequence,
    timestamp: DateTime.utc(2026, 7, 20, 0, 0, sequence),
    eventKind: kind,
    origin: 'fixture',
    payload: payload,
  );
}
