import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets('operator glyph substitution is display-only and toggleable', (
    tester,
  ) async {
    const text = 'value |> transform\nvalue -> @stdout\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'glyph.styio',
        text: text,
        revision: 0,
      ),
      languageService: const LocalStyioLanguageService(),
    );

    await tester.pumpWidget(_editorHarness(controller));

    expect(controller.document.text, text);
    expect(controller.searchDocument('|>').single.range.start, text.indexOf('|>'));
    expect(controller.searchDocument('->').single.range.start, text.indexOf('->'));
    expect(_glyphIcons(tester), contains(Icons.play_arrow_rounded));
    expect(_glyphIcons(tester), contains(Icons.arrow_right_alt_rounded));

    await tester.tap(
      find.byKey(const ValueKey('editor-glyph-substitution-toggle')),
    );
    await tester.pump();

    expect(controller.document.text, text);
    expect(controller.glyphSubstitutionEnabled, isFalse);
    expect(_glyphIcons(tester), isNot(contains(Icons.play_arrow_rounded)));
    expect(_glyphIcons(tester), isNot(contains(Icons.arrow_right_alt_rounded)));
    expect(_spanTextsOnLine(tester, lineIndex: 0).join(), contains('|>'));
    expect(_spanTextsOnLine(tester, lineIndex: 1).join(), contains('->'));
  });

  testWidgets('selected operator remains literal source text while enabled', (
    tester,
  ) async {
    const text = 'value |> transform\nvalue -> @stdout\n';
    final arrowStart = text.indexOf('->');
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'selected-glyph.styio',
        text: text,
        revision: 0,
      ),
      languageService: const LocalStyioLanguageService(),
      initialSelection: SelectionState(
        baseOffset: arrowStart,
        extentOffset: arrowStart + 2,
      ),
    );

    await tester.pumpWidget(_editorHarness(controller));

    expect(controller.selectedSourceText, '->');
    expect(_glyphIcons(tester), contains(Icons.play_arrow_rounded));
    expect(_glyphIcons(tester), isNot(contains(Icons.arrow_right_alt_rounded)));
    expect(_spanTextsOnLine(tester, lineIndex: 1).join(), contains('->'));
  });
}

Widget _editorHarness(EditorSessionController controller) {
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

List<String> _spanTextsOnLine(WidgetTester tester, {required int lineIndex}) {
  final texts = <String>[];

  void visit(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text != null) {
        texts.add(span.text!);
      }
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child);
      }
    }
  }

  final richTexts = tester.widgetList<RichText>(
    find.descendant(
      of: find.byKey(ValueKey('source-line-$lineIndex'), skipOffstage: false),
      matching: find.byType(RichText, skipOffstage: false),
      skipOffstage: false,
    ),
  );
  for (final richText in richTexts) {
    visit(richText.text);
  }
  return texts;
}

List<IconData> _glyphIcons(WidgetTester tester) {
  final icons = <IconData>[];

  void visit(InlineSpan span) {
    if (span is WidgetSpan && span.child is DecoratedBox) {
      final decorated = span.child as DecoratedBox;
      final padding = decorated.child;
      if (padding is Padding && padding.child is Icon) {
        final icon = padding.child as Icon;
        if (icon.icon != null) {
          icons.add(icon.icon!);
        }
      }
    }
    if (span is TextSpan) {
      for (final child in span.children ?? const <InlineSpan>[]) {
        visit(child);
      }
    }
  }

  for (final richText in tester.widgetList<RichText>(
    find.byType(RichText, skipOffstage: false),
  )) {
    visit(richText.text);
  }
  return icons;
}
