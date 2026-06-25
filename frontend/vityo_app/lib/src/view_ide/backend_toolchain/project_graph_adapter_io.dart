import 'dart:convert';
import 'dart:io';

import '../platform/platform_target.dart';
import 'adapter_contracts.dart';
import 'hosted_control_plane.dart';
import 'hosted_payload_codec.dart';
import 'project_graph_adapter.dart';
import 'project_graph_contract.dart';
import 'spio_cli_discovery.dart' show appendSpioExecutableCandidates;

Map<String, String> Function() _environmentProvider = () =>
    Platform.environment;

void debugOverrideProjectGraphEnvironment(Map<String, String>? environment) {
  _environmentProvider = environment == null
      ? () => Platform.environment
      : () => Map<String, String>.unmodifiable(environment);
}

Future<ProjectGraphAdapter> createPlatformProjectGraphAdapter({
  required PlatformTarget platformTarget,
}) async {
  final hostedClient = await createHostedControlPlaneClient(
    platformTarget: platformTarget,
  );
  if (hostedClient != null) {
    return _HostedProjectGraphAdapter(
      platformTarget: platformTarget,
      hostedClient: hostedClient,
    );
  }
  final rootDirectory = _discoverProjectRoot(Directory.current);
  final support = await _probeSpioProjectGraphSupport(
    startDirectory: rootDirectory,
  );
  return _LocalProjectGraphAdapter(
    platformTarget: platformTarget,
    projectGraphSupport: support,
  );
}

class _HostedProjectGraphAdapter implements ProjectGraphAdapter {
  _HostedProjectGraphAdapter({
    required this.platformTarget,
    required this.hostedClient,
  }) : _workspaceId = hostedClient.config.workspaceId;

  final PlatformTarget platformTarget;
  final HostedControlPlaneClient hostedClient;
  String? _workspaceId;

  @override
  AdapterCapabilitySnapshot
  get capabilitySnapshot => const AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cloud,
    languageService: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.partial,
      detail: 'Hosted language service stays reserved behind the cloud route.',
    ),
    projectGraph: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail:
          'Hosted workspaces publish project graph through the hosted control plane.',
      supportedContractVersions: <int>[1],
    ),
    execution: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail: 'Hosted execution is live through the shared control plane.',
      supportedContractVersions: <int>[1],
    ),
    runtimeEvents: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail:
          'Hosted execution publishes replayable runtime event payloads through the shared control plane.',
      supportedContractVersions: <int>[1],
    ),
  );

  @override
  Future<ProjectGraphSnapshot> loadProjectGraph() async {
    final response = _workspaceId == null
        ? await hostedClient.openWorkspace(platformTarget: platformTarget)
        : await hostedClient.projectGraph(workspaceId: _workspaceId!);
    final snapshot = hostedProjectGraphSnapshotFromEnvelope(response);
    _workspaceId = snapshot.hostedWorkspace?.workspaceId ?? _workspaceId;
    return snapshot;
  }
}

class _LocalProjectGraphAdapter implements ProjectGraphAdapter {
  _LocalProjectGraphAdapter({
    required this.platformTarget,
    required this.projectGraphSupport,
  });

  final PlatformTarget platformTarget;
  final _SpioProjectGraphSupport projectGraphSupport;
  PublishedPayloadFailure? _lastProjectGraphPayloadFailure;
  PublishedPayloadFailure? _lastToolchainStatePayloadFailure;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cli,
    languageService: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Language-service data still needs a published styio contract.',
    ),
    projectGraph: AdapterEndpointCapability(
      level: _projectGraphCapabilityLevel(),
      detail: _projectGraphCapabilityDetail(),
      supportedContractVersions: projectGraphSupport.publishedPayloadAvailable
          ? const <int>[1]
          : const <int>[],
    ),
    execution: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail:
          'Execution capability is provided by the dedicated execution adapter.',
    ),
    runtimeEvents: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail:
          'Runtime events are not exposed through the current CLI project graph path.',
    ),
  );

  @override
  Future<ProjectGraphSnapshot> loadProjectGraph() async {
    _lastProjectGraphPayloadFailure = null;
    _lastToolchainStatePayloadFailure = null;
    final rootDirectory = _discoverProjectRoot(Directory.current);
    final manifestFile = File(_joinPath(rootDirectory.path, 'spio.toml'));
    final toolchainPin = _findUpwardFile(
      startDirectory: rootDirectory,
      candidates: const <String>['spio-toolchain.toml'],
    );
    final styioConfig = _findUpwardFile(
      startDirectory: rootDirectory,
      candidates: const <String>['styio.toml', '.styio.toml'],
    );
    final styioBinaryOverride = _styioBinaryOverrideFromEnvironment();
    final compiler = await _probeCompiler(startDirectory: rootDirectory);
    final hasManifest = await manifestFile.exists();
    final publishedToolchainEnvironmentResult =
        projectGraphSupport.toolchainStateAvailable
        ? await _loadPublishedToolchainEnvironment(
            spioBinary: projectGraphSupport.binaryPath,
            manifestPath: hasManifest ? manifestFile.path : null,
            styioBinaryOverride: styioBinaryOverride,
          )
        : const _PublishedPayloadLoadResult<
            ToolchainEnvironmentSnapshot
          >.success(null);
    final publishedToolchainEnvironment =
        publishedToolchainEnvironmentResult.payload;
    _lastToolchainStatePayloadFailure =
        publishedToolchainEnvironmentResult.failure;
    final pinnedToolchain = toolchainPin == null
        ? const _ParsedToolchain()
        : await _parseToolchainPin(toolchainPin);

    if (!hasManifest) {
      final fallbackFile = _joinPath(
        _joinPath(rootDirectory.path, 'scratch'),
        'main.styio',
      );
      return ProjectGraphSnapshot.scratch(
        workspaceRoot: rootDirectory.path,
        activeFilePath: fallbackFile,
        title: 'Scratch Project',
        toolchain:
            publishedToolchainEnvironment?.toolchain ??
            ToolchainStatusSnapshot(
              source: toolchainPin == null
                  ? ToolchainResolutionSource.unavailable
                  : ToolchainResolutionSource.projectPin,
              detail: toolchainPin == null
                  ? 'No spio.toml discovered. The shell is running in scratch mode.'
                  : 'Project toolchain pin is present but no manifest was discovered.',
              pinPath: toolchainPin,
            ),
        activeCompiler:
            publishedToolchainEnvironment?.activeCompiler ?? compiler,
        toolchainEnvironment: publishedToolchainEnvironment,
        toolchainStatePayloadFailure: _lastToolchainStatePayloadFailure,
        notes: <String>[
          'No spio.toml was found while scanning upward from ${Directory.current.path}.',
          'The editor remains usable in scratch mode and can still target published styio single-file execution.',
          if (_lastToolchainStatePayloadFailure != null)
            _publishedPayloadFailureNote(_lastToolchainStatePayloadFailure!),
          ...?publishedToolchainEnvironment?.notes,
        ],
      );
    }

    final publishedSnapshotResult =
        projectGraphSupport.publishedPayloadAvailable
        ? await _loadPublishedProjectGraph(
            spioBinary: projectGraphSupport.binaryPath,
            manifestPath: manifestFile.path,
            styioBinaryOverride: styioBinaryOverride,
          )
        : const _PublishedPayloadLoadResult<ProjectGraphSnapshot>.success(null);
    final publishedSnapshot = publishedSnapshotResult.payload;
    _lastProjectGraphPayloadFailure = publishedSnapshotResult.failure;
    if (publishedSnapshot != null) {
      return publishedSnapshot.copyWith(
        toolchain:
            publishedToolchainEnvironment?.toolchain ??
            publishedSnapshot.toolchain,
        activeCompiler:
            publishedToolchainEnvironment?.activeCompiler ??
            publishedSnapshot.activeCompiler,
        toolchainEnvironment:
            publishedToolchainEnvironment ??
            publishedSnapshot.toolchainEnvironment,
        projectGraphPayloadFailure: _lastProjectGraphPayloadFailure,
        toolchainStatePayloadFailure: _lastToolchainStatePayloadFailure,
        notes: _mergeNotes(
          _mergeNotes(
            publishedSnapshot.notes,
            _publishedPayloadFailureNotes(
              projectGraphPayloadFailure: _lastProjectGraphPayloadFailure,
              toolchainStatePayloadFailure: _lastToolchainStatePayloadFailure,
            ),
          ),
          publishedToolchainEnvironment?.notes ?? const <String>[],
        ),
      );
    }

    final parsedRoot = await _parseManifest(
      manifestPath: manifestFile.path,
      workspaceRoot: rootDirectory.path,
      isWorkspaceMember: false,
    );

    final packages = <ProjectPackageSnapshot>[];
    final dependencies = <ProjectDependencySnapshot>[];
    final targets = <ProjectTargetDescriptor>[];

    if (parsedRoot.package != null) {
      packages.add(parsedRoot.package!);
      dependencies.addAll(parsedRoot.dependencies);
      targets.addAll(parsedRoot.package!.targets);
    }

    for (final member in parsedRoot.workspaceMembers) {
      final memberManifestPath = _joinPath(
        _joinPath(rootDirectory.path, member),
        'spio.toml',
      );
      final memberManifest = File(memberManifestPath);
      if (!await memberManifest.exists()) {
        continue;
      }
      final parsedMember = await _parseManifest(
        manifestPath: memberManifestPath,
        workspaceRoot: _joinPath(rootDirectory.path, member),
        isWorkspaceMember: true,
      );
      if (parsedMember.package != null) {
        packages.add(parsedMember.package!);
        dependencies.addAll(parsedMember.dependencies);
        targets.addAll(parsedMember.package!.targets);
      }
    }

    final manifestKind = parsedRoot.workspaceMembers.isNotEmpty
        ? (parsedRoot.package != null
              ? ProjectKind.combinedRoot
              : ProjectKind.workspace)
        : ProjectKind.package;
    final editorFiles = <String>{
      for (final target in targets) target.filePath,
    }.toList();
    if (editorFiles.isEmpty) {
      editorFiles.add(
        _joinPath(_joinPath(rootDirectory.path, 'src'), 'main.styio'),
      );
    }

    final lockfilePath = _joinPath(rootDirectory.path, 'spio.lock');
    final vendorRoot = _joinPath(
      _joinPath(rootDirectory.path, '.spio'),
      'vendor',
    );
    final buildRoot = _joinPath(
      _joinPath(rootDirectory.path, '.spio'),
      'build',
    );
    final toolchain = _toolchainFromManifest(
      parsedRoot.toolchain,
      toolchainPin: toolchainPin,
      pinnedToolchain: pinnedToolchain,
    );

    return ProjectGraphSnapshot(
      id: manifestFile.path,
      title: parsedRoot.package?.packageName ?? 'Workspace Project',
      kind: manifestKind,
      workspaceRoot: rootDirectory.path,
      workspaceMembers: parsedRoot.workspaceMembers,
      manifestPath: manifestFile.path,
      lockfilePath: lockfilePath,
      toolchainPinPath: toolchainPin,
      styioConfigPath: styioConfig,
      vendorRoot: vendorRoot,
      buildRoot: buildRoot,
      packages: packages,
      dependencies: dependencies,
      targets: targets,
      editorFiles: editorFiles,
      toolchain: publishedToolchainEnvironment?.toolchain ?? toolchain,
      lockState: await File(lockfilePath).exists()
          ? ProjectLockState.unknown
          : ProjectLockState.missing,
      vendorState: await Directory(vendorRoot).exists()
          ? ProjectVendorState.present
          : ProjectVendorState.missing,
      activeCompiler: publishedToolchainEnvironment?.activeCompiler ?? compiler,
      toolchainEnvironment: publishedToolchainEnvironment,
      packageDistribution: _derivePackageDistributionFromPackages(packages),
      projectGraphPayloadFailure: _lastProjectGraphPayloadFailure,
      toolchainStatePayloadFailure: _lastToolchainStatePayloadFailure,
      notes: _mergeNotes(<String>[
        if (projectGraphSupport.publishedPayloadAvailable)
          'spio advertises a published project graph payload, but the shell fell back to canonical file inference because the published payload could not be loaded.',
        if (!projectGraphSupport.publishedPayloadAvailable)
          'Project graph is built from canonical spio/styio files until spio publishes a dedicated project graph payload.',
        ..._publishedPayloadFailureNotes(
          projectGraphPayloadFailure: _lastProjectGraphPayloadFailure,
          toolchainStatePayloadFailure: _lastToolchainStatePayloadFailure,
        ),
        if (parsedRoot.workspaceMembers.isNotEmpty)
          'Workspace members discovered: ${parsedRoot.workspaceMembers.join(', ')}',
      ], publishedToolchainEnvironment?.notes ?? const <String>[]),
    );
  }

  AdapterCapabilityLevel _projectGraphCapabilityLevel() {
    if (_lastProjectGraphPayloadFailure != null ||
        _lastToolchainStatePayloadFailure != null) {
      return AdapterCapabilityLevel.partial;
    }
    return projectGraphSupport.publishedPayloadAvailable
        ? AdapterCapabilityLevel.available
        : AdapterCapabilityLevel.partial;
  }

  String _projectGraphCapabilityDetail() {
    if (_lastProjectGraphPayloadFailure != null) {
      return 'spio advertises the project graph contract, but `${_lastProjectGraphPayloadFailure!.command}` failed so the shell is using canonical file inference instead. ${_lastProjectGraphPayloadFailure!.detail}';
    }
    if (_lastToolchainStatePayloadFailure != null) {
      return 'spio advertises the toolchain state contract, but `${_lastToolchainStatePayloadFailure!.command}` failed so toolchain state is only partially available. ${_lastToolchainStatePayloadFailure!.detail}';
    }
    return projectGraphSupport.detail;
  }
}

class _PublishedPayloadLoadResult<T> {
  const _PublishedPayloadLoadResult.success(this.payload) : failure = null;

  const _PublishedPayloadLoadResult.failure(this.failure) : payload = null;

  final T? payload;
  final PublishedPayloadFailure? failure;
}

class _SpioProjectGraphSupport {
  const _SpioProjectGraphSupport({
    required this.publishedPayloadAvailable,
    required this.toolchainStateAvailable,
    this.binaryPath,
    required this.detail,
  });

  final bool publishedPayloadAvailable;
  final bool toolchainStateAvailable;
  final String? binaryPath;
  final String detail;
}

class _ParsedManifest {
  const _ParsedManifest({
    required this.package,
    required this.workspaceMembers,
    required this.dependencies,
    required this.toolchain,
  });

  final ProjectPackageSnapshot? package;
  final List<String> workspaceMembers;
  final List<ProjectDependencySnapshot> dependencies;
  final _ParsedToolchain toolchain;
}

class _ParsedToolchain {
  const _ParsedToolchain({this.channel, this.version});

  final String? channel;
  final String? version;
}

class _ParsedDependency {
  const _ParsedDependency({
    required this.name,
    required this.kind,
    required this.requirement,
    required this.isWorkspaceReference,
    required this.sourceKind,
    this.packageIdentity,
    this.pathSource,
    this.gitSource,
    this.gitRevision,
    this.registryRoot,
    this.requestedVersion,
    this.publishBlocking = false,
  });

  final String name;
  final ProjectDependencyKind kind;
  final String requirement;
  final bool isWorkspaceReference;
  final ProjectDependencySourceKind sourceKind;
  final String? packageIdentity;
  final String? pathSource;
  final String? gitSource;
  final String? gitRevision;
  final String? registryRoot;
  final String? requestedVersion;
  final bool publishBlocking;
}

class _MutableTarget {
  _MutableTarget({required this.kind});

  final ProjectTargetKind kind;
  String? name;
  String? path;
}

enum _ManifestSection {
  root,
  package,
  workspace,
  dependencies,
  devDependencies,
  toolchain,
  lib,
  bin,
  test,
  other,
}

const Map<String, _ManifestSection> _manifestSectionByHeader =
    <String, _ManifestSection>{
      '': _ManifestSection.root,
      'package': _ManifestSection.package,
      'workspace': _ManifestSection.workspace,
      'dependencies': _ManifestSection.dependencies,
      'dev-dependencies': _ManifestSection.devDependencies,
      'toolchain': _ManifestSection.toolchain,
      'lib': _ManifestSection.lib,
      'bin': _ManifestSection.bin,
      'test': _ManifestSection.test,
    };

const Map<_ManifestSection, ProjectDependencyKind> _dependencyKindBySection =
    <_ManifestSection, ProjectDependencyKind>{
      _ManifestSection.dependencies: ProjectDependencyKind.runtime,
      _ManifestSection.devDependencies: ProjectDependencyKind.dev,
    };

const Map<_ManifestSection, ProjectTargetKind> _inlineTargetKindBySection =
    <_ManifestSection, ProjectTargetKind>{
      _ManifestSection.lib: ProjectTargetKind.lib,
    };

const Map<_ManifestSection, ProjectTargetKind> _arrayTargetKindBySection =
    <_ManifestSection, ProjectTargetKind>{
      _ManifestSection.bin: ProjectTargetKind.bin,
      _ManifestSection.test: ProjectTargetKind.test,
    };

enum _InlineDependencyShape { pathOrWorkspace, git, registry, unknown }

_ManifestSection _manifestSectionFromHeader(String section) {
  return _manifestSectionByHeader[section] ?? _ManifestSection.other;
}

Future<_ParsedManifest> _parseManifest({
  required String manifestPath,
  required String workspaceRoot,
  required bool isWorkspaceMember,
}) async {
  final lines = await File(manifestPath).readAsLines();
  String? packageName;
  String? packageVersion;
  var packagePublishEnabled = false;
  final workspaceMembers = <String>[];
  final targets = <ProjectTargetDescriptor>[];
  final parsedDependencies = <_ParsedDependency>[];
  _MutableTarget? pendingTarget;
  var section = _ManifestSection.root;
  String? toolchainChannel;
  String? toolchainVersion;

  void flushPendingTarget() {
    final current = pendingTarget;
    if (current == null) {
      return;
    }
    if (current.path != null) {
      final resolvedPath = _resolveRelativePath(workspaceRoot, current.path!);
      final targetName = current.kind == ProjectTargetKind.lib
          ? (packageName?.split('/').last ?? 'lib')
          : (current.name ?? current.kind.name);
      final package = packageName ?? 'workspace/anonymous';
      targets.add(
        ProjectTargetDescriptor(
          id: '$package:${current.kind.name}:$targetName',
          packageName: package,
          kind: current.kind,
          name: targetName,
          filePath: resolvedPath,
        ),
      );
    }
    pendingTarget = null;
  }

  for (final rawLine in lines) {
    final line = _stripComment(rawLine).trim();
    if (line.isEmpty) {
      continue;
    }
    if (line.startsWith('[[') && line.endsWith(']]')) {
      flushPendingTarget();
      section = _manifestSectionFromHeader(
        line.substring(2, line.length - 2).trim(),
      );
      pendingTarget = _targetForSection(section, isArrayHeader: true);
      continue;
    }
    if (line.startsWith('[') && line.endsWith(']')) {
      flushPendingTarget();
      section = _manifestSectionFromHeader(
        line.substring(1, line.length - 1).trim(),
      );
      pendingTarget = _targetForSection(section, isArrayHeader: false);
      continue;
    }

    final separator = line.indexOf('=');
    if (separator == -1) {
      continue;
    }
    final key = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trim();
    final dependencyKind = _dependencyKindBySection[section];
    if (dependencyKind != null) {
      parsedDependencies.add(
        _parseDependency(name: key, value: value, kind: dependencyKind),
      );
      continue;
    }

    switch (section) {
      case _ManifestSection.package:
        if (key == 'name') {
          packageName = _parseString(value);
        } else if (key == 'version') {
          packageVersion = _parseString(value);
        } else if (key == 'publish') {
          packagePublishEnabled = _parseBool(value) ?? false;
        }
      case _ManifestSection.workspace:
        if (key == 'members') {
          workspaceMembers.addAll(_parseStringArray(value));
        }
      case _ManifestSection.toolchain:
        if (key == 'channel') {
          toolchainChannel = _parseString(value);
        } else if (key == 'version') {
          toolchainVersion = _parseString(value);
        }
      case _ManifestSection.lib:
        _applyTargetField(
          pendingTarget: pendingTarget,
          key: key,
          value: value,
          supportsName: false,
        );
      case _ManifestSection.bin:
      case _ManifestSection.test:
        _applyTargetField(
          pendingTarget: pendingTarget,
          key: key,
          value: value,
          supportsName: true,
        );
      case _ManifestSection.dependencies:
      case _ManifestSection.devDependencies:
      case _ManifestSection.root:
      case _ManifestSection.other:
    }
  }

  flushPendingTarget();

  final resolvedPackageName = packageName;
  final package = resolvedPackageName == null
      ? null
      : ProjectPackageSnapshot(
          packageName: resolvedPackageName,
          version: packageVersion ?? '0.0.0',
          rootPath: workspaceRoot,
          manifestPath: manifestPath,
          targets: targets,
          dependencies: parsedDependencies
              .map(
                (dependency) => ProjectDependencySnapshot(
                  sourcePackageName: resolvedPackageName,
                  dependencyName: dependency.name,
                  kind: dependency.kind,
                  requirement: dependency.requirement,
                  isWorkspaceReference: dependency.isWorkspaceReference,
                  packageIdentity: dependency.packageIdentity,
                  sourceKind: dependency.sourceKind,
                  pathSource: dependency.pathSource,
                  gitSource: dependency.gitSource,
                  gitRevision: dependency.gitRevision,
                  registryRoot: dependency.registryRoot,
                  requestedVersion: dependency.requestedVersion,
                  publishBlocking: dependency.publishBlocking,
                ),
              )
              .toList(growable: false),
          isWorkspaceMember: isWorkspaceMember,
          publishEnabled: packagePublishEnabled,
        );

  return _ParsedManifest(
    package: package,
    workspaceMembers: workspaceMembers,
    dependencies: package?.dependencies ?? const <ProjectDependencySnapshot>[],
    toolchain: _ParsedToolchain(
      channel: toolchainChannel,
      version: toolchainVersion,
    ),
  );
}

ToolchainStatusSnapshot _toolchainFromManifest(
  _ParsedToolchain toolchain, {
  required String? toolchainPin,
  required _ParsedToolchain pinnedToolchain,
}) {
  if (toolchainPin != null) {
    final resolvedChannel = pinnedToolchain.channel ?? toolchain.channel;
    final resolvedVersion = pinnedToolchain.version ?? toolchain.version;
    final detailParts = <String>[
      'Project toolchain pin discovered at $toolchainPin.',
      if (resolvedChannel != null) 'channel `$resolvedChannel` resolved.',
      if (resolvedVersion != null) 'version `$resolvedVersion` resolved.',
    ];
    return ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: detailParts.join(' '),
      pinPath: toolchainPin,
      channel: resolvedChannel,
      version: resolvedVersion,
    );
  }
  if (toolchain.channel != null || toolchain.version != null) {
    return ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.unknown,
      detail:
          'Manifest declares toolchain ${toolchain.channel != null ? 'channel `${toolchain.channel}`' : 'selection'}${toolchain.version != null ? ' with version `${toolchain.version}`' : ''} but no project pin is present.',
      channel: toolchain.channel,
      version: toolchain.version,
    );
  }
  return const ToolchainStatusSnapshot(
    source: ToolchainResolutionSource.unavailable,
    detail: 'No toolchain pin or explicit manifest channel was resolved.',
  );
}

Future<_ParsedToolchain> _parseToolchainPin(String toolchainPinPath) async {
  final pinFile = File(toolchainPinPath);
  if (!await pinFile.exists()) {
    return const _ParsedToolchain();
  }

  String? channel;
  String? version;
  for (final rawLine in await pinFile.readAsLines()) {
    final line = _stripComment(rawLine).trim();
    if (line.isEmpty || line.startsWith('[')) {
      continue;
    }
    final separator = line.indexOf('=');
    if (separator == -1) {
      continue;
    }
    final key = line.substring(0, separator).trim();
    final value = line.substring(separator + 1).trim();
    if (key == 'channel') {
      channel = _parseString(value);
    } else if (key == 'version') {
      version = _parseString(value);
    }
  }

  return _ParsedToolchain(channel: channel, version: version);
}

_MutableTarget? _targetForSection(
  _ManifestSection section, {
  required bool isArrayHeader,
}) {
  final targetKind = isArrayHeader
      ? _arrayTargetKindBySection[section]
      : _inlineTargetKindBySection[section];
  return targetKind == null ? null : _MutableTarget(kind: targetKind);
}

void _applyTargetField({
  required _MutableTarget? pendingTarget,
  required String key,
  required String value,
  required bool supportsName,
}) {
  if (key == 'path') {
    pendingTarget?.path = _parseString(value);
    return;
  }
  if (supportsName && key == 'name') {
    pendingTarget?.name = _parseString(value);
  }
}

Future<CompilerHandshakeSnapshot?> _probeCompiler({
  required Directory startDirectory,
}) async {
  final candidates = <String>[];
  final seenCandidates = <String>{};
  final explicit = _styioBinaryOverrideFromEnvironment();
  if (explicit != null) {
    _addStyioExecutableCandidates(candidates, explicit);
  }
  final spioManaged = _environmentValue('SPIO_STYIO_BIN');
  if (spioManaged != null) {
    _addStyioExecutableCandidates(candidates, spioManaged);
  }
  final spioHome = _environmentValue('SPIO_HOME');
  if (spioHome != null) {
    _addStyioExecutableCandidates(
      candidates,
      _joinPath(spioHome, 'tools/styio/current/bin/styio'),
    );
  }
  final home = _environmentValue('HOME');
  if (home != null) {
    _addStyioExecutableCandidates(
      candidates,
      _joinPath(home, '.spio/tools/styio/current/bin/styio'),
    );
  }

  var current = startDirectory.absolute;
  while (true) {
    _addStyioExecutableCandidates(
      candidates,
      _joinPath(current.path, '../styio-nightly/build/bin/styio'),
    );
    _addStyioExecutableCandidates(
      candidates,
      _joinPath(current.path, '../styio-nightly/build-codex/bin/styio'),
    );
    _addStyioExecutableCandidates(
      candidates,
      _joinPath(current.path, '../styio/build/bin/styio'),
    );
    _addStyioExecutableCandidates(
      candidates,
      _joinPath(current.path, '../styio/build-codex/bin/styio'),
    );
    _addStyioExecutableCandidates(
      candidates,
      _joinPath(
        current.path,
        '../../Unka-Malloc/styio-nightly/build/bin/styio',
      ),
    );
    _addStyioExecutableCandidates(
      candidates,
      _joinPath(
        current.path,
        '../../Unka-Malloc/styio-nightly/build-codex/bin/styio',
      ),
    );
    _addStyioExecutableCandidates(
      candidates,
      _joinPath(current.path, '../../Unka-Malloc/styio/build/bin/styio'),
    );
    _addStyioExecutableCandidates(
      candidates,
      _joinPath(current.path, '../../Unka-Malloc/styio/build-codex/bin/styio'),
    );
    final parent = current.parent;
    if (parent.path == current.path) {
      break;
    }
    current = parent;
  }

  for (final candidate in candidates) {
    if (!seenCandidates.add(candidate)) {
      continue;
    }
    final binary = File(candidate);
    if (!await binary.exists()) {
      continue;
    }

    try {
      final result = await Process.run(binary.path, const <String>[
        '--machine-info=json',
      ]);
      if (result.exitCode != 0) {
        continue;
      }
      final decoded = jsonDecode(result.stdout as String);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      final contracts = <String, List<int>>{};
      final rawContracts =
          decoded['supported_contract_versions'] ??
          decoded['supported_contracts'];
      if (rawContracts is Map<String, dynamic>) {
        for (final entry in rawContracts.entries) {
          final rawVersions = entry.value;
          if (rawVersions is List) {
            contracts[entry.key] = rawVersions
                .whereType<num>()
                .map((value) => value.toInt())
                .toList(growable: false);
          }
        }
      }
      return CompilerHandshakeSnapshot(
        binaryPath: binary.path,
        tool: decoded['tool'] as String? ?? 'styio',
        compilerVersion: decoded['compiler_version'] as String? ?? 'unknown',
        channel: decoded['channel'] as String? ?? 'unknown',
        variant: decoded['variant'] as String? ?? 'unknown',
        capabilities: (decoded['capabilities'] as List? ?? const <Object>[])
            .whereType<String>()
            .toList(growable: false),
        supportedContractVersions: contracts,
        integrationPhase:
            decoded['active_integration_phase'] as String? ??
            (contracts['compile_plan']?.isNotEmpty == true
                ? 'compile-plan-live'
                : 'bootstrap-single-file'),
        supportedAdapterModes:
            (decoded['supported_adapter_modes'] as List? ?? const <Object>[])
                .whereType<String>()
                .toList(growable: false),
        featureFlags: _parseBoolMap(decoded['feature_flags']),
      );
    } catch (_) {
      continue;
    }
  }
  return null;
}

void _addStyioExecutableCandidates(List<String> candidates, String path) {
  if (Platform.isWindows && !_hasWindowsExecutableExtension(path)) {
    candidates.add('$path.exe');
    candidates.add('$path.cmd');
    candidates.add('$path.bat');
  }
  candidates.add(path);
}

bool _hasWindowsExecutableExtension(String path) {
  return RegExp(r'\.(bat|cmd|com|exe)$', caseSensitive: false).hasMatch(path);
}

Future<_SpioProjectGraphSupport> _probeSpioProjectGraphSupport({
  required Directory startDirectory,
}) async {
  final candidates = <String>[];
  final seenCandidates = <String>{};
  final explicit = _environmentValue('VITYO_SPIO_BIN');
  if (explicit != null) {
    appendSpioExecutableCandidates(candidates, explicit);
  }
  final envBinary = _environmentValue('SPIO_BIN');
  if (envBinary != null) {
    appendSpioExecutableCandidates(candidates, envBinary);
  }
  appendSpioExecutableCandidates(
    candidates,
    _joinPath(_joinPath(startDirectory.path, '.spio'), 'bin/spio'),
  );
  appendSpioExecutableCandidates(
    candidates,
    _joinPath(startDirectory.path, 'spio'),
  );
  appendSpioExecutableCandidates(
    candidates,
    _joinPath(_joinPath(startDirectory.path, 'scripts'), 'spio'),
  );
  appendSpioExecutableCandidates(candidates, 'spio');

  for (final candidate in candidates) {
    if (!seenCandidates.add(candidate)) {
      continue;
    }

    try {
      final result = await Process.run(candidate, const <String>[
        'machine-info',
        '--json',
      ]);
      if (result.exitCode != 0) {
        continue;
      }
      final decoded = jsonDecode(result.stdout as String);
      if (decoded is! Map<String, dynamic>) {
        continue;
      }
      final rawContracts =
          decoded['supported_contract_versions'] ??
          decoded['supported_contracts'];
      if (rawContracts is! Map<String, dynamic>) {
        continue;
      }
      final versions = rawContracts['project_graph'];
      final toolchainVersions = rawContracts['toolchain_state'];
      if (versions is List && versions.whereType<num>().contains(1)) {
        return _SpioProjectGraphSupport(
          publishedPayloadAvailable: true,
          toolchainStateAvailable:
              toolchainVersions is List &&
              toolchainVersions.whereType<num>().contains(1),
          binaryPath: candidate,
          detail:
              'Project graph is available through published spio project-graph payloads.',
        );
      }
      return _SpioProjectGraphSupport(
        publishedPayloadAvailable: false,
        toolchainStateAvailable:
            toolchainVersions is List &&
            toolchainVersions.whereType<num>().contains(1),
        binaryPath: candidate,
        detail:
            'spio is available, but the active binary does not advertise the project_graph contract yet.',
      );
    } catch (_) {
      continue;
    }
  }

  return const _SpioProjectGraphSupport(
    publishedPayloadAvailable: false,
    toolchainStateAvailable: false,
    detail:
        'Project graph is currently inferred from canonical project files until spio publishes a success payload.',
  );
}

Future<_PublishedPayloadLoadResult<ProjectGraphSnapshot>>
_loadPublishedProjectGraph({
  required String? spioBinary,
  required String manifestPath,
  required String? styioBinaryOverride,
}) async {
  if (spioBinary == null || spioBinary.isEmpty) {
    return const _PublishedPayloadLoadResult<ProjectGraphSnapshot>.failure(
      PublishedPayloadFailure(
        command: 'spio project-graph --json',
        detail:
            'No spio binary was available for the published project graph path.',
      ),
    );
  }

  try {
    final result = await Process.run(spioBinary, <String>[
      'project-graph',
      '--json',
      '--manifest-path',
      manifestPath,
      if (styioBinaryOverride != null) ...<String>[
        '--styio-bin',
        styioBinaryOverride,
      ],
    ]);
    if (result.exitCode != 0) {
      return _PublishedPayloadLoadResult<ProjectGraphSnapshot>.failure(
        PublishedPayloadFailure(
          command: 'spio project-graph --json',
          detail: _describePayloadCommandFailure(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
          ),
        ),
      );
    }
    final decoded = jsonDecode(result.stdout as String);
    if (decoded is! Map<String, dynamic>) {
      return const _PublishedPayloadLoadResult<ProjectGraphSnapshot>.failure(
        PublishedPayloadFailure(
          command: 'spio project-graph --json',
          detail:
              'Published project graph payload did not decode into a JSON object.',
        ),
      );
    }
    if (decoded['schema_version'] != 1) {
      return _PublishedPayloadLoadResult<ProjectGraphSnapshot>.failure(
        PublishedPayloadFailure(
          command: 'spio project-graph --json',
          detail:
              'Published project graph payload reported unsupported schema_version `${decoded['schema_version']}`.',
        ),
      );
    }

    try {
      final packages = (decoded['packages'] as List? ?? const <Object>[])
          .whereType<Map<String, dynamic>>()
          .map(_projectPackageFromPayload)
          .toList(growable: false);
      final dependencies =
          (decoded['dependencies'] as List? ?? const <Object>[])
              .whereType<Map<String, dynamic>>()
              .map(_projectDependencyFromPayload)
              .toList(growable: false);
      final targets = (decoded['targets'] as List? ?? const <Object>[])
          .whereType<Map<String, dynamic>>()
          .map(_projectTargetFromPayload)
          .toList(growable: false);
      final activeCompiler = decoded['active_compiler'] is Map<String, dynamic>
          ? _compilerHandshakeFromPayload(
              decoded['active_compiler'] as Map<String, dynamic>,
            )
          : null;
      final toolchain = decoded['toolchain'] is Map<String, dynamic>
          ? _toolchainStatusFromPayload(
              decoded['toolchain'] as Map<String, dynamic>,
            )
          : const ToolchainStatusSnapshot(
              source: ToolchainResolutionSource.unavailable,
              detail: 'spio project-graph did not publish toolchain state.',
            );
      final notes = (decoded['notes'] as List? ?? const <Object>[])
          .whereType<String>()
          .toList(growable: false);
      final managedToolchains =
          decoded['managed_toolchains'] is Map<String, dynamic>
          ? _managedToolchainStateFromPayload(
              decoded['managed_toolchains'] as Map<String, dynamic>,
            )
          : const ManagedToolchainStateSnapshot();
      final projectPin = decoded['toolchain_pin_path'] is String
          ? ProjectToolchainPinSnapshot(
              path: decoded['toolchain_pin_path'] as String,
              channel: decoded['toolchain'] is Map<String, dynamic>
                  ? (decoded['toolchain'] as Map<String, dynamic>)['channel']
                        as String?
                  : null,
              version: decoded['toolchain'] is Map<String, dynamic>
                  ? (decoded['toolchain'] as Map<String, dynamic>)['version']
                        as String?
                  : null,
              installPresent: false,
            )
          : null;
      final packageDistribution =
          decoded['package_distribution'] is Map<String, dynamic>
          ? _packageDistributionFromPayload(
              decoded['package_distribution'] as Map<String, dynamic>,
            )
          : _derivePackageDistributionFromPackages(packages);
      final sourceState = decoded['source_state'] is Map<String, dynamic>
          ? _projectSourceStateFromPayload(
              decoded['source_state'] as Map<String, dynamic>,
            )
          : null;

      return _PublishedPayloadLoadResult<ProjectGraphSnapshot>.success(
        ProjectGraphSnapshot(
          id: decoded['id'] as String? ?? manifestPath,
          title: decoded['title'] as String? ?? 'Workspace Project',
          kind: _projectKindFromString(decoded['kind'] as String?),
          workspaceRoot: decoded['workspace_root'] as String? ?? '',
          workspaceMembers:
              (decoded['workspace_members'] as List? ?? const <Object>[])
                  .whereType<String>()
                  .toList(growable: false),
          manifestPath: decoded['manifest_path'] as String?,
          lockfilePath: decoded['lockfile_path'] as String?,
          toolchainPinPath: decoded['toolchain_pin_path'] as String?,
          styioConfigPath: decoded['styio_config_path'] as String?,
          vendorRoot: decoded['vendor_root'] as String?,
          buildRoot: decoded['build_root'] as String?,
          packages: packages,
          dependencies: dependencies,
          targets: targets,
          editorFiles: (decoded['editor_files'] as List? ?? const <Object>[])
              .whereType<String>()
              .toList(growable: false),
          toolchain: toolchain,
          lockState: _lockStateFromString(decoded['lock_state'] as String?),
          vendorState: _vendorStateFromString(
            decoded['vendor_state'] as String?,
          ),
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
          notes: notes.isEmpty
              ? const <String>[
                  'Project graph loaded through published spio machine payload.',
                ]
              : notes,
        ),
      );
    } catch (error) {
      return _PublishedPayloadLoadResult<ProjectGraphSnapshot>.failure(
        PublishedPayloadFailure(
          command: 'spio project-graph --json',
          detail: 'Published project graph payload could not be parsed: $error',
        ),
      );
    }
  } on FormatException catch (error) {
    return _PublishedPayloadLoadResult<ProjectGraphSnapshot>.failure(
      PublishedPayloadFailure(
        command: 'spio project-graph --json',
        detail:
            'Published project graph payload emitted invalid JSON: ${_previewPayloadText(error.source?.toString() ?? '')}',
      ),
    );
  } catch (error) {
    return _PublishedPayloadLoadResult<ProjectGraphSnapshot>.failure(
      PublishedPayloadFailure(
        command: 'spio project-graph --json',
        detail: 'Published project graph load failed: $error',
      ),
    );
  }
}

Future<_PublishedPayloadLoadResult<ToolchainEnvironmentSnapshot>>
_loadPublishedToolchainEnvironment({
  required String? spioBinary,
  required String? manifestPath,
  required String? styioBinaryOverride,
}) async {
  if (spioBinary == null || spioBinary.isEmpty) {
    return const _PublishedPayloadLoadResult<
      ToolchainEnvironmentSnapshot
    >.failure(
      PublishedPayloadFailure(
        command: 'spio tool status --json',
        detail:
            'No spio binary was available for the published toolchain-state path.',
      ),
    );
  }

  try {
    final args = <String>['tool', 'status', '--json'];
    if (manifestPath != null && manifestPath.isNotEmpty) {
      args.addAll(<String>['--manifest-path', manifestPath]);
    }
    if (styioBinaryOverride != null) {
      args.addAll(<String>['--styio-bin', styioBinaryOverride]);
    }
    final result = await Process.run(spioBinary, args);
    if (result.exitCode != 0) {
      return _PublishedPayloadLoadResult<ToolchainEnvironmentSnapshot>.failure(
        PublishedPayloadFailure(
          command: 'spio tool status --json',
          detail: _describePayloadCommandFailure(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
          ),
        ),
      );
    }

    final decoded = jsonDecode(result.stdout as String);
    if (decoded is! Map<String, dynamic>) {
      return const _PublishedPayloadLoadResult<
        ToolchainEnvironmentSnapshot
      >.failure(
        PublishedPayloadFailure(
          command: 'spio tool status --json',
          detail:
              'Published toolchain-state payload did not decode into a JSON object.',
        ),
      );
    }
    if (decoded['schema_version'] != 1) {
      return _PublishedPayloadLoadResult<ToolchainEnvironmentSnapshot>.failure(
        PublishedPayloadFailure(
          command: 'spio tool status --json',
          detail:
              'Published toolchain-state payload reported unsupported schema_version `${decoded['schema_version']}`.',
        ),
      );
    }

    final toolchain = decoded['toolchain'] is Map<String, dynamic>
        ? _toolchainStatusFromPayload(
            decoded['toolchain'] as Map<String, dynamic>,
          )
        : const ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.unavailable,
            detail: 'spio tool status did not publish toolchain state.',
          );
    final activeCompiler = decoded['active_compiler'] is Map<String, dynamic>
        ? _compilerHandshakeFromPayload(
            decoded['active_compiler'] as Map<String, dynamic>,
          )
        : null;
    final currentCompiler = decoded['current_compiler'] is Map<String, dynamic>
        ? _compilerHandshakeFromPayload(
            decoded['current_compiler'] as Map<String, dynamic>,
          )
        : null;

    return _PublishedPayloadLoadResult<ToolchainEnvironmentSnapshot>.success(
      ToolchainEnvironmentSnapshot(
        schemaVersion: decoded['schema_version'] as int? ?? 1,
        toolchain: toolchain,
        candidateBinaryPath: decoded['toolchain'] is Map<String, dynamic>
            ? (decoded['toolchain']
                      as Map<String, dynamic>)['candidate_binary_path']
                  as String?
            : null,
        projectPin: decoded['project_pin'] is Map<String, dynamic>
            ? _projectToolchainPinFromPayload(
                decoded['project_pin'] as Map<String, dynamic>,
              )
            : null,
        activeCompiler: activeCompiler,
        activeCompilerError: decoded['active_compiler_error'] as String?,
        currentCompiler: currentCompiler,
        currentCompilerError: decoded['current_compiler_error'] as String?,
        managedToolchains: decoded['managed_toolchains'] is Map<String, dynamic>
            ? _managedToolchainStateFromPayload(
                decoded['managed_toolchains'] as Map<String, dynamic>,
              )
            : const ManagedToolchainStateSnapshot(),
        notes: (decoded['notes'] as List? ?? const <Object>[])
            .whereType<String>()
            .toList(growable: false),
      ),
    );
  } on FormatException catch (error) {
    return _PublishedPayloadLoadResult<ToolchainEnvironmentSnapshot>.failure(
      PublishedPayloadFailure(
        command: 'spio tool status --json',
        detail:
            'Published toolchain-state payload emitted invalid JSON: ${_previewPayloadText(error.source?.toString() ?? '')}',
      ),
    );
  } catch (error) {
    return _PublishedPayloadLoadResult<ToolchainEnvironmentSnapshot>.failure(
      PublishedPayloadFailure(
        command: 'spio tool status --json',
        detail: 'Published toolchain-state load failed: $error',
      ),
    );
  }
}

String? _styioBinaryOverrideFromEnvironment() {
  return _environmentValue('VITYO_STYIO_BIN');
}

String? _environmentValue(String name) {
  final value = _environmentProvider()[name];
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

const Map<String, ProjectKind> _projectKindByWireValue = <String, ProjectKind>{
  'package': ProjectKind.package,
  'workspace': ProjectKind.workspace,
  'combined-root': ProjectKind.combinedRoot,
  'hosted': ProjectKind.hosted,
  'scratch': ProjectKind.scratch,
};

const Map<String, ProjectTargetKind> _projectTargetKindByWireValue =
    <String, ProjectTargetKind>{
      'lib': ProjectTargetKind.lib,
      'test': ProjectTargetKind.test,
      'bin': ProjectTargetKind.bin,
    };

const Map<String, ProjectDependencyKind> _projectDependencyKindByWireValue =
    <String, ProjectDependencyKind>{
      'dev': ProjectDependencyKind.dev,
      'runtime': ProjectDependencyKind.runtime,
    };

const Map<String, ProjectDependencySourceKind>
_projectDependencySourceKindByWireValue = <String, ProjectDependencySourceKind>{
  'path': ProjectDependencySourceKind.path,
  'git': ProjectDependencySourceKind.git,
  'registry': ProjectDependencySourceKind.registry,
  'unknown': ProjectDependencySourceKind.unknown,
};

const Map<String, ProjectLockState> _lockStateByWireValue =
    <String, ProjectLockState>{
      'fresh': ProjectLockState.fresh,
      'stale': ProjectLockState.stale,
      'missing': ProjectLockState.missing,
      'unknown': ProjectLockState.unknown,
    };

const Map<String, ProjectVendorState> _vendorStateByWireValue =
    <String, ProjectVendorState>{
      'present': ProjectVendorState.present,
      'missing': ProjectVendorState.missing,
      'unknown': ProjectVendorState.unknown,
    };

const Map<String, ToolchainResolutionSource> _toolchainSourceByWireValue =
    <String, ToolchainResolutionSource>{
      'project-pin': ToolchainResolutionSource.projectPin,
      'managed-current': ToolchainResolutionSource.managedCurrent,
      'environment': ToolchainResolutionSource.environment,
      'unknown': ToolchainResolutionSource.unknown,
      'unavailable': ToolchainResolutionSource.unavailable,
    };

ProjectKind _projectKindFromString(String? raw) {
  return _projectKindByWireValue[raw] ?? ProjectKind.scratch;
}

ProjectTargetKind _projectTargetKindFromString(String? raw) {
  return _projectTargetKindByWireValue[raw] ?? ProjectTargetKind.bin;
}

ProjectDependencyKind _projectDependencyKindFromString(String? raw) {
  return _projectDependencyKindByWireValue[raw] ??
      ProjectDependencyKind.runtime;
}

ProjectDependencySourceKind _projectDependencySourceKindFromString(
  String? raw,
) {
  return _projectDependencySourceKindByWireValue[raw] ??
      ProjectDependencySourceKind.unknown;
}

ProjectLockState _lockStateFromString(String? raw) {
  return _lockStateByWireValue[raw] ?? ProjectLockState.unknown;
}

ProjectVendorState _vendorStateFromString(String? raw) {
  return _vendorStateByWireValue[raw] ?? ProjectVendorState.unknown;
}

ToolchainResolutionSource _toolchainSourceFromString(String? raw) {
  return _toolchainSourceByWireValue[raw] ??
      ToolchainResolutionSource.unavailable;
}

ProjectTargetDescriptor _projectTargetFromPayload(
  Map<String, dynamic> payload,
) {
  return ProjectTargetDescriptor(
    id: payload['id'] as String? ?? '',
    packageName: payload['package_name'] as String? ?? '',
    kind: _projectTargetKindFromString(payload['kind'] as String?),
    name: payload['name'] as String? ?? '',
    filePath: payload['file_path'] as String? ?? '',
  );
}

ProjectDependencySnapshot _projectDependencyFromPayload(
  Map<String, dynamic> payload,
) {
  final sourceKind = _projectDependencySourceKindFromString(
    payload['source_kind'] as String?,
  );
  final packageIdentity = payload['package'] as String?;
  final registryRoot = payload['registry'] as String?;
  final requestedVersion = payload['version'] as String?;
  return ProjectDependencySnapshot(
    sourcePackageName: payload['source_package_name'] as String? ?? '',
    dependencyName: payload['dependency_name'] as String? ?? '',
    kind: _projectDependencyKindFromString(payload['kind'] as String?),
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

ProjectPackageSnapshot _projectPackageFromPayload(
  Map<String, dynamic> payload,
) {
  return ProjectPackageSnapshot(
    packageName: payload['package_name'] as String? ?? '',
    version: payload['version'] as String? ?? '',
    rootPath: payload['root_path'] as String? ?? '',
    manifestPath: payload['manifest_path'] as String? ?? '',
    targets: (payload['targets'] as List? ?? const <Object>[])
        .whereType<Map<String, dynamic>>()
        .map(_projectTargetFromPayload)
        .toList(growable: false),
    dependencies: (payload['dependencies'] as List? ?? const <Object>[])
        .whereType<Map<String, dynamic>>()
        .map(_projectDependencyFromPayload)
        .toList(growable: false),
    isWorkspaceMember: payload['is_workspace_member'] as bool? ?? false,
    publishEnabled: payload['publish_enabled'] as bool? ?? false,
  );
}

PackageDistributionSnapshot? _derivePackageDistributionFromPackages(
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
                        transport: _registryTransportFromRoot(registryRoot),
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
              _appendUniqueNote(
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
              _appendUniqueNote(
                blockingReasons,
                'dependency in [${dependency.kind == ProjectDependencyKind.dev ? 'dev-dependencies' : 'dependencies'}] uses a git source: ${dependency.dependencyName}',
              );
              break;
            case ProjectDependencySourceKind.unknown:
              if (dependency.publishBlocking) {
                _appendUniqueNote(
                  blockingReasons,
                  'dependency in [${dependency.kind == ProjectDependencyKind.dev ? 'dev-dependencies' : 'dependencies'}] is not registry-addressable: ${dependency.dependencyName}',
                );
              }
              break;
          }

          if (dependency.publishBlocking &&
              dependency.sourceKind == ProjectDependencySourceKind.registry) {
            _appendUniqueNote(
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

String _registryTransportFromRoot(String registryRoot) {
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

void _appendUniqueNote(List<String> notes, String note) {
  if (!notes.contains(note)) {
    notes.add(note);
  }
}

RegistrySourceSnapshot _registrySourceFromPayload(
  Map<String, dynamic> payload,
) {
  return RegistrySourceSnapshot(
    registryRoot: payload['registry_root'] as String? ?? '',
    transport: payload['transport'] as String? ?? 'unknown',
    dependencyRefs: payload['dependency_refs'] as int? ?? 0,
    packages: (payload['packages'] as List? ?? const <Object>[])
        .whereType<String>()
        .toList(growable: false),
  );
}

PackageDistributionPackageSnapshot _distributionPackageFromPayload(
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

PackageDistributionSnapshot _packageDistributionFromPayload(
  Map<String, dynamic> payload,
) {
  return PackageDistributionSnapshot(
    schemaVersion: payload['schema_version'] as int? ?? 1,
    packages: (payload['packages'] as List? ?? const <Object>[])
        .whereType<Map<String, dynamic>>()
        .map(_distributionPackageFromPayload)
        .toList(growable: false),
    registrySources: (payload['registry_sources'] as List? ?? const <Object>[])
        .whereType<Map<String, dynamic>>()
        .map(_registrySourceFromPayload)
        .toList(growable: false),
    publishablePackages: payload['publishable_packages'] as int? ?? 0,
    blockedPackages: payload['blocked_packages'] as int? ?? 0,
  );
}

GitCacheStateSnapshot _gitCacheStateFromPayload(Map<String, dynamic> payload) {
  return GitCacheStateSnapshot(
    reposRoot: payload['repos_root'] as String?,
    checkoutsRoot: payload['checkouts_root'] as String?,
    reposPresent: payload['repos_present'] as bool? ?? false,
    checkoutsPresent: payload['checkouts_present'] as bool? ?? false,
  );
}

RegistryCacheStateSnapshot _registryCacheStateFromPayload(
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

VendorSourceStateSnapshot _vendorSourceStateFromPayload(
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

ProjectSourceStateSnapshot _projectSourceStateFromPayload(
  Map<String, dynamic> payload,
) {
  return ProjectSourceStateSnapshot(
    schemaVersion: payload['schema_version'] as int? ?? 1,
    spioHome: payload['spio_home'] as String?,
    declaredGitDependencies: payload['declared_git_dependencies'] as int? ?? 0,
    declaredRegistryDependencies:
        payload['declared_registry_dependencies'] as int? ?? 0,
    gitCache: payload['git_cache'] is Map<String, dynamic>
        ? _gitCacheStateFromPayload(
            payload['git_cache'] as Map<String, dynamic>,
          )
        : const GitCacheStateSnapshot(),
    registryCache: payload['registry_cache'] is Map<String, dynamic>
        ? _registryCacheStateFromPayload(
            payload['registry_cache'] as Map<String, dynamic>,
          )
        : const RegistryCacheStateSnapshot(),
    vendor: payload['vendor'] is Map<String, dynamic>
        ? _vendorSourceStateFromPayload(
            payload['vendor'] as Map<String, dynamic>,
          )
        : const VendorSourceStateSnapshot(),
  );
}

ToolchainStatusSnapshot _toolchainStatusFromPayload(
  Map<String, dynamic> payload,
) {
  return ToolchainStatusSnapshot(
    source: _toolchainSourceFromString(payload['source'] as String?),
    detail: payload['detail'] as String? ?? 'No toolchain detail published.',
    pinPath: payload['pin_path'] as String?,
    channel: payload['channel'] as String?,
    version: payload['version'] as String?,
  );
}

ProjectToolchainPinSnapshot _projectToolchainPinFromPayload(
  Map<String, dynamic> payload,
) {
  return ProjectToolchainPinSnapshot(
    path: payload['path'] as String? ?? '',
    channel: payload['channel'] as String?,
    version: payload['version'] as String?,
    installRoot: payload['install_root'] as String?,
    installBinaryPath: payload['install_binary_path'] as String?,
    installPresent: payload['install_present'] as bool? ?? false,
  );
}

ManagedToolchainInstallSnapshot _managedToolchainInstallFromPayload(
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

ManagedToolchainStateSnapshot _managedToolchainStateFromPayload(
  Map<String, dynamic> payload,
) {
  return ManagedToolchainStateSnapshot(
    spioHome: payload['spio_home'] as String?,
    currentBinaryPath: payload['current_binary'] as String?,
    currentMetadataPath: payload['current_metadata_path'] as String?,
    installed: (payload['installed'] as List? ?? const <Object>[])
        .whereType<Map<String, dynamic>>()
        .map(_managedToolchainInstallFromPayload)
        .toList(growable: false),
  );
}

CompilerHandshakeSnapshot _compilerHandshakeFromPayload(
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
    featureFlags: _parseBoolMap(payload['feature_flags']),
  );
}

List<String> _mergeNotes(List<String> base, List<String> extra) {
  final seen = <String>{};
  final merged = <String>[];
  for (final note in <String>[...base, ...extra]) {
    if (note.isEmpty || !seen.add(note)) {
      continue;
    }
    merged.add(note);
  }
  return merged;
}

List<String> _publishedPayloadFailureNotes({
  PublishedPayloadFailure? projectGraphPayloadFailure,
  PublishedPayloadFailure? toolchainStatePayloadFailure,
}) {
  return <String>[
    if (projectGraphPayloadFailure != null)
      _publishedPayloadFailureNote(projectGraphPayloadFailure),
    if (toolchainStatePayloadFailure != null)
      _publishedPayloadFailureNote(toolchainStatePayloadFailure),
  ];
}

String _publishedPayloadFailureNote(PublishedPayloadFailure failure) {
  return 'Published payload failure for `${failure.command}`: ${failure.detail}';
}

String _describePayloadCommandFailure({
  required int exitCode,
  required Object? stdout,
  required Object? stderr,
}) {
  final stderrText = _previewPayloadText(stderr?.toString() ?? '');
  if (stderrText.isNotEmpty) {
    return 'Command exited with code $exitCode. stderr: $stderrText';
  }
  final stdoutText = _previewPayloadText(stdout?.toString() ?? '');
  if (stdoutText.isNotEmpty) {
    return 'Command exited with code $exitCode. stdout: $stdoutText';
  }
  return 'Command exited with code $exitCode and did not emit any diagnostic output.';
}

String _previewPayloadText(String text) {
  final collapsed = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (collapsed.isEmpty) {
    return '';
  }
  const maxLength = 180;
  if (collapsed.length <= maxLength) {
    return collapsed;
  }
  return '${collapsed.substring(0, maxLength)}...';
}

Directory _discoverProjectRoot(Directory startDirectory) {
  var current = startDirectory.absolute;
  while (true) {
    final manifest = File(_joinPath(current.path, 'spio.toml'));
    final styioConfig = File(_joinPath(current.path, 'styio.toml'));
    final gitDir = Directory(_joinPath(current.path, '.git'));
    if (manifest.existsSync() ||
        styioConfig.existsSync() ||
        gitDir.existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      return startDirectory.absolute;
    }
    current = parent;
  }
}

String? _findUpwardFile({
  required Directory startDirectory,
  required List<String> candidates,
}) {
  var current = startDirectory.absolute;
  while (true) {
    for (final candidate in candidates) {
      final file = File(_joinPath(current.path, candidate));
      if (file.existsSync()) {
        return file.path;
      }
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      return null;
    }
    current = parent;
  }
}

String _parseString(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('"') && trimmed.endsWith('"') && trimmed.length >= 2) {
    return trimmed.substring(1, trimmed.length - 1);
  }
  return trimmed;
}

List<String> _parseStringArray(String raw) {
  final trimmed = raw.trim();
  if (!trimmed.startsWith('[') || !trimmed.endsWith(']')) {
    return const <String>[];
  }
  final body = trimmed.substring(1, trimmed.length - 1).trim();
  if (body.isEmpty) {
    return const <String>[];
  }
  return body
      .split(',')
      .map(_parseString)
      .where((value) => value.isNotEmpty)
      .toList(growable: false);
}

Map<String, bool> _parseBoolMap(Object? raw) {
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

_ParsedDependency _parseDependency({
  required String name,
  required String value,
  required ProjectDependencyKind kind,
}) {
  final trimmed = value.trim();
  if (trimmed.startsWith('{') && trimmed.endsWith('}')) {
    final entries = _parseInlineTableEntries(trimmed);
    final path = entries['path'];
    final git = entries['git'];
    final rev = entries['rev'];
    final registry = entries['registry'];
    final version = entries['version'];
    final packageIdentity = entries['package'];
    final workspace = entries['workspace'];
    final isWorkspaceReference = path != null || workspace == 'true';
    switch (_inlineDependencyShapeFromEntries(entries)) {
      case _InlineDependencyShape.pathOrWorkspace:
        return _ParsedDependency(
          name: name,
          kind: kind,
          requirement: path != null
              ? 'path:$path'
              : (workspace == 'true' ? 'workspace' : trimmed),
          isWorkspaceReference: isWorkspaceReference,
          sourceKind: ProjectDependencySourceKind.path,
          packageIdentity: packageIdentity,
          pathSource: path,
          publishBlocking: true,
        );
      case _InlineDependencyShape.git:
        return _ParsedDependency(
          name: name,
          kind: kind,
          requirement: rev == null ? 'git:$git' : 'git:$git#$rev',
          isWorkspaceReference: false,
          sourceKind: ProjectDependencySourceKind.git,
          packageIdentity: packageIdentity,
          gitSource: git,
          gitRevision: rev,
          publishBlocking: true,
        );
      case _InlineDependencyShape.registry:
        final publishBlocking =
            registry == null ||
            registry.isEmpty ||
            packageIdentity == null ||
            packageIdentity.isEmpty ||
            version == null ||
            version.isEmpty;
        return _ParsedDependency(
          name: name,
          kind: kind,
          requirement: version == null
              ? 'registry:$registry'
              : 'registry:$registry@$version',
          isWorkspaceReference: false,
          sourceKind: ProjectDependencySourceKind.registry,
          packageIdentity: packageIdentity,
          registryRoot: registry,
          requestedVersion: version,
          publishBlocking: publishBlocking,
        );
      case _InlineDependencyShape.unknown:
        return _ParsedDependency(
          name: name,
          kind: kind,
          requirement: version ?? trimmed,
          isWorkspaceReference: isWorkspaceReference,
          sourceKind: ProjectDependencySourceKind.unknown,
          packageIdentity: packageIdentity,
          requestedVersion: version,
          publishBlocking: true,
        );
    }
  }

  return _ParsedDependency(
    name: name,
    kind: kind,
    requirement: _parseString(trimmed),
    isWorkspaceReference: false,
    sourceKind: ProjectDependencySourceKind.unknown,
    publishBlocking: true,
  );
}

Map<String, String> _parseInlineTableEntries(String raw) {
  final body = raw.substring(1, raw.length - 1);
  final entries = <String, String>{};
  for (final fragment in body.split(',')) {
    final separator = fragment.contains(':')
        ? fragment.indexOf(':')
        : fragment.indexOf('=');
    if (separator == -1) {
      continue;
    }
    entries[fragment.substring(0, separator).trim()] = _parseString(
      fragment.substring(separator + 1).trim(),
    );
  }
  return entries;
}

// Inline source markers are mutually exclusive; precedence matches legacy parsing.
_InlineDependencyShape _inlineDependencyShapeFromEntries(
  Map<String, String> entries,
) {
  if (entries.containsKey('path') || entries['workspace'] == 'true') {
    return _InlineDependencyShape.pathOrWorkspace;
  }
  if (entries.containsKey('git')) {
    return _InlineDependencyShape.git;
  }
  if (entries.containsKey('registry')) {
    return _InlineDependencyShape.registry;
  }
  return _InlineDependencyShape.unknown;
}

bool? _parseBool(String value) {
  final normalized = value.trim().toLowerCase();
  if (normalized == 'true') {
    return true;
  }
  if (normalized == 'false') {
    return false;
  }
  return null;
}

String _stripComment(String line) {
  final hashIndex = line.indexOf('#');
  if (hashIndex == -1) {
    return line;
  }
  return line.substring(0, hashIndex);
}

String _resolveRelativePath(String rootPath, String rawPath) {
  if (_isAbsolutePath(rawPath)) {
    return rawPath;
  }
  return Directory(rootPath).uri.resolve(rawPath).toFilePath();
}

bool _isAbsolutePath(String path) {
  return path.startsWith(Platform.pathSeparator) ||
      RegExp(r'^[A-Za-z]:[\\/]').hasMatch(path);
}

String _joinPath(String base, String child) {
  return Directory(base).uri.resolve(child).toFilePath();
}
