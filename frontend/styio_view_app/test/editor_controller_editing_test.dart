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

  test('moves caret to smart line start without document history', () {
    const text = 'fn main() {\n  value = 1\n}\n';
    final valueStart = text.indexOf('value');
    final lineStart = text.lastIndexOf('\n', valueStart) + 1;
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(valueStart + 3),
    );

    controller.moveCaretToSmartLineStart();
    expect(controller.selection.end, valueStart);

    controller.moveCaretToSmartLineStart();
    expect(controller.selection.end, lineStart);

    controller.moveCaretToSmartLineStart();
    expect(controller.selection.end, valueStart);
    expect(controller.canUndo, isFalse);
  });

  test('extends selection to smart line start', () {
    const text = 'fn main() {\n  value = 1\n}\n';
    final valueStart = text.indexOf('value');
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(valueStart + 3),
    );

    controller.moveCaretToSmartLineStart(expandSelection: true);

    expect(controller.selection.baseOffset, valueStart + 3);
    expect(controller.selection.extentOffset, valueStart);
    expect(controller.document.text, text);
    expect(controller.canUndo, isFalse);
  });

  test('moves smart line start on blank indented lines to column zero', () {
    const text = 'alpha\n  \nomega';
    final blankLineStart = text.indexOf('\n') + 1;
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(blankLineStart + 2),
    );

    controller.moveCaretToSmartLineStart();

    expect(controller.selection.end, blankLineStart);
    expect(controller.canUndo, isFalse);
  });

  test('moves caret by token-aware word stops without document history', () {
    const text = 'alpha beta\nnext_state renderFlow';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(1),
    );

    controller.moveCaretByWord(forward: true);
    expect(controller.selection.end, text.indexOf('alpha') + 'alpha'.length);

    controller.moveCaretByWord(forward: true);
    expect(controller.selection.end, text.indexOf('beta'));

    controller.moveCaretByWord(forward: true);
    expect(controller.selection.end, text.indexOf('beta') + 'beta'.length);

    controller.moveCaretByWord(forward: false);
    expect(controller.selection.end, text.indexOf('beta'));

    controller.selectCollapsed(text.indexOf('next_state'));
    controller.moveCaretByWord(forward: true);
    expect(controller.selection.end, text.indexOf('_'));

    controller.moveCaretByWord(forward: true);
    expect(controller.selection.end, text.indexOf('state'));

    controller.selectCollapsed(text.indexOf('renderFlow'));
    controller.moveCaretByWord(forward: true);
    expect(controller.selection.end, text.indexOf('Flow'));
    expect(controller.canUndo, isFalse);
  });

  test('extends selection by token-aware word stops', () {
    const text = 'alpha beta';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(0),
    );

    controller.moveCaretByWord(forward: true, expandSelection: true);

    expect(controller.selection.start, 0);
    expect(controller.selection.end, 'alpha'.length);
    expect(controller.document.text, text);
    expect(controller.canUndo, isFalse);
  });

  test('deletes to token-aware word boundaries', () {
    const text = 'alpha beta';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(text.length),
    );

    expect(controller.deleteToWordBoundary(forward: false), isTrue);
    expect(controller.document.text, 'alpha ');
    expect(controller.selection.end, 'alpha '.length);
    expect(controller.canUndo, isTrue);

    controller.undo();
    controller.selectCollapsed(text.indexOf('beta'));

    expect(controller.deleteToWordBoundary(forward: true), isTrue);
    expect(controller.document.text, 'alpha ');
    expect(controller.selection.end, text.indexOf('beta'));
  });

  test('deletes active selection through word-boundary delete action', () {
    const text = 'alpha beta';
    final start = text.indexOf('beta');
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState(
        baseOffset: start,
        extentOffset: text.length,
      ),
    );

    expect(controller.deleteToWordBoundary(forward: false), isTrue);
    expect(controller.document.text, 'alpha ');
    expect(controller.selection.end, start);
  });

  test('does not create undo entries for word delete at document boundary', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: 'alpha',
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(0),
    );

    expect(controller.deleteToWordBoundary(forward: false), isFalse);
    expect(controller.document.text, 'alpha');
    expect(controller.canUndo, isFalse);

    controller.selectCollapsed(controller.document.length);
    expect(controller.deleteToWordBoundary(forward: true), isFalse);
    expect(controller.document.text, 'alpha');
    expect(controller.canUndo, isFalse);
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

  test('inserts newline with inherited indentation', () {
    const text = 'fn main() {\n  value = 1';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(text.length),
    );

    controller.insertNewline();

    expect(controller.document.text, 'fn main() {\n  value = 1\n  ');
    expect(controller.selection.end, controller.document.length);
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.document.text, text);
  });

  test('inserts newline with one extra indent after opening pairs', () {
    const text = 'fn main() {';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(text.length),
    );

    controller.insertNewline();

    expect(controller.document.text, 'fn main() {\n  ');
    expect(controller.selection.end, controller.document.length);
  });

  test('splits empty paired braces with inner and closing indentation', () {
    const text = '  ||> {}';
    final caretOffset = text.indexOf('{') + 1;
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(caretOffset),
    );

    controller.insertNewline();

    expect(controller.document.text, '  ||> {\n    \n  }');
    expect(controller.selection.end, '  ||> {\n    '.length);
  });

  test('indents and outdents the current line preserving caret column', () {
    const text = 'alpha\nbeta\n';
    final caretOffset = text.indexOf('beta') + 2;
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(caretOffset),
    );

    expect(controller.indentLineOrSelection(), isTrue);
    expect(controller.document.text, 'alpha\n  beta\n');
    expect(controller.selection.end, caretOffset + 2);
    expect(controller.canUndo, isTrue);

    expect(controller.outdentLineOrSelection(), isTrue);
    expect(controller.document.text, text);
    expect(controller.selection.end, caretOffset);
  });

  test('indents and outdents selected lines as a block', () {
    const text = 'one\ntwo\nthree\n';
    final start = text.indexOf('two');
    final end = text.indexOf('three') + 'three'.length;
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState(baseOffset: start, extentOffset: end),
    );

    expect(controller.indentLineOrSelection(), isTrue);
    expect(controller.document.text, 'one\n  two\n  three\n');
    expect(controller.selection.start, start);
    expect(controller.selection.end, 'one\n  two\n  three'.length);

    expect(controller.outdentLineOrSelection(), isTrue);
    expect(controller.document.text, text);
    expect(controller.selection.start, start);
    expect(controller.selection.end, end);
  });

  test('does not create undo entries when outdent has no line indent', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: 'alpha',
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(2),
    );

    expect(controller.outdentLineOrSelection(), isFalse);
    expect(controller.document.text, 'alpha');
    expect(controller.canUndo, isFalse);
  });

  test('inserts paired braces with the caret between them', () {
    const text = 'fn main() ';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(text.length),
    );

    controller.insertTypedCharacter('{');

    expect(controller.document.text, 'fn main() {}');
    expect(controller.selection.end, text.length + 1);
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.document.text, text);
  });

  test('surrounds selected text when typing a quote or brace', () {
    const text = 'value';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState(
        baseOffset: 0,
        extentOffset: text.length,
      ),
    );

    controller.insertTypedCharacter('"');

    expect(controller.document.text, '"value"');
    expect(controller.selection.end, '"value"'.length);
    expect(controller.canUndo, isTrue);
  });

  test('skips closing paired characters and backspaces empty pairs', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: '[]',
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(1),
    );

    controller.insertTypedCharacter(']');

    expect(controller.document.text, '[]');
    expect(controller.selection.end, 2);
    expect(controller.canUndo, isFalse);

    controller.selectCollapsed(1);
    controller.backspace();

    expect(controller.document.text, '');
    expect(controller.selection.end, 0);
    expect(controller.canUndo, isTrue);
  });

  test('deletes the current line and places caret at next line start', () {
    const text = 'alpha\nbeta\ngamma\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('beta') + 2),
    );

    expect(controller.deleteLineAtSelection(), isTrue);
    expect(controller.document.text, 'alpha\ngamma\n');
    expect(controller.selection.end, 'alpha\n'.length);
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.document.text, text);
    expect(controller.selection.end, text.indexOf('beta') + 2);
  });

  test('deletes selected lines as a block', () {
    const text = 'one\ntwo\nthree\nfour\n';
    final start = text.indexOf('two');
    final end = text.indexOf('three') + 'three'.length;
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState(baseOffset: start, extentOffset: end),
    );

    expect(controller.deleteLineAtSelection(), isTrue);
    expect(controller.document.text, 'one\nfour\n');
    expect(controller.selection.end, start);
  });

  test('deletes the final line without inventing extra text', () {
    const text = 'alpha\nbeta';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('beta') + 2),
    );

    expect(controller.deleteLineAtSelection(), isTrue);
    expect(controller.document.text, 'alpha\n');
    expect(controller.selection.end, controller.document.length);

    expect(controller.deleteLineAtSelection(), isTrue);
    expect(controller.document.text, '');
    expect(controller.selection.end, 0);

    expect(controller.deleteLineAtSelection(), isFalse);
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

  test('extends and shrinks structural selection without document history', () {
    const text = 'fn main(user) {\n  value = user\n}\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('value') + 2),
    );

    expect(controller.extendSelectionStructurally(), isTrue);
    expect(controller.selection.start, text.indexOf('value'));
    expect(controller.selection.end, text.indexOf('value') + 'value'.length);

    expect(controller.extendSelectionStructurally(), isTrue);
    expect(
      text.substring(controller.selection.start, controller.selection.end),
      contains('value = user'),
    );
    expect(controller.canUndo, isFalse);

    expect(controller.shrinkSelectionStructurally(), isTrue);
    expect(controller.selection.start, text.indexOf('value'));
    expect(controller.selection.end, text.indexOf('value') + 'value'.length);

    expect(controller.shrinkSelectionStructurally(), isTrue);
    expect(controller.selection.isCollapsed, isTrue);
    expect(controller.selection.end, text.indexOf('value') + 2);
    expect(controller.document.text, text);
  });

  test('surrounds the current statement with a Styio task block', () {
    const text = 'fn main() {\n  value = 1\n  next = 2\n}\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('value') + 2),
    );

    final taskTemplate = controller.surroundTemplatesAtSelection.firstWhere(
      (template) => template.id == 'styio.task-block',
    );

    expect(controller.applySurroundTemplateAtSelection(taskTemplate), isTrue);
    expect(
      controller.document.text,
      'fn main() {\n  ||> {\n    value = 1\n  }\n  next = 2\n}\n',
    );
    expect(
      controller.document.text.substring(
        controller.selection.start,
        controller.selection.end,
      ),
      '    value = 1',
    );
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.document.text, text);
  });

  test('surrounds selected statements as an indented block', () {
    const text = 'fn main() {\n  value = 1\n  next = 2\n}\n';
    final start = text.indexOf('value');
    final end = text.indexOf('next') + 'next = 2'.length;
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState(baseOffset: start, extentOffset: end),
    );

    final taskTemplate = controller.surroundTemplatesAtSelection.firstWhere(
      (template) => template.id == 'styio.task-block',
    );

    expect(controller.applySurroundTemplateAtSelection(taskTemplate), isTrue);
    expect(
      controller.document.text,
      'fn main() {\n  ||> {\n    value = 1\n    next = 2\n  }\n}\n',
    );
    expect(
      controller.document.text.substring(
        controller.selection.start,
        controller.selection.end,
      ),
      '    value = 1\n    next = 2',
    );
  });

  test('does not offer surround templates for blank statements', () {
    const text = 'fn main() {\n  \n}\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('\n  \n') + 3),
    );

    expect(controller.surroundTemplatesAtSelection, isEmpty);
  });

  test('moves caret between matching braces', () {
    const text = 'fn main() {\n  ||> {\n    value = [1]\n  }\n}\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('[')),
    );

    expect(controller.moveCaretToMatchingBrace(), isTrue);
    expect(controller.selection.end, text.indexOf(']') + 1);

    expect(controller.moveCaretToMatchingBrace(), isTrue);
    expect(controller.selection.end, text.indexOf('['));
  });

  test('moves from nested content to the previous unclosed brace', () {
    const text = 'fn main() {\n  ||> {\n    value = 1\n  }\n}\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('value')),
    );

    expect(controller.moveCaretToMatchingBrace(), isTrue);
    expect(controller.selection.end, text.indexOf('{', text.indexOf('||>')));
    expect(controller.canUndo, isFalse);
  });

  test('toggles line comments for the current line', () {
    const text = 'value = 1\nnext = 2\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('value') + 2),
    );

    expect(controller.toggleLineComment(), isTrue);
    expect(controller.document.text, '// value = 1\nnext = 2\n');
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.document.text, text);

    expect(controller.toggleLineComment(), isTrue);
    expect(controller.toggleLineComment(), isTrue);
    expect(controller.document.text, text);
  });

  test('duplicates the current line and preserves caret column', () {
    const text = 'alpha\nbeta\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(2),
    );

    expect(controller.duplicateLineOrSelection(), isTrue);
    expect(controller.document.text, 'alpha\nalpha\nbeta\n');
    expect(controller.selection.end, 8);
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.document.text, text);
  });

  test('duplicates the active selection and selects the duplicate', () {
    const text = 'alpha beta';
    final start = text.indexOf('beta');
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState(
        baseOffset: start,
        extentOffset: start + 4,
      ),
    );

    expect(controller.duplicateLineOrSelection(), isTrue);
    expect(controller.document.text, 'alpha betabeta');
    expect(controller.selection.start, start + 4);
    expect(controller.selection.end, start + 8);
  });

  test('moves the current line while preserving caret column', () {
    const text = 'alpha\nbeta\ngamma\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('beta') + 2),
    );

    expect(controller.moveLineOrSelection(down: false), isTrue);
    expect(controller.document.text, 'beta\nalpha\ngamma\n');
    expect(controller.selection.end, 2);
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.document.text, text);
    expect(controller.selection.end, text.indexOf('beta') + 2);

    expect(controller.moveLineOrSelection(down: true), isTrue);
    expect(controller.document.text, 'alpha\ngamma\nbeta\n');
    expect(
      controller.selection.end,
      controller.document.text.indexOf('beta') + 2,
    );
  });

  test('moves selected lines as a block', () {
    const text = 'one\ntwo\nthree\nfour\n';
    final start = text.indexOf('two');
    final end = text.indexOf('three') + 'three'.length;
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState(baseOffset: start, extentOffset: end),
    );

    expect(controller.moveLineOrSelection(down: false), isTrue);
    expect(controller.document.text, 'two\nthree\none\nfour\n');
    expect(controller.selection.start, 0);
    expect(controller.selection.end, 'two\nthree'.length);
  });

  test('moves lines without adding a trailing newline', () {
    const text = 'alpha\nbeta';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('beta') + 1),
    );

    expect(controller.moveLineOrSelection(down: false), isTrue);
    expect(controller.document.text, 'beta\nalpha');
    expect(controller.selection.end, 1);

    controller.undo();
    controller.selectCollapsed(1);
    expect(controller.moveLineOrSelection(down: true), isTrue);
    expect(controller.document.text, 'beta\nalpha');
    expect(
      controller.selection.end,
      controller.document.text.indexOf('alpha') + 1,
    );
  });

  test('does not move lines beyond document boundaries', () {
    const text = 'alpha\nbeta\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(0),
    );

    expect(controller.moveLineOrSelection(down: false), isFalse);
    expect(controller.document.text, text);

    controller.selectCollapsed(text.indexOf('beta') + 1);
    expect(controller.moveLineOrSelection(down: true), isFalse);
    expect(controller.document.text, text);
    expect(controller.canUndo, isFalse);
  });

  test('joins the current line with the next line', () {
    const text = 'value =\n  source\nnext\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(2),
    );

    expect(controller.joinLinesAtSelection(), isTrue);
    expect(controller.document.text, 'value = source\nnext\n');
    expect(controller.selection.end, 'value = '.length);
    expect(controller.canUndo, isTrue);

    controller.undo();
    expect(controller.document.text, text);
  });

  test('joins selected lines into one selected line', () {
    const text = 'one\n  two\n  three\nfour\n';
    final end = text.indexOf('three') + 'three'.length;
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState(baseOffset: 0, extentOffset: end),
    );

    expect(controller.joinLinesAtSelection(), isTrue);
    expect(controller.document.text, 'one two three\nfour\n');
    expect(controller.selection.start, 0);
    expect(controller.selection.end, 'one two three'.length);
  });

  test('joins lines without adding a trailing newline', () {
    const text = 'alpha\n  beta';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: const SelectionState.collapsed(0),
    );

    expect(controller.joinLinesAtSelection(), isTrue);
    expect(controller.document.text, 'alpha beta');

    expect(controller.joinLinesAtSelection(), isFalse);
    expect(controller.document.text, 'alpha beta');
  });

  test(
    'toggles line comments across selected lines preserving indentation',
    () {
      const text = '  value = 1\n\n  next = 2\nfinal = 3\n';
      final finalLineStart = text.indexOf('final');
      final controller = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'sample.styio',
          text: text,
          revision: 0,
        ),
        languageService: const SimpleStyioLanguageService(),
        initialSelection: SelectionState(
          baseOffset: 0,
          extentOffset: finalLineStart,
        ),
      );

      expect(controller.toggleLineComment(), isTrue);
      expect(
        controller.document.text,
        '  // value = 1\n\n  // next = 2\nfinal = 3\n',
      );

      expect(controller.toggleLineComment(), isTrue);
      expect(controller.document.text, text);
    },
  );

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

    expect(controller.applyRename('price'), isTrue);

    expect(controller.document.text, contains('price = 10'));
    expect(controller.document.text, contains('price -> @resource'));
    expect(controller.document.text, isNot(contains('value')));
    expect(controller.canUndo, isTrue);
  });

  test('rejects invalid rename edits without changing document history', () {
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

    expect(controller.applyRename('1bad'), isFalse);
    expect(controller.document.text, text);
    expect(controller.canUndo, isFalse);
  });

  test(
    'rejects conflicting rename edits without changing document history',
    () {
      const text = 'price = 1\ntotal = price\ntotal -> @stdout\n';
      final controller = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'sample.styio',
          text: text,
          revision: 0,
        ),
        languageService: const SimpleStyioLanguageService(),
        initialSelection: SelectionState.collapsed(text.indexOf('price')),
      );

      final plan = controller.renamePlanAtSelection('total');
      expect(plan?.hasConflicts, isTrue);
      expect(controller.applyRename('total'), isFalse);
      expect(controller.document.text, text);
      expect(controller.canUndo, isFalse);
    },
  );

  test('applies safe delete only for unused current-file variables', () {
    const text = 'used = 1\nunused = 2\nused -> @stdout\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('unused')),
    );

    expect(controller.safeDeletePlanAtSelection?.hasConflicts, isFalse);
    expect(controller.applySafeDeleteAtSelection(), isTrue);
    expect(controller.document.text, 'used = 1\nused -> @stdout\n');
    expect(controller.canUndo, isTrue);
  });

  test('rejects safe delete when current-file usages remain', () {
    const text = 'used = 1\nused -> @stdout\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('used')),
    );

    expect(controller.safeDeletePlanAtSelection?.hasConflicts, isTrue);
    expect(controller.applySafeDeleteAtSelection(), isFalse);
    expect(controller.document.text, text);
    expect(controller.canUndo, isFalse);
  });

  test('applies inline variable edits and removes the declaration', () {
    const text = 'seed = 40 + 2\nvalue = seed\nseed -> @stdout\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('seed')),
    );

    final plan = controller.inlineVariablePlanAtSelection;
    expect(plan?.hasConflicts, isFalse);
    expect(plan?.references.length, 2);
    expect(controller.applyInlineVariableAtSelection(), isTrue);
    expect(controller.document.text, 'value = 40 + 2\n40 + 2 -> @stdout\n');
    expect(controller.canUndo, isTrue);
  });

  test('rejects inline variable when the declaration has no initializer', () {
    const text = 'let pending\npending -> @stdout\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('pending')),
    );

    expect(controller.inlineVariablePlanAtSelection?.hasConflicts, isTrue);
    expect(controller.applyInlineVariableAtSelection(), isFalse);
    expect(controller.document.text, text);
    expect(controller.canUndo, isFalse);
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

  test('selects a resolved reference without changing document history', () {
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

    final reference = controller.referencesAtSelection.last;
    final selected = controller.selectReference(reference);

    expect(selected, isTrue);
    expect(controller.selection.start, text.lastIndexOf('value'));
    expect(
      controller.selection.end,
      text.lastIndexOf('value') + 'value'.length,
    );
    expect(controller.canUndo, isFalse);
    expect(controller.document.text, text);
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
