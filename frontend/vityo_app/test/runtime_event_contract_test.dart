import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/runtime_event_adapter.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/runtime/runtime_replay_summary.dart';

void main() {
  test('runtime event registry normalizes sequence within a session', () async {
    recordRuntimeEventsForSession(
      'runtime-session-contract',
      <RuntimeEventEnvelope>[
        _event(
          sessionId: 'producer-session',
          sequence: 42,
          eventKind: 'compile.started',
        ),
        _event(
          sessionId: 'producer-session',
          sequence: 7,
          eventKind: 'run.finished',
        ),
      ],
    );
    addTearDown(() => clearRuntimeEventsForSession('runtime-session-contract'));

    final adapter = createRuntimeEventAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final events = await adapter
        .sessionEvents('runtime-session-contract')
        .toList();

    expect(events.map((event) => event.sessionId), <String>[
      'runtime-session-contract',
      'runtime-session-contract',
    ]);
    expect(events.map((event) => event.sequence), <int>[1, 2]);
    expect(events.map((event) => event.eventKind), <String>[
      'compile.started',
      'run.finished',
    ]);
  });

  test('unknown runtime event kind degrades to unsupported replay lane', () {
    final event = _event(
      sessionId: 'runtime-session-unknown',
      sequence: 1,
      eventKind: 'runtime.experimental.snapshot',
      payload: const <String, Object?>{'raw': 'opaque'},
    );

    final replay = summarizeRuntimeReplay(<RuntimeEventEnvelope>[event]);
    final graph = summarizeRuntimeGraph(<RuntimeEventEnvelope>[event]);

    expect(isKnownRuntimeEventKind(event.eventKind), isFalse);
    expect(runtimeEventFamily(event.eventKind), 'unsupported');
    expect(replay.families, <String>['unsupported']);
    expect(
      replay.lanes.single.detailLabel,
      'unsupported event kind runtime.experimental.snapshot · raw=opaque',
    );
    expect(
      graph.observedNodes,
      contains('unsupported event kind runtime.experimental.snapshot · raw=opaque'),
    );
    expect(
      formatRuntimeEvent(event),
      contains('unsupported event kind runtime.experimental.snapshot'),
    );
  });
}

RuntimeEventEnvelope _event({
  required String sessionId,
  required int sequence,
  required String eventKind,
  Map<String, Object?> payload = const <String, Object?>{},
}) {
  return RuntimeEventEnvelope(
    schemaVersion: 1,
    sessionId: sessionId,
    sequence: sequence,
    timestamp: DateTime.utc(2026, 5, 18, 0, 0, sequence),
    eventKind: eventKind,
    origin: 'test',
    payload: payload,
  );
}
