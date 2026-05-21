import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/editor_controller.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test(
    'agent workspace snapshot captures active and inactive documents',
    () async {
      final controller = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'src/main.styio',
          text: 'value = 1\n',
          revision: 3,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/other.styio': DocumentState(
            documentId: 'src/other.styio',
            text: 'other = 1\n',
            revision: 2,
          ),
        },
      );
      const patch = AgentCodePatch(
        patchId: 'patch-snapshot',
        summary: 'Change two files.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'src/main.styio',
            start: 8,
            end: 9,
            replacementText: '2',
          ),
          AgentCodePatchEdit(
            documentId: 'src/other.styio',
            start: 8,
            end: 9,
            replacementText: '2',
          ),
        ],
      );

      final result =
          await AgentWorkspaceSnapshotService(
            editorController: controller,
            workspaceDocumentStore: store,
          ).captureBeforePatch(
            patch,
            capturedAt: DateTime.utc(2026, 5, 22),
            snapshotId: 'snapshot-1',
          );
      final snapshot = result.snapshot!;

      expect(result.status, AgentWorkspaceSnapshotCaptureStatus.captured);
      expect(result.captured, isTrue);
      expect(snapshot.snapshotId, 'snapshot-1');
      expect(snapshot.patchId, 'patch-snapshot');
      expect(snapshot.complete, isTrue);
      expect(snapshot.documentIds, <String>[
        'src/main.styio',
        'src/other.styio',
      ]);
      expect(snapshot.documentFor('src/main.styio')!.text, 'value = 1\n');
      expect(snapshot.documentFor('src/other.styio')!.revision, 2);
      expect(snapshot.toJson()['documentCount'], 2);
      expect(snapshot.todoItems, isEmpty);
    },
  );

  test(
    'agent workspace snapshot records documents created by a patch',
    () async {
      final controller = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'src/main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      final store = InMemoryWorkspaceDocumentStore();
      const patch = AgentCodePatch(
        patchId: 'patch-create',
        summary: 'Create file.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'src/new.styio',
            operation: AgentCodePatchEditOperation.create,
            start: 0,
            end: 0,
            replacementText: 'new = 1\n',
          ),
        ],
      );

      final result = await AgentWorkspaceSnapshotService(
        editorController: controller,
        workspaceDocumentStore: store,
      ).captureBeforePatch(patch, snapshotId: 'snapshot-create');
      final snapshot = result.snapshot!;

      expect(snapshot.documentFor('src/new.styio')!.existed, isFalse);
      expect(snapshot.documentFor('src/new.styio')!.text, isEmpty);
      expect(snapshot.complete, isTrue);
    },
  );

  test(
    'agent workspace snapshot builds revert plan for modified and added files',
    () async {
      final controller = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'src/main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      final store = InMemoryWorkspaceDocumentStore();
      final service = AgentWorkspaceSnapshotService(
        editorController: controller,
        workspaceDocumentStore: store,
      );
      final snapshot = AgentWorkspaceChangeSnapshot(
        snapshotId: 'snapshot-revert',
        patchId: 'patch-after',
        activeDocumentId: 'src/main.styio',
        capturedAt: DateTime.utc(2026, 5, 22),
        documents: const <AgentWorkspaceSnapshotDocument>[
          AgentWorkspaceSnapshotDocument(
            documentId: 'src/main.styio',
            existed: true,
            text: 'value = 1\n',
            revision: 1,
          ),
          AgentWorkspaceSnapshotDocument(
            documentId: 'src/new.styio',
            existed: false,
            text: '',
            revision: 0,
          ),
        ],
      );

      controller.applyFormattingEdits(const <FormattingEdit>[
        FormattingEdit(range: SourceRange(start: 8, end: 9), newText: '2'),
      ]);
      await store.saveDocument(
        const DocumentState(
          documentId: 'src/new.styio',
          text: 'new = 1\n',
          revision: 1,
        ),
      );

      final plan = await service.buildRevertPlan(snapshot);
      final activeRevert = plan.patch.edits.singleWhere(
        (edit) => edit.documentId == 'src/main.styio',
      );
      final createdFileRevert = plan.patch.edits.singleWhere(
        (edit) => edit.documentId == 'src/new.styio',
      );

      expect(plan.status, AgentWorkspaceRevertPlanStatus.ready);
      expect(plan.ready, isTrue);
      expect(plan.diffSummary.modifiedDocumentIds, <String>['src/main.styio']);
      expect(plan.diffSummary.addedDocumentIds, <String>['src/new.styio']);
      expect(plan.diffSummary.changedDocumentCount, 2);
      expect(activeRevert.operation, AgentCodePatchEditOperation.replace);
      expect(activeRevert.start, 0);
      expect(activeRevert.end, 'value = 2\n'.length);
      expect(activeRevert.replacementText, 'value = 1\n');
      expect(createdFileRevert.operation, AgentCodePatchEditOperation.delete);
      expect(plan.toJson()['status'], 'ready');
      expect(plan.todoItems, isEmpty);
    },
  );

  test(
    'agent workspace snapshot marks inactive documents unavailable without store',
    () async {
      final controller = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'src/main.styio',
          text: 'value = 1\n',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      );
      const patch = AgentCodePatch(
        patchId: 'patch-partial',
        summary: 'Change inactive file.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'src/main.styio',
            start: 8,
            end: 9,
            replacementText: '2',
          ),
          AgentCodePatchEdit(
            documentId: 'src/missing-store.styio',
            start: 0,
            end: 0,
            replacementText: 'value = 3\n',
          ),
        ],
      );

      final result = await AgentWorkspaceSnapshotService(
        editorController: controller,
      ).captureBeforePatch(patch, snapshotId: 'snapshot-partial');
      final snapshot = result.snapshot!;

      expect(result.status, AgentWorkspaceSnapshotCaptureStatus.partial);
      expect(snapshot.complete, isFalse);
      expect(snapshot.documentIds, <String>['src/main.styio']);
      expect(snapshot.unavailableDocumentIds, <String>[
        'src/missing-store.styio',
      ]);
    },
  );
}
