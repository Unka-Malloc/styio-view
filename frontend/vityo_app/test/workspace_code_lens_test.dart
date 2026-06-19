import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace code lens counts project-visible usages', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/runtime.styio': DocumentState(
          documentId: 'lib/runtime.styio',
          text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
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
      },
    );
    final service = WorkspaceCodeLensService(documentStore: store);

    final result = await service.collectCodeLenses(
      filePaths: const <String>['lib/runtime.styio', 'main.styio'],
      query: const WorkspaceCodeLensQuery(
        targetFilePath: 'lib/runtime.styio',
      ),
    );

    expect(result.status, WorkspaceCodeLensStatus.completed);
    expect(result.filesSearched, 2);
    expect(result.symbolsIndexed, 1);
    expect(result.lensCount, 1);
    expect(result.referencedSymbolCount, 1);

    final lens = result.lenses.single;
    expect(lens.symbolName, 'blend');
    expect(lens.symbolKindLabel, 'function');
    expect(lens.kindLabel, 'references');
    expect(lens.usageCount, 1);
    expect(lens.referenceCount, 2);
    expect(lens.commandTitle, '1 usage');
    expect(lens.previewText, 'fn blend(left: f64, right: f64): f64 {');
  });

  test('workspace code lens uses overlays and limits', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'saved = value\n',
          revision: 0,
        ),
      },
    );
    const overlay = DocumentState(
      documentId: 'main.styio',
      text: '''
fn first(): f64 { emit 1.0 }
fn second(): f64 { emit 2.0 }
''',
      revision: 1,
    );
    final service = WorkspaceCodeLensService(documentStore: store);

    final result = await service.collectCodeLenses(
      filePaths: const <String>['main.styio'],
      overlayDocuments: const <String, DocumentState>{'main.styio': overlay},
      query: const WorkspaceCodeLensQuery(
        targetFilePath: 'main.styio',
        maxResults: 1,
      ),
    );

    expect(result.status, WorkspaceCodeLensStatus.hitLimit);
    expect(result.hitLimit, isTrue);
    expect(result.symbolsIndexed, 2);
    expect(result.lensCount, 1);
    expect(result.lenses.single.symbolName, 'first');
  });

  test('workspace code lens exposes query helpers and non-function lenses', () async {
    const query = WorkspaceCodeLensQuery(targetFilePath: 'lib/main.styio');
    final copied = query.copyWith(
      targetFilePath: 'lib/other.styio',
      includeGlobs: const <String>['lib/*.styio'],
      excludeGlobs: const <String>['lib/generated/**'],
      maxResults: 4,
    );

    expect(copied.targetFilePath, 'lib/other.styio');
    expect(copied.includeGlobs, const <String>['lib/*.styio']);
    expect(copied.excludeGlobs, const <String>['lib/generated/**']);
    expect(copied.maxResults, 4);

    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/main.styio': DocumentState(
          documentId: 'lib/main.styio',
          text: '''
@prices: f64 := {}
loadPrices = ||> {
  <| 1
}
''',
          revision: 0,
        ),
        'lib/generated/skip.styio': DocumentState(
          documentId: 'lib/generated/skip.styio',
          text: '#generated := () => {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceCodeLensService(documentStore: store);

    final result = await service.collectCodeLenses(
      filePaths: const <String>[
        'lib/main.styio',
        'lib/main.styio',
        'lib/generated/skip.styio',
      ],
      query: const WorkspaceCodeLensQuery(
        targetFilePath: 'lib/main.styio',
        includeGlobs: <String>['lib/*.styio'],
        excludeGlobs: <String>['lib/generated/**'],
      ),
    );

    expect(result.status, WorkspaceCodeLensStatus.completed);
    expect(result.filesSearched, 1);
    expect(result.symbolsIndexed, 2);
    expect(result.lensCount, 2);
    expect(result.referencedSymbolCount, 0);

    final resource = result.lenses.singleWhere(
      (lens) => lens.symbolName == 'prices',
    );
    expect(resource.symbolKindLabel, 'resource');
    expect(resource.kindLabel, 'references');
    expect(resource.commandTitle, 'No usages');

    final task = result.lenses.singleWhere(
      (lens) => lens.symbolName == 'loadPrices',
    );
    expect(task.symbolKindLabel, 'task');
    expect(task.previewText, 'loadPrices = ||> {');
  });

  test('workspace code lens handles target mismatches and glob forms', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/main.styio': DocumentState(
          documentId: 'lib/main.styio',
          text: 'value = 1\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceCodeLensService(documentStore: store);

    final overlayMismatch = await service.collectCodeLenses(
      filePaths: const <String>['lib/main.styio'],
      overlayDocuments: const <String, DocumentState>{
        'lib/main.styio': DocumentState(
          documentId: 'lib/other.styio',
          text: '#other := () => {}\n',
          revision: 1,
        ),
      },
      query: const WorkspaceCodeLensQuery(targetFilePath: 'lib/main.styio'),
    );
    final suffixGlob = await service.collectCodeLenses(
      filePaths: const <String>['lib/main.styio'],
      query: const WorkspaceCodeLensQuery(
        targetFilePath: 'lib/main.styio',
        includeGlobs: <String>['**/main.styio'],
      ),
    );
    final excluded = await service.collectCodeLenses(
      filePaths: const <String>['lib/main.styio'],
      query: const WorkspaceCodeLensQuery(
        targetFilePath: 'lib/main.styio',
        excludeGlobs: <String>['lib/**'],
      ),
    );

    expect(overlayMismatch.status, WorkspaceCodeLensStatus.emptyWorkspace);
    expect(overlayMismatch.filesSearched, 1);
    expect(suffixGlob.status, WorkspaceCodeLensStatus.noLenses);
    expect(excluded.status, WorkspaceCodeLensStatus.emptyWorkspace);
  });

  test('workspace code lens reports empty workspace and no lenses', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'value = 1\n',
          revision: 0,
        ),
        'README.md': DocumentState(
          documentId: 'README.md',
          text: 'value = 1\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceCodeLensService(documentStore: store);

    final emptyWorkspace = await service.collectCodeLenses(
      filePaths: const <String>['README.md'],
      query: const WorkspaceCodeLensQuery(targetFilePath: 'README.md'),
    );
    final noLenses = await service.collectCodeLenses(
      filePaths: const <String>['main.styio'],
      query: const WorkspaceCodeLensQuery(targetFilePath: 'main.styio'),
    );

    expect(emptyWorkspace.status, WorkspaceCodeLensStatus.emptyWorkspace);
    expect(noLenses.status, WorkspaceCodeLensStatus.noLenses);
    expect(noLenses.message, 'No code lenses found in main.styio.');
  });
}
