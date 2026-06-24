import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/backend_toolchain/project_workflow_selection.dart';

void main() {
  test('project workflow selection maps explicit target kinds', () {
    final testTarget = _target(
      kind: ProjectTargetKind.test,
      name: 'unit',
      filePath: '/workspace/demo/test/unit.styio',
    );
    final libTarget = _target(
      kind: ProjectTargetKind.lib,
      name: 'demo',
      filePath: '/workspace/demo/src/lib.styio',
    );
    final binTarget = _target(
      kind: ProjectTargetKind.bin,
      name: 'cli',
      filePath: '/workspace/demo/src/main.styio',
    );
    final graph = _graph(targets: <ProjectTargetDescriptor>[
      testTarget,
      libTarget,
      binTarget,
    ]);

    final testWorkflow = selectProjectWorkflow(
      projectGraph: graph,
      activeFilePath: testTarget.filePath,
    );
    final libWorkflow = selectProjectWorkflow(
      projectGraph: graph,
      activeFilePath: libTarget.filePath,
    );
    final binWorkflow = selectProjectWorkflow(
      projectGraph: graph,
      activeFilePath: binTarget.filePath,
    );

    expect(testWorkflow.command, 'test');
    expect(testWorkflow.kind, 'test');
    expect(
      testWorkflow.args,
      <String>['--package', 'demo/app', '--test', 'unit'],
    );
    expect(testWorkflow.targetName, 'unit');
    expect(testWorkflow.targetKind, 'test');
    expect(
      testWorkflow.successMessage,
      'Project test target completed through spio.',
    );

    expect(libWorkflow.command, 'build');
    expect(libWorkflow.kind, 'build');
    expect(libWorkflow.args, <String>['--package', 'demo/app', '--lib']);
    expect(libWorkflow.targetKind, 'lib');

    expect(binWorkflow.command, 'run');
    expect(binWorkflow.kind, 'run');
    expect(binWorkflow.args, <String>['--package', 'demo/app', '--bin', 'cli']);
    expect(binWorkflow.targetName, 'cli');
    expect(binWorkflow.targetKind, 'bin');
  });

  test('project workflow selection falls back by package and target count', () {
    final helperGraph = _graph(
      targets: <ProjectTargetDescriptor>[
        _target(
          kind: ProjectTargetKind.bin,
          name: 'cli',
          filePath: '/workspace/demo/src/main.styio',
        ),
      ],
    );
    final packageBuildGraph = _graph(targets: <ProjectTargetDescriptor>[
      _target(
        kind: ProjectTargetKind.bin,
        name: 'cli',
        filePath: '/workspace/demo/src/main.styio',
      ),
      _target(
        kind: ProjectTargetKind.test,
        name: 'unit',
        filePath: '/workspace/demo/test/unit.styio',
      ),
    ]);
    final projectBuildGraph = _graph(
      targets: const <ProjectTargetDescriptor>[],
      packages: const <ProjectPackageSnapshot>[],
    );

    final singlePackageTarget = selectProjectWorkflow(
      projectGraph: helperGraph,
      activeFilePath: '/workspace/demo/src/helper.styio',
    );
    final singleProjectTarget = selectProjectWorkflow(
      projectGraph: helperGraph,
      activeFilePath: '/workspace/other/src/helper.styio',
    );
    final packageBuild = selectProjectWorkflow(
      projectGraph: packageBuildGraph,
      activeFilePath: '/workspace/demo/src/helper.styio',
    );
    final projectBuild = selectProjectWorkflow(
      projectGraph: projectBuildGraph,
      activeFilePath: 'relative/helper.styio',
    );

    expect(singlePackageTarget.command, 'run');
    expect(singlePackageTarget.targetName, 'cli');
    expect(singleProjectTarget.command, 'run');
    expect(singleProjectTarget.targetName, 'cli');

    expect(packageBuild.command, 'build');
    expect(packageBuild.kind, 'build');
    expect(packageBuild.args, <String>['--package', 'demo/app']);
    expect(packageBuild.packageName, 'demo/app');
    expect(
      packageBuild.successMessage,
      'Project package build completed through spio.',
    );

    expect(projectBuild.command, 'build');
    expect(projectBuild.args, isEmpty);
    expect(projectBuild.packageName, isNull);
    expect(projectBuild.successMessage, 'Project build completed through spio.');
  });

  test('project workflow selection exposes package helpers', () {
    final graph = _graph(targets: const <ProjectTargetDescriptor>[]);

    expect(packageArgs(''), isEmpty);
    expect(packageArgs('demo/app'), <String>['--package', 'demo/app']);
    expect(
      packageNameForPath(
        projectGraph: graph,
        activeFilePath: '/workspace/demo',
      ),
      'demo/app',
    );
    expect(
      packageNameForPath(
        projectGraph: graph,
        activeFilePath: '/workspace/demo/src/main.styio',
      ),
      'demo/app',
    );
    expect(
      packageNameForPath(
        projectGraph: graph,
        activeFilePath: '/workspace/other/main.styio',
      ),
      isNull,
    );
    expect(
      packageNameForPath(
        projectGraph: graph,
        activeFilePath: r'C:\workspace\demo\src\main.styio',
      ),
      isNull,
    );
  });
}

ProjectTargetDescriptor _target({
  required ProjectTargetKind kind,
  required String name,
  required String filePath,
}) {
  return ProjectTargetDescriptor(
    id: 'demo/app:${kind.label}:$name',
    packageName: 'demo/app',
    kind: kind,
    name: name,
    filePath: filePath,
  );
}

ProjectGraphSnapshot _graph({
  required List<ProjectTargetDescriptor> targets,
  List<ProjectPackageSnapshot>? packages,
}) {
  return ProjectGraphSnapshot(
    id: '/workspace/demo/spio.toml',
    title: 'demo/app',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/demo/spio.toml',
    packages:
        packages ??
        <ProjectPackageSnapshot>[
          ProjectPackageSnapshot(
            packageName: 'demo/app',
            version: '0.1.0',
            rootPath: '/workspace/demo',
            manifestPath: '/workspace/demo/spio.toml',
            targets: targets,
          ),
        ],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: targets,
    editorFiles: targets
        .map((target) => target.filePath)
        .toList(growable: false),
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'project pin',
    ),
    lockState: ProjectLockState.missing,
    vendorState: ProjectVendorState.missing,
    notes: const <String>[],
  );
}
