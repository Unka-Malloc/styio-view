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

import 'package:flutter/foundation.dart';

import '../lib/src/view_ide/editor/document/document_state.dart';

/// Generates a document with [lineCount] lines of text.
DocumentState generateDocument(int lineCount, {String documentId = 'bench.styio'}) {
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
    final p50 = durations[(durations.length * 0.5).round().clamp(0, durations.length - 1)];
    final p95 = durations[(durations.length * 0.95).round().clamp(0, durations.length - 1)];
    final p99 = durations[(durations.length * 0.99).round().clamp(0, durations.length - 1)];
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
    final doc = generateDocument(size);
    final rng = Random(42);
    final r = BenchmarkRunner('random_insert_${size}lines').run(100, (_) {
      for (var j = 0; j < 10; j++) {
        final offset = rng.nextInt(doc.length);
        doc.replaceRange(start: offset, end: offset, replacement: 'x');
      }
    });
    results.add(r);
  }

  // 3. Random delete operations
  for (final size in [1000, 10000, 100000]) {
    final doc = generateDocument(size);
    final rng = Random(42);
    final r = BenchmarkRunner('random_delete_${size}lines').run(100, (_) {
      for (var j = 0; j < 10; j++) {
        final offset = rng.nextInt(doc.length - 1);
        doc.replaceRange(start: offset, end: offset + 1, replacement: '');
      }
    });
    results.add(r);
  }

  // 4. positionForOffset / offsetForLineColumn performance
  for (final size in [1000, 10000, 100000]) {
    final doc = generateDocument(size);
    final rng = Random(42);
    final offsets = List.generate(100, (_) => rng.nextInt(doc.length));
    final r = BenchmarkRunner('position_for_offset_${size}lines').run(100, (_) {
      for (final offset in offsets) {
        doc.positionForOffset(offset);
      }
    });
    results.add(r);

    final lines = doc.lines;
    final lineColumnPairs = List.generate(
      100,
      (_) => (line: rng.nextInt(lines.length), column: rng.nextInt(60)),
    );
    final r2 = BenchmarkRunner('offset_for_line_column_${size}lines').run(100, (_) {
      for (final pair in lineColumnPairs) {
        doc.offsetForLineColumn(line: pair.line, column: pair.column);
      }
    });
    results.add(r2);
  }

  // 5. Viewport text extraction (simulate rendering a range)
  for (final size in [1000, 10000, 100000]) {
    final doc = generateDocument(size);
    final r = BenchmarkRunner('viewport_extraction_${size}lines').run(100, (_) {
      // Simulate extracting 50 lines from the middle of the document
      final lines = doc.lines;
      final midLine = lines.length ~/ 2;
      final startLine = midLine.clamp(0, lines.length - 25);
      final endLine = (startLine + 50).clamp(0, lines.length);
      final start = doc.offsetForLineColumn(line: startLine, column: 0);
      final end = doc.offsetForLineColumn(
        line: endLine - 1,
        column: lines[endLine - 1].length,
      );
      doc.text.substring(start, end);
    });
    results.add(r);
  }

  // 6. lineStarts recomputation (potential O(n^2) hotspot)
  for (final size in [1000, 10000, 100000]) {
    final doc = generateDocument(size);
    final r = BenchmarkRunner('line_starts_recompute_${size}lines').run(100, (_) {
      doc.lineStarts;
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
