import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace breadcrumbs include path and active document symbol', () {
    const document = DocumentState(
      documentId: 'src/main.styio',
      text: 'entry = 1\n#calculate := (input) => {\n  <| input\n}\n',
      revision: 0,
    );
    final service = const WorkspaceBreadcrumbsService();
    final caretOffset = document.text.indexOf('<| input');

    final result = service.buildForDocument(
      filePaths: const <String>['README.md', 'src/main.styio'],
      document: document,
      query: WorkspaceBreadcrumbsQuery(
        targetFilePath: 'src/main.styio',
        caretOffset: caretOffset,
      ),
    );

    expect(result.status, WorkspaceBreadcrumbsStatus.ready);
    expect(result.symbolsIndexed, greaterThanOrEqualTo(2));
    expect(result.items.map((item) => item.label), <String>[
      'src',
      'main.styio',
      'calculate',
    ]);
    expect(result.activeSymbol?.kind, WorkspaceBreadcrumbItemKind.symbol);
    expect(result.activeSymbol?.symbolKind, SymbolKind.function);
    expect(result.activeSymbol?.line, 1);
  });

  test('workspace breadcrumbs fall back to a path-only trail', () {
    const document = DocumentState(
      documentId: 'README.md',
      text: '# Not a Styio source file\n',
      revision: 0,
    );
    final service = const WorkspaceBreadcrumbsService();

    final result = service.buildForDocument(
      filePaths: const <String>['README.md'],
      document: document,
      query: const WorkspaceBreadcrumbsQuery(
        targetFilePath: 'README.md',
        caretOffset: 0,
      ),
    );

    expect(result.status, WorkspaceBreadcrumbsStatus.pathOnly);
    expect(result.symbolsIndexed, 0);
    expect(result.hasSymbolContext, isFalse);
    expect(result.items.map((item) => item.label), <String>['README.md']);
  });

  test('workspace breadcrumbs require an active workspace file', () {
    const document = DocumentState(
      documentId: 'missing.styio',
      text: 'value = 1\n',
      revision: 0,
    );
    final service = const WorkspaceBreadcrumbsService();

    final result = service.buildForDocument(
      filePaths: const <String>['src/main.styio'],
      document: document,
      query: const WorkspaceBreadcrumbsQuery(
        targetFilePath: 'missing.styio',
        caretOffset: 0,
      ),
    );

    expect(result.status, WorkspaceBreadcrumbsStatus.emptyWorkspace);
    expect(result.items, isEmpty);
    expect(result.message, isNotNull);
  });
}
