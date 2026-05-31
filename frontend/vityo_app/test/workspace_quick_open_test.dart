import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace quick open returns recent files first for an empty query', () {
    final result = const WorkspaceQuickOpenService().findFiles(
      filePaths: const <String>[
        'src/main.styio',
        'src/worker.styio',
        'README.md',
        'src/main.styio',
      ],
      recentFilePaths: const <String>[
        'src/worker.styio',
        'missing.styio',
        'src/main.styio',
      ],
      query: const WorkspaceQuickOpenQuery(maxResults: 2),
    );

    expect(result.status, WorkspaceQuickOpenStatus.hitLimit);
    expect(result.hitLimit, isTrue);
    expect(result.filesSearched, 3);
    expect(
      result.items.map((item) => item.filePath),
      <String>['src/worker.styio', 'src/main.styio'],
    );
    expect(result.items.map((item) => item.recentRank), <int?>[0, 1]);
  });

  test('workspace quick open scores fuzzy filename matches', () {
    final result = const WorkspaceQuickOpenService().findFiles(
      filePaths: const <String>[
        'src/view_ide/workspace/workspace_search.dart',
        'src/view_ide/workspace/workspace_quick_open.dart',
        'src/runtime/project_graph.dart',
      ],
      query: const WorkspaceQuickOpenQuery(pattern: 'wqo'),
    );

    expect(result.status, WorkspaceQuickOpenStatus.completed);
    expect(
      result.items.first.filePath,
      'src/view_ide/workspace/workspace_quick_open.dart',
    );
    expect(result.items.first.fileName, 'workspace_quick_open.dart');
    expect(result.items.first.parentPath, 'src/view_ide/workspace');
    expect(result.items.first.matches, isNotEmpty);
  });

  test('workspace quick open narrows by path substring', () {
    final result = const WorkspaceQuickOpenService().findFiles(
      filePaths: const <String>[
        'lib/runtime/project_graph.dart',
        'lib/workspace/project_graph.dart',
        'lib/workspace/runtime_surface.dart',
      ],
      query: const WorkspaceQuickOpenQuery(pattern: 'runtime/project'),
    );

    expect(result.matchCount, 1);
    expect(result.items.single.filePath, 'lib/runtime/project_graph.dart');
  });

  test('workspace controller tracks recent opened files across project refreshes', () {
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(
        const <String>['src/main.styio', 'src/worker.styio', 'README.md'],
      ),
    );

    expect(controller.recentFiles, <String>['src/main.styio']);

    controller.openFile('src/worker.styio');
    expect(
      controller.recentFiles,
      <String>['src/worker.styio', 'src/main.styio'],
    );

    controller.openFile('src/main.styio');
    expect(
      controller.recentFiles,
      <String>['src/main.styio', 'src/worker.styio'],
    );

    controller.replaceProject(
      _projectGraph(const <String>['src/main.styio', 'src/other.styio']),
      activeFilePath: 'src/other.styio',
    );

    expect(controller.activeFilePath, 'src/other.styio');
    expect(
      controller.recentFiles,
      <String>['src/other.styio', 'src/main.styio'],
    );
  });
}

ProjectGraphSnapshot _projectGraph(List<String> editorFiles) {
  return ProjectGraphSnapshot(
    id: '/workspace/demo',
    title: 'Demo',
    kind: ProjectKind.scratch,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: const <String>[],
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: editorFiles,
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.unavailable,
      detail: 'No project toolchain pin is active in scratch mode.',
    ),
    lockState: ProjectLockState.missing,
    vendorState: ProjectVendorState.missing,
    notes: const <String>[],
  );
}
