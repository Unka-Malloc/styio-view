import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace definition finds project definitions by symbol name', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/runtime.styio': DocumentState(
          documentId: 'lib/runtime.styio',
          text: '''
#blend := (left, right) => {
  <| left
}
''',
          revision: 0,
        ),
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/runtime }
value = blend(1.0, 2.0)
''',
          revision: 0,
        ),
        'unrelated.styio': DocumentState(
          documentId: 'unrelated.styio',
          text: '''
#blendLabel := (value) => {
  <| value
}
''',
          revision: 0,
        ),
        'README.md': DocumentState(
          documentId: 'README.md',
          text: '#blend should not be indexed\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDefinitionService(documentStore: store);

    final result = await service.findDefinitions(
      filePaths: const <String>[
        'main.styio',
        'lib/runtime.styio',
        'unrelated.styio',
        'README.md',
      ],
      query: const WorkspaceDefinitionQuery(pattern: 'blend'),
    );

    expect(result.status, WorkspaceDefinitionStatus.completed);
    expect(result.filesSearched, 3);
    expect(result.definitionsIndexed, 2);
    expect(result.matchCount, 2);
    expect(result.definitions.first.name, 'blend');
    expect(result.definitions.first.kind, StyioProjectSymbolKind.function);
    expect(result.definitions.first.filePath, 'lib/runtime.styio');
    expect(
      result.definitions.map((definition) => definition.filePath),
      isNot(contains('README.md')),
    );
  });

  test('workspace definition filters by kind, path, type, and limits', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/runtime.styio': DocumentState(
          documentId: 'lib/runtime.styio',
          text: '''
@prices : f64|..2| := {}
loadPrices = ||> {
}
''',
          revision: 0,
        ),
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '#priceReader := () => {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDefinitionService(documentStore: store);

    final typeResult = await service.findDefinitions(
      filePaths: const <String>['lib/runtime.styio', 'main.styio'],
      query: const WorkspaceDefinitionQuery(pattern: 'f64'),
    );

    expect(typeResult.definitions.single.name, 'prices');
    expect(typeResult.definitions.single.kind, StyioProjectSymbolKind.resource);

    final pathResult = await service.findDefinitions(
      filePaths: const <String>['lib/runtime.styio', 'main.styio'],
      query: const WorkspaceDefinitionQuery(pattern: 'runtime'),
    );

    expect(
      pathResult.definitions.map((definition) => definition.filePath).toSet(),
      <String>{'lib/runtime.styio'},
    );

    final taskResult = await service.findDefinitions(
      filePaths: const <String>['lib/runtime.styio', 'main.styio'],
      query: const WorkspaceDefinitionQuery(pattern: 'task'),
    );

    expect(taskResult.definitions.single.name, 'loadPrices');
    expect(taskResult.definitions.single.kind, StyioProjectSymbolKind.task);

    final limitedResult = await service.findDefinitions(
      filePaths: const <String>['lib/runtime.styio', 'main.styio'],
      query: const WorkspaceDefinitionQuery(pattern: 'price', maxResults: 1),
    );

    expect(limitedResult.status, WorkspaceDefinitionStatus.hitLimit);
    expect(limitedResult.hitLimit, isTrue);
    expect(limitedResult.matchCount, 1);
  });

  test('workspace definition uses unsaved overlay documents', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '#savedName := () => {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDefinitionService(documentStore: store);

    final result = await service.findDefinitions(
      filePaths: const <String>['src/main.styio'],
      overlayDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '#unsavedName := () => {}\n',
          revision: 1,
        ),
      },
      query: const WorkspaceDefinitionQuery(pattern: 'unsaved'),
    );

    expect(result.matchCount, 1);
    expect(result.definitions.single.name, 'unsavedName');
    expect(result.definitions.single.previewText, '#unsavedName := () => {}');
  });

  test('workspace definition accepts declaration sigils in queries', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '''
#calculate := () => {}
@values : i64|..2| := {}
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDefinitionService(documentStore: store);

    final functionResult = await service.findDefinitions(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceDefinitionQuery(pattern: '#calculate'),
    );
    final resourceResult = await service.findDefinitions(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceDefinitionQuery(pattern: '@values'),
    );

    expect(functionResult.definitions.single.name, 'calculate');
    expect(resourceResult.definitions.single.name, 'values');
  });
}
