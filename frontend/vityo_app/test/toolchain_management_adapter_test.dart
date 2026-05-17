import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/backend_toolchain/toolchain_management_adapter.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('toolchain management adapter executes published spio tool use', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_toolchain_manager_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));

    File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('[package]\nname = "demo/app"\nversion = "0.1.0"\n');
    final spioBinary = File(
      '${tempRoot.path}${Platform.pathSeparator}.spio${Platform.pathSeparator}bin${Platform.pathSeparator}spio',
    );
    spioBinary.createSync(recursive: true);
    spioBinary.writeAsStringSync('''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['--json', 'tool', 'use', '--version', '0.0.5', '--channel', 'stable']:
    print(json.dumps({
        'command': 'tool use',
        'message': 'activated managed styio compiler: /workspace/.spio/tools/styio/current/bin/styio',
        'compiler_version': '0.0.5',
        'channel': 'stable',
    }))
    raise SystemExit(0)

raise SystemExit(64)
''');
    Process.runSync('chmod', <String>['+x', spioBinary.path]);

    final adapter = await createToolchainManagementAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final result = await adapter.useManagedCompiler(
      projectGraph: _projectGraphFor(tempRoot.path),
      compilerVersion: '0.0.5',
      channel: 'stable',
    );

    expect(result.succeeded, isTrue);
    expect(result.command, 'tool use');
    expect(result.payload?['compiler_version'], '0.0.5');
    expect(result.statusMessage, contains('activated managed styio compiler'));
  });

  test('toolchain pin blocks when no manifest is resolved', () async {
    final adapter = await createToolchainManagementAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final result = await adapter.pinManagedCompiler(
      projectGraph: ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/scratch',
        activeFilePath: '/workspace/scratch/main.styio',
        title: 'Scratch',
        notes: const <String>[],
      ),
      compilerVersion: '0.0.5',
      channel: 'stable',
    );

    expect(result.status, ToolchainCommandStatus.blocked);
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
