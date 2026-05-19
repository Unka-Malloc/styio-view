import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets('editor surface truncates large source preview', (tester) async {
    final text = List<String>.generate(
      450,
      (index) => 'value_$index := $index',
    ).join('\n');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 20000,
            child: EditorSurface(
              controller: EditorSessionController(
                initialDocument: DocumentState(
                  documentId: 'large.styio',
                  text: text,
                  revision: 1,
                ),
                languageService: const LocalStyioLanguageService(),
              ),
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1400,
                height: 20000,
              ),
            ),
          ),
        ),
      ),
    );

    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey('source-large-document-truncation-banner'),
        skipOffstage: false,
      ),
      800,
      scrollable: _sourceScrollable(),
      maxScrolls: 500,
    );
    expect(
      find.byKey(
        const ValueKey('source-large-document-truncation-banner'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('source-line-49')), findsNothing);
    expect(
      find.byKey(const ValueKey('source-line-449'), skipOffstage: false),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey('source-large-document-truncation-banner'),
        skipOffstage: false,
      ),
      800,
      scrollable: _sourceScrollable(),
      maxScrolls: 500,
    );
    expect(
      find.byKey(
        const ValueKey('source-large-document-truncation-banner'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
    expect(
      find.textContaining(
        'Current caret line 450 is outside',
        skipOffstage: false,
      ),
      findsNothing,
    );
  });

  testWidgets('editor surface large preview follows caret navigation', (
    tester,
  ) async {
    final text = List<String>.generate(
      450,
      (index) => 'value_$index := $index',
    ).join('\n');
    final controller = EditorSessionController(
      initialDocument: DocumentState(
        documentId: 'large.styio',
        text: text,
        revision: 1,
      ),
      languageService: const LocalStyioLanguageService(),
    )..selectLineColumn(line: 0, column: 0);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1400,
            height: 20000,
            child: EditorSurface(
              controller: controller,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1400,
                height: 20000,
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('source-line-0'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('source-line-449')), findsNothing);

    controller.selectLineColumn(line: 449, column: 0);
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-line-449'), skipOffstage: false),
      800,
      scrollable: _sourceScrollable(),
      maxScrolls: 500,
    );
    expect(find.byKey(const ValueKey('source-line-0')), findsNothing);
    expect(
      find.byKey(const ValueKey('source-line-449'), skipOffstage: false),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.byKey(
        const ValueKey('source-large-document-truncation-banner'),
        skipOffstage: false,
      ),
      800,
      scrollable: _sourceScrollable(),
      maxScrolls: 500,
    );
    expect(
      find.byKey(
        const ValueKey('source-large-document-truncation-banner'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });
}

Finder _sourceScrollable() {
  return find.descendant(
    of: find.byKey(const ValueKey('source-buffer-surface')),
    matching: find.byType(Scrollable),
  );
}
