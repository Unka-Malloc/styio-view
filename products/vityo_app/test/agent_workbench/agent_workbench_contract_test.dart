import 'package:vityo_app/src/ide/agent_client/agent_client.dart';
import 'package:vityo_app/src/ide/workbench/agent_collaboration/collaboration_store.dart';
import 'package:vityo_app/src/ide/workspace/workspace_change_set.dart';
import 'package:vityo_app/src/ide/workspace/workspace_revision_service.dart';
import 'package:vityo_app/src/ide/workspace/workspace_transaction_service.dart';
import 'package:test/test.dart';

void main() {
  test(
    'session reductions are isolated bounded and revision ordered',
    () async {
      final store = AgentCollaborationStore(
        commands: _Commands(),
        transactions: _Transactions(),
        maxTimelineEntriesPerSession: 2,
      );
      await Future.wait(<Future<CollaborationProjection>>[
        store.apply(_snapshot('one', 3, const <String>['a', 'b', 'c'])),
        store.apply(_snapshot('two', 2, const <String>['x'])),
      ]);

      expect(store.projection.session('one').timeline, hasLength(2));
      expect(store.projection.session('one').droppedTimelineCount, 1);
      expect(
        store.projection.session('one').timeline.map((entry) => entry.label),
        <String>['b', 'c'],
      );
      expect(store.projection.session('two').timeline.single.label, 'x');
      await expectLater(
        store.apply(_snapshot('one', 2, const <String>[])),
        throwsA(
          isA<CollaborationFailure>().having(
            (failure) => failure.code,
            'code',
            'stale_snapshot',
          ),
        ),
      );
      await store.close();
    },
  );

  test('permission failure remains pending and can be retried', () async {
    final commands = _Commands()..failPermission = true;
    final store = AgentCollaborationStore(
      commands: commands,
      transactions: _Transactions(),
      maxTimelineEntriesPerSession: 2,
    );
    await store.apply(_snapshot('one', 1, const <String>[]));
    await store.addPermission(
      const AgentPermissionRequest(
        id: 'permission',
        agentId: 'agent',
        sessionId: 'one',
        options: <String>{'allow_once'},
      ),
    );
    await expectLater(
      store.resolvePermission(
        sessionId: 'one',
        permissionId: 'permission',
        decision: AgentPermissionDecision.allowOnce,
      ),
      throwsStateError,
    );
    expect(
      store.projection.session('one').pendingPermissions,
      contains('permission'),
    );

    commands.failPermission = false;
    await store.resolvePermission(
      sessionId: 'one',
      permissionId: 'permission',
      decision: AgentPermissionDecision.allowOnce,
    );
    expect(store.projection.session('one').pendingPermissions, isEmpty);
    await store.close();
  });

  test('review state follows authoritative transaction receipts', () async {
    final revisions = InMemoryWorkspaceRevisionService(
      initialDocuments: const <String, String>{'file': 'before'},
    );
    final store = AgentCollaborationStore(
      commands: _Commands(),
      transactions: RevisionedWorkspaceTransactionService(revisions),
      maxTimelineEntriesPerSession: 2,
    );
    await store.apply(_snapshot('one', 1, const <String>[]));
    final review = await store.proposeChange(
      sessionId: 'one',
      changeSet: WorkspaceChangeSet(
        id: 'change',
        baseWorkspaceRevision: 0,
        resources: <WorkspaceResourceChange>[
          WorkspaceResourceChange(
            resourceId: 'file',
            baseDocumentRevision: 0,
            edits: const <WorkspaceTextChange>[
              WorkspaceTextChange(start: 0, end: 6, replacement: 'after'),
            ],
          ),
        ],
      ),
    );
    expect(review.outcome, WorkspaceTransactionOutcome.ready);
    final rejected = await store.resolveChange(
      sessionId: 'one',
      changeSetId: 'change',
      decision: AgentChangeReviewDecision.reject,
    );
    expect(rejected.outcome, WorkspaceTransactionOutcome.rejected);
    expect(revisions.snapshot().document('file').text, 'before');
    await store.close();
  });
}

AgentSessionSnapshot _snapshot(
  String sessionId,
  int revision,
  List<String> labels,
) => AgentSessionSnapshot(
  sessionId: sessionId,
  revision: revision,
  updates: <AgentSessionUpdate>[
    AgentSessionUpdate(
      sessionId: sessionId,
      kind: 'session_state',
      text: sessionId,
      payload: <String, Object?>{
        'id': 'state',
        'title': sessionId,
        'status': 'running',
      },
    ),
    for (var index = 0; index < labels.length; index += 1)
      AgentSessionUpdate(
        sessionId: sessionId,
        kind: 'turn',
        text: labels[index],
        payload: <String, Object?>{'id': '$index'},
      ),
  ],
);

final class _Commands implements AgentWorkbenchCommandPort {
  bool failPermission = false;

  @override
  Future<void> cancel(String sessionId) async {}

  @override
  Future<void> reconnect(String sessionId) async {}

  @override
  Future<void> resolvePermission({
    required String sessionId,
    required String permissionId,
    required AgentPermissionDecision decision,
  }) async {
    if (failPermission) {
      throw StateError('fixture denial');
    }
  }

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
