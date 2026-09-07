import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/editor.dart' hide TextRange;
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  group('REQ-INPUT-003 rendered editor input acceptance', () {
    testWidgets(
      'real text input keeps composition provisional and commits every cursor once',
      (tester) async {
        const source = 'A B';
        final controller = _controller(source);
        addTearDown(controller.dispose);
        controller.selectSelections(const <SelectionState>[
          SelectionState.collapsed(0),
          SelectionState.collapsed(3),
        ], primaryIndex: 1);

        await tester.pumpWidget(_harness(controller));
        await _focusSource(tester);

        expect(tester.testTextInput.hasAnyClients, isTrue);
        expect(tester.testTextInput.isVisible, isTrue);
        expect(
          tester.testTextInput.setClientArgs?['inputType']?['name'],
          'TextInputType.multiline',
        );

        final composing = _replaceRemoteSelection(
          _remoteEditingValue(tester),
          '日本',
          composing: true,
        );
        tester.testTextInput.updateEditingValue(composing);
        await tester.pump();

        expect(controller.document.text, source);
        expect(controller.document.revision, 0);
        expect(controller.historyController.undoDepth, 0);
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
          composing.copyWith(composing: TextRange.empty),
        );
        await tester.pump();

        expect(controller.document.text, '日本A B日本');
        expect(controller.document.revision, 1);
        expect(controller.historyController.undoDepth, 1);
        expect(
          find.byKey(const ValueKey('source-composition-range')),
          findsNothing,
        );

        controller.undo();
        await tester.pump();
        expect(controller.document.text, source);
        expect(controller.document.revision, 0);
        expect(controller.selectionSet.selections, hasLength(2));

        // Printable KeyEvent characters are no longer an insertion path.
        await tester.sendKeyEvent(LogicalKeyboardKey.keyX, character: 'x');
        await tester.pump();
        expect(controller.document.text, source);
        expect(controller.historyController.undoDepth, 0);

        final committedX = _replaceRemoteSelection(
          _remoteEditingValue(tester),
          'x',
          composing: false,
        );
        tester.testTextInput.updateEditingValue(committedX);
        await tester.pump();
        expect(controller.document.text, 'xA Bx');
        expect(controller.document.revision, 1);
        expect(controller.historyController.undoDepth, 1);
      },
    );

    testWidgets('cancel, connection close, and reconnect have one outcome', (
      tester,
    ) async {
      final controller = _controller('seed');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_harness(controller));
      await _focusSource(tester);
      final closedClientId = _lastTextInputClientId(tester);

      final canceledValue = _replaceRemoteSelection(
        _remoteEditingValue(tester),
        '候補',
        composing: true,
      );
      tester.testTextInput.updateEditingValue(canceledValue);
      await tester.pump();
      expect(controller.document.text, 'seed');

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(controller.document.text, 'seed');
      expect(controller.historyController.undoDepth, 0);
      expect(
        find.byKey(const ValueKey('source-composition-range')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('source-input-status')), findsOneWidget);

      final focusLossValue = _replaceRemoteSelection(
        _remoteEditingValue(tester),
        'é',
        composing: true,
      );
      tester.testTextInput.updateEditingValue(focusLossValue);
      await tester.pump();
      tester.testTextInput.closeConnection();
      await tester.pump();

      expect(controller.document.text, 'seedé');
      expect(controller.document.revision, 1);
      expect(controller.historyController.undoDepth, 1);
      expect(tester.testTextInput.hasAnyClients, isFalse);

      await _focusSource(tester);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(_remoteEditingValue(tester).text, contains('seedé'));
      expect(_lastTextInputClientId(tester), isNot(closedClientId));

      // A callback from the superseded connection cannot replay the commit.
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            SystemChannels.textInput.name,
            SystemChannels.textInput.codec.encodeMethodCall(
              MethodCall('TextInputClient.updateEditingState', <Object?>[
                closedClientId,
                focusLossValue.toJSON(),
              ]),
            ),
            (_) {},
          );
      await tester.pump();
      expect(controller.document.text, 'seedé');
      expect(controller.historyController.undoDepth, 1);
    });

    testWidgets('the focused source surface exposes editable semantics', (
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
  });
}

EditorSessionController _controller(String text) {
  return EditorSessionController(
    initialDocument: DocumentState(
      documentId: 'rendered-input.styio',
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
  expect(state, isNotNull, reason: 'the editor must publish editing state');
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

int _lastTextInputClientId(WidgetTester tester) {
  final call = tester.testTextInput.log.lastWhere(
    (entry) => entry.method == 'TextInput.setClient',
  );
  return (call.arguments as List<Object?>).first! as int;
}
