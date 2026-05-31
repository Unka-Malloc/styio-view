import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace declaration finds project symbols and type declarations', () async {
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
        'lib/types.styio': DocumentState(
          documentId: 'lib/types.styio',
          text: '''
schema OrderBook {
  bid: f64
  ask: f64
}

state OrderFilled {
}
''',
          revision: 0,
        ),
        'README.md': DocumentState(
          documentId: 'README.md',
          text: 'schema OrderBook should not be indexed\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDeclarationService(documentStore: store);

    final orderResult = await service.findDeclarations(
      filePaths: const <String>[
        'lib/runtime.styio',
        'lib/types.styio',
        'README.md',
      ],
      query: const WorkspaceDeclarationQuery(pattern: 'Order'),
    );

    expect(orderResult.status, WorkspaceDeclarationStatus.completed);
    expect(orderResult.filesSearched, 2);
    expect(orderResult.declarationsIndexed, 3);
    expect(orderResult.matchCount, 2);
    expect(orderResult.declarations.first.name, 'OrderBook');
    expect(orderResult.declarations.first.kind, WorkspaceDeclarationKind.schema);
    expect(
      orderResult.declarations.map((declaration) => declaration.kind).toSet(),
      <WorkspaceDeclarationKind>{
        WorkspaceDeclarationKind.schema,
        WorkspaceDeclarationKind.state,
      },
    );
    expect(
      orderResult.declarations.map((declaration) => declaration.filePath),
      isNot(contains('README.md')),
    );

    final functionResult = await service.findDeclarations(
      filePaths: const <String>['lib/runtime.styio', 'lib/types.styio'],
      query: const WorkspaceDeclarationQuery(pattern: 'blend'),
    );

    expect(functionResult.declarations.single.name, 'blend');
    expect(
      functionResult.declarations.single.kind,
      WorkspaceDeclarationKind.function,
    );
  });

  test('workspace declaration uses unsaved overlays and enforces limits', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: 'schema SavedShape {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDeclarationService(documentStore: store);

    final result = await service.findDeclarations(
      filePaths: const <String>['src/main.styio'],
      overlayDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '''
schema UnsavedShape {}
#unsavedTask := () => {}
''',
          revision: 1,
        ),
      },
      query: const WorkspaceDeclarationQuery(
        pattern: 'Unsaved',
        maxResults: 1,
      ),
    );

    expect(result.status, WorkspaceDeclarationStatus.hitLimit);
    expect(result.hitLimit, isTrue);
    expect(result.matchCount, 1);
    expect(result.declarationsIndexed, 2);
    expect(
      result.declarations.single.name.toLowerCase(),
      startsWith('unsaved'),
    );
    expect(result.declarations.single.previewText, contains('unsaved'));
  });

  test('workspace declaration reports empty, empty workspace, and misses', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'README.md': DocumentState(
          documentId: 'README.md',
          text: 'schema Ignored {}\n',
          revision: 0,
        ),
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '#calculate := () => {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceDeclarationService(documentStore: store);

    final emptyPatternResult = await service.findDeclarations(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceDeclarationQuery(pattern: '  '),
    );
    final emptyWorkspaceResult = await service.findDeclarations(
      filePaths: const <String>['README.md'],
      query: const WorkspaceDeclarationQuery(pattern: 'Ignored'),
    );
    final noDeclarationResult = await service.findDeclarations(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceDeclarationQuery(pattern: 'missing'),
    );

    expect(emptyPatternResult.status, WorkspaceDeclarationStatus.emptyPattern);
    expect(
      emptyPatternResult.message,
      'Go to Declaration requires a symbol name.',
    );
    expect(
      emptyWorkspaceResult.status,
      WorkspaceDeclarationStatus.emptyWorkspace,
    );
    expect(
      noDeclarationResult.status,
      WorkspaceDeclarationStatus.noDeclarations,
    );
  });
}
