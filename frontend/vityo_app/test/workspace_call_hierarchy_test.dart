import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace call hierarchy finds incoming callers', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/runtime.styio': DocumentState(
          documentId: 'lib/runtime.styio',
          text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}

fn normalize(value: f64): f64 {
  emit blend(value, 1.0)
}
''',
          revision: 0,
        ),
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/runtime }
fn run(): f64 {
  emit normalize(2.0) + blend(1.0, 2.0)
}
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceCallHierarchyService(documentStore: store);

    final result = await service.buildHierarchy(
      filePaths: const <String>['lib/runtime.styio', 'main.styio'],
      query: const WorkspaceCallHierarchyQuery(pattern: 'blend'),
    );

    expect(result.status, WorkspaceCallHierarchyStatus.completed);
    expect(result.target?.name, 'blend');
    expect(result.callCount, 2);
    expect(result.referenceCount, 2);
    expect(
      result.calls.map((call) => call.symbol.name),
      containsAll(<String>['normalize', 'run']),
    );
    expect(
      result.calls.singleWhere((call) => call.symbol.name == 'run')
          .firstLocation
          .previewText,
      '  emit normalize(2.0) + blend(1.0, 2.0)',
    );
  });

  test('workspace call hierarchy finds outgoing callees', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/runtime.styio': DocumentState(
          documentId: 'lib/runtime.styio',
          text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}

fn normalize(value: f64): f64 {
  emit blend(value, 1.0)
}
''',
          revision: 0,
        ),
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/runtime }
fn run(): f64 {
  emit normalize(2.0) + blend(1.0, 2.0)
}
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceCallHierarchyService(documentStore: store);

    final result = await service.buildHierarchy(
      filePaths: const <String>['lib/runtime.styio', 'main.styio'],
      query: const WorkspaceCallHierarchyQuery(
        pattern: 'run',
        direction: WorkspaceCallHierarchyDirection.outgoing,
      ),
    );

    expect(result.status, WorkspaceCallHierarchyStatus.completed);
    expect(result.target?.name, 'run');
    expect(result.callCount, 2);
    expect(
      result.calls.map((call) => call.symbol.name),
      containsAll(<String>['blend', 'normalize']),
    );
    expect(
      result.calls.map((call) => call.firstLocation.filePath).toSet(),
      equals(<String>{'main.styio'}),
    );
  });

  test('workspace call hierarchy uses unsaved overlay documents', () async {
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
    final service = WorkspaceCallHierarchyService(documentStore: store);

    final result = await service.buildHierarchy(
      filePaths: const <String>['lib/runtime.styio', 'main.styio'],
      overlayDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
@import { lib/runtime }
fn run(): f64 {
  emit blend(1.0, 2.0)
}
''',
          revision: 1,
        ),
      },
      query: const WorkspaceCallHierarchyQuery(pattern: 'blend'),
    );

    expect(result.callCount, 1);
    expect(result.calls.single.symbol.name, 'run');
    expect(
      result.calls.single.firstLocation.previewText,
      '  emit blend(1.0, 2.0)',
    );
  });

  test('workspace call hierarchy reports hit limits', () async {
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
fn first(): f64 {
  emit blend(1.0, 2.0)
}

fn second(): f64 {
  emit blend(3.0, 4.0)
}
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceCallHierarchyService(documentStore: store);

    final result = await service.buildHierarchy(
      filePaths: const <String>['lib/runtime.styio', 'main.styio'],
      query: const WorkspaceCallHierarchyQuery(
        pattern: 'blend',
        maxResults: 1,
      ),
    );

    expect(result.status, WorkspaceCallHierarchyStatus.hitLimit);
    expect(result.hitLimit, isTrue);
    expect(result.referenceCount, 1);
  });
}
