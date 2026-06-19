import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/hosted_payload_codec.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';

void main() {
  test('hosted workspace payload accepts public enum label spellings', () {
    final record = hostedWorkspaceRecordFromPayload(<String, dynamic>{
      'workspaceId': 'demo-workspace',
      'schemaVersion': '1',
      'ownerRef': 'Vityo',
      'status': HostedWorkspaceStatus.pendingDeletion.label,
      'entryUrl': 'https://hosted.example/workspaces/demo-workspace',
      'createdAt': '2026-04-21T00:00:00Z',
      'lastActiveAt': '2026-04-21T00:05:00Z',
      'retentionDays': 14,
      'exportState': HostedWorkspaceExportState.notRequested.label,
    });

    expect(record.status, HostedWorkspaceStatus.pendingDeletion);
    expect(record.exportState, HostedWorkspaceExportState.notRequested);
    expect(record.retentionDays, 14);
  });

  test('hosted workspace payload decodes lifecycle aliases and dates', () {
    final cases = <String, HostedWorkspaceStatus>{
      'provisioning': HostedWorkspaceStatus.provisioning,
      'closing': HostedWorkspaceStatus.closing,
      'pending_deletion': HostedWorkspaceStatus.pendingDeletion,
      'deleted': HostedWorkspaceStatus.deleted,
      'unknown': HostedWorkspaceStatus.active,
    };

    for (final entry in cases.entries) {
      final record = hostedWorkspaceRecordFromPayload(<String, dynamic>{
        'workspaceId': 'demo-${entry.key}',
        'status': entry.key,
        'createdAt': '2026-04-21T00:00:00+02:00',
        'lastActiveAt': '',
        'closedAt': '2026-04-22T00:00:00Z',
        'retentionDeadline': '2026-05-06T00:00:00Z',
        'coreFileExportUrl': 'https://hosted.example/export.core',
        'coreFileExportExpiresAt': '2026-04-23T00:00:00Z',
      });

      expect(record.status, entry.value);
      expect(record.createdAt, DateTime.utc(2026, 4, 20, 22));
      expect(
        record.lastActiveAt,
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
      expect(record.closedAt, DateTime.utc(2026, 4, 22));
      expect(record.retentionDeadline, DateTime.utc(2026, 5, 6));
      expect(record.coreFileExportUrl, contains('export.core'));
      expect(record.coreFileExportExpiresAt, DateTime.utc(2026, 4, 23));
    }

    final ready = hostedWorkspaceRecordFromPayload(<String, dynamic>{
      'exportState': 'ready',
    });
    final expired = hostedWorkspaceRecordFromPayload(<String, dynamic>{
      'exportState': 'expired',
    });
    final preparing = hostedWorkspaceRecordFromPayload(<String, dynamic>{
      'exportState': 'preparing',
    });

    expect(ready.exportState, HostedWorkspaceExportState.ready);
    expect(expired.exportState, HostedWorkspaceExportState.expired);
    expect(preparing.exportState, HostedWorkspaceExportState.preparing);
  });

  test('hosted project graph envelope decodes full hosted payload', () {
    final registryDependency = <String, dynamic>{
      'source_package_name': 'demo/app',
      'dependency_name': 'assertions',
      'kind': 'runtime',
      'requirement': '^1.0.0',
      'source_kind': 'registry',
      'package': 'assertions',
      'registry': 'https://registry.example',
      'version': '1.0.1',
    };
    final devRegistryDependency = <String, dynamic>{
      'source_package_name': 'demo/app',
      'dependency_name': 'lint_rules',
      'kind': 'dev',
      'requirement': '^2.0.0',
      'source_kind': 'registry',
      'package': 'lint_rules',
      'registry': 'file:///workspace/registry',
      'version': '2.0.0',
    };
    final pathDependency = <String, dynamic>{
      'source_package_name': 'demo/app',
      'dependency_name': 'render/kit',
      'kind': 'runtime',
      'requirement': 'workspace',
      'is_workspace_reference': true,
      'source_kind': 'path',
      'path': '../render-kit',
    };
    final gitDependency = <String, dynamic>{
      'source_package_name': 'demo/app',
      'dependency_name': 'metrics',
      'kind': 'dev',
      'requirement': 'git',
      'source_kind': 'git',
      'git': 'https://example.test/metrics.git',
      'rev': 'abc123',
    };
    final unknownDependency = <String, dynamic>{
      'source_package_name': 'demo/app',
      'dependency_name': 'mystery',
      'kind': 'runtime',
      'requirement': '*',
      'source_kind': 'unknown',
      'publish_blocking': true,
    };

    final graph = hostedProjectGraphSnapshotFromEnvelope(<String, dynamic>{
      'workspace': <String, dynamic>{
        'workspaceId': 'demo-workspace',
        'status': 'active',
        'entryUrl': 'https://hosted.example/workspaces/demo-workspace',
      },
      'payload': <String, dynamic>{
        'id': '/workspace/demo/spio.toml',
        'title': 'demo/app',
        'workspace_root': '/workspace/demo',
        'workspace_members': <String>['packages/render'],
        'manifest_path': '/workspace/demo/spio.toml',
        'lockfile_path': '/workspace/demo/spio.lock',
        'toolchain_pin_path': '/workspace/demo/spio-toolchain.toml',
        'styio_config_path': '/workspace/demo/styio.toml',
        'vendor_root': '/workspace/demo/.spio/vendor',
        'build_root': '/workspace/demo/.spio/build',
        'lock_state': 'fresh',
        'vendor_state': 'present',
        'editor_files': <String>['/workspace/demo/src/main.styio'],
        'targets': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'demo/app:lib:core',
            'package_name': 'demo/app',
            'kind': 'lib',
            'name': 'core',
            'file_path': 'src/lib.styio',
          },
          <String, dynamic>{
            'id': 'demo/app:test:main',
            'package_name': 'demo/app',
            'kind': 'test',
            'name': 'main',
            'file_path': 'test/main_test.styio',
          },
        ],
        'dependencies': <Map<String, dynamic>>[
          registryDependency,
          pathDependency,
          gitDependency,
          unknownDependency,
        ],
        'packages': <Map<String, dynamic>>[
          <String, dynamic>{
            'package_name': 'demo/app',
            'version': '0.1.0',
            'root_path': '/workspace/demo',
            'manifest_path': '/workspace/demo/spio.toml',
            'is_workspace_member': true,
            'publish_enabled': true,
            'targets': <Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'demo/app:bin:app',
                'package_name': 'demo/app',
                'kind': 'bin',
                'name': 'app',
                'file_path': 'bin/app.styio',
              },
            ],
            'dependencies': <Map<String, dynamic>>[
              registryDependency,
              devRegistryDependency,
              pathDependency,
              gitDependency,
              unknownDependency,
            ],
          },
        ],
        'toolchain': <String, dynamic>{
          'source': 'project-pin',
          'detail': 'Pinned toolchain is active.',
          'pin_path': '/workspace/demo/spio-toolchain.toml',
          'channel': 'stable',
          'version': '0.0.5',
        },
        'active_compiler': <String, dynamic>{
          'binary_path': '/toolchains/styio',
          'tool': 'styio',
          'compiler_version': '0.0.5',
          'channel': 'stable',
          'variant': 'hosted',
          'capabilities': <Object>['runtime_event_stream', 42],
          'supported_contract_versions': <String, dynamic>{
            'compile_plan': <Object>[1, 2, 'ignored'],
          },
          'integration_phase': 'compile',
          'supported_adapter_modes': <Object>['project', false],
          'feature_flags': <Object?, Object?>{
            'runtime': true,
            'ignored': 'yes',
          },
        },
        'managed_toolchains': <String, dynamic>{
          'spio_home': '/workspace/demo/.spio',
          'current_binary': '/workspace/demo/.spio/bin/styio',
          'current_metadata_path': '/workspace/demo/.spio/current.json',
          'installed': <Map<String, dynamic>>[
            <String, dynamic>{
              'channel': 'stable',
              'compiler_version': '0.0.5',
              'install_root': '/workspace/demo/.spio/toolchains/stable',
              'install_binary_path':
                  '/workspace/demo/.spio/toolchains/stable/styio',
              'install_metadata_path':
                  '/workspace/demo/.spio/toolchains/stable/metadata.json',
            },
          ],
        },
        'source_state': <String, dynamic>{
          'schema_version': 2,
          'spio_home': '/workspace/demo/.spio',
          'declared_git_dependencies': 1,
          'declared_registry_dependencies': 2,
          'git_cache': <String, dynamic>{
            'repos_root': '/workspace/demo/.spio/git/repos',
            'checkouts_root': '/workspace/demo/.spio/git/checkouts',
            'repos_present': true,
            'checkouts_present': true,
          },
          'registry_cache': <String, dynamic>{
            'cache_root': '/workspace/demo/.spio/registry',
            'index_root': '/workspace/demo/.spio/registry/index',
            'blob_root': '/workspace/demo/.spio/registry/blobs',
            'checkout_root': '/workspace/demo/.spio/registry/checkouts',
            'index_present': true,
            'blobs_present': true,
            'checkouts_present': true,
          },
          'vendor': <String, dynamic>{
            'vendor_root': '/workspace/demo/.spio/vendor',
            'metadata_path': '/workspace/demo/.spio/vendor/vendor.json',
            'vendor_present': true,
            'metadata_present': true,
            'git_snapshots': 1,
          },
        },
        'notes': <String>['hosted ok'],
      },
    });

    expect(graph.kind, ProjectKind.hosted);
    expect(graph.title, 'demo/app');
    expect(graph.workspaceRoot, '/workspace/demo');
    expect(graph.workspaceMembers, <String>['packages/render']);
    expect(
      graph.targets.map((target) => target.kind),
      contains(ProjectTargetKind.lib),
    );
    expect(
      graph.targets.map((target) => target.kind),
      contains(ProjectTargetKind.test),
    );
    expect(graph.packages.single.dependencies, hasLength(5));
    expect(graph.dependencies.last.publishBlocking, isTrue);
    expect(graph.toolchain.source, ToolchainResolutionSource.projectPin);
    expect(graph.lockState, ProjectLockState.fresh);
    expect(graph.vendorState, ProjectVendorState.present);
    expect(graph.activeCompiler!.supportsContract('compile_plan'), isTrue);
    expect(
      graph.activeCompiler!.supportedContractVersions['compile_plan'],
      <int>[1, 2],
    );
    expect(graph.activeCompiler!.hasFeatureFlag('runtime'), isTrue);
    expect(graph.toolchainEnvironment!.projectPin!.channel, 'stable');
    expect(
      graph.toolchainEnvironment!.managedToolchains.installed,
      hasLength(1),
    );
    expect(graph.packageDistribution!.publishablePackages, 0);
    expect(graph.packageDistribution!.blockedPackages, 1);
    expect(
      graph.packageDistribution!.packages.single.blockingReasons,
      contains(contains('local path')),
    );
    expect(
      graph.packageDistribution!.registrySources.map(
        (source) => source.transport,
      ),
      containsAll(<String>['https', 'file']),
    );
    expect(graph.sourceState!.gitCache.reposPresent, isTrue);
    expect(graph.sourceState!.registryCache.blobsPresent, isTrue);
    expect(graph.sourceState!.vendor.metadataPresent, isTrue);
    expect(graph.hostedWorkspace!.workspaceId, 'demo-workspace');
    expect(graph.notes, <String>['hosted ok']);
  });

  test('hosted payload helpers decode defaults and supplied distribution', () {
    expect(
      () => hostedProjectGraphSnapshotFromEnvelope(<String, dynamic>{
        'payload': 'missing',
      }),
      throwsA(isA<FormatException>()),
    );

    expect(projectKindFromString('package'), ProjectKind.package);
    expect(projectKindFromString('workspace'), ProjectKind.workspace);
    expect(projectKindFromString('combined-root'), ProjectKind.combinedRoot);
    expect(projectKindFromString('scratch'), ProjectKind.scratch);
    expect(projectTargetKindFromString(null), ProjectTargetKind.bin);
    expect(projectDependencyKindFromString(null), ProjectDependencyKind.runtime);
    expect(
      projectDependencySourceKindFromString('registry'),
      ProjectDependencySourceKind.registry,
    );
    expect(lockStateFromString('stale'), ProjectLockState.stale);
    expect(lockStateFromString('missing'), ProjectLockState.missing);
    expect(vendorStateFromString('missing'), ProjectVendorState.missing);
    expect(
      toolchainSourceFromString('managed-current'),
      ToolchainResolutionSource.managedCurrent,
    );
    expect(
      toolchainSourceFromString('environment'),
      ToolchainResolutionSource.environment,
    );
    expect(
      toolchainSourceFromString('unknown'),
      ToolchainResolutionSource.unknown,
    );
    expect(registryTransportFromRoot('http://registry.example'), 'http');
    expect(registryTransportFromRoot('ssh://registry.example'), 'unknown');

    final graph = hostedProjectGraphSnapshotFromEnvelope(<String, dynamic>{
      'payload': <String, dynamic>{
        'manifest_path': '/workspace/demo/spio.toml',
        'package_distribution': <String, dynamic>{
          'schema_version': 3,
          'publishable_packages': 1,
          'blocked_packages': 1,
          'packages': <Map<String, dynamic>>[
            <String, dynamic>{
              'package_name': 'demo/app',
              'manifest_path': '/workspace/demo/spio.toml',
              'publish_enabled': true,
              'publish_ready': true,
              'runtime_registry_dependencies': 2,
              'dev_path_dependencies': 1,
            },
          ],
          'registry_sources': <Map<String, dynamic>>[
            <String, dynamic>{
              'registry_root': 'http://registry.example',
              'transport': 'http',
              'dependency_refs': 2,
              'packages': <String>['demo/app'],
            },
          ],
        },
      },
    });

    expect(graph.id, '/workspace/demo/spio.toml');
    expect(graph.toolchain.source, ToolchainResolutionSource.unavailable);
    expect(graph.notes.single, contains('hosted control-plane'));
    expect(graph.packageDistribution!.schemaVersion, 3);
    expect(graph.packageDistribution!.packages.single.publishReady, isTrue);
    expect(graph.packageDistribution!.registrySources.single.dependencyRefs, 2);
  });
}
