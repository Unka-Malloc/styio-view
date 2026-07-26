/// Stable context ranking and deduplication.
library;

import 'context_evidence.dart';

final class RankedContextEvidence {
  const RankedContextEvidence({
    required this.evidence,
    required this.score,
    required this.explicit,
  });

  final ContextEvidence evidence;
  final double score;
  final bool explicit;
}

final class ContextRanking {
  ContextRanking({
    required List<RankedContextEvidence> candidates,
    required this.deduplicatedCount,
  }) : candidates = List<RankedContextEvidence>.unmodifiable(candidates);

  final List<RankedContextEvidence> candidates;
  final int deduplicatedCount;
}

final class ContextRanker {
  const ContextRanker();

  ContextRanking rank(Iterable<ContextEvidence> evidence, ContextQuery query) {
    final canonical = evidence.toList(growable: false)..sort(_canonicalCompare);
    final seen = <String>{};
    final ranked = <RankedContextEvidence>[];
    var deduplicated = 0;
    for (final item in canonical) {
      final key =
          '${item.resource}\u0000${item.range.start}:${item.range.end}'
          '\u0000${item.contentDigest}';
      if (!seen.add(key)) {
        deduplicated += 1;
        continue;
      }
      final normalizedContent = item.content.toLowerCase();
      var termScore = 0.0;
      for (final term in query.terms) {
        if (normalizedContent.contains(term.toLowerCase())) {
          termScore += 1;
        }
      }
      ranked.add(
        RankedContextEvidence(
          evidence: item,
          score: item.baseScore + termScore,
          explicit: query.explicitEvidenceIds.contains(item.id),
        ),
      );
    }
    ranked.sort((left, right) {
      final explicit = _boolCompare(right.explicit, left.explicit);
      if (explicit != 0) return explicit;
      final score = right.score.compareTo(left.score);
      if (score != 0) return score;
      return _canonicalCompare(left.evidence, right.evidence);
    });
    return ContextRanking(candidates: ranked, deduplicatedCount: deduplicated);
  }

  static int _canonicalCompare(ContextEvidence left, ContextEvidence right) {
    final priority = _sourcePriority(
      left.source,
    ).compareTo(_sourcePriority(right.source));
    if (priority != 0) return priority;
    final resource = left.resource.compareTo(right.resource);
    if (resource != 0) return resource;
    final range = left.range.start.compareTo(right.range.start);
    if (range != 0) return range;
    return left.id.compareTo(right.id);
  }

  static int _sourcePriority(String source) => switch (source) {
    'attachment' => 0,
    'diagnostics' => 1,
    'changed' => 2,
    'symbols' => 3,
    'search' => 4,
    _ => 100,
  };

  static int _boolCompare(bool left, bool right) =>
      (left ? 1 : 0).compareTo(right ? 1 : 0);
}
