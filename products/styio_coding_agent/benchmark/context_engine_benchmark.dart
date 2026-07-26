import 'dart:convert';

import 'package:styio_coding_agent/styio_coding_agent.dart';

Future<void> main() async {
  final source = _BenchmarkSource(10000);
  final cache = ContextCache(maxEntries: 64, maxBytes: 8192);
  final engine = ContextEngine(
    sources: <ContextSource>[source],
    cache: cache,
    maxCandidatesPerSource: 64,
  );
  final revisions = <String, int>{
    for (var index = 0; index < 10000; index += 1)
      'workspace://root/lib/$index.dart': 1,
  };
  final stopwatch = Stopwatch()..start();
  for (var run = 0; run < 20; run += 1) {
    await engine.select(
      ContextQuery(
        terms: const <String>['candidate'],
        roots: const <String>{'workspace://root/'},
        expectedRevisions: revisions,
      ),
      const ContextBudget(
        maxItems: 12,
        maxBytes: 2048,
        maxTokens: 128,
        reservedOutputTokens: 32,
      ),
      cancellation: AgentCancellationController().token,
    );
  }
  stopwatch.stop();
  if (source.maximumRequestedLimit > 64 ||
      cache.entryCount > cache.maxEntries ||
      cache.byteCount > cache.maxBytes ||
      cache.metrics.evictions == 0 ||
      stopwatch.elapsedMilliseconds > 3000) {
    throw StateError('Context benchmark exceeded a declared bound.');
  }
  print(
    jsonEncode(<String, Object>{
      'runs': 20,
      'elapsed_ms': stopwatch.elapsedMilliseconds,
      'maximum_requested_candidates': source.maximumRequestedLimit,
      'cache_entries': cache.entryCount,
      'cache_bytes': cache.byteCount,
      'cache_evictions': cache.metrics.evictions,
    }),
  );
}

final class _BenchmarkSource implements ContextSource {
  _BenchmarkSource(int count)
    : _items = List<ContextEvidence>.generate(
        count,
        (index) => ContextEvidence.create(
          id: 'candidate-$index',
          source: 'search',
          resource: 'workspace://root/lib/$index.dart',
          revision: 1,
          range: const ContextRange(start: 0, end: 8),
          sensitivity: ContextSensitivity.internal,
          baseScore: index.toDouble(),
          content: 'candidate $index',
          tokenCost: 3,
          provenance: const ContextProvenance(
            sourceId: 'benchmark',
            retrieval: 'bounded-page',
            sourceRevision: 1,
          ),
        ),
        growable: false,
      );

  @override
  String get id => 'benchmark';

  final List<ContextEvidence> _items;
  int maximumRequestedLimit = 0;
  int _cursor = 0;

  @override
  Future<ContextPage> fetch(
    ContextQuery query, {
    required int limit,
    required AgentCancellationToken cancellation,
  }) async {
    if (limit > maximumRequestedLimit) maximumRequestedLimit = limit;
    final start = _cursor;
    _cursor = (_cursor + limit) % _items.length;
    return ContextPage(
      items: _items.skip(start).take(limit).toList(growable: false),
      hasMore: start + limit < _items.length,
    );
  }
}
