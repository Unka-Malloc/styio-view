import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace text search honors literal matching and glob filters', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: 'task build {\n  emit "READY"\n}\n',
          revision: 0,
        ),
        'src/build_test.styio': DocumentState(
          documentId: 'src/build_test.styio',
          text: 'task test {\n  emit "ready"\n}\n',
          revision: 0,
        ),
        'README.md': DocumentState(
          documentId: 'README.md',
          text: 'ready\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceTextSearchService(documentStore: store);

    final result = await service.searchFiles(
      filePaths: const <String>[
        'src/main.styio',
        'src/main.styio',
        'src/build_test.styio',
        'README.md',
      ],
      query: const WorkspaceTextSearchQuery(
        pattern: 'ready',
        includeGlobs: <String>['**/*.styio'],
        excludeGlobs: <String>['*_test.styio'],
      ),
    );

    expect(result.status, WorkspaceTextSearchStatus.completed);
    expect(result.filesSearched, 1);
    expect(result.matchCount, 1);
    expect(result.matchedFileCount, 1);
    expect(result.matches.single.filePath, 'src/main.styio');
    expect(result.matches.single.line, 1);
    expect(result.matches.single.column, 8);
    expect(result.matches.single.previewText, '  emit "READY"');
  });

  test('workspace text search supports regex and hit limits', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: 'task build {}\ntask test {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceTextSearchService(documentStore: store);

    final result = await service.searchFiles(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceTextSearchQuery(
        pattern: r'\btask\s+\w+',
        literal: false,
        maxResults: 1,
      ),
    );

    expect(result.status, WorkspaceTextSearchStatus.hitLimit);
    expect(result.hitLimit, isTrue);
    expect(result.matchCount, 1);
    expect(result.matches.single.previewText, 'task build {}');
  });

  test('workspace text search rejects invalid regex patterns', () async {
    final service = WorkspaceTextSearchService(
      documentStore: InMemoryWorkspaceDocumentStore(),
    );

    final result = await service.searchFiles(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceTextSearchQuery(pattern: r'(', literal: false),
    );

    expect(result.status, WorkspaceTextSearchStatus.invalidPattern);
    expect(result.filesSearched, 0);
    expect(result.matches, isEmpty);
  });

  test('workspace text search uses unsaved overlay documents', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: 'task build {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceTextSearchService(documentStore: store);

    final result = await service.searchFiles(
      filePaths: const <String>['src/main.styio'],
      overlayDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: 'task build {\n  emit "unsaved"\n}\n',
          revision: 1,
        ),
      },
      query: const WorkspaceTextSearchQuery(pattern: 'unsaved'),
    );

    expect(result.status, WorkspaceTextSearchStatus.completed);
    expect(result.matchCount, 1);
    expect(result.matches.single.previewText, '  emit "unsaved"');
  });
}
