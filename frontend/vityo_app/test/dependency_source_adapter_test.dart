import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/dependency_source_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

import 'fake_spio_cli.dart';

void main() {
  test('dependency source adapter executes published spio fetch', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_dependency_source_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));

    File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('[package]\nname = "demo/app"\nversion = "0.1.0"\n');
    final manifestPath = '${tempRoot.path}${Platform.pathSeparator}spio.toml';
    await writeFakeSpioCli(
      workspaceRoot: tempRoot,
      pythonSource: '''#!/usr/bin/env python3
import json, os, sys

expected_manifest = os.path.normpath(${jsonEncode(manifestPath)})
args = sys.argv[1:]
if (
    len(args) == 6
    and args[:3] == ['--json', 'fetch', '--manifest-path']
    and os.path.normpath(args[3]) == expected_manifest
    and args[4:] == ['--locked', '--offline']
):
    print(json.dumps({
        'command': 'fetch',
        'message': 'materialized dependency sources under local spio cache',
        'packages': 3,
        'git_packages': 1,
        'registry_packages': 1,
        'locked': True,
        'offline': True,
    }))
    raise SystemExit(0)

raise SystemExit(64)
''',
    );

    final adapter = await createDependencySourceAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final result = await adapter.fetchDependencies(
      projectGraph: _projectGraphFor(tempRoot.path),
      locked: true,
      offline: true,
    );

    expect(result.succeeded, isTrue);
    expect(result.command, 'fetch');
    expect(result.payload?['packages'], 3);
    expect(result.payload?['offline'], isTrue);
  });

  test('dependency source adapter blocks vendor without manifest', () async {
    final adapter = await createDependencySourceAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final result = await adapter.vendorDependencies(
      projectGraph: ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/scratch',
        activeFilePath: '/workspace/scratch/main.styio',
        title: 'Scratch',
        notes: const <String>[],
      ),
    );

    expect(result.status, DependencySourceCommandStatus.blocked);
    expect(result.statusMessage, contains('requires a resolved spio manifest'));
  });
}

ProjectGraphSnapshot _projectGraphFor(String workspaceRoot) {
  final manifestPath = '$workspaceRoot${Platform.pathSeparator}spio.toml';
  return ProjectGraphSnapshot(
    id: manifestPath,
    title: 'demo/app',
    kind: ProjectKind.package,
    workspaceRoot: workspaceRoot,
    workspaceMembers: const <String>[],
    manifestPath: manifestPath,
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: <String>[
      '$workspaceRoot${Platform.pathSeparator}src${Platform.pathSeparator}main.styio',
    ],
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.unavailable,
      detail: 'No toolchain resolved for this test fixture.',
    ),
    lockState: ProjectLockState.unknown,
    vendorState: ProjectVendorState.missing,
    notes: const <String>[],
  );
}
