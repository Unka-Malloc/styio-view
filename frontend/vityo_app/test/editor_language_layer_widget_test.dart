import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets('semantic spans overlay token spans without replacing them', (
    tester,
  ) async {
    const text = '#main := () => {\n  value := 1\n}\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'semantic-overlay.styio',
        text: text,
        revision: 0,
      ),
      languageService: const LocalStyioLanguageService(),
    );

    await tester.pumpWidget(_editorHarness(controller));

    expect(controller.analysis.tokenSpans.map((token) => token.lexeme), contains('#'));
    expect(controller.analysis.tokenSpans.map((token) => token.lexeme), contains('main'));
    expect(controller.analysis.semanticSpans, isNotEmpty);
    expect(
      _stylesForText(tester, lineIndex: 0, text: '#').single.color,
      const Color(0xFF255A96),
    );
    expect(
      _stylesForText(tester, lineIndex: 0, text: 'main').single.color,
      const Color(0xFFAA4D7D),
    );
    expect(
      _stylesForText(tester, lineIndex: 0, text: 'main').single.fontWeight,
      FontWeight.w700,
    );
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

List<TextStyle> _stylesForText(
  WidgetTester tester, {
  required int lineIndex,
  required String text,
}) {
  final styles = <TextStyle>[];

  void visit(InlineSpan span) {
    if (span is TextSpan) {
      if (span.text == text && span.style != null) {
        styles.add(span.style!);
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
  return styles;
}
