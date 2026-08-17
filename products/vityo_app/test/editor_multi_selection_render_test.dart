import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/editor.dart' hide TextRange;
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  group('rendered multi-selection and composition overlays', () {
    testWidgets('composition overlay and selection markers stay aligned', (
      tester,
    ) async {
      const source = 'A B';
      final controller = _controller(source);
      addTearDown(controller.dispose);
      controller.selectSelections(const <SelectionState>[
        SelectionState.collapsed(0),
        SelectionState.collapsed(3),
      ], primaryIndex: 1);

      await tester.pumpWidget(_harness(controller));
      await _focusSource(tester);

      expect(controller.selectionSet.selections, hasLength(2));
      expect(controller.selectionSet.primaryIndex, 1);

      tester.testTextInput.updateEditingValue(
        _replaceRemoteSelection(
          _remoteEditingValue(tester),
          '日本',
          composing: true,
        ),
      );
      await tester.pump();

      expect(controller.document.text, source);
      expect(
        find.byKey(const ValueKey('source-composition-range')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('source-selection-item-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('source-selection-item-1')),
        findsOneWidget,
      );

      tester.testTextInput.updateEditingValue(
        _replaceRemoteSelection(
          _remoteEditingValue(tester),
          '日本',
          composing: false,
        ).copyWith(composing: TextRange.empty),
      );
      await tester.pump();

      expect(controller.document.text, '日本A B日本');
      expect(
        find.byKey(const ValueKey('source-composition-range')),
        findsNothing,
      );
      expect(controller.selectionSet.selections, hasLength(2));
      expect(controller.selectionSet.primaryIndex, 1);
    });

    testWidgets('selection set updates preserve primary identity', (
      tester,
    ) async {
      final controller = _controller('one\ntwo\nthree');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_harness(controller));
      await _focusSource(tester);

      controller.selectSelections(const <SelectionState>[
        SelectionState.collapsed(0),
        SelectionState.collapsed(4),
      ], primaryIndex: 0);
      await tester.pump();

      expect(controller.selectionSet.primaryIndex, 0);
      expect(controller.selectionSet.selections, hasLength(2));

      controller.selectSelections(const <SelectionState>[
        SelectionState.collapsed(4),
      ], primaryIndex: 0);
      await tester.pump();

      expect(controller.selectionSet.selections, hasLength(1));
      expect(controller.selectionSet.primaryIndex, 0);
    });
  });
}

EditorSessionController _controller(String text) {
  return EditorSessionController(
    initialDocument: DocumentState(
      documentId: 'multi-selection-render.styio',
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
