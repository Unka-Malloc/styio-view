import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace type hierarchy finds referenced supertypes', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'models/types.styio': DocumentState(
          documentId: 'models/types.styio',
          text: '''
schema Price {
}

state Pending {
}

schema Order {
  price: Price
  lifecycle: Pending
}
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceTypeHierarchyService(documentStore: store);

    final result = await service.buildHierarchy(
      filePaths: const <String>['models/types.styio'],
      query: const WorkspaceTypeHierarchyQuery(pattern: 'Order'),
    );

    expect(result.status, WorkspaceTypeHierarchyStatus.completed);
    expect(result.target?.name, 'Order');
    expect(result.relationCount, 2);
    expect(
      result.relations.map((relation) => relation.symbol.name),
      containsAll(<String>['Pending', 'Price']),
    );
    expect(
      result.relations.singleWhere(
        (relation) => relation.symbol.name == 'Price',
      ).firstLocation.previewText,
      '  price: Price',
    );
  });

  test('workspace type hierarchy finds referencing subtypes', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'models/types.styio': DocumentState(
          documentId: 'models/types.styio',
          text: '''
schema Price {
}

schema Order {
  price: Price
}

schema Quote {
  price: Price
}
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceTypeHierarchyService(documentStore: store);

    final result = await service.buildHierarchy(
      filePaths: const <String>['models/types.styio'],
      query: const WorkspaceTypeHierarchyQuery(
        pattern: 'Price',
        direction: WorkspaceTypeHierarchyDirection.subtypes,
      ),
    );

    expect(result.status, WorkspaceTypeHierarchyStatus.completed);
    expect(result.target?.name, 'Price');
    expect(result.relationCount, 2);
    expect(
      result.relations.map((relation) => relation.symbol.name).toSet(),
      <String>{'Order', 'Quote'},
    );
  });

  test('workspace type hierarchy uses unsaved overlay documents', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'models/types.styio': DocumentState(
          documentId: 'models/types.styio',
          text: '''
schema Price {
}

schema Order {
}
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceTypeHierarchyService(documentStore: store);

    final result = await service.buildHierarchy(
      filePaths: const <String>['models/types.styio'],
      overlayDocuments: const <String, DocumentState>{
        'models/types.styio': DocumentState(
          documentId: 'models/types.styio',
          text: '''
schema Price {
}

schema Order {
  price: Price
}
''',
          revision: 1,
        ),
      },
      query: const WorkspaceTypeHierarchyQuery(pattern: 'Order'),
    );

    expect(result.status, WorkspaceTypeHierarchyStatus.completed);
    expect(result.relations.single.symbol.name, 'Price');
    expect(result.relations.single.firstLocation.previewText, '  price: Price');
  });

  test('workspace type hierarchy reports limits and no relations', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'models/types.styio': DocumentState(
          documentId: 'models/types.styio',
          text: '''
schema Price {
}

state Pending {
}

schema Order {
  price: Price
  lifecycle: Pending
}

schema Isolated {
}
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceTypeHierarchyService(documentStore: store);

    final limitedResult = await service.buildHierarchy(
      filePaths: const <String>['models/types.styio'],
      query: const WorkspaceTypeHierarchyQuery(
        pattern: 'Order',
        maxResults: 1,
      ),
    );
    final isolatedResult = await service.buildHierarchy(
      filePaths: const <String>['models/types.styio'],
      query: const WorkspaceTypeHierarchyQuery(pattern: 'Isolated'),
    );

    expect(limitedResult.status, WorkspaceTypeHierarchyStatus.hitLimit);
    expect(limitedResult.hitLimit, isTrue);
    expect(limitedResult.referenceCount, 1);
    expect(isolatedResult.status, WorkspaceTypeHierarchyStatus.noRelations);
    expect(isolatedResult.message, contains('No supertypes'));
  });
}
