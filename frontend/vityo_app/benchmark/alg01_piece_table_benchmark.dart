/// ALG-01: Piece Table Benchmark
///
/// Benchmarks the editor's core document model for:
/// - Opening documents of varying sizes (1k, 10k, 100k lines)
/// - Random insertions (1k)
/// - Random deletions (1k)
/// - Undo of 1k edits
/// - Viewport text extraction
///
/// Targets:
/// - 10k lines typing p95 < 16ms
/// - 100k lines no O(n^2) behavior
library;

import 'dart:math';

import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/editor/document/text_buffer/text_buffer.dart';

/// Generates a document with [lineCount] lines of text.
DocumentState generateDocument(
  int lineCount, {
  String documentId = 'bench.styio',
}) {
  final lines = <String>[];
  for (var i = 0; i < lineCount; i++) {
    final lineLength = 40 + (i % 20);
    final line = String.fromCharCodes(
      List.generate(lineLength, (_) => 0x61 + Random(i * 9973).nextInt(26)),
    );
    lines.add(line);
  }
  return DocumentState(
    documentId: documentId,
    text: lines.join('\n') + (lineCount > 0 ? '\n' : ''),
    revision: 0,
  );
}

/// Benchmark result structure.
class BenchmarkResult {
  const BenchmarkResult({
    required this.name,
    required this.iterations,
    required this.totalDurationMs,
    required this.meanMs,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.minMs,
    required this.maxMs,
  });

  final String name;
  final int iterations;
  final double totalDurationMs;
  final double meanMs;
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
  final double minMs;
  final double maxMs;

  Map<String, dynamic> toJson() => {
    'name': name,
    'iterations': iterations,
    'totalDurationMs': totalDurationMs,
    'meanMs': meanMs,
    'p50Ms': p50Ms,
    'p95Ms': p95Ms,
    'p99Ms': p99Ms,
    'minMs': minMs,
    'maxMs': maxMs,
  };
}

/// Simple stopwatch-based benchmark helper.
class BenchmarkRunner {
  final String name;

  BenchmarkRunner(this.name);

  BenchmarkResult run(int iterations, void Function(int i) body) {
    final durations = <double>[];
    for (var i = 0; i < iterations; i++) {
      final sw = Stopwatch()..start();
      body(i);
      sw.stop();
      durations.add(sw.elapsedMicroseconds / 1000.0);
    }
    durations.sort();
    final total = durations.fold(0.0, (a, b) => a + b);
    final mean = total / durations.length;
    final p50Index = (durations.length * 0.5)
        .round()
        .clamp(0, durations.length - 1)
        .toInt();
    final p95Index = (durations.length * 0.95)
        .round()
        .clamp(0, durations.length - 1)
        .toInt();
    final p99Index = (durations.length * 0.99)
        .round()
        .clamp(0, durations.length - 1)
        .toInt();
    final p50 = durations[p50Index];
    final p95 = durations[p95Index];
    final p99 = durations[p99Index];
    final min = durations.first;
    final max = durations.last;

    return BenchmarkResult(
      name: name,
      iterations: iterations,
      totalDurationMs: total,
      meanMs: mean,
      p50Ms: p50,
      p95Ms: p95,
      p99Ms: p99,
      minMs: min,
      maxMs: max,
    );
  }
}

/// Run all ALG-01 benchmarks.
List<Map<String, dynamic>> runAlg01Benchmarks() {
  final results = <BenchmarkResult>[];

  // 1. Open documents of varying sizes
  for (final size in [1000, 10000, 100000]) {
    final r = BenchmarkRunner('open_document_${size}lines').run(50, (_) {
      generateDocument(size);
    });
    results.add(r);
  }

  // 2. Random insert operations
  for (final size in [1000, 10000, 100000]) {
    var buffer = generateDocument(size).textBuffer;
    final rng = Random(42);
    final r = BenchmarkRunner('random_insert_${size}lines').run(100, (_) {
      for (var j = 0; j < 10; j++) {
        final offset = rng.nextInt(buffer.length + 1);
        buffer = buffer.replace(
          TextRange(start: offset, end: offset),
          'x',
        );
      }
    });
    results.add(r);
  }

  // 3. Random delete operations
  for (final size in [1000, 10000, 100000]) {
    var buffer = generateDocument(size).textBuffer;
    final rng = Random(42);
    final r = BenchmarkRunner('random_delete_${size}lines').run(100, (_) {
      for (var j = 0; j < 10; j++) {
        if (buffer.length == 0) {
          continue;
        }
        final offset = rng.nextInt(buffer.length);
        buffer = buffer.replace(
          TextRange(start: offset, end: offset + 1),
          '',
        );
      }
    });
    results.add(r);
  }

  // 4. positionForOffset / offsetForLineColumn performance
  for (final size in [1000, 10000, 100000]) {
    final doc = generateDocument(size);
    final snapshot = doc.textBufferSnapshot;
    final rng = Random(42);
    final offsets = List.generate(100, (_) => rng.nextInt(snapshot.length));
    final r = BenchmarkRunner('position_for_offset_${size}lines').run(100, (_) {
      for (final offset in offsets) {
        snapshot.positionAt(offset);
      }
    });
    results.add(r);

    final lines = snapshot.lines;
    final lineColumnPairs = List.generate(
      100,
      (_) => (line: rng.nextInt(lines.length), column: rng.nextInt(60)),
    );
    final r2 = BenchmarkRunner(
      'offset_for_line_column_${size}lines',
    ).run(100, (_) {
      for (final pair in lineColumnPairs) {
        snapshot.offsetAt(TextPosition(line: pair.line, column: pair.column));
      }
    });
    results.add(r2);
  }

  // 5. Viewport text extraction (simulate rendering a range)
  for (final size in [1000, 10000, 100000]) {
    final doc = generateDocument(size);
    final snapshot = doc.textBufferSnapshot;
    final r = BenchmarkRunner('viewport_extraction_${size}lines').run(100, (_) {
      // Simulate extracting 50 lines from the middle of the document
      final lines = snapshot.lines;
      final midLine = lines.length ~/ 2;
      final startLine = midLine.clamp(0, lines.length - 25).toInt();
      final endLine = (startLine + 50).clamp(0, lines.length).toInt();
      final start = snapshot.offsetAt(
        TextPosition(line: startLine, column: 0),
      );
      final end = snapshot.offsetAt(
        TextPosition(line: endLine - 1, column: lines[endLine - 1].length),
      );
      snapshot.getText(TextRange(start: start, end: end));
    });
    results.add(r);
  }

  // 6. cached lineStarts query (guards against repeated split/scan hotspots)
  for (final size in [1000, 10000, 100000]) {
    final doc = generateDocument(size);
    final snapshot = doc.textBufferSnapshot;
    final r = BenchmarkRunner('line_starts_cached_${size}lines').run(100, (_) {
      snapshot.lineStarts;
    });
    results.add(r);
  }

  return results.map((r) => r.toJson()).toList();
}

void main() {
  print('=== ALG-01: Piece Table Benchmarks ===');
  final results = runAlg01Benchmarks();
  for (final r in results) {
    print('  ${r['name']}: mean=${r['meanMs']}ms p95=${r['p95Ms']}ms');
  }
  print('');
}
