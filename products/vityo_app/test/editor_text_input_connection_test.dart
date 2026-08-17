import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/editor.dart' hide TextRange;
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  group('EditorTextInputClient transport', () {
    testWidgets('CJK composition stays provisional until platform commit', (
      tester,
    ) async {
      final controller = _controller('ab');
      addTearDown(controller.dispose);
      controller.selectCollapsed(0);
      await tester.pumpWidget(_harness(controller));
      await _focusSource(tester);

      final composing = _replaceRemoteSelection(
        _remoteEditingValue(tester),
        '語',
        composing: true,
      );
      tester.testTextInput.updateEditingValue(composing);
      await tester.pump();

      expect(controller.document.text, 'ab');
      expect(controller.document.revision, 0);
      expect(find.byKey(const ValueKey('source-composition-range')), findsOneWidget);

      tester.testTextInput.updateEditingValue(
        composing.copyWith(composing: TextRange.empty),
      );
      await tester.pump();

      expect(controller.document.text, '語ab');
      expect(controller.document.revision, 1);
    });

    testWidgets('dead-key style direct commit bypasses provisional state', (
      tester,
    ) async {
      final controller = _controller('a');
      addTearDown(controller.dispose);
      controller.selectCollapsed(0);
      await tester.pumpWidget(_harness(controller));
      await _focusSource(tester);

      final committed = _replaceRemoteSelection(
        _remoteEditingValue(tester),
        'é',
        composing: false,
      );
      tester.testTextInput.updateEditingValue(committed);
      await tester.pump();

      expect(controller.document.text, 'éa');
      expect(
        find.byKey(const ValueKey('source-composition-range')),
        findsNothing,
      );
    });

    testWidgets('escape cancels composition without source mutation', (
      tester,
    ) async {
      final controller = _controller('keep');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_harness(controller));
      await _focusSource(tester);

      tester.testTextInput.updateEditingValue(
        _replaceRemoteSelection(
          _remoteEditingValue(tester),
          '候補',
          composing: true,
        ),
      );
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(controller.document.text, 'keep');
      expect(controller.historyController.undoDepth, 0);
      expect(
        find.byKey(const ValueKey('source-composition-range')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('source-input-status')), findsOneWidget);
    });

    testWidgets('connection close commits once and reconnect uses new generation', (
      tester,
    ) async {
      final controller = _controller('seed');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_harness(controller));
      await _focusSource(tester);
      final closedClientId = _lastTextInputClientId(tester);

      tester.testTextInput.updateEditingValue(
        _replaceRemoteSelection(
          _remoteEditingValue(tester),
          'é',
          composing: true,
        ),
      );
      await tester.pump();
      tester.testTextInput.closeConnection();
      await tester.pump();

      expect(controller.document.text, 'seedé');
      expect(tester.testTextInput.hasAnyClients, isFalse);

      await _focusSource(tester);
      expect(tester.testTextInput.hasAnyClients, isTrue);
      expect(_lastTextInputClientId(tester), isNot(closedClientId));

      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            SystemChannels.textInput.name,
            SystemChannels.textInput.codec.encodeMethodCall(
              MethodCall('TextInputClient.updateEditingState', <Object?>[
                closedClientId,
                _remoteEditingValue(tester).toJSON(),
              ]),
            ),
            (_) {},
          );
      await tester.pump();
      expect(controller.document.text, 'seedé');
      expect(controller.historyController.undoDepth, 1);
    });

    testWidgets('stale revision and selection changes reject replay', (
      tester,
    ) async {
      final controller = _controller('line');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_harness(controller));
      await _focusSource(tester);

      tester.testTextInput.updateEditingValue(
        _replaceRemoteSelection(
          _remoteEditingValue(tester),
          '仮',
          composing: true,
        ),
      );
      await tester.pump();

      controller.insertText('!');
      await tester.pump();

      expect(controller.document.text, 'line!');
      expect(
        find.byKey(const ValueKey('source-composition-range')),
        findsNothing,
      );
    });

    testWidgets('printable KeyEvent does not mutate committed source', (
      tester,
    ) async {
      final controller = _controller('fixed');
      addTearDown(controller.dispose);
      await tester.pumpWidget(_harness(controller));
      await _focusSource(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.keyZ, character: 'z');
      await tester.pump();

      expect(controller.document.text, 'fixed');
      expect(controller.historyController.undoDepth, 0);
    });

    testWidgets('backspace deletes one emoji grapheme through text-input seam', (
      tester,
    ) async {
      const emoji = '👨‍👩‍👧‍👦';
      final controller = _controller('x${emoji}y');
      addTearDown(controller.dispose);
      controller.selectCollapsed(1 + emoji.length);
      await tester.pumpWidget(_harness(controller));
      await _focusSource(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();

      expect(controller.document.text, 'xy');
      expect(controller.selectionSet.primarySelection.extentOffset, 1);
      expect(controller.historyController.undoDepth, 1);
    });

    testWidgets('multi-cursor backspace and enter share one undo intent', (
      tester,
    ) async {
      final controller = _controller('ab\ncd');
      addTearDown(controller.dispose);
      controller.selectionController.selectSelectionSet(
        EditorSelectionSet.normalized(
          selections: const [
            SelectionState.collapsed(1),
            SelectionState.collapsed(4),
          ],
          primaryIndex: 0,
          documentLength: controller.document.length,
        ),
      );
      await tester.pumpWidget(_harness(controller));
      await _focusSource(tester);

      await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
      await tester.pump();
      expect(controller.document.text, 'b\nd');
      expect(controller.selectionSet.selections, hasLength(2));
      expect(controller.historyController.undoDepth, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(controller.document.text, '\nb\n\nd');
      expect(controller.selectionSet.selections, hasLength(2));
      expect(controller.historyController.undoDepth, 2);

      controller.undo();
      await tester.pump();
      expect(controller.document.text, 'b\nd');
      expect(controller.selectionSet.selections, hasLength(2));
    });
  });
}

EditorSessionController _controller(String text) {
  return EditorSessionController(
    initialDocument: DocumentState(
      documentId: 'text-input.styio',
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

int _lastTextInputClientId(WidgetTester tester) {
  final call = tester.testTextInput.log.lastWhere(
    (entry) => entry.method == 'TextInput.setClient',
  );
  return (call.arguments as List<Object?>).first! as int;
}
