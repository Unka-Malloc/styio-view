/// Revisioned evidence records and source contracts.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../cancellation.dart';

enum ContextSensitivity { public, internal, confidential, secret }

final class ContextRange {
  const ContextRange({required this.start, required this.end})
    : assert(start >= 0),
      assert(end >= start);

  final int start;
  final int end;
}

final class ContextProvenance {
  const ContextProvenance({
    required this.sourceId,
    required this.retrieval,
    required this.sourceRevision,
  });

  final String sourceId;
  final String retrieval;
  final int sourceRevision;
}

final class ContextEvidence {
  const ContextEvidence._({
    required this.id,
    required this.source,
    required this.resource,
    required this.revision,
    required this.range,
    required this.sensitivity,
    required this.baseScore,
    required this.content,
    required this.tokenCost,
    required this.provenance,
    required this.contentDigest,
    required this.byteCost,
    required this.truncated,
  });

  factory ContextEvidence.create({
    required String id,
    required String source,
    required String resource,
    required int revision,
    required ContextRange range,
    required ContextSensitivity sensitivity,
    required double baseScore,
    required String content,
    required int tokenCost,
    required ContextProvenance provenance,
    bool truncated = false,
  }) {
    if (id.isEmpty || source.isEmpty || resource.isEmpty) {
      throw ArgumentError('Context evidence identity fields cannot be empty.');
    }
    if (revision < 0 || tokenCost < 0) {
      throw ArgumentError('Revision and token cost cannot be negative.');
    }
    final bytes = utf8.encode(content);
    return ContextEvidence._(
      id: id,
      source: source,
      resource: resource,
      revision: revision,
      range: range,
      sensitivity: sensitivity,
      baseScore: baseScore,
      content: content,
      tokenCost: tokenCost,
      provenance: provenance,
      contentDigest: sha256.convert(bytes).toString(),
      byteCost: bytes.length,
      truncated: truncated,
    );
  }

  final String id;
  final String source;
  final String resource;
  final int revision;
  final ContextRange range;
  final ContextSensitivity sensitivity;
  final double baseScore;
  final String content;
  final int tokenCost;
  final ContextProvenance provenance;
  final String contentDigest;
  final int byteCost;
  final bool truncated;
}

final class ContextQuery {
  ContextQuery({
    required List<String> terms,
    required Set<String> roots,
    required Map<String, int> expectedRevisions,
    Set<String> explicitEvidenceIds = const <String>{},
    this.maximumSensitivity = ContextSensitivity.internal,
    this.deadline,
  }) : terms = List<String>.unmodifiable(terms),
       roots = Set<String>.unmodifiable(roots),
       expectedRevisions = Map<String, int>.unmodifiable(expectedRevisions),
       explicitEvidenceIds = Set<String>.unmodifiable(explicitEvidenceIds);

  final List<String> terms;
  final Set<String> roots;
  final Map<String, int> expectedRevisions;
  final Set<String> explicitEvidenceIds;
  final ContextSensitivity maximumSensitivity;
  final DateTime? deadline;
}

final class ContextBudget {
  const ContextBudget({
    required this.maxItems,
    required this.maxBytes,
    required this.maxTokens,
    required this.reservedOutputTokens,
    this.perSourceCaps = const <String, int>{},
  });

  final int maxItems;
  final int maxBytes;
  final int maxTokens;
  final int reservedOutputTokens;
  final Map<String, int> perSourceCaps;
}

abstract interface class ContextSource {
  String get id;

  Future<ContextPage> fetch(
    ContextQuery query, {
    required int limit,
    required AgentCancellationToken cancellation,
  });
}

final class ContextPage {
  ContextPage({required List<ContextEvidence> items, required this.hasMore})
    : items = List<ContextEvidence>.unmodifiable(items);

  final List<ContextEvidence> items;
  final bool hasMore;
}

enum ContextSourceFailureCode { unavailable, deadline, invalidResponse }

final class ContextSourceFailure implements Exception {
  const ContextSourceFailure({
    required this.code,
    required this.message,
    this.sourceId = '',
  });

  final ContextSourceFailureCode code;
  final String message;
  final String sourceId;

  ContextSourceFailure attributedTo(String source) =>
      ContextSourceFailure(code: code, message: message, sourceId: source);

  @override
  String toString() => 'ContextSourceFailure(${code.name}, source: $sourceId)';
}

enum ContextEngineFailureCode { cancelled, deadline, invalidBudget }

final class ContextEngineFailure implements Exception {
  const ContextEngineFailure(this.code, this.message);

  final ContextEngineFailureCode code;
  final String message;

  @override
  String toString() => 'ContextEngineFailure(${code.name}): $message';
}
