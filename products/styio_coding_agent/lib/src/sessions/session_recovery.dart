library;

import 'effect_receipt.dart';
import 'session_event.dart';
import 'session_projection.dart';

enum SessionRecoveryStatus {
  recovered,
  tailCorrupted,
  checkpointInvalid,
  sequenceConflict,
  replayLimitExceeded,
}

final class RecoveredSession {
  const RecoveredSession({
    required this.status,
    required this.projection,
    this.failureSequence,
  });

  final SessionRecoveryStatus status;
  final SessionProjection projection;
  final int? failureSequence;
}

final class SessionRecovery {
  const SessionRecovery({
    required this.maxHotEvents,
    this.maxReplayEvents = 4096,
  }) : assert(maxHotEvents > 0),
       assert(maxReplayEvents > 0);

  final int maxHotEvents;
  final int maxReplayEvents;

  RecoveredSession recover({
    required SessionCheckpoint checkpoint,
    required Iterable<SessionEvent> eventTail,
    required Iterable<EffectReceipt> effectReceipts,
  }) {
    if (!checkpoint.isValid) {
      return RecoveredSession(
        status: SessionRecoveryStatus.checkpointInvalid,
        projection: SessionProjection.empty(checkpoint.sessionId),
      );
    }
    var projection = checkpoint.projection;
    final projector = SessionProjector(maxHotEvents: maxHotEvents);
    var replayed = 0;
    for (final event in eventTail) {
      if (replayed >= maxReplayEvents) {
        return RecoveredSession(
          status: SessionRecoveryStatus.replayLimitExceeded,
          projection: projection,
          failureSequence: event.sequence,
        );
      }
      if (event.sessionId != checkpoint.sessionId ||
          event.sequence != projection.appliedSequence + 1) {
        return RecoveredSession(
          status: SessionRecoveryStatus.sequenceConflict,
          projection: projection,
          failureSequence: event.sequence,
        );
      }
      if (event.previousDigest != projection.lastEventDigest ||
          !event.hasValidDigest) {
        return RecoveredSession(
          status: SessionRecoveryStatus.tailCorrupted,
          projection: projection,
          failureSequence: event.sequence,
        );
      }
      projection = projector.project(
        sessionId: checkpoint.sessionId,
        events: <SessionEvent>[event],
        base: projection,
      );
      replayed += 1;
    }
    projection = projector.project(
      sessionId: checkpoint.sessionId,
      events: const <SessionEvent>[],
      base: projection,
      effectReceipts: effectReceipts,
    );
    return RecoveredSession(
      status: SessionRecoveryStatus.recovered,
      projection: projection,
    );
  }
}
