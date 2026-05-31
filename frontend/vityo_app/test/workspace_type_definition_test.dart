import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace type definition finds schema and state declarations', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
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
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
book: OrderBook
next = OrderFilled
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
    final service = WorkspaceTypeDefinitionService(documentStore: store);

    final result = await service.findTypeDefinitions(
      filePaths: const <String>[
        'main.styio',
        'lib/types.styio',
        'README.md',
      ],
      query: const WorkspaceTypeDefinitionQuery(pattern: 'Order'),
    );

    expect(result.status, WorkspaceTypeDefinitionStatus.completed);
    expect(result.filesSearched, 2);
    expect(result.typesIndexed, 2);
    expect(result.matchCount, 2);
    expect(result.types.first.name, 'OrderBook');
    expect(result.types.first.kind, WorkspaceTypeDefinitionKind.schema);
    expect(
      result.types.map((type) => type.kind).toSet(),
      <WorkspaceTypeDefinitionKind>{
        WorkspaceTypeDefinitionKind.schema,
        WorkspaceTypeDefinitionKind.state,
      },
    );
    expect(
      result.types.map((type) => type.filePath),
      isNot(contains('README.md')),
    );
  });

  test(
    'workspace type definition filters by kind, path, glob, and limit',
    () async {
      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'models/order.styio': DocumentState(
            documentId: 'models/order.styio',
            text: '''
schema TradeEvent {
}
''',
            revision: 0,
          ),
          'flows/lifecycle.styio': DocumentState(
            documentId: 'flows/lifecycle.styio',
            text: '''
state AwaitingFill {
}

state Filled {
}
''',
            revision: 0,
          ),
        },
      );
      final service = WorkspaceTypeDefinitionService(documentStore: store);
      const files = <String>['models/order.styio', 'flows/lifecycle.styio'];

      final kindResult = await service.findTypeDefinitions(
        filePaths: files,
        query: const WorkspaceTypeDefinitionQuery(pattern: 'state'),
      );

      expect(kindResult.matchCount, 2);
      expect(
        kindResult.types.map((type) => type.kind).toSet(),
        <WorkspaceTypeDefinitionKind>{WorkspaceTypeDefinitionKind.state},
      );

      final pathResult = await service.findTypeDefinitions(
        filePaths: files,
        query: const WorkspaceTypeDefinitionQuery(pattern: 'lifecycle'),
      );

      expect(
        pathResult.types.map((type) => type.filePath).toSet(),
        <String>{'flows/lifecycle.styio'},
      );

      final includeResult = await service.findTypeDefinitions(
        filePaths: files,
        query: const WorkspaceTypeDefinitionQuery(
          pattern: 'Trade',
          includeGlobs: <String>['models/*.styio'],
        ),
      );

      expect(includeResult.types.single.name, 'TradeEvent');

      final excludeResult = await service.findTypeDefinitions(
        filePaths: files,
        query: const WorkspaceTypeDefinitionQuery(
          pattern: 'Trade',
          excludeGlobs: <String>['models/**'],
        ),
      );

      expect(excludeResult.status, WorkspaceTypeDefinitionStatus.noTypes);

      final limitedResult = await service.findTypeDefinitions(
        filePaths: files,
        query: const WorkspaceTypeDefinitionQuery(
          pattern: 'state',
          maxResults: 1,
        ),
      );

      expect(limitedResult.status, WorkspaceTypeDefinitionStatus.hitLimit);
      expect(limitedResult.hitLimit, isTrue);
      expect(limitedResult.matchCount, 1);
    },
  );

  test('workspace type definition uses unsaved overlay documents', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: 'schema SavedShape {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceTypeDefinitionService(documentStore: store);

    final result = await service.findTypeDefinitions(
      filePaths: const <String>['src/main.styio'],
      overlayDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: 'schema UnsavedShape {}\n',
          revision: 1,
        ),
      },
      query: const WorkspaceTypeDefinitionQuery(pattern: 'Unsaved'),
    );

    expect(result.matchCount, 1);
    expect(result.types.single.name, 'UnsavedShape');
    expect(result.types.single.previewText, 'schema UnsavedShape {}');
  });

  test('workspace type definition reports empty query and workspace', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'README.md': DocumentState(
          documentId: 'README.md',
          text: 'schema Ignored {}\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceTypeDefinitionService(documentStore: store);

    final emptyPatternResult = await service.findTypeDefinitions(
      filePaths: const <String>['README.md'],
      query: const WorkspaceTypeDefinitionQuery(pattern: '  '),
    );
    final emptyWorkspaceResult = await service.findTypeDefinitions(
      filePaths: const <String>['README.md'],
      query: const WorkspaceTypeDefinitionQuery(pattern: 'Ignored'),
    );

    expect(
      emptyPatternResult.status,
      WorkspaceTypeDefinitionStatus.emptyPattern,
    );
    expect(
      emptyWorkspaceResult.status,
      WorkspaceTypeDefinitionStatus.emptyWorkspace,
    );
  });
}
