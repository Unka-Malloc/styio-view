import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';

void main() {
  test('editor render plan round trips active layers', () {
    const plan = EditorRenderPlan(
      activeLayers: <EditorRenderLayer>{
        EditorRenderLayer.text,
        EditorRenderLayer.overlay,
      },
      glyphSubstitutionEnabled: false,
    );
    final restored = EditorRenderPlan.fromJson(plan.toJson());

    expect(restored.activeLayers, <EditorRenderLayer>{
      EditorRenderLayer.text,
      EditorRenderLayer.overlay,
    });
    expect(restored.glyphSubstitutionEnabled, isFalse);
    expect(restored.toJson()['activeLayers'], <String>['text', 'overlay']);
  });

  test('editor semantic theme maps semantic and diagnostic colors', () {
    final theme = EditorSemanticTheme.foundation();
    final restored = EditorSemanticTheme.fromJson(theme.toJson());

    expect(restored.themeId, 'vityo.foundation.semantic');
    expect(restored.colorForSemanticKind(SemanticKind.function), 0xFFAA4D7D);
    expect(restored.colorForSemanticKind(SemanticKind.typeName), 0xFF4D6D2A);
    expect(
      restored.underlineColorForSeverity(DiagnosticSeverity.error),
      0xFFCB4D45,
    );
  });

  test('editor render snapshot captures controller presentation facts', () {
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'main.styio',
        text: 'value := 1\n',
        revision: 2,
      ),
      languageService: const LocalStyioLanguageService(),
    );
    addTearDown(controller.dispose);
    controller.selectRange(baseOffset: 0, extentOffset: 5);

    final snapshot = EditorRenderSnapshot.fromController(controller);
    final restored = EditorRenderSnapshot.fromJson(snapshot.toJson());

    expect(snapshot.documentId, 'main.styio');
    expect(snapshot.revision, 2);
    expect(snapshot.lineCount, 2);
    expect(snapshot.hasSelection, isTrue);
    expect(snapshot.renderPlan.activeLayers, contains(EditorRenderLayer.text));
    expect(snapshot.tokenCount, greaterThanOrEqualTo(1));
    expect(snapshot.virtualizedRowWindow.containsLine(0), isTrue);
    expect(restored.virtualizedRowWindow.totalLineCount, 2);
    expect(restored.selectionStart, 0);
    expect(restored.selectionEnd, 5);
    expect(
      restored.toJson()['virtualizedRowWindow'],
      isA<Map<String, Object?>>(),
    );
    expect(restored.toJson()['hasCodeActionWidget'], isFalse);
    expect(restored.toJson()['todo'], contains('concrete scroll controller'));
  });

  test('editor render snapshot exposes code action widget availability', () {
    const snapshot = EditorRenderSnapshot(
      documentId: 'main.styio',
      revision: 1,
      lineCount: 1,
      characterCount: 10,
      selectionStart: 0,
      selectionEnd: 0,
      renderPlan: EditorRenderPlan(
        activeLayers: <EditorRenderLayer>{EditorRenderLayer.text},
      ),
      tokenCount: 1,
      semanticCount: 1,
      diagnosticCount: 1,
      virtualizedRowWindow: EditorVirtualizedRowWindow(
        totalLineCount: 1,
        startLine: 0,
        endLineExclusive: 1,
        viewportFirstLine: 0,
        viewportLineCapacity: 1,
        overscanLineCount: 0,
      ),
      contextActionCount: 2,
    );

    expect(snapshot.hasCodeActionWidget, isTrue);
    expect(snapshot.toJson()['hasCodeActionWidget'], isTrue);
  });

  test('editor render snapshot exposes lightbulb action state', () {
    const text = 'let stream\n';
    final controller = EditorSessionController(
      initialDocument: const DocumentState(
        documentId: 'sample.styio',
        text: text,
        revision: 0,
      ),
      languageService: const SimpleStyioLanguageService(),
      initialSelection: SelectionState.collapsed(text.indexOf('stream') + 2),
    );
    addTearDown(controller.dispose);

    final snapshot = EditorRenderSnapshot.fromController(controller);
    final restored = EditorRenderSnapshot.fromJson(snapshot.toJson());

    expect(snapshot.codeActionWidget.visible, isTrue);
    expect(snapshot.codeActionWidget.actionCount, greaterThanOrEqualTo(1));
    expect(snapshot.codeActionWidget.serviceFactCount, greaterThanOrEqualTo(1));
    expect(snapshot.codeActionWidget.primaryLabel, isNotEmpty);
    expect(restored.codeActionWidget.visible, isTrue);
    expect(restored.codeActionWidget.primaryLabel, isNotEmpty);
    expect(
      (restored.toJson()['codeActionWidget']! as Map<String, Object?>)['todo'],
      contains('lightbulb popup'),
    );
  });

  test('editor virtualized row window includes overscan around viewport', () {
    final window = EditorVirtualizedRowWindow.fromViewport(
      totalLineCount: 200,
      firstVisibleLine: 50,
      viewportLineCapacity: 20,
      overscanLineCount: 5,
    );
    final restored = EditorVirtualizedRowWindow.fromJson(window.toJson());

    expect(window.startLine, 45);
    expect(window.endLineExclusive, 75);
    expect(window.renderLineCount, 30);
    expect(window.containsLine(44), isFalse);
    expect(window.containsLine(74), isTrue);
    expect(window.coversFullDocument, isFalse);
    expect(restored.viewportFirstLine, 50);
  });
}
