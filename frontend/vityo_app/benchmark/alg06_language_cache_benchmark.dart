/// ALG-06: Language Cache Benchmark
///
/// Benchmarks language service cache operations:
/// - Cache hit latency
/// - Cache miss latency
/// - Invalidation overhead
/// - Eviction overhead
library;

import 'dart:math';

import 'alg01_piece_table_benchmark.dart';

class AnalysisCacheEntry {
  final String contentHash;
  final dynamic analysis;
  final DateTime createdAt;

  const AnalysisCacheEntry({
    required this.contentHash,
    required this.analysis,
    required this.createdAt,
  });
}

class LanguageAnalysisCache {
  final int maxSize;
  final Map<String, AnalysisCacheEntry> _cache = {};
  final List<String> _accessOrder = [];

  LanguageAnalysisCache({this.maxSize = 100});

  /// Try to get from cache.
  AnalysisCacheEntry? get(String contentHash) {
    final entry = _cache[contentHash];
    if (entry != null) {
      _accessOrder.remove(contentHash);
      _accessOrder.add(contentHash);
    }
    return entry;
  }

  /// Put an entry in the cache.
  void put(String contentHash, AnalysisCacheEntry entry) {
    if (_cache.length >= maxSize && !_cache.containsKey(contentHash)) {
      _evictOne();
    }
    _cache[contentHash] = entry;
    _accessOrder.remove(contentHash);
    _accessOrder.add(contentHash);
  }

  /// Invalidate entries.
  void invalidate(String contentHash) {
    _cache.remove(contentHash);
    _accessOrder.remove(contentHash);
  }

  /// Evict least recently used.
  void _evictOne() {
    if (_accessOrder.isNotEmpty) {
      final oldest = _accessOrder.removeAt(0);
      _cache.remove(oldest);
    }
  }

  int get size => _cache.length;
}

class TextDocument {
  final String text;
  final String contentHash;

  TextDocument(this.text, this.contentHash);
}

/// Generate text documents.
List<TextDocument> generateDocuments(int count, int sizePerDoc) {
  final rng = Random(42);
  return List.generate(count, (i) {
    final text = String.fromCharCodes(
      List.generate(sizePerDoc, (_) => 0x20 + rng.nextInt(95)),
    );
    return TextDocument(text, 'hash_${i}_${text.length}');
  });
}

/// Run all ALG-06 benchmarks.
List<Map<String, dynamic>> runAlg06Benchmarks() {
  final results = <Map<String, dynamic>>[];

  final cache = LanguageAnalysisCache(maxSize: 1000);
  final docs = generateDocuments(2000, 5000);
  final analyses = docs.map((d) => AnalysisCacheEntry(
    contentHash: d.contentHash,
    analysis: 'analysis_result_for_${d.contentHash}',
    createdAt: DateTime.now(),
  )).toList();

  // Pre-populate first 500 entries
  for (var i = 0; i < 500; i++) {
    cache.put(docs[i].contentHash, analyses[i]);
  }

  // Cache hit latency
  final r1 = BenchmarkRunner('cache_hit_latency').run(1000, (_) {
    final idx = Random(99).nextInt(500);
    cache.get(docs[idx].contentHash);
  });
  results.add(r1.toJson());

  // Cache miss latency
  final r2 = BenchmarkRunner('cache_miss_latency').run(1000, (_) {
    cache.get('nonexistent_hash_${Random(99).nextInt(99999)}');
  });
  results.add(r2.toJson());

  // Invalidation overhead
  final r3 = BenchmarkRunner('cache_invalidation_overhead').run(500, (_) {
    cache.invalidate(docs[Random(99).nextInt(500)].contentHash);
    // Re-add for next iteration
    final idx = Random(99).nextInt(500);
    cache.put(docs[idx].contentHash, analyses[idx]);
  });
  results.add(r3.toJson());

  // Eviction overhead (putting beyond capacity)
  final fullCache = LanguageAnalysisCache(maxSize: 500);
  // Fill to full
  for (var i = 0; i < 500; i++) {
    fullCache.put(docs[i].contentHash, analyses[i]);
  }
  final r4 = BenchmarkRunner('cache_eviction_overhead').run(500, (_) {
    fullCache.put('new_hash_${Random(99).nextInt(99999)}', AnalysisCacheEntry(
      contentHash: 'new',
      analysis: 'new_analysis',
      createdAt: DateTime.now(),
    ));
  });
  results.add(r4.toJson());

  return results;
}

void main() {
  print('=== ALG-06: Language Cache Benchmarks ===');
  final results = runAlg06Benchmarks();
  for (final r in results) {
    print('  ${r['name']}: mean=${r['meanMs']}ms p95=${r['p95Ms']}ms');
  }
  print('');
}
