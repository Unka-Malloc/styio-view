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
        toolCallId: 'tool-permission',
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

  test('terminal session state clears and rejects late permissions', () async {
    final store = AgentCollaborationStore(
      commands: _Commands(),
      transactions: _Transactions(),
      maxTimelineEntriesPerSession: 2,
    );
    await store.apply(_snapshot('one', 1, const <String>[]));
    await store.addPermission(
      const AgentPermissionRequest(
        id: 'pending',
        agentId: 'agent',
        sessionId: 'one',
        toolCallId: 'tool-pending',
        options: <String>{'allow_once'},
      ),
    );
    await store.apply(
      const AgentSessionSnapshot(
        sessionId: 'one',
        revision: 2,
        updates: <AgentSessionUpdate>[
          AgentSessionUpdate(
            sessionId: 'one',
            kind: 'session_state',
            payload: <String, Object?>{'id': 'failed', 'status': 'failed'},
          ),
        ],
      ),
    );
    await store.addPermission(
      const AgentPermissionRequest(
        id: 'late',
        agentId: 'agent',
        sessionId: 'one',
        toolCallId: 'tool-late',
        options: <String>{'allow_once'},
      ),
    );

    final session = store.projection.session('one');
    expect(session.status, CollaborationTaskStatus.failed);
    expect(session.pendingPermissions, isEmpty);
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
    await expectLater(
      store.proposeChange(
        sessionId: 'one',
        changeSet: WorkspaceChangeSet(
          id: 'change',
          baseWorkspaceRevision: 0,
          resources: <WorkspaceResourceChange>[
            WorkspaceResourceChange(
              resourceId: 'file',
              baseDocumentRevision: 0,
              edits: const <WorkspaceTextChange>[
                WorkspaceTextChange(start: 0, end: 6, replacement: 'different'),
              ],
            ),
          ],
        ),
      ),
      throwsA(
        isA<CollaborationFailure>().having(
          (failure) => failure.code,
          'code',
          'change_set_id_collision',
        ),
      ),
    );
    final rejected = await store.resolveChange(
      sessionId: 'one',
      changeSetId: 'change',
      decision: AgentChangeReviewDecision.reject,
    );
    expect(rejected.outcome, WorkspaceTransactionOutcome.rejected);
    expect(revisions.snapshot().document('file').text, 'before');
    await store.close();
  });

  test('failed rollback remains retryable without losing authority', () async {
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
    final committed = await store.resolveChange(
      sessionId: 'one',
      changeSetId: review.changeSet.id,
      decision: AgentChangeReviewDecision.commit,
    );
    revisions.failNextCommit();
    final failed = await store.resolveChange(
      sessionId: 'one',
      changeSetId: review.changeSet.id,
      decision: AgentChangeReviewDecision.revert,
    );
    expect(failed.outcome, WorkspaceTransactionOutcome.failed);
    expect(failed.transactionId, committed.transactionId);

    final retried = await store.resolveChange(
      sessionId: 'one',
      changeSetId: review.changeSet.id,
      decision: AgentChangeReviewDecision.revert,
    );
    expect(retried.outcome, WorkspaceTransactionOutcome.rolledBack);
    expect(retried.transactionId, isNull);
    expect(revisions.snapshot().document('file').text, 'before');
    await store.close();
  });

  test('session and change-review state is bounded and fails closed', () async {
    final store = AgentCollaborationStore(
      commands: _Commands(),
      transactions: _Transactions(),
      maxTimelineEntriesPerSession: 2,
      maxSessions: 1,
      maxChangeReviewsPerSession: 1,
      maxResourcesPerChangeSet: 1,
      maxEditsPerChangeSet: 1,
      maxReplacementCharactersPerChangeSet: 4,
    );
    await store.apply(_snapshot('one', 1, const <String>[]));

    await expectLater(
      store.apply(_snapshot('two', 1, const <String>[])),
      throwsA(
        isA<CollaborationFailure>().having(
          (failure) => failure.code,
          'code',
          'session_limit_exceeded',
        ),
      ),
    );
    await expectLater(
      store.proposeChange(
        sessionId: 'one',
        changeSet: WorkspaceChangeSet(
          id: 'oversized',
          baseWorkspaceRevision: 0,
          resources: <WorkspaceResourceChange>[
            WorkspaceResourceChange(
              resourceId: 'file',
              baseDocumentRevision: 0,
              edits: const <WorkspaceTextChange>[
                WorkspaceTextChange(start: 0, end: 0, replacement: '12345'),
              ],
            ),
          ],
        ),
      ),
      throwsA(
        isA<CollaborationFailure>().having(
          (failure) => failure.code,
          'code',
          'change_set_limit_exceeded',
        ),
      ),
    );

    await store.proposeChange(
      sessionId: 'one',
      changeSet: WorkspaceChangeSet(
        id: 'first',
        baseWorkspaceRevision: 0,
        resources: <WorkspaceResourceChange>[
          WorkspaceResourceChange(
            resourceId: 'file',
            baseDocumentRevision: 0,
            edits: const <WorkspaceTextChange>[
              WorkspaceTextChange(start: 0, end: 0, replacement: 'ok'),
            ],
          ),
        ],
      ),
    );
    await expectLater(
      store.proposeChange(
        sessionId: 'one',
        changeSet: WorkspaceChangeSet(
          id: 'second',
          baseWorkspaceRevision: 0,
          resources: <WorkspaceResourceChange>[
            WorkspaceResourceChange(
              resourceId: 'file',
              baseDocumentRevision: 0,
              edits: const <WorkspaceTextChange>[
                WorkspaceTextChange(start: 0, end: 0, replacement: 'ok'),
              ],
            ),
          ],
        ),
      ),
      throwsA(
        isA<CollaborationFailure>().having(
          (failure) => failure.code,
          'code',
          'change_review_limit_exceeded',
        ),
      ),
    );
    await store.close();
    expect(store.projection.sessions, isEmpty);
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
