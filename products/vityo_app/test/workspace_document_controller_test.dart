import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:vityo_app/src/ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/interaction/document_resource_binding.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/editor_workspace_state_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/workspace_document_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/workspace_file_lifecycle.dart';
import 'package:vityo_app/src/ide/workspace/workspace.dart';

void main() {
  test(
    'stale workspace document load cannot replace the newest route',
    () async {
      const firstPath = '/workspace/demo/first.styio';
      const secondPath = '/workspace/demo/second.styio';
      const thirdPath = '/workspace/demo/third.styio';
      final workspace = WorkspaceController(
        projectSnapshot: _projectGraph(<String>[
          firstPath,
          secondPath,
          thirdPath,
        ]),
      );
      addTearDown(workspace.dispose);
      final editor = EditorSessionController(
        initialDocument: _document(firstPath),
        languageService: const SimpleStyioLanguageService(),
      );
      addTearDown(editor.dispose);
      final store = _DelayedWorkspaceDocumentStore();
      final binding = EditorDocumentResourceBinding(documentStore: store)
        ..bindLoadedDocument(editor.document);
      addTearDown(binding.dispose);
      final state = EditorWorkspaceStateController(documentCacheLimit: 4);
      final controller = WorkspaceDocumentController(
        workspaceController: workspace,
        editorController: editor,
        fileBinding: binding,
        documentStore: store,
        state: state,
        sessionStore: null,
        sessionWorkspaceId: 'demo',
        log: (_) {},
        notify: () {},
      );

      workspace.openFile(secondPath);
      final secondLoad = controller.loadActiveDocument();
      workspace.openFile(thirdPath);
      final thirdLoad = controller.loadActiveDocument();

      store.complete(thirdPath, _document(thirdPath));
      await thirdLoad;
      store.complete(secondPath, _document(secondPath));
      await secondLoad;

      expect(controller.activeDocumentPath, thirdPath);
      expect(workspace.activeFilePath, thirdPath);
      expect(editor.document.documentId, thirdPath);
      expect(state.document(firstPath), isNotNull);
    },
  );

  test('dirty active document blocks close with explicit recovery', () {
    const path = '/workspace/demo/main.styio';
    final document = _document(path);
    final workspace = WorkspaceController(
      projectSnapshot: _projectGraph(<String>[path]),
    );
    addTearDown(workspace.dispose);
    final editor = EditorSessionController(
      initialDocument: document,
      languageService: const SimpleStyioLanguageService(),
    );
    addTearDown(editor.dispose);
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: <String, DocumentState>{path: document},
    );
    final binding = EditorDocumentResourceBinding(documentStore: store)
      ..bindLoadedDocument(document);
    addTearDown(binding.dispose);
    final state = EditorWorkspaceStateController(documentCacheLimit: 4);
    final controller = WorkspaceDocumentController(
      workspaceController: workspace,
      editorController: editor,
      fileBinding: binding,
      documentStore: store,
      state: state,
      sessionStore: null,
      sessionWorkspaceId: 'demo',
      log: (_) {},
      notify: () {},
    );
    final edited = document.replaceRange(
      start: 0,
      end: 0,
      replacement: 'changed\n',
    );
    editor.loadDocument(edited);
    binding.markDocumentChanged(edited);
    state.markDirty(path);

    final result = controller.requestClose(path);

    expect(
      result.status,
      WorkspaceFileCloseRequestStatus.blockedUnsavedChanges,
    );
    expect(result.requiresUserChoice, isTrue);
    expect(result.canSave, isTrue);
    expect(result.canDiscard, isTrue);
    expect(result.canSwitchToFile, isFalse);
    expect(workspace.openFilePaths, contains(path));
    expect(controller.lastCloseRequest, same(result));

    controller.clearCloseRequest();
    expect(controller.lastCloseRequest, isNull);
  });

  test(
    'discard recovery reloads backing content and completes close',
    () async {
      const path = '/workspace/demo/main.styio';
      final document = _document(path);
      final workspace = WorkspaceController(
        projectSnapshot: _projectGraph(<String>[path]),
      );
      addTearDown(workspace.dispose);
      final editor = EditorSessionController(
        initialDocument: document,
        languageService: const SimpleStyioLanguageService(),
      );
      addTearDown(editor.dispose);
      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: <String, DocumentState>{path: document},
      );
      final binding = EditorDocumentResourceBinding(documentStore: store)
        ..bindLoadedDocument(document);
      addTearDown(binding.dispose);
      final state = EditorWorkspaceStateController(documentCacheLimit: 4);
      final controller = WorkspaceDocumentController(
        workspaceController: workspace,
        editorController: editor,
        fileBinding: binding,
        documentStore: store,
        state: state,
        sessionStore: null,
        sessionWorkspaceId: 'demo',
        log: (_) {},
        notify: () {},
      );
      final edited = document.replaceRange(
        start: 0,
        end: 0,
        replacement: 'changed\n',
      );
      editor.loadDocument(edited);
      binding.markDocumentChanged(edited);
      state.markDirty(path);
      expect(controller.requestClose(path).requiresUserChoice, isTrue);

      final result = await controller.discardAndCloseRequested();

      expect(result?.status, WorkspaceFileCloseRequestStatus.closed);
      expect(editor.document, document);
      expect(binding.snapshot.state, DocumentResourceBindingState.boundClean);
      expect(state.isDirty(path), isFalse);
    },
  );

  test(
    'save all persists active and cached inactive dirty documents',
    () async {
      const activePath = '/workspace/demo/main.styio';
      const inactivePath = '/workspace/demo/helper.styio';
      final activeDocument = _document(activePath);
      final inactiveDocument = _document(inactivePath);
      final workspace = WorkspaceController(
        projectSnapshot: _projectGraph(<String>[activePath, inactivePath]),
      );
      addTearDown(workspace.dispose);
      final editor = EditorSessionController(
        initialDocument: activeDocument,
        languageService: const SimpleStyioLanguageService(),
      );
      addTearDown(editor.dispose);
      final store = InMemoryWorkspaceDocumentStore(
        seededDocuments: <String, DocumentState>{
          activePath: activeDocument,
          inactivePath: inactiveDocument,
        },
      );
      final binding = EditorDocumentResourceBinding(documentStore: store)
        ..bindLoadedDocument(activeDocument);
      addTearDown(binding.dispose);
      final state = EditorWorkspaceStateController(documentCacheLimit: 4);
      final controller = WorkspaceDocumentController(
        workspaceController: workspace,
        editorController: editor,
        fileBinding: binding,
        documentStore: store,
        state: state,
        sessionStore: null,
        sessionWorkspaceId: 'demo',
        log: (_) {},
        notify: () {},
      );
      final editedActive = activeDocument.replaceRange(
        start: 0,
        end: 0,
        replacement: 'active change\n',
      );
      final editedInactive = inactiveDocument.replaceRange(
        start: 0,
        end: 0,
        replacement: 'inactive change\n',
      );
      editor.loadDocument(editedActive);
      binding.markDocumentChanged(editedActive);
      controller.cacheDocument(inactivePath, editedInactive);
      state
        ..markDirty(activePath)
        ..markDirty(inactivePath);

      final result = await controller.saveAll(
        saveActive: () async {
          final saveResult = await binding.save(editor.document);
          if (saveResult.saved) {
            state.clearDirty(activePath);
          }
          return saveResult.snapshot;
        },
      );

      expect(result.savedAll, isTrue);
      expect(result.savedDocumentIds, <String>[activePath, inactivePath]);
      expect(result.skippedDocumentIds, isEmpty);
      expect(state.dirtyDocumentPaths, isEmpty);
      expect((await store.loadDocument(activePath)).text, editedActive.text);
      expect(
        (await store.loadDocument(inactivePath)).text,
        editedInactive.text,
      );
    },
  );
}

DocumentState _document(String path) =>
    DocumentState(documentId: path, text: '$path\n', revision: 1);

ProjectGraphSnapshot _projectGraph(List<String> editorFiles) {
  return ProjectGraphSnapshot(
    id: '/workspace/demo/pafio.toml',
    title: 'demo',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/demo/pafio.toml',
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: editorFiles,
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.unavailable,
      detail: 'No toolchain required for navigation test.',
    ),
    lockState: ProjectLockState.unknown,
    vendorState: ProjectVendorState.missing,
    notes: const <String>[],
  );
}

final class _DelayedWorkspaceDocumentStore implements WorkspaceDocumentStore {
  final Map<String, Completer<DocumentState>> _loads =
      <String, Completer<DocumentState>>{};

  void complete(String path, DocumentState document) {
    (_loads[path] ??= Completer<DocumentState>()).complete(document);
  }

  @override
  Future<DocumentState> loadDocument(String path) =>
      (_loads[path] ??= Completer<DocumentState>()).future;

  @override
  Future<void> saveDocument(DocumentState document) async {}

  @override
  Future<bool> deleteDocument(String path) async => false;

  @override
  Future<bool> documentExists(String path) async => _loads.containsKey(path);

  @override
  String? filePathForDocumentId(String documentId) => documentId;
}
