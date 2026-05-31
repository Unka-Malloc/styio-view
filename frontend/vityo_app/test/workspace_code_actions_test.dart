import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace code actions collect deterministic project fixes', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/missing }
value = 1
''',
          revision: 0,
        ),
        'README.md': DocumentState(
          documentId: 'README.md',
          text: '@import { lib/missing }\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceCodeActionsService(documentStore: store);

    final result = await service.collectCodeActions(
      filePaths: const <String>['main.styio', 'README.md'],
      query: const WorkspaceCodeActionsQuery(),
    );

    expect(result.status, WorkspaceCodeActionsStatus.completed);
    expect(result.filesSearched, 1);
    expect(result.actionCount, 1);
    expect(result.actions.single.id, 'clean-up-project-imports');
    expect(result.actions.single.label, 'Clean up project imports');
    expect(result.actions.single.editCount, 1);
    expect(result.actions.single.changedFileCount, 1);
    expect(result.actions.single.documents.single.filePath, 'main.styio');
    expect(
      result.actions.single.documents.single.previewText,
      '@import { lib/missing }',
    );
  });

  test('workspace code actions filter and report hit limits', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/math.styio': DocumentState(
          documentId: 'lib/math.styio',
          text:
              'fn unusedBlend(left: f64, right: f64): f64 { emit left + right }\n',
          revision: 0,
        ),
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/missing }
value = 1
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceCodeActionsService(documentStore: store);

    final filtered = await service.collectCodeActions(
      filePaths: const <String>['lib/math.styio', 'main.styio'],
      query: const WorkspaceCodeActionsQuery(pattern: 'exported'),
    );
    final limited = await service.collectCodeActions(
      filePaths: const <String>['lib/math.styio', 'main.styio'],
      query: const WorkspaceCodeActionsQuery(maxResults: 1),
    );

    expect(filtered.actionCount, 1);
    expect(filtered.actions.single.label, 'Remove unused exported symbols');
    expect(limited.status, WorkspaceCodeActionsStatus.hitLimit);
    expect(limited.hitLimit, isTrue);
    expect(limited.actionCount, 1);
  });

  test('workspace code actions apply through overlays and save changes', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceCodeActionsService(documentStore: store);
    const overlay = DocumentState(
      documentId: 'main.styio',
      text: '''
@import { lib/missing }
value = 1
''',
      revision: 1,
    );

    final preview = await service.collectCodeActions(
      filePaths: const <String>['main.styio'],
      overlayDocuments: const <String, DocumentState>{'main.styio': overlay},
      query: const WorkspaceCodeActionsQuery(),
    );
    final apply = await service.applyCodeAction(
      filePaths: const <String>['main.styio'],
      overlayDocuments: const <String, DocumentState>{'main.styio': overlay},
      query: preview.query,
      actionId: preview.actions.single.id,
    );

    expect(apply.applied, isTrue);
    expect(apply.documentsChanged, 1);
    expect(apply.editsApplied, 1);
    expect((await store.loadDocument('main.styio')).text, 'value = 1\n');
    expect((await store.loadDocument('main.styio')).revision, 2);
  });
}
