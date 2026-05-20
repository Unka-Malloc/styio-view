import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test(
    'workspace edit applier applies edits across stored documents',
    () async {
      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'main.styio': DocumentState(
            documentId: 'main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
          'lib/math.styio': DocumentState(
            documentId: 'lib/math.styio',
            text: 'name = old\n',
            revision: 7,
          ),
        },
      );
      final applier = WorkspaceEditApplier(workspaceDocumentStore: store);
      const plan = WorkspaceEditPlan(
        id: 'rename-value',
        summary: 'Rename values.',
        source: WorkspaceEditSource.rename,
        editsByDocument: <String, List<FormattingEdit>>{
          'main.styio': <FormattingEdit>[
            FormattingEdit(
              range: SourceRange(start: 0, end: 5),
              newText: 'count',
            ),
          ],
          'lib/math.styio': <FormattingEdit>[
            FormattingEdit(
              range: SourceRange(start: 7, end: 10),
              newText: 'next',
            ),
          ],
        },
      );

      final result = await applier.apply(plan);
      final main = await store.loadDocument('main.styio');
      final math = await store.loadDocument('lib/math.styio');

      expect(result.applied, isTrue);
      expect(result.appliedEditCount, 2);
      expect(result.toJson()['applied'], isTrue);
      expect(result.appliedDocumentIds, <String>[
        'lib/math.styio',
        'main.styio',
      ]);
      expect(result.message, contains('rename plan rename-value'));
      expect(main.text, 'count = 1\n');
      expect(main.revision, 2);
      expect(math.text, 'name = next\n');
      expect(math.revision, 8);
    },
  );

  test('workspace edit plan previews normalized document edits', () {
    const plan = WorkspaceEditPlan(
      id: 'preview-rename',
      summary: 'Preview rename.',
      source: WorkspaceEditSource.rename,
      editsByDocument: <String, List<FormattingEdit>>{
        'main.styio': <FormattingEdit>[
          FormattingEdit(
            range: SourceRange(start: 5, end: 10),
            newText: 'count',
          ),
        ],
        'missing.styio': <FormattingEdit>[
          FormattingEdit(range: SourceRange(start: 0, end: 0), newText: 'x'),
        ],
      },
    );

    final preview = plan.preview(const <DocumentState>[
      DocumentState(
        documentId: 'main.styio',
        text: 'head\nvalue = 1\n',
        revision: 4,
      ),
    ]);

    expect(preview.planId, 'preview-rename');
    expect(preview.summary, 'Preview rename.');
    expect(preview.source, WorkspaceEditSource.rename);
    expect(preview.hasChanges, isTrue);
    expect(preview.hasMissingDocuments, isTrue);
    expect(preview.canApply, isFalse);
    expect(preview.missingDocumentIds, <String>['missing.styio']);
    expect(preview.editCount, 1);
    expect(preview.documents.single.documentId, 'main.styio');
    expect(preview.documents.single.revision, 4);
    expect(preview.documents.single.beforeText, 'head\nvalue = 1\n');
    expect(preview.documents.single.afterText, 'head\ncount = 1\n');
    final previewJson = preview.toJson();
    expect(previewJson['editCount'], 1);
    expect(previewJson['missingDocumentCount'], 1);
    expect(previewJson['missingDocumentIds'], <String>['missing.styio']);
    expect(previewJson['hasMissingDocuments'], isTrue);
    expect(previewJson['canApply'], isFalse);
    final confirmation = WorkspaceEditConfirmationPlan.fromPreview(preview);
    expect(
      confirmation.status,
      WorkspaceEditConfirmationStatus.blockedMissingDocuments,
    );
    expect(confirmation.ready, isFalse);
    expect(confirmation.toJson()['missingDocumentIds'], <String>[
      'missing.styio',
    ]);
    final documentJson =
        (previewJson['documents']! as List<Object?>).single!
            as Map<String, Object?>;
    final editJson =
        (documentJson['edits']! as List<Object?>).single!
            as Map<String, Object?>;
    expect(editJson['start'], 5);
    expect(editJson['end'], 10);
    expect(editJson['newText'], 'count');
    final rangeJson = editJson['range']! as Map<String, Object?>;
    expect(rangeJson['startLine'], 1);
    expect(rangeJson['startColumn'], 0);
    expect(rangeJson['endLine'], 1);
    expect(rangeJson['endColumn'], 5);
  });

  test(
    'workspace edit applier rejects unsafe document ids before load',
    () async {
      final store = _AccessFailingWorkspaceDocumentStore();
      final applier = WorkspaceEditApplier(workspaceDocumentStore: store);
      final plan = WorkspaceEditPlan.singleDocument(
        id: 'unsafe',
        summary: 'Unsafe.',
        source: WorkspaceEditSource.agent,
        documentId: '../secret.styio',
        edits: const <FormattingEdit>[
          FormattingEdit(range: SourceRange(start: 0, end: 0), newText: 'x'),
        ],
      );

      final result = await applier.apply(plan);

      expect(result.applied, isFalse);
      expect(result.message, contains('unsafe documentId'));
    },
  );

  test(
    'workspace edit applier applies file create and delete operations',
    () async {
      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'old.styio': DocumentState(
            documentId: 'old.styio',
            text: 'old\n',
            revision: 1,
          ),
        },
      );
      final applier = WorkspaceEditApplier(workspaceDocumentStore: store);
      const plan = WorkspaceEditPlan(
        id: 'file-ops',
        summary: 'Create and delete files.',
        source: WorkspaceEditSource.agent,
        editsByDocument: <String, List<FormattingEdit>>{},
        fileOperations: <WorkspaceFileOperation>[
          WorkspaceFileOperation.create(documentId: 'new.styio', text: 'new\n'),
          WorkspaceFileOperation.delete(documentId: 'old.styio'),
        ],
      );

      final preview = plan.preview(const <DocumentState>[
        DocumentState(documentId: 'old.styio', text: 'old\n', revision: 1),
      ]);
      final confirmation = WorkspaceEditConfirmationPlan.fromPreview(preview);
      final result = await applier.apply(plan);

      expect(preview.hasChanges, isTrue);
      expect(preview.fileOperations, hasLength(2));
      expect(preview.canApply, isTrue);
      expect(preview.toJson()['fileOperationCount'], 2);
      expect(confirmation.ready, isTrue);
      expect(confirmation.fileOperationCount, 2);
      expect(result.applied, isTrue);
      expect(result.createdDocumentIds, <String>['new.styio']);
      expect(result.deletedDocumentIds, <String>['old.styio']);
      expect(await store.documentExists('new.styio'), isTrue);
      expect(await store.documentExists('old.styio'), isFalse);
      expect((await store.loadDocument('new.styio')).text, 'new\n');
    },
  );

  test('workspace edit confirmation blocks unsafe file operations', () {
    const plan = WorkspaceEditPlan(
      id: 'unsafe-file-op',
      summary: 'Unsafe file op.',
      source: WorkspaceEditSource.agent,
      editsByDocument: <String, List<FormattingEdit>>{},
      fileOperations: <WorkspaceFileOperation>[
        WorkspaceFileOperation.create(
          documentId: '../secret.styio',
          text: 'secret',
        ),
      ],
    );

    final preview = plan.preview(const <DocumentState>[]);
    final confirmation = WorkspaceEditConfirmationPlan.fromPreview(preview);

    expect(preview.hasBlockedFileOperations, isTrue);
    expect(
      preview.fileOperations.single.status,
      WorkspaceFileOperationPreviewStatus.blockedUnsafeDocumentId,
    );
    expect(
      confirmation.status,
      WorkspaceEditConfirmationStatus.blockedFileOperations,
    );
    expect(confirmation.ready, isFalse);
  });

  test(
    'workspace edit applier rolls back file operations on save failure',
    () async {
      final store = _SaveFailingOnceWorkspaceDocumentStore(
        failDocumentId: 'main.styio',
        seededDocuments: const <String, DocumentState>{
          'main.styio': DocumentState(
            documentId: 'main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
        },
      );
      final applier = WorkspaceEditApplier(workspaceDocumentStore: store);
      const plan = WorkspaceEditPlan(
        id: 'rollback-file-op',
        summary: 'Create then edit.',
        source: WorkspaceEditSource.agent,
        fileOperations: <WorkspaceFileOperation>[
          WorkspaceFileOperation.create(
            documentId: 'generated.styio',
            text: 'generated\n',
          ),
        ],
        editsByDocument: <String, List<FormattingEdit>>{
          'main.styio': <FormattingEdit>[
            FormattingEdit(
              range: SourceRange(start: 0, end: 5),
              newText: 'count',
            ),
          ],
        },
      );

      final result = await applier.apply(plan);
      final main = await store.loadDocument('main.styio');

      expect(result.applied, isFalse);
      expect(result.rollbackApplied, isTrue);
      expect(
        result.rollbackMessages,
        contains('Rolled back created document generated.styio.'),
      );
      expect(
        result.rollbackMessages,
        contains('Restored document main.styio.'),
      );
      expect(await store.documentExists('generated.styio'), isFalse);
      expect(main.text, 'value = 1\n');
      expect(main.revision, 1);
      expect(result.toJson()['rollbackApplied'], isTrue);
    },
  );

  test(
    'workspace edit applier rejects overlapping edits without saving',
    () async {
      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'main.styio': DocumentState(
            documentId: 'main.styio',
            text: 'value = 1\n',
            revision: 1,
          ),
        },
      );
      final applier = WorkspaceEditApplier(workspaceDocumentStore: store);
      final plan = WorkspaceEditPlan.singleDocument(
        id: 'overlap',
        summary: 'Overlap.',
        source: WorkspaceEditSource.codeAction,
        documentId: 'main.styio',
        edits: const <FormattingEdit>[
          FormattingEdit(range: SourceRange(start: 0, end: 5), newText: 'a'),
          FormattingEdit(range: SourceRange(start: 4, end: 7), newText: 'b'),
        ],
      );

      final result = await applier.apply(plan);
      final document = await store.loadDocument('main.styio');

      expect(result.applied, isFalse);
      expect(result.message, contains('invalid or overlapping'));
      expect(document.text, 'value = 1\n');
      expect(document.revision, 1);
    },
  );

  test('workspace edit applier skips no-op edits without saving', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 9,
        ),
      },
    );
    final applier = WorkspaceEditApplier(workspaceDocumentStore: store);
    final plan = WorkspaceEditPlan.singleDocument(
      id: 'noop',
      summary: 'No-op.',
      source: WorkspaceEditSource.codeAction,
      documentId: 'main.styio',
      edits: const <FormattingEdit>[
        FormattingEdit(range: SourceRange(start: 0, end: 5), newText: 'value'),
      ],
    );

    final result = await applier.apply(plan);
    final document = await store.loadDocument('main.styio');

    expect(result.applied, isFalse);
    expect(result.appliedEditCount, 0);
    expect(result.appliedDocumentIds, isEmpty);
    expect(result.skippedNoOpDocumentIds, <String>['main.styio']);
    expect(result.message, contains('produced no text changes'));
    expect(document.text, 'value = 1\n');
    expect(document.revision, 9);
  });

  test('workspace edit plan can be created from quick fix', () {
    const quickFix = DiagnosticQuickFix(
      label: 'Insert missing import.',
      edits: <FormattingEdit>[
        FormattingEdit(
          range: SourceRange(start: 0, end: 0),
          newText: '@import { styio/core }\n',
        ),
      ],
    );

    final plan = WorkspaceEditPlan.fromQuickFix(
      id: 'quick-fix-import',
      documentId: 'main.styio',
      quickFix: quickFix,
    );

    expect(plan.id, 'quick-fix-import');
    expect(plan.summary, 'Insert missing import.');
    expect(plan.source, WorkspaceEditSource.codeAction);
    expect(plan.editCount, 1);
    expect(
      plan.editsByDocument['main.styio']!.single.newText,
      contains('@import'),
    );
  });

  test(
    'workspace edit confirmation plan reports ready and blocked previews',
    () {
      const readyPreview = WorkspaceEditPreview(
        planId: 'ready',
        summary: 'Ready edit.',
        source: WorkspaceEditSource.agent,
        documents: <WorkspaceEditDocumentPreview>[
          WorkspaceEditDocumentPreview(
            documentId: 'main.styio',
            revision: 1,
            beforeText: 'old',
            afterText: 'new',
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(start: 0, end: 3),
                newText: 'new',
              ),
            ],
          ),
        ],
      );
      const noChangePreview = WorkspaceEditPreview(
        planId: 'noop',
        summary: 'No-op edit.',
        source: WorkspaceEditSource.agent,
        documents: <WorkspaceEditDocumentPreview>[
          WorkspaceEditDocumentPreview(
            documentId: 'main.styio',
            revision: 1,
            beforeText: 'same',
            afterText: 'same',
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(start: 0, end: 4),
                newText: 'same',
              ),
            ],
          ),
        ],
      );

      final ready = WorkspaceEditConfirmationPlan.fromPreview(readyPreview);
      final noChange = WorkspaceEditConfirmationPlan.fromPreview(
        noChangePreview,
      );
      final tooMany = WorkspaceEditConfirmationPlan.fromPreview(
        readyPreview,
        maxEditCount: 0,
      );

      expect(ready.ready, isTrue);
      expect(ready.requiresUserConfirmation, isTrue);
      expect(ready.documentIds, <String>['main.styio']);
      expect(ready.toJson()['todo'], contains('diff UI'));
      expect(noChange.status, WorkspaceEditConfirmationStatus.blockedNoChanges);
      expect(noChange.requiresUserConfirmation, isFalse);
      expect(
        tooMany.status,
        WorkspaceEditConfirmationStatus.blockedTooManyEdits,
      );
    },
  );

  test('workspace edit plan can be created from rename plan', () {
    const renamePlan = RenamePlan(
      target: DocumentSymbol(
        name: 'value',
        kind: SymbolKind.variable,
        nameRange: SourceRange(start: 0, end: 5),
        declarationRange: SourceRange(start: 0, end: 10),
      ),
      newName: 'count',
      references: <ReferenceSpan>[],
      edits: <FormattingEdit>[
        FormattingEdit(range: SourceRange(start: 0, end: 5), newText: 'count'),
      ],
    );

    final plan = WorkspaceEditPlan.fromRenamePlan(
      id: 'rename-value',
      documentId: 'main.styio',
      renamePlan: renamePlan,
    );

    expect(plan.id, 'rename-value');
    expect(plan.summary, 'Rename value to count.');
    expect(plan.source, WorkspaceEditSource.rename);
    expect(plan.editsByDocument['main.styio']!.single.newText, 'count');
  });
}

class _AccessFailingWorkspaceDocumentStore implements WorkspaceDocumentStore {
  @override
  Future<bool> deleteDocument(String path) {
    throw StateError('store should not be accessed');
  }

  @override
  Future<bool> documentExists(String path) {
    throw StateError('store should not be accessed');
  }

  @override
  String? filePathForDocumentId(String documentId) => null;

  @override
  Future<DocumentState> loadDocument(String path) {
    throw StateError('store should not be accessed');
  }

  @override
  Future<void> saveDocument(DocumentState document) {
    throw StateError('store should not be accessed');
  }
}

class _SaveFailingOnceWorkspaceDocumentStore implements WorkspaceDocumentStore {
  _SaveFailingOnceWorkspaceDocumentStore({
    required this.failDocumentId,
    required Map<String, DocumentState> seededDocuments,
  }) : _documents = Map<String, DocumentState>.from(seededDocuments);

  final String failDocumentId;
  final Map<String, DocumentState> _documents;
  var _failed = false;

  @override
  Future<bool> deleteDocument(String path) async {
    return _documents.remove(path) != null;
  }

  @override
  Future<bool> documentExists(String path) async {
    return _documents.containsKey(path);
  }

  @override
  String? filePathForDocumentId(String documentId) => null;

  @override
  Future<DocumentState> loadDocument(String path) async {
    final document = _documents[path];
    if (document == null) {
      throw StateError('missing document $path');
    }
    return document;
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    if (!_failed && document.documentId == failDocumentId) {
      _failed = true;
      throw StateError('simulated save failure');
    }
    _documents[document.documentId] = document;
  }
}
