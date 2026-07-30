import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/service/project_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/project_language_context_controller.dart';

void main() {
  test(
    'collect publishes honest fallback facts and caches inactive documents',
    () async {
      const active = DocumentState(
        documentId: 'main.styio',
        text: '@import { lib/math }\nvalue = blend(1, 2)\n',
        revision: 2,
      );
      const helper = DocumentState(
        documentId: 'lib/math.styio',
        text: 'fn blend(left: i32, right: i32): i32 { emit left + right }\n',
        revision: 1,
      );
      final editor = EditorSessionController(
        initialDocument: active,
        languageService: const SimpleStyioLanguageService(),
      );
      addTearDown(editor.dispose);
      editor.selectCollapsed(active.text.indexOf('blend'));
      final cached = <String, DocumentState>{};
      final logs = <String>[];
      final telemetryDocuments = <String>[];
      var notifications = 0;
      final controller = ProjectLanguageContextController(
        languageService: const ProjectStyioLanguageService(),
        editorController: editor,
        documentSamples: () => const <DocumentState>[active, helper],
        loadDocuments: () async => const <DocumentState>[active, helper],
        cacheDocument: (documentId, document) {
          cached[documentId] = document;
        },
        languageServiceStatus: LanguageServiceStatusSurface.unavailable,
        lastDaemonRestartDispatch: () => null,
        compareReferences: (left, right) {
          final documentCompare = left.documentId.compareTo(right.documentId);
          return documentCompare != 0
              ? documentCompare
              : left.range.start.compareTo(right.range.start);
        },
        log: logs.add,
        recordSemanticTokensTelemetry: ({required documentId}) {
          telemetryDocuments.add(documentId);
        },
      )..addListener(() => notifications += 1);
      addTearDown(controller.dispose);

      final metadata = await controller.collect();

      expect(metadata['documentId'], active.documentId);
      expect(metadata['documentCount'], 2);
      expect(metadata['definitionCount'], greaterThan(0));
      expect(metadata['referenceCount'], greaterThan(0));
      expect(metadata['definitions'], isA<List<Object?>>());
      expect(metadata['references'], isA<List<Object?>>());
      final authority =
          metadata['syntaxValidationAuthority']! as Map<String, Object?>;
      expect(authority['preferredSource'], 'vityo-ide-syntax-contract');
      expect(authority['fallbackSource'], 'vityo-ide-syntax-contract');
      expect(authority['fallbackActive'], isTrue);
      expect(
        metadata['suggestedCommandIds'],
        contains('refreshLanguageService'),
      );
      expect(cached, <String, DocumentState>{helper.documentId: helper});
      expect(telemetryDocuments, <String>[active.documentId]);
      expect(logs.single, startsWith('Project language context collected:'));
      expect(notifications, 1);
    },
  );

  test('project editor facts use the unsaved document sample', () {
    const disk = DocumentState(
      documentId: 'main.styio',
      text: 'value = missing\n',
      revision: 1,
    );
    const unsaved = DocumentState(
      documentId: 'main.styio',
      text: 'fn blend(left: i32): i32 { emit left }\nvalue = blend(1)\n',
      revision: 2,
    );
    final editor = EditorSessionController(
      initialDocument: unsaved,
      languageService: const SimpleStyioLanguageService(),
    );
    addTearDown(editor.dispose);
    editor.selectCollapsed(unsaved.text.lastIndexOf('blend'));
    final controller = ProjectLanguageContextController(
      languageService: const ProjectStyioLanguageService(),
      editorController: editor,
      documentSamples: () => const <DocumentState>[unsaved],
      loadDocuments: () async => const <DocumentState>[disk],
      cacheDocument: (_, _) {},
      languageServiceStatus: LanguageServiceStatusSurface.unavailable,
      lastDaemonRestartDispatch: () => null,
      compareReferences: (_, _) => 0,
      log: (_) {},
      recordSemanticTokensTelemetry: ({required documentId}) {},
    );
    addTearDown(controller.dispose);

    expect(controller.projectHoverAtSelection?.markdown, contains('blend'));
    expect(
      controller.projectCompletionsAtSelection.map((item) => item.label),
      contains('blend'),
    );
    expect(
      controller.mergedCompletionsAtSelection
          .map((item) => '${item.kind.name}:${item.label}:${item.insertText}')
          .toSet()
          .length,
      controller.mergedCompletionsAtSelection.length,
    );
  });
}
