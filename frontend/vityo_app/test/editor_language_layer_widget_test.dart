import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  test('mergeCompletionItems keeps primary order and dedupes fallback', () {
    const localMain = CompletionItem(
      label: 'main',
      kind: CompletionItemKind.function,
      insertText: 'main',
    );
    const projectMain = CompletionItem(
      label: 'main',
      kind: CompletionItemKind.function,
      insertText: 'main',
      detail: 'project duplicate',
    );
    const projectBlend = CompletionItem(
      label: 'blend',
      kind: CompletionItemKind.function,
      insertText: 'blend',
    );

    final completions = mergeCompletionItems(
      const <CompletionItem>[localMain],
      const <CompletionItem>[projectMain, projectBlend],
    );

    expect(completions, <CompletionItem>[localMain, projectBlend]);
  });

  testWidgets('editor surface renders project hover and completion fallback', (
    tester,
  ) async {
    const text = 'value = blend()\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'project-context.styio',
        text: text,
        revision: 0,
      ),
      languageService: const LocalStyioLanguageService(),
    )..selectCollapsed(text.indexOf('blend') + 1);

    await tester.pumpWidget(
      _editorHarness(
        controller,
        projectHoverAtSelection: const HoverPayload(
          range: SourceRange(start: 8, end: 13),
          markdown: 'function blend',
        ),
        projectCompletionsAtSelection: const <CompletionItem>[
          CompletionItem(
            label: 'projectBlend',
            kind: CompletionItemKind.function,
            insertText: 'projectBlend',
          ),
        ],
      ),
    );

    expect(
      find.textContaining('function blend', skipOffstage: false),
      findsWidgets,
    );
    expect(
      find.textContaining('projectBlend', skipOffstage: false),
      findsWidgets,
    );
  });

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
      FontWeight.w600,
    );
  });
}

Widget _editorHarness(
  EditorSessionController controller, {
  HoverPayload? projectHoverAtSelection,
  List<CompletionItem> projectCompletionsAtSelection =
      const <CompletionItem>[],
}) {
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
          projectHoverAtSelection: projectHoverAtSelection,
          projectCompletionsAtSelection: projectCompletionsAtSelection,
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
