import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/dependency_source_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/pafio_cli_discovery.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';

import 'fake_pafio_cli.dart';

import 'backend_provider_test_support.dart';

void main() {
  test('dependency source adapter executes published pafio sync', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_dependency_source_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));

    File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('[package]\nname = "demo/app"\nversion = "0.1.0"\n');
    final manifestPath = '${tempRoot.path}${Platform.pathSeparator}pafio.toml';
    final pafio = await writeFakePafioCli(
      workspaceRoot: tempRoot,
      pythonSource: '''#!/usr/bin/env python3
import json, os, sys

expected_manifest = os.path.normpath(${jsonEncode(manifestPath)})
args = sys.argv[1:]
if args == ['--version']:
    print('pafio test')
    raise SystemExit(0)
if (
    len(args) == 6
    and args[:3] == ['--json', 'sync', '--manifest-path']
    and os.path.normpath(args[3]) == expected_manifest
    and args[4:] == ['--locked', '--offline']
):
    print(json.dumps({
        'command': 'sync',
        'message': 'materialized dependency sources under local pafio cache',
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
    debugOverridePafioDiscoveryEnvironment(<String, String>{
      ...Platform.environment,
      'VITYO_PAFIO_BIN': pafio.path,
    });
    addTearDown(() => debugOverridePafioDiscoveryEnvironment(null));

    final adapter = await createDependencySourceAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final result = await adapter.syncDependencies(
      projectGraph: _projectGraphFor(tempRoot.path),
      locked: true,
      offline: true,
    );

    expect(result.succeeded, isTrue);
    expect(result.command, 'sync');
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
    expect(result.statusMessage, contains('requires a resolved pafio manifest'));
  });
}

ProjectGraphSnapshot _projectGraphFor(String workspaceRoot) {
  final manifestPath = '$workspaceRoot${Platform.pathSeparator}pafio.toml';
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
