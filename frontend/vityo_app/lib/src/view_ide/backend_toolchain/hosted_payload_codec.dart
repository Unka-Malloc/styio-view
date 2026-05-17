import 'project_graph_contract.dart';

HostedWorkspaceRecordSnapshot hostedWorkspaceRecordFromPayload(
  Map<String, dynamic> payload,
) {
  return HostedWorkspaceRecordSnapshot(
    workspaceId: payload['workspaceId'] as String? ?? '',
    schemaVersion: payload['schemaVersion'] as String? ?? '1',
    ownerRef: payload['ownerRef'] as String? ?? 'Vityo',
    status: _hostedWorkspaceStatusFromString(payload['status'] as String?),
    entryUrl: payload['entryUrl'] as String? ?? '',
    createdAt:
        _dateTimeFromString(payload['createdAt'] as String?) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    lastActiveAt:
        _dateTimeFromString(payload['lastActiveAt'] as String?) ??
        DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    retentionDays: payload['retentionDays'] as int? ?? 7,
    exportState: _hostedWorkspaceExportStateFromString(
      payload['exportState'] as String?,
    ),
    closedAt: _dateTimeFromString(payload['closedAt'] as String?),
    retentionDeadline: _dateTimeFromString(
      payload['retentionDeadline'] as String?,
    ),
    coreFileExportUrl: payload['coreFileExportUrl'] as String?,
    coreFileExportExpiresAt: _dateTimeFromString(
      payload['coreFileExportExpiresAt'] as String?,
    ),
  );
}

ProjectGraphSnapshot hostedProjectGraphSnapshotFromEnvelope(
  Map<String, dynamic> envelope,
) {
  final payload = envelope['payload'];
  if (payload is! Map<String, dynamic>) {
    throw const FormatException(
      'Hosted project-graph response is missing payload.',
    );
  }

  final packages = (payload['packages'] as List? ?? const <Object>[])
      .whereType<Map<String, dynamic>>()
      .map(projectPackageFromPayload)
      .toList(growable: false);
  final dependencies = (payload['dependencies'] as List? ?? const <Object>[])
      .whereType<Map<String, dynamic>>()
      .map(projectDependencyFromPayload)
      .toList(growable: false);
  final targets = (payload['targets'] as List? ?? const <Object>[])
      .whereType<Map<String, dynamic>>()
      .map(projectTargetFromPayload)
      .toList(growable: false);
  final activeCompiler = payload['active_compiler'] is Map<String, dynamic>
      ? compilerHandshakeFromPayload(
          payload['active_compiler'] as Map<String, dynamic>,
        )
      : null;
  final toolchain = payload['toolchain'] is Map<String, dynamic>
      ? toolchainStatusFromPayload(payload['toolchain'] as Map<String, dynamic>)
      : const ToolchainStatusSnapshot(
          source: ToolchainResolutionSource.unavailable,
          detail: 'Hosted route did not publish toolchain state.',
        );
  final notes = (payload['notes'] as List? ?? const <Object>[])
      .whereType<String>()
      .toList(growable: false);
  final managedToolchains =
      payload['managed_toolchains'] is Map<String, dynamic>
      ? managedToolchainStateFromPayload(
          payload['managed_toolchains'] as Map<String, dynamic>,
        )
      : const ManagedToolchainStateSnapshot();
  final projectPin = payload['toolchain_pin_path'] is String
      ? ProjectToolchainPinSnapshot(
          path: payload['toolchain_pin_path'] as String,
          channel: payload['toolchain'] is Map<String, dynamic>
              ? (payload['toolchain'] as Map<String, dynamic>)['channel']
                    as String?
              : null,
          version: payload['toolchain'] is Map<String, dynamic>
              ? (payload['toolchain'] as Map<String, dynamic>)['version']
                    as String?
              : null,
          installPresent: false,
        )
      : null;
  final packageDistribution =
      payload['package_distribution'] is Map<String, dynamic>
      ? packageDistributionFromPayload(
          payload['package_distribution'] as Map<String, dynamic>,
        )
      : derivePackageDistributionFromPackages(packages);
  final sourceState = payload['source_state'] is Map<String, dynamic>
      ? projectSourceStateFromPayload(
          payload['source_state'] as Map<String, dynamic>,
        )
      : null;
  final hostedWorkspace = envelope['workspace'] is Map<String, dynamic>
      ? hostedWorkspaceRecordFromPayload(
          envelope['workspace'] as Map<String, dynamic>,
        )
      : null;

  return ProjectGraphSnapshot(
    id: payload['id'] as String? ?? payload['manifest_path'] as String? ?? '',
    title: payload['title'] as String? ?? 'Hosted Workspace',
    kind: ProjectKind.hosted,
    workspaceRoot: payload['workspace_root'] as String? ?? '',
    workspaceMembers:
        (payload['workspace_members'] as List? ?? const <Object>[])
            .whereType<String>()
            .toList(growable: false),
    manifestPath: payload['manifest_path'] as String?,
    lockfilePath: payload['lockfile_path'] as String?,
    toolchainPinPath: payload['toolchain_pin_path'] as String?,
    styioConfigPath: payload['styio_config_path'] as String?,
    vendorRoot: payload['vendor_root'] as String?,
    buildRoot: payload['build_root'] as String?,
    packages: packages,
    dependencies: dependencies,
    targets: targets,
    editorFiles: (payload['editor_files'] as List? ?? const <Object>[])
        .whereType<String>()
        .toList(growable: false),
    toolchain: toolchain,
    lockState: lockStateFromString(payload['lock_state'] as String?),
    vendorState: vendorStateFromString(payload['vendor_state'] as String?),
    activeCompiler: activeCompiler,
    toolchainEnvironment: ToolchainEnvironmentSnapshot(
      schemaVersion: 1,
      toolchain: toolchain,
      projectPin: projectPin,
      activeCompiler: activeCompiler,
      managedToolchains: managedToolchains,
      notes: notes,
    ),
    packageDistribution: packageDistribution,
    sourceState: sourceState,
    hostedWorkspace: hostedWorkspace,
    notes: notes.isEmpty
        ? const <String>[
            'Project graph loaded through the hosted control-plane route.',
          ]
        : notes,
  );
}

ProjectKind projectKindFromString(String? raw) {
  switch (raw) {
    case 'package':
      return ProjectKind.package;
    case 'workspace':
      return ProjectKind.workspace;
    case 'combined-root':
      return ProjectKind.combinedRoot;
    case 'hosted':
      return ProjectKind.hosted;
    case 'scratch':
    default:
      return ProjectKind.scratch;
  }
}

ProjectTargetKind projectTargetKindFromString(String? raw) {
  switch (raw) {
    case 'lib':
      return ProjectTargetKind.lib;
    case 'test':
      return ProjectTargetKind.test;
    case 'bin':
    default:
      return ProjectTargetKind.bin;
  }
}

ProjectDependencyKind projectDependencyKindFromString(String? raw) {
  switch (raw) {
    case 'dev':
      return ProjectDependencyKind.dev;
    case 'runtime':
    default:
      return ProjectDependencyKind.runtime;
  }
}

ProjectDependencySourceKind projectDependencySourceKindFromString(String? raw) {
  switch (raw) {
    case 'path':
      return ProjectDependencySourceKind.path;
    case 'git':
      return ProjectDependencySourceKind.git;
    case 'registry':
      return ProjectDependencySourceKind.registry;
    case 'unknown':
    default:
      return ProjectDependencySourceKind.unknown;
  }
}

ProjectLockState lockStateFromString(String? raw) {
  switch (raw) {
    case 'fresh':
      return ProjectLockState.fresh;
    case 'stale':
      return ProjectLockState.stale;
    case 'missing':
      return ProjectLockState.missing;
    case 'unknown':
    default:
      return ProjectLockState.unknown;
  }
}

ProjectVendorState vendorStateFromString(String? raw) {
  switch (raw) {
    case 'present':
      return ProjectVendorState.present;
    case 'missing':
      return ProjectVendorState.missing;
    case 'unknown':
    default:
      return ProjectVendorState.unknown;
  }
}

ToolchainResolutionSource toolchainSourceFromString(String? raw) {
  switch (raw) {
    case 'project-pin':
      return ToolchainResolutionSource.projectPin;
    case 'managed-current':
      return ToolchainResolutionSource.managedCurrent;
    case 'environment':
      return ToolchainResolutionSource.environment;
    case 'unknown':
      return ToolchainResolutionSource.unknown;
    case 'unavailable':
    default:
      return ToolchainResolutionSource.unavailable;
  }
}

ProjectTargetDescriptor projectTargetFromPayload(Map<String, dynamic> payload) {
  return ProjectTargetDescriptor(
    id: payload['id'] as String? ?? '',
    packageName: payload['package_name'] as String? ?? '',
    kind: projectTargetKindFromString(payload['kind'] as String?),
    name: payload['name'] as String? ?? '',
    filePath: payload['file_path'] as String? ?? '',
  );
}

ProjectDependencySnapshot projectDependencyFromPayload(
  Map<String, dynamic> payload,
) {
  final sourceKind = projectDependencySourceKindFromString(
    payload['source_kind'] as String?,
  );
  final packageIdentity = payload['package'] as String?;
  final registryRoot = payload['registry'] as String?;
  final requestedVersion = payload['version'] as String?;
  return ProjectDependencySnapshot(
    sourcePackageName: payload['source_package_name'] as String? ?? '',
    dependencyName: payload['dependency_name'] as String? ?? '',
    kind: projectDependencyKindFromString(payload['kind'] as String?),
    requirement: payload['requirement'] as String? ?? '',
    isWorkspaceReference: payload['is_workspace_reference'] as bool? ?? false,
    packageIdentity: packageIdentity,
    sourceKind: sourceKind,
    pathSource: payload['path'] as String?,
    gitSource: payload['git'] as String?,
    gitRevision: payload['rev'] as String?,
    registryRoot: registryRoot,
    requestedVersion: requestedVersion,
    publishBlocking:
        payload['publish_blocking'] as bool? ??
        (sourceKind == ProjectDependencySourceKind.path ||
            sourceKind == ProjectDependencySourceKind.git ||
            sourceKind == ProjectDependencySourceKind.unknown ||
            ((sourceKind == ProjectDependencySourceKind.registry) &&
                ((registryRoot == null || registryRoot.isEmpty) ||
                    (packageIdentity == null || packageIdentity.isEmpty) ||
                    (requestedVersion == null || requestedVersion.isEmpty)))),
  );
}

ProjectPackageSnapshot projectPackageFromPayload(Map<String, dynamic> payload) {
  return ProjectPackageSnapshot(
    packageName: payload['package_name'] as String? ?? '',
    version: payload['version'] as String? ?? '',
    rootPath: payload['root_path'] as String? ?? '',
    manifestPath: payload['manifest_path'] as String? ?? '',
    targets: (payload['targets'] as List? ?? const <Object>[])
        .whereType<Map<String, dynamic>>()
        .map(projectTargetFromPayload)
        .toList(growable: false),
    dependencies: (payload['dependencies'] as List? ?? const <Object>[])
        .whereType<Map<String, dynamic>>()
        .map(projectDependencyFromPayload)
        .toList(growable: false),
    isWorkspaceMember: payload['is_workspace_member'] as bool? ?? false,
    publishEnabled: payload['publish_enabled'] as bool? ?? false,
  );
}

PackageDistributionSnapshot? derivePackageDistributionFromPackages(
  List<ProjectPackageSnapshot> packages,
) {
  if (packages.isEmpty) {
    return null;
  }

  final registrySources = <String, _MutableRegistrySourceSummary>{};
  final distributionPackages = packages
      .map((package) {
        final blockingReasons = <String>[];
        var runtimeRegistryDependencies = 0;
        var runtimePathDependencies = 0;
        var runtimeGitDependencies = 0;
        var devRegistryDependencies = 0;
        var devPathDependencies = 0;
        var devGitDependencies = 0;

        if (!package.publishEnabled) {
          blockingReasons.add('package publish = false');
        }

        for (final dependency in package.dependencies) {
          switch (dependency.sourceKind) {
            case ProjectDependencySourceKind.registry:
              if (dependency.kind == ProjectDependencyKind.dev) {
                devRegistryDependencies += 1;
              } else {
                runtimeRegistryDependencies += 1;
              }
              final registryRoot = dependency.registryRoot;
              if (registryRoot != null && registryRoot.isNotEmpty) {
                registrySources
                    .putIfAbsent(
                      registryRoot,
                      () => _MutableRegistrySourceSummary(
                        registryRoot: registryRoot,
                        transport: registryTransportFromRoot(registryRoot),
                      ),
                    )
                    .notePackage(package.packageName);
              }
              break;
            case ProjectDependencySourceKind.path:
              if (dependency.kind == ProjectDependencyKind.dev) {
                devPathDependencies += 1;
              } else {
                runtimePathDependencies += 1;
              }
              appendUniqueNote(
                blockingReasons,
                'dependency in [${dependency.kind == ProjectDependencyKind.dev ? 'dev-dependencies' : 'dependencies'}] uses a local path or workspace source: ${dependency.dependencyName}',
              );
              break;
            case ProjectDependencySourceKind.git:
              if (dependency.kind == ProjectDependencyKind.dev) {
                devGitDependencies += 1;
              } else {
                runtimeGitDependencies += 1;
              }
              appendUniqueNote(
                blockingReasons,
                'dependency in [${dependency.kind == ProjectDependencyKind.dev ? 'dev-dependencies' : 'dependencies'}] uses a git source: ${dependency.dependencyName}',
              );
              break;
            case ProjectDependencySourceKind.unknown:
              if (dependency.publishBlocking) {
                appendUniqueNote(
                  blockingReasons,
                  'dependency in [${dependency.kind == ProjectDependencyKind.dev ? 'dev-dependencies' : 'dependencies'}] is not registry-addressable: ${dependency.dependencyName}',
                );
              }
              break;
          }

          if (dependency.publishBlocking &&
              dependency.sourceKind == ProjectDependencySourceKind.registry) {
            appendUniqueNote(
              blockingReasons,
              'registry dependency in [${dependency.kind == ProjectDependencyKind.dev ? 'dev-dependencies' : 'dependencies'}] is incomplete: ${dependency.dependencyName}',
            );
          }
        }

        final publishReady = package.publishEnabled && blockingReasons.isEmpty;
        return PackageDistributionPackageSnapshot(
          packageName: package.packageName,
          manifestPath: package.manifestPath,
          publishEnabled: package.publishEnabled,
          publishReady: publishReady,
          blockingReasons: blockingReasons,
          runtimeRegistryDependencies: runtimeRegistryDependencies,
          runtimePathDependencies: runtimePathDependencies,
          runtimeGitDependencies: runtimeGitDependencies,
          devRegistryDependencies: devRegistryDependencies,
          devPathDependencies: devPathDependencies,
          devGitDependencies: devGitDependencies,
        );
      })
      .toList(growable: false);

  final publishablePackages = distributionPackages
      .where((package) => package.publishReady)
      .length;

  return PackageDistributionSnapshot(
    schemaVersion: 1,
    packages: distributionPackages,
    registrySources: registrySources.values
        .map(
          (registry) => RegistrySourceSnapshot(
            registryRoot: registry.registryRoot,
            transport: registry.transport,
            dependencyRefs: registry.dependencyRefs,
            packages: registry.packages.toList(growable: false),
          ),
        )
        .toList(growable: false),
    publishablePackages: publishablePackages,
    blockedPackages: distributionPackages.length - publishablePackages,
  );
}

class _MutableRegistrySourceSummary {
  _MutableRegistrySourceSummary({
    required this.registryRoot,
    required this.transport,
  });

  final String registryRoot;
  final String transport;
  int dependencyRefs = 0;
  final Set<String> packages = <String>{};

  void notePackage(String packageName) {
    dependencyRefs += 1;
    packages.add(packageName);
  }
}

String registryTransportFromRoot(String registryRoot) {
  if (registryRoot.startsWith('https://')) {
    return 'https';
  }
  if (registryRoot.startsWith('http://')) {
    return 'http';
  }
  if (registryRoot.startsWith('file://')) {
    return 'file';
  }
  return 'unknown';
}

void appendUniqueNote(List<String> notes, String note) {
  if (!notes.contains(note)) {
    notes.add(note);
  }
}

RegistrySourceSnapshot registrySourceFromPayload(Map<String, dynamic> payload) {
  return RegistrySourceSnapshot(
    registryRoot: payload['registry_root'] as String? ?? '',
    transport: payload['transport'] as String? ?? 'unknown',
    dependencyRefs: payload['dependency_refs'] as int? ?? 0,
    packages: (payload['packages'] as List? ?? const <Object>[])
        .whereType<String>()
        .toList(growable: false),
  );
}

PackageDistributionPackageSnapshot distributionPackageFromPayload(
  Map<String, dynamic> payload,
) {
  return PackageDistributionPackageSnapshot(
    packageName: payload['package_name'] as String? ?? '',
    manifestPath: payload['manifest_path'] as String? ?? '',
    publishEnabled: payload['publish_enabled'] as bool? ?? false,
    publishReady: payload['publish_ready'] as bool? ?? false,
    blockingReasons: (payload['blocking_reasons'] as List? ?? const <Object>[])
        .whereType<String>()
        .toList(growable: false),
    runtimeRegistryDependencies:
        payload['runtime_registry_dependencies'] as int? ?? 0,
    runtimePathDependencies: payload['runtime_path_dependencies'] as int? ?? 0,
    runtimeGitDependencies: payload['runtime_git_dependencies'] as int? ?? 0,
    devRegistryDependencies: payload['dev_registry_dependencies'] as int? ?? 0,
    devPathDependencies: payload['dev_path_dependencies'] as int? ?? 0,
    devGitDependencies: payload['dev_git_dependencies'] as int? ?? 0,
  );
}

PackageDistributionSnapshot packageDistributionFromPayload(
  Map<String, dynamic> payload,
) {
  return PackageDistributionSnapshot(
    schemaVersion: payload['schema_version'] as int? ?? 1,
    packages: (payload['packages'] as List? ?? const <Object>[])
        .whereType<Map<String, dynamic>>()
        .map(distributionPackageFromPayload)
        .toList(growable: false),
    registrySources: (payload['registry_sources'] as List? ?? const <Object>[])
        .whereType<Map<String, dynamic>>()
        .map(registrySourceFromPayload)
        .toList(growable: false),
    publishablePackages: payload['publishable_packages'] as int? ?? 0,
    blockedPackages: payload['blocked_packages'] as int? ?? 0,
  );
}

GitCacheStateSnapshot gitCacheStateFromPayload(Map<String, dynamic> payload) {
  return GitCacheStateSnapshot(
    reposRoot: payload['repos_root'] as String?,
    checkoutsRoot: payload['checkouts_root'] as String?,
    reposPresent: payload['repos_present'] as bool? ?? false,
    checkoutsPresent: payload['checkouts_present'] as bool? ?? false,
  );
}

RegistryCacheStateSnapshot registryCacheStateFromPayload(
  Map<String, dynamic> payload,
) {
  return RegistryCacheStateSnapshot(
    cacheRoot: payload['cache_root'] as String?,
    indexRoot: payload['index_root'] as String?,
    blobRoot: payload['blob_root'] as String?,
    checkoutRoot: payload['checkout_root'] as String?,
    indexPresent: payload['index_present'] as bool? ?? false,
    blobsPresent: payload['blobs_present'] as bool? ?? false,
    checkoutsPresent: payload['checkouts_present'] as bool? ?? false,
  );
}

VendorSourceStateSnapshot vendorSourceStateFromPayload(
  Map<String, dynamic> payload,
) {
  return VendorSourceStateSnapshot(
    vendorRoot: payload['vendor_root'] as String?,
    metadataPath: payload['metadata_path'] as String?,
    vendorPresent: payload['vendor_present'] as bool? ?? false,
    metadataPresent: payload['metadata_present'] as bool? ?? false,
    gitSnapshots: payload['git_snapshots'] as int? ?? 0,
  );
}

ProjectSourceStateSnapshot projectSourceStateFromPayload(
  Map<String, dynamic> payload,
) {
  return ProjectSourceStateSnapshot(
    schemaVersion: payload['schema_version'] as int? ?? 1,
    spioHome: payload['spio_home'] as String?,
    declaredGitDependencies: payload['declared_git_dependencies'] as int? ?? 0,
    declaredRegistryDependencies:
        payload['declared_registry_dependencies'] as int? ?? 0,
    gitCache: payload['git_cache'] is Map<String, dynamic>
        ? gitCacheStateFromPayload(payload['git_cache'] as Map<String, dynamic>)
        : const GitCacheStateSnapshot(),
    registryCache: payload['registry_cache'] is Map<String, dynamic>
        ? registryCacheStateFromPayload(
            payload['registry_cache'] as Map<String, dynamic>,
          )
        : const RegistryCacheStateSnapshot(),
    vendor: payload['vendor'] is Map<String, dynamic>
        ? vendorSourceStateFromPayload(
            payload['vendor'] as Map<String, dynamic>,
          )
        : const VendorSourceStateSnapshot(),
  );
}

ToolchainStatusSnapshot toolchainStatusFromPayload(
  Map<String, dynamic> payload,
) {
  return ToolchainStatusSnapshot(
    source: toolchainSourceFromString(payload['source'] as String?),
    detail: payload['detail'] as String? ?? 'No toolchain detail published.',
    pinPath: payload['pin_path'] as String?,
    channel: payload['channel'] as String?,
    version: payload['version'] as String?,
  );
}

ManagedToolchainInstallSnapshot managedToolchainInstallFromPayload(
  Map<String, dynamic> payload,
) {
  return ManagedToolchainInstallSnapshot(
    channel: payload['channel'] as String? ?? 'unknown',
    compilerVersion: payload['compiler_version'] as String? ?? 'unknown',
    installRoot: payload['install_root'] as String? ?? '',
    installBinaryPath: payload['install_binary_path'] as String? ?? '',
    installMetadataPath: payload['install_metadata_path'] as String?,
  );
}

ManagedToolchainStateSnapshot managedToolchainStateFromPayload(
  Map<String, dynamic> payload,
) {
  return ManagedToolchainStateSnapshot(
    spioHome: payload['spio_home'] as String?,
    currentBinaryPath: payload['current_binary'] as String?,
    currentMetadataPath: payload['current_metadata_path'] as String?,
    installed: (payload['installed'] as List? ?? const <Object>[])
        .whereType<Map<String, dynamic>>()
        .map(managedToolchainInstallFromPayload)
        .toList(growable: false),
  );
}

CompilerHandshakeSnapshot compilerHandshakeFromPayload(
  Map<String, dynamic> payload,
) {
  final contracts = <String, List<int>>{};
  final rawContracts = payload['supported_contract_versions'];
  if (rawContracts is Map<String, dynamic>) {
    for (final entry in rawContracts.entries) {
      final versions = entry.value;
      if (versions is List) {
        contracts[entry.key] = versions
            .whereType<num>()
            .map((value) => value.toInt())
            .toList(growable: false);
      }
    }
  }

  return CompilerHandshakeSnapshot(
    binaryPath:
        payload['binary_path'] as String? ?? payload['binary'] as String? ?? '',
    tool: payload['tool'] as String? ?? 'styio',
    compilerVersion: payload['compiler_version'] as String? ?? 'unknown',
    channel: payload['channel'] as String? ?? 'unknown',
    variant: payload['variant'] as String? ?? 'unknown',
    capabilities: (payload['capabilities'] as List? ?? const <Object>[])
        .whereType<String>()
        .toList(growable: false),
    supportedContractVersions: contracts,
    integrationPhase:
        payload['integration_phase'] as String? ??
        payload['active_integration_phase'] as String? ??
        'unknown',
    supportedAdapterModes:
        (payload['supported_adapter_modes'] as List? ?? const <Object>[])
            .whereType<String>()
            .toList(growable: false),
    featureFlags: parseBoolMap(payload['feature_flags']),
  );
}

Map<String, bool> parseBoolMap(Object? raw) {
  if (raw is! Map) {
    return const <String, bool>{};
  }

  final parsed = <String, bool>{};
  for (final entry in raw.entries) {
    if (entry.key is String && entry.value is bool) {
      parsed[entry.key as String] = entry.value as bool;
    }
  }
  return Map<String, bool>.unmodifiable(parsed);
}

DateTime? _dateTimeFromString(String? raw) {
  if (raw == null || raw.isEmpty) {
    return null;
  }
  return DateTime.tryParse(raw)?.toUtc();
}

HostedWorkspaceStatus _hostedWorkspaceStatusFromString(String? raw) {
  switch (raw) {
    case 'provisioning':
      return HostedWorkspaceStatus.provisioning;
    case 'closing':
      return HostedWorkspaceStatus.closing;
    case 'pending-deletion':
    case 'pending_deletion':
      return HostedWorkspaceStatus.pendingDeletion;
    case 'deleted':
      return HostedWorkspaceStatus.deleted;
    case 'active':
    default:
      return HostedWorkspaceStatus.active;
  }
}

HostedWorkspaceExportState _hostedWorkspaceExportStateFromString(String? raw) {
  switch (raw) {
    case 'preparing':
      return HostedWorkspaceExportState.preparing;
    case 'ready':
      return HostedWorkspaceExportState.ready;
    case 'expired':
      return HostedWorkspaceExportState.expired;
    case 'not-requested':
    case 'not_requested':
    default:
      return HostedWorkspaceExportState.notRequested;
  }
}
