/// ALG-10: Virtualization Benchmark
///
/// Benchmarks list virtualization performance:
/// - Frame time for large lists with various item counts
/// - Scroll performance simulation
library;

import 'dart:math';

import 'alg01_piece_table_benchmark.dart';

class VirtualListItem {
  final int index;
  final double height;
  final String content;

  const VirtualListItem({
    required this.index,
    required this.height,
    required this.content,
  });
}

class VirtualListModel {
  final List<VirtualListItem> items;
  final double viewportHeight;

  const VirtualListModel({
    required this.items,
    required this.viewportHeight,
  });

  int get totalItems => items.length;

  /// Compute which items are visible in a viewport at [scrollOffset].
  List<VirtualListItem> visibleItems(double scrollOffset) {
    final result = <VirtualListItem>[];
    var y = 0.0;
    for (final item in items) {
      if (y + item.height > scrollOffset && y < scrollOffset + viewportHeight) {
        result.add(item);
      }
      y += item.height;
      if (y > scrollOffset + viewportHeight) break;
    }
    return result;
  }

  /// Compute total content height.
  double get totalHeight {
    double h = 0;
    for (final item in items) {
      h += item.height;
    }
    return h;
  }

  /// Compute the offset for a given item index.
  double offsetForIndex(int index) {
    double offset = 0;
    for (var i = 0; i < index && i < items.length; i++) {
      offset += items[i].height;
    }
    return offset;
  }
}

/// Generate virtual list items.
List<VirtualListItem> generateItems(int count) {
  final rng = Random(42);
  return List.generate(count, (i) {
    final height = 20.0 + rng.nextDouble() * 60.0; // 20-80px height
    return VirtualListItem(
      index: i,
      height: height,
      content: 'Item $i content ${'x' * (10 + rng.nextInt(90))}',
    );
  });
}

/// Run all ALG-10 benchmarks.
List<Map<String, dynamic>> runAlg10Benchmarks() {
  final results = <Map<String, dynamic>>[];

  for (final size in [100, 1000, 10000, 100000]) {
    final items = generateItems(size);
    final model = VirtualListModel(items: items, viewportHeight: 800);
    final rng = Random(99);

    // Visible items query (frame time simulation)
    final r1 = BenchmarkRunner('visible_items_query_${size}items').run(100, (_) {
      final offset = rng.nextDouble() * (model.totalHeight - 800);
      model.visibleItems(offset);
    });
    results.add(r1.toJson());

    // Offset calculation for a specific item
    final r2 = BenchmarkRunner('offset_for_index_${size}items').run(100, (_) {
      final idx = rng.nextInt(items.length);
      model.offsetForIndex(idx);
    });
    results.add(r2.toJson());

    // Total height computation
    final r3 = BenchmarkRunner('total_height_${size}items').run(100, (_) {
      model.totalHeight;
    });
    results.add(r3.toJson());
  }

  return results;
}

void main() {
  print('=== ALG-10: Virtualization Benchmarks ===');
  final results = runAlg10Benchmarks();
  for (final r in results) {
    print('  ${r['name']}: mean=${r['meanMs']}ms p95=${r['p95Ms']}ms');
  }
  print('');
}
