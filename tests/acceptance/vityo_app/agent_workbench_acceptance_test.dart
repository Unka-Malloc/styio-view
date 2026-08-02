import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/agent_client/agent_client.dart';
import 'package:vityo_app/src/ide/workbench/agent_collaboration/collaboration_store.dart';
import 'package:vityo_app/src/ide/workspace/workspace_change_set.dart';
import 'package:vityo_app/src/ide/workspace/workspace_revision_service.dart';
import 'package:vityo_app/src/ide/workspace/workspace_transaction_service.dart';
import 'package:vityo_app/src/presentation/agent_workbench/change_review_view.dart';
import 'package:vityo_app/src/presentation/agent_workbench/session_view.dart';
import 'package:vityo_app/src/presentation/agent_workbench/task_center.dart';

void main() {
  /// REQ-IDE-004 / criterion 1 / concurrent normalized projections, bounded
  /// hot windows, reconnect replay, persistent attention, and routed controls.
  ///
  /// Precondition: two fake sessions with overlapping update IDs, one pending
  /// permission, and a four-entry per-session hot-window budget.
  /// Action: reduce both snapshots concurrently, replay one snapshot, render
  /// the task center and each session, then steer/cancel/approve.
  /// Oracle: ID namespaces never cross sessions; history reports omissions;
  /// replay is idempotent; background attention remains visible; every command
  /// carries the selected session/permission ID.
  testWidgets(
    'two concurrent sessions stay independent and route visible controls',
    (tester) async {
      final commands = _RecordingCommandPort();
      final store = AgentCollaborationStore(
        commands: commands,
        transactions: _RejectingTransactionService(),
        maxTimelineEntriesPerSession: 4,
      );
      final alpha = _snapshot(
        'alpha',
        7,
        status: 'running',
        title: 'Alpha task',
        entries: const <(String, String)>[
          ('turn', 'alpha turn'),
          ('plan', 'alpha plan'),
          ('step', 'alpha step'),
          ('tool', 'alpha tool'),
          ('artifact', 'alpha artifact'),
          ('diagnostic', 'alpha diagnostic'),
        ],
      );
      final beta = _snapshot(
        'beta',
        4,
        status: 'waiting_for_user',
        title: 'Beta task',
        entries: const <(String, String)>[
          ('turn', 'beta turn'),
          ('tool', 'beta tool'),
        ],
      );
      await Future.wait(<Future<CollaborationProjection>>[
        store.apply(alpha),
        store.apply(beta),
      ]);
      await store.addPermission(
        const AgentPermissionRequest(
          id: 'permission-beta',
          agentId: 'fixture-agent',
          sessionId: 'beta',
          toolCallId: 'tool-permission-beta',
          options: <String>{'allow_once', 'reject_once'},
        ),
      );
      final beforeReplay = store.projection;
      await store.apply(alpha);
      final afterReplay = store.projection;

      expect(afterReplay.sessions.keys.toSet(), <String>{'alpha', 'beta'});
      expect(
        afterReplay
            .session('alpha')
            .timeline
            .every((entry) => entry.sessionId == 'alpha'),
        isTrue,
      );
      expect(
        afterReplay
            .session('beta')
            .timeline
            .every((entry) => entry.sessionId == 'beta'),
        isTrue,
      );
      expect(afterReplay.session('alpha').timeline, hasLength(4));
      expect(afterReplay.session('alpha').droppedTimelineCount, 2);
      expect(
        afterReplay.session('alpha').timeline.map((entry) => entry.label),
        beforeReplay.session('alpha').timeline.map((entry) => entry.label),
      );
      expect(afterReplay.attentionCount, 1);

      String? selected;
      await tester.pumpWidget(
        _host(
          AgentTaskCenter(
            projection: afterReplay,
            selectedSessionId: 'alpha',
            onSelectSession: (sessionId) => selected = sessionId,
          ),
        ),
      );
      expect(find.text('Alpha task'), findsOneWidget);
      expect(find.text('Beta task'), findsOneWidget);
      expect(find.text('1 action required'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('agent-task-beta')));
      expect(selected, 'beta');

      await tester.pumpWidget(
        _host(
          AgentSessionView(
            session: afterReplay.session('alpha'),
            commands: commands,
          ),
        ),
      );
      expect(find.text('alpha diagnostic'), findsOneWidget);
      expect(find.text('beta tool'), findsNothing);
      await tester.enterText(
        find.byKey(const ValueKey<String>('agent-steer-input')),
        'focus tests',
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('agent-steer-submit')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('agent-cancel')));

      await tester.pumpWidget(
        _host(
          AgentSessionView(
            session: store.projection.session('beta'),
            commands: commands,
          ),
        ),
      );
      expect(find.text('Permission required'), findsOneWidget);
      await tester.tap(
        find.byKey(
          const ValueKey<String>('permission-permission-beta-allow_once'),
        ),
      );
      await tester.pump();

      expect(commands.steers, <String>['alpha:focus tests']);
      expect(commands.cancellations, <String>['alpha']);
      expect(commands.permissions, <String>['beta:permission-beta:allowOnce']);
      expect(store.projection.attentionCount, 0);
      expect(store.projection.session('beta').pendingPermissions, isEmpty);
      await store.close();
    },
  );

  /// REQ-IDE-004 / criterion 2 and REQ-IDE-007 / authoritative change review.
  ///
  /// Precondition: a real two-file revision store, a current proposal, and a
  /// second proposal bound to the old revision.
  /// Action: preview and accept the current proposal through the review
  /// surface, preview the stale proposal, then revert the committed change.
  /// Oracle: file/hunk review is visible; only WorkspaceTransactionService
  /// receipts change files; stale input is a conflict with no mutation; revert
  /// restores both resources through the same transaction authority.
  testWidgets(
    'multi-file review commits conflicts and reverts through transactions',
    (tester) async {
      final revisions = InMemoryWorkspaceRevisionService(
        initialDocuments: const <String, String>{
          'lib/a.dart': 'old a',
          'lib/b.dart': 'old b',
        },
      );
      final transactions = RevisionedWorkspaceTransactionService(revisions);
      final store = AgentCollaborationStore(
        commands: _RecordingCommandPort(),
        transactions: transactions,
        maxTimelineEntriesPerSession: 8,
      );
      await store.apply(
        _snapshot(
          'review',
          1,
          status: 'running',
          title: 'Review task',
          entries: const <(String, String)>[],
        ),
      );
      final proposal = WorkspaceChangeSet(
        id: 'change-current',
        baseWorkspaceRevision: 0,
        resources: <WorkspaceResourceChange>[
          WorkspaceResourceChange(
            resourceId: 'lib/a.dart',
            baseDocumentRevision: 0,
            edits: const <WorkspaceTextChange>[
              WorkspaceTextChange(start: 0, end: 5, replacement: 'new a'),
            ],
          ),
          WorkspaceResourceChange(
            resourceId: 'lib/b.dart',
            baseDocumentRevision: 0,
            edits: const <WorkspaceTextChange>[
              WorkspaceTextChange(start: 0, end: 5, replacement: 'new b'),
            ],
          ),
        ],
      );
      await store.proposeChange(sessionId: 'review', changeSet: proposal);

      await tester.pumpWidget(
        _host(
          AgentChangeReviewView(
            review: store.projection
                .session('review')
                .changeReviews['change-current']!,
            onDecision: (decision) => store.resolveChange(
              sessionId: 'review',
              changeSetId: 'change-current',
              decision: decision,
            ),
          ),
        ),
      );
      expect(find.text('lib/a.dart'), findsOneWidget);
      expect(find.text('lib/b.dart'), findsOneWidget);
      expect(find.text('2 files · 2 hunks'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('change-review-commit')),
      );
      await tester.pumpAndSettle();

      expect(revisions.snapshot().document('lib/a.dart').text, 'new a');
      expect(revisions.snapshot().document('lib/b.dart').text, 'new b');
      expect(
        store.projection
            .session('review')
            .changeReviews['change-current']!
            .outcome,
        WorkspaceTransactionOutcome.committed,
      );

      final stale = WorkspaceChangeSet(
        id: 'change-stale',
        baseWorkspaceRevision: 0,
        resources: <WorkspaceResourceChange>[
          WorkspaceResourceChange(
            resourceId: 'lib/a.dart',
            baseDocumentRevision: 0,
            edits: const <WorkspaceTextChange>[
              WorkspaceTextChange(start: 0, end: 5, replacement: 'unsafe'),
            ],
          ),
        ],
      );
      final conflicted = await store.proposeChange(
        sessionId: 'review',
        changeSet: stale,
      );
      expect(conflicted.outcome, WorkspaceTransactionOutcome.conflict);
      expect(revisions.snapshot().document('lib/a.dart').text, 'new a');

      final reverted = await store.resolveChange(
        sessionId: 'review',
        changeSetId: 'change-current',
        decision: AgentChangeReviewDecision.revert,
      );
      expect(reverted.outcome, WorkspaceTransactionOutcome.rolledBack);
      expect(revisions.snapshot().document('lib/a.dart').text, 'old a');
      expect(revisions.snapshot().document('lib/b.dart').text, 'old b');
      await store.close();
    },
  );

  /// REQ-IDE-004/007 / denial and session isolation.
  ///
  /// Precondition: one permission attached to session alpha.
  /// Action: resolve it from beta, then resolve it twice from alpha.
  /// Oracle: both invalid attempts fail before the command port; the valid
  /// decision is emitted exactly once and remains resolved after navigation.
  test('permission resolution is session-bound and exactly once', () async {
    final commands = _RecordingCommandPort();
    final store = AgentCollaborationStore(
      commands: commands,
      transactions: _RejectingTransactionService(),
      maxTimelineEntriesPerSession: 4,
    );
    await store.apply(
      _snapshot(
        'alpha',
        1,
        status: 'waiting_for_user',
        title: 'Alpha',
        entries: const <(String, String)>[],
      ),
    );
    await store.apply(
      _snapshot(
        'beta',
        1,
        status: 'running',
        title: 'Beta',
        entries: const <(String, String)>[],
      ),
    );
    await store.addPermission(
      const AgentPermissionRequest(
        id: 'permission-alpha',
        agentId: 'fixture-agent',
        sessionId: 'alpha',
        toolCallId: 'tool-permission-alpha',
        options: <String>{'allow_once'},
      ),
    );

    await expectLater(
      store.resolvePermission(
        sessionId: 'beta',
        permissionId: 'permission-alpha',
        decision: AgentPermissionDecision.allowOnce,
      ),
      throwsA(
        isA<CollaborationFailure>().having(
          (failure) => failure.code,
          'code',
          'permission_session_mismatch',
        ),
      ),
    );
    await store.resolvePermission(
      sessionId: 'alpha',
      permissionId: 'permission-alpha',
      decision: AgentPermissionDecision.allowOnce,
    );
    await expectLater(
      store.resolvePermission(
        sessionId: 'alpha',
        permissionId: 'permission-alpha',
        decision: AgentPermissionDecision.allowOnce,
      ),
      throwsA(
        isA<CollaborationFailure>().having(
          (failure) => failure.code,
          'code',
          'permission_already_resolved',
        ),
      ),
    );
    expect(commands.permissions, <String>['alpha:permission-alpha:allowOnce']);
    await store.close();
  });
}

AgentSessionSnapshot _snapshot(
  String sessionId,
  int revision, {
  required String status,
  required String title,
  required List<(String, String)> entries,
}) {
  final updates = <AgentSessionUpdate>[
    AgentSessionUpdate(
      sessionId: sessionId,
      kind: 'session_state',
      text: title,
      payload: <String, Object?>{
        'id': 'state',
        'status': status,
        'title': title,
      },
    ),
    for (var index = 0; index < entries.length; index += 1)
      AgentSessionUpdate(
        sessionId: sessionId,
        kind: entries[index].$1,
        text: entries[index].$2,
        payload: <String, Object?>{'id': 'shared-$index'},
      ),
  ];
  return AgentSessionSnapshot(
    sessionId: sessionId,
    revision: revision,
    updates: updates,
  );
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SizedBox(width: 900, height: 700, child: child)),
);

final class _RecordingCommandPort implements AgentWorkbenchCommandPort {
  final List<String> steers = <String>[];
  final List<String> cancellations = <String>[];
  final List<String> permissions = <String>[];

  @override
  Future<void> cancel(String sessionId) async {
    cancellations.add(sessionId);
  }

  @override
  Future<void> reconnect(String sessionId) async {}

  @override
  Future<void> resolvePermission({
    required String sessionId,
    required String permissionId,
    required AgentPermissionDecision decision,
  }) async {
    permissions.add('$sessionId:$permissionId:${decision.name}');
  }

  @override
  Future<void> retry(String sessionId) async {}

  @override
  Future<void> steer(String sessionId, String prompt) async {
    steers.add('$sessionId:$prompt');
  }
}

final class _RejectingTransactionService
    implements WorkspaceTransactionService {
  @override
  Future<WorkspaceTransactionReceipt> commit(String previewId) async =>
      const WorkspaceTransactionReceipt(
        id: 'rejected-fixture',
        outcome: WorkspaceTransactionOutcome.failed,
        workspaceRevision: 0,
      );

  @override
  Future<WorkspaceTransactionPreview> preview(
    WorkspaceChangeSet changeSet,
  ) async => WorkspaceTransactionPreview(
    id: 'preview-${changeSet.id}',
    changeSetId: changeSet.id,
    outcome: WorkspaceTransactionOutcome.ready,
    conflicts: const <WorkspaceConflict>[],
  );

  @override
  Future<WorkspaceTransactionReceipt> reject(String previewId) async =>
      const WorkspaceTransactionReceipt(
        id: 'rejected-fixture',
        outcome: WorkspaceTransactionOutcome.rejected,
        workspaceRevision: 0,
      );

  @override
  Future<WorkspaceTransactionReceipt> rollback(String transactionId) async =>
      const WorkspaceTransactionReceipt(
        id: 'rollback-fixture',
        outcome: WorkspaceTransactionOutcome.rolledBack,
        workspaceRevision: 0,
      );
}
