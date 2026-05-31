import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace problems collects project diagnostics across files', () async {
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
price = 1.0
price -> @prices
''',
          revision: 0,
        ),
        'README.md': DocumentState(
          documentId: 'README.md',
          text: 'price -> @prices\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceProblemsService(documentStore: store);

    final result = await service.collectProblems(
      filePaths: const <String>[
        'main.styio',
        'lib/runtime.styio',
        'README.md',
      ],
      query: const WorkspaceProblemsQuery(),
    );

    expect(result.status, WorkspaceProblemsStatus.completed);
    expect(result.filesSearched, 2);
    expect(result.problemCount, greaterThanOrEqualTo(1));
    expect(result.errorCount, greaterThanOrEqualTo(1));
    expect(
      result.problems.map((problem) => problem.diagnostic.code),
      contains('unresolved-resource'),
    );
    expect(
      result.problems.map((problem) => problem.filePath),
      isNot(contains('README.md')),
    );
    expect(result.problems.first.severity, DiagnosticSeverity.error);
  });

  test('workspace problems filters by severity and text', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
price = 1.0
price -> @prices
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceProblemsService(documentStore: store);

    final result = await service.collectProblems(
      filePaths: const <String>['main.styio'],
      query: const WorkspaceProblemsQuery(
        pattern: 'prices',
        severities: <DiagnosticSeverity>{DiagnosticSeverity.error},
      ),
    );

    expect(result.problemCount, 1);
    expect(result.problems.single.diagnostic.code, 'unresolved-resource');
    expect(result.problems.single.previewText, 'price -> @prices');
  });

  test('workspace problems uses unsaved overlay documents', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: 'price = 1.0\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceProblemsService(documentStore: store);

    final result = await service.collectProblems(
      filePaths: const <String>['main.styio'],
      overlayDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
price = 1.0
price -> @prices
''',
          revision: 1,
        ),
      },
      query: const WorkspaceProblemsQuery(),
    );

    expect(
      result.problems.map((problem) => problem.diagnostic.code),
      contains('unresolved-resource'),
    );
  });

  test('workspace problems reports hit limits', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'main.styio': DocumentState(
          documentId: 'main.styio',
          text: '''
price = 1.0
price -> @prices
total -> @totals
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceProblemsService(documentStore: store);

    final result = await service.collectProblems(
      filePaths: const <String>['main.styio'],
      query: const WorkspaceProblemsQuery(maxResults: 1),
    );

    expect(result.status, WorkspaceProblemsStatus.hitLimit);
    expect(result.hitLimit, isTrue);
    expect(result.problemCount, 1);
  });
}
