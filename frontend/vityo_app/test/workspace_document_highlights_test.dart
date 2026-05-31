import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
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
