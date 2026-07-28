import 'dart:async';

import 'package:vityo_coding_agent/vityo_coding_agent.dart';
import 'package:test/test.dart';

void main() {
  test('context selection fails before fetching after its deadline', () async {
    final source = _CountingSource();
    final engine = ContextEngine(
      sources: <ContextSource>[source],
      cache: ContextCache(maxEntries: 1, maxBytes: 16),
      maxCandidatesPerSource: 1,
      clock: () => DateTime.utc(2026, 1, 2),
    );
    await expectLater(
      engine.select(
        ContextQuery(
          terms: const <String>[],
          roots: const <String>{'workspace://root/'},
          expectedRevisions: const <String, int>{},
          deadline: DateTime.utc(2026, 1, 1),
        ),
        const ContextBudget(
          maxItems: 1,
          maxBytes: 16,
          maxTokens: 2,
          reservedOutputTokens: 1,
        ),
        cancellation: AgentCancellationController().token,
      ),
      throwsA(
        isA<ContextEngineFailure>().having(
          (error) => error.code,
          'code',
          ContextEngineFailureCode.deadline,
        ),
      ),
    );
    expect(source.fetchCount, 0);
  });

  test('a hanging source becomes a typed deadline failure', () async {
    final engine = ContextEngine(
      sources: <ContextSource>[_NeverSource()],
      cache: ContextCache(maxEntries: 1, maxBytes: 16),
      maxCandidatesPerSource: 1,
    );
    final bundle = await engine.select(
      ContextQuery(
        terms: const <String>[],
        roots: const <String>{'workspace://root/'},
        expectedRevisions: const <String, int>{},
        deadline: DateTime.now().add(const Duration(milliseconds: 20)),
      ),
      const ContextBudget(
        maxItems: 1,
        maxBytes: 16,
        maxTokens: 2,
        reservedOutputTokens: 1,
      ),
      cancellation: AgentCancellationController().token,
    );
    expect(
      bundle.sourceFailures.single.code,
      ContextSourceFailureCode.deadline,
    );
  });

  test('evidence retains source-level truncation metadata', () {
    final evidence = ContextEvidence.create(
      id: 'truncated',
      source: 'search',
      resource: 'workspace://root/a.dart',
      revision: 1,
      range: const ContextRange(start: 0, end: 3),
      sensitivity: ContextSensitivity.internal,
      baseScore: 1,
      content: 'abc',
      tokenCost: 1,
      provenance: const ContextProvenance(
        sourceId: 'search',
        retrieval: 'fixture',
        sourceRevision: 1,
      ),
      truncated: true,
    );
    expect(evidence.truncated, isTrue);
  });

  test('LRU invalidates only stale revisions for a resource', () {
    final cache = ContextCache(maxEntries: 2, maxBytes: 32);
    const old = ContextCacheKey(
      evidenceId: 'old',
      resource: 'workspace://root/a.dart',
      revision: 1,
    );
    const other = ContextCacheKey(
      evidenceId: 'other',
      resource: 'workspace://root/b.dart',
      revision: 1,
    );
    cache.put(old, 'old');
    cache.put(other, 'other');
    cache.invalidateResource(old.resource, currentRevision: 2);
    expect(cache.get(old), isNull);
    expect(cache.get(other), 'other');
  });

  test('conversation compaction keeps a bounded hot tail', () {
    final result = const ConversationCompactor().compact(
      <ConversationTurn>[
        ConversationTurn(
          id: 'secret',
          revision: 1,
          text: 'do-not-copy',
          tokenCost: 2,
          sensitivity: ContextSensitivity.secret,
        ),
        ConversationTurn(
          id: 'hot',
          revision: 2,
          text: 'visible',
          tokenCost: 2,
          sensitivity: ContextSensitivity.internal,
        ),
      ],
      maxHotTurns: 1,
      maxSummaryTokens: 4,
    );
    expect(result.hotTurns.single.id, 'hot');
    expect(result.summary, isNot(contains('do-not-copy')));
    expect(result.redactedTurnCount, 1);
  });

  test('conversation compaction redacts secrets inside the hot tail', () {
    final result = const ConversationCompactor().compact(
      const <ConversationTurn>[
        ConversationTurn(
          id: 'secret-hot',
          revision: 1,
          text: 'must-not-escape',
          tokenCost: 2,
          sensitivity: ContextSensitivity.secret,
        ),
      ],
      maxHotTurns: 1,
      maxSummaryTokens: 0,
    );
    expect(result.hotTurns.single.text, '[redacted]');
    expect(result.redactedTurnCount, 1);
  });
}

final class _CountingSource implements ContextSource {
  @override
  String get id => 'counting';

  int fetchCount = 0;

  @override
  Future<ContextPage> fetch(
    ContextQuery query, {
    required int limit,
    required AgentCancellationToken cancellation,
  }) async {
    fetchCount += 1;
    return ContextPage(items: const <ContextEvidence>[], hasMore: false);
  }
}

final class _NeverSource implements ContextSource {
  @override
  String get id => 'never';

  @override
  Future<ContextPage> fetch(
    ContextQuery query, {
    required int limit,
    required AgentCancellationToken cancellation,
  }) => Completer<ContextPage>().future;
}
