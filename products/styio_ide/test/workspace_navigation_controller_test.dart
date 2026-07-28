import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:styio_ide/src/ide/editor/editor.dart';
import 'package:styio_ide/src/view_ide/language/service/project_styio_language_service.dart';
import 'package:styio_ide/src/view_ide/language/simple_styio_language_service.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/workspace_navigation_controller.dart';
import 'package:styio_ide/src/ide/workspace/workspace.dart';

void main() {
  test('project document loading prefers unsaved editor facts', () async {
    const activePath = 'main.styio';
    const helperPath = 'lib/math.styio';
    const diskActive = DocumentState(
      documentId: activePath,
      text: 'disk value\n',
      revision: 1,
    );
    const unsavedActive = DocumentState(
      documentId: activePath,
      text: 'unsaved value\n',
      revision: 2,
    );
    const helper = DocumentState(
      documentId: helperPath,
      text: 'fn blend(): i32 { emit 1 }\n',
      revision: 1,
    );
    final fixture = _fixture(
      documents: const <DocumentState>[diskActive, helper],
      activeDocument: unsavedActive,
    );
    addTearDown(fixture.dispose);

    final documents = await fixture.controller.loadDocuments();

    expect(documents, hasLength(2));
    expect(
      documents.singleWhere((document) => document.documentId == activePath),
      unsavedActive,
    );
    expect(
      documents.singleWhere((document) => document.documentId == helperPath),
      helper,
    );
  });

  test(
    'project definition navigation opens the authoritative target',
    () async {
      const main = DocumentState(
        documentId: 'main.styio',
        text: '@import { lib/math }\nvalue = blend(1, 2)\n',
        revision: 1,
      );
      const helper = DocumentState(
        documentId: 'lib/math.styio',
        text: 'fn blend(left: i32, right: i32): i32 { emit left + right }\n',
        revision: 1,
      );
      final fixture = _fixture(
        documents: const <DocumentState>[main, helper],
        activeDocument: main,
      );
      addTearDown(fixture.dispose);
      fixture.editor.selectCollapsed(main.text.indexOf('blend'));

      final selected = await fixture.controller.goToDefinition();

      expect(selected, isTrue);
      expect(fixture.editor.document.documentId, helper.documentId);
      expect(
        fixture.editor.document.text.substring(
          fixture.editor.selection.start,
          fixture.editor.selection.end,
        ),
        'blend',
      );
    },
  );
}

_NavigationFixture _fixture({
  required List<DocumentState> documents,
  required DocumentState activeDocument,
}) {
  final store = InMemoryWorkspaceDocumentStore(
    seededDocuments: <String, DocumentState>{
      for (final document in documents) document.documentId: document,
    },
  );
  final workspace = WorkspaceController(
    projectSnapshot: _projectGraph(
      documents.map((document) => document.documentId).toList(),
    ),
  );
  final editor = EditorSessionController(
    initialDocument: activeDocument,
    languageService: const SimpleStyioLanguageService(),
  );
  late final WorkspaceNavigationController controller;
  controller = WorkspaceNavigationController(
    workspaceController: workspace,
    documentStore: store,
    editorController: editor,
    languageService: const ProjectStyioLanguageService(),
    documentSamples: () => <DocumentState>[editor.document],
    openWorkspaceFile: (path) async {
      if (!workspace.files.contains(path)) {
        return false;
      }
      workspace.openFile(path);
      editor.loadDocument(await store.loadDocument(path));
      return true;
    },
    log: (_) {},
  );
  return _NavigationFixture(
    workspace: workspace,
    editor: editor,
    controller: controller,
  );
}

final class _NavigationFixture {
  const _NavigationFixture({
    required this.workspace,
    required this.editor,
    required this.controller,
  });

  final WorkspaceController workspace;
  final EditorSessionController editor;
  final WorkspaceNavigationController controller;

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
