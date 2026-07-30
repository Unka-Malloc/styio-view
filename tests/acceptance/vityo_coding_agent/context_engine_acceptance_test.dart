import 'package:vityo_coding_agent/vityo_coding_agent.dart';

Future<void> main() async {
  await _selectsDeterministicallyUnderRevisionAndSensitivityBudgets();
  _invalidatesOnlyAffectedCacheEntries();
  _compactsConversationDeterministicallyAndRedactsSecrets();
  await _boundsSourceRetrievalAndReportsTypedFailures();
}

Future<void>
_selectsDeterministicallyUnderRevisionAndSensitivityBudgets() async {
  final diagnostics = _FakeSource(
    id: 'diagnostics',
    evidence: <ContextEvidence>[
      _evidence(
        id: 'stale',
        source: 'diagnostics',
        resource: 'workspace://root/lib/old.dart',
        revision: 1,
        content: 'target stale diagnostic',
        score: 100,
      ),
      _evidence(
        id: 'current',
        source: 'diagnostics',
        resource: 'workspace://root/lib/main.dart',
        revision: 2,
        content: 'target current diagnostic',
        score: 40,
      ),
      _evidence(
        id: 'secret',
        source: 'diagnostics',
        resource: 'workspace://root/.secret',
        revision: 1,
        content: 'credential-value-must-not-escape',
        score: 1000,
        sensitivity: ContextSensitivity.secret,
      ),
    ],
  );
  final search = _FakeSource(
    id: 'search',
    evidence: <ContextEvidence>[
      _evidence(
        id: 'attachment',
        source: 'attachment',
        resource: 'workspace://root/README.md',
        revision: 3,
        content: 'explicit low score evidence',
        score: 1,
      ),
      _evidence(
        id: 'duplicate-current',
        source: 'search',
        resource: 'workspace://root/lib/main.dart',
        revision: 2,
        content: 'target current diagnostic',
        score: 90,
      ),
      _evidence(
        id: 'outside-root',
        source: 'search',
        resource: 'workspace://other/private.dart',
        revision: 1,
        content: 'target outside approved root',
        score: 500,
      ),
      _evidence(
        id: 'ranked',
        source: 'search',
        resource: 'workspace://root/lib/helper.dart',
        revision: 1,
        content: 'target helper implementation',
        score: 30,
      ),
    ],
  );
  final query = ContextQuery(
    terms: const <String>['target'],
    roots: const <String>{'workspace://root/'},
    expectedRevisions: const <String, int>{
      'workspace://root/lib/old.dart': 2,
      'workspace://root/lib/main.dart': 2,
      'workspace://root/README.md': 3,
      'workspace://root/lib/helper.dart': 1,
    },
    explicitEvidenceIds: const <String>{'attachment'},
    maximumSensitivity: ContextSensitivity.confidential,
  );
  const budget = ContextBudget(
    maxItems: 3,
    maxBytes: 512,
    maxTokens: 64,
    reservedOutputTokens: 16,
    perSourceCaps: <String, int>{'diagnostics': 2, 'search': 1},
  );
  final first = await ContextEngine(
    sources: <ContextSource>[diagnostics, search],
    cache: ContextCache(maxEntries: 8, maxBytes: 2048),
    maxCandidatesPerSource: 8,
  ).select(
    query,
    budget,
    cancellation: AgentCancellationController().token,
  );
  final second = await ContextEngine(
    sources: <ContextSource>[search, diagnostics],
    cache: ContextCache(maxEntries: 8, maxBytes: 2048),
    maxCandidatesPerSource: 8,
  ).select(
    query,
    budget,
    cancellation: AgentCancellationController().token,
  );

  final firstIds = first.items.map((item) => item.evidence.id).toList();
  final secondIds = second.items.map((item) => item.evidence.id).toList();
  _expect(firstIds.toString() == secondIds.toString(), 'selection must be stable');
  _expect(firstIds.first == 'attachment', 'explicit evidence must be hard included');
  _expect(!firstIds.contains('stale'), 'stale revisions must be rejected');
  _expect(!firstIds.contains('secret'), 'secret evidence must not enter the bundle');
  _expect(!firstIds.contains('outside-root'), 'unapproved roots must be rejected');
  _expect(
    !firstIds.contains('duplicate-current') && first.deduplicatedCount == 1,
    'same digest/resource evidence must be deterministically deduplicated',
  );
  _expect(
    first.totalBytes <= budget.maxBytes &&
        first.totalTokens + budget.reservedOutputTokens <= budget.maxTokens,
    'packed context must obey byte and reserved token budgets',
  );
  _expect(
    first.staleCount == 1 &&
        first.redactedCount == 1 &&
        first.rootDeniedCount == 1 &&
        first.truncated,
    'all exclusions and truncation must remain visible',
  );
  _expect(
    first.items.every(
      (item) =>
          item.evidence.provenance.sourceId.isNotEmpty &&
          item.evidence.contentDigest.length == 64,
    ),
    'selected evidence must retain provenance and a SHA-256 digest',
  );
}

void _invalidatesOnlyAffectedCacheEntries() {
  final cache = ContextCache(maxEntries: 2, maxBytes: 64);
  final a1 = const ContextCacheKey(
    evidenceId: 'a',
    resource: 'workspace://root/a.dart',
    revision: 1,
  );
  final b1 = const ContextCacheKey(
    evidenceId: 'b',
    resource: 'workspace://root/b.dart',
    revision: 1,
  );
  final c1 = const ContextCacheKey(
    evidenceId: 'c',
    resource: 'workspace://root/c.dart',
    revision: 1,
  );
  cache.put(a1, 'alpha');
  cache.put(b1, 'bravo');
  _expect(cache.get(a1) == 'alpha', 'cache hit must return materialized content');
  cache.put(c1, 'charlie');
  _expect(cache.get(b1) == null, 'least-recently-used entry must be evicted');
  _expect(cache.get(c1) == 'charlie', 'unrelated entry must remain cached');
  cache.invalidateResource('workspace://root/a.dart', currentRevision: 2);
  _expect(cache.get(a1) == null, 'stale resource revision must be invalidated');
  _expect(cache.get(c1) == 'charlie', 'invalidation must be resource-local');
  _expect(
    cache.metrics.evictions == 1 &&
        cache.metrics.hits >= 3 &&
        cache.metrics.misses >= 2 &&
        cache.entryCount <= 2 &&
        cache.byteCount <= 64,
    'cache metrics and bounds must be explicit',
  );
}

void _compactsConversationDeterministicallyAndRedactsSecrets() {
  final turns = <ConversationTurn>[
    for (var index = 0; index < 12; index += 1)
      ConversationTurn(
        id: 'turn-$index',
        revision: index,
        text: index == 4 ? 'private-token-value' : 'message $index evidence',
        tokenCost: 3,
        sensitivity: index == 4
            ? ContextSensitivity.secret
            : ContextSensitivity.internal,
      ),
  ];
  const compactor = ConversationCompactor();
  final first = compactor.compact(
    turns,
    maxHotTurns: 3,
    maxSummaryTokens: 18,
  );
  final second = compactor.compact(
    turns,
    maxHotTurns: 3,
    maxSummaryTokens: 18,
  );
  _expect(
    first.summary == second.summary &&
        first.summaryDigest == second.summaryDigest,
    'conversation compaction must be deterministic',
  );
  _expect(
    first.hotTurns.map((turn) => turn.id).join(',') ==
        'turn-9,turn-10,turn-11',
    'the bounded hot window must retain the latest turns in order',
  );
  _expect(
    first.omittedTurnCount == 9 &&
        first.redactedTurnCount == 1 &&
        !first.summary.contains('private-token-value') &&
        first.truncated,
    'compaction must expose omission and redact secret turns',
  );
}

Future<void> _boundsSourceRetrievalAndReportsTypedFailures() async {
  final healthy = _FakeSource(
    id: 'healthy',
    evidence: <ContextEvidence>[
      for (var index = 0; index < 10000; index += 1)
        _evidence(
          id: 'item-$index',
          source: 'healthy',
          resource: 'workspace://root/lib/$index.dart',
          revision: 1,
          content: 'candidate $index',
          score: index.toDouble(),
        ),
    ],
  );
  final unavailable = _FakeSource(
    id: 'unavailable',
    failure: const ContextSourceFailure(
      code: ContextSourceFailureCode.unavailable,
      message: 'index unavailable',
    ),
  );
  final engine = ContextEngine(
    sources: <ContextSource>[healthy, unavailable],
    cache: ContextCache(maxEntries: 4, maxBytes: 256),
    maxCandidatesPerSource: 32,
  );
  final bundle = await engine.select(
    ContextQuery(
      terms: const <String>['candidate'],
      roots: const <String>{'workspace://root/'},
      expectedRevisions: <String, int>{
        for (var index = 0; index < 10000; index += 1)
          'workspace://root/lib/$index.dart': 1,
      },
    ),
    const ContextBudget(
      maxItems: 4,
      maxBytes: 128,
      maxTokens: 24,
      reservedOutputTokens: 4,
    ),
    cancellation: AgentCancellationController().token,
  );
  _expect(
    healthy.requestedLimits.single == 32 && healthy.fetchCount == 1,
    'one turn must request only a bounded page, never scan the whole source',
  );
  _expect(
    bundle.sourceFailures.single.sourceId == 'unavailable' &&
        bundle.sourceFailures.single.code ==
            ContextSourceFailureCode.unavailable,
    'independent source failure must remain typed and observable',
  );

  final cancellation = AgentCancellationController()..cancel();
  await _expectContextFailure(
    () => engine.select(
      ContextQuery(
        terms: const <String>['cancel'],
        roots: const <String>{'workspace://root/'},
        expectedRevisions: const <String, int>{},
      ),
      const ContextBudget(
        maxItems: 1,
        maxBytes: 16,
        maxTokens: 4,
        reservedOutputTokens: 1,
      ),
      cancellation: cancellation.token,
    ),
    ContextEngineFailureCode.cancelled,
  );
}

ContextEvidence _evidence({
  required String id,
  required String source,
  required String resource,
  required int revision,
  required String content,
  required double score,
  ContextSensitivity sensitivity = ContextSensitivity.internal,
}) => ContextEvidence.create(
  id: id,
  source: source,
  resource: resource,
  revision: revision,
  range: const ContextRange(start: 0, end: 10),
  sensitivity: sensitivity,
  baseScore: score,
  content: content,
  tokenCost: 4,
  provenance: ContextProvenance(
    sourceId: source,
    retrieval: 'fixture',
    sourceRevision: revision,
  ),
);

final class _FakeSource implements ContextSource {
  _FakeSource({
    required this.id,
    List<ContextEvidence> evidence = const <ContextEvidence>[],
    this.failure,
  }) : _evidence = List<ContextEvidence>.unmodifiable(evidence);

  @override
  final String id;
  final List<ContextEvidence> _evidence;
  final ContextSourceFailure? failure;
  int fetchCount = 0;
  final List<int> requestedLimits = <int>[];

  @override
  Future<ContextPage> fetch(
    ContextQuery query, {
    required int limit,
    required AgentCancellationToken cancellation,
  }) async {
    fetchCount += 1;
    requestedLimits.add(limit);
    if (failure case final value?) {
      throw value;
    }
    return ContextPage(
      items: _evidence.take(limit).toList(growable: false),
      hasMore: _evidence.length > limit,
    );
  }
}

Future<void> _expectContextFailure(
  Future<Object?> Function() action,
  ContextEngineFailureCode code,
) async {
  try {
    await action();
  } on ContextEngineFailure catch (error) {
    _expect(error.code == code, 'expected ${code.name}, got ${error.code.name}');
    return;
  }
  throw StateError('expected ContextEngineFailure(${code.name})');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
