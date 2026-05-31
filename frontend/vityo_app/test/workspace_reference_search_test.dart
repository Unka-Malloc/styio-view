import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
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
}
