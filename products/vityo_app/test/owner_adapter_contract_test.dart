import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/owner_adapters/pafio_metadata_adapter.dart';
import 'package:vityo_app/owner_adapters/styio_compiler_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';

void main() {
  test('Pafio metadata v1 is the complete local project source', () {
    final metadata = PafioMetadataAdapter.decode(
      jsonEncode(<String, Object?>{
        'package': <String, Object?>{
          'id': 'workspace:demo/app@1.0.0',
          'manifest_path': '/workspace/pafio.toml',
          'name': 'demo/app',
          'publish': true,
          'root': '/workspace',
          'source_kind': 'workspace',
          'version': '1.0.0',
          'edition': '2026',
        },
        'workspace': <String, Object?>{
          'exclude': <String>[],
          'manifest_path': '/workspace/pafio.toml',
          'members': <String>['packages/core'],
          'packages': <Object?>[
            <String, Object?>{
              'id': 'workspace:demo/app@1.0.0',
              'manifest_path': '/workspace/pafio.toml',
              'name': 'demo/app',
              'publish': true,
              'root': '/workspace',
              'source_kind': 'workspace',
              'version': '1.0.0',
              'edition': '2026',
            },
            <String, Object?>{
              'id': 'workspace:demo/core@1.0.0',
              'manifest_path': '/workspace/packages/core/pafio.toml',
              'name': 'demo/core',
              'publish': false,
              'root': '/workspace/packages/core',
              'source_kind': 'workspace',
              'version': '1.0.0',
              'edition': '2026',
            },
          ],
          'resolver': '1',
          'root': '/workspace',
          'root_package_ids': <String>['workspace:demo/app@1.0.0'],
        },
        'dependencies': <Object?>[
          <String, Object?>{
            'alias': 'core',
            'kind': 'normal',
            'package': 'demo/core',
            'package_id': 'workspace:demo/core@1.0.0',
            'parent_package_id': 'workspace:demo/app@1.0.0',
            'requirement': null,
            'source': <String, Object?>{
              'kind': 'path',
              'location': 'packages/core',
              'rev': null,
            },
          },
        ],
        'targets': <Object?>[
          <String, Object?>{
            'kind': 'bin',
            'name': 'app',
            'package_id': 'workspace:demo/app@1.0.0',
            'path': '/workspace/src/main.styio',
          },
          <String, Object?>{
            'kind': 'lib',
            'name': 'demo/core',
            'package_id': 'workspace:demo/core@1.0.0',
            'path': '/workspace/packages/core/src/lib.styio',
          },
        ],
        'lock': <String, Object?>{
          'package_count': 2,
          'path': '/workspace/pafio.lock',
          'present': true,
          'resolver': '1',
        },
        'resolution': <String, Object?>{
          'package_count': 2,
          'path': '/workspace/.pafio/resolution-v1.json',
          'present': true,
          'root_package_ids': <String>['workspace:demo/app@1.0.0'],
          'schema_version': 1,
        },
        'vendor': <String, Object?>{
          'metadata_path': '/workspace/vendor/pafio-vendor.json',
          'present': false,
          'root': '/workspace/vendor',
        },
      }),
    );
    final graph = metadata.toProjectGraph();

    expect(graph.kind, ProjectKind.combinedRoot);
    expect(graph.title, 'demo/app');
    expect(graph.workspaceMembers, <String>['packages/core']);
    expect(graph.packages.map((item) => item.packageName), <String>[
      'demo/app',
      'demo/core',
    ]);
    expect(graph.targets.map((item) => item.kind), <ProjectTargetKind>[
      ProjectTargetKind.bin,
      ProjectTargetKind.lib,
    ]);
    expect(graph.dependencies.single.dependencyName, 'core');
    expect(
      graph.dependencies.single.sourceKind,
      ProjectDependencySourceKind.path,
    );
    expect(graph.dependencies.single.pathSource, 'packages/core');
    expect(graph.lockState, ProjectLockState.unknown);
    expect(graph.vendorState, ProjectVendorState.missing);
    expect(graph.hasAuthoritativeProjectGraphFacts, isTrue);
    expect(graph.toolchain.source, ToolchainResolutionSource.unavailable);
  });

  test('Pafio metadata rejects extra product-owner fields', () {
    expect(
      () => PafioMetadataAdapter.decode(
        jsonEncode(<String, Object?>{
          'package': <String, Object?>{},
          'workspace': <String, Object?>{},
          'dependencies': <Object?>[],
          'targets': <Object?>[],
          'lock': <String, Object?>{},
          'resolution': <String, Object?>{},
          'vendor': <String, Object?>{},
          'managed_toolchain': <String, Object?>{},
        }),
      ),
      throwsA(isA<PafioMetadataException>()),
    );
  });

  test('Styio machine-info v1 is decoded independently of Pafio', () {
    final compiler = StyioCompilerAdapter.decode(
      jsonEncode(<String, Object?>{
        'tool': 'styio',
        'compiler_version': '1.2.3',
        'channel': 'nightly',
        'variant': 'system',
        'capabilities': <String>['compile-plan'],
        'supported_contracts': <String, Object?>{
          'compile_plan': <int>[1],
          'diagnostics': <int>[1],
          'receipt': <int>[1],
          'runtime_events': <int>[1],
        },
        'feature_flags': <String, Object?>{'compile_plan_consumer': true},
      }),
      binaryPath: 'styio',
    );

    expect(compiler.tool, 'styio');
    expect(compiler.compilerVersion, '1.2.3');
    expect(compiler.supportsContract('compile_plan'), isTrue);
    expect(compiler.hasFeatureFlag('compile_plan_consumer'), isTrue);
  });
}
