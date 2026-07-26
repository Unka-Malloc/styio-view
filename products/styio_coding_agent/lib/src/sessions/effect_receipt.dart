library;

import 'dart:convert';

import 'session_event.dart';

enum EffectExecutionOutcome { committed, rejected }

final class EffectRequest {
  const EffectRequest({
    required this.sessionId,
    required this.idempotencyKey,
    required this.effectKind,
    required this.parameters,
  });

  final String sessionId;
  final String idempotencyKey;
  final String effectKind;
  final Map<String, Object?> parameters;

  bool get isValid =>
      sessionId.trim().isNotEmpty &&
      idempotencyKey.trim().isNotEmpty &&
      effectKind.trim().isNotEmpty;
}

final class EffectExecutionReceipt {
  EffectExecutionReceipt({
    required this.effectId,
    required this.outcome,
    required Map<String, Object?> metadata,
  }) : metadata = freezeStringMap(metadata);

  final String effectId;
  final EffectExecutionOutcome outcome;
  final Map<String, Object?> metadata;
}

final class EffectReceipt {
  EffectReceipt({
    required this.sessionId,
    required this.idempotencyKey,
    required this.effectKind,
    required this.effectId,
    required this.eventSequence,
    required this.outcome,
    required Map<String, Object?> metadata,
  }) : metadata = freezeStringMap(metadata);

  final String sessionId;
  final String idempotencyKey;
  final String effectKind;
  final String effectId;
  final int eventSequence;
  final EffectExecutionOutcome outcome;
  final Map<String, Object?> metadata;

  factory EffectReceipt.fromJson(Map<String, Object?> json) => EffectReceipt(
    sessionId: json['sessionId']! as String,
    idempotencyKey: json['idempotencyKey']! as String,
    effectKind: json['effectKind']! as String,
    effectId: json['effectId']! as String,
    eventSequence: json['eventSequence']! as int,
    outcome: EffectExecutionOutcome.values.byName(json['outcome']! as String),
    metadata: Map<String, Object?>.from(json['metadata']! as Map),
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'sessionId': sessionId,
    'idempotencyKey': idempotencyKey,
    'effectKind': effectKind,
    'effectId': effectId,
    'eventSequence': eventSequence,
    'outcome': outcome.name,
    'metadata': metadata,
  };
}

abstract interface class RecoverableEffectPort {
  Future<EffectExecutionReceipt> execute(EffectRequest request);
}

enum EffectCommitOutcome {
  committed,
  sequenceConflict,
  rejected,
  corruptedTail,
}

final class EffectCommitResult {
  const EffectCommitResult({
    required this.outcome,
    required this.currentSequence,
    required this.replayedFromJournal,
    this.receipt,
  });

  final EffectCommitOutcome outcome;
  final int currentSequence;
  final bool replayedFromJournal;
  final EffectReceipt? receipt;
}

abstract interface class EffectReceiptJournal {
  Future<EffectReceipt?> findEffectReceipt(
    String sessionId,
    String idempotencyKey,
  );

  Future<List<EffectReceipt>> loadEffectReceipts(
    String sessionId, {
    int maxReceipts = 1024,
  });

  Future<EffectCommitResult> appendEffect({
    required EffectRequest request,
    required EffectExecutionReceipt execution,
    required SessionCorrelation correlation,
    required int expectedSequence,
  });
}

final class EffectCommitCoordinator {
  const EffectCommitCoordinator({
    required this.store,
    required this.port,
    this.maxRequestBytes = 65536,
  }) : assert(maxRequestBytes > 0);

  final EffectReceiptJournal store;
  final RecoverableEffectPort port;
  final int maxRequestBytes;

  Future<EffectCommitResult> commit({
    required EffectRequest request,
    required SessionCorrelation correlation,
    required int expectedSequence,
  }) async {
    if (!request.isValid ||
        !correlation.isValid ||
        request.sessionId != correlation.sessionId ||
        utf8.encode(canonicalJson(request.parameters)).length >
            maxRequestBytes) {
      return EffectCommitResult(
        outcome: EffectCommitOutcome.rejected,
        currentSequence: expectedSequence,
        replayedFromJournal: false,
      );
    }
    final existing = await store.findEffectReceipt(
      request.sessionId,
      request.idempotencyKey,
    );
    if (existing != null) {
      return EffectCommitResult(
        outcome: EffectCommitOutcome.committed,
        currentSequence: existing.eventSequence,
        replayedFromJournal: true,
        receipt: existing,
      );
    }
    final execution = await port.execute(request);
    if (execution.outcome != EffectExecutionOutcome.committed ||
        execution.effectId.trim().isEmpty) {
      return EffectCommitResult(
        outcome: EffectCommitOutcome.rejected,
        currentSequence: expectedSequence,
        replayedFromJournal: false,
      );
    }
    return store.appendEffect(
      request: request,
      execution: execution,
      correlation: correlation,
      expectedSequence: expectedSequence,
    );
  }
}
