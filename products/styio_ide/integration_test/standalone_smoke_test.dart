import 'package:styio_ide/src/ide/workspace/workspace_change_set.dart';
import 'package:styio_ide/src/ide/workspace/workspace_revision_service.dart';
import 'package:styio_ide/src/ide/workspace/workspace_transaction_service.dart';

Future<void> main() async {
  final revisions = InMemoryWorkspaceRevisionService();
  final transactions = RevisionedWorkspaceTransactionService(revisions);
  final workspace = StandaloneIdeWorkspace(
    revisions: revisions,
    transactions: transactions,
  );
  await workspace.open(
    const <String, String>{'main.dart': 'void main() {}\n'},
  );
  final document = workspace.openDocument('main.dart');
  final preview = await workspace.edit(
    WorkspaceChangeSet(
      id: 'standalone',
      baseWorkspaceRevision: document.workspaceRevision,
      resources: <WorkspaceResourceChange>[
        WorkspaceResourceChange(
          resourceId: document.resourceId,
          baseDocumentRevision: document.revision,
          edits: const <WorkspaceTextChange>[
            WorkspaceTextChange(start: 5, end: 9, replacement: 'start'),
          ],
        ),
      ],
    ),
  );
  _expect(
    (await transactions.commit(preview.id)).outcome ==
        WorkspaceTransactionOutcome.committed,
    'standalone edit must commit',
  );
  await workspace.save('main.dart');
  _expect(
    workspace.persistedText('main.dart') == 'void start() {}\n',
    'standalone save must persist the committed text',
  );
  _expect(
    workspace.search('start').length == 1,
    'standalone search must observe the committed revision',
  );
  workspace.close();
  try {
    workspace.openDocument('main.dart');
  } on StateError {
    return;
  }
  throw StateError('closed standalone workspace accepted document access');
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
