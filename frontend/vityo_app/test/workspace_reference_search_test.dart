import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace reference search exposes query and result helpers', () {
    final copied = const WorkspaceReferenceSearchQuery(
      pattern: '  Blend  ',
      includeDefinitions: false,
      accessKinds: <ReferenceAccess>{ReferenceAccess.read},
      includeGlobs: <String>['src/*.styio'],
      excludeGlobs: <String>['*.generated.styio'],
      maxResults: 4,
    ).copyWith(
      pattern: 'Task',
      includeDefinitions: true,
      accessKinds: const <ReferenceAccess>{ReferenceAccess.write},
      includeGlobs: const <String>['**/*.styio'],
      excludeGlobs: const <String>[],
      maxResults: 8,
    );
    const definition = WorkspaceReferenceDefinition(
      filePath: 'src/main.styio',
      name: 'publish',
      kind: StyioProjectSymbolKind.task,
      range: SourceRange(start: 0, end: 7),
      line: 0,
      column: 0,
      referenceCount: 2,
      type: 'i64',
    );
    const declaration = WorkspaceReferenceSearchItem(
      filePath: 'src/main.styio',
      name: 'publish',
      kind: StyioProjectSymbolKind.task,
      range: SourceRange(start: 0, end: 7),
      line: 0,
      column: 0,
      previewText: 'task publish',
      isDefinition: true,
      access: ReferenceAccess.declaration,
      definition: definition,
    );
    const write = WorkspaceReferenceSearchItem(
      filePath: 'src/main.styio',
      name: 'publish',
      kind: StyioProjectSymbolKind.task,
      range: SourceRange(start: 20, end: 27),
      line: 1,
      column: 2,
      previewText: 'value -> @publish',
      isDefinition: false,
      access: ReferenceAccess.write,
      definition: definition,
    );
    final result = WorkspaceReferenceSearchResult(
      query: copied,
      status: WorkspaceReferenceSearchStatus.completed,
      filesSearched: 1,
      definitionsSearched: 1,
      definitions: <WorkspaceReferenceDefinition>[definition],
      references: <WorkspaceReferenceSearchItem>[declaration, write],
    );

    expect(copied.pattern, 'Task');
    expect(copied.includeDefinitions, isTrue);
    expect(copied.accessKinds, {ReferenceAccess.write});
    expect(copied.maxResults, 8);
    expect(definition.kindLabel, 'task');
    expect(declaration.accessLabel, 'declaration');
    expect(write.accessLabel, 'write');
    expect(result.hitLimit, isFalse);
    expect(result.matchCount, 2);
    expect(result.matchedFileCount, 1);
    expect(result.declarationCount, 1);
    expect(result.writeCount, 1);
    expect(result.readCount, 0);
  });

  test('workspace reference search groups usages by project symbol', () async {
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
        'unrelated.styio': DocumentState(
          documentId: 'unrelated.styio',
          text: '''
fn blend(value: string): string {
  emit value
}
label = blend("local")
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceReferenceSearchService(documentStore: store);

    final result = await service.findReferences(
      filePaths: const <String>[
        'main.styio',
        'lib/runtime.styio',
        'unrelated.styio',
      ],
      query: const WorkspaceReferenceSearchQuery(pattern: 'blend'),
    );

    expect(result.status, WorkspaceReferenceSearchStatus.completed);
    expect(result.filesSearched, 3);
    expect(result.definitionsSearched, 2);
    expect(result.definitions, hasLength(2));

    final runtimeReferences = result.references
        .where((item) => item.definition.filePath == 'lib/runtime.styio')
        .toList(growable: false);
    expect(runtimeReferences, hasLength(2));
    expect(
      runtimeReferences.map((item) => item.filePath),
      containsAll(<String>['lib/runtime.styio', 'main.styio']),
    );
    expect(
      runtimeReferences.map((item) => item.filePath),
      isNot(contains('unrelated.styio')),
    );
    expect(
      runtimeReferences.where((item) => item.isDefinition),
      hasLength(1),
    );
  });

  test('workspace reference search can omit definitions and hit limits', () async {
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
first = blend(1.0, 2.0)
second = blend(3.0, 4.0)
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceReferenceSearchService(documentStore: store);

    final result = await service.findReferences(
      filePaths: const <String>['lib/runtime.styio', 'main.styio'],
      query: const WorkspaceReferenceSearchQuery(
        pattern: 'blend',
        includeDefinitions: false,
        maxResults: 1,
      ),
    );

    expect(result.status, WorkspaceReferenceSearchStatus.hitLimit);
    expect(result.hitLimit, isTrue);
    expect(result.references, hasLength(1));
    expect(result.references.single.isDefinition, isFalse);
    expect(result.references.single.filePath, 'main.styio');
  });

  test('workspace reference search filters usage access kinds', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'resources.styio': DocumentState(
          documentId: 'resources.styio',
          text: '''
@prices: f64 := {}

fn publish(price: f64) {
  latest = @prices
  price -> @prices
}
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceReferenceSearchService(documentStore: store);

    final readResult = await service.findReferences(
      filePaths: const <String>['resources.styio'],
      query: const WorkspaceReferenceSearchQuery(
        pattern: 'prices',
        includeDefinitions: false,
        accessKinds: <ReferenceAccess>{ReferenceAccess.read},
      ),
    );
    final writeResult = await service.findReferences(
      filePaths: const <String>['resources.styio'],
      query: const WorkspaceReferenceSearchQuery(
        pattern: 'prices',
        includeDefinitions: false,
        accessKinds: <ReferenceAccess>{ReferenceAccess.write},
      ),
    );
    final declarationResult = await service.findReferences(
      filePaths: const <String>['resources.styio'],
      query: const WorkspaceReferenceSearchQuery(
        pattern: 'prices',
        accessKinds: <ReferenceAccess>{ReferenceAccess.declaration},
      ),
    );

    expect(readResult.status, WorkspaceReferenceSearchStatus.completed);
    expect(readResult.matchCount, 1);
    expect(readResult.readCount, 1);
    expect(readResult.writeCount, 0);
    expect(readResult.references.single.access, ReferenceAccess.read);
    expect(readResult.references.single.previewText, '  latest = @prices');

    expect(writeResult.matchCount, 1);
    expect(writeResult.writeCount, 1);
    expect(writeResult.readCount, 0);
    expect(writeResult.references.single.access, ReferenceAccess.write);
    expect(writeResult.references.single.previewText, '  price -> @prices');

    expect(declarationResult.matchCount, 1);
    expect(declarationResult.declarationCount, 1);
    expect(
      declarationResult.references.single.access,
      ReferenceAccess.declaration,
    );
    expect(declarationResult.references.single.isDefinition, isTrue);
  });

  test('workspace reference search uses unsaved overlay documents', () async {
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
          text: '@import { lib/runtime }\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceReferenceSearchService(documentStore: store);

    final result = await service.findReferences(
      filePaths: const <String>['lib/runtime.styio', 'main.styio'],
      overlayDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/runtime }
value = blend(1.0, 2.0)
''',
          revision: 1,
        ),
      },
      query: const WorkspaceReferenceSearchQuery(pattern: 'blend'),
    );

    expect(result.matchCount, 2);
    expect(
      result.references.map((item) => item.filePath),
      contains('main.styio'),
    );
    expect(
      result.references.singleWhere((item) => item.filePath == 'main.styio')
          .previewText,
      'value = blend(1.0, 2.0)',
    );
  });

  test('workspace reference search reports empty and unmatched queries', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: 'value = 1\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceReferenceSearchService(documentStore: store);

    final emptyPattern = await service.findReferences(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceReferenceSearchQuery(pattern: '   '),
    );
    final emptyWorkspace = await service.findReferences(
      filePaths: const <String>['README.md'],
      query: const WorkspaceReferenceSearchQuery(pattern: 'value'),
    );
    final noDefinitions = await service.findReferences(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceReferenceSearchQuery(pattern: 'missing'),
    );

    expect(emptyPattern.status, WorkspaceReferenceSearchStatus.emptyPattern);
    expect(emptyPattern.message, contains('symbol name'));
    expect(emptyWorkspace.status, WorkspaceReferenceSearchStatus.emptyWorkspace);
    expect(noDefinitions.status, WorkspaceReferenceSearchStatus.noDefinitions);
    expect(noDefinitions.message, contains('missing'));
  });

  test('workspace reference search honors globs and fuzzy task matches', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '''
buildData = ||> {
  <| 1
}
''',
          revision: 0,
        ),
        'src/skip.generated.styio': DocumentState(
          documentId: 'src/skip.generated.styio',
          text: 'buildSkipped = ||> { <| 1 }\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceReferenceSearchService(documentStore: store);

    final result = await service.findReferences(
      filePaths: const <String>[
        'src/main.styio',
        'src/main.styio',
        'src/skip.generated.styio',
      ],
      query: const WorkspaceReferenceSearchQuery(
        pattern: 'bd',
        includeGlobs: <String>['*.styio'],
        excludeGlobs: <String>['*.generated.styio'],
      ),
    );

    expect(result.status, WorkspaceReferenceSearchStatus.completed);
    expect(result.filesSearched, 1);
    expect(result.definitions.single.name, 'buildData');
    expect(result.definitions.single.kindLabel, 'task');
    expect(result.references.single.previewText, 'buildData = ||> {');
  });
}
