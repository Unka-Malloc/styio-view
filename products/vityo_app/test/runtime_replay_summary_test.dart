import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test('runtime replay summary handles empty event list', () {
    final replay = summarizeRuntimeReplay(const <RuntimeEventEnvelope>[]);
    final graph = summarizeRuntimeGraph(const <RuntimeEventEnvelope>[]);
    final debugLanes = summarizeRuntimeDebugLanes(
      const <RuntimeEventEnvelope>[],
    );

    expect(replay.events, isEmpty);
    expect(replay.latestEvent, isNull);
    expect(replay.windowLabel, 'No replay window.');
    expect(graph.routeNodes, isEmpty);
    expect(graph.summarySentence, 'No execution graph has been derived yet.');
    expect(debugLanes, isEmpty);
    expect(summarizeRuntimeDebugDigest(debugLanes), isNull);
  });

  test('runtime replay groups families and lane status accents', () {
    final events = <RuntimeEventEnvelope>[
      _event(1, 'compile.started', const <String, Object?>{'intent': 'run'}),
      _event(2, 'compile.failed', const <String, Object?>{'code': 'E_STYIO'}),
      _event(
        3,
        'unit.test.started',
        const <String, Object?>{'test_name': 'smoke'},
      ),
      _event(
        4,
        'unit.test.finished',
        const <String, Object?>{'test_name': 'smoke', 'success': true},
      ),
      _event(5, 'custom', const <String, Object?>{'value': 7}),
    ];

    final replay = summarizeRuntimeReplay(events);
    final compileLane = replay.lanes.firstWhere(
      (lane) => lane.family == 'compile',
    );
    final testLane = replay.lanes.firstWhere(
      (lane) => lane.family == 'unit.test',
    );
    final observedLane = replay.lanes.firstWhere(
      (lane) => lane.family == 'unsupported',
    );

    expect(runtimeEventFamily('unit.test.finished'), 'unit.test');
    expect(runtimeEventStatus('compile.failed'), 'failed');
    expect(replay.families, <String>['compile', 'unit.test', 'unsupported']);
    expect(replay.latestEvent!.eventKind, 'custom');
    expect(replay.windowLabel, 'Window 00:00:01 -> 00:00:05.');
    expect(compileLane.statusLabel, 'failed lane');
    expect(compileLane.accent, RuntimeAccent.failed);
    expect(compileLane.detailLabel, 'code=E_STYIO');
    expect(testLane.statusLabel, 'completed lane');
    expect(testLane.accent, RuntimeAccent.completed);
    expect(observedLane.statusLabel, 'observed lane');
    expect(observedLane.accent, RuntimeAccent.observed);
  });

  test('runtime graph summary derives route nodes, edges, and relations', () {
    final graph = summarizeRuntimeGraph(<RuntimeEventEnvelope>[
      _event(1, 'transition.fired', const <String, Object?>{
        'from': 'empty',
        'to': 'tokenized',
      }),
      _event(2, 'compile.started', const <String, Object?>{'intent': 'run'}),
      _event(3, 'state.changed', const <String, Object?>{'phase': 'parsed'}),
      _event(4, 'thread.spawned', const <String, Object?>{'thread_id': 'main'}),
      _event(5, 'log.emitted', const <String, Object?>{
        'stream': 'stdout',
        'message': 'ready',
      }),
      _event(6, 'run.finished', const <String, Object?>{'success': true}),
    ]);

    expect(graph.routeNodes, <String>[
      'empty',
      'tokenized',
      'compile.started',
      'run.finished',
    ]);
    expect(graph.transitionEdges, <String>['empty -> tokenized']);
    expect(graph.terminalNode, 'run.finished');
    expect(graph.routeTraceLabel, contains('empty -> tokenized'));
    expect(graph.observedDigestLabel, contains('phase=parsed'));
    expect(graph.observedDigestLabel, contains('thread_id=main'));
    expect(graph.summarySentence, contains('4 node(s) / 1 explicit edge(s)'));

    final emptyNode = graph.nodeDetails.firstWhere(
      (detail) => detail.label == 'empty',
    );
    final tokenizedNode = graph.nodeDetails.firstWhere(
      (detail) => detail.label == 'tokenized',
    );
    final edge = graph.edgeDetails.single;

    expect(emptyNode.outboundEdges, <String>['empty -> tokenized']);
    expect(emptyNode.relationLabel, 'out empty -> tokenized');
    expect(tokenizedNode.inboundEdges, <String>['empty -> tokenized']);
    expect(edge.filterTokens, <String>[
      'edge=empty -> tokenized',
      'event=transition.fired',
    ]);
    expect(edge.timelineLabel, 'transition.fired');
  });

  test('runtime debug lanes summarize thread, test, and log families', () {
    final lanes = summarizeRuntimeDebugLanes(<RuntimeEventEnvelope>[
      _event(1, 'thread.spawned', const <String, Object?>{'thread_id': 'main'}),
      _event(
        2,
        'unit.test.started',
        const <String, Object?>{'test_name': 'smoke'},
      ),
      _event(
        3,
        'unit.test.finished',
        const <String, Object?>{'test_name': 'smoke', 'success': true},
      ),
      _event(4, 'log.emitted', const <String, Object?>{
        'stream': 'stdout',
        'message': 'ok',
      }),
    ]);

    final thread = lanes.firstWhere((lane) => lane.family == 'thread');
    final test = lanes.firstWhere((lane) => lane.family == 'unit.test');
    final log = lanes.firstWhere((lane) => lane.family == 'log');

    expect(thread.title, 'Thread Lane');
    expect(thread.digestLabel, 'threads main');
    expect(thread.filterTokens, <String>['family=thread', 'thread_id=main']);
    expect(test.statusLabel, 'completed test lane');
    expect(test.traceLabel, 'unit.test.started -> unit.test.finished');
    expect(log.detailLabel, contains('stdout'));
    expect(log.detailLabel, contains('ok'));
    expect(log.accent, RuntimeAccent.log);
    final digest = summarizeRuntimeDebugDigest(lanes);
    expect(digest, contains('threads main'));
    expect(digest, contains('tests smoke'));
    expect(digest, contains('logs stdout'));
  });

  test('runtime payload formatting selects stable summary fields', () {
    final event = _event(
      7,
      'diagnostic.emitted',
      const <String, Object?>{'unit_id': 'demo/main', 'code': 'W1'},
    );

    expect(formatRuntimeClock(DateTime.utc(2026, 6, 19, 3, 4, 5)), '03:04:05');
    expect(runtimePayloadSummary(const <String, Object?>{}), isNull);
    expect(runtimePayloadSummary(event.payload), 'unit_id=demo/main');
    expect(runtimePayloadSuffix(event.payload), contains('unit_id=demo/main'));
    expect(formatRuntimeEvent(event), contains('[runtime #7] 00:00:07'));
    expect(formatRuntimeEvent(event), contains('diagnostic.emitted'));
    expect(formatRuntimeEvent(event), contains('unit_id=demo/main'));
  });
}

RuntimeEventEnvelope _event(
  int sequence,
  String eventKind,
  Map<String, Object?> payload,
) {
  return RuntimeEventEnvelope(
    schemaVersion: 1,
    sessionId: 'runtime-test',
    sequence: sequence,
    timestamp: DateTime.utc(2026, 6, 19, 0, 0, sequence),
    eventKind: eventKind,
    origin: 'test-origin',
    payload: payload,
  );
}
