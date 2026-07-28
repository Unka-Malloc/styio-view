/// ALG-08: AI Context Benchmark
///
/// Benchmarks AI context packing and budget clipping:
/// - Packing time for various workspace sizes
/// - Budget clipping overhead
library;

import 'dart:math';

import 'alg01_piece_table_benchmark.dart';

enum ContextItemKind { documentSymbol, diagnostic, reference, semanticToken }

class ContextItem {
  final String id;
  final ContextItemKind kind;
  final int tokenCount;
  final String content;

  const ContextItem({
    required this.id,
    required this.kind,
    required this.tokenCount,
    required this.content,
  });
}

class AIContextBudget {
  final int maxTokens;

  const AIContextBudget({required this.maxTokens});

  /// Pack context items into budget.
  List<ContextItem> pack(List<ContextItem> items) {
    var usedTokens = 0;
    final packed = <ContextItem>[];

    for (final item in items) {
      final wouldUse = usedTokens + item.tokenCount;
      if (wouldUse > maxTokens) {
        // Budget clipping: truncate last item
        final remaining = maxTokens - usedTokens;
        if (remaining > 0) {
          packed.add(ContextItem(
            id: item.id,
            kind: item.kind,
            tokenCount: remaining,
            content: item.content.substring(0, remaining * 4),
          ));
        }
        break;
      }
      packed.add(item);
      usedTokens += item.tokenCount;
    }

    return packed;
  }

  /// Clip items to fit budget (alternative strategy: prioritize by kind).
  List<ContextItem> clipByPriority(List<ContextItem> items) {
    final priorityOrder = [
      ContextItemKind.diagnostic,
      ContextItemKind.documentSymbol,
      ContextItemKind.reference,
      ContextItemKind.semanticToken,
    ];

    final sorted = items.toList()
      ..sort((a, b) {
        final pa = priorityOrder.indexOf(a.kind);
        final pb = priorityOrder.indexOf(b.kind);
        return pa.compareTo(pb);
      });

    return pack(sorted);
  }
}

/// Generate context items.
List<ContextItem> generateContextItems(int count) {
  final rng = Random(42);
  final kinds = ContextItemKind.values;
  return List.generate(count, (i) {
    final tokenCount = 10 + rng.nextInt(100);
    return ContextItem(
      id: 'ctx_$i',
      kind: kinds[i % kinds.length],
      tokenCount: tokenCount,
      content: 'Context item $i content ${'x' * (tokenCount * 4)}',
    );
  });
}

/// Run all ALG-08 benchmarks.
List<Map<String, dynamic>> runAlg08Benchmarks() {
  final results = <Map<String, dynamic>>[];

  for (final size in [100, 1000, 10000]) {
    final items = generateContextItems(size);
    final budget = const AIContextBudget(maxTokens: 64000);

    // Packing time
    final r1 = BenchmarkRunner('context_packing_${size}items').run(100, (_) {
      budget.pack(items);
    });
    results.add(r1.toJson());

    // Budget clipping overhead
    final r2 = BenchmarkRunner('budget_clipping_${size}items').run(100, (_) {
      budget.clipByPriority(items);
    });
    results.add(r2.toJson());
  }

  return results;
}

void main() {
  print('=== ALG-08: AI Context Benchmarks ===');
  final results = runAlg08Benchmarks();
  for (final r in results) {
    print('  ${r['name']}: mean=${r['meanMs']}ms p95=${r['p95Ms']}ms');
  }
  print('');
}
