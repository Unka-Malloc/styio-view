import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace document highlights classify symbol usages', () async {
    const source = '''
@prices: f64 := {}

fn publish(price: f64) {
  latest = @prices
  price -> @prices
}
''';
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'resources.styio': DocumentState(
          documentId: 'resources.styio',
          text: source,
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDocumentHighlightsService(documentStore: store);

    final result = await service.collectHighlights(
      filePaths: const <String>['resources.styio'],
      query: WorkspaceDocumentHighlightsQuery(
        targetFilePath: 'resources.styio',
        offset: source.indexOf('@prices', source.indexOf('latest')) + 1,
      ),
    );

    expect(result.status, WorkspaceDocumentHighlightsStatus.completed);
    expect(result.filesSearched, 1);
    expect(result.highlightsIndexed, 3);
    expect(result.highlightCount, 3);
    expect(result.declarationCount, 1);
    expect(result.readCount, 1);
    expect(result.writeCount, 1);
    expect(result.textCount, 0);
    expect(result.token, 'prices');

    final read = result.highlights.singleWhere(
      (item) => item.kind == WorkspaceDocumentHighlightKind.read,
    );
    expect(read.previewText, '  latest = @prices');
    expect(read.isActive, isTrue);

    final write = result.highlights.singleWhere(
      (item) => item.kind == WorkspaceDocumentHighlightKind.write,
    );
    expect(write.previewText, '  price -> @prices');
    expect(write.symbolKindLabel, 'resource');
  });

  test('workspace document highlights filters access kinds and limits', () async {
    const source = '''
@prices: f64 := {}
first = @prices
second = @prices
third = @prices
''';
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'resources.styio': DocumentState(
          documentId: 'resources.styio',
          text: source,
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDocumentHighlightsService(documentStore: store);

    final result = await service.collectHighlights(
      filePaths: const <String>['resources.styio'],
      query: WorkspaceDocumentHighlightsQuery(
        targetFilePath: 'resources.styio',
        offset: source.indexOf('@prices', source.indexOf('second')) + 1,
        includeDeclarations: false,
        includeWrite: false,
        maxResults: 1,
      ),
    );

    expect(result.status, WorkspaceDocumentHighlightsStatus.hitLimit);
    expect(result.hitLimit, isTrue);
    expect(result.highlightsIndexed, 4);
    expect(result.highlightCount, 1);
    expect(result.readCount, 1);
    expect(result.declarationCount, 0);
  });

  test('workspace document highlights use overlays and textual fallback', () async {
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
      text: 'alpha = beta + beta\n',
      revision: 1,
    );
    final service = WorkspaceDocumentHighlightsService(documentStore: store);

    final result = await service.collectHighlights(
      filePaths: const <String>['main.styio'],
      overlayDocuments: const <String, DocumentState>{'main.styio': overlay},
      query: WorkspaceDocumentHighlightsQuery(
        targetFilePath: 'main.styio',
        offset: overlay.text.indexOf('beta'),
      ),
    );

    expect(result.status, WorkspaceDocumentHighlightsStatus.completed);
    expect(result.highlightsIndexed, 2);
    expect(result.highlightCount, 2);
    expect(result.textCount, 2);
    expect(
      result.highlights.map((item) => item.previewText).toSet(),
      <String>{'alpha = beta + beta'},
    );
  });

  test('workspace document highlights exposes query and label helpers', () async {
    const query = WorkspaceDocumentHighlightsQuery(
      targetFilePath: 'main.styio',
      offset: 2,
    );
    final copied = query.copyWith(
      targetFilePath: 'lib/main.styio',
      offset: 4,
      includeText: false,
      includeDeclarations: false,
      includeRead: false,
      includeWrite: false,
      includeGlobs: const <String>['lib/*.styio'],
      excludeGlobs: const <String>['lib/generated/**'],
      maxResults: 3,
    );

    expect(copied.targetFilePath, 'lib/main.styio');
    expect(copied.offset, 4);
    expect(copied.includeText, isFalse);
    expect(copied.includeDeclarations, isFalse);
    expect(copied.includeRead, isFalse);
    expect(copied.includeWrite, isFalse);
    expect(copied.includeGlobs, const <String>['lib/*.styio']);
    expect(copied.excludeGlobs, const <String>['lib/generated/**']);
    expect(copied.maxResults, 3);

    const range = SourceRange(start: 0, end: 5);
    const text = WorkspaceDocumentHighlightItem(
      filePath: 'main.styio',
      name: 'value',
      kind: WorkspaceDocumentHighlightKind.text,
      range: range,
      line: 0,
      column: 0,
      previewText: 'value = 1',
      isActive: true,
    );
    const declaration = WorkspaceDocumentHighlightItem(
      filePath: 'main.styio',
      name: 'run',
      kind: WorkspaceDocumentHighlightKind.declaration,
      range: range,
      line: 0,
      column: 0,
      previewText: 'fn run() {}',
      isActive: false,
      symbolKind: SymbolKind.function,
    );
    const read = WorkspaceDocumentHighlightItem(
      filePath: 'main.styio',
      name: 'state',
      kind: WorkspaceDocumentHighlightKind.read,
      range: range,
      line: 0,
      column: 0,
      previewText: 'state = next',
      isActive: false,
      symbolKind: SymbolKind.state,
    );
    const write = WorkspaceDocumentHighlightItem(
      filePath: 'main.styio',
      name: 'task',
      kind: WorkspaceDocumentHighlightKind.write,
      range: range,
      line: 0,
      column: 0,
      previewText: 'task -> value',
      isActive: false,
      symbolKind: SymbolKind.task,
    );
    const pipeline = WorkspaceDocumentHighlightItem(
      filePath: 'main.styio',
      name: 'pipe',
      kind: WorkspaceDocumentHighlightKind.read,
      range: range,
      line: 0,
      column: 0,
      previewText: 'pipe',
      isActive: false,
      symbolKind: SymbolKind.pipeline,
    );
    const variable = WorkspaceDocumentHighlightItem(
      filePath: 'main.styio',
      name: 'local',
      kind: WorkspaceDocumentHighlightKind.read,
      range: range,
      line: 0,
      column: 0,
      previewText: 'local',
      isActive: false,
      symbolKind: SymbolKind.variable,
    );
    const parameter = WorkspaceDocumentHighlightItem(
      filePath: 'main.styio',
      name: 'input',
      kind: WorkspaceDocumentHighlightKind.read,
      range: range,
      line: 0,
      column: 0,
      previewText: 'input',
      isActive: false,
      symbolKind: SymbolKind.parameter,
    );

    expect(text.kindLabel, 'text');
    expect(text.symbolKindLabel, 'text');
    expect(declaration.kindLabel, 'declaration');
    expect(read.kindLabel, 'read');
    expect(write.kindLabel, 'write');
    expect(
      <String>[
        declaration.symbolKindLabel,
        read.symbolKindLabel,
        write.symbolKindLabel,
        pipeline.symbolKindLabel,
        variable.symbolKindLabel,
        parameter.symbolKindLabel,
      ],
      <String>['function', 'state', 'task', 'pipeline', 'variable', 'parameter'],
    );
  });

  test('workspace document highlights reports filtered highlights and globs', () async {
    const source = 'alpha = beta + beta\n';
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/main.styio': DocumentState(
          documentId: 'lib/main.styio',
          text: source,
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDocumentHighlightsService(documentStore: store);

    final noHighlights = await service.collectHighlights(
      filePaths: const <String>['lib/main.styio'],
      query: WorkspaceDocumentHighlightsQuery(
        targetFilePath: 'lib/main.styio',
        offset: source.indexOf('beta'),
        includeText: false,
      ),
    );
    final suffixGlob = await service.collectHighlights(
      filePaths: const <String>['lib/main.styio'],
      query: const WorkspaceDocumentHighlightsQuery(
        targetFilePath: 'lib/main.styio',
        offset: 0,
        includeGlobs: <String>['**/main.styio'],
      ),
    );
    final wildcardGlob = await service.collectHighlights(
      filePaths: const <String>['lib/main.styio'],
      query: const WorkspaceDocumentHighlightsQuery(
        targetFilePath: 'lib/main.styio',
        offset: 0,
        includeGlobs: <String>['lib/*.styio'],
      ),
    );
    final excluded = await service.collectHighlights(
      filePaths: const <String>['lib/main.styio'],
      query: const WorkspaceDocumentHighlightsQuery(
        targetFilePath: 'lib/main.styio',
        offset: 0,
        excludeGlobs: <String>['lib/**'],
      ),
    );

    expect(noHighlights.status, WorkspaceDocumentHighlightsStatus.noHighlights);
    expect(noHighlights.highlightsIndexed, 2);
    expect(noHighlights.message, 'No document highlights match `beta`.');
    expect(suffixGlob.status, WorkspaceDocumentHighlightsStatus.completed);
    expect(wildcardGlob.status, WorkspaceDocumentHighlightsStatus.completed);
    expect(excluded.status, WorkspaceDocumentHighlightsStatus.emptyWorkspace);
  });

  test('workspace document highlights reports empty workspace and selection', () async {
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
    final service = WorkspaceDocumentHighlightsService(documentStore: store);

    final emptyWorkspace = await service.collectHighlights(
      filePaths: const <String>['README.md'],
      query: const WorkspaceDocumentHighlightsQuery(
        targetFilePath: 'README.md',
        offset: 0,
      ),
    );
    final emptySelection = await service.collectHighlights(
      filePaths: const <String>['main.styio'],
      query: const WorkspaceDocumentHighlightsQuery(
        targetFilePath: 'main.styio',
        offset: 8,
      ),
    );

    expect(
      emptyWorkspace.status,
      WorkspaceDocumentHighlightsStatus.emptyWorkspace,
    );
    expect(
      emptySelection.status,
      WorkspaceDocumentHighlightsStatus.emptySelection,
    );
    expect(
      emptySelection.message,
      'Document Highlights requires an identifier at the cursor.',
    );
  });
}
