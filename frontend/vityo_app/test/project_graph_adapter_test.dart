import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_adapter_io.dart'
    show debugOverrideProjectGraphEnvironment;
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

import 'fake_spio_cli.dart';

void main() {
  test('project graph adapter discovers canonical spio package files', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_project_graph_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));

    final previousCurrentDirectory = Directory.current;
    addTearDown(() => Directory.current = previousCurrentDirectory);

    File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[workspace]
members = ["packages/render-kit"]

[toolchain]
channel = "stable"

[dependencies]
render-kit = { path = "packages/render-kit" }
palette = "^2.0.0"

[dev-dependencies]
assertions = "^1.0.0"

[lib]
path = "src/lib.styio"

[[bin]]
name = "demo"
path = "src/main.styio"

[[test]]
name = "render-flow"
path = "tests/render_flow.styio"
''');
    File('${tempRoot.path}${Platform.pathSeparator}spio.lock')
      ..createSync(recursive: true)
      ..writeAsStringSync('# lock');
    File('${tempRoot.path}${Platform.pathSeparator}spio-toolchain.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('channel = "stable"\nversion = "0.0.1"\n');
    File('${tempRoot.path}${Platform.pathSeparator}styio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('target = "preview"\n');
    Directory(
      '${tempRoot.path}${Platform.pathSeparator}.spio${Platform.pathSeparator}vendor',
    ).createSync(recursive: true);
    Directory(
      '${tempRoot.path}${Platform.pathSeparator}.spio${Platform.pathSeparator}build',
    ).createSync(recursive: true);
    Directory(
      '${tempRoot.path}${Platform.pathSeparator}src',
    ).createSync(recursive: true);
    Directory(
      '${tempRoot.path}${Platform.pathSeparator}packages${Platform.pathSeparator}render-kit${Platform.pathSeparator}src',
    ).createSync(recursive: true);
    Directory(
      '${tempRoot.path}${Platform.pathSeparator}tests',
    ).createSync(recursive: true);
    File(
        '${tempRoot.path}${Platform.pathSeparator}packages${Platform.pathSeparator}render-kit${Platform.pathSeparator}spio.toml',
      )
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[package]
name = "demo/render-kit"
version = "0.2.0"

[lib]
path = "src/lib.styio"
''');

    Directory.current = tempRoot;

    final adapter = await createProjectGraphAdapter(
      platformTarget: PlatformTarget.macos,
    );
    final graph = await adapter.loadProjectGraph();

    expect(graph.kind, ProjectKind.combinedRoot);
    expect(graph.manifestPath, endsWith('${Platform.pathSeparator}spio.toml'));
    expect(graph.lockState, ProjectLockState.unknown);
    expect(graph.vendorState, ProjectVendorState.present);
    expect(graph.toolchain.source, ToolchainResolutionSource.projectPin);
    expect(graph.toolchain.channel, 'stable');
    expect(graph.toolchain.version, '0.0.1');
    expect(
      graph.toolchainPinPath,
      endsWith('${Platform.pathSeparator}spio-toolchain.toml'),
    );
    expect(
      graph.styioConfigPath,
      endsWith('${Platform.pathSeparator}styio.toml'),
    );
    expect(graph.packages.map((package) => package.packageName).toSet(), {
      'demo/app',
      'demo/render-kit',
    });
    expect(graph.workspaceMembers, ['packages/render-kit']);
    expect(graph.workspaceMemberCount, 1);
    expect(graph.packages.length, 2);
    expect(graph.dependencyCount, 3);
    expect(
      graph.packages
          .firstWhere((package) => package.packageName == 'demo/app')
          .publishEnabled,
      isFalse,
    );
    expect(
      graph.dependencies
          .where((dependency) => dependency.sourcePackageName == 'demo/app')
          .map((dependency) => dependency.dependencyName)
          .toSet(),
      {'render-kit', 'palette', 'assertions'},
    );
    final runtimeWorkspaceDependency = graph.dependencies.firstWhere(
      (dependency) => dependency.dependencyName == 'render-kit',
    );
    expect(
      runtimeWorkspaceDependency.sourceKind,
      ProjectDependencySourceKind.path,
    );
    expect(runtimeWorkspaceDependency.pathSource, 'packages/render-kit');
    expect(runtimeWorkspaceDependency.publishBlocking, isTrue);
    expect(graph.packageDistribution, isNotNull);
    expect(graph.packageDistribution?.blockedPackages, 2);
    expect(graph.sourceState, isNull);
    expect(graph.targets.length, 4);
    expect(graph.targets.map((target) => target.kind).toSet(), {
      ProjectTargetKind.lib,
      ProjectTargetKind.bin,
      ProjectTargetKind.test,
    });
  });

  test(
    'project graph adapter falls back to scratch mode without spio.toml',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_project_graph_scratch_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final previousCurrentDirectory = Directory.current;
      addTearDown(() => Directory.current = previousCurrentDirectory);

      Directory.current = tempRoot;

      final adapter = await createProjectGraphAdapter(
        platformTarget: PlatformTarget.linux,
      );
      final graph = await adapter.loadProjectGraph();

      expect(graph.kind, ProjectKind.scratch);
      expect(graph.manifestPath, isNull);
      expect(
        graph.editorFiles.single.endsWith(
          'scratch${Platform.pathSeparator}main.styio',
        ),
        isTrue,
      );
      expect(graph.notes, isNotEmpty);
    },
  );

  test(
    'project graph adapter applies project pin metadata in scratch mode',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_project_graph_scratch_pin_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final previousCurrentDirectory = Directory.current;
      addTearDown(() => Directory.current = previousCurrentDirectory);

      Directory('${tempRoot.path}${Platform.pathSeparator}.git').createSync();
      File('${tempRoot.path}${Platform.pathSeparator}spio-toolchain.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[toolchain]
channel = "nightly"
version = "2026.6.19"
''');
      final nested = Directory(
        '${tempRoot.path}${Platform.pathSeparator}tools${Platform.pathSeparator}scratch',
      )..createSync(recursive: true);

      Directory.current = nested;

      final adapter = await createProjectGraphAdapter(
        platformTarget: PlatformTarget.linux,
      );
      final graph = await adapter.loadProjectGraph();

      expect(graph.kind, ProjectKind.scratch);
      expect(graph.workspaceRoot, tempRoot.absolute.path);
      expect(graph.toolchain.source, ToolchainResolutionSource.projectPin);
      expect(
        graph.toolchain.detail,
        contains('Project toolchain pin is present'),
      );
      expect(
        graph.toolchain.pinPath,
        endsWith('${Platform.pathSeparator}spio-toolchain.toml'),
      );
    },
  );

  test(
    'project graph adapter infers workspace packages and dependency sources',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_project_graph_workspace_sources_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final previousCurrentDirectory = Directory.current;
      addTearDown(() => Directory.current = previousCurrentDirectory);

      File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[workspace]
members = ["packages/core", "packages/missing"]

[toolchain]
channel = "preview"
version = "0.9.0"
''');
      File(
          '${tempRoot.path}${Platform.pathSeparator}packages${Platform.pathSeparator}core${Platform.pathSeparator}spio.toml',
        )
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[package]
name = "demo/core"
version = "1.2.3"
publish = true

[dependencies]
workspace-kit = { workspace = true, package = "demo/workspace-kit" }
remote = { registry: "file:///registry", package = "demo/remote", version = "1.0.0" }
incomplete = { registry = "mirror" }
fallback = "^1.0.0"

[dev-dependencies]
tooling = { git: "https://git.example/demo/tooling.git", rev = "abc123", package = "demo/tooling" }
pinned = { version = "2.0.0" }
''');

      Directory.current = tempRoot;

      final adapter = await createProjectGraphAdapter(
        platformTarget: PlatformTarget.macos,
      );
      final graph = await adapter.loadProjectGraph();

      expect(graph.kind, ProjectKind.workspace);
      expect(graph.title, 'Workspace Project');
      expect(graph.workspaceMembers, ['packages/core', 'packages/missing']);
      expect(graph.packages.single.packageName, 'demo/core');
      expect(graph.packages.single.publishEnabled, isTrue);
      expect(graph.targets, isEmpty);
      expect(
        graph.editorFiles.single,
        endsWith('src${Platform.pathSeparator}main.styio'),
      );
      expect(graph.toolchain.source, ToolchainResolutionSource.unknown);
      expect(graph.toolchain.channel, 'preview');
      expect(graph.toolchain.version, '0.9.0');
      expect(graph.lockState, ProjectLockState.missing);
      expect(graph.vendorState, ProjectVendorState.missing);
      expect(graph.dependencyCount, 6);

      final dependenciesByName = {
        for (final dependency in graph.dependencies)
          dependency.dependencyName: dependency,
      };
      expect(
        dependenciesByName['workspace-kit']?.sourceKind,
        ProjectDependencySourceKind.path,
      );
      expect(dependenciesByName['workspace-kit']?.isWorkspaceReference, isTrue);
      expect(dependenciesByName['workspace-kit']?.requirement, 'workspace');
      expect(
        dependenciesByName['remote']?.sourceKind,
        ProjectDependencySourceKind.registry,
      );
      expect(dependenciesByName['remote']?.registryRoot, 'file:///registry');
      expect(dependenciesByName['remote']?.publishBlocking, isFalse);
      expect(dependenciesByName['incomplete']?.publishBlocking, isTrue);
      expect(
        dependenciesByName['tooling']?.sourceKind,
        ProjectDependencySourceKind.git,
      );
      expect(
        dependenciesByName['tooling']?.gitSource,
        'https://git.example/demo/tooling.git',
      );
      expect(dependenciesByName['tooling']?.gitRevision, 'abc123');
      expect(
        dependenciesByName['pinned']?.sourceKind,
        ProjectDependencySourceKind.unknown,
      );
      expect(dependenciesByName['pinned']?.requestedVersion, '2.0.0');

      final distribution = graph.packageDistribution;
      expect(distribution, isNotNull);
      expect(distribution?.publishablePackages, 0);
      expect(distribution?.blockedPackages, 1);
      final packageDistribution = distribution!.packages.single;
      expect(packageDistribution.runtimeRegistryDependencies, 2);
      expect(packageDistribution.runtimePathDependencies, 1);
      expect(packageDistribution.devGitDependencies, 1);
      expect(
        packageDistribution.blockingReasons.where(
          (reason) => reason.contains('workspace-kit'),
        ),
        isNotEmpty,
      );
      expect(
        distribution.registrySources
            .firstWhere((source) => source.registryRoot == 'file:///registry')
            .transport,
        'file',
      );
    },
  );

  test(
    'project graph adapter prefers published spio payload when available',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_project_graph_payload_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final previousCurrentDirectory = Directory.current;
      addTearDown(() => Directory.current = previousCurrentDirectory);

      File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[toolchain]
channel = "stable"
implicit-std = true

[[bin]]
name = "demo"
path = "src/main.styio"
''');
      await writeFakeSpioCli(
        workspaceRoot: tempRoot,
        pythonSource: '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['machine-info', '--json']:
    print(json.dumps({
        'tool': 'spio',
        'supported_contract_versions': {
            'project_graph': [1],
            'toolchain_state': [1],
        },
    }))
    raise SystemExit(0)

if len(sys.argv) >= 4 and sys.argv[1] == 'project-graph' and sys.argv[2] == '--json':
    print(json.dumps({
        'command': 'project-graph',
        'schema_version': 1,
        'id': '/workspace/demo/spio.toml',
        'title': 'demo/app',
        'kind': 'package',
        'workspace_root': '/workspace/demo',
        'workspace_members': [],
        'manifest_path': '/workspace/demo/spio.toml',
        'lockfile_path': '/workspace/demo/spio.lock',
        'toolchain_pin_path': '/workspace/demo/spio-toolchain.toml',
        'styio_config_path': None,
        'vendor_root': '/workspace/demo/.spio/vendor',
        'build_root': '/workspace/demo/.spio/build',
        'packages': [{
            'package_name': 'demo/app',
            'version': '0.1.0',
            'root_path': '/workspace/demo',
            'manifest_path': '/workspace/demo/spio.toml',
            'publish_enabled': True,
            'targets': [{
                'id': 'demo/app:bin:demo',
                'package_name': 'demo/app',
                'kind': 'bin',
                'name': 'demo',
                'file_path': '/workspace/demo/src/main.styio',
            }],
            'dependencies': [{
                'source_package_name': 'demo/app',
                'dependency_name': 'util',
                'kind': 'runtime',
                'requirement': 'registry:https://packages.example.test@0.2.0',
                'is_workspace_reference': False,
                'source_kind': 'registry',
                'package': 'demo/util',
                'path': None,
                'git': None,
                'rev': None,
                'registry': 'https://packages.example.test',
                'version': '0.2.0',
                'publish_blocking': False,
            }],
            'is_workspace_member': False,
        }],
        'dependencies': [{
            'source_package_name': 'demo/app',
            'dependency_name': 'util',
            'kind': 'runtime',
            'requirement': 'registry:https://packages.example.test@0.2.0',
            'is_workspace_reference': False,
            'source_kind': 'registry',
            'package': 'demo/util',
            'path': None,
            'git': None,
            'rev': None,
            'registry': 'https://packages.example.test',
            'version': '0.2.0',
            'publish_blocking': False,
        }],
        'targets': [{
            'id': 'demo/app:bin:demo',
            'package_name': 'demo/app',
            'kind': 'bin',
            'name': 'demo',
            'file_path': '/workspace/demo/src/main.styio',
        }],
        'editor_files': ['/workspace/demo/src/main.styio'],
        'toolchain': {
            'source': 'project-pin',
            'detail': 'Project toolchain pin resolved to managed styio stable/0.0.1.',
            'pin_path': '/workspace/demo/spio-toolchain.toml',
            'channel': 'stable',
            'version': '0.0.1',
        },
        'lock_state': 'fresh',
        'vendor_state': 'present',
        'package_distribution': {
            'schema_version': 1,
            'packages': [{
                'package_name': 'demo/app',
                'manifest_path': '/workspace/demo/spio.toml',
                'publish_enabled': True,
                'publish_ready': True,
                'blocking_reasons': [],
                'runtime_registry_dependencies': 1,
                'runtime_path_dependencies': 0,
                'runtime_git_dependencies': 0,
                'dev_registry_dependencies': 0,
                'dev_path_dependencies': 0,
                'dev_git_dependencies': 0,
            }],
            'registry_sources': [{
                'registry_root': 'https://packages.example.test',
                'transport': 'https',
                'dependency_refs': 1,
                'packages': ['demo/app'],
            }],
            'publishable_packages': 1,
            'blocked_packages': 0,
        },
        'source_state': {
            'schema_version': 1,
            'spio_home': '/workspace/.spio',
            'declared_git_dependencies': 0,
            'declared_registry_dependencies': 1,
            'git_cache': {
                'repos_root': '/workspace/.spio/git/repos',
                'checkouts_root': '/workspace/.spio/git/checkouts',
                'repos_present': False,
                'checkouts_present': False,
            },
            'registry_cache': {
                'cache_root': '/workspace/.spio/registry',
                'index_root': '/workspace/.spio/registry/index',
                'blob_root': '/workspace/.spio/registry/blobs/sha256',
                'checkout_root': '/workspace/.spio/registry/checkouts',
                'index_present': True,
                'blobs_present': True,
                'checkouts_present': True,
            },
            'vendor': {
                'vendor_root': '/workspace/demo/.spio/vendor',
                'metadata_path': '/workspace/demo/.spio/vendor/spio-vendor.json',
                'vendor_present': True,
                'metadata_present': True,
                'git_snapshots': 0,
            },
        },
        'active_compiler': {
            'binary_path': '/toolchains/styio/bin/styio',
            'tool': 'styio',
            'compiler_version': '0.0.1',
            'channel': 'stable',
            'variant': 'full',
            'capabilities': ['machine_info_json', 'jsonl_diagnostics', 'single_file_entry'],
            'supported_contract_versions': {'compile_plan': [1]},
            'integration_phase': 'compile-plan-live',
            'supported_adapter_modes': ['cli'],
            'feature_flags': {'compile_plan_consumer': True},
        },
        'notes': ['Project graph loaded through published spio machine payload.'],
    }))
    raise SystemExit(0)

if len(sys.argv) >= 3 and sys.argv[1] == 'tool' and sys.argv[2] == 'status':
    print(json.dumps({
        'command': 'tool status',
        'schema_version': 1,
        'toolchain': {
            'source': 'project-pin',
            'detail': 'Project pin resolves to managed styio stable/0.0.1.',
            'pin_path': '/workspace/demo/spio-toolchain.toml',
            'channel': 'stable',
            'version': '0.0.1',
            'candidate_binary_path': '/workspace/.spio/tools/styio/stable/0.0.1/bin/styio',
        },
        'project_pin': {
            'path': '/workspace/demo/spio-toolchain.toml',
            'channel': 'stable',
            'version': '0.0.1',
            'install_root': '/workspace/.spio/tools/styio/stable/0.0.1',
            'install_binary_path': '/workspace/.spio/tools/styio/stable/0.0.1/bin/styio',
            'install_present': True,
        },
        'active_compiler': {
            'binary_path': '/toolchains/styio/bin/styio',
            'tool': 'styio',
            'compiler_version': '0.0.1',
            'channel': 'stable',
            'variant': 'full',
            'capabilities': ['machine_info_json', 'jsonl_diagnostics', 'single_file_entry'],
            'supported_contract_versions': {'compile_plan': [1]},
            'integration_phase': 'compile-plan-live',
            'supported_adapter_modes': ['cli'],
            'feature_flags': {'compile_plan_consumer': True},
        },
        'active_compiler_error': None,
        'current_compiler': {
            'binary_path': '/toolchains/styio-current/bin/styio',
            'tool': 'styio',
            'compiler_version': '0.0.2',
            'channel': 'stable',
            'variant': 'full',
            'capabilities': ['machine_info_json'],
            'supported_contract_versions': {'machine_info': [1]},
            'integration_phase': 'bootstrap-single-file',
            'supported_adapter_modes': ['cli'],
            'feature_flags': {},
        },
        'current_compiler_error': None,
        'managed_toolchains': {
            'spio_home': '/workspace/.spio',
            'current_binary': '/workspace/.spio/tools/styio/current/bin/styio',
            'current_metadata_path': '/workspace/.spio/tools/styio/current/install.json',
            'installed': [{
                'channel': 'stable',
                'compiler_version': '0.0.1',
                'install_root': '/workspace/.spio/tools/styio/stable/0.0.1',
                'install_binary_path': '/workspace/.spio/tools/styio/stable/0.0.1/bin/styio',
                'install_metadata_path': '/workspace/.spio/tools/styio/stable/0.0.1/install.json',
            }],
        },
        'notes': ['Toolchain state loaded through published spio machine payload.'],
    }))
    raise SystemExit(0)

raise SystemExit(64)
''',
      );

      Directory.current = tempRoot;

      final adapter = await createProjectGraphAdapter(
        platformTarget: PlatformTarget.macos,
      );
      final graph = await adapter.loadProjectGraph();

      expect(
        adapter.capabilitySnapshot.projectGraph.level,
        AdapterCapabilityLevel.available,
      );
      expect(graph.kind, ProjectKind.package);
      expect(graph.title, 'demo/app');
      expect(graph.lockState, ProjectLockState.fresh);
      expect(graph.vendorState, ProjectVendorState.present);
      expect(graph.toolchain.source, ToolchainResolutionSource.projectPin);
      expect(graph.toolchain.version, '0.0.1');
      expect(graph.activeCompiler?.supportsContract('compile_plan'), isTrue);
      expect(
        graph.notes.any(
          (note) => note.contains('published spio machine payload'),
        ),
        isTrue,
      );
      expect(graph.toolchainEnvironment, isNotNull);
      expect(graph.toolchainEnvironment?.projectPin?.installPresent, isTrue);
      expect(graph.toolchainEnvironment?.managedToolchains.installed.length, 1);
      expect(
        graph.toolchainEnvironment?.currentCompiler?.compilerVersion,
        '0.0.2',
      );
      expect(graph.packageDistribution, isNotNull);
      expect(graph.packageDistribution?.publishablePackages, 1);
      expect(
        graph.packageDistribution?.registrySources.single.registryRoot,
        'https://packages.example.test',
      );
      expect(graph.sourceState, isNotNull);
      expect(graph.sourceState?.spioHome, '/workspace/.spio');
      expect(graph.sourceState?.declaredRegistryDependencies, 1);
      expect(graph.sourceState?.registryCache.indexPresent, isTrue);
      expect(graph.sourceState?.vendor.metadataPresent, isTrue);
      expect(
        graph.dependencies.single.sourceKind,
        ProjectDependencySourceKind.registry,
      );
      expect(graph.dependencies.single.packageIdentity, 'demo/util');
    },
  );

  test(
    'project graph adapter surfaces published project graph payload failures',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_project_graph_failure_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final previousCurrentDirectory = Directory.current;
      addTearDown(() => Directory.current = previousCurrentDirectory);

      File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[toolchain]
channel = "stable"

[[bin]]
name = "demo"
path = "src/main.styio"
''');
      Directory(
        '${tempRoot.path}${Platform.pathSeparator}src',
      ).createSync(recursive: true);
      await writeFakeSpioCli(
        workspaceRoot: tempRoot,
        pythonSource: '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['machine-info', '--json']:
    print(json.dumps({
        'tool': 'spio',
        'supported_contract_versions': {
            'project_graph': [1],
            'toolchain_state': [1],
        },
    }))
    raise SystemExit(0)

args = sys.argv[1:]
if len(args) >= 2 and args[0] == 'project-graph' and args[1] == '--json':
    print('{broken')
    raise SystemExit(0)

if len(args) >= 3 and args[0] == 'tool' and args[1] == 'status':
    print(json.dumps({
        'command': 'tool status',
        'schema_version': 1,
        'toolchain': {
            'source': 'managed-current',
            'detail': 'Toolchain state stayed available for the failure fixture.',
            'channel': 'stable',
            'version': '0.0.1',
        },
        'managed_toolchains': {
            'spio_home': '/workspace/.spio',
            'installed': [],
        },
        'notes': ['Toolchain state loaded through published spio machine payload.'],
    }))
    raise SystemExit(0)

raise SystemExit(64)
''',
      );

      Directory.current = tempRoot;

      final adapter = await createProjectGraphAdapter(
        platformTarget: PlatformTarget.macos,
      );
      final graph = await adapter.loadProjectGraph();

      expect(
        adapter.capabilitySnapshot.projectGraph.level,
        AdapterCapabilityLevel.partial,
      );
      expect(
        adapter.capabilitySnapshot.projectGraph.detail,
        contains('project-graph'),
      );
      expect(graph.kind, ProjectKind.package);
      expect(graph.title, 'demo/app');
      expect(graph.hasProjectGraphPayloadFailure, isTrue);
      expect(
        graph.projectGraphPayloadFailure?.command,
        'spio project-graph --json',
      );
      expect(
        graph.projectGraphPayloadFailure?.detail,
        contains('invalid JSON'),
      );
      expect(graph.toolchainEnvironment, isNotNull);
      expect(
        graph.notes.any((note) => note.contains('Published payload failure')),
        isTrue,
      );
    },
  );

  test(
    'project graph adapter surfaces published toolchain-state payload failures',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_toolchain_state_failure_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final previousCurrentDirectory = Directory.current;
      addTearDown(() => Directory.current = previousCurrentDirectory);

      File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[toolchain]
channel = "stable"

[[bin]]
name = "demo"
path = "src/main.styio"
''');
      await writeFakeSpioCli(
        workspaceRoot: tempRoot,
        pythonSource: '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['machine-info', '--json']:
    print(json.dumps({
        'tool': 'spio',
        'supported_contract_versions': {
            'project_graph': [1],
            'toolchain_state': [1],
        },
    }))
    raise SystemExit(0)

args = sys.argv[1:]
if len(args) >= 2 and args[0] == 'project-graph' and args[1] == '--json':
    print(json.dumps({
        'command': 'project-graph',
        'schema_version': 1,
        'id': '/workspace/demo/spio.toml',
        'title': 'demo/app',
        'kind': 'package',
        'workspace_root': '/workspace/demo',
        'workspace_members': [],
        'manifest_path': '/workspace/demo/spio.toml',
        'lockfile_path': '/workspace/demo/spio.lock',
        'toolchain_pin_path': '/workspace/demo/spio-toolchain.toml',
        'vendor_root': '/workspace/demo/.spio/vendor',
        'build_root': '/workspace/demo/.spio/build',
        'packages': [{
            'package_name': 'demo/app',
            'version': '0.1.0',
            'root_path': '/workspace/demo',
            'manifest_path': '/workspace/demo/spio.toml',
            'publish_enabled': True,
            'targets': [{
                'id': 'demo/app:bin:demo',
                'package_name': 'demo/app',
                'kind': 'bin',
                'name': 'demo',
                'file_path': '/workspace/demo/src/main.styio',
            }],
            'dependencies': [],
            'is_workspace_member': False,
        }],
        'dependencies': [],
        'targets': [{
            'id': 'demo/app:bin:demo',
            'package_name': 'demo/app',
            'kind': 'bin',
            'name': 'demo',
            'file_path': '/workspace/demo/src/main.styio',
        }],
        'editor_files': ['/workspace/demo/src/main.styio'],
        'toolchain': {
            'source': 'project-pin',
            'detail': 'Project graph still carries redundant toolchain metadata.',
            'pin_path': '/workspace/demo/spio-toolchain.toml',
            'channel': 'stable',
            'version': '0.0.1',
        },
        'lock_state': 'fresh',
        'vendor_state': 'present',
        'managed_toolchains': {
            'spio_home': '/workspace/.spio',
            'installed': [],
        },
    }))
    raise SystemExit(0)

if len(args) >= 3 and args[0] == 'tool' and args[1] == 'status':
    print('{broken')
    raise SystemExit(0)

raise SystemExit(64)
''',
      );

      Directory.current = tempRoot;

      final adapter = await createProjectGraphAdapter(
        platformTarget: PlatformTarget.macos,
      );
      final graph = await adapter.loadProjectGraph();

      expect(
        adapter.capabilitySnapshot.projectGraph.level,
        AdapterCapabilityLevel.partial,
      );
      expect(
        adapter.capabilitySnapshot.projectGraph.detail,
        contains('toolchain-state'),
      );
      expect(graph.kind, ProjectKind.package);
      expect(graph.title, 'demo/app');
      expect(graph.hasToolchainStatePayloadFailure, isTrue);
      expect(
        graph.toolchainStatePayloadFailure?.command,
        'spio tool status --json',
      );
      expect(
        graph.toolchainStatePayloadFailure?.detail,
        contains('invalid JSON'),
      );
      expect(graph.toolchainEnvironment, isNotNull);
      expect(
        graph.toolchainEnvironment?.toolchain.source,
        ToolchainResolutionSource.projectPin,
      );
      expect(
        graph.notes.any((note) => note.contains('Published payload failure')),
        isTrue,
      );
    },
  );

  test(
    'project graph adapter forwards VITYO_STYIO_BIN into published manifest reads',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_project_graph_override_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final previousCurrentDirectory = Directory.current;
      addTearDown(() => Directory.current = previousCurrentDirectory);
      addTearDown(() => debugOverrideProjectGraphEnvironment(null));

      File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[toolchain]
channel = "stable"

[[bin]]
name = "demo"
path = "src/main.styio"
''');

      final styioBinary = await writeFakePythonCli(
        directory: Directory(
          '${tempRoot.path}${Platform.pathSeparator}toolchains',
        ),
        executableName: 'override-styio',
        pythonSource: '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['--machine-info=json']:
    print(json.dumps({
        'tool': 'styio',
        'compiler_version': '9.9.9',
        'channel': 'override',
        'variant': 'full',
        'capabilities': ['machine_info_json', 'jsonl_diagnostics', 'single_file_entry'],
        'supported_contract_versions': {'compile_plan': [1]},
        'active_integration_phase': 'compile-plan-live',
        'supported_adapter_modes': ['cli'],
        'feature_flags': {'compile_plan_consumer': True},
    }))
    raise SystemExit(0)

raise SystemExit(64)
''',
      );

      await writeFakeSpioCli(
        workspaceRoot: tempRoot,
        pythonSource:
            '''#!/usr/bin/env python3
import json, sys

override = ${jsonEncode(styioBinary.path)}

def override_applied(args):
    if '--styio-bin' not in args:
        return False
    index = args.index('--styio-bin')
    return index + 1 < len(args) and args[index + 1] == override

if sys.argv[1:] == ['machine-info', '--json']:
    print(json.dumps({
        'tool': 'spio',
        'supported_contract_versions': {
            'project_graph': [1],
            'toolchain_state': [1],
        },
    }))
    raise SystemExit(0)

args = sys.argv[1:]
if len(args) >= 4 and args[0] == 'project-graph' and args[1] == '--json':
    if not override_applied(args):
        raise SystemExit(64)
    print(json.dumps({
        'command': 'project-graph',
        'schema_version': 1,
        'id': '/workspace/demo/spio.toml',
        'title': 'demo/app',
        'kind': 'package',
        'workspace_root': '/workspace/demo',
        'workspace_members': [],
        'manifest_path': '/workspace/demo/spio.toml',
        'lockfile_path': '/workspace/demo/spio.lock',
        'vendor_root': '/workspace/demo/.spio/vendor',
        'build_root': '/workspace/demo/.spio/build',
        'packages': [{
            'package_name': 'demo/app',
            'version': '0.1.0',
            'root_path': '/workspace/demo',
            'manifest_path': '/workspace/demo/spio.toml',
            'publish_enabled': True,
            'targets': [{
                'id': 'demo/app:bin:demo',
                'package_name': 'demo/app',
                'kind': 'bin',
                'name': 'demo',
                'file_path': '/workspace/demo/src/main.styio',
            }],
            'dependencies': [],
            'is_workspace_member': False,
        }],
        'dependencies': [],
        'targets': [{
            'id': 'demo/app:bin:demo',
            'package_name': 'demo/app',
            'kind': 'bin',
            'name': 'demo',
            'file_path': '/workspace/demo/src/main.styio',
        }],
        'editor_files': ['/workspace/demo/src/main.styio'],
        'toolchain': {
            'source': 'environment',
            'detail': 'Project graph consumed the styio override from VITYO_STYIO_BIN.',
            'channel': 'override',
            'version': '9.9.9',
        },
        'lock_state': 'unknown',
        'vendor_state': 'missing',
        'active_compiler': {
            'binary_path': override,
            'tool': 'styio',
            'compiler_version': '9.9.9',
            'channel': 'override',
            'variant': 'full',
            'capabilities': ['machine_info_json', 'jsonl_diagnostics', 'single_file_entry'],
            'supported_contract_versions': {'compile_plan': [1]},
            'integration_phase': 'compile-plan-live',
            'supported_adapter_modes': ['cli'],
            'feature_flags': {'compile_plan_consumer': True},
        },
        'notes': ['Project graph loaded through published spio machine payload with override.'],
    }))
    raise SystemExit(0)

if len(args) >= 3 and args[0] == 'tool' and args[1] == 'status':
    if not override_applied(args):
        raise SystemExit(64)
    print(json.dumps({
        'command': 'tool status',
        'schema_version': 1,
        'toolchain': {
            'source': 'environment',
            'detail': 'Tool status consumed the styio override from VITYO_STYIO_BIN.',
            'channel': 'override',
            'version': '9.9.9',
            'candidate_binary_path': override,
        },
        'active_compiler': {
            'binary_path': override,
            'tool': 'styio',
            'compiler_version': '9.9.9',
            'channel': 'override',
            'variant': 'full',
            'capabilities': ['machine_info_json', 'jsonl_diagnostics', 'single_file_entry'],
            'supported_contract_versions': {'compile_plan': [1]},
            'integration_phase': 'compile-plan-live',
            'supported_adapter_modes': ['cli'],
            'feature_flags': {'compile_plan_consumer': True},
        },
        'managed_toolchains': {
            'spio_home': '/workspace/.spio',
            'installed': [],
        },
        'notes': ['Toolchain state loaded through published spio machine payload with override.'],
    }))
    raise SystemExit(0)

raise SystemExit(64)
''',
      );

      debugOverrideProjectGraphEnvironment(
        Map<String, String>.from(Platform.environment)
          ..['VITYO_STYIO_BIN'] = styioBinary.path,
      );
      Directory.current = tempRoot;

      final adapter = await createProjectGraphAdapter(
        platformTarget: PlatformTarget.macos,
      );
      final graph = await adapter.loadProjectGraph();

      expect(graph.kind, ProjectKind.package);
      expect(graph.toolchain.source, ToolchainResolutionSource.environment);
      expect(graph.toolchain.version, '9.9.9');
      expect(graph.activeCompiler?.binaryPath, styioBinary.path);
      expect(graph.activeCompiler?.channel, 'override');
      expect(graph.toolchainEnvironment?.candidateBinaryPath, styioBinary.path);
      expect(
        graph.toolchainEnvironment?.toolchain.source,
        ToolchainResolutionSource.environment,
      );
      expect(graph.notes.any((note) => note.contains('override')), isTrue);
    },
  );

  test(
    'project graph adapter merges toolchain-state without project graph contract',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_project_graph_toolchain_only_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final previousCurrentDirectory = Directory.current;
      addTearDown(() => Directory.current = previousCurrentDirectory);

      File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[package]
name = "demo/toolchain-only"
version = "0.1.0"

[toolchain]
channel = "stable"

[[bin]]
name = "demo"
path = "src/main.styio"
''');
      Directory(
        '${tempRoot.path}${Platform.pathSeparator}src',
      ).createSync(recursive: true);

      await writeFakeSpioCli(
        workspaceRoot: tempRoot,
        pythonSource: '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['machine-info', '--json']:
    print(json.dumps({
        'tool': 'spio',
        'supported_contract_versions': {
            'project_graph': [],
            'toolchain_state': [1],
        },
    }))
    raise SystemExit(0)

args = sys.argv[1:]
if len(args) >= 3 and args[0] == 'tool' and args[1] == 'status':
    print(json.dumps({
        'command': 'tool status',
        'schema_version': 1,
        'toolchain': {
            'source': 'managed-current',
            'detail': 'Current managed styio selected through spio.',
            'channel': 'nightly',
            'version': '2026.6.19',
            'candidate_binary_path': '/workspace/.spio/tools/styio/current/bin/styio',
        },
        'active_compiler': {
            'binary_path': '/workspace/.spio/tools/styio/current/bin/styio',
            'tool': 'styio',
            'compiler_version': '2026.6.19',
            'channel': 'nightly',
            'variant': 'full',
            'capabilities': ['machine_info_json'],
            'supported_contract_versions': {'machine_info': [1]},
            'active_integration_phase': 'bootstrap-single-file',
            'supported_adapter_modes': ['cli'],
            'feature_flags': {'compile_plan_consumer': False},
        },
        'current_compiler_error': 'current compiler probe stayed cached',
        'managed_toolchains': {
            'spio_home': '/workspace/.spio',
            'current_binary': '/workspace/.spio/tools/styio/current/bin/styio',
            'installed': [],
        },
        'notes': ['Toolchain-only payload merged with inferred project graph.'],
    }))
    raise SystemExit(0)

raise SystemExit(64)
''',
      );

      Directory.current = tempRoot;

      final adapter = await createProjectGraphAdapter(
        platformTarget: PlatformTarget.linux,
      );
      final graph = await adapter.loadProjectGraph();

      expect(
        adapter.capabilitySnapshot.projectGraph.level,
        AdapterCapabilityLevel.partial,
      );
      expect(
        adapter.capabilitySnapshot.projectGraph.detail,
        contains('does not advertise the project_graph contract'),
      );
      expect(graph.kind, ProjectKind.package);
      expect(graph.toolchain.source, ToolchainResolutionSource.managedCurrent);
      expect(graph.toolchain.channel, 'nightly');
      expect(graph.activeCompiler?.compilerVersion, '2026.6.19');
      expect(
        graph.toolchainEnvironment?.currentCompilerError,
        contains('cached'),
      );
      expect(
        graph.notes.any((note) => note.contains('Toolchain-only payload')),
        isTrue,
      );
    },
  );

  test(
    'project graph adapter records published payload command and schema failures',
    () async {
      final originalCurrentDirectory = Directory.current;
      addTearDown(() => Directory.current = originalCurrentDirectory);

      Future<ProjectGraphSnapshot> loadGraphWithSpio({
        required String tempPrefix,
        required String projectGraphBody,
      }) async {
        final tempRoot = await Directory.systemTemp.createTemp(tempPrefix);
        addTearDown(() => _deleteDirectoryWithRetry(tempRoot));

        File('${tempRoot.path}${Platform.pathSeparator}spio.toml')
          ..createSync(recursive: true)
          ..writeAsStringSync('''
[package]
name = "demo/app"
version = "0.1.0"

[[bin]]
name = "demo"
path = "src/main.styio"
''');
        Directory(
          '${tempRoot.path}${Platform.pathSeparator}src',
        ).createSync(recursive: true);

        await writeFakeSpioCli(
          workspaceRoot: tempRoot,
          pythonSource:
              '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['machine-info', '--json']:
    print(json.dumps({
        'tool': 'spio',
        'supported_contract_versions': {'project_graph': [1]},
    }))
    raise SystemExit(0)

args = sys.argv[1:]
if len(args) >= 2 and args[0] == 'project-graph' and args[1] == '--json':
$projectGraphBody

raise SystemExit(64)
''',
        );
        final previousCurrentDirectory = Directory.current;
        Directory.current = tempRoot;
        try {
          final adapter = await createProjectGraphAdapter(
            platformTarget: PlatformTarget.linux,
          );
          return await adapter.loadProjectGraph();
        } finally {
          Directory.current = previousCurrentDirectory;
        }
      }

      final commandFailure = await loadGraphWithSpio(
        tempPrefix: 'vityo_project_graph_command_failure_test_',
        projectGraphBody: '''
    sys.stderr.write('project graph exploded\\n')
    raise SystemExit(42)
''',
      );
      final schemaFailure = await loadGraphWithSpio(
        tempPrefix: 'vityo_project_graph_schema_failure_test_',
        projectGraphBody: '''
    print(json.dumps({'schema_version': 2, 'kind': 'package'}))
    raise SystemExit(0)
''',
      );

      expect(commandFailure.hasProjectGraphPayloadFailure, isTrue);
      expect(
        commandFailure.projectGraphPayloadFailure?.detail,
        contains('stderr: project graph exploded'),
      );
      expect(
        commandFailure.notes.any((note) => note.contains('spio project-graph')),
        isTrue,
      );
      expect(schemaFailure.hasProjectGraphPayloadFailure, isTrue);
      expect(
        schemaFailure.projectGraphPayloadFailure?.detail,
        contains('unsupported schema_version `2`'),
      );
    },
  );

  test(
    'project graph adapter derives distribution from sparse published payloads',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_project_graph_derived_distribution_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));

      final previousCurrentDirectory = Directory.current;
      addTearDown(() => Directory.current = previousCurrentDirectory);

      final manifestPath = '${tempRoot.path}${Platform.pathSeparator}spio.toml';
      final rootJson = jsonEncode(tempRoot.path);
      final manifestJson = jsonEncode(manifestPath);
      final srcPath =
          '${tempRoot.path}${Platform.pathSeparator}src${Platform.pathSeparator}main.styio';
      final srcJson = jsonEncode(srcPath);
      File(manifestPath)
        ..createSync(recursive: true)
        ..writeAsStringSync('''
[package]
name = "demo/sparse"
version = "0.1.0"

[[bin]]
name = "demo"
path = "src/main.styio"
''');
      Directory(
        '${tempRoot.path}${Platform.pathSeparator}src',
      ).createSync(recursive: true);

      await writeFakeSpioCli(
        workspaceRoot: tempRoot,
        pythonSource:
            '''#!/usr/bin/env python3
import json, sys

if sys.argv[1:] == ['machine-info', '--json']:
    print(json.dumps({
        'tool': 'spio',
        'supported_contract_versions': {'project_graph': [1]},
    }))
    raise SystemExit(0)

args = sys.argv[1:]
if len(args) >= 2 and args[0] == 'project-graph' and args[1] == '--json':
    runtime_registry = {
        'source_package_name': 'demo/sparse',
        'dependency_name': 'runtime-registry',
        'kind': 'runtime',
        'requirement': 'registry:https://packages.example.test@1.0.0',
        'source_kind': 'registry',
        'package': 'demo/runtime-registry',
        'registry': 'https://packages.example.test',
        'version': '1.0.0',
    }
    dev_registry = {
        'source_package_name': 'demo/sparse',
        'dependency_name': 'dev-registry',
        'kind': 'dev',
        'requirement': 'registry:file:///registry@2.0.0',
        'source_kind': 'registry',
        'package': 'demo/dev-registry',
        'registry': 'file:///registry',
        'version': '2.0.0',
    }
    runtime_path = {
        'source_package_name': 'demo/sparse',
        'dependency_name': 'local-kit',
        'kind': 'runtime',
        'requirement': 'path:../local-kit',
        'source_kind': 'path',
        'path': '../local-kit',
    }
    dev_git = {
        'source_package_name': 'demo/sparse',
        'dependency_name': 'dev-tool',
        'kind': 'dev',
        'requirement': 'git:https://git.example/tool.git#abc123',
        'source_kind': 'git',
        'git': 'https://git.example/tool.git',
        'rev': 'abc123',
    }
    unknown = {
        'source_package_name': 'demo/sparse',
        'dependency_name': 'mystery',
        'kind': 'runtime',
        'requirement': '^0.1.0',
        'source_kind': 'unknown',
    }
    dependencies = [runtime_registry, dev_registry, runtime_path, dev_git, unknown]
    print(json.dumps({
        'schema_version': 1,
        'id': $manifestJson,
        'title': 'demo/sparse',
        'kind': 'package',
        'workspace_root': $rootJson,
        'workspace_members': [],
        'manifest_path': $manifestJson,
        'packages': [{
            'package_name': 'demo/sparse',
            'version': '0.1.0',
            'root_path': $rootJson,
            'manifest_path': $manifestJson,
            'publish_enabled': True,
            'targets': [{
                'id': 'demo/sparse:bin:demo',
                'package_name': 'demo/sparse',
                'kind': 'bin',
                'name': 'demo',
                'file_path': $srcJson,
            }],
            'dependencies': dependencies,
            'is_workspace_member': False,
        }],
        'dependencies': dependencies,
        'targets': [{
            'id': 'demo/sparse:bin:demo',
            'package_name': 'demo/sparse',
            'kind': 'bin',
            'name': 'demo',
            'file_path': $srcJson,
        }],
        'editor_files': [$srcJson],
    }))
    raise SystemExit(0)

raise SystemExit(64)
''',
      );
      Directory.current = tempRoot;

      final adapter = await createProjectGraphAdapter(
        platformTarget: PlatformTarget.linux,
      );
      final graph = await adapter.loadProjectGraph();

      expect(graph.kind, ProjectKind.package);
      expect(graph.toolchain.source, ToolchainResolutionSource.unavailable);
      expect(graph.notes, [
        'Project graph loaded through published spio machine payload.',
      ]);
      final distribution = graph.packageDistribution!;
      expect(distribution.publishablePackages, 0);
      expect(distribution.blockedPackages, 1);
      expect(
        distribution.registrySources.map((source) => source.transport).toSet(),
        {'file', 'https'},
      );
      final packageDistribution = distribution.packages.single;
      expect(packageDistribution.runtimeRegistryDependencies, 1);
      expect(packageDistribution.devRegistryDependencies, 1);
      expect(packageDistribution.runtimePathDependencies, 1);
      expect(packageDistribution.devGitDependencies, 1);
      expect(
        packageDistribution.blockingReasons,
        containsAll(<String>[
          'dependency in [dependencies] uses a local path or workspace source: local-kit',
          'dependency in [dev-dependencies] uses a git source: dev-tool',
          'dependency in [dependencies] is not registry-addressable: mystery',
        ]),
      );
    },
  );
}

Future<void> _deleteDirectoryWithRetry(Directory directory) async {
  for (var attempt = 0; attempt < 5; attempt += 1) {
    try {
      if (await directory.exists()) {
        await directory.delete(recursive: true);
      }
      return;
    } on FileSystemException {
      if (attempt == 4) {
        rethrow;
      }
      await Future<void>.delayed(Duration(milliseconds: 50 * (attempt + 1)));
    }
  }
}
