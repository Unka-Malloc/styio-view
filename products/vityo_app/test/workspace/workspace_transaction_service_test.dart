import 'package:test/test.dart';
import 'package:vityo_app/src/ide/workspace/workspace_change_set.dart';
import 'package:vityo_app/src/ide/workspace/workspace_revision_service.dart';
import 'package:vityo_app/src/ide/workspace/workspace_transaction_service.dart';

void main() {
  test('multi-resource commit is atomic and rollback is revisioned', () async {
    final revisions = InMemoryWorkspaceRevisionService(
      initialDocuments: const <String, String>{'a': 'one', 'b': 'two'},
    );
    final service = RevisionedWorkspaceTransactionService(revisions);
    final before = revisions.snapshot();
    final preview = await service.preview(
      WorkspaceChangeSet(
        id: 'change',
        baseWorkspaceRevision: before.workspaceRevision,
        resources: <WorkspaceResourceChange>[
          WorkspaceResourceChange(
            resourceId: 'a',
            baseDocumentRevision: before.document('a').revision,
            edits: const <WorkspaceTextChange>[
              WorkspaceTextChange(start: 0, end: 3, replacement: 'ONE'),
            ],
          ),
          WorkspaceResourceChange(
            resourceId: 'b',
            baseDocumentRevision: before.document('b').revision,
            edits: const <WorkspaceTextChange>[
              WorkspaceTextChange(start: 0, end: 3, replacement: 'TWO'),
            ],
          ),
        ],
      ),
    );

    final committed = await service.commit(preview.id);
    expect(committed.outcome, WorkspaceTransactionOutcome.committed);
    expect(revisions.snapshot().document('a').text, 'ONE');
    expect(revisions.snapshot().document('b').text, 'TWO');

    final rolledBack = await service.rollback(committed.id);
    expect(rolledBack.outcome, WorkspaceTransactionOutcome.rolledBack);
    expect(revisions.snapshot().document('a').text, 'one');
    expect(revisions.snapshot().document('b').text, 'two');
  });

  test('stale, overlap, and injected failure never mutate', () async {
    final revisions = InMemoryWorkspaceRevisionService(
      initialDocuments: const <String, String>{'a': 'alpha'},
    );
    final service = RevisionedWorkspaceTransactionService(revisions);
    final before = revisions.snapshot();

    final overlap = await service.preview(
      WorkspaceChangeSet(
        id: 'overlap',
        baseWorkspaceRevision: before.workspaceRevision,
        resources: <WorkspaceResourceChange>[
          WorkspaceResourceChange(
            resourceId: 'a',
            baseDocumentRevision: before.document('a').revision,
            edits: const <WorkspaceTextChange>[
              WorkspaceTextChange(start: 0, end: 3, replacement: 'x'),
              WorkspaceTextChange(start: 2, end: 4, replacement: 'y'),
            ],
          ),
        ],
      ),
    );
    expect(overlap.outcome, WorkspaceTransactionOutcome.conflict);
    expect(revisions.snapshot(), before);

    revisions.failNextCommit();
    final ready = await service.preview(
      WorkspaceChangeSet(
        id: 'failure',
        baseWorkspaceRevision: before.workspaceRevision,
        resources: <WorkspaceResourceChange>[
          WorkspaceResourceChange(
            resourceId: 'a',
            baseDocumentRevision: before.document('a').revision,
            edits: const <WorkspaceTextChange>[
              WorkspaceTextChange(start: 0, end: 5, replacement: 'ALPHA'),
            ],
          ),
        ],
      ),
    );
    expect((await service.commit(ready.id)).outcome,
        WorkspaceTransactionOutcome.failed);
    expect(revisions.snapshot(), before);
  });
}
