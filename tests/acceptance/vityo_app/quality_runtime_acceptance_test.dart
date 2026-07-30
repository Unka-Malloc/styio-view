import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/agent_client/agent_client.dart';
import 'package:vityo_app/src/ide/agent_client/agent_session_recovery_store.dart';
import 'package:vityo_app/src/ide/workbench/agent_collaboration/collaboration_store.dart';
import 'package:vityo_app/src/ide/workspace/workspace_change_set.dart';
import 'package:vityo_app/src/ide/workspace/workspace_transaction_service.dart';
import 'package:vityo_app/src/presentation/agent_workbench/session_view.dart';
import 'package:vityo_app/src/presentation/agent_workbench/task_center.dart';

void main() {
  /// REQ-IDE-008 / criterion 1 / backpressure and bounded memory.
  ///
  /// Precondition: a reducer with strict queue, byte, and hot-history budgets.
  /// Action: submit 200 payload-bearing events without awaiting each enqueue.
  /// Oracle: every input is either retained or explicitly counted as dropped;
  /// retained events and bytes stay within budget; the final event order is
  /// stable and no unbounded pending queue remains.
  test('event backpressure is bounded and never drops silently', () async {
    const policy = AgentEventBackpressurePolicy(
      maxQueuedEvents: 8,
      maxQueuedBytes: 4096,
      maxHotHistoryEvents: 5,
      maxHotHistoryBytes: 1536,
    );
    final reducer = AgentSessionReducer(
      sessionId: 'bounded',
      maxBufferedUpdates: policy.maxHotHistoryEvents,
      backpressurePolicy: policy,
    );
    final submitted = <Future<void>>[];
    for (var index = 0; index < 200; index += 1) {
      submitted.add(
        reducer.reduce(
          AgentSessionUpdate(
            sessionId: 'bounded',
            kind: 'tool',
            text: 'event-$index',
            payload: <String, Object?>{
              'id': '$index',
              'body': List<String>.filled(80, 'x').join(),
            },
          ),
        ),
      );
    }
    await Future.wait<void>(submitted);
    final snapshot = reducer.snapshot;
    expect(snapshot.updates.length, lessThanOrEqualTo(5));
    expect(snapshot.bufferedUpdateBytes, lessThanOrEqualTo(1536));
    expect(snapshot.droppedUpdateCount, greaterThan(0));
    expect(
      snapshot.acceptedUpdateCount + snapshot.droppedUpdateCount,
      200,
    );
    expect(snapshot.queuedUpdateCount, 0);
    final retainedIds = snapshot.updates
        .map((update) => int.parse(update.payload['id']! as String))
        .toList(growable: false);
    expect(
      retainedIds,
      orderedEquals(retainedIds.toList(growable: false)..sort()),
    );
    await reducer.close();
  });

  /// REQ-IDE-007/008 / criterion 1 / compact recovery, redaction, corruption.
  ///
  /// Precondition: a bounded recovery store and a projection containing
  /// bearer-shaped and sensitive-key material.
  /// Action: checkpoint, reconstruct after a simulated restart, then corrupt
  /// the durable payload and load again.
  /// Oracle: restored state keeps revisions/reconnect metadata and explicit
  /// omissions without containing secrets; corrupted state fails closed with
  /// a stable code rather than inventing a successful recovery.
  test('recovery is bounded redacted deterministic and fails closed', () async {
    final storage = MemoryAgentSessionRecoveryStorage();
    final store = AgentSessionRecoveryStore(
      storage: storage,
      maxSessions: 2,
      maxTimelineEntriesPerSession: 2,
      maxEncodedBytes: 4096,
    );
    await store.save(
      AgentRecoveryCheckpoint(
        sessionId: 'recoverable',
        agentId: 'fixture-agent',
        processGeneration: 3,
        protocolVersion: 1,
        workspaceRevision: 19,
        status: 'waiting_for_user',
        droppedUpdateCount: 4,
        timeline: <AgentSessionUpdate>[
          const AgentSessionUpdate(
            sessionId: 'recoverable',
            kind: 'turn',
            text: 'Bearer fixture-token',
            payload: <String, Object?>{'id': 'one'},
          ),
          const AgentSessionUpdate(
            sessionId: 'recoverable',
            kind: 'tool',
            text: 'tool finished',
            payload: <String, Object?>{
              'id': 'two',
              'authorization': 'private-value',
            },
          ),
          const AgentSessionUpdate(
            sessionId: 'recoverable',
            kind: 'receipt',
            text: 'validation passed',
            payload: <String, Object?>{'id': 'three'},
          ),
        ],
      ),
    );
    final encoded = await storage.read();
    expect(encoded, isNot(contains('fixture-token')));
    expect(encoded, isNot(contains('private-value')));

    final restarted = AgentSessionRecoveryStore(
      storage: storage,
      maxSessions: 2,
      maxTimelineEntriesPerSession: 2,
      maxEncodedBytes: 4096,
    );
    final recovered = await restarted.loadAll();
    expect(recovered, hasLength(1));
    expect(recovered.single.sessionId, 'recoverable');
    expect(recovered.single.workspaceRevision, 19);
    expect(recovered.single.processGeneration, 3);
    expect(recovered.single.timeline, hasLength(2));
    expect(recovered.single.droppedUpdateCount, 5);

    await storage.write('{"schemaVersion":1,"sessions":[');
    await expectLater(
      restarted.loadAll(),
      throwsA(
        isA<AgentSessionRecoveryFailure>().having(
          (failure) => failure.code,
          'code',
          'corrupted_projection',
        ),
      ),
    );
  });

  /// REQ-IDE-008 / criterion 1 / process failure isolation.
  ///
  /// Precondition: one healthy and one crashing supervised Agent descriptor.
  /// Action: connect the healthy Agent, attempt the crashing Agent, then query
  /// and use the healthy connection again.
  /// Oracle: the crashing descriptor reports process_failed while the sibling
  /// generation/capabilities remain usable and registry shutdown reaps it.
  test('one failed Agent process does not invalidate a sibling', () async {
    final fixture = File(
      '${Directory.current.path}${Platform.pathSeparator}..'
      '${Platform.pathSeparator}..${Platform.pathSeparator}tests'
      '${Platform.pathSeparator}acceptance${Platform.pathSeparator}fixtures'
      '${Platform.pathSeparator}vityo_app${Platform.pathSeparator}'
      'agent_client${Platform.pathSeparator}fake_agent.dart',
    );
    final registry = AgentClientRegistry(
      descriptors: <String, AgentLaunchDescriptor>{
        'healthy': AgentLaunchDescriptor(
          id: 'healthy',
          executable: Platform.resolvedExecutable,
          arguments: <String>['run', fixture.path, 'normal'],
          workingDirectory: Directory.current.path,
        ),
        'crash': AgentLaunchDescriptor(
          id: 'crash',
          executable: Platform.resolvedExecutable,
          arguments: <String>['run', fixture.path, 'crash'],
          workingDirectory: Directory.current.path,
        ),
      },
      policy: const AgentClientPolicy(
        requestTimeout: Duration(seconds: 3),
        shutdownTimeout: Duration(seconds: 2),
      ),
    );
    try {
      final healthy = await registry.connect('healthy');
      await expectLater(
        registry.connect('crash'),
        throwsA(
          isA<AgentClientFailure>().having(
            (failure) => failure.code,
            'code',
            'process_failed',
          ),
        ),
      );
      final stillHealthy = registry.connection('healthy');
      expect(stillHealthy.generation, healthy.generation);
      expect(stillHealthy.protocolVersion, 1);
      final session = await registry.newSession(
        agentId: 'healthy',
        cwd: Directory.current.uri,
      );
      expect(session.agentId, 'healthy');
    } finally {
      final receipts = await registry.close();
      expect(
        receipts.where((receipt) => receipt.agentId == 'healthy'),
        hasLength(1),
      );
    }
  });

  /// REQ-IDE-008 / criterion 1 / accessible virtualized collaboration.
  ///
  /// Precondition: 10,000 immutable timeline entries and one background
  /// permission requiring attention.
  /// Action: render task/session surfaces, traverse controls by keyboard, and
  /// inspect semantic labels.
  /// Oracle: only a visible-range number of rows is built, attention/control
  /// semantics are exposed, and keyboard activation routes to the exact
  /// session without rendering the full history.
  testWidgets(
    'large collaboration surfaces are virtualized and keyboard accessible',
    (tester) async {
      final commands = _Commands();
      final session = CollaborationSessionProjection(
        sessionId: 'large',
        snapshotRevision: 10,
        title: 'Large task',
        status: CollaborationTaskStatus.active,
        timeline: <CollaborationTimelineEntry>[
          for (var index = 0; index < 10000; index += 1)
            CollaborationTimelineEntry(
              id: 'large:turn:$index',
              sessionId: 'large',
              kind: CollaborationTimelineKind.turn,
              label: 'entry $index',
              payload: <String, Object?>{'id': '$index'},
            ),
        ],
        droppedTimelineCount: 20,
        pendingPermissions:
            const <String, CollaborationPermissionProjection>{},
        changeReviews: const <String, AgentChangeReviewProjection>{},
      );
      final projection = CollaborationProjection(
        revision: 1,
        sessions: <String, CollaborationSessionProjection>{'large': session},
        orderedSessionIds: const <String>['large'],
      );
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 900,
              height: 700,
              child: AgentSessionView(session: session, commands: commands),
            ),
          ),
        ),
      );
      expect(find.byType(ListTile), findsWidgets);
      expect(find.byType(ListTile).evaluate().length, lessThan(40));
      expect(find.bySemanticsLabel('Cancel Agent task'), findsOneWidget);
      expect(find.bySemanticsLabel('Reconnect Agent'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(commands.routedSessionIds.every((id) => id == 'large'), isTrue);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 500,
              child: AgentTaskCenter(
                projection: projection,
                onSelectSession: commands.routedSessionIds.add,
              ),
            ),
          ),
        ),
      );
      expect(find.bySemanticsLabel('Agent task center'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('agent-task-large')),
      );
      expect(commands.routedSessionIds.last, 'large');
      semantics.dispose();
    },
  );
}

final class _Commands implements AgentWorkbenchCommandPort {
  final List<String> routedSessionIds = <String>[];

  @override
  Future<void> cancel(String sessionId) async {
    routedSessionIds.add(sessionId);
  }

  @override
  Future<void> reconnect(String sessionId) async {
    routedSessionIds.add(sessionId);
  }

  @override
  Future<void> resolvePermission({
    required String sessionId,
    required String permissionId,
    required AgentPermissionDecision decision,
  }) async {
    routedSessionIds.add(sessionId);
  }

  @override
  Future<void> retry(String sessionId) async {
    routedSessionIds.add(sessionId);
  }

  @override
  Future<void> steer(String sessionId, String prompt) async {
    routedSessionIds.add(sessionId);
  }
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
