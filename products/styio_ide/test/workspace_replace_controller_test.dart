import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:styio_ide/src/ide/editor/editor.dart';
import 'package:styio_ide/src/view_ide/language/simple_styio_language_service.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/editor_workspace_state_controller.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/workspace_replace_controller.dart';
import 'package:styio_ide/src/ide/workspace/workspace.dart';

void main() {
  test(
    'reviewed preview applies and synchronizes the active document',
    () async {
      const active = DocumentState(
        documentId: 'src/main.styio',
        text: 'needle main\n',
        revision: 1,
      );
      const inactive = DocumentState(
        documentId: 'src/helper.styio',
        text: 'needle helper\n',
        revision: 1,
      );
      final fixture = _fixture(<DocumentState>[active, inactive]);
      addTearDown(fixture.dispose);

      final preview = await fixture.controller.preview(
        query: 'needle',
        replacement: 'thread',
      );
      final result = await fixture.controller.apply(preview!);

      expect(result?.replacementCount, 2);
      expect(result?.failures, isEmpty);
      expect(fixture.controller.lastPreview, isNull);
      expect(fixture.editor.document.text, 'thread main\n');
      expect(
        (await fixture.store.loadDocument(inactive.documentId)).text,
        'thread helper\n',
      );
      expect(fixture.state.dirtyDocumentPaths.toSet(), <String>{
        active.documentId,
        inactive.documentId,
      });
    },
  );

  test(
    'stale preview fails closed without replacing active editor text',
    () async {
      const active = DocumentState(
        documentId: 'src/main.styio',
        text: 'needle main\n',
        revision: 1,
      );
      final fixture = _fixture(<DocumentState>[active]);
      addTearDown(fixture.dispose);
      final preview = await fixture.controller.preview(
        query: 'needle',
        replacement: 'thread',
      );
      await fixture.store.saveDocument(
        const DocumentState(
          documentId: 'src/main.styio',
          text: 'newer disk content\n',
          revision: 2,
        ),
      );

      final result = await fixture.controller.apply(preview!);

      expect(result?.documents, isEmpty);
      expect(result?.failures, hasLength(1));
      expect(result?.failures.single.message, contains('changed since'));
      expect(fixture.editor.document, active);
      expect(fixture.state.dirtyDocumentPaths, isEmpty);
      expect(fixture.controller.lastPreview, same(preview));
    },
  );
}

_ReplaceFixture _fixture(List<DocumentState> documents) {
  final active = documents.first;
  final workspace = WorkspaceController(
    projectSnapshot: _projectGraph(
      documents.map((document) => document.documentId).toList(),
    ),
  );
  final store = InMemoryWorkspaceDocumentStore(
    seededDocuments: <String, DocumentState>{
      for (final document in documents) document.documentId: document,
    },
  );
  final editor = EditorSessionController(
    initialDocument: active,
    languageService: const SimpleStyioLanguageService(),
  );
  final state = EditorWorkspaceStateController(documentCacheLimit: 8);
  return _ReplaceFixture(
    workspace: workspace,
    store: store,
    editor: editor,
    state: state,
    controller: WorkspaceReplaceController(
      workspaceController: workspace,
      documentStore: store,
      editorController: editor,
      editorWorkspaceState: state,
      log: (_) {},
    ),
  );
}

final class _ReplaceFixture {
  const _ReplaceFixture({
    required this.workspace,
    required this.store,
    required this.editor,
    required this.state,
    required this.controller,
  });

  final WorkspaceController workspace;
  final InMemoryWorkspaceDocumentStore store;
  final EditorSessionController editor;
  final EditorWorkspaceStateController state;
  final WorkspaceReplaceController controller;

  void dispose() {
    controller.dispose();
    editor.dispose();
    workspace.dispose();
  }
}

ProjectGraphSnapshot _projectGraph(List<String> editorFiles) {
  return ProjectGraphSnapshot(
    id: 'fixture://project',
    title: 'fixture',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/fixture',
    workspaceMembers: const <String>[],
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: editorFiles,
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'fixture',
    ),
    lockState: ProjectLockState.unknown,
    vendorState: ProjectVendorState.unknown,
    notes: const <String>[],
  );
}
