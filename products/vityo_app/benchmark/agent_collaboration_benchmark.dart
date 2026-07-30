import 'dart:convert';
import 'dart:io';

import 'package:vityo_app/src/ide/agent_client/agent_client.dart';
import 'package:vityo_app/src/ide/workbench/agent_collaboration/collaboration_store.dart';
import 'package:vityo_app/src/ide/workspace/workspace_change_set.dart';
import 'package:vityo_app/src/ide/workspace/workspace_transaction_service.dart';

Future<void> main() async {
  const submittedEvents = 5000;
  const policy = AgentEventBackpressurePolicy(
    maxQueuedEvents: 256,
    maxQueuedBytes: 512 * 1024,
    maxHotHistoryEvents: 128,
    maxHotHistoryBytes: 256 * 1024,
  );
  final reducer = AgentSessionReducer(
    sessionId: 'benchmark',
    maxBufferedUpdates: policy.maxHotHistoryEvents,
    backpressurePolicy: policy,
  );
  final reduceStopwatch = Stopwatch()..start();
  await Future.wait<void>(<Future<void>>[
    for (var index = 0; index < submittedEvents; index += 1)
      reducer.reduce(
        AgentSessionUpdate(
          sessionId: 'benchmark',
          kind: 'tool',
          text: 'event-$index',
          payload: <String, Object?>{'id': '$index', 'value': index},
        ),
      ),
  ]);
  reduceStopwatch.stop();
  final reduced = reducer.snapshot;

  final store = AgentCollaborationStore(
    commands: _Commands(),
    transactions: _Transactions(),
    maxTimelineEntriesPerSession: 128,
  );
  final projectionStopwatch = Stopwatch()..start();
  await store.apply(
    AgentSessionSnapshot(
      sessionId: 'benchmark',
      revision: 1,
      updates: <AgentSessionUpdate>[
        const AgentSessionUpdate(
          sessionId: 'benchmark',
          kind: 'session_state',
          text: 'Benchmark',
          payload: <String, Object?>{
            'id': 'state',
            'title': 'Benchmark',
            'status': 'running',
          },
        ),
        for (var index = 0; index < 10000; index += 1)
          AgentSessionUpdate(
            sessionId: 'benchmark',
            kind: 'turn',
            text: 'entry-$index',
            payload: <String, Object?>{'id': '$index'},
          ),
      ],
    ),
  );
  projectionStopwatch.stop();
  final projected = store.projection.session('benchmark');

  final passed =
      reduceStopwatch.elapsedMilliseconds <= 1500 &&
      projectionStopwatch.elapsedMilliseconds <= 750 &&
      reduced.updates.length <= policy.maxHotHistoryEvents &&
      reduced.bufferedUpdateBytes <= policy.maxHotHistoryBytes &&
      reduced.acceptedUpdateCount + reduced.droppedUpdateCount ==
          submittedEvents &&
      projected.timeline.length == 128 &&
      projected.droppedTimelineCount == 10000 - 128;
  final result = <String, Object?>{
    'schemaVersion': 1,
    'benchmark': 'agent_collaboration',
    'passed': passed,
    'budgets': const <String, Object?>{
      'reduceMs': 1500,
      'projectionMs': 750,
      'hotEvents': 128,
      'hotBytes': 256 * 1024,
    },
    'observed': <String, Object?>{
      'reduceMs': reduceStopwatch.elapsedMilliseconds,
      'projectionMs': projectionStopwatch.elapsedMilliseconds,
      'retainedEvents': reduced.updates.length,
      'retainedBytes': reduced.bufferedUpdateBytes,
      'droppedEvents': reduced.droppedUpdateCount,
      'projectedEvents': projected.timeline.length,
      'projectedDroppedEvents': projected.droppedTimelineCount,
    },
  };
  stdout.writeln(jsonEncode(result));
  await reducer.close();
  await store.close();
  if (!passed) {
    throw StateError('Agent collaboration performance budget exceeded');
  }
}

final class _Commands implements AgentWorkbenchCommandPort {
  @override
  Future<void> cancel(String sessionId) async {}

  @override
  Future<void> reconnect(String sessionId) async {}

  @override
  Future<void> resolvePermission({
    required String sessionId,
    required String permissionId,
    required AgentPermissionDecision decision,
  }) async {}

  @override
  Future<void> retry(String sessionId) async {}

  @override
  Future<void> steer(String sessionId, String prompt) async {}
}

final class _Transactions implements WorkspaceTransactionService {
  @override
  Future<WorkspaceTransactionReceipt> commit(String previewId) async =>
      const WorkspaceTransactionReceipt(
        id: 'commit',
        outcome: WorkspaceTransactionOutcome.committed,
        workspaceRevision: 1,
      );

  @override
  Future<WorkspaceTransactionPreview> preview(
    WorkspaceChangeSet changeSet,
  ) async => WorkspaceTransactionPreview(
    id: 'preview',
    changeSetId: changeSet.id,
    outcome: WorkspaceTransactionOutcome.ready,
    conflicts: const <WorkspaceConflict>[],
  );

  @override
  Future<WorkspaceTransactionReceipt> reject(String previewId) async =>
      const WorkspaceTransactionReceipt(
        id: 'reject',
        outcome: WorkspaceTransactionOutcome.rejected,
        workspaceRevision: 0,
      );

  @override
  Future<WorkspaceTransactionReceipt> rollback(String transactionId) async =>
      const WorkspaceTransactionReceipt(
        id: 'rollback',
        outcome: WorkspaceTransactionOutcome.rolledBack,
        workspaceRevision: 2,
      );
}
