import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace implementation finds type implementors', () async {
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
    final service = WorkspaceImplementationService(documentStore: store);

    final result = await service.findImplementations(
      filePaths: const <String>['models/types.styio'],
      query: const WorkspaceImplementationQuery(pattern: 'Price'),
    );

    expect(result.status, WorkspaceImplementationStatus.completed);
    expect(result.target?.name, 'Price');
    expect(result.implementationCount, greaterThanOrEqualTo(2));
    expect(result.referenceCount, greaterThanOrEqualTo(2));
    expect(
      result.implementations.map((item) => item.name).toSet(),
      <String>{'Order', 'Quote'},
    );
    expect(
      result.implementations.singleWhere(
        (item) => item.name == 'Order',
      ).firstReference.previewText,
      '  price: Price',
    );
  });

  test('workspace implementation uses unsaved overlay documents', () async {
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
    final service = WorkspaceImplementationService(documentStore: store);

    final result = await service.findImplementations(
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
      query: const WorkspaceImplementationQuery(pattern: 'Price'),
    );

    expect(result.status, WorkspaceImplementationStatus.completed);
    expect(result.implementations.single.name, 'Order');
    expect(
      result.implementations.single.firstReference.previewText,
      '  price: Price',
    );
  });

  test('workspace implementation reports limits and no implementations', () async {
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

schema Isolated {
}
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceImplementationService(documentStore: store);

    final limitedResult = await service.findImplementations(
      filePaths: const <String>['models/types.styio'],
      query: const WorkspaceImplementationQuery(
        pattern: 'Price',
        maxResults: 1,
      ),
    );
    final isolatedResult = await service.findImplementations(
      filePaths: const <String>['models/types.styio'],
      query: const WorkspaceImplementationQuery(pattern: 'Isolated'),
    );

    expect(limitedResult.status, WorkspaceImplementationStatus.hitLimit);
    expect(limitedResult.hitLimit, isTrue);
    expect(limitedResult.referenceCount, 1);
    expect(
      isolatedResult.status,
      WorkspaceImplementationStatus.noImplementations,
    );
    expect(isolatedResult.message, contains('No implementations'));
  });
}
