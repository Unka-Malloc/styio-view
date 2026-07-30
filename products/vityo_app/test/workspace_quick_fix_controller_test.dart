import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/service/project_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/editor_workspace_state_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/workspace_quick_fix_controller.dart';
import 'package:vityo_app/src/ide/workspace/workspace.dart';

void main() {
  test(
    'reviewed project quick fix applies active and inactive edits',
    () async {
      final fixture = _fixture();
      addTearDown(fixture.dispose);

      final preview = await fixture.controller.previewFirst();
      final applied = await fixture.controller.applyFirst(
        expectedPreviewPlanId: preview?.planId,
      );

      expect(preview, isNotNull);
      expect(applied, isTrue);
      expect(fixture.controller.lastApplyResult?.successful, isTrue);
      expect(fixture.editor.document.text, _cleanMainText);
      expect(fixture.state.isDirty(_mainPath), isTrue);
      expect(
        (await fixture.store.loadDocument(_helperPath)).text,
        _cleanHelperText,
      );
    },
  );

  test('mismatched preview plan fails closed with review evidence', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);
    final beforeMain = fixture.editor.document;
    final beforeHelper = await fixture.store.loadDocument(_helperPath);

    final applied = await fixture.controller.applyFirst(
      expectedPreviewPlanId: 'stale-preview-plan',
    );

    expect(applied, isFalse);
    expect(fixture.controller.lastPreview, isNotNull);
    expect(fixture.controller.lastApplyResult?.successful, isFalse);
    expect(fixture.controller.lastApplyResult?.message, contains('stale'));
    expect(fixture.editor.document, beforeMain);
    expect(await fixture.store.loadDocument(_helperPath), beforeHelper);
    expect(fixture.state.dirtyDocumentPaths, isEmpty);
  });
}

const _mainPath = 'main.styio';
const _helperPath = 'lib/sorted.styio';
const _mainText = '''
@import { styio/io }
@import { styio/core }
@import { styio/io }
value = 1
''';
const _helperText = '''
@import { styio/io }
@import { styio/core }
ready = true
''';
const _cleanMainText = '''
@import { styio/core }
@import { styio/io }
value = 1
''';
const _cleanHelperText = '''
@import { styio/core }
@import { styio/io }
ready = true
''';

_QuickFixFixture _fixture() {
  const main = DocumentState(
    documentId: _mainPath,
    text: _mainText,
    revision: 1,
  );
  const helper = DocumentState(
    documentId: _helperPath,
    text: _helperText,
    revision: 1,
  );
  final store = InMemoryWorkspaceDocumentStore(
    seededDocuments: const <String, DocumentState>{
      _mainPath: main,
      _helperPath: helper,
    },
  );
  final editor = EditorSessionController(
    initialDocument: main,
    languageService: const SimpleStyioLanguageService(),
  );
  final state = EditorWorkspaceStateController(documentCacheLimit: 8);
  final documents = <DocumentState>[main, helper];
  final controller = WorkspaceQuickFixController(
    languageService: const ProjectStyioLanguageService(),
    loadDocuments: () async => documents,
    documentSamples: () => documents,
    documentStore: store,
    editorController: editor,
    editorWorkspaceState: state,
    cacheDocument: (documentId, document) {
      state.cacheDocument(
        documentId,
        document,
        activeDocumentPath: _mainPath,
        openFilePaths: const <String>[_mainPath, _helperPath],
      );
    },
    log: (_) {},
  );
  return _QuickFixFixture(
    store: store,
    editor: editor,
    state: state,
    controller: controller,
  );
}

final class _QuickFixFixture {
  const _QuickFixFixture({
    required this.store,
    required this.editor,
    required this.state,
    required this.controller,
  });

  final InMemoryWorkspaceDocumentStore store;
  final EditorSessionController editor;
  final EditorWorkspaceStateController state;
  final WorkspaceQuickFixController controller;

  void dispose() {
    controller.dispose();
    editor.dispose();
  }
}
