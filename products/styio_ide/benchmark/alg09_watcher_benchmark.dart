/// ALG-09: Watcher Benchmark
///
/// Benchmarks file watcher and event handling:
/// - Burst event handling
/// - Overflow detection
library;

import 'dart:math';

import 'alg01_piece_table_benchmark.dart';

enum FileChangeType { created, modified, deleted }

class FileEvent {
  final String path;
  final FileChangeType type;
  final int timestamp;

  const FileEvent({
    required this.path,
    required this.type,
    required this.timestamp,
  });
}

class FileWatcher {
  final int maxBatchSize;
  final int debounceMs;
  final List<FileEvent> _pending = [];
  final List<List<FileEvent>> _processedBatches = [];
  bool _overflowed = false;

  FileWatcher({this.maxBatchSize = 1000, this.debounceMs = 100});

  /// Handle a single event.
  void handleEvent(FileEvent event) {
    _pending.add(event);
    if (_pending.length >= maxBatchSize) {
      _flush();
      _overflowed = true;
    }
  }

  /// Handle a burst of events.
  void handleBurst(List<FileEvent> events) {
    for (final event in events) {
      _pending.add(event);
      if (_pending.length >= maxBatchSize) {
        _flush();
        _overflowed = true;
      }
    }
    _flush();
  }

  /// Debounced flush.
  void _flush() {
    if (_pending.isEmpty) return;
    _processedBatches.add(List.from(_pending));
    _pending.clear();
  }

  bool get hasOverflowed => _overflowed;
  int get processedCount =>
      _processedBatches.fold(0, (sum, batch) => sum + batch.length);
}

/// Generate file events.
List<FileEvent> generateFileEvents(int count) {
  final rng = Random(42);
  final types = FileChangeType.values;
  return List.generate(count, (i) {
    return FileEvent(
      path: '/path/to/file_${i % 100}.styio',
      type: types[rng.nextInt(types.length)],
      timestamp: i,
    );
  });
}

/// Run all ALG-09 benchmarks.
List<Map<String, dynamic>> runAlg09Benchmarks() {
  final results = <Map<String, dynamic>>[];

  // Burst event handling with varying burst sizes
  for (final burstSize in [100, 1000, 10000]) {
    final watcher = FileWatcher(maxBatchSize: 1000);
    final events = generateFileEvents(burstSize);

    final r1 = BenchmarkRunner('burst_event_handling_$burstSize').run(100, (_) {
      watcher.handleBurst(events);
    });
    results.add(r1.toJson());
  }

  // Overflow detection (burst larger than maxBatchSize)
  final overflowWatcher = FileWatcher(maxBatchSize: 500);
  final overflowEvents = generateFileEvents(2000);
  final r2 = BenchmarkRunner('overflow_detection_2000burst').run(100, (_) {
    overflowWatcher.handleBurst(overflowEvents);
  });
  results.add(r2.toJson());

  return results;
}

void main() {
  print('=== ALG-09: Watcher Benchmarks ===');
  final results = runAlg09Benchmarks();
  for (final r in results) {
    print('  ${r['name']}: mean=${r['meanMs']}ms p95=${r['p95Ms']}ms');
  }
  print('');
}
