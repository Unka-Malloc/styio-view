library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'effect_receipt.dart';
import 'session_event.dart';
import 'session_event_store.dart';
import 'session_journal.dart';
import 'session_projection.dart';

/// Append-only JSON-lines session store over a host-provided durable journal.
///
/// Each event batch, effect receipt, or checkpoint is one flushed record.
/// A partial final record is treated as a corrupt tail and never overwritten.
final class JournalSessionEventStore implements SessionEventStore {
  JournalSessionEventStore({
    required SessionJournal journal,
    SessionRedactor redactor = const SessionRedactor(),
    this.maxBatchEvents = 256,
    this.maxEventBytes = 65536,
  }) : _journal = journal,
       _redactor = redactor {
    if (maxBatchEvents <= 0 || maxEventBytes <= 0) {
      throw ArgumentError('Session store budgets must be positive.');
    }
  }

  final SessionJournal _journal;
  final SessionRedactor _redactor;
  final int maxBatchEvents;
  final int maxEventBytes;

  @override
  Future<SessionAppendResult> append({
    required String sessionId,
    required int expectedSequence,
    required List<SessionEventDraft> events,
  }) => _serialized(sessionId, () async {
    final snapshot = await _read(sessionId);
    if (snapshot.corruptedTail) {
      return SessionAppendResult(
        outcome: SessionAppendOutcome.corruptedTail,
        currentSequence: snapshot.currentSequence,
        committedEvents: const <SessionEvent>[],
      );
    }
    if (expectedSequence != snapshot.currentSequence) {
      return SessionAppendResult(
        outcome: SessionAppendOutcome.sequenceConflict,
        currentSequence: snapshot.currentSequence,
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
        currentSequence: snapshot.currentSequence,
        committedEvents: const <SessionEvent>[],
      );
    }
    var previousDigest = snapshot.lastDigest;
    final committed = <SessionEvent>[];
    for (final draft in events) {
      final event = SessionEvent.commit(
        sequence: snapshot.currentSequence + committed.length + 1,
        draft: draft,
        previousDigest: previousDigest,
        redactor: _redactor,
      );
      committed.add(event);
      previousDigest = event.digest;
    }
    _appendRecord(sessionId, <String, Object?>{
      'schemaVersion': 1,
      'type': 'eventBatch',
      'events': <Map<String, Object?>>[
        for (final event in committed) event.toJson(),
      ],
    });
    return SessionAppendResult(
      outcome: SessionAppendOutcome.committed,
      currentSequence: snapshot.currentSequence + committed.length,
      committedEvents: committed,
    );
  });

  @override
  Future<SessionEventBatch> load({
    required String sessionId,
    required int afterSequence,
    int maxEvents = 1024,
  }) => _serialized(sessionId, () async {
    if (maxEvents <= 0) throw ArgumentError.value(maxEvents, 'maxEvents');
    final snapshot = await _read(
      sessionId,
      afterSequence: afterSequence,
      maxEvents: maxEvents,
    );
    return SessionEventBatch(
      sessionId: sessionId,
      currentSequence: snapshot.currentSequence,
      events: snapshot.events,
      corruptedTail: snapshot.corruptedTail,
      hasMore:
          afterSequence.clamp(0, snapshot.currentSequence) +
              snapshot.events.length <
          snapshot.currentSequence,
    );
  });

  @override
  Future<EffectReceipt?> findEffectReceipt(
    String sessionId,
    String idempotencyKey,
  ) => _serialized(
    sessionId,
    () async => (await _read(
      sessionId,
      effectKey: idempotencyKey,
    )).effects[idempotencyKey],
  );

  @override
  Future<List<EffectReceipt>> loadEffectReceipts(
    String sessionId, {
    int maxReceipts = 1024,
  }) => _serialized(sessionId, () async {
    if (maxReceipts <= 0) {
      throw ArgumentError.value(maxReceipts, 'maxReceipts');
    }
    final snapshot = await _read(sessionId, maxReceipts: maxReceipts);
    return List<EffectReceipt>.unmodifiable(snapshot.effects.values);
  });

  @override
  Future<EffectCommitResult> appendEffect({
    required EffectRequest request,
    required EffectExecutionReceipt execution,
    required SessionCorrelation correlation,
    required int expectedSequence,
  }) => _serialized(request.sessionId, () async {
    final snapshot = await _read(
      request.sessionId,
      effectKey: request.idempotencyKey,
    );
    final existing = snapshot.effects[request.idempotencyKey];
    if (existing != null) {
      return EffectCommitResult(
        outcome: EffectCommitOutcome.committed,
        currentSequence: snapshot.currentSequence,
        replayedFromJournal: true,
        receipt: existing,
      );
    }
    if (snapshot.corruptedTail) {
      return EffectCommitResult(
        outcome: EffectCommitOutcome.corruptedTail,
        currentSequence: snapshot.currentSequence,
        replayedFromJournal: false,
      );
    }
    if (!request.isValid ||
        request.sessionId != correlation.sessionId ||
        canonicalUtf8Length(_redactor.redact(request.parameters)) >
            maxEventBytes ||
        canonicalUtf8Length(_redactor.redact(execution.metadata)) >
            maxEventBytes ||
        expectedSequence != snapshot.currentSequence) {
      return EffectCommitResult(
        outcome: expectedSequence != snapshot.currentSequence
            ? EffectCommitOutcome.sequenceConflict
            : EffectCommitOutcome.rejected,
        currentSequence: snapshot.currentSequence,
        replayedFromJournal: false,
      );
    }
    final event = SessionEvent.commit(
      sequence: snapshot.currentSequence + 1,
      draft: SessionEventDraft(
        kind: SessionEventKind.changeCommitted,
        correlation: correlation,
        occurredAt: DateTime.now().toUtc(),
        payload: <String, Object?>{
          'effectKind': request.effectKind,
          'effectId': execution.effectId,
          'parameters': request.parameters,
          'outcome': execution.outcome.name,
        },
      ),
      previousDigest: snapshot.lastDigest,
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
    _appendRecord(request.sessionId, <String, Object?>{
      'schemaVersion': 1,
      'type': 'effect',
      'events': <Map<String, Object?>>[event.toJson()],
      'receipt': receipt.toJson(),
    });
    return EffectCommitResult(
      outcome: EffectCommitOutcome.committed,
      currentSequence: event.sequence,
      replayedFromJournal: false,
      receipt: receipt,
    );
  });

  @override
  Future<void> saveCheckpoint(SessionCheckpoint checkpoint) =>
      _serialized(checkpoint.sessionId, () async {
        if (!checkpoint.isValid) {
          throw ArgumentError('Cannot save an invalid session checkpoint.');
        }
        final snapshot = await _read(checkpoint.sessionId);
        if (snapshot.corruptedTail ||
            checkpoint.appliedSequence > snapshot.currentSequence) {
          throw StateError('Checkpoint cannot advance a corrupt session log.');
        }
        _appendRecord(checkpoint.sessionId, <String, Object?>{
          'schemaVersion': 1,
          'type': 'checkpoint',
          'checkpoint': checkpoint.toJson(),
        });
      });

  @override
  Future<SessionCheckpoint?> loadCheckpoint(String sessionId) =>
      _serialized(sessionId, () async => (await _read(sessionId)).checkpoint);

  Future<T> _serialized<T>(String sessionId, FutureOr<T> Function() action) {
    return _journal.synchronized(_sessionName(sessionId), action);
  }

  String _sessionName(String sessionId) =>
      sha256.convert(utf8.encode(sessionId)).toString();

  void _appendRecord(String sessionId, Map<String, Object?> record) {
    _journal.appendLine(_sessionName(sessionId), canonicalJson(record));
  }

  Future<_FileSnapshot> _read(
    String sessionId, {
    int afterSequence = 0,
    int maxEvents = 0,
    String? effectKey,
    int maxReceipts = 0,
  }) async {
    final snapshot = _FileSnapshot();
    await for (final line in _journal.readLines(_sessionName(sessionId))) {
      if (line.trim().isEmpty) continue;
      try {
        final record = Map<String, Object?>.from(jsonDecode(line) as Map);
        if (record['schemaVersion'] != 1) {
          snapshot.corruptedTail = true;
          break;
        }
        final type = record['type'];
        if (type == 'checkpoint') {
          final checkpoint = SessionCheckpoint.fromJson(
            Map<String, Object?>.from(record['checkpoint']! as Map),
          );
          if (!checkpoint.isValid ||
              checkpoint.sessionId != sessionId ||
              checkpoint.appliedSequence > snapshot.currentSequence) {
            snapshot.corruptedTail = true;
            break;
          }
          snapshot.checkpoint = checkpoint;
          continue;
        }
        final rawEvents = record['events']! as List;
        final events = <SessionEvent>[
          for (final raw in rawEvents)
            SessionEvent.fromJson(Map<String, Object?>.from(raw as Map)),
        ];
        for (final event in events) {
          if (event.sessionId != sessionId ||
              event.sequence != snapshot.currentSequence + 1 ||
              event.previousDigest != snapshot.lastDigest ||
              !event.hasValidDigest) {
            throw const FormatException('invalid event chain');
          }
          snapshot.currentSequence = event.sequence;
          snapshot.lastDigest = event.digest;
          if (event.sequence > afterSequence &&
              snapshot.events.length < maxEvents) {
            snapshot.events.add(event);
          }
        }
        if (type == 'effect') {
          final receipt = EffectReceipt.fromJson(
            Map<String, Object?>.from(record['receipt']! as Map),
          );
          if (receipt.sessionId != sessionId ||
              receipt.eventSequence != snapshot.currentSequence) {
            throw const FormatException('invalid effect receipt');
          }
          final retain =
              receipt.idempotencyKey == effectKey ||
              (maxReceipts > 0 && snapshot.effects.length < maxReceipts);
          if (retain) {
            if (snapshot.effects.containsKey(receipt.idempotencyKey)) {
              throw const FormatException('duplicate effect receipt');
            }
            snapshot.effects[receipt.idempotencyKey] = receipt;
          }
        } else if (type != 'eventBatch') {
          throw const FormatException('unknown record type');
        }
      } on Object {
        snapshot.corruptedTail = true;
        break;
      }
    }
    return snapshot;
  }
}

final class _FileSnapshot {
  final List<SessionEvent> events = <SessionEvent>[];
  final Map<String, EffectReceipt> effects = <String, EffectReceipt>{};
  int currentSequence = 0;
  String lastDigest = '';
  SessionCheckpoint? checkpoint;
  bool corruptedTail = false;
}
