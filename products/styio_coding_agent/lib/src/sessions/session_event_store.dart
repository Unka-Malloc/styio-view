library;

import 'effect_receipt.dart';
import 'session_event.dart';
import 'session_projection.dart';

enum SessionAppendOutcome {
  committed,
  sequenceConflict,
  invalidEvent,
  corruptedTail,
}

final class SessionAppendResult {
  SessionAppendResult({
    required this.outcome,
    required this.currentSequence,
    required List<SessionEvent> committedEvents,
  }) : committedEvents = List<SessionEvent>.unmodifiable(committedEvents);

  final SessionAppendOutcome outcome;
  final int currentSequence;
  final List<SessionEvent> committedEvents;
}

final class SessionEventBatch {
  SessionEventBatch({
    required this.sessionId,
    required this.currentSequence,
    required List<SessionEvent> events,
    this.corruptedTail = false,
    this.hasMore = false,
  }) : events = List<SessionEvent>.unmodifiable(events);

  final String sessionId;
  final int currentSequence;
  final List<SessionEvent> events;
  final bool corruptedTail;
  final bool hasMore;
}

abstract interface class SessionEventStore implements EffectReceiptJournal {
  Future<SessionAppendResult> append({
    required String sessionId,
    required int expectedSequence,
    required List<SessionEventDraft> events,
  });

  Future<SessionEventBatch> load({
    required String sessionId,
    required int afterSequence,
    int maxEvents = 1024,
  });

  Future<void> saveCheckpoint(SessionCheckpoint checkpoint);

  Future<SessionCheckpoint?> loadCheckpoint(String sessionId);
}

final class InMemorySessionEventStore implements SessionEventStore {
  InMemorySessionEventStore({
    SessionRedactor redactor = const SessionRedactor(),
    this.maxBatchEvents = 256,
    this.maxEventBytes = 65536,
  }) : _redactor = redactor {
    if (maxBatchEvents <= 0 || maxEventBytes <= 0) {
      throw ArgumentError('Session store budgets must be positive.');
    }
  }

  final SessionRedactor _redactor;
  final int maxBatchEvents;
  final int maxEventBytes;
  final Map<String, _SessionLog> _logs = <String, _SessionLog>{};
  final Map<String, SessionCheckpoint> _checkpoints =
      <String, SessionCheckpoint>{};

  @override
  Future<SessionAppendResult> append({
    required String sessionId,
    required int expectedSequence,
    required List<SessionEventDraft> events,
  }) async {
    final log = _logs.putIfAbsent(sessionId, _SessionLog.new);
    final current = log.events.length;
    if (expectedSequence != current) {
      return SessionAppendResult(
        outcome: SessionAppendOutcome.sequenceConflict,
        currentSequence: current,
        committedEvents: const <SessionEvent>[],
      );
    }
    if (sessionId.trim().isEmpty ||
        events.isEmpty ||
        events.length > maxBatchEvents ||
        events.any(
          (event) =>
              event.correlation.sessionId != sessionId ||
              canonicalUtf8Length(_redactor.redact(event.payload)) >
                  maxEventBytes,
        )) {
      return SessionAppendResult(
        outcome: SessionAppendOutcome.invalidEvent,
        currentSequence: current,
        committedEvents: const <SessionEvent>[],
      );
    }
    var previousDigest = log.events.isEmpty ? '' : log.events.last.digest;
    final committed = <SessionEvent>[];
    for (final draft in events) {
      final event = SessionEvent.commit(
        sequence: current + committed.length + 1,
        draft: draft,
        previousDigest: previousDigest,
        redactor: _redactor,
      );
      committed.add(event);
      previousDigest = event.digest;
    }
    log.events.addAll(committed);
    return SessionAppendResult(
      outcome: SessionAppendOutcome.committed,
      currentSequence: log.events.length,
      committedEvents: committed,
    );
  }

  @override
  Future<SessionEventBatch> load({
    required String sessionId,
    required int afterSequence,
    int maxEvents = 1024,
  }) async {
    if (maxEvents <= 0) throw ArgumentError.value(maxEvents, 'maxEvents');
    final log = _logs[sessionId];
    final current = log?.events.length ?? 0;
    final start = afterSequence.clamp(0, current);
    final page = (log?.events.skip(start) ?? const <SessionEvent>[])
        .take(maxEvents)
        .toList(growable: false);
    return SessionEventBatch(
      sessionId: sessionId,
      currentSequence: current,
      events: page,
      hasMore: start + page.length < current,
    );
  }

  @override
  Future<EffectReceipt?> findEffectReceipt(
    String sessionId,
    String idempotencyKey,
  ) async => _logs[sessionId]?.effects[idempotencyKey];

  @override
  Future<List<EffectReceipt>> loadEffectReceipts(
    String sessionId, {
    int maxReceipts = 1024,
  }) async {
    if (maxReceipts <= 0) {
      throw ArgumentError.value(maxReceipts, 'maxReceipts');
    }
    return List<EffectReceipt>.unmodifiable(
      (_logs[sessionId]?.effects.values ?? const <EffectReceipt>[]).take(
        maxReceipts,
      ),
    );
  }

  @override
  Future<void> saveCheckpoint(SessionCheckpoint checkpoint) async {
    if (!checkpoint.isValid) {
      throw ArgumentError('Cannot save an invalid session checkpoint.');
    }
    _checkpoints[checkpoint.sessionId] = checkpoint;
  }

  @override
  Future<SessionCheckpoint?> loadCheckpoint(String sessionId) async =>
      _checkpoints[sessionId];

  @override
  Future<EffectCommitResult> appendEffect({
    required EffectRequest request,
    required EffectExecutionReceipt execution,
    required SessionCorrelation correlation,
    required int expectedSequence,
  }) async {
    final log = _logs.putIfAbsent(request.sessionId, _SessionLog.new);
    final existing = log.effects[request.idempotencyKey];
    if (existing != null) {
      return EffectCommitResult(
        outcome: EffectCommitOutcome.committed,
        currentSequence: log.events.length,
        replayedFromJournal: true,
        receipt: existing,
      );
    }
    if (!request.isValid ||
        request.sessionId != correlation.sessionId ||
        canonicalUtf8Length(_redactor.redact(request.parameters)) >
            maxEventBytes ||
        canonicalUtf8Length(_redactor.redact(execution.metadata)) >
            maxEventBytes ||
        expectedSequence != log.events.length) {
      return EffectCommitResult(
        outcome: expectedSequence != log.events.length
            ? EffectCommitOutcome.sequenceConflict
            : EffectCommitOutcome.rejected,
        currentSequence: log.events.length,
        replayedFromJournal: false,
      );
    }
    final draft = SessionEventDraft(
      kind: SessionEventKind.changeCommitted,
      correlation: correlation,
      occurredAt: DateTime.now().toUtc(),
      payload: <String, Object?>{
        'effectKind': request.effectKind,
        'effectId': execution.effectId,
        'parameters': request.parameters,
        'outcome': execution.outcome.name,
      },
    );
    final event = SessionEvent.commit(
      sequence: log.events.length + 1,
      draft: draft,
      previousDigest: log.events.isEmpty ? '' : log.events.last.digest,
      redactor: _redactor,
    );
    final receipt = EffectReceipt(
      sessionId: request.sessionId,
      idempotencyKey: request.idempotencyKey,
      effectKind: request.effectKind,
      effectId: execution.effectId,
      eventSequence: event.sequence,
      outcome: execution.outcome,
      metadata: _redactor.redact(execution.metadata),
    );
    log.events.add(event);
    log.effects[request.idempotencyKey] = receipt;
    return EffectCommitResult(
      outcome: EffectCommitOutcome.committed,
      currentSequence: log.events.length,
      replayedFromJournal: false,
      receipt: receipt,
    );
  }
}

final class _SessionLog {
  final List<SessionEvent> events = <SessionEvent>[];
  final Map<String, EffectReceipt> effects = <String, EffectReceipt>{};
}
