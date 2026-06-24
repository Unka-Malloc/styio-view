import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/editor/selection/selection_state.dart';
import 'package:vityo_app/src/view_ide/interaction/run_unit_selection.dart';

void main() {
  test('explicit selection becomes the run unit', () {
    const document = DocumentState(
      documentId: 'src/main.styio',
      text: '#first := () => {}\n#second := () => {}\n',
      revision: 1,
    );
    final start = document.text.indexOf('#second');
    final end = start + '#second := () => {}'.length;

    final unit = selectRunUnitForEditor(
      document: document,
      selection: SelectionState(baseOffset: start, extentOffset: end),
    );

    expect(unit.kind, RunUnitSelectionKind.explicitSelection);
    expect(unit.range.start, start);
    expect(unit.range.end, end);
    expect(unit.text, '#second := () => {}');
  });

  test('collapsed caret selects the containing top-level Styio block', () {
    const text = '''
#first := () => {
  <| 1
}
#second := () => {
  <| 2
}
''';
    const document = DocumentState(
      documentId: 'src/main.styio',
      text: text,
      revision: 1,
    );

    final unit = selectRunUnitForEditor(
      document: document,
      selection: SelectionState.collapsed(text.indexOf('<| 2')),
    );

    expect(unit.kind, RunUnitSelectionKind.topLevelBlock);
    expect(unit.text, '''
#second := () => {
  <| 2
}''');
  });

  test('collapsed caret selects top-level assignment-style block', () {
    const text = '''
value := 1
value

other := 2
other
''';
    const document = DocumentState(
      documentId: 'scratch.styio',
      text: text,
      revision: 1,
    );

    final unit = selectRunUnitForEditor(
      document: document,
      selection: SelectionState.collapsed(text.indexOf('other')),
    );

    expect(unit.kind, RunUnitSelectionKind.topLevelBlock);
    expect(unit.text, '''
other := 2
other''');
  });
}
