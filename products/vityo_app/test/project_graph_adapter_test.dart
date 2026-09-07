import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_adapter_io.dart'
    show debugOverrideProjectGraphEnvironment;
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';

import 'backend_provider_test_support.dart';
import 'fake_pafio_cli.dart';

void main() {
  setUpAll(startBackendProviderTestServices);
  tearDownAll(stopBackendProviderTestServices);

  tearDown(() {
    debugOverrideProjectGraphEnvironment(null);
  });

  test('local project graph consumes only Pafio metadata v1', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_pafio_metadata_project_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final previousCurrentDirectory = Directory.current;
    addTearDown(() => Directory.current = previousCurrentDirectory);

    final manifestPath = '${tempRoot.path}${Platform.pathSeparator}pafio.toml';
    File(manifestPath)
      ..createSync(recursive: true)
      ..writeAsStringSync('[pafio]\nmanifest-version = 1\n');
    final sourcePath =
        '${tempRoot.path}${Platform.pathSeparator}src'
        '${Platform.pathSeparator}main.styio';
    final metadataPayload = <String, Object?>{
      'package': <String, Object?>{
        'id': 'workspace:demo/app@1.0.0',
        'manifest_path': manifestPath,
        'name': 'demo/app',
        'publish': true,
        'root': tempRoot.path,
        'source_kind': 'workspace',
        'version': '1.0.0',
        'edition': '2026',
      },
      'workspace': <String, Object?>{
        'exclude': <String>[],
        'manifest_path': manifestPath,
        'members': <String>[],
        'packages': <Object?>[
          <String, Object?>{
            'id': 'workspace:demo/app@1.0.0',
            'manifest_path': manifestPath,
            'name': 'demo/app',
            'publish': true,
            'root': tempRoot.path,
            'source_kind': 'workspace',
            'version': '1.0.0',
            'edition': '2026',
          },
        ],
        'resolver': '1',
        'root': tempRoot.path,
        'root_package_ids': <String>['workspace:demo/app@1.0.0'],
      },
      'dependencies': <Object?>[],
      'targets': <Object?>[
        <String, Object?>{
          'kind': 'bin',
          'name': 'app',
          'package_id': 'workspace:demo/app@1.0.0',
          'path': sourcePath,
        },
      ],
      'lock': <String, Object?>{
        'package_count': 1,
        'path': '${tempRoot.path}${Platform.pathSeparator}pafio.lock',
        'present': true,
        'resolver': '1',
      },
      'resolution': <String, Object?>{
        'package_count': 1,
        'path': '${tempRoot.path}${Platform.pathSeparator}resolution.json',
        'present': true,
        'root_package_ids': <String>['workspace:demo/app@1.0.0'],
        'schema_version': 1,
      },
      'vendor': <String, Object?>{
        'metadata_path': '${tempRoot.path}${Platform.pathSeparator}vendor.json',
        'present': false,
        'root': '${tempRoot.path}${Platform.pathSeparator}vendor',
      },
    };
    final tools = Directory(
      '${tempRoot.path}${Platform.pathSeparator}test-tools',
    );
    final pafio = await writeFakePythonCli(
      directory: tools,
      executableName: 'pafio',
      pythonSource:
          '''#!/usr/bin/env python3
import sys
if "--version" in sys.argv:
    print("pafio 1.0.0")
elif len(sys.argv) > 1 and sys.argv[1] == "metadata":
    print(${jsonEncode(jsonEncode(metadataPayload))})
else:
    raise SystemExit(2)
''',
    );
    final styio = await writeFakePythonCli(
      directory: tools,
      executableName: 'styio',
      pythonSource: '''#!/usr/bin/env python3
import json
print(json.dumps({
    "tool": "styio",
    "compiler_version": "1.2.3",
    "channel": "system",
    "variant": "test",
    "supported_contracts": {"compile_plan": [1]}
}))
''',
    );

    Directory.current = tempRoot;
    debugOverrideProjectGraphEnvironment(<String, String>{
      'PWD': tempRoot.path,
      'VITYO_PAFIO_BIN': pafio.path,
      'VITYO_STYIO_BIN': styio.path,
    });

    final adapter = await createProjectGraphAdapter(
      platformTarget: PlatformTarget.macos,
      workspaceRoot: tempRoot.path,
    );
    final graph = await adapter.loadProjectGraph();

    expect(graph.kind, ProjectKind.package);
    expect(graph.title, 'demo/app');
    expect(graph.packages.single.packageName, 'demo/app');
    expect(graph.targets.single.filePath, sourcePath);
    expect(graph.activeCompiler?.compilerVersion, '1.2.3');
    expect(graph.hasAuthoritativeProjectGraphFacts, isTrue);
    expect(graph.projectGraphPayloadFailure, isNull);
    expect(graph.notes, <String>[
      'Project facts loaded exclusively from Pafio metadata v1.',
    ]);
  });

  test(
    'missing manifest stays in scratch mode without file inference',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_pafio_metadata_scratch_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final previousCurrentDirectory = Directory.current;
      addTearDown(() => Directory.current = previousCurrentDirectory);
      Directory.current = tempRoot;
      debugOverrideProjectGraphEnvironment(<String, String>{
        'PWD': tempRoot.path,
      });

      final adapter = await createProjectGraphAdapter(
        platformTarget: PlatformTarget.linux,
        workspaceRoot: tempRoot.path,
      );
      final graph = await adapter.loadProjectGraph();

      expect(graph.kind, ProjectKind.scratch);
      expect(graph.manifestPath, isNull);
      expect(graph.packages, isEmpty);
      expect(graph.targets, isEmpty);
      expect(graph.notes.single, contains('No pafio.toml'));
    },
  );

  test('missing Pafio blocks metadata instead of parsing pafio.toml', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_pafio_metadata_blocked_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final previousCurrentDirectory = Directory.current;
    addTearDown(() => Directory.current = previousCurrentDirectory);
    File('${tempRoot.path}${Platform.pathSeparator}pafio.toml')
      ..createSync(recursive: true)
      ..writeAsStringSync('''
[package]
name = "must/not-be-parsed"
version = "9.9.9"
''');
    Directory.current = tempRoot;
    debugOverrideProjectGraphEnvironment(<String, String>{
      'PWD': tempRoot.path,
      'PATH': '${tempRoot.path}${Platform.pathSeparator}empty-path',
    });

    final adapter = await createProjectGraphAdapter(
      platformTarget: PlatformTarget.linux,
      workspaceRoot: tempRoot.path,
    );
    final graph = await adapter.loadProjectGraph();

    expect(graph.kind, ProjectKind.package);
    expect(graph.title, 'Pafio Project');
    expect(graph.packages, isEmpty);
    expect(graph.projectGraphPayloadFailure, isNotNull);
    expect(graph.projectGraphPayloadFailure?.command, 'pafio metadata --json');
  });
}
