import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/service/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets('editor surface renders external file conflict recovery', (
    tester,
  ) async {
    var acceptedExternalChange = false;
    const localDocument = DocumentState(
      documentId: 'fixture://file-conflict',
      text: 'value := 1\n',
      revision: 1,
    );
    const externalDocument = DocumentState(
      documentId: 'fixture://file-conflict',
      text: 'value := 2\n',
      revision: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1200,
            height: 800,
            child: EditorSurface(
              controller: EditorSessionController(
                initialDocument: localDocument,
                languageService: const LocalStyioLanguageService(),
              ),
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1200,
                height: 800,
              ),
              fileBindingSnapshot: const DocumentResourceBindingSnapshot(
                state: DocumentResourceBindingState.conflicted,
                resourceId: 'fixture://file-conflict',
                document: localDocument,
                externalDocument: externalDocument,
                failureKind: DocumentResourceBindingFailureKind.conflict,
                failureMessage: 'External changes conflict with local edits.',
              ),
              onAcceptExternalChange: () {
                acceptedExternalChange = true;
              },
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('editor-file-binding-status-banner')),
      findsOneWidget,
    );
    expect(find.text('External file conflict'), findsOneWidget);
    expect(find.text('Use external version'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('editor-file-binding-accept-external')),
    );

    expect(acceptedExternalChange, isTrue);
  });

  testWidgets('editor surface renders readonly and provider unavailable states', (
    tester,
  ) async {
    const document = DocumentState(
      documentId: 'fixture://readonly',
      text: 'value := 1\n',
      revision: 1,
    );

    Future<void> pumpStatus(DocumentResourceBindingSnapshot snapshot) {
      return tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 1200,
              height: 800,
              child: EditorSurface(
                controller: EditorSessionController(
                  initialDocument: document,
                  languageService: const LocalStyioLanguageService(),
                ),
                viewportProfile: const ViewportProfile(
                  family: ViewportFamily.desktop,
                  width: 1200,
                  height: 800,
                ),
                fileBindingSnapshot: snapshot,
                onAcceptExternalChange: () {},
              ),
            ),
          ),
        ),
      );
    }

    await pumpStatus(
      const DocumentResourceBindingSnapshot(
        state: DocumentResourceBindingState.readonly,
        resourceId: 'fixture://readonly',
        document: document,
        failureKind: DocumentResourceBindingFailureKind.readonly,
        failureMessage: 'The backing resource is read-only.',
      ),
    );

    expect(find.text('Backing file is read-only'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('editor-file-binding-accept-external')),
          )
          .onPressed,
      isNull,
    );

    await pumpStatus(
      const DocumentResourceBindingSnapshot(
        state: DocumentResourceBindingState.providerUnavailable,
        resourceId: 'fixture://readonly',
        document: document,
        failureKind: DocumentResourceBindingFailureKind.providerUnavailable,
        failureMessage: 'The current file provider is unavailable.',
      ),
    );

    expect(find.text('File provider unavailable'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('editor-file-binding-accept-external')),
          )
          .onPressed,
      isNull,
    );
  });

  testWidgets('editor surface renders fixed mobile language layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const document = DocumentState(
      documentId: 'fixture://mobile-layout',
      text: 'value := 1\n',
      revision: 1,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 430,
            height: 932,
            child: EditorSurface(
              controller: EditorSessionController(
                initialDocument: document,
                languageService: const LocalStyioLanguageService(),
              ),
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.mobile,
                width: 430,
                height: 932,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('editor-language-family-mobile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-language-layout-mobile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-language-layout-scroll-mobile')),
      findsNothing,
    );
  });

  testWidgets('editor surface dispatches core keyboard editing commands', (
    tester,
  ) async {
    const document = DocumentState(
      documentId: 'fixture://keyboard',
      text: 'value = 1\nnext = value\n',
      revision: 1,
    );
    final controller = EditorSessionController(
      initialDocument: document,
      languageService: const LocalStyioLanguageService(),
    );
    controller.selectCollapsed(document.text.indexOf('value'));

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

    await _focusSourceBuffer(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    expect(controller.selection.start, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    expect(controller.selection.start, document.text.indexOf('\n'));

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    expect(controller.selection.start, 0);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(controller.document.text.startsWith('\nvalue'), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
  });

  testWidgets('editor surface opens keyboard-driven assistance panels', (
    tester,
  ) async {
    const text = '''
price = 1.0
tax = 0.5
fn blend(left: f64, right: f64): f64 {
  emit left + right
}
value = blend(pri)
loose
''';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'fixture://assistance-panels',
        text: text,
        revision: 1,
      ),
      languageService: const SimpleStyioLanguageService(),
    );

    Future<void> sendShortcut(
      LogicalKeyboardKey key, {
      bool meta = true,
      bool alt = false,
      bool shift = false,
    }) async {
      if (meta) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
      }
      if (alt) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
      }
      if (shift) {
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      }
      await tester.sendKeyEvent(key);
      if (shift) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      }
      if (alt) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
      }
      if (meta) {
        await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
      }
      await tester.pump();
    }

    Future<void> closePanel() async {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
    }

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
    await _focusSourceBuffer(tester);

    controller.selectCollapsed(text.indexOf('pri)') + 3);
    await tester.pump();
    await sendShortcut(LogicalKeyboardKey.space);
    expect(
      find.byKey(const ValueKey('source-completion-lookup')),
      findsOneWidget,
    );
    await closePanel();

    controller.selectCollapsed(text.lastIndexOf('blend(') + 'blend('.length);
    await tester.pump();
    await sendShortcut(LogicalKeyboardKey.keyP);
    expect(
      find.byKey(const ValueKey('source-parameter-info-panel')),
      findsOneWidget,
    );
    await closePanel();

    controller.selectRange(
      baseOffset: text.indexOf('price = 1.0'),
      extentOffset: text.indexOf('price = 1.0') + 'price = 1.0'.length,
    );
    await tester.pump();
    await sendShortcut(LogicalKeyboardKey.keyT, alt: true);
    expect(
      find.byKey(const ValueKey('source-surround-lookup')),
      findsOneWidget,
    );
    await closePanel();

    controller.selectCollapsed(text.indexOf('price'));
    await tester.pump();
    await sendShortcut(LogicalKeyboardKey.keyQ);
    expect(find.byKey(const ValueKey('source-quick-doc-panel')), findsOneWidget);
    await closePanel();

    await sendShortcut(LogicalKeyboardKey.keyN, alt: true, shift: true);
    expect(find.byKey(const ValueKey('source-symbol-lookup')), findsOneWidget);
    await closePanel();

    controller.selectCollapsed(text.indexOf('loose'));
    await tester.pump();
    await sendShortcut(LogicalKeyboardKey.enter, meta: false, alt: true);
    expect(
      find.byKey(const ValueKey('source-quick-fix-lookup')),
      findsOneWidget,
    );
  });

  testWidgets('editor surface cycles mobile language inspector sections', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const text = '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}

price = 1.0
tax = 0.5
value = blend(price, tax)
''';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'fixture://mobile-inspector',
        text: text,
        revision: 1,
      ),
      languageService: const LocalStyioLanguageService(),
    );
    controller.selectCollapsed(text.indexOf('price, tax') + 2);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 430,
            height: 932,
            child: EditorSurface(
              controller: controller,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.mobile,
                width: 430,
                height: 932,
              ),
            ),
          ),
        ),
      ),
    );

    final mobilePane = find.byKey(
      const ValueKey('language-pane-mobile'),
      skipOffstage: false,
    );
    expect(mobilePane, findsOneWidget);
    final tabScrollable = find
        .descendant(
          of: mobilePane,
          matching: find.byType(Scrollable, skipOffstage: false),
          skipOffstage: false,
        )
        .first;

    for (final section in const <String, String>{
      'Blocks': 'blocks',
      'Inlays': 'inlays',
      'Symbols': 'symbols',
      'Resolve': 'resolve',
      'Token': 'token',
      'Hover': 'hover',
      'Complete': 'completions',
      'Format': 'formatting',
    }.entries) {
      final tabLabel = find.descendant(
        of: tabScrollable,
        matching: find.text(section.key, skipOffstage: false),
        skipOffstage: false,
      );
      final tab = find.ancestor(
        of: tabLabel.first,
        matching: find.byType(InkWell, skipOffstage: false),
      );
      expect(tab, findsOneWidget);
      tester.widget<InkWell>(tab).onTap!();
      await tester.pump();

      expect(
        find.byKey(
          ValueKey('language-mobile-section-${section.value}'),
          skipOffstage: false,
        ),
        findsOneWidget,
      );
    }
  });
}

Future<void> _focusSourceBuffer(WidgetTester tester) async {
  final sourceSurface = find.byKey(const ValueKey('source-buffer-surface'));
  final sourceFocus = find.ancestor(
    of: sourceSurface,
    matching: find.byType(Focus),
  );
  if (sourceFocus.evaluate().isNotEmpty) {
    tester.widget<Focus>(sourceFocus.first).focusNode?.requestFocus();
  } else {
    await tester.tap(sourceSurface);
  }
  await tester.pump();
}
