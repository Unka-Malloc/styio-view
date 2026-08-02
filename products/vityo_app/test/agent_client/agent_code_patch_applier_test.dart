import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/agent_client/agent_client.dart';
import 'package:vityo_app/src/ide/workspace/workspace_revision_service.dart';
import 'package:vityo_app/src/ide/workspace/workspace_transaction_service.dart';

void main() {
  test('rejects inconsistent document base revisions before preview', () async {
    final revisions = InMemoryWorkspaceRevisionService(
      initialDocuments: const <String, String>{'lib/a.dart': 'abcd'},
    );
    final result =
        await AgentCodePatchApplier(
          transactionService: RevisionedWorkspaceTransactionService(revisions),
          revisionService: revisions,
        ).apply(
          const AgentCodePatch(
            patchId: 'patch-1',
            edits: <AgentCodePatchEdit>[
              AgentCodePatchEdit(
                documentId: 'lib/a.dart',
                start: 0,
                end: 1,
                replacementText: 'A',
                baseRevision: 0,
              ),
              AgentCodePatchEdit(
                documentId: 'lib/a.dart',
                start: 2,
                end: 3,
                replacementText: 'C',
                baseRevision: 1,
              ),
            ],
          ),
        );

    expect(result.applied, isFalse);
    expect(result.message, contains('inconsistent base revisions'));
    expect(revisions.snapshot().document('lib/a.dart').text, 'abcd');
  });

  test('enforces aggregate replacement text limit', () async {
    final revisions = InMemoryWorkspaceRevisionService(
      initialDocuments: const <String, String>{'lib/a.dart': 'ab'},
    );
    final result =
        await AgentCodePatchApplier(
          transactionService: RevisionedWorkspaceTransactionService(revisions),
          revisionService: revisions,
        ).apply(
          AgentCodePatch(
            patchId: 'patch-2',
            edits: <AgentCodePatchEdit>[
              AgentCodePatchEdit(
                documentId: 'lib/a.dart',
                start: 0,
                end: 1,
                replacementText: 'x' * 100001,
              ),
              AgentCodePatchEdit(
                documentId: 'lib/a.dart',
                start: 1,
                end: 2,
                replacementText: 'y' * 100000,
              ),
            ],
          ),
        );

    expect(result.applied, isFalse);
    expect(result.message, contains('replacement text limit'));
    expect(revisions.snapshot().document('lib/a.dart').text, 'ab');
  });

  test('counts only edits committed for non-no-op documents', () async {
    final revisions = InMemoryWorkspaceRevisionService(
      initialDocuments: const <String, String>{
        'lib/a.dart': 'abc',
        'lib/b.dart': 'xyz',
      },
    );
    final result =
        await AgentCodePatchApplier(
          transactionService: RevisionedWorkspaceTransactionService(revisions),
          revisionService: revisions,
        ).apply(
          const AgentCodePatch(
            patchId: 'patch-3',
            edits: <AgentCodePatchEdit>[
              AgentCodePatchEdit(
                documentId: 'lib/a.dart',
                start: 0,
                end: 1,
                replacementText: 'A',
              ),
              AgentCodePatchEdit(
                documentId: 'lib/b.dart',
                start: 0,
                end: 1,
                replacementText: 'x',
              ),
            ],
          ),
        );

    expect(result.applied, isTrue);
    expect(result.appliedEditCount, 1);
    expect(result.appliedDocumentIds, <String>['lib/a.dart']);
    expect(result.skippedNoOpDocumentIds, <String>['lib/b.dart']);
  });
}
