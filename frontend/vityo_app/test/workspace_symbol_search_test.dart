import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_symbol_search.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_store_types.dart';

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

  test('workspace symbol search exposes helpers and labels', () async {
    const query = WorkspaceSymbolSearchQuery(pattern: 'load');
    final copied = query.copyWith(
      pattern: 'prices',
      includeGlobs: const <String>['src/*.styio'],
      excludeGlobs: const <String>['src/generated/**'],
      maxResults: 5,
    );

    expect(copied.pattern, 'prices');
    expect(copied.includeGlobs, const <String>['src/*.styio']);
    expect(copied.excludeGlobs, const <String>['src/generated/**']);
    expect(copied.maxResults, 5);

    const range = SourceRange(start: 0, end: 5);
    const matches = <WorkspaceSymbolSearchMatch>[
      WorkspaceSymbolSearchMatch(start: 0, end: 1),
    ];
    const items = <WorkspaceSymbolSearchItem>[
      WorkspaceSymbolSearchItem(
        filePath: 'main.styio',
        name: 'run',
        kind: SymbolKind.function,
        detail: '',
        nameRange: range,
        declarationRange: range,
        line: 0,
        column: 0,
        previewText: 'run',
        score: 1,
        matches: matches,
      ),
      WorkspaceSymbolSearchItem(
        filePath: 'main.styio',
        name: 'pipe',
        kind: SymbolKind.pipeline,
        detail: '',
        nameRange: range,
        declarationRange: range,
        line: 0,
        column: 0,
        previewText: 'pipe',
        score: 1,
        matches: matches,
      ),
      WorkspaceSymbolSearchItem(
        filePath: 'state.styio',
        name: 'Ready',
        kind: SymbolKind.state,
        detail: '',
        nameRange: range,
        declarationRange: range,
        line: 0,
        column: 0,
        previewText: 'state Ready {}',
        score: 1,
        matches: matches,
      ),
      WorkspaceSymbolSearchItem(
        filePath: 'resource.styio',
        name: 'prices',
        kind: SymbolKind.resource,
        detail: '',
        nameRange: range,
        declarationRange: range,
        line: 0,
        column: 0,
        previewText: '@prices: f64 := {}',
        score: 1,
        matches: matches,
      ),
      WorkspaceSymbolSearchItem(
        filePath: 'task.styio',
        name: 'loadPrices',
        kind: SymbolKind.task,
        detail: '',
        nameRange: range,
        declarationRange: range,
        line: 0,
        column: 0,
        previewText: 'loadPrices = ||> {}',
        score: 1,
        matches: matches,
      ),
      WorkspaceSymbolSearchItem(
        filePath: 'local.styio',
        name: 'value',
        kind: SymbolKind.variable,
        detail: '',
        nameRange: range,
        declarationRange: range,
        line: 0,
        column: 0,
        previewText: 'value = 1',
        score: 1,
        matches: matches,
      ),
      WorkspaceSymbolSearchItem(
        filePath: 'local.styio',
        name: 'input',
        kind: SymbolKind.parameter,
        detail: '',
        nameRange: range,
        declarationRange: range,
        line: 0,
        column: 0,
        previewText: 'fn run(input) {}',
        score: 1,
        matches: matches,
      ),
    ];
    const result = WorkspaceSymbolSearchResult(
      query: query,
      status: WorkspaceSymbolSearchStatus.hitLimit,
      filesSearched: 4,
      symbolsIndexed: 7,
      items: items,
    );

    expect(result.hitLimit, isTrue);
    expect(result.matchCount, 7);
    expect(result.matchedFileCount, 5);
    expect(
      items.map((item) => item.kindLabel),
      <String>[
        'function',
        'pipeline',
        'state',
        'resource',
        'task',
        'variable',
        'parameter',
      ],
    );
  });

  test('workspace symbol search handles empty patterns, fuzzy matches, and globs', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '''
@prices: f64 := {}
loadPrices = ||> {
  <| 1
}
''',
          revision: 0,
        ),
        'src/generated/skip.styio': DocumentState(
          documentId: 'src/generated/skip.styio',
          text: '#generated := () => {}\n',
          revision: 0,
        ),
        'README.md': DocumentState(
          documentId: 'README.md',
          text: '# ignored\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceSymbolSearchService(documentStore: store);

    final emptyWorkspace = await service.searchSymbols(
      filePaths: const <String>['README.md'],
      query: const WorkspaceSymbolSearchQuery(),
    );
    final emptyPattern = await service.searchSymbols(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceSymbolSearchQuery(pattern: ''),
    );
    final fuzzy = await service.searchSymbols(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceSymbolSearchQuery(pattern: 'lp'),
    );
    final kindContainer = await service.searchSymbols(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceSymbolSearchQuery(pattern: 'prices resource'),
    );
    final pathFallback = await service.searchSymbols(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceSymbolSearchQuery(pattern: 'src/main'),
    );
    final basenameGlob = await service.searchSymbols(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceSymbolSearchQuery(
        pattern: 'prices',
        includeGlobs: <String>['ma?n.styio'],
      ),
    );
    final doubleStarGlob = await service.searchSymbols(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceSymbolSearchQuery(
        pattern: 'prices',
        includeGlobs: <String>['src/**.styio'],
      ),
    );
    final excluded = await service.searchSymbols(
      filePaths: const <String>['src/main.styio', 'src/generated/skip.styio'],
      query: const WorkspaceSymbolSearchQuery(
        pattern: 'generated',
        excludeGlobs: <String>['src/generated/**'],
      ),
    );

    expect(emptyWorkspace.status, WorkspaceSymbolSearchStatus.emptyWorkspace);
    expect(emptyPattern.status, WorkspaceSymbolSearchStatus.completed);
    expect(emptyPattern.matchCount, greaterThanOrEqualTo(2));
    expect(fuzzy.items.single.name, 'loadPrices');
    expect(fuzzy.items.single.matches, hasLength(2));
    expect(kindContainer.items.single.name, 'prices');
    expect(pathFallback.matchCount, greaterThanOrEqualTo(2));
    expect(
      basenameGlob.items.map((item) => item.name),
      contains('prices'),
    );
    expect(
      doubleStarGlob.items.map((item) => item.name),
      contains('prices'),
    );
    expect(excluded.matchCount, 0);
  });
}
