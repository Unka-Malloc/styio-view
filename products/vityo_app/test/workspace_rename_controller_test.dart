import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/service/project_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/editor_workspace_state_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/workspace_rename_controller.dart';
import 'package:vityo_app/src/ide/workspace/workspace.dart';

void main() {
  test('project rename applies active and persisted inactive edits', () async {
    final fixture = _fixture(conflictingName: false);
    addTearDown(fixture.dispose);
    fixture.editor.selectCollapsed(fixture.main.text.indexOf('blend'));

    final applied = await fixture.controller.renameAtSelection('mix');

    expect(applied, isTrue);
    expect(fixture.editor.document.text, contains('mix(1.0'));
    expect(fixture.state.isDirty(fixture.main.documentId), isTrue);
    expect(
      (await fixture.store.loadDocument(fixture.runtime.documentId)).text,
      contains('fn mix'),
    );
    expect(fixture.safetyEvents.single.safe, isTrue);
    expect(fixture.safetyEvents.single.targetName, 'blend');
    expect(fixture.safetyEvents.single.newName, 'mix');
  });

  test('project rename collision fails closed with safety evidence', () async {
    final fixture = _fixture(conflictingName: true);
    addTearDown(fixture.dispose);
    fixture.editor.selectCollapsed(fixture.main.text.indexOf('blend'));
    final beforeRuntime = await fixture.store.loadDocument(
      fixture.runtime.documentId,
    );

    final applied = await fixture.controller.renameAtSelection('mix');

    expect(applied, isFalse);
    expect(fixture.editor.document, fixture.main);
    expect(
      await fixture.store.loadDocument(fixture.runtime.documentId),
      beforeRuntime,
    );
    expect(fixture.state.dirtyDocumentPaths, isEmpty);
    expect(fixture.safetyEvents.single.safe, isFalse);
    expect(fixture.safetyEvents.single.metadata['conflict'], isNotNull);
  });
}

_RenameFixture _fixture({required bool conflictingName}) {
  const main = DocumentState(
    documentId: 'main.styio',
    text: '@import { lib/runtime }\nvalue = blend(1.0, 2.0)\n',
    revision: 1,
  );
  final runtime = DocumentState(
    documentId: 'lib/runtime.styio',
    text:
        'fn blend(left: f64, right: f64): f64 { emit left + right }\n'
        '${conflictingName ? 'fn mix(): f64 { emit 0.0 }\n' : ''}',
    revision: 1,
  );
  final documents = <DocumentState>[main, runtime];
  final store = InMemoryWorkspaceDocumentStore(
    seededDocuments: <String, DocumentState>{
      for (final document in documents) document.documentId: document,
    },
  );
  final editor = EditorSessionController(
    initialDocument: main,
    languageService: const SimpleStyioLanguageService(),
  );
  final state = EditorWorkspaceStateController(documentCacheLimit: 8);
  final safetyEvents = <_SafetyEvent>[];
  final controller = WorkspaceRenameController(
    languageService: const ProjectStyioLanguageService(),
    loadDocuments: () async => documents,
    editorController: editor,
    documentStore: store,
    editorWorkspaceState: state,
    cacheDocument: (documentId, document) {
      state.cacheDocument(
        documentId,
        document,
        activeDocumentPath: main.documentId,
        openFilePaths: documents.map((document) => document.documentId),
      );
    },
    activeDocumentPath: () => main.documentId,
    log: (_) {},
    recordSafety:
        ({
          required safe,
          required newName,
          required message,
          required targetName,
          required metadata,
        }) async {
          safetyEvents.add(
            _SafetyEvent(
              safe: safe,
              newName: newName,
              targetName: targetName,
              metadata: metadata,
            ),
          );
        },
  );
  return _RenameFixture(
    main: main,
    runtime: runtime,
    store: store,
    editor: editor,
    state: state,
    controller: controller,
    safetyEvents: safetyEvents,
  );
}

final class _RenameFixture {
  const _RenameFixture({
    required this.main,
    required this.runtime,
    required this.store,
    required this.editor,
    required this.state,
    required this.controller,
    required this.safetyEvents,
  });

  final DocumentState main;
  final DocumentState runtime;
  final InMemoryWorkspaceDocumentStore store;
  final EditorSessionController editor;
  final EditorWorkspaceStateController state;
  final WorkspaceRenameController controller;
  final List<_SafetyEvent> safetyEvents;

  void dispose() {
    controller.dispose();
    editor.dispose();
  }
}

final class _SafetyEvent {
  const _SafetyEvent({
    required this.safe,
    required this.newName,
    required this.targetName,
    required this.metadata,
  });

  final bool safe;
  final String newName;
  final String targetName;
  final Map<String, Object?> metadata;
}
