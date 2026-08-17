import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/editor.dart' hide TextRange;
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  group('editor accessibility input semantics', () {
    testWidgets('focused source semantics expose editable value and actions', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = _controller('left אב right');
      addTearDown(controller.dispose);
      controller.selectSelections(const <SelectionState>[
        SelectionState.collapsed(0),
        SelectionState(baseOffset: 5, extentOffset: 7),
        SelectionState.collapsed(13),
      ], primaryIndex: 1);

      await tester.pumpWidget(_harness(controller));
      await _focusSource(tester);

      final node = tester.getSemantics(
        find.byKey(const ValueKey('source-buffer-semantics')),
      );
      final data = node.getSemanticsData();
      expect(node.flagsCollection.isTextField, isTrue);
      expect(node.flagsCollection.isFocused, Tristate.isTrue);
      expect(data.textSelection, isNotNull);
      expect(data.value, isNotEmpty);
      expect('${data.label} ${data.hint}', contains('3 selections'));
      expect(data.hasAction(SemanticsAction.setSelection), isTrue);
      expect(data.hasAction(SemanticsAction.setText), isTrue);
      expect(
        data.hasAction(SemanticsAction.moveCursorForwardByCharacter),
        isTrue,
      );
      expect(
        data.hasAction(SemanticsAction.moveCursorBackwardByCharacter),
        isTrue,
      );
      semantics.dispose();
    });

    testWidgets('semantics report composition and input status in hint', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final controller = _controller('seed');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_harness(controller));
      await _focusSource(tester);

      tester.testTextInput.updateEditingValue(
        _replaceRemoteSelection(
          _remoteEditingValue(tester),
          '語',
          composing: true,
        ),
      );
      await tester.pump();

      final composingNode = tester.getSemantics(
        find.byKey(const ValueKey('source-buffer-semantics')),
      );
      expect(
        composingNode.getSemanticsData().hint,
        contains('composition active'),
      );
      expect(find.byKey(const ValueKey('source-input-status')), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      final canceledNode = tester.getSemantics(
        find.byKey(const ValueKey('source-buffer-semantics')),
      );
      expect(
        canceledNode.getSemanticsData().hint,
        contains('composition idle'),
      );
      semantics.dispose();
    });
  });
}

EditorSessionController _controller(String text) {
  return EditorSessionController(
    initialDocument: DocumentState(
      documentId: 'accessibility-input.styio',
      text: text,
      revision: 0,
    ),
    languageService: const LocalStyioLanguageService(),
  );
}

Widget _harness(EditorSessionController controller) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(
        width: 1200,
        height: 800,
        child: EditorSurface(
          controller: controller,
          viewportProfile: const ViewportProfile(
            family: ViewportFamily.desktop,
            width: 1200,
            height: 800,
          ),
        ),
      ),
    ),
  );
}

Future<void> _focusSource(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('source-buffer-surface')));
  await tester.pump();
  await tester.pump();
}

TextEditingValue _remoteEditingValue(WidgetTester tester) {
  final state = tester.testTextInput.editingState;
  expect(state, isNotNull);
  return TextEditingValue(
    text: state!['text'] as String,
    selection: TextSelection(
      baseOffset: state['selectionBase'] as int,
      extentOffset: state['selectionExtent'] as int,
    ),
    composing: TextRange(
      start: state['composingBase'] as int,
      end: state['composingExtent'] as int,
    ),
  );
}

TextEditingValue _replaceRemoteSelection(
  TextEditingValue current,
  String replacement, {
  required bool composing,
}) {
  final start = current.selection.start;
  final end = current.selection.end;
  final nextText = current.text.replaceRange(start, end, replacement);
  final nextOffset = start + replacement.length;
  return TextEditingValue(
    text: nextText,
    selection: TextSelection.collapsed(offset: nextOffset),
    composing: composing
        ? TextRange(start: start, end: nextOffset)
        : TextRange.empty,
  );
}
