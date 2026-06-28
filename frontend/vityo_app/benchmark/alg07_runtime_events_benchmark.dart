/// ALG-07: Runtime Events Benchmark
///
/// Benchmarks runtime event processing:
/// - 1k/10k/100k events replay
/// - Log line filter
/// - Graph digest recompute
library;

import 'dart:math';

import 'alg01_piece_table_benchmark.dart';

enum EventType {
  logMessage,
  stateTransition,
  dataFlow,
  errorSignal,
  metricEmit,
}

class RuntimeEvent {
  final int timestamp;
  final EventType type;
  final String source;
  final String payload;

  const RuntimeEvent({
    required this.timestamp,
    required this.type,
    required this.source,
    required this.payload,
  });
}

class RuntimeReplayEngine {
  final List<RuntimeEvent> events;

  const RuntimeReplayEngine({required this.events});

  /// Replay all events sequentially.
  void replayAll() {
    for (final event in events) {
      _processEvent(event);
    }
  }

  /// Filter events by source and type.
  List<RuntimeEvent> filterEvents(String sourceFilter, EventType typeFilter) {
    return events.where((e) =>
      e.source.contains(sourceFilter) && e.type == typeFilter
    ).toList();
  }

  /// Recompute graph digest from all events.
  String recomputeDigest() {
    var digest = 0;
    for (final event in events) {
      digest ^= event.timestamp;
      digest = ((digest << 5) - digest) ^ event.type.hashCode;
    }
    return digest.toRadixString(16);
  }

  void _processEvent(RuntimeEvent event) {
    // Simulate processing by computing a hash
    final hash = event.timestamp ^ event.type.hashCode ^ event.payload.length;
    if (hash < 0) {
      throw StateError('unexpected');
    }
  }
}

/// Generate runtime events.
List<RuntimeEvent> generateEvents(int count) {
  final rng = Random(42);
  final types = EventType.values;
  final sources = ['renderer', 'compiler', 'analyzer', 'runtime', 'network'];
  return List.generate(count, (i) {
    return RuntimeEvent(
      timestamp: i,
      type: types[rng.nextInt(types.length)],
      source: sources[rng.nextInt(sources.length)],
      payload: 'event_$i payload with length ${rng.nextInt(200)}',
    );
  });
}

/// Run all ALG-07 benchmarks.
List<Map<String, dynamic>> runAlg07Benchmarks() {
  final results = <Map<String, dynamic>>[];

  for (final size in [1000, 10000, 100000]) {
    final events = generateEvents(size);
    final engine = RuntimeReplayEngine(events: events);

    // Events replay
    final r1 = BenchmarkRunner('events_replay_$size').run(100, (_) {
      engine.replayAll();
    });
    results.add(r1.toJson());

    // Log line filter
    final r2 = BenchmarkRunner('log_line_filter_$size').run(100, (_) {
      engine.filterEvents('runtime', EventType.logMessage);
    });
    results.add(r2.toJson());

    // Graph digest recompute
    final r3 = BenchmarkRunner('graph_digest_recompute_$size').run(100, (_) {
      engine.recomputeDigest();
    });
    results.add(r3.toJson());
  }

  return results;
}

void main() {
  print('=== ALG-07: Runtime Events Benchmarks ===');
  final results = runAlg07Benchmarks();
  for (final r in results) {
    print('  ${r['name']}: mean=${r['meanMs']}ms p95=${r['p95Ms']}ms');
  }
  print('');
}
