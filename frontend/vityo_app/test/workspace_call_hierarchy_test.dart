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

  test('workspace call hierarchy reports boundary query states', () async {
    const baseQuery = WorkspaceCallHierarchyQuery(pattern: 'run');
    final copiedQuery = baseQuery.copyWith(
      pattern: 'task',
      direction: WorkspaceCallHierarchyDirection.outgoing,
      includeGlobs: const <String>['lib/*.styio'],
      excludeGlobs: const <String>['model?.styio'],
      maxResults: 0,
    );
    final retainedQuery = copiedQuery.copyWith();

    expect(copiedQuery.pattern, 'task');
    expect(copiedQuery.direction, WorkspaceCallHierarchyDirection.outgoing);
    expect(copiedQuery.includeGlobs, const <String>['lib/*.styio']);
    expect(copiedQuery.excludeGlobs, const <String>['model?.styio']);
    expect(copiedQuery.maxResults, 0);
    expect(retainedQuery.pattern, copiedQuery.pattern);
    expect(retainedQuery.direction, copiedQuery.direction);

    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/model1.styio': DocumentState(
          documentId: 'lib/model1.styio',
          text: '''
fn lonely(): i64 {
  emit 1
}
''',
          revision: 0,
        ),
        'scripts/main.styio': DocumentState(
          documentId: 'scripts/main.styio',
          text: 'value = 1\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceCallHierarchyService(documentStore: store);

    final emptyPattern = await service.buildHierarchy(
      filePaths: const <String>['lib/model1.styio'],
      query: const WorkspaceCallHierarchyQuery(pattern: '   '),
    );
    final emptyWorkspace = await service.buildHierarchy(
      filePaths: const <String>[
        'lib/model1.styio',
        'loose.styio',
        'README.md',
      ],
      query: const WorkspaceCallHierarchyQuery(
        pattern: 'run',
        includeGlobs: <String>['**.styio'],
        excludeGlobs: <String>['model?.styio', 'loose.styio'],
      ),
    );
    final noDefinitions = await service.buildHierarchy(
      filePaths: const <String>['scripts/main.styio'],
      query: const WorkspaceCallHierarchyQuery(pattern: 'run'),
    );
    final noMatch = await service.buildHierarchy(
      filePaths: const <String>['lib/model1.styio'],
      query: const WorkspaceCallHierarchyQuery(pattern: 'missing'),
    );
    final incomingNoCalls = await service.buildHierarchy(
      filePaths: const <String>['lib/model1.styio'],
      query: const WorkspaceCallHierarchyQuery(pattern: 'lonely'),
    );
    final outgoingNoCalls = await service.buildHierarchy(
      filePaths: const <String>['lib/model1.styio'],
      query: const WorkspaceCallHierarchyQuery(
        pattern: 'lonely',
        direction: WorkspaceCallHierarchyDirection.outgoing,
      ),
    );

    expect(emptyPattern.status, WorkspaceCallHierarchyStatus.emptyPattern);
    expect(emptyPattern.message, contains('requires a symbol name'));
    expect(emptyWorkspace.status, WorkspaceCallHierarchyStatus.emptyWorkspace);
    expect(noDefinitions.status, WorkspaceCallHierarchyStatus.noDefinitions);
    expect(noDefinitions.definitionsSearched, 0);
    expect(noMatch.status, WorkspaceCallHierarchyStatus.noDefinitions);
    expect(noMatch.definitionsSearched, 1);
    expect(noMatch.message, contains('missing'));
    expect(incomingNoCalls.status, WorkspaceCallHierarchyStatus.completed);
    expect(incomingNoCalls.callCount, 0);
    expect(incomingNoCalls.message, contains('No incoming calls'));
    expect(outgoingNoCalls.status, WorkspaceCallHierarchyStatus.completed);
    expect(outgoingNoCalls.message, contains('No outgoing calls'));
  });

  test('workspace call hierarchy ranks task, path, and fuzzy matches',
      () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'tasks/runtime.styio': DocumentState(
          documentId: 'tasks/runtime.styio',
          text: '''
load = ||> { <| 42 }
buildData = ||> { <| load }

fn tieAlpha(): i64 {
  emit 1
}

fn tieBravo(): i64 {
  emit 2
}

fn duplicate(): i64 {
  emit 1
}

fn duplicate(): i64 {
  emit 2
}

fn open(): f64 {
  emit blend(1.0, 2.0)

fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
          revision: 0,
        ),
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
@import { tasks/runtime }
value = blend(1.0, 2.0)
?| load -> result: i64
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceCallHierarchyService(documentStore: store);

    final taskKind = await service.buildHierarchy(
      filePaths: const <String>['tasks/runtime.styio', 'main.styio'],
      query: const WorkspaceCallHierarchyQuery(pattern: 'task'),
    );
    final fuzzyTask = await service.buildHierarchy(
      filePaths: const <String>['tasks/runtime.styio'],
      query: const WorkspaceCallHierarchyQuery(pattern: 'bda'),
    );
    final pathMatch = await service.buildHierarchy(
      filePaths: const <String>['tasks/runtime.styio'],
      query: const WorkspaceCallHierarchyQuery(pattern: 'runtime'),
    );
    final nameTie = await service.buildHierarchy(
      filePaths: const <String>['tasks/runtime.styio'],
      query: const WorkspaceCallHierarchyQuery(pattern: 'tie'),
    );
    final duplicateTie = await service.buildHierarchy(
      filePaths: const <String>['tasks/runtime.styio'],
      query: const WorkspaceCallHierarchyQuery(pattern: 'duplicate'),
    );
    final incoming = await service.buildHierarchy(
      filePaths: const <String>['tasks/runtime.styio', 'main.styio'],
      query: const WorkspaceCallHierarchyQuery(pattern: 'blend'),
    );
    final outgoingTask = await service.buildHierarchy(
      filePaths: const <String>['tasks/runtime.styio'],
      query: const WorkspaceCallHierarchyQuery(
        pattern: 'buildData',
        direction: WorkspaceCallHierarchyDirection.outgoing,
      ),
    );

    expect(taskKind.target?.kind, WorkspaceCallHierarchySymbolKind.task);
    expect(taskKind.target?.kindLabel, 'task');
    expect(fuzzyTask.target?.name, 'buildData');
    expect(fuzzyTask.target?.kind, WorkspaceCallHierarchySymbolKind.task);
    expect(pathMatch.target?.filePath, 'tasks/runtime.styio');
    expect(nameTie.target?.name, 'tieAlpha');
    expect(duplicateTie.target?.name, 'duplicate');
    expect(
      incoming.calls.any((call) => call.symbol.isTopLevel),
      isTrue,
    );
    expect(
      incoming.calls
          .singleWhere((call) => call.symbol.isTopLevel)
          .symbol
          .kindLabel,
      'top level',
    );
    expect(incoming.matchedFileCount, 2);
    expect(outgoingTask.target?.kindLabel, 'task');
    expect(outgoingTask.status, WorkspaceCallHierarchyStatus.completed);
    expect(outgoingTask.calls, isEmpty);
  });
}
