import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/deployment_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

import 'fake_pafio_cli.dart';

void main() {
  test('deployment adapter executes published pafio pack', () async {
    final tempRoot = await _createWorkspaceFixture();
    addTearDown(() => tempRoot.delete(recursive: true));

    final adapter = await createDeploymentAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final result = await adapter.packProject(
      projectGraph: _projectGraphFor(tempRoot.path),
      packageName: 'demo/app',
    );

    expect(result.succeeded, isTrue);
    expect(result.command, 'pack');
    expect(result.payload?['package'], 'demo/app');
    expect(result.payload?['archive_path'], contains('dist'));
    expect(result.statusMessage, contains('wrote source package'));
  });

  test('deployment adapter executes publish preflight through pafio', () async {
    final tempRoot = await _createWorkspaceFixture();
    addTearDown(() => tempRoot.delete(recursive: true));

    final adapter = await createDeploymentAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final result = await adapter.preparePublish(
      projectGraph: _projectGraphFor(tempRoot.path),
      packageName: 'demo/app',
    );

    expect(result.succeeded, isTrue);
    expect(result.command, 'publish');
    expect(result.payload?['package'], 'demo/app');
    expect(result.payload?['archive_path'], contains('dist'));
    expect(result.statusMessage, contains('prepared publish candidate'));
  });

  test(
    'deployment adapter auto-selects the only publish-ready package',
    () async {
      final tempRoot = await _createWorkspaceFixture();
      addTearDown(() => tempRoot.delete(recursive: true));

      final adapter = await createDeploymentAdapter(
        platformTarget: PlatformTarget.macos,
      );
      final result = await adapter.preparePublish(
        projectGraph: _projectGraphFor(
          tempRoot.path,
          packageDistribution: const PackageDistributionSnapshot(
            schemaVersion: 1,
            packages: <PackageDistributionPackageSnapshot>[
              PackageDistributionPackageSnapshot(
                packageName: 'demo/app',
                manifestPath: '/workspace/demo/pafio.toml',
                publishEnabled: true,
                publishReady: true,
              ),
            ],
            publishablePackages: 1,
            blockedPackages: 0,
          ),
        ),
      );

      expect(result.succeeded, isTrue);
      expect(result.payload?['package'], 'demo/app');
    },
  );

  test('deployment adapter executes registry publish through pafio', () async {
    final tempRoot = await _createWorkspaceFixture();
    addTearDown(() => tempRoot.delete(recursive: true));

    final adapter = await createDeploymentAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final result = await adapter.publishToRegistry(
      projectGraph: _projectGraphFor(tempRoot.path),
      registryRoot: '/registry/local',
      packageName: 'demo/app',
    );

    expect(result.succeeded, isTrue);
    expect(result.command, 'publish');
    expect(result.payload?['package'], 'demo/app');
    expect(result.payload?['registry_root'], '/registry/local');
    expect(result.payload?['archive_path'], contains('dist'));
    expect(result.statusMessage, contains('published package'));
  });

  test('deployment adapter blocks when no manifest is resolved', () async {
    final adapter = await createDeploymentAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final result = await adapter.packProject(
      projectGraph: ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/scratch',
        activeFilePath: '/workspace/scratch/main.styio',
        title: 'Scratch',
        notes: const <String>[],
      ),
    );

    expect(result.status, DeploymentCommandStatus.blocked);
    expect(result.statusMessage, contains('resolved pafio manifest path'));
  });

  test(
    'deployment adapter blocks publish when project graph has no publish-ready package',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_deployment_adapter_blocked_publish_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync(
          '[package]\nname = "demo/app"\nversion = "0.1.0"\n',
        );

      final adapter = await createDeploymentAdapter(
        platformTarget: PlatformTarget.macos,
      );
      final result = await adapter.preparePublish(
        projectGraph: _projectGraphFor(
          tempRoot.path,
          packageDistribution: const PackageDistributionSnapshot(
            schemaVersion: 1,
            packages: <PackageDistributionPackageSnapshot>[
              PackageDistributionPackageSnapshot(
                packageName: 'demo/app',
                manifestPath: '/workspace/demo/pafio.toml',
                publishEnabled: false,
                publishReady: false,
                blockingReasons: <String>['package publish = false'],
              ),
            ],
            publishablePackages: 0,
            blockedPackages: 1,
          ),
        ),
      );

      expect(result.status, DeploymentCommandStatus.blocked);
      expect(result.statusMessage, contains('No publish-ready package'));
      expect(result.statusMessage, contains('package publish = false'));
    },
  );
}

Future<Directory> _createWorkspaceFixture() async {
  final tempRoot = await Directory.systemTemp.createTemp(
    'vityo_deployment_adapter_test_',
  );
  final manifestPath = '${tempRoot.path}${Platform.pathSeparator}pafio.toml';
  File(manifestPath)
    ..createSync(recursive: true)
    ..writeAsStringSync('[package]\nname = "demo/app"\nversion = "0.1.0"\n');

  await writeFakePafioCli(
    workspaceRoot: tempRoot,
    pythonSource: '''#!/usr/bin/env python3
import json, sys

args = sys.argv[1:]

if args[:2] == ['--json', 'pack'] and '--manifest-path' in args and '--package' in args:
    print(json.dumps({
        'command': 'pack',
        'message': 'wrote source package: /workspace/demo/dist/app-0.1.0.tar',
        'package': args[args.index('--package') + 1],
        'archive_path': '/workspace/demo/dist/app-0.1.0.tar',
    }))
    raise SystemExit(0)

if args[:2] == ['--json', 'publish'] and '--dry-run' in args and '--manifest-path' in args and '--package' in args:
    print(json.dumps({
        'command': 'publish',
        'mode': 'dry-run',
        'message': 'prepared publish candidate: /workspace/demo/dist/app-0.1.0.tar',
        'package': args[args.index('--package') + 1],
        'archive_path': '/workspace/demo/dist/app-0.1.0.tar',
    }))
    raise SystemExit(0)

if args[:2] == ['--json', 'publish'] and '--registry' in args and '--manifest-path' in args and '--package' in args:
    print(json.dumps({
        'command': 'publish',
        'mode': 'publish',
        'message': 'published package into local filesystem registry: /registry/local/entries/demo-app.json',
        'package': args[args.index('--package') + 1],
        'registry_root': args[args.index('--registry') + 1],
        'archive_path': '/workspace/demo/dist/app-0.1.0.tar',
    }))
    raise SystemExit(0)

print(json.dumps({
    'error': 'unexpected args',
    'args': args,
}), file=sys.stderr)
raise SystemExit(64)
''',
  );
  return tempRoot;
}

ProjectGraphSnapshot _projectGraphFor(
  String workspaceRoot, {
  PackageDistributionSnapshot? packageDistribution,
}) {
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
    packageDistribution: packageDistribution,
    notes: const <String>[],
  );
}
