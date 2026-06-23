import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace outline lists current file document symbols', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '''
entry = 1
#calculate := (input) => {
  <| input
}
''',
          revision: 0,
        ),
        'README.md': DocumentState(
          documentId: 'README.md',
          text: '#calculate is not a Styio symbol here\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceOutlineService(documentStore: store);

    final result = await service.collectOutline(
      filePaths: const <String>['README.md', 'src/main.styio'],
      query: const WorkspaceOutlineQuery(targetFilePath: 'src/main.styio'),
    );

    expect(result.status, WorkspaceOutlineStatus.completed);
    expect(result.filesSearched, 1);
    expect(result.symbolsIndexed, greaterThanOrEqualTo(2));
    expect(result.items.map((item) => item.name), contains('entry'));
    expect(result.items.map((item) => item.name), contains('calculate'));
    final calculateItems = result.items.where(
      (item) => item.name == 'calculate',
    );
    expect(
      calculateItems.map((item) => item.kind),
      contains(SymbolKind.function),
    );
  });

  test('workspace outline filters symbols and reports hit limits', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '''
alpha = 1
beta = 2
#calculate := (input) => {
  <| input
}
''',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceOutlineService(documentStore: store);

    final filtered = await service.collectOutline(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceOutlineQuery(
        targetFilePath: 'src/main.styio',
        pattern: 'calc',
      ),
    );
    final limited = await service.collectOutline(
      filePaths: const <String>['src/main.styio'],
      query: const WorkspaceOutlineQuery(
        targetFilePath: 'src/main.styio',
        maxResults: 1,
      ),
    );

    expect(filtered.items.map((item) => item.name), contains('calculate'));
    expect(filtered.items.first.name, 'calculate');
    expect(limited.status, WorkspaceOutlineStatus.hitLimit);
    expect(limited.hitLimit, isTrue);
    expect(limited.matchCount, 1);
  });

  test('workspace outline uses unsaved overlay documents', () async {
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: 'entry = 1\n',
          revision: 0,
        ),
      },
    );
    final service = WorkspaceOutlineService(documentStore: store);

    final result = await service.collectOutline(
      filePaths: const <String>['src/main.styio'],
      overlayDocuments: const <String, DocumentState>{
        'src/main.styio': DocumentState(
          documentId: 'src/main.styio',
          text: '#calculate := (input) => {\n  <| input\n}\n',
          revision: 1,
        ),
      },
      query: const WorkspaceOutlineQuery(targetFilePath: 'src/main.styio'),
    );

    expect(result.items.map((item) => item.name), contains('calculate'));
    expect(result.items.map((item) => item.name), isNot(contains('entry')));
  });
}
