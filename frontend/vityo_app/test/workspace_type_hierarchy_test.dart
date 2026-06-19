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

  test('workspace type hierarchy reports boundary query states', () async {
    const baseQuery = WorkspaceTypeHierarchyQuery(pattern: 'Order');
    final copiedQuery = baseQuery.copyWith(
      pattern: 'state',
      direction: WorkspaceTypeHierarchyDirection.subtypes,
      includeGlobs: const <String>['models/*.styio'],
      excludeGlobs: const <String>['model?.styio'],
      maxResults: 0,
    );
    final retainedQuery = copiedQuery.copyWith();

    expect(copiedQuery.pattern, 'state');
    expect(copiedQuery.direction, WorkspaceTypeHierarchyDirection.subtypes);
    expect(copiedQuery.includeGlobs, const <String>['models/*.styio']);
    expect(copiedQuery.excludeGlobs, const <String>['model?.styio']);
    expect(copiedQuery.maxResults, 0);
    expect(retainedQuery.pattern, copiedQuery.pattern);
    expect(retainedQuery.direction, copiedQuery.direction);

    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'models/model1.styio': DocumentState(
          documentId: 'models/model1.styio',
          text: 'schema Order {}\n',
          revision: 0,
        ),
        'scripts/main.styio': DocumentState(
          documentId: 'scripts/main.styio',
          text: 'fn run(): i64 { emit 1 }\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceTypeHierarchyService(documentStore: store);

    final emptyPattern = await service.buildHierarchy(
      filePaths: const <String>['models/model1.styio'],
      query: const WorkspaceTypeHierarchyQuery(pattern: '   '),
    );
    final emptyWorkspace = await service.buildHierarchy(
      filePaths: const <String>[
        'models/model1.styio',
        'loose.styio',
        'README.md',
      ],
      query: const WorkspaceTypeHierarchyQuery(
        pattern: 'Order',
        includeGlobs: <String>['**.styio'],
        excludeGlobs: <String>['model?.styio', 'loose.styio'],
      ),
    );
    final noTypes = await service.buildHierarchy(
      filePaths: const <String>['scripts/main.styio'],
      query: const WorkspaceTypeHierarchyQuery(pattern: 'Order'),
    );
    final noMatch = await service.buildHierarchy(
      filePaths: const <String>['models/model1.styio'],
      query: const WorkspaceTypeHierarchyQuery(pattern: 'Missing'),
    );

    expect(emptyPattern.status, WorkspaceTypeHierarchyStatus.emptyPattern);
    expect(emptyPattern.message, contains('requires a type name'));
    expect(emptyWorkspace.status, WorkspaceTypeHierarchyStatus.emptyWorkspace);
    expect(noTypes.status, WorkspaceTypeHierarchyStatus.noTypes);
    expect(noTypes.message, contains('No workspace type declarations'));
    expect(noMatch.status, WorkspaceTypeHierarchyStatus.noTypes);
    expect(noMatch.typesIndexed, 1);
    expect(noMatch.message, contains('Missing'));
  });

  test('workspace type hierarchy ranks fuzzy matches and duplicate relations',
      () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'models/duplicates.styio': DocumentState(
          documentId: 'models/duplicates.styio',
          text: '''
schema Shared {
}

schema Shared {
}

state PendingState {
}

schema PrefixOrder {
  related: Shared
}

schema KeywordBody state PendingState {
}

schema Inline price: Price
schema Open {
  price: Price
schema Price {
}
''',
          revision: 0,
        ),
        'models/shared_extra.styio': DocumentState(
          documentId: 'models/shared_extra.styio',
          text: '''
schema Shared {
}
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceTypeHierarchyService(documentStore: store);

    final duplicateRelations = await service.buildHierarchy(
      filePaths: const <String>[
        'models/duplicates.styio',
        'models/shared_extra.styio',
      ],
      query: const WorkspaceTypeHierarchyQuery(pattern: 'PrefixOrder'),
    );
    final prefixMatch = await service.buildHierarchy(
      filePaths: const <String>['models/duplicates.styio'],
      query: const WorkspaceTypeHierarchyQuery(pattern: 'Pending'),
    );
    final containsMatch = await service.buildHierarchy(
      filePaths: const <String>['models/duplicates.styio'],
      query: const WorkspaceTypeHierarchyQuery(pattern: 'Body'),
    );
    final kindMatch = await service.buildHierarchy(
      filePaths: const <String>['models/duplicates.styio'],
      query: const WorkspaceTypeHierarchyQuery(pattern: 'state'),
    );
    final pathMatch = await service.buildHierarchy(
      filePaths: const <String>['models/shared_extra.styio'],
      query: const WorkspaceTypeHierarchyQuery(pattern: 'shared_extra'),
    );
    final inlineBody = await service.buildHierarchy(
      filePaths: const <String>['models/duplicates.styio'],
      query: const WorkspaceTypeHierarchyQuery(pattern: 'Inline'),
    );
    final openBody = await service.buildHierarchy(
      filePaths: const <String>['models/duplicates.styio'],
      query: const WorkspaceTypeHierarchyQuery(pattern: 'Open'),
    );

    expect(duplicateRelations.status, WorkspaceTypeHierarchyStatus.completed);
    expect(duplicateRelations.relationCount, 3);
    expect(duplicateRelations.referenceCount, 3);
    expect(duplicateRelations.matchedFileCount, 2);
    expect(
      duplicateRelations.relations.map((relation) => relation.symbol.name),
      everyElement('Shared'),
    );
    expect(prefixMatch.target?.name, 'PendingState');
    expect(prefixMatch.target?.kindLabel, 'state');
    expect(containsMatch.target?.name, 'KeywordBody');
    expect(
      containsMatch.relations.map((relation) => relation.symbol.name),
      contains('PendingState'),
    );
    expect(kindMatch.target?.kindLabel, 'state');
    expect(pathMatch.target?.filePath, 'models/shared_extra.styio');
    expect(inlineBody.relations.single.symbol.name, 'Price');
    expect(openBody.relations.single.symbol.name, 'Price');
  });
}
