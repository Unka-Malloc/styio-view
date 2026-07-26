import 'dart:io';

import 'package:styio_coding_agent/styio_coding_agent.dart';

import '../bin/src/io_session_journal.dart';

Future<void> main() async {
  final durableRoot = Directory.systemTemp.createTempSync(
    'styio-session-recovery-',
  );
  try {
    const correlation = SessionCorrelation(
      taskId: 'restart-task',
      sessionId: 'restart-session',
    );
    final initialStore = JournalSessionEventStore(
      journal: IoSessionJournal(durableRoot),
    );
    final append = await initialStore.append(
      sessionId: correlation.sessionId,
      expectedSequence: 0,
      events: <SessionEventDraft>[
        _draft(correlation, 'goal'),
        _draft(correlation, 'turn'),
      ],
    );
    final checkpoint = SessionCheckpoint.fromProjection(
      const SessionProjector(maxHotEvents: 1).project(
        sessionId: correlation.sessionId,
        events: <SessionEvent>[append.committedEvents.first],
      ),
    );
    await initialStore.saveCheckpoint(checkpoint);

    final restartedStore = JournalSessionEventStore(
      journal: IoSessionJournal(durableRoot),
    );
    final durableCheckpoint = await restartedStore.loadCheckpoint(
      correlation.sessionId,
    );
    final tail = await restartedStore.load(
      sessionId: correlation.sessionId,
      afterSequence: durableCheckpoint!.appliedSequence,
    );
    final recovered = const SessionRecovery(maxHotEvents: 1).recover(
      checkpoint: durableCheckpoint,
      eventTail: tail.events,
      effectReceipts: <EffectReceipt>[],
    );
    if (recovered.status != SessionRecoveryStatus.recovered ||
        recovered.projection.appliedSequence != 2) {
      throw StateError('new store instance did not recover durable state');
    }

    final port = _EffectPort();
    const request = EffectRequest(
      sessionId: 'restart-session',
      idempotencyKey: 'stable-key',
      effectKind: 'change',
      parameters: <String, Object?>{'resource': 'lib/main.dart'},
    );
    await port.execute(request);
    final first = await EffectCommitCoordinator(
      store: restartedStore,
      port: port,
    ).commit(request: request, correlation: correlation, expectedSequence: 2);
    final replay = await EffectCommitCoordinator(
      store: JournalSessionEventStore(journal: IoSessionJournal(durableRoot)),
      port: port,
    ).commit(request: request, correlation: correlation, expectedSequence: 2);

    if (first.outcome != EffectCommitOutcome.committed ||
        replay.outcome != EffectCommitOutcome.committed ||
        !replay.replayedFromJournal ||
        port.physicalEffects != 1) {
      throw StateError('restart duplicated a committed effect');
    }
  } finally {
    durableRoot.deleteSync(recursive: true);
  }
}

SessionEventDraft _draft(SessionCorrelation correlation, String value) =>
    SessionEventDraft(
      kind: SessionEventKind.turnRecorded,
      correlation: correlation,
      occurredAt: DateTime.utc(2026),
      payload: <String, Object?>{'value': value},
    );

final class _EffectPort implements RecoverableEffectPort {
  final Map<String, EffectExecutionReceipt> _completed =
      <String, EffectExecutionReceipt>{};
  int physicalEffects = 0;

  @override
  Future<EffectExecutionReceipt> execute(EffectRequest request) async =>
      _completed.putIfAbsent(request.idempotencyKey, () {
        physicalEffects += 1;
        return EffectExecutionReceipt(
          effectId: 'effect-${request.idempotencyKey}',
          outcome: EffectExecutionOutcome.committed,
          metadata: const <String, Object?>{'adapter': 'synthetic'},
        );
      });
}
