import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent_client/agent.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/ide/editor/editor.dart';
import 'package:vityo_app/src/view_ide/language/service/project_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/workspace_search_controller.dart';
import 'package:vityo_app/src/ide/workspace/workspace.dart';

void main() {
  test('text and symbol search publish one shared document scan', () async {
    const activePath = 'main.styio';
    const helperPath = 'lib/math.styio';
    const unsavedActive = DocumentState(
      documentId: activePath,
      text: 'value = blend(1, 2)\n',
      revision: 2,
    );
    const helper = DocumentState(
      documentId: helperPath,
      text: 'fn blend(left: i32, right: i32): i32 { emit left + right }\n',
      revision: 1,
    );
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        activePath: DocumentState(
          documentId: activePath,
          text: 'disk content\n',
          revision: 1,
        ),
        helperPath: helper,
      },
    );
    final workspace = WorkspaceController(
      projectSnapshot: _projectGraph(const <String>[activePath, helperPath]),
    );
    addTearDown(workspace.dispose);
    AgentWorkspaceSearchResultContext? textResult;
    AgentWorkspaceSymbolSearchResultContext? symbolResult;
    final controller = WorkspaceSearchController(
      workspaceController: workspace,
      documentStore: store,
      languageService: const ProjectStyioLanguageService(),
      documentSamples: () => const <DocumentState>[unsavedActive],
      publishResults: (text, symbols) {
        textResult = text;
        symbolResult = symbols;
      },
      log: (_) {},
    );

    final searched = await controller.search('blend');

    expect(searched, isTrue);
    expect(textResult?.scannedDocumentCount, 2);
    expect(textResult?.matchCount, 2);
    expect(symbolResult?.scannedDocumentCount, 2);
    expect(symbolResult?.matches.map((match) => match.name), contains('blend'));
  });

  test('empty search fails closed without publishing stale results', () async {
    final workspace = WorkspaceController(
      projectSnapshot: _projectGraph(const <String>['main.styio']),
    );
    addTearDown(workspace.dispose);
    var published = false;
    final controller = WorkspaceSearchController(
      workspaceController: workspace,
      documentStore: InMemoryWorkspaceDocumentStore(),
      languageService: const ProjectStyioLanguageService(),
      documentSamples: () => const <DocumentState>[],
      publishResults: (_, _) {
        published = true;
      },
      log: (_) {},
    );

    expect(await controller.search('  '), isFalse);
    expect(published, isFalse);
  });
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
