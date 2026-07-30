/// Deterministic bounded context selection.
library;

import 'dart:async';

import '../cancellation.dart';
import 'context_cache.dart';
import 'context_evidence.dart';
import 'context_ranker.dart';

final class SelectedContextItem {
  const SelectedContextItem({required this.evidence, required this.score});

  final ContextEvidence evidence;
  final double score;
}

final class ContextBundle {
  ContextBundle({
    required List<SelectedContextItem> items,
    required this.totalBytes,
    required this.totalTokens,
    required this.deduplicatedCount,
    required this.staleCount,
    required this.redactedCount,
    required this.rootDeniedCount,
    required this.truncated,
    required List<ContextSourceFailure> sourceFailures,
  }) : items = List<SelectedContextItem>.unmodifiable(items),
       sourceFailures = List<ContextSourceFailure>.unmodifiable(sourceFailures);

  final List<SelectedContextItem> items;
  final int totalBytes;
  final int totalTokens;
  final int deduplicatedCount;
  final int staleCount;
  final int redactedCount;
  final int rootDeniedCount;
  final bool truncated;
  final List<ContextSourceFailure> sourceFailures;
}

final class ContextEngine {
  ContextEngine({
    required List<ContextSource> sources,
    required this.cache,
    required this.maxCandidatesPerSource,
    ContextRanker ranker = const ContextRanker(),
    DateTime Function()? clock,
  }) : sources = List<ContextSource>.unmodifiable(sources),
       _ranker = ranker,
       _clock = clock ?? DateTime.now {
    if (maxCandidatesPerSource <= 0) {
      throw ArgumentError.value(
        maxCandidatesPerSource,
        'maxCandidatesPerSource',
      );
    }
  }

  final List<ContextSource> sources;
  final ContextCache cache;
  final int maxCandidatesPerSource;
  final ContextRanker _ranker;
  final DateTime Function() _clock;

  Future<ContextBundle> select(
    ContextQuery query,
    ContextBudget budget, {
    required AgentCancellationToken cancellation,
  }) async {
    _validateBudget(budget);
    _throwIfCancelled(cancellation);
    _throwIfDeadlineReached(query);

    final results = await Future.wait(
      sources.map((source) => _fetch(source, query, cancellation)),
    );
    _throwIfCancelled(cancellation);

    final failures = <ContextSourceFailure>[];
    final candidates = <ContextEvidence>[];
    var sourceTruncated = false;
    for (final result in results) {
      if (result.failure case final failure?) {
        failures.add(failure);
      } else if (result.page case final page?) {
        candidates.addAll(page.items);
        sourceTruncated = sourceTruncated || page.hasMore;
      }
    }

    final eligible = <ContextEvidence>[];
    var staleCount = 0;
    var redactedCount = 0;
    var rootDeniedCount = 0;
    for (final evidence in candidates) {
      if (!_insideAnyRoot(evidence.resource, query.roots)) {
        rootDeniedCount += 1;
        continue;
      }
      if (evidence.sensitivity.index > query.maximumSensitivity.index) {
        redactedCount += 1;
        continue;
      }
      final expected = query.expectedRevisions[evidence.resource];
      if (expected == null || expected != evidence.revision) {
        staleCount += 1;
        continue;
      }
      final cacheKey = ContextCacheKey(
        evidenceId: evidence.id,
        resource: evidence.resource,
        revision: evidence.revision,
      );
      if (cache.get(cacheKey) == null) {
        cache.put(cacheKey, evidence.content);
      }
      eligible.add(evidence);
    }

    final ranking = _ranker.rank(eligible, query);
    final selected = <SelectedContextItem>[];
    final sourceCounts = <String, int>{};
    final availableTokens = budget.maxTokens - budget.reservedOutputTokens;
    var bytes = 0;
    var tokens = 0;
    var packingTruncated = false;
    for (final candidate in ranking.candidates) {
      final evidence = candidate.evidence;
      final cap = budget.perSourceCaps[evidence.source];
      final sourceCount = sourceCounts[evidence.source] ?? 0;
      final fits =
          selected.length < budget.maxItems &&
          bytes + evidence.byteCost <= budget.maxBytes &&
          tokens + evidence.tokenCost <= availableTokens &&
          (cap == null || sourceCount < cap);
      if (!fits) {
        packingTruncated = true;
        continue;
      }
      selected.add(
        SelectedContextItem(evidence: evidence, score: candidate.score),
      );
      sourceCounts[evidence.source] = sourceCount + 1;
      bytes += evidence.byteCost;
      tokens += evidence.tokenCost;
    }

    return ContextBundle(
      items: selected,
      totalBytes: bytes,
      totalTokens: tokens,
      deduplicatedCount: ranking.deduplicatedCount,
      staleCount: staleCount,
      redactedCount: redactedCount,
      rootDeniedCount: rootDeniedCount,
      truncated:
          sourceTruncated ||
          packingTruncated ||
          staleCount > 0 ||
          redactedCount > 0 ||
          rootDeniedCount > 0 ||
          ranking.deduplicatedCount > 0 ||
          selected.any((item) => item.evidence.truncated),
      sourceFailures: failures,
    );
  }

  Future<_SourceResult> _fetch(
    ContextSource source,
    ContextQuery query,
    AgentCancellationToken cancellation,
  ) async {
    _throwIfCancelled(cancellation);
    final cancellationSignal = Completer<ContextPage>();
    final deadlineSignal = Completer<ContextPage>();
    Timer? deadlineTimer;
    final subscription = cancellation.cancellations.listen((_) {
      if (!cancellationSignal.isCompleted) {
        cancellationSignal.completeError(
          const ContextEngineFailure(
            ContextEngineFailureCode.cancelled,
            'Context selection was cancelled.',
          ),
        );
      }
    });
    final deadline = query.deadline;
    if (deadline != null) {
      final remaining = deadline.difference(_clock());
      if (remaining <= Duration.zero) {
        await subscription.cancel();
        throw const ContextEngineFailure(
          ContextEngineFailureCode.deadline,
          'Context selection deadline was reached.',
        );
      }
      deadlineTimer = Timer(remaining, () {
        if (!deadlineSignal.isCompleted) {
          deadlineSignal.completeError(
            const ContextSourceFailure(
              code: ContextSourceFailureCode.deadline,
              message: 'Context source deadline was reached.',
            ),
          );
        }
      });
    }
    try {
      final races = <Future<ContextPage>>[
        source.fetch(
          query,
          limit: maxCandidatesPerSource,
          cancellation: cancellation,
        ),
        cancellationSignal.future,
      ];
      if (deadline != null) races.add(deadlineSignal.future);
      final page = await Future.any<ContextPage>(races);
      return _SourceResult(page: page);
    } on ContextSourceFailure catch (error) {
      return _SourceResult(failure: error.attributedTo(source.id));
    } finally {
      deadlineTimer?.cancel();
      await subscription.cancel();
    }
  }

  static void _validateBudget(ContextBudget budget) {
    if (budget.maxItems < 0 ||
        budget.maxBytes < 0 ||
        budget.maxTokens < 0 ||
        budget.reservedOutputTokens < 0 ||
        budget.reservedOutputTokens > budget.maxTokens ||
        budget.perSourceCaps.values.any((value) => value < 0)) {
      throw const ContextEngineFailure(
        ContextEngineFailureCode.invalidBudget,
        'Context budget bounds are invalid.',
      );
    }
  }

  static void _throwIfCancelled(AgentCancellationToken cancellation) {
    if (cancellation.isCancelled) {
      throw const ContextEngineFailure(
        ContextEngineFailureCode.cancelled,
        'Context selection was cancelled.',
      );
    }
  }

  void _throwIfDeadlineReached(ContextQuery query) {
    final deadline = query.deadline;
    if (deadline != null && !_clock().isBefore(deadline)) {
      throw const ContextEngineFailure(
        ContextEngineFailureCode.deadline,
        'Context selection deadline was reached.',
      );
    }
  }

  static bool _insideAnyRoot(String resource, Set<String> roots) {
    final candidate = Uri.tryParse(resource);
    if (candidate == null || !candidate.hasScheme) return false;
    final normalizedCandidate = _normalizePath(candidate.pathSegments);
    if (normalizedCandidate == null) return false;
    for (final rootValue in roots) {
      final root = Uri.tryParse(rootValue);
      if (root == null ||
          root.scheme != candidate.scheme ||
          root.authority != candidate.authority) {
        continue;
      }
      final normalizedRoot = _normalizePath(root.pathSegments);
      if (normalizedRoot == null) continue;
      if (normalizedCandidate.length < normalizedRoot.length) continue;
      var matches = true;
      for (var index = 0; index < normalizedRoot.length; index += 1) {
        if (normalizedCandidate[index] != normalizedRoot[index]) {
          matches = false;
          break;
        }
      }
      if (matches) return true;
    }
    return false;
  }

  static List<String>? _normalizePath(List<String> segments) {
    final normalized = <String>[];
    for (final segment in segments) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') return null;
      normalized.add(segment);
    }
    return normalized;
  }
}

final class _SourceResult {
  const _SourceResult({this.page, this.failure});

  final ContextPage? page;
  final ContextSourceFailure? failure;
}
