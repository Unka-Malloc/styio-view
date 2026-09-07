import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/editor.dart' hide TextRange;
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets(
    'family emoji multi-selection and composition paint without UTF-16 faults',
    (tester) async {
      const text = 'ab 👨‍👩‍👧 cd';
      final controller = EditorSessionController(
        initialDocument: const DocumentState(
          documentId: 'emoji-render.styio',
          text: text,
          revision: 0,
        ),
        languageService: const LocalStyioLanguageService(),
      );
      addTearDown(controller.dispose);

      final emojiStart = text.indexOf('👨');
      final emojiEnd = emojiStart + '👨‍👩‍👧'.length;
      controller.selectSelections([
        const SelectionState.collapsed(0),
        SelectionState(baseOffset: emojiEnd, extentOffset: emojiStart),
        const SelectionState.collapsed(text.length),
      ], primaryIndex: 1);

      await tester.pumpWidget(
        MaterialApp(
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
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.byKey(const ValueKey('source-buffer-surface')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(tester.testTextInput.hasAnyClients, isTrue);

      controller.selectSelections(const [
        SelectionState.collapsed(0),
        SelectionState.collapsed(3),
      ], primaryIndex: 0);
      await tester.pump();

      final state = tester.testTextInput.editingState!;
      final current = TextEditingValue(
        text: state['text'] as String,
        selection: TextSelection(
          baseOffset: state['selectionBase'] as int,
          extentOffset: state['selectionExtent'] as int,
        ),
      );
      final start = current.selection.start;
      final end = current.selection.end;
      final next = current.text.replaceRange(start, end, '日');
      final offset = start + 1;
      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: offset),
          composing: TextRange(start: start, end: offset),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.document.revision, 0);
      expect(
        find.byKey(const ValueKey('source-composition-range')),
        findsOneWidget,
      );

      tester.testTextInput.updateEditingValue(
        TextEditingValue(
          text: next,
          selection: TextSelection.collapsed(offset: offset),
          composing: TextRange.empty,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(controller.document.revision, 1);
      expect(controller.document.text.contains('👨‍👩‍👧'), isTrue);
    },
  );
}
