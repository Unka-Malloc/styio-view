import 'package:vityo_coding_agent/vityo_coding_agent.dart';
import 'package:test/test.dart';

void main() {
  test(
    'event store assigns a digest chain and rejects stale writers',
    () async {
      final store = InMemorySessionEventStore();
      const correlation = SessionCorrelation(
        taskId: 'task',
        sessionId: 'session',
      );
      final first = await store.append(
        sessionId: 'session',
        expectedSequence: 0,
        events: <SessionEventDraft>[_draft(correlation, 'first')],
      );
      final stale = await store.append(
        sessionId: 'session',
        expectedSequence: 0,
        events: <SessionEventDraft>[_draft(correlation, 'stale')],
      );

      expect(first.outcome, SessionAppendOutcome.committed);
      expect(first.committedEvents.single.hasValidDigest, isTrue);
      expect(stale.outcome, SessionAppendOutcome.sequenceConflict);
      expect(stale.currentSequence, 1);
    },
  );

  test('redacts nested durable payloads and freezes snapshots', () async {
    final source = <String, Object?>{
      'token': 'private',
      'nested': <String, Object?>{'password': 'private', 'safe': 'value'},
    };
    final store = InMemorySessionEventStore();
    const correlation = SessionCorrelation(
      taskId: 'task',
      sessionId: 'session',
    );
    final result = await store.append(
      sessionId: 'session',
      expectedSequence: 0,
      events: <SessionEventDraft>[
        SessionEventDraft(
          kind: SessionEventKind.goalRecorded,
          correlation: correlation,
          occurredAt: DateTime.utc(2026),
          payload: source,
        ),
      ],
    );
    (source['nested']! as Map<String, Object?>)['safe'] = 'changed';

    expect(
      result.committedEvents.single.payload.toString(),
      isNot(contains('private')),
    );
    expect(result.committedEvents.single.payload.toString(), contains('value'));
  });

  test('recovery preserves prefix when the tail digest is corrupt', () async {
    final store = InMemorySessionEventStore();
    const correlation = SessionCorrelation(
      taskId: 'task',
      sessionId: 'session',
    );
    final append = await store.append(
      sessionId: 'session',
      expectedSequence: 0,
      events: <SessionEventDraft>[
        _draft(correlation, 'one'),
        _draft(correlation, 'two'),
      ],
    );
    final checkpoint = SessionCheckpoint.fromProjection(
      const SessionProjector(
        maxHotEvents: 1,
      ).project(sessionId: 'session', events: <SessionEvent>[]),
    );
    final second = append.committedEvents.last;
    final corrupt = SessionEvent(
      sessionId: second.sessionId,
      sequence: second.sequence,
      kind: second.kind,
      correlation: second.correlation,
      occurredAt: second.occurredAt,
      payload: const <String, Object?>{'value': 'tampered'},
      previousDigest: second.previousDigest,
      digest: second.digest,
    );
    final recovered = const SessionRecovery(maxHotEvents: 1).recover(
      checkpoint: checkpoint,
      eventTail: <SessionEvent>[append.committedEvents.first, corrupt],
      effectReceipts: <EffectReceipt>[],
    );

    expect(recovered.status, SessionRecoveryStatus.tailCorrupted);
    expect(recovered.projection.appliedSequence, 1);
    expect(recovered.failureSequence, 2);
  });

  test('bounds append, loading, and replay work', () async {
    final store = InMemorySessionEventStore(
      maxBatchEvents: 2,
      maxEventBytes: 128,
    );
    const correlation = SessionCorrelation(
      taskId: 'task',
      sessionId: 'session',
    );
    final oversized = await store.append(
      sessionId: 'session',
      expectedSequence: 0,
      events: <SessionEventDraft>[
        _draft(correlation, 'one'),
        _draft(correlation, 'two'),
        _draft(correlation, 'three'),
      ],
    );
    expect(oversized.outcome, SessionAppendOutcome.invalidEvent);

    final oversizedPayload = await store.append(
      sessionId: 'session',
      expectedSequence: 0,
      events: <SessionEventDraft>[
        _draft(correlation, List<String>.filled(256, 'x').join()),
      ],
    );
    expect(oversizedPayload.outcome, SessionAppendOutcome.invalidEvent);

    final append = await store.append(
      sessionId: 'session',
      expectedSequence: 0,
      events: <SessionEventDraft>[
        _draft(correlation, 'one'),
        _draft(correlation, 'two'),
      ],
    );
    final page = await store.load(
      sessionId: 'session',
      afterSequence: 0,
      maxEvents: 1,
    );
    expect(page.events, hasLength(1));
    expect(page.hasMore, isTrue);

    final checkpoint = SessionCheckpoint.fromProjection(
      SessionProjection.empty('session'),
    );
    final recovered = const SessionRecovery(maxHotEvents: 1, maxReplayEvents: 1)
        .recover(
          checkpoint: checkpoint,
          eventTail: append.committedEvents,
          effectReceipts: const <EffectReceipt>[],
        );
    expect(recovered.status, SessionRecoveryStatus.replayLimitExceeded);
    expect(recovered.projection.appliedSequence, 1);
    expect(recovered.failureSequence, 2);
  });
}

SessionEventDraft _draft(SessionCorrelation correlation, String value) =>
    SessionEventDraft(
      kind: SessionEventKind.turnRecorded,
      correlation: correlation,
      occurredAt: DateTime.utc(2026),
      payload: <String, Object?>{'value': value},
    );
