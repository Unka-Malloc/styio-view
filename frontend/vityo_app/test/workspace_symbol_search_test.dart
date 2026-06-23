import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace symbol search indexes styio symbols by name', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: 'entry = 1\n',
          revision: 0,
        ),
        'src/calc.styio': DocumentState(
          documentId: 'src/calc.styio',
          text: '#calculate := (input) => {\n  <| input\n}\n',
          revision: 0,
        ),
        'README.md': DocumentState(
          documentId: 'README.md',
          text: '#calculate should not be a Styio workspace symbol\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceSymbolSearchService(documentStore: store);

    final result = await service.searchSymbols(
      filePaths: const <String>[
        'README.md',
        'src/main.styio',
        'src/main.styio',
        'src/calc.styio',
      ],
      query: const WorkspaceSymbolSearchQuery(pattern: 'calc'),
    );

    expect(result.status, WorkspaceSymbolSearchStatus.completed);
    expect(result.filesSearched, 2);
    expect(result.items.first.name, 'calculate');
    expect(result.items.first.kind, SymbolKind.function);
    expect(result.items.first.filePath, 'src/calc.styio');
    expect(result.items.first.line, 0);
    expect(result.items.first.column, 1);
    expect(result.items.first.matches, isNotEmpty);
  });

  test('workspace symbol search supports container fragments and hit limits', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/worker/math.styio': DocumentState(
          documentId: 'src/worker/math.styio',
          text: '#loadPrices := () => {\n  total = 1\n}\n',
          revision: 0,
        ),
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '#loadConfig := () => {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceSymbolSearchService(documentStore: store);

    final containerResult = await service.searchSymbols(
      filePaths: const <String>[
        'src/worker/math.styio',
        'src/main.styio',
      ],
      query: const WorkspaceSymbolSearchQuery(pattern: 'load worker'),
    );

    expect(
      containerResult.items.map((item) => item.name),
      contains('loadPrices'),
    );
    expect(containerResult.items.first.name, 'loadPrices');
    expect(containerResult.items.first.filePath, 'src/worker/math.styio');

    final limitedResult = await service.searchSymbols(
      filePaths: const <String>[
        'src/worker/math.styio',
        'src/main.styio',
      ],
      query: const WorkspaceSymbolSearchQuery(maxResults: 1),
    );

    expect(limitedResult.status, WorkspaceSymbolSearchStatus.hitLimit);
    expect(limitedResult.hitLimit, isTrue);
    expect(limitedResult.matchCount, 1);
    expect(limitedResult.symbolsIndexed, greaterThan(1));
  });

  test('workspace symbol search uses unsaved overlay documents', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '#savedName := () => {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceSymbolSearchService(documentStore: store);

    final result = await service.searchSymbols(
      filePaths: const <String>['src/main.styio'],
      overlayDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '#unsavedName := () => {}\n',
          revision: 1,
        ),
      },
      query: const WorkspaceSymbolSearchQuery(pattern: 'unsaved'),
    );

    expect(result.matchCount, 1);
    expect(result.items.single.name, 'unsavedName');
    expect(result.items.single.previewText, '#unsavedName := () => {}');
  });
}
