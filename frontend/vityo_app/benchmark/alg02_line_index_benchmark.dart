/// ALG-02: LineIndex Benchmark
///
/// Benchmarks line-index operations:
/// - offset -> line lookup for various document sizes
/// - line -> offset lookup for various document sizes
/// - Edit-only-update-affected-range efficiency
library;

import 'dart:math';

import 'alg01_piece_table_benchmark.dart';

class LineIndex {
  /// Builds a line-start index from document text.
  static List<int> buildIndex(String text) {
    final starts = <int>[];
    starts.add(0);
    for (var i = 0; i < text.length; i++) {
      if (text[i] == '\n') {
        starts.add(i + 1);
      }
    }
    return starts;
  }

  /// Binary search to find the line for a given offset.
  static int offsetToLine(List<int> lineStarts, int offset) {
    var lo = 0;
    var hi = lineStarts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Get the start offset of a given line.
  static int lineToOffset(List<int> lineStarts, int line) {
    if (line < 0) return 0;
    if (line >= lineStarts.length) return lineStarts.last;
    return lineStarts[line];
  }

  /// Update line starts after an edit, only recomputing affected range.
  static List<int> updateAffectedRange(
    List<int> oldStarts,
    int editStart,
    int editEnd,
    String replacement,
  ) {
    // Find the line containing editStart
    final startLine = offsetToLine(oldStarts, editStart);

    // Find the line after editEnd
    final afterEditLine = offsetToLine(oldStarts, editEnd);

    // Build the prefix (unchanged lines before editStart)
    final prefix = oldStarts.sublist(0, startLine + 1);

    // Compute the delta from the edit
    final originalLength = editEnd - editStart;
    final newLength = replacement.length;
    final delta = newLength - originalLength;

    // Build suffix (unchanged lines after editEnd), shifted by delta
    final suffix = <int>[];
    for (var i = afterEditLine + 1; i < oldStarts.length; i++) {
      suffix.add(oldStarts[i] + delta);
    }

    return [...prefix, ...suffix];
  }

  /// Simple linear scan version for comparison (potential O(n)).
  static List<int> rebuildFull(String text) {
    return buildIndex(text);
  }
}

/// Generate benchmark text with lineStarts pre-built.
String generateTextForLines(int lineCount) {
  final rng = Random(42);
  final lines = <String>[];
  for (var i = 0; i < lineCount; i++) {
    final lineLength = 30 + (i % 30);
    final line = String.fromCharCodes(
      List.generate(lineLength, (_) => 0x61 + rng.nextInt(26)),
    );
    lines.add(line);
  }
  return lines.join('\n');
}

/// Run all ALG-02 benchmarks.
List<Map<String, dynamic>> runAlg02Benchmarks() {
  final results = <Map<String, dynamic>>[];
  final sizes = [100, 1000, 10000, 100000];

  for (final size in sizes) {
    final text = generateTextForLines(size);
    final lineStarts = LineIndex.buildIndex(text);
    final rng = Random(42);

    // offsetToLine benchmarks
    final r1 = BenchmarkRunner('offset_to_line_${size}lines').run(200, (_) {
      for (var j = 0; j < 50; j++) {
        final offset = rng.nextInt(text.length);
        LineIndex.offsetToLine(lineStarts, offset);
      }
    });
    results.add(r1.toJson());

    // lineToOffset benchmarks
    final r2 = BenchmarkRunner('line_to_offset_${size}lines').run(200, (_) {
      for (var j = 0; j < 50; j++) {
        final line = rng.nextInt(lineStarts.length);
        LineIndex.lineToOffset(lineStarts, line);
      }
    });
    results.add(r2.toJson());

    // Edit-only-update-affected-range vs full rebuild
    final r3 = BenchmarkRunner('update_affected_range_${size}lines').run(200, (_) {
      final editStart = text.length ~/ 2;
      final editEnd = editStart + 5;
      LineIndex.updateAffectedRange(lineStarts, editStart, editEnd, 'REPLACEMENT');
    });
    results.add(r3.toJson());

    // Full rebuild for comparison
    final r4 = BenchmarkRunner('full_rebuild_${size}lines').run(200, (_) {
      LineIndex.rebuildFull(text);
    });
    results.add(r4.toJson());
  }

  return results;
}

void main() {
  print('=== ALG-02: LineIndex Benchmarks ===');
  final results = runAlg02Benchmarks();
  for (final r in results) {
    print('  ${r['name']}: mean=${r['meanMs']}ms p95=${r['p95Ms']}ms');
  }
  print('');
}
