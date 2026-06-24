import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';

void main() {
  test('workspace controller tracks opened files in order', () {
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(
        editorFiles: const <String>['main.styio', 'lib.styio'],
      ),
    );

    expect(controller.activeFilePath, 'main.styio');
    expect(controller.openFilePaths, <String>['main.styio']);

    controller.openFile('lib.styio');
    controller.openFile('lib.styio');

    expect(controller.activeFilePath, 'lib.styio');
    expect(controller.openFilePaths, <String>['main.styio', 'lib.styio']);
  });

  test('workspace controller closes active file and falls back to previous tab', () {
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(
        editorFiles: const <String>['main.styio', 'lib.styio', 'test.styio'],
      ),
    );

    controller
      ..openFile('lib.styio')
      ..openFile('test.styio')
      ..closeFile('test.styio');

    expect(controller.activeFilePath, 'lib.styio');
    expect(controller.openFilePaths, <String>['main.styio', 'lib.styio']);

    controller.closeFile('lib.styio');

    expect(controller.activeFilePath, 'main.styio');
    expect(controller.openFilePaths, <String>['main.styio']);
  });

  test('workspace controller prunes open files when project changes', () {
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(
        editorFiles: const <String>['main.styio', 'lib.styio'],
      ),
    );

    controller.openFile('lib.styio');
    controller.replaceProject(
      _projectGraph(editorFiles: const <String>['next.styio']),
    );

    expect(controller.activeFilePath, 'next.styio');
    expect(controller.openFilePaths, <String>['next.styio']);
  });

  test('workspace controller closes inactive file without changing active file', () {
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(
        editorFiles: const <String>['main.styio', 'lib.styio', 'test.styio'],
      ),
    );

    controller
      ..openFile('lib.styio')
      ..openFile('test.styio')
      ..closeFile('lib.styio');

    expect(controller.activeFilePath, 'test.styio');
    expect(controller.openFilePaths, <String>['main.styio', 'test.styio']);
  });

  test('workspace controller falls back to project file when last open file closes', () {
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(
        editorFiles: const <String>['main.styio', 'lib.styio'],
      ),
    );

    controller.closeFile('main.styio');

    expect(controller.activeFilePath, 'main.styio');
    expect(controller.openFilePaths, <String>['main.styio']);
  });

  test('workspace controller opens target files through target descriptors', () {
    const target = ProjectTargetDescriptor(
      id: 'fixture:bin:app',
      packageName: 'fixture/app',
      kind: ProjectTargetKind.bin,
      name: 'app',
      filePath: 'bin/app.styio',
    );
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(
        editorFiles: const <String>['main.styio', 'bin/app.styio'],
        targets: const <ProjectTargetDescriptor>[target],
      ),
    );

    controller.openTarget(target);

    expect(controller.activeFilePath, 'bin/app.styio');
    expect(controller.openFilePaths, <String>['main.styio', 'bin/app.styio']);
  });

  test('workspace controller exposes immutable open file paths', () {
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(
        editorFiles: const <String>['main.styio', 'lib.styio'],
      ),
    );

    expect(
      () => controller.openFilePaths.add('lib.styio'),
      throwsUnsupportedError,
    );
    expect(controller.openFilePaths, <String>['main.styio']);
  });

  test('workspace controller opens explicit active file during project replacement', () {
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(
        editorFiles: const <String>['main.styio', 'lib.styio'],
      ),
    );

    controller
      ..openFile('lib.styio')
      ..replaceProject(
        _projectGraph(editorFiles: const <String>['next.styio', 'extra.styio']),
        activeFilePath: 'extra.styio',
      );

    expect(controller.activeFilePath, 'extra.styio');
    expect(controller.openFilePaths, <String>['extra.styio']);
  });

  test('workspace controller restores open files from session snapshot', () {
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(
        editorFiles: const <String>[
          'main.styio',
          'lib.styio',
          'test.styio',
        ],
      ),
    );

    controller.restoreOpenFiles(
      const <String>[
        'lib.styio',
        'missing.styio',
        'test.styio',
        'lib.styio',
      ],
      activeFilePath: 'test.styio',
    );

    expect(controller.activeFilePath, 'test.styio');
    expect(controller.openFilePaths, <String>['lib.styio', 'test.styio']);
  });

  test('workspace controller registers created files without opening them', () {
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(
        editorFiles: const <String>['main.styio'],
      ),
    );

    controller.registerFile('generated.styio');

    expect(controller.files, <String>['main.styio', 'generated.styio']);
    expect(controller.activeFilePath, 'main.styio');
    expect(controller.openFilePaths, <String>['main.styio']);
  });

  test('workspace controller unregisters deleted inactive open files', () {
    final controller = WorkspaceController(
      projectSnapshot: _projectGraph(
        editorFiles: const <String>['main.styio', 'lib.styio'],
      ),
    );

    controller
      ..openFile('lib.styio')
      ..unregisterFile('main.styio');

    expect(controller.files, <String>['lib.styio']);
    expect(controller.activeFilePath, 'lib.styio');
    expect(controller.openFilePaths, <String>['lib.styio']);
  });
}

ProjectGraphSnapshot _projectGraph({
  required List<String> editorFiles,
  List<ProjectTargetDescriptor> targets = const <ProjectTargetDescriptor>[],
}) {
  return ProjectGraphSnapshot(
    id: 'fixture://project',
    title: 'fixture',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/fixture',
    workspaceMembers: const <String>[],
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: targets,
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
