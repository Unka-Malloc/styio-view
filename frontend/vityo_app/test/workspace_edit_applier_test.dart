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
