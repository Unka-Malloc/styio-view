/// ALG-03: Decorations Benchmark
///
/// Benchmarks viewport decoration queries:
/// - 10k diagnostics viewport query
/// - 100k semantic spans viewport query
/// - Range update after edit
library;

import 'dart:math';

import 'package:vityo_app/src/view_ide/editor/document/range_index.dart' as editor_index;
import 'alg01_piece_table_benchmark.dart';

class SourceRange {
  final int start;
  final int end;
  const SourceRange({required this.start, required this.end});

  bool contains(int offset) => offset >= start && offset < end;
  bool intersects(SourceRange other) =>
      start < other.end && end > other.start;
}

enum DiagnosticSeverity { error, warning, info }

class Diagnostic {
  final SourceRange range;
  final String message;
  final DiagnosticSeverity severity;
  final String code;

  const Diagnostic({
    required this.range,
    required this.message,
    required this.severity,
    required this.code,
  });
}

enum SemanticKind { keyword, type, function, variable, comment, string, number }

class SemanticSpan {
  final SourceRange range;
  final SemanticKind kind;

  const SemanticSpan({required this.range, required this.kind});
}

/// Generate diagnostics spanning a document.
List<Diagnostic> generateDiagnostics(int count, int documentLength) {
  final rng = Random(42);
  final diagnostics = <Diagnostic>[];
  for (var i = 0; i < count; i++) {
    final start = rng.nextInt(documentLength - 20);
    final length = 1 + rng.nextInt(15);
    diagnostics.add(Diagnostic(
      range: SourceRange(start: start, end: start + length),
      message: 'Diagnostic $i',
      severity: DiagnosticSeverity.warning,
      code: 'W$i',
    ));
  }
  return diagnostics;
}

/// Generate semantic spans.
List<SemanticSpan> generateSemanticSpans(int count, int documentLength) {
  final rng = Random(42);
  final spans = <SemanticSpan>[];
  final kinds = SemanticKind.values;
  for (var i = 0; i < count; i++) {
    final start = rng.nextInt(documentLength - 5);
    final length = 1 + rng.nextInt(20);
    spans.add(SemanticSpan(
      range: SourceRange(start: start, end: start + length),
      kind: kinds[i % kinds.length],
    ));
  }
  return spans;
}

/// Run all ALG-03 benchmarks.
List<Map<String, dynamic>> runAlg03Benchmarks() {
  final results = <Map<String, dynamic>>[];

  // Test with various document sizes
  final docLength = 1000000; // ~1M char document
  final viewportStart = 400000;
  final viewportEnd = 450000; // ~50k char viewport
  final viewport = SourceRange(start: viewportStart, end: viewportEnd);

  // 10k diagnostics viewport query
  final diagnostics10k = generateDiagnostics(10000, docLength);
  final r1 = BenchmarkRunner('diagnostics_viewport_query_10k').run(100, (_) {
    var count = 0;
    for (final d in diagnostics10k) {
      if (d.range.intersects(viewport)) {
        count++;
      }
    }
    return; // prevent unused
  });
  results.add(r1.toJson());

  // 100k diagnostics viewport query
  final diagnostics100k = generateDiagnostics(100000, docLength);
  final r2 = BenchmarkRunner('diagnostics_viewport_query_100k').run(100, (_) {
    var count = 0;
    for (final d in diagnostics100k) {
      if (d.range.intersects(viewport)) {
        count++;
      }
    }
    return;
  });
  results.add(r2.toJson());

  final diagnostics100kIndex = editor_index.RangeIndex<Diagnostic>.fromValues(
    diagnostics100k,
    startOf: (diagnostic) => diagnostic.range.start,
    endOf: (diagnostic) => diagnostic.range.end,
    revision: 1,
  );
  final r2Indexed = BenchmarkRunner(
    'diagnostics_viewport_query_100k_indexed',
  ).run(100, (_) {
    diagnostics100kIndex.overlapQuery(
      start: viewport.start,
      end: viewport.end,
    );
  });
  results.add(r2Indexed.toJson());

  // 100k semantic spans viewport query
  final spans100k = generateSemanticSpans(100000, docLength);
  final r3 = BenchmarkRunner('semantic_spans_viewport_query_100k').run(100, (_) {
    var count = 0;
    for (final s in spans100k) {
      if (s.range.intersects(viewport)) {
        count++;
      }
    }
    return;
  });
  results.add(r3.toJson());

  final spans100kIndex = editor_index.RangeIndex<SemanticSpan>.fromValues(
    spans100k,
    startOf: (span) => span.range.start,
    endOf: (span) => span.range.end,
    revision: 1,
  );
  final r3Indexed = BenchmarkRunner(
    'semantic_spans_viewport_query_100k_indexed',
  ).run(
    100,
    (_) {
      spans100kIndex.overlapQuery(
        start: viewport.start,
        end: viewport.end,
      );
    },
  );
  results.add(r3Indexed.toJson());

  // Range update after edit (shift all positions after edit point)
  final editOffset = 200000;
  final delta = 50; // inserted 50 chars
  final r4 = BenchmarkRunner('diagnostics_range_update_after_edit_100k').run(100, (_) {
    final updated = <Diagnostic>[];
    for (final d in diagnostics100k) {
      if (d.range.start >= editOffset) {
        updated.add(Diagnostic(
          range: SourceRange(start: d.range.start + delta, end: d.range.end + delta),
          message: d.message,
          severity: d.severity,
          code: d.code,
        ));
      } else if (d.range.end > editOffset) {
        // Range straddles edit point
        updated.add(Diagnostic(
          range: SourceRange(start: d.range.start, end: d.range.end + delta),
          message: d.message,
          severity: d.severity,
          code: d.code,
        ));
      } else {
        updated.add(d);
      }
    }
  });
  results.add(r4.toJson());

  return results;
}

void main() {
  print('=== ALG-03: Decorations Benchmarks ===');
  final results = runAlg03Benchmarks();
  for (final r in results) {
    print('  ${r['name']}: mean=${r['meanMs']}ms p95=${r['p95Ms']}ms');
  }
  print('');
}
