import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_code_patch_applier.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/editor_controller.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('agent code patch applies edits through editor controller', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: '/workspace/demo/src/main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentCodePatchApplier(editorController: controller);
    const patch = AgentCodePatch(
      patchId: 'patch-1',
      summary: 'Change value.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: '/workspace/demo/src/main.styio',
          start: 8,
          end: 9,
          replacementText: '2',
        ),
      ],
    );

    final result = applier.apply(patch);

    expect(result.applied, isTrue);
    expect(result.appliedEditCount, 1);
    expect(result.appliedOperationCounts, <String, int>{'replace': 1});
    expect(result.appliedDocumentIds, <String>['/workspace/demo/src/main.styio']);
    expect(result.createdDocumentIds, isEmpty);
    expect(result.deletedDocumentIds, isEmpty);
    expect(result.message, contains('Operations: replace 1'));
    expect(controller.document.text, 'value = 2\n');
    expect(controller.canUndo, isTrue);
  });

  test('agent code patch skips active no-op edits without undo', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: '/workspace/demo/src/main.styio',
        text: 'value = 1\n',
        revision: 5,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentCodePatchApplier(editorController: controller);
    const patch = AgentCodePatch(
      patchId: 'patch-noop-active',
      summary: 'No-op active edit.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: '/workspace/demo/src/main.styio',
          start: 0,
          end: 5,
          replacementText: 'value',
        ),
      ],
    );

    final result = applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.appliedEditCount, 0);
    expect(result.skippedNoOpDocumentIds, <String>[
      '/workspace/demo/src/main.styio',
    ]);
    expect(result.message, contains('produced no text changes'));
    expect(controller.document.text, 'value = 1\n');
    expect(controller.document.revision, 5);
    expect(controller.canUndo, isFalse);
  });

  test('agent code patch applies multiple non-overlapping edits', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: '/workspace/demo/src/main.styio',
        text: 'alpha beta\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentCodePatchApplier(editorController: controller);
    const patch = AgentCodePatch(
      patchId: 'patch-multi',
      summary: 'Change two words.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: '/workspace/demo/src/main.styio',
          start: 0,
          end: 5,
          replacementText: 'one',
        ),
        AgentCodePatchEdit(
          documentId: '/workspace/demo/src/main.styio',
          start: 6,
          end: 10,
          replacementText: 'two',
        ),
      ],
    );

    final result = applier.apply(patch);

    expect(result.applied, isTrue);
    expect(result.appliedEditCount, 2);
    expect(controller.document.text, 'one two\n');
    expect(controller.canUndo, isTrue);
  });

  test('agent code patch rejects edits for unopened documents', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: '/workspace/demo/src/main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentCodePatchApplier(editorController: controller);
    const patch = AgentCodePatch(
      patchId: 'patch-2',
      summary: 'Change another file.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: '/workspace/demo/src/other.styio',
          start: 0,
          end: 0,
          replacementText: 'value = 2\n',
        ),
      ],
    );

    final result = applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.appliedEditCount, 0);
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent code patch rejects stale base revision', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: '/workspace/demo/src/main.styio',
        text: 'value = 1\n',
        revision: 3,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentCodePatchApplier(editorController: controller);
    const patch = AgentCodePatch(
      patchId: 'patch-stale',
      summary: 'Change stale value.',
      baseRevision: 2,
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: '/workspace/demo/src/main.styio',
          start: 8,
          end: 9,
          replacementText: '2',
        ),
      ],
    );

    final result = applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.message, contains('revision 2'));
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent code patch rejects invalid edit ranges', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: '/workspace/demo/src/main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentCodePatchApplier(editorController: controller);
    const patch = AgentCodePatch(
      patchId: 'patch-3',
      summary: 'Invalid edit.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: '/workspace/demo/src/main.styio',
          start: 20,
          end: 21,
          replacementText: '2',
        ),
      ],
    );

    final result = applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.appliedEditCount, 0);
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent code patch rejects oversized replacement text', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentCodePatchApplier(editorController: controller);
    final patch = AgentCodePatch(
      patchId: 'patch-oversized-replacement',
      summary: 'Oversized edit.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'main.styio',
          start: 0,
          end: 0,
          replacementText: List<String>.filled(200001, 'x').join(),
        ),
      ],
    );

    final result = applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.message, contains('too large'));
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent code patch rejects too many active edits', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentCodePatchApplier(editorController: controller);
    final patch = AgentCodePatch(
      patchId: 'patch-too-many-active-edits',
      summary: 'Too many edits.',
      edits: List<AgentCodePatchEdit>.generate(
        501,
        (_) => const AgentCodePatchEdit(
          documentId: 'main.styio',
          start: 0,
          end: 0,
          replacementText: 'x',
        ),
      ),
    );

    final result = applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.message, contains('too many edits'));
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent code patch rejects empty document id', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: '',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentCodePatchApplier(editorController: controller);
    const patch = AgentCodePatch(
      patchId: 'patch-empty-document',
      summary: 'Invalid document.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: '',
          start: 0,
          end: 1,
          replacementText: 'x',
        ),
      ],
    );

    final result = applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.message, contains('without documentId'));
    expect(controller.document.text, 'value = 1\n');
  });

  test('agent code patch rejects path traversal document id', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: '../secret.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentCodePatchApplier(editorController: controller);
    const patch = AgentCodePatch(
      patchId: 'patch-unsafe-document',
      summary: 'Unsafe document.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: '../secret.styio',
          start: 0,
          end: 1,
          replacementText: 'x',
        ),
      ],
    );

    final result = applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.message, contains('unsafe documentId'));
    expect(controller.document.text, 'value = 1\n');
  });

  test('agent workspace code patch rejects unsafe document id before store access', () async {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentWorkspaceCodePatchApplier(
      editorController: controller,
      workspaceDocumentStore: _AccessFailingWorkspaceDocumentStore(),
    );
    const patch = AgentCodePatch(
      patchId: 'patch-unsafe-workspace-document',
      summary: 'Unsafe workspace document.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: '../secret.styio',
          operation: AgentCodePatchEditOperation.create,
          start: 0,
          end: 0,
          replacementText: 'x',
        ),
      ],
    );

    final result = await applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.message, contains('unsafe documentId'));
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent workspace code patch rejects too many edits before store access', () async {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentWorkspaceCodePatchApplier(
      editorController: controller,
      workspaceDocumentStore: _AccessFailingWorkspaceDocumentStore(),
    );
    final patch = AgentCodePatch(
      patchId: 'patch-too-many-workspace-edits',
      summary: 'Too many workspace edits.',
      edits: List<AgentCodePatchEdit>.generate(
        501,
        (_) => const AgentCodePatchEdit(
          documentId: 'other.txt',
          start: 0,
          end: 0,
          replacementText: 'x',
        ),
      ),
    );

    final result = await applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.message, contains('too many edits'));
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent workspace code patch rejects inactive dirty documents before store access', () async {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentWorkspaceCodePatchApplier(
      editorController: controller,
      workspaceDocumentStore: _AccessFailingWorkspaceDocumentStore(),
      dirtyDocumentIds: const <String>['other.styio'],
    );
    const patch = AgentCodePatch(
      patchId: 'patch-inactive-dirty',
      summary: 'Update a dirty inactive file.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'other.styio',
          baseRevision: 1,
          start: 0,
          end: 5,
          replacementText: 'next',
        ),
      ],
    );

    final result = await applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.message, contains('inactive dirty document other.styio'));
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent code patch rejects overlapping edit ranges', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: '/workspace/demo/src/main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentCodePatchApplier(editorController: controller);
    const patch = AgentCodePatch(
      patchId: 'patch-4',
      summary: 'Overlapping edit.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: '/workspace/demo/src/main.styio',
          start: 0,
          end: 7,
          replacementText: 'count',
        ),
        AgentCodePatchEdit(
          documentId: '/workspace/demo/src/main.styio',
          start: 6,
          end: 9,
          replacementText: '2',
        ),
      ],
    );

    final result = applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.message, contains('overlapping'));
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent code patch rejects ambiguous same-offset insert edits', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: '/workspace/demo/src/main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentCodePatchApplier(editorController: controller);
    const patch = AgentCodePatch(
      patchId: 'patch-same-offset-inserts',
      summary: 'Ambiguous insert ordering.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: '/workspace/demo/src/main.styio',
          start: 0,
          end: 0,
          replacementText: 'first\n',
        ),
        AgentCodePatchEdit(
          documentId: '/workspace/demo/src/main.styio',
          start: 0,
          end: 0,
          replacementText: 'second\n',
        ),
      ],
    );

    final result = applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.message, contains('same-offset insert'));
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent workspace code patch applies active and stored documents', () async {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'other.styio': DocumentState(
          documentId: 'other.styio',
          text: 'name = old\n',
          revision: 7,
        ),
      },
    );
    final applier = AgentWorkspaceCodePatchApplier(
      editorController: controller,
      workspaceDocumentStore: store,
    );
    const patch = AgentCodePatch(
      patchId: 'patch-workspace',
      summary: 'Update two files.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'main.styio',
          baseRevision: 1,
          start: 8,
          end: 9,
          replacementText: '2',
        ),
        AgentCodePatchEdit(
          documentId: 'other.styio',
          baseRevision: 7,
          start: 7,
          end: 10,
          replacementText: 'new',
        ),
      ],
    );

    final result = await applier.apply(patch);
    final otherDocument = await store.loadDocument('other.styio');

    expect(result.applied, isTrue);
    expect(result.appliedEditCount, 2);
    expect(result.appliedOperationCounts, <String, int>{'replace': 2});
    expect(result.appliedDocumentIds, unorderedEquals(<String>['main.styio', 'other.styio']));
    expect(result.createdDocumentIds, isEmpty);
    expect(result.deletedDocumentIds, isEmpty);
    expect(controller.document.text, 'value = 2\n');
    expect(otherDocument.text, 'name = new\n');
    expect(otherDocument.revision, 8);
  });

  test('agent workspace code patch skips inactive no-op edits', () async {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'other.styio': DocumentState(
          documentId: 'other.styio',
          text: 'name = old\n',
          revision: 7,
        ),
      },
    );
    final applier = AgentWorkspaceCodePatchApplier(
      editorController: controller,
      workspaceDocumentStore: store,
    );
    const patch = AgentCodePatch(
      patchId: 'patch-workspace-noop',
      summary: 'No-op inactive edit.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'other.styio',
          baseRevision: 7,
          start: 7,
          end: 10,
          replacementText: 'old',
        ),
      ],
    );

    final result = await applier.apply(patch);
    final otherDocument = await store.loadDocument('other.styio');

    expect(result.applied, isFalse);
    expect(result.appliedEditCount, 0);
    expect(result.skippedNoOpDocumentIds, <String>['other.styio']);
    expect(result.message, contains('produced no text changes'));
    expect(otherDocument.text, 'name = old\n');
    expect(otherDocument.revision, 7);
    expect(controller.canUndo, isFalse);
  });

  test('agent workspace code patch creates a missing workspace document', () async {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final store = InMemoryWorkspaceDocumentStore();
    final applier = AgentWorkspaceCodePatchApplier(
      editorController: controller,
      workspaceDocumentStore: store,
    );
    const patch = AgentCodePatch(
      patchId: 'patch-create-file',
      summary: 'Create helper file.',
      baseRevision: 1,
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'helper.txt',
          operation: AgentCodePatchEditOperation.create,
          start: 0,
          end: 0,
          replacementText: 'created by agent\n',
        ),
      ],
    );

    final result = await applier.apply(patch);
    final createdDocument = await store.loadDocument('helper.txt');

    expect(result.applied, isTrue);
    expect(result.appliedEditCount, 1);
    expect(result.appliedOperationCounts, <String, int>{'create': 1});
    expect(result.appliedDocumentIds, <String>['helper.txt']);
    expect(result.createdDocumentIds, <String>['helper.txt']);
    expect(result.deletedDocumentIds, isEmpty);
    expect(result.message, contains('Operations: create 1'));
    expect(createdDocument.text, 'created by agent\n');
    expect(createdDocument.revision, 1);
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent workspace code patch rejects create for existing document', () async {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'helper.txt': DocumentState(
          documentId: 'helper.txt',
          text: 'existing\n',
          revision: 3,
        ),
      },
    );
    final applier = AgentWorkspaceCodePatchApplier(
      editorController: controller,
      workspaceDocumentStore: store,
    );
    const patch = AgentCodePatch(
      patchId: 'patch-create-existing-file',
      summary: 'Create helper file.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'helper.txt',
          operation: AgentCodePatchEditOperation.create,
          start: 0,
          end: 0,
          replacementText: 'new\n',
        ),
      ],
    );

    final result = await applier.apply(patch);
    final existingDocument = await store.loadDocument('helper.txt');

    expect(result.applied, isFalse);
    expect(result.message, contains('already exists'));
    expect(existingDocument.text, 'existing\n');
  });

  test('agent workspace code patch deletes an existing workspace document', () async {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'obsolete.txt': DocumentState(
          documentId: 'obsolete.txt',
          text: 'remove me\n',
          revision: 2,
        ),
      },
    );
    final applier = AgentWorkspaceCodePatchApplier(
      editorController: controller,
      workspaceDocumentStore: store,
    );
    const patch = AgentCodePatch(
      patchId: 'patch-delete-file',
      summary: 'Delete obsolete file.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'obsolete.txt',
          operation: AgentCodePatchEditOperation.delete,
          baseRevision: 2,
          start: 0,
          end: 0,
          replacementText: '',
        ),
      ],
    );

    final result = await applier.apply(patch);

    expect(result.applied, isTrue);
    expect(result.appliedEditCount, 1);
    expect(result.appliedOperationCounts, <String, int>{'delete': 1});
    expect(result.appliedDocumentIds, <String>['obsolete.txt']);
    expect(result.createdDocumentIds, isEmpty);
    expect(result.deletedDocumentIds, <String>['obsolete.txt']);
    expect(result.message, contains('Operations: delete 1'));
    expect(await store.documentExists('obsolete.txt'), isFalse);
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent workspace code patch rejects delete for missing document', () async {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final store = InMemoryWorkspaceDocumentStore();
    final applier = AgentWorkspaceCodePatchApplier(
      editorController: controller,
      workspaceDocumentStore: store,
    );
    const patch = AgentCodePatch(
      patchId: 'patch-delete-missing-file',
      summary: 'Delete missing file.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'obsolete.txt',
          operation: AgentCodePatchEditOperation.delete,
          start: 0,
          end: 0,
          replacementText: '',
        ),
      ],
    );

    final result = await applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.message, contains('does not exist'));
  });

  test('agent workspace code patch rolls back saved documents when later save fails', () async {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final store = _FailingSecondSaveWorkspaceDocumentStore();
    final applier = AgentWorkspaceCodePatchApplier(
      editorController: controller,
      workspaceDocumentStore: store,
    );
    const patch = AgentCodePatch(
      patchId: 'patch-rollback-save',
      summary: 'Update two stored files.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'first.txt',
          baseRevision: 1,
          start: 0,
          end: 5,
          replacementText: 'FIRST',
        ),
        AgentCodePatchEdit(
          documentId: 'second.txt',
          baseRevision: 1,
          start: 0,
          end: 6,
          replacementText: 'SECOND',
        ),
      ],
    );

    final result = await applier.apply(patch);
    final firstDocument = await store.loadDocument('first.txt');
    final secondDocument = await store.loadDocument('second.txt');

    expect(result.applied, isFalse);
    expect(result.message, contains('failed to save second.txt'));
    expect(firstDocument.text, 'first\n');
    expect(secondDocument.text, 'second\n');
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent workspace code patch leaves active document unchanged when workspace save fails', () async {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentWorkspaceCodePatchApplier(
      editorController: controller,
      workspaceDocumentStore: _FailingSaveWorkspaceDocumentStore(),
    );
    const patch = AgentCodePatch(
      patchId: 'patch-save-failure',
      summary: 'Update two files.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'main.styio',
          baseRevision: 1,
          start: 8,
          end: 9,
          replacementText: '2',
        ),
        AgentCodePatchEdit(
          documentId: 'other.styio',
          baseRevision: 1,
          start: 7,
          end: 10,
          replacementText: 'new',
        ),
      ],
    );

    final result = await applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.message, contains('failed to save other.styio'));
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });

  test('agent workspace code patch leaves active document unchanged when workspace load fails', () async {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value = 1\n',
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
    final applier = AgentWorkspaceCodePatchApplier(
      editorController: controller,
      workspaceDocumentStore: _FailingLoadWorkspaceDocumentStore(),
    );
    const patch = AgentCodePatch(
      patchId: 'patch-load-failure',
      summary: 'Update two files.',
      edits: <AgentCodePatchEdit>[
        AgentCodePatchEdit(
          documentId: 'main.styio',
          baseRevision: 1,
          start: 8,
          end: 9,
          replacementText: '2',
        ),
        AgentCodePatchEdit(
          documentId: 'missing.styio',
          start: 0,
          end: 0,
          replacementText: 'name = new\n',
        ),
      ],
    );

    final result = await applier.apply(patch);

    expect(result.applied, isFalse);
    expect(result.message, contains('failed to load missing.styio'));
    expect(controller.document.text, 'value = 1\n');
    expect(controller.canUndo, isFalse);
  });
}

class _AccessFailingWorkspaceDocumentStore implements WorkspaceDocumentStore {
  @override
  Future<DocumentState> loadDocument(String path) {
    throw StateError('workspace store should not load unsafe paths');
  }

  @override
  Future<void> saveDocument(DocumentState document) {
    throw StateError('workspace store should not save unsafe paths');
  }

  @override
  Future<bool> deleteDocument(String path) {
    throw StateError('workspace store should not delete unsafe paths');
  }

  @override
  Future<bool> documentExists(String path) {
    throw StateError('workspace store should not check unsafe paths');
  }

  @override
  String? filePathForDocumentId(String documentId) {
    throw StateError('workspace store should not resolve unsafe paths');
  }
}

class _FailingLoadWorkspaceDocumentStore implements WorkspaceDocumentStore {
  @override
  Future<DocumentState> loadDocument(String path) {
    throw StateError('load failed');
  }

  @override
  Future<void> saveDocument(DocumentState document) async {}

  @override
  Future<bool> deleteDocument(String path) async => false;

  @override
  Future<bool> documentExists(String path) async => false;

  @override
  String? filePathForDocumentId(String documentId) => documentId;
}

class _FailingSaveWorkspaceDocumentStore implements WorkspaceDocumentStore {
  @override
  Future<DocumentState> loadDocument(String path) async {
    return DocumentState(
      documentId: path,
      text: path == 'other.styio' ? 'name = old\n' : '',
      revision: 1,
    );
  }

  @override
  Future<void> saveDocument(DocumentState document) {
    throw StateError('save failed');
  }

  @override
  Future<bool> deleteDocument(String path) async => false;

  @override
  Future<bool> documentExists(String path) async => path == 'other.styio';

  @override
  String? filePathForDocumentId(String documentId) => documentId;
}

class _FailingSecondSaveWorkspaceDocumentStore
    implements WorkspaceDocumentStore {
  _FailingSecondSaveWorkspaceDocumentStore()
    : _documents = <String, DocumentState>{
        'first.txt': const DocumentState(
          documentId: 'first.txt',
          text: 'first\n',
          revision: 1,
        ),
        'second.txt': const DocumentState(
          documentId: 'second.txt',
          text: 'second\n',
          revision: 1,
        ),
      };

  final Map<String, DocumentState> _documents;
  var _saveCount = 0;

  @override
  Future<DocumentState> loadDocument(String path) async {
    return _documents[path]!;
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    _saveCount += 1;
    if (_saveCount == 2) {
      throw StateError('second save failed');
    }
    _documents[document.documentId] = document;
  }

  @override
  Future<bool> deleteDocument(String path) async {
    return _documents.remove(path) != null;
  }

  @override
  Future<bool> documentExists(String path) async => _documents.containsKey(path);

  @override
  String? filePathForDocumentId(String documentId) => documentId;
}
