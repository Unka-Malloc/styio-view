import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_render/editor/editor.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets('editor surface renders and folds semantic function blocks', (
    tester,
  ) async {
    const text = '#main := () => {\n  value := 1\n}\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'semantic-block.styio',
        text: text,
        revision: 0,
      ),
      languageService: const LocalStyioLanguageService(),
    );

    await tester.pumpWidget(_editorHarness(controller));

    expect(controller.analysis.semanticBlocks.single.label, 'main');
    expect(
      find.byKey(const ValueKey('source-fold-toggle-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('source-line-0'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('source-line-2'), skipOffstage: false),
      findsOneWidget,
    );

    final toggle = tester.widget<IconButton>(
      find.byKey(const ValueKey('source-fold-toggle-0')),
    );
    expect(toggle.onPressed, isNotNull);
    toggle.onPressed!();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('source-fold-summary-0'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.text('2 folded lines'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('source-line-0'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('source-line-2')), findsNothing);
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
