/// Deterministic bounded conversation compaction.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'context_evidence.dart';

final class ConversationTurn {
  const ConversationTurn({
    required this.id,
    required this.revision,
    required this.text,
    required this.tokenCost,
    required this.sensitivity,
  });

  final String id;
  final int revision;
  final String text;
  final int tokenCost;
  final ContextSensitivity sensitivity;
}

final class ConversationCompaction {
  ConversationCompaction({
    required this.summary,
    required this.summaryDigest,
    required List<ConversationTurn> hotTurns,
    required this.omittedTurnCount,
    required this.redactedTurnCount,
    required this.truncated,
  }) : hotTurns = List<ConversationTurn>.unmodifiable(hotTurns);

  final String summary;
  final String summaryDigest;
  final List<ConversationTurn> hotTurns;
  final int omittedTurnCount;
  final int redactedTurnCount;
  final bool truncated;
}

final class ConversationCompactor {
  const ConversationCompactor();

  ConversationCompaction compact(
    List<ConversationTurn> turns, {
    required int maxHotTurns,
    required int maxSummaryTokens,
  }) {
    if (maxHotTurns < 0 || maxSummaryTokens < 0) {
      throw ArgumentError('Compaction bounds cannot be negative.');
    }
    final hotStart = turns.length > maxHotTurns
        ? turns.length - maxHotTurns
        : 0;
    final omitted = turns.take(hotStart);
    final lines = <String>[];
    var usedTokens = 0;
    var redacted = turns
        .where((turn) => turn.sensitivity == ContextSensitivity.secret)
        .length;
    for (final turn in omitted) {
      final isSecret = turn.sensitivity == ContextSensitivity.secret;
      final text = isSecret ? '[redacted]' : turn.text;
      final line = '${turn.id}@${turn.revision}: $text';
      final cost = turn.tokenCost.clamp(1, maxSummaryTokens + 1);
      if (usedTokens + cost > maxSummaryTokens) {
        continue;
      }
      lines.add(line);
      usedTokens += cost;
    }
    final summary = lines.join('\n');
    return ConversationCompaction(
      summary: summary,
      summaryDigest: sha256.convert(utf8.encode(summary)).toString(),
      hotTurns: turns.skip(hotStart).map(_redactSecret).toList(growable: false),
      omittedTurnCount: hotStart,
      redactedTurnCount: redacted,
      truncated: hotStart > 0,
    );
  }

  static ConversationTurn _redactSecret(ConversationTurn turn) {
    if (turn.sensitivity != ContextSensitivity.secret) return turn;
    return ConversationTurn(
      id: turn.id,
      revision: turn.revision,
      text: '[redacted]',
      tokenCost: turn.tokenCost,
      sensitivity: turn.sensitivity,
    );
  }
}
