enum ProjectKind { scratch, package, workspace, combinedRoot, hosted }

extension ProjectKindX on ProjectKind {
  String get label {
    switch (this) {
      case ProjectKind.scratch:
        return 'scratch';
      case ProjectKind.package:
        return 'package';
      case ProjectKind.workspace:
        return 'workspace';
      case ProjectKind.combinedRoot:
        return 'combined-root';
      case ProjectKind.hosted:
        return 'hosted';
    }
  }
}

enum ProjectTargetKind { lib, bin, test }

extension ProjectTargetKindX on ProjectTargetKind {
  String get label {
    switch (this) {
      case ProjectTargetKind.lib:
        return 'lib';
      case ProjectTargetKind.bin:
        return 'bin';
      case ProjectTargetKind.test:
        return 'test';
    }
  }
}

enum ProjectDependencyKind { runtime, dev }

extension ProjectDependencyKindX on ProjectDependencyKind {
  String get label {
    switch (this) {
      case ProjectDependencyKind.runtime:
        return 'runtime';
      case ProjectDependencyKind.dev:
        return 'dev';
    }
  }
}

enum ProjectDependencySourceKind { path, git, registry, unknown }

extension ProjectDependencySourceKindX on ProjectDependencySourceKind {
  String get label {
    switch (this) {
      case ProjectDependencySourceKind.path:
        return 'path';
      case ProjectDependencySourceKind.git:
        return 'git';
      case ProjectDependencySourceKind.registry:
        return 'registry';
      case ProjectDependencySourceKind.unknown:
        return 'unknown';
    }
  }
}

enum ProjectLockState { fresh, stale, missing, unknown }

extension ProjectLockStateX on ProjectLockState {
  String get label {
    switch (this) {
      case ProjectLockState.fresh:
        return 'fresh';
      case ProjectLockState.stale:
        return 'stale';
      case ProjectLockState.missing:
        return 'missing';
      case ProjectLockState.unknown:
        return 'unknown';
    }
  }
}

enum ProjectVendorState { present, missing, unknown }

extension ProjectVendorStateX on ProjectVendorState {
  String get label {
    switch (this) {
      case ProjectVendorState.present:
        return 'present';
      case ProjectVendorState.missing:
        return 'missing';
      case ProjectVendorState.unknown:
        return 'unknown';
    }
  }
}

enum ToolchainResolutionSource {
  projectPin,
  managedCurrent,
  environment,
  unavailable,
  unknown,
}

extension ToolchainResolutionSourceX on ToolchainResolutionSource {
  String get label {
    switch (this) {
      case ToolchainResolutionSource.projectPin:
        return 'project-pin';
      case ToolchainResolutionSource.managedCurrent:
        return 'managed-current';
      case ToolchainResolutionSource.environment:
        return 'environment';
      case ToolchainResolutionSource.unavailable:
        return 'unavailable';
      case ToolchainResolutionSource.unknown:
        return 'unknown';
    }
  }
}

enum HostedWorkspaceStatus {
  provisioning,
  active,
  closing,
  pendingDeletion,
  deleted,
}

extension HostedWorkspaceStatusX on HostedWorkspaceStatus {
  String get label {
    switch (this) {
      case HostedWorkspaceStatus.provisioning:
        return 'provisioning';
      case HostedWorkspaceStatus.active:
        return 'active';
      case HostedWorkspaceStatus.closing:
        return 'closing';
      case HostedWorkspaceStatus.pendingDeletion:
        return 'pending-deletion';
      case HostedWorkspaceStatus.deleted:
        return 'deleted';
    }
  }
}

enum HostedWorkspaceExportState { notRequested, preparing, ready, expired }

extension HostedWorkspaceExportStateX on HostedWorkspaceExportState {
  String get label {
    switch (this) {
      case HostedWorkspaceExportState.notRequested:
        return 'not-requested';
      case HostedWorkspaceExportState.preparing:
        return 'preparing';
      case HostedWorkspaceExportState.ready:
        return 'ready';
      case HostedWorkspaceExportState.expired:
        return 'expired';
    }
  }
}

class HostedWorkspaceRecordSnapshot {
  const HostedWorkspaceRecordSnapshot({
    required this.workspaceId,
    required this.schemaVersion,
    required this.ownerRef,
    required this.status,
    required this.entryUrl,
    required this.createdAt,
    required this.lastActiveAt,
    required this.retentionDays,
    required this.exportState,
    this.closedAt,
    this.retentionDeadline,
    this.coreFileExportUrl,
    this.coreFileExportExpiresAt,
  });

  final String workspaceId;
  final String schemaVersion;
  final String ownerRef;
  final HostedWorkspaceStatus status;
  final String entryUrl;
  final DateTime createdAt;
  final DateTime lastActiveAt;
  final int retentionDays;
  final HostedWorkspaceExportState exportState;
  final DateTime? closedAt;
  final DateTime? retentionDeadline;
  final String? coreFileExportUrl;
  final DateTime? coreFileExportExpiresAt;
}

class ProjectTargetDescriptor {
  const ProjectTargetDescriptor({
    required this.id,
    required this.packageName,
    required this.kind,
    required this.name,
    required this.filePath,
  });

  final String id;
  final String packageName;
  final ProjectTargetKind kind;
  final String name;
  final String filePath;
}

class ProjectPackageSnapshot {
  const ProjectPackageSnapshot({
    required this.packageName,
    required this.version,
    required this.rootPath,
    required this.manifestPath,
    required this.targets,
    this.dependencies = const <ProjectDependencySnapshot>[],
    this.isWorkspaceMember = false,
    this.publishEnabled = false,
  });

  final String packageName;
  final String version;
  final String rootPath;
  final String manifestPath;
  final List<ProjectTargetDescriptor> targets;
  final List<ProjectDependencySnapshot> dependencies;
  final bool isWorkspaceMember;
  final bool publishEnabled;
}

class ProjectDependencySnapshot {
  const ProjectDependencySnapshot({
    required this.sourcePackageName,
    required this.dependencyName,
    required this.kind,
    required this.requirement,
    this.isWorkspaceReference = false,
    this.packageIdentity,
    this.sourceKind = ProjectDependencySourceKind.unknown,
    this.pathSource,
    this.gitSource,
    this.gitRevision,
    this.registryRoot,
    this.requestedVersion,
    this.publishBlocking = false,
  });

  final String sourcePackageName;
  final String dependencyName;
  final ProjectDependencyKind kind;
  final String requirement;
  final bool isWorkspaceReference;
  final String? packageIdentity;
  final ProjectDependencySourceKind sourceKind;
  final String? pathSource;
  final String? gitSource;
  final String? gitRevision;
  final String? registryRoot;
  final String? requestedVersion;
  final bool publishBlocking;
}

class ToolchainStatusSnapshot {
  const ToolchainStatusSnapshot({
    required this.source,
    required this.detail,
    this.pinPath,
    this.channel,
    this.version,
  });

  final ToolchainResolutionSource source;
  final String detail;
  final String? pinPath;
  final String? channel;
  final String? version;
}

class CompilerHandshakeSnapshot {
  const CompilerHandshakeSnapshot({
    required this.binaryPath,
    required this.tool,
    required this.compilerVersion,
    required this.channel,
    required this.variant,
    required this.capabilities,
    required this.supportedContractVersions,
    required this.integrationPhase,
    this.supportedAdapterModes = const <String>[],
    this.featureFlags = const <String, bool>{},
  });

  final String binaryPath;
  final String tool;
  final String compilerVersion;
  final String channel;
  final String variant;
  final List<String> capabilities;
  final Map<String, List<int>> supportedContractVersions;
  final String integrationPhase;
  final List<String> supportedAdapterModes;
  final Map<String, bool> featureFlags;

  bool supportsContract(String contractName) {
    return supportedContractVersions[contractName]?.isNotEmpty == true;
  }

  bool hasFeatureFlag(String featureName) {
    return featureFlags[featureName] == true;
  }

  String get contractSummary {
    if (supportedContractVersions.isEmpty) {
      return 'no published contract versions';
    }
    return supportedContractVersions.entries
        .map((entry) => '${entry.key}:${entry.value.join('/')}')
        .join(' · ');
  }

  String get capabilitySummary {
    if (capabilities.isEmpty) {
      return 'no declared capabilities';
    }
    return capabilities.join(' · ');
  }
}

class ManagedToolchainInstallSnapshot {
  const ManagedToolchainInstallSnapshot({
    required this.channel,
    required this.compilerVersion,
    required this.installRoot,
    required this.installBinaryPath,
    this.installMetadataPath,
  });

  final String channel;
  final String compilerVersion;
  final String installRoot;
  final String installBinaryPath;
  final String? installMetadataPath;
}

class ManagedToolchainStateSnapshot {
  const ManagedToolchainStateSnapshot({
    this.spioHome,
    this.currentBinaryPath,
    this.currentMetadataPath,
    this.installed = const <ManagedToolchainInstallSnapshot>[],
  });

  final String? spioHome;
  final String? currentBinaryPath;
  final String? currentMetadataPath;
  final List<ManagedToolchainInstallSnapshot> installed;
}

class ProjectToolchainPinSnapshot {
  const ProjectToolchainPinSnapshot({
    required this.path,
    this.channel,
    this.version,
    this.installRoot,
    this.installBinaryPath,
    required this.installPresent,
  });

  final String path;
  final String? channel;
  final String? version;
  final String? installRoot;
  final String? installBinaryPath;
  final bool installPresent;
}

class ToolchainEnvironmentSnapshot {
  const ToolchainEnvironmentSnapshot({
    required this.schemaVersion,
    required this.toolchain,
    required this.managedToolchains,
    this.candidateBinaryPath,
    this.projectPin,
    this.activeCompiler,
    this.activeCompilerError,
    this.currentCompiler,
    this.currentCompilerError,
    this.notes = const <String>[],
  });

  final int schemaVersion;
  final ToolchainStatusSnapshot toolchain;
  final String? candidateBinaryPath;
  final ProjectToolchainPinSnapshot? projectPin;
  final CompilerHandshakeSnapshot? activeCompiler;
  final String? activeCompilerError;
  final CompilerHandshakeSnapshot? currentCompiler;
  final String? currentCompilerError;
  final ManagedToolchainStateSnapshot managedToolchains;
  final List<String> notes;
}

class RegistrySourceSnapshot {
  const RegistrySourceSnapshot({
    required this.registryRoot,
    required this.transport,
    required this.dependencyRefs,
    this.packages = const <String>[],
  });

  final String registryRoot;
  final String transport;
  final int dependencyRefs;
  final List<String> packages;
}

class PackageDistributionPackageSnapshot {
  const PackageDistributionPackageSnapshot({
    required this.packageName,
    required this.manifestPath,
    required this.publishEnabled,
    required this.publishReady,
    this.blockingReasons = const <String>[],
    this.runtimeRegistryDependencies = 0,
    this.runtimePathDependencies = 0,
    this.runtimeGitDependencies = 0,
    this.devRegistryDependencies = 0,
    this.devPathDependencies = 0,
    this.devGitDependencies = 0,
  });

  final String packageName;
  final String manifestPath;
  final bool publishEnabled;
  final bool publishReady;
  final List<String> blockingReasons;
  final int runtimeRegistryDependencies;
  final int runtimePathDependencies;
  final int runtimeGitDependencies;
  final int devRegistryDependencies;
  final int devPathDependencies;
  final int devGitDependencies;
}

class PackageDistributionSnapshot {
  const PackageDistributionSnapshot({
    required this.schemaVersion,
    this.packages = const <PackageDistributionPackageSnapshot>[],
    this.registrySources = const <RegistrySourceSnapshot>[],
    this.publishablePackages = 0,
    this.blockedPackages = 0,
  });

  final int schemaVersion;
  final List<PackageDistributionPackageSnapshot> packages;
  final List<RegistrySourceSnapshot> registrySources;
  final int publishablePackages;
  final int blockedPackages;
}

class GitCacheStateSnapshot {
  const GitCacheStateSnapshot({
    this.reposRoot,
    this.checkoutsRoot,
    this.reposPresent = false,
    this.checkoutsPresent = false,
  });

  final String? reposRoot;
  final String? checkoutsRoot;
  final bool reposPresent;
  final bool checkoutsPresent;
}

class RegistryCacheStateSnapshot {
  const RegistryCacheStateSnapshot({
    this.cacheRoot,
    this.indexRoot,
    this.blobRoot,
    this.checkoutRoot,
    this.indexPresent = false,
    this.blobsPresent = false,
    this.checkoutsPresent = false,
  });

  final String? cacheRoot;
  final String? indexRoot;
  final String? blobRoot;
  final String? checkoutRoot;
  final bool indexPresent;
  final bool blobsPresent;
  final bool checkoutsPresent;
}

class VendorSourceStateSnapshot {
  const VendorSourceStateSnapshot({
    this.vendorRoot,
    this.metadataPath,
    this.vendorPresent = false,
    this.metadataPresent = false,
    this.gitSnapshots = 0,
  });

  final String? vendorRoot;
  final String? metadataPath;
  final bool vendorPresent;
  final bool metadataPresent;
  final int gitSnapshots;
}

class ProjectSourceStateSnapshot {
  const ProjectSourceStateSnapshot({
    required this.schemaVersion,
    this.spioHome,
    this.declaredGitDependencies = 0,
    this.declaredRegistryDependencies = 0,
    this.gitCache = const GitCacheStateSnapshot(),
    this.registryCache = const RegistryCacheStateSnapshot(),
    this.vendor = const VendorSourceStateSnapshot(),
  });

  final int schemaVersion;
  final String? spioHome;
  final int declaredGitDependencies;
  final int declaredRegistryDependencies;
  final GitCacheStateSnapshot gitCache;
  final RegistryCacheStateSnapshot registryCache;
  final VendorSourceStateSnapshot vendor;
}

class PublishedPayloadFailure {
  const PublishedPayloadFailure({required this.command, required this.detail});

  final String command;
  final String detail;
}

class ProjectGraphSnapshot {
  const ProjectGraphSnapshot({
    required this.id,
    required this.title,
    required this.kind,
    required this.workspaceRoot,
    required this.workspaceMembers,
    required this.packages,
    required this.dependencies,
    required this.targets,
    required this.editorFiles,
    required this.toolchain,
    required this.lockState,
    required this.vendorState,
    required this.notes,
    this.manifestPath,
    this.lockfilePath,
    this.toolchainPinPath,
    this.styioConfigPath,
    this.vendorRoot,
    this.buildRoot,
    this.activeCompiler,
    this.toolchainEnvironment,
    this.packageDistribution,
    this.sourceState,
    this.projectGraphPayloadFailure,
    this.toolchainStatePayloadFailure,
    this.hostedWorkspace,
  });

  final String id;
  final String title;
  final ProjectKind kind;
  final String workspaceRoot;
  final List<String> workspaceMembers;
  final String? manifestPath;
  final String? lockfilePath;
  final String? toolchainPinPath;
  final String? styioConfigPath;
  final String? vendorRoot;
  final String? buildRoot;
  final List<ProjectPackageSnapshot> packages;
  final List<ProjectDependencySnapshot> dependencies;
  final List<ProjectTargetDescriptor> targets;
  final List<String> editorFiles;
  final ToolchainStatusSnapshot toolchain;
  final ProjectLockState lockState;
  final ProjectVendorState vendorState;
  final CompilerHandshakeSnapshot? activeCompiler;
  final ToolchainEnvironmentSnapshot? toolchainEnvironment;
  final PackageDistributionSnapshot? packageDistribution;
  final ProjectSourceStateSnapshot? sourceState;
  final PublishedPayloadFailure? projectGraphPayloadFailure;
  final PublishedPayloadFailure? toolchainStatePayloadFailure;
  final HostedWorkspaceRecordSnapshot? hostedWorkspace;
  final List<String> notes;

  bool get hasManifest => manifestPath != null;

  bool get hasActiveCompiler => activeCompiler != null;

  bool get hasToolchainEnvironment => toolchainEnvironment != null;

  bool get hasPackageDistribution => packageDistribution != null;

  bool get hasSourceState => sourceState != null;

  bool get hasProjectGraphPayloadFailure => projectGraphPayloadFailure != null;

  bool get hasToolchainStatePayloadFailure =>
      toolchainStatePayloadFailure != null;

  bool get isScratch => kind == ProjectKind.scratch;

  bool get isHosted => kind == ProjectKind.hosted;

  bool get hasHostedWorkspace => hostedWorkspace != null;

  int get packageCount => packages.length;

  int get targetCount => targets.length;

  int get editorFileCount => editorFiles.length;

  int get workspaceMemberCount => workspaceMembers.length;

  int get dependencyCount => dependencies.length;

  bool get compilePlanConsumerAdvertised =>
      activeCompiler?.hasFeatureFlag('compile_plan_consumer') == true ||
      activeCompiler?.supportsContract('compile_plan') == true;

  bool get jitRouteAdvertised =>
      activeCompiler?.hasFeatureFlag('jit_route') == true ||
      activeCompiler?.hasFeatureFlag('jit_consumer') == true ||
      activeCompiler?.supportsContract('jit') == true ||
      activeCompiler?.supportsContract('jit_route') == true;

  ProjectGraphSnapshot copyWith({
    ToolchainStatusSnapshot? toolchain,
    CompilerHandshakeSnapshot? activeCompiler,
    ToolchainEnvironmentSnapshot? toolchainEnvironment,
    PackageDistributionSnapshot? packageDistribution,
    ProjectSourceStateSnapshot? sourceState,
    PublishedPayloadFailure? projectGraphPayloadFailure,
    PublishedPayloadFailure? toolchainStatePayloadFailure,
    HostedWorkspaceRecordSnapshot? hostedWorkspace,
    List<String>? notes,
  }) {
    return ProjectGraphSnapshot(
      id: id,
      title: title,
      kind: kind,
      workspaceRoot: workspaceRoot,
      workspaceMembers: workspaceMembers,
      manifestPath: manifestPath,
      lockfilePath: lockfilePath,
      toolchainPinPath: toolchainPinPath,
      styioConfigPath: styioConfigPath,
      vendorRoot: vendorRoot,
      buildRoot: buildRoot,
      packages: packages,
      dependencies: dependencies,
      targets: targets,
      editorFiles: editorFiles,
      toolchain: toolchain ?? this.toolchain,
      lockState: lockState,
      vendorState: vendorState,
      activeCompiler: activeCompiler ?? this.activeCompiler,
      toolchainEnvironment: toolchainEnvironment ?? this.toolchainEnvironment,
      packageDistribution: packageDistribution ?? this.packageDistribution,
      sourceState: sourceState ?? this.sourceState,
      projectGraphPayloadFailure:
          projectGraphPayloadFailure ?? this.projectGraphPayloadFailure,
      toolchainStatePayloadFailure:
          toolchainStatePayloadFailure ?? this.toolchainStatePayloadFailure,
      hostedWorkspace: hostedWorkspace ?? this.hostedWorkspace,
      notes: notes ?? this.notes,
    );
  }

  static ProjectGraphSnapshot scratch({
    required String workspaceRoot,
    required String activeFilePath,
    required String title,
    required List<String> notes,
    ToolchainStatusSnapshot? toolchain,
    CompilerHandshakeSnapshot? activeCompiler,
    ToolchainEnvironmentSnapshot? toolchainEnvironment,
    PackageDistributionSnapshot? packageDistribution,
    ProjectSourceStateSnapshot? sourceState,
    PublishedPayloadFailure? projectGraphPayloadFailure,
    PublishedPayloadFailure? toolchainStatePayloadFailure,
    HostedWorkspaceRecordSnapshot? hostedWorkspace,
  }) {
    return ProjectGraphSnapshot(
      id: 'scratch:${workspaceRoot.hashCode}',
      title: title,
      kind: ProjectKind.scratch,
      workspaceRoot: workspaceRoot,
      workspaceMembers: const <String>[],
      manifestPath: null,
      lockfilePath: '$workspaceRoot/spio.lock',
      toolchainPinPath: null,
      styioConfigPath: null,
      vendorRoot: '$workspaceRoot/.spio/vendor',
      buildRoot: '$workspaceRoot/.spio/build',
      packages: const <ProjectPackageSnapshot>[],
      dependencies: const <ProjectDependencySnapshot>[],
      targets: const <ProjectTargetDescriptor>[],
      editorFiles: <String>[activeFilePath],
      toolchain:
          toolchain ??
          const ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.unavailable,
            detail: 'No project toolchain pin is active in scratch mode.',
          ),
      lockState: ProjectLockState.missing,
      vendorState: ProjectVendorState.missing,
      activeCompiler: activeCompiler,
      toolchainEnvironment: toolchainEnvironment,
      packageDistribution: packageDistribution,
      sourceState: sourceState,
      projectGraphPayloadFailure: projectGraphPayloadFailure,
      toolchainStatePayloadFailure: toolchainStatePayloadFailure,
      hostedWorkspace: hostedWorkspace,
      notes: notes,
    );
  }
}
