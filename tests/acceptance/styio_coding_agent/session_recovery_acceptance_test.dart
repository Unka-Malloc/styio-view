import 'dart:async';

import 'package:styio_coding_agent/styio_coding_agent.dart';

Future<void> main() async {
  await _recoversCheckpointAndTailWithBoundedRedactedHistory();
  await _preservesValidPrefixAndReportsIntegrityFailures();
  await _preventsDuplicateEffectsAcrossEveryAcknowledgementBoundary();
  await _isolatesSessionSequencesAndRejectsConcurrentStaleWriters();
}

Future<void> _recoversCheckpointAndTailWithBoundedRedactedHistory() async {
  final store = InMemorySessionEventStore(
    redactor: const SessionRedactor(
      sensitiveKeys: <String>{'authorization', 'password', 'token'},
    ),
  );
  final correlation = const SessionCorrelation(
    taskId: 'task-recovery',
    sessionId: 'session-recovery',
    turnId: 'turn-1',
  );
  final kinds = <SessionEventKind>[
    SessionEventKind.goalRecorded,
    SessionEventKind.turnRecorded,
    SessionEventKind.planRecorded,
    SessionEventKind.stepRecorded,
    SessionEventKind.toolCallRecorded,
    SessionEventKind.permissionRecorded,
    SessionEventKind.changeCommitted,
    SessionEventKind.validationRecorded,
    SessionEventKind.budgetRecorded,
    SessionEventKind.terminalRecorded,
  ];
  final append = await store.append(
    sessionId: correlation.sessionId,
    expectedSequence: 0,
    events: <SessionEventDraft>[
      for (final kind in kinds)
        SessionEventDraft(
          kind: kind,
          correlation: correlation,
          occurredAt: DateTime.utc(2026, 7, 26, 1, kind.index),
          payload: <String, Object?>{
            'kind': kind.name,
            'authorization': 'DO_NOT_PERSIST',
            'nested': <String, Object?>{
              'password': 'DO_NOT_PERSIST',
              'safe': 'visible',
            },
          },
        ),
    ],
  );
  _expect(
    append.outcome == SessionAppendOutcome.committed &&
        append.committedEvents.length == kinds.length &&
        append.currentSequence == kinds.length,
    'append must atomically assign a monotonic committed sequence',
  );

  final stored = await store.load(
    sessionId: correlation.sessionId,
    afterSequence: 0,
  );
  final persistedText = stored.events
      .map((event) => event.payload.toString())
      .join();
  _expect(
    !persistedText.contains('DO_NOT_PERSIST') &&
        persistedText.contains(SessionRedactor.replacement),
    'redaction must happen before session events become durable',
  );

  final projector = const SessionProjector(maxHotEvents: 3);
  final checkpointProjection = projector.project(
    sessionId: correlation.sessionId,
    events: stored.events.take(5),
  );
  final checkpoint = SessionCheckpoint.fromProjection(checkpointProjection);
  final recovery = const SessionRecovery(maxHotEvents: 3).recover(
    checkpoint: checkpoint,
    eventTail: stored.events.skip(5),
    effectReceipts: const <EffectReceipt>[],
  );

  _expect(
    recovery.status == SessionRecoveryStatus.recovered &&
        recovery.projection.appliedSequence == kinds.length &&
        recovery.projection.latestByKind.keys.toSet().containsAll(kinds) &&
        recovery.projection.hotEvents.length == 3 &&
        recovery.projection.hotEvents.last.kind ==
            SessionEventKind.terminalRecorded,
    'checkpoint plus valid tail must reconstruct all compact state with a bounded hot window',
  );
  _expect(
    recovery.projection.latestByKind.values.every(
      (event) =>
          event.correlation.sessionId == correlation.sessionId &&
          event.correlation.taskId == correlation.taskId &&
          event.digest.isNotEmpty,
    ),
    'every recovered fact must retain correlation and integrity provenance',
  );
}

Future<void> _preservesValidPrefixAndReportsIntegrityFailures() async {
  final store = InMemorySessionEventStore();
  const correlation = SessionCorrelation(
    taskId: 'task-corruption',
    sessionId: 'session-corruption',
  );
  final append = await store.append(
    sessionId: correlation.sessionId,
    expectedSequence: 0,
    events: <SessionEventDraft>[
      for (var index = 0; index < 4; index += 1)
        SessionEventDraft(
          kind: SessionEventKind.turnRecorded,
          correlation: correlation,
          occurredAt: DateTime.utc(2026, 7, 26, 2, index),
          payload: <String, Object?>{'index': index},
        ),
    ],
  );
  final events = append.committedEvents;
  final checkpointProjection = const SessionProjector(
    maxHotEvents: 2,
  ).project(sessionId: correlation.sessionId, events: events.take(1));
  final checkpoint = SessionCheckpoint.fromProjection(checkpointProjection);
  final corrupted = SessionEvent(
    sessionId: events[2].sessionId,
    sequence: events[2].sequence,
    kind: events[2].kind,
    correlation: events[2].correlation,
    occurredAt: events[2].occurredAt,
    payload: const <String, Object?>{'index': 'tampered'},
    previousDigest: events[2].previousDigest,
    digest: events[2].digest,
  );
  final tailRecovery = const SessionRecovery(maxHotEvents: 2).recover(
    checkpoint: checkpoint,
    eventTail: <SessionEvent>[events[1], corrupted, events[3]],
    effectReceipts: const <EffectReceipt>[],
  );
  _expect(
    tailRecovery.status == SessionRecoveryStatus.tailCorrupted &&
        tailRecovery.failureSequence == corrupted.sequence &&
        tailRecovery.projection.appliedSequence == events[1].sequence &&
        tailRecovery.projection.hotEvents.last.sequence == events[1].sequence,
    'a corrupted tail must expose the failure and preserve the valid prefix',
  );

  final invalidCheckpoint = SessionCheckpoint(
    sessionId: checkpoint.sessionId,
    appliedSequence: checkpoint.appliedSequence,
    lastEventDigest: checkpoint.lastEventDigest,
    projection: checkpoint.projection,
    projectionDigest: 'invalid-checkpoint-digest',
  );
  final checkpointRecovery = const SessionRecovery(maxHotEvents: 2).recover(
    checkpoint: invalidCheckpoint,
    eventTail: events.skip(1),
    effectReceipts: const <EffectReceipt>[],
  );
  _expect(
    checkpointRecovery.status == SessionRecoveryStatus.checkpointInvalid &&
        checkpointRecovery.projection.appliedSequence == 0,
    'a checkpoint digest mismatch must fail closed instead of trusting its projection',
  );
}

Future<void>
_preventsDuplicateEffectsAcrossEveryAcknowledgementBoundary() async {
  final store = InMemorySessionEventStore(
    redactor: const SessionRedactor(
      sensitiveKeys: <String>{'token'},
    ),
  );
  final port = _IdempotentEffectPort();
  final coordinator = EffectCommitCoordinator(store: store, port: port);
  const request = EffectRequest(
    sessionId: 'session-effect',
    idempotencyKey: 'effect-key-1',
    effectKind: 'workspace-change',
    parameters: <String, Object?>{
      'resource': 'lib/main.dart',
      'token': 'DO_NOT_PERSIST',
    },
  );
  const correlation = SessionCorrelation(
    taskId: 'task-effect',
    sessionId: 'session-effect',
    stepId: 'step-1',
    operationId: 'change-1',
  );

  // Simulate a crash after the host performed the effect but before the Agent
  // durably acknowledged it. Reissuing the same idempotency key must observe
  // the host receipt, not perform another mutation.
  await port.execute(request);
  final recovered = await coordinator.commit(
    request: request,
    correlation: correlation,
    expectedSequence: 0,
  );
  _expect(
    recovered.outcome == EffectCommitOutcome.committed &&
        !recovered.replayedFromJournal &&
        port.physicalEffectCount == 1,
    'restart after effect execution must reconcile the same host idempotency key exactly once',
  );

  final replayed = await coordinator.commit(
    request: request,
    correlation: correlation,
    expectedSequence: 0,
  );
  _expect(
    replayed.outcome == EffectCommitOutcome.committed &&
        replayed.replayedFromJournal &&
        replayed.receipt?.effectId == recovered.receipt?.effectId &&
        port.physicalEffectCount == 1,
    'a durable effect receipt must suppress both host replay and duplicate events',
  );
  final events = await store.load(
    sessionId: request.sessionId,
    afterSequence: 0,
  );
  final receipts = await store.loadEffectReceipts(request.sessionId);
  _expect(
    events.events.length == 1 &&
        receipts.length == 1 &&
        receipts.single.eventSequence == events.events.single.sequence &&
        !receipts.single.metadata.toString().contains('DO_NOT_PERSIST'),
    'effect event and redacted receipt must commit atomically at one sequence',
  );
}

Future<void>
_isolatesSessionSequencesAndRejectsConcurrentStaleWriters() async {
  final store = InMemorySessionEventStore();
  const first = SessionCorrelation(taskId: 'task-a', sessionId: 'session-a');
  const second = SessionCorrelation(taskId: 'task-b', sessionId: 'session-b');
  final results = await Future.wait(<Future<SessionAppendResult>>[
    store.append(
      sessionId: first.sessionId,
      expectedSequence: 0,
      events: <SessionEventDraft>[_draft(first, 'a-first')],
    ),
    store.append(
      sessionId: second.sessionId,
      expectedSequence: 0,
      events: <SessionEventDraft>[_draft(second, 'b-first')],
    ),
  ]);
  _expect(
    results.every(
      (result) =>
          result.outcome == SessionAppendOutcome.committed &&
          result.currentSequence == 1,
    ),
    'independent sessions must maintain isolated sequence spaces',
  );

  final staleWriters = await Future.wait(<Future<SessionAppendResult>>[
    store.append(
      sessionId: first.sessionId,
      expectedSequence: 1,
      events: <SessionEventDraft>[_draft(first, 'winner-one')],
    ),
    store.append(
      sessionId: first.sessionId,
      expectedSequence: 1,
      events: <SessionEventDraft>[_draft(first, 'winner-two')],
    ),
  ]);
  _expect(
    staleWriters
            .where(
              (result) =>
                  result.outcome == SessionAppendOutcome.committed,
            )
            .length ==
        1 &&
        staleWriters
                .where(
                  (result) =>
                      result.outcome == SessionAppendOutcome.sequenceConflict,
                )
                .length ==
            1 &&
        staleWriters.every((result) => result.currentSequence == 2),
    'one serialized writer must win and the stale writer must receive the current sequence',
  );
}

SessionEventDraft _draft(SessionCorrelation correlation, String value) =>
    SessionEventDraft(
      kind: SessionEventKind.turnRecorded,
      correlation: correlation,
      occurredAt: DateTime.utc(2026, 7, 26),
      payload: <String, Object?>{'value': value},
    );

final class _IdempotentEffectPort implements RecoverableEffectPort {
  final Map<String, EffectExecutionReceipt> _receipts =
      <String, EffectExecutionReceipt>{};
  int physicalEffectCount = 0;

  @override
  Future<EffectExecutionReceipt> execute(EffectRequest request) async =>
      _receipts.putIfAbsent(request.idempotencyKey, () {
        physicalEffectCount += 1;
        return EffectExecutionReceipt(
          effectId: 'host-effect-${request.idempotencyKey}',
          outcome: EffectExecutionOutcome.committed,
          metadata: const <String, Object?>{
            'host': 'synthetic',
            'token': 'DO_NOT_PERSIST',
          },
        );
      });
}

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}
