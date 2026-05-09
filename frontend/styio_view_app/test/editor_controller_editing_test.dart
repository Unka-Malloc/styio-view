import 'package:flutter_test/flutter_test.dart';
import 'package:styio_view_app/src/editor/document_state.dart';
import 'package:styio_view_app/src/editor/editor_controller.dart';
import 'package:styio_view_app/src/editor/selection_state.dart';
import 'package:styio_view_app/src/language/language_contract.dart';
import 'package:styio_view_app/src/language/simple_styio_language_service.dart';

void main() {
  test('backspace decomposes substituted operator source', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: 'let flow = source |> sink',
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
    );

    final operatorEnd = controller.document.text.indexOf('|>') + 2;
    controller.selectCollapsed(operatorEnd);
    controller.backspace();

    expect(controller.document.text, 'let flow = source | sink');
    expect(controller.selection.end, operatorEnd - 1);
  });

  test('supports vertical caret movement with column clamping', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: 'ab\ncdef\nxy',
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(6),
    );

    controller.moveCaretVertically(1);
    expect(controller.selection.end, 10);

    controller.moveCaretVertically(-1);
    expect(controller.selection.end, 5);

    controller.moveCaretToLineBoundary(end: false);
    expect(controller.selection.end, 3);
  });

  test('inserts and deletes forward at the caret', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: 'abc',
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(1),
    );

    controller.insertText('Z');
    expect(controller.document.text, 'aZbc');
    expect(controller.selection.end, 2);

    controller.deleteForward();
    expect(controller.document.text, 'aZc');
    expect(controller.selection.end, 2);
  });

  test('expands selection with shifted caret movement', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: 'alpha beta',
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(5),
    );

    controller.moveCaretHorizontally(3, expandSelection: true);
    expect(controller.selection.baseOffset, 5);
    expect(controller.selection.extentOffset, 8);
    expect(controller.selection.isCollapsed, isFalse);

    controller.insertText('|>');
    expect(controller.document.text, 'alpha|>ta');
    expect(controller.selection.isCollapsed, isTrue);
  });

  test(
    'applies completion item by replacing the active token at caret edge',
    () {
      final controller = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'sample.styio',
          text: 'pip',
          revision: 0,
        ),
        languageService: const SimpleStyioLanguageService(),
        initialSelection: const SelectionState.collapsed(3),
      );

      const pipelineCompletion = CompletionItem(
        label: 'pipeline',
        kind: CompletionItemKind.keyword,
        insertText: 'pipeline ',
        detail: 'Declare a pipeline.',
      );

      controller.applyCompletionItem(pipelineCompletion);

      expect(controller.document.text, 'pipeline ');
      expect(controller.selection.end, 'pipeline '.length);
      expect(controller.canUndo, isTrue);
    },
  );

  test('applies best completion item at the caret', () {
    const text = 'job = ||> { <| 42 }\njo';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(text.length),
    );

    final applied = controller.applyBestCompletionAtSelection();

    expect(applied, isTrue);
    expect(controller.document.text, 'job = ||> { <| 42 }\njob');
    expect(controller.canUndo, isTrue);
  });

  test('applies token completion only when an identifier is active', () {
    const text = 'job = ||> { <| 42 }\njo';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(text.length),
    );

    expect(controller.applyTokenCompletionAtSelection(), isTrue);
    expect(controller.document.text, 'job = ||> { <| 42 }\njob');

    controller.loadDocument(
      const DocumentState(documentId: 'sample.styio', text: '', revision: 0),
    );
    expect(controller.applyTokenCompletionAtSelection(), isFalse);
  });

  test('applies formatting edits and preserves collapsed caret position', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: 'let stream = source  \nemit stream  ',
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(19),
    );

    final edits = controller.analysis.formattingEdits;
    controller.applyFormattingEdits(edits);

    expect(controller.document.text, 'let stream = source\nemit stream');
    expect(controller.selection.end, 19);
    expect(controller.analysis.formattingEdits, isEmpty);
  });

  test('applies diagnostic quick fix returned by the language service', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: 'let stream\n',
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
    );

    final diagnostic = controller.analysis.diagnostics.singleWhere(
      (item) => item.code == 'missing-assignment',
    );
    final quickFix = controller.quickFixesForDiagnostics([diagnostic]).single;

    controller.applyDiagnosticQuickFix(quickFix);

    expect(controller.document.text, 'let stream = value\n');
    expect(controller.analysis.diagnostics, isEmpty);
  });

  test('applies first diagnostic quick fix at the caret', () {
    const text = 'let stream\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('stream') + 2),
    );

    final applied = controller.applyFirstQuickFixAtSelection();

    expect(applied, isTrue);
    expect(controller.document.text, 'let stream = value\n');
    expect(controller.canUndo, isTrue);
  });

  test('resolves active token when caret lands on token boundary', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: 'pipeline renderFlow',
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(8),
    );

    expect(controller.tokenAtSelection?.lexeme, 'pipeline');
    expect(controller.semanticKindAtSelection, isNull);

    controller.selectCollapsed(18);
    expect(controller.tokenAtSelection?.lexeme, 'renderFlow');
    expect(controller.semanticKindAtSelection, SemanticKind.pipeline);
  });

  test('resolves definition and current-file usages at the caret', () {
    const text = '''
@resource : f64|..2| := {
  value = 10
  value -> @resource
}
value -> @stdout
''';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.lastIndexOf('value')),
    );

    expect(controller.definitionAtSelection?.symbol.name, 'value');
    expect(controller.referencesAtSelection.length, 3);

    controller.selectCollapsed(text.lastIndexOf('resource'));
    expect(controller.definitionAtSelection?.symbol.kind, SymbolKind.resource);
    expect(controller.referencesAtSelection.length, 2);
  });

  test('applies rename edits from the resolved symbol at caret', () {
    const text = '''
@resource : f64|..2| := {
  value = 10
  value -> @resource
}
''';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.lastIndexOf('value')),
    );

    final plan = controller.renamePlanAtSelection('price');
    expect(plan?.edits.length, 2);

    controller.applyRename('price');

    expect(controller.document.text, contains('price = 10'));
    expect(controller.document.text, contains('price -> @resource'));
    expect(controller.document.text, isNot(contains('value')));
    expect(controller.canUndo, isTrue);
  });

  test('selects the resolved definition without changing document history', () {
    const text = 'value = value\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.lastIndexOf('value')),
    );

    final navigated = controller.selectDefinitionAtSelection();

    expect(navigated, isTrue);
    expect(controller.selection.start, 0);
    expect(controller.selection.end, 'value'.length);
    expect(controller.canUndo, isFalse);
    expect(controller.document.text, text);
  });

  test('selects a document symbol without changing document history', () {
    const text = 'fn main(user) {\n  value = user\n}\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
    );

    final symbol = controller.analysis.documentSymbols.singleWhere(
      (candidate) => candidate.name == 'main',
    );
    final selected = controller.selectDocumentSymbol(symbol);

    expect(selected, isTrue);
    expect(controller.selection.start, text.indexOf('main'));
    expect(controller.selection.end, text.indexOf('main') + 'main'.length);
    expect(controller.canUndo, isFalse);
    expect(controller.document.text, text);
  });

  test('cycles between resolved current-file usages', () {
    const text = 'value = value\nvalue -> @stdout\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('= value') + 3),
    );

    expect(controller.referencesAtSelection.length, 3);

    expect(controller.selectNextReferenceAtSelection(), isTrue);
    expect(controller.selection.start, text.lastIndexOf('value'));

    expect(controller.selectNextReferenceAtSelection(), isTrue);
    expect(controller.selection.start, 0);

    expect(controller.selectPreviousReferenceAtSelection(), isTrue);
    expect(controller.selection.start, text.lastIndexOf('value'));
  });

  test('cycles between diagnostics without changing document history', () {
    const text = 'let stream\nmissingPrice -> @stdout\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(0),
    );

    expect(controller.analysis.diagnostics.length, 2);

    expect(controller.selectNextDiagnosticAtSelection(), isTrue);
    expect(controller.selection.start, 0);
    expect(controller.selection.end, text.indexOf('\n'));

    expect(controller.selectNextDiagnosticAtSelection(), isTrue);
    expect(controller.selection.start, text.indexOf('missingPrice'));
    expect(controller.canUndo, isFalse);

    expect(controller.selectPreviousDiagnosticAtSelection(), isTrue);
    expect(controller.selection.start, 0);
  });

  test('selects a diagnostic without changing document history', () {
    const text = 'let stream\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
    );

    final diagnostic = controller.analysis.diagnostics.singleWhere(
      (item) => item.code == 'missing-assignment',
    );
    final selected = controller.selectDiagnostic(diagnostic);

    expect(selected, isTrue);
    expect(controller.selection.start, 0);
    expect(controller.selection.end, text.indexOf('\n'));
    expect(controller.canUndo, isFalse);
    expect(controller.document.text, text);
  });
}
