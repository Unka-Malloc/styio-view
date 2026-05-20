import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';

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
    expect(restored.selectionStart, 0);
    expect(restored.selectionEnd, 5);
    expect(restored.toJson()['todo'], contains('virtualized row rendering'));
  });
}
