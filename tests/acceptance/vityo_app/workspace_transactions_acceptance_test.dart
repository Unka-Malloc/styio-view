import 'dart:io';

import 'package:vityo_app/src/ide/workspace/workspace_change_set.dart';
import 'package:vityo_app/src/ide/workspace/workspace_revision_service.dart';
import 'package:vityo_app/src/ide/workspace/workspace_transaction_service.dart';

Future<void> main() async {
  await _standaloneWorkspaceLifecycleNeedsNoAgent();
  await _transactionLifecycleIsRevisionBoundAndAtomic();
  _agentMutationBoundaryHasOneAuthority();
}

/// REQ-IDE-002 / criterion 1 / standalone IDE bootstrap seam.
///
/// Precondition: an empty in-memory IDE workspace and no Agent object.
/// Action: open, edit through the transaction authority, save, search, close.
/// Oracle: exact persisted text and search result at the committed revision,
/// followed by a closed session that rejects document access.
Future<void> _standaloneWorkspaceLifecycleNeedsNoAgent() async {
  final revisions = InMemoryWorkspaceRevisionService();
  final transactions = RevisionedWorkspaceTransactionService(revisions);
  final workspace = StandaloneIdeWorkspace(
    revisions: revisions,
    transactions: transactions,
  );

  await workspace.open(
    const <String, String>{
      'lib/main.dart': 'void main() {}\n',
      'README.md': 'Styio\n',
    },
  );
  final opened = workspace.openDocument('lib/main.dart');
  _expect(opened.text == 'void main() {}\n', 'open must expose exact text');

  final preview = await workspace.edit(
    WorkspaceChangeSet(
      id: 'manual-edit',
      baseWorkspaceRevision: opened.workspaceRevision,
      resources: <WorkspaceResourceChange>[
        WorkspaceResourceChange(
          resourceId: opened.resourceId,
          baseDocumentRevision: opened.documentRevision,
          edits: const <WorkspaceTextChange>[
            WorkspaceTextChange(start: 5, end: 9, replacement: 'start'),
          ],
        ),
      ],
    ),
  );
  _expect(preview.outcome == WorkspaceTransactionOutcome.ready,
      'a valid standalone edit must be previewable');
  final committed = await transactions.commit(preview.id);
  _expect(committed.outcome == WorkspaceTransactionOutcome.committed,
      'a standalone edit must commit');

  await workspace.save('lib/main.dart');
  _expect(
    workspace.persistedText('lib/main.dart') == 'void start() {}\n',
    'save must persist the committed revision exactly',
  );
  final matches = workspace.search('start');
  _expect(
    matches.length == 1 &&
        matches.single.resourceId == 'lib/main.dart' &&
        matches.single.start == 5,
    'search must observe the same committed revision',
  );

  workspace.close();
  _expectThrows(
    () => workspace.openDocument('lib/main.dart'),
    'closed workspace must reject document access',
  );
}

/// REQ-IDE-002 / criterion 2 / in-memory store, stale revision, and
/// mid-commit failure seams.
///
/// The exact before/after snapshots are the oracle: preview and reject never
/// mutate; stale/overlap/failure outcomes preserve every resource; commit and
/// rollback change all resources together and publish one workspace revision.
Future<void> _transactionLifecycleIsRevisionBoundAndAtomic() async {
  final revisions = InMemoryWorkspaceRevisionService(
    initialDocuments: const <String, String>{
      'a.txt': 'alpha',
      'b.txt': 'bravo',
    },
  );
  final transactions = RevisionedWorkspaceTransactionService(revisions);
  final initial = revisions.snapshot();

  final rejectedPreview = await transactions.preview(
    _twoFileChange(initial, id: 'reject-me'),
  );
  _expect(revisions.snapshot() == initial, 'preview must not mutate');
  final rejected = await transactions.reject(rejectedPreview.id);
  _expect(
    rejected.outcome == WorkspaceTransactionOutcome.rejected &&
        revisions.snapshot() == initial,
    'reject must be terminal and mutation-free',
  );

  final commitPreview = await transactions.preview(
    _twoFileChange(initial, id: 'commit-me'),
  );
  final committed = await transactions.commit(commitPreview.id);
  final afterCommit = revisions.snapshot();
  _expect(
    committed.outcome == WorkspaceTransactionOutcome.committed &&
        afterCommit.workspaceRevision == initial.workspaceRevision + 1 &&
        afterCommit.document('a.txt').text == 'ALPHA' &&
        afterCommit.document('b.txt').text == 'BRAVO',
    'commit must atomically publish exact multi-resource results',
  );

  final stale = await transactions.preview(
    _twoFileChange(initial, id: 'stale'),
  );
  _expect(
    stale.outcome == WorkspaceTransactionOutcome.conflict &&
        stale.conflicts.any(
          (conflict) =>
              conflict.kind == WorkspaceConflictKind.staleWorkspaceRevision,
        ) &&
        revisions.snapshot() == afterCommit,
    'a stale base revision must fail before mutation',
  );

  final overlapping = await transactions.preview(
    WorkspaceChangeSet(
      id: 'overlap',
      baseWorkspaceRevision: afterCommit.workspaceRevision,
      resources: <WorkspaceResourceChange>[
        WorkspaceResourceChange(
          resourceId: 'a.txt',
          baseDocumentRevision: afterCommit.document('a.txt').revision,
          edits: const <WorkspaceTextChange>[
            WorkspaceTextChange(start: 0, end: 3, replacement: 'x'),
            WorkspaceTextChange(start: 2, end: 4, replacement: 'y'),
          ],
        ),
      ],
    ),
  );
  _expect(
    overlapping.outcome == WorkspaceTransactionOutcome.conflict &&
        overlapping.conflicts.any(
          (conflict) =>
              conflict.kind == WorkspaceConflictKind.overlappingEdits,
        ) &&
        revisions.snapshot() == afterCommit,
    'overlapping ranges must be rejected without mutation',
  );

  revisions.failNextCommit();
  final failedPreview = await transactions.preview(
    _twoFileChange(afterCommit, id: 'fail-before-swap', upperCase: false),
  );
  final failed = await transactions.commit(failedPreview.id);
  _expect(
    failed.outcome == WorkspaceTransactionOutcome.failed &&
        revisions.snapshot() == afterCommit,
    'an injected commit failure must leave zero partial mutation',
  );

  final rolledBack = await transactions.rollback(committed.id);
  final afterRollback = revisions.snapshot();
  _expect(
    rolledBack.outcome == WorkspaceTransactionOutcome.rolledBack &&
        afterRollback.workspaceRevision == afterCommit.workspaceRevision + 1 &&
        afterRollback.document('a.txt').text == initial.document('a.txt').text &&
        afterRollback.document('b.txt').text == initial.document('b.txt').text,
    'rollback must atomically restore the receipted before-image',
  );
}

WorkspaceChangeSet _twoFileChange(
  WorkspaceSnapshot snapshot, {
  required String id,
  bool upperCase = true,
}) {
  return WorkspaceChangeSet(
    id: id,
    baseWorkspaceRevision: snapshot.workspaceRevision,
    resources: <WorkspaceResourceChange>[
      WorkspaceResourceChange(
        resourceId: 'a.txt',
        baseDocumentRevision: snapshot.document('a.txt').revision,
        edits: <WorkspaceTextChange>[
          WorkspaceTextChange(
            start: 0,
            end: 5,
            replacement: upperCase ? 'ALPHA' : 'alpha!',
          ),
        ],
      ),
      WorkspaceResourceChange(
        resourceId: 'b.txt',
        baseDocumentRevision: snapshot.document('b.txt').revision,
        edits: <WorkspaceTextChange>[
          WorkspaceTextChange(
            start: 0,
            end: 5,
            replacement: upperCase ? 'BRAVO' : 'bravo!',
          ),
        ],
      ),
    ],
  );
}

/// REQ-IDE-002 / authoritative host boundary.
///
/// Precondition: the final IDE domain and any Agent patch adapters exist.
/// Action: inspect source dependencies and the retired topology.
/// Oracle: editor/workspace import no Agent layer, Agent patch adapters depend
/// on WorkspaceTransactionService and never on concrete stores/controllers,
/// and the migrated editor/workspace directories have no old implementation.
void _agentMutationBoundaryHasOneAuthority() {
  final repository = File.fromUri(Platform.script).parent.parent.parent.parent;
  final product = Directory.fromUri(
    repository.uri.resolve('products/vityo_app/'),
  );
  for (final relative in const <String>[
    'lib/src/ide/editor',
    'lib/src/ide/workspace',
  ]) {
    final root = Directory.fromUri(product.uri.resolve('$relative/'));
    _expect(root.existsSync(), '$relative must exist');
    for (final file in root
        .listSync(recursive: true)
        .whereType<File>()
        .where((entry) => entry.path.endsWith('.dart'))) {
      final source = file.readAsStringSync();
      _expect(
        !source.contains('/agent_client/') &&
            !source.contains('../agent_client') &&
            !source.contains('package:vityo_coding_agent/'),
        '${file.path} must remain Agent-independent',
      );
    }
  }

  for (final retired in const <String>[
    'lib/src/view_ide/editor',
    'lib/src/view_ide/workspace',
  ]) {
    _expect(
      !Directory.fromUri(product.uri.resolve('$retired/')).existsSync(),
      '$retired retains the pre-cutover implementation',
    );
  }

  final sourceRoot = Directory.fromUri(product.uri.resolve('lib/src/'));
  final patchAdapters = sourceRoot
      .listSync(recursive: true)
      .whereType<File>()
      .where(
        (entry) {
          final name = entry.uri.pathSegments.last.toLowerCase();
          return entry.path.endsWith('.dart') &&
              (name.startsWith('agent_patch_') ||
                  name.startsWith('agent_code_patch_'));
        },
      )
      .toList(growable: false);
  _expect(patchAdapters.isNotEmpty, 'an Agent patch adapter must be present');
  for (final adapter in patchAdapters) {
    final source = adapter.readAsStringSync();
    _expect(
      source.contains('WorkspaceTransactionService') &&
          !source.contains('WorkspaceDocumentStore') &&
          !source.contains('EditorSessionController') &&
          !source.contains('.save('),
      '${adapter.path} bypasses the authoritative transaction service',
    );
  }
}

void _expectThrows(void Function() action, String message) {
  try {
    action();
  } catch (_) {
    return;
  }
  throw StateError(message);
}

void _expect(bool condition, String message) {
  if (!condition) {
    throw StateError(message);
  }
}
