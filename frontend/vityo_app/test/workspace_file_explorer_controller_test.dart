import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace file explorer builds stable directory tree', () {
    final tree = buildWorkspaceFileExplorerTree(const <String>[
      'README.md',
      'src/main.styio',
      'src/lib/math.styio',
      'test/parser_test.styio',
    ]);

    expect(tree.map((node) => node.name), <String>['src', 'test', 'README.md']);
    expect(tree.first.kind, WorkspaceFileExplorerNodeKind.directory);
    expect(tree.first.fileCount, 2);
    expect(tree.first.children.map((node) => node.path), <String>[
      'src/lib',
      'src/main.styio',
    ]);
    expect(tree.first.toJson()['fileCount'], 2);
  });

  test('workspace file explorer discovery normalizes file system paths', () {
    final discovery = WorkspaceFileExplorerDiscoveryResult.fromPaths(
      seedPaths: const <String>['README.md'],
      discoveredPaths: const <String>[
        'src\\main.styio',
        'src/main.styio',
        'src/lib/math.styio',
        '../secret.styio',
        '/tmp/outside.styio',
        '',
      ],
      source: 'fixture-fs',
    );
    final workspaceController = WorkspaceController(
      projectSnapshot: _projectGraph(editorFiles: const <String>['README.md']),
    );
    final controller = WorkspaceFileExplorerController(
      workspaceController: workspaceController,
      operationService: WorkspaceFileOperationService(
        workspaceController: workspaceController,
        documentStore: InMemoryWorkspaceDocumentStore(),
      ),
    );
    addTearDown(controller.dispose);

    final snapshot = controller.snapshotFromDiscovery(discovery);

    expect(discovery.source, 'fixture-fs');
    expect(discovery.filePaths, <String>[
      'README.md',
      'src/lib/math.styio',
      'src/main.styio',
    ]);
    expect(discovery.ignoredPathCount, 3);
    expect(discovery.truncated, isFalse);
    expect(snapshot.fileCount, 3);
    expect(snapshot.discovery, same(discovery));
    expect(snapshot.roots.map((node) => node.name), <String>[
      'src',
      'README.md',
    ]);
    expect(snapshot.toJson()['discovery'], isA<Map<String, Object?>>());
  });

  test('workspace file explorer controller runs file operations', () async {
    final store = InMemoryWorkspaceDocumentStore();
    final workspaceController = WorkspaceController(
      projectSnapshot: _projectGraph(editorFiles: const <String>['main.styio']),
    );
    final controller = WorkspaceFileExplorerController(
      workspaceController: workspaceController,
      operationService: WorkspaceFileOperationService(
        workspaceController: workspaceController,
        documentStore: store,
      ),
    );
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() {
      notifications += 1;
    });

    final created = await controller.run(
      const WorkspaceFileExplorerActionRequest(
        kind: WorkspaceFileOperationKind.create,
        path: 'src/new.styio',
        text: 'value := 1\n',
        open: true,
      ),
    );
    final renamed = await controller.run(
      const WorkspaceFileExplorerActionRequest(
        kind: WorkspaceFileOperationKind.rename,
        path: 'src/new.styio',
        nextPath: 'src/renamed.styio',
      ),
    );
    final revealed = await controller.run(
      const WorkspaceFileExplorerActionRequest(
        kind: WorkspaceFileOperationKind.reveal,
        path: 'main.styio',
      ),
    );
    final snapshot = controller.snapshot;

    expect(created.applied, isTrue);
    expect(renamed.applied, isTrue);
    expect(revealed.applied, isTrue);
    expect(controller.lastResult, same(revealed));
    expect(snapshot.fileCount, 2);
    expect(snapshot.activeFilePath, 'main.styio');
    expect(snapshot.toJson()['fileCount'], 2);
    expect(workspaceController.files, <String>[
      'main.styio',
      'src/renamed.styio',
    ]);
    expect(await store.documentExists('src/new.styio'), isFalse);
    expect(await store.documentExists('src/renamed.styio'), isTrue);
    expect(notifications, greaterThanOrEqualTo(3));
  });
}

ProjectGraphSnapshot _projectGraph({required List<String> editorFiles}) {
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
