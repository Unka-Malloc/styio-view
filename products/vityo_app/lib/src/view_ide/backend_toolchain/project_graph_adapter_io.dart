import '../../../owner_adapters/pafio_metadata_adapter.dart';
import '../../../owner_adapters/platform_hosted_adapter.dart';
import '../../../owner_adapters/styio_compiler_adapter.dart';
import '../environment/system_compatibility/file_system/file_system_manager.dart';
import '../environment/system_compatibility/platform_manager/platform_manager.dart';
import '../environment/system_compatibility/process/process.dart';
import '../platform/platform_target.dart';
import 'adapter_contracts.dart';
import 'hosted_control_plane.dart';
import 'pafio_cli_discovery.dart';
import 'project_graph_adapter.dart';
import 'project_graph_contract.dart';

Map<String, String> Function() _environmentProvider = () =>
    const <String, String>{};

void debugOverrideProjectGraphEnvironment(Map<String, String>? environment) {
  _environmentProvider = environment == null
      ? () => const <String, String>{}
      : () => Map<String, String>.unmodifiable(environment);
}

Future<ProjectGraphAdapter> createPlatformProjectGraphAdapter({
  required PlatformTarget platformTarget,
  PlatformManagerBundle? platformManagers,
}) async {
  final hostedClient = await createHostedControlPlaneClient(
    platformTarget: platformTarget,
  );
  if (hostedClient != null) {
    return PlatformHostedAdapter(
      platformTarget: platformTarget,
      client: hostedClient,
    );
  }

  final managers = platformManagers;
  if (managers == null) {
    return _ScratchProjectGraphAdapter(workspaceRoot: _currentDirectoryPath());
  }
  final environment = _environmentProvider();
  final environmentWorkingDirectory = environment['PWD']?.trim();
  final workspaceRoot = await _discoverProjectRoot(
    managers,
    environmentWorkingDirectory == null || environmentWorkingDirectory.isEmpty
        ? _currentDirectoryPath()
        : environmentWorkingDirectory,
  );
  final pafioBinary = await resolvePafioBinary(
    managers,
    environment: environment,
  );
  final styioBinary = await _resolveManagedStyioBinary(
    managers,
    environment: environment,
  );
  return _ManagedMetadataProjectGraphAdapter(
    workspaceRoot: workspaceRoot,
    platformManagers: managers,
    pafioAdapter: pafioBinary == null
        ? null
        : PafioMetadataAdapter(
            binaryPath: pafioBinary,
            processManager: managers.process,
          ),
    compilerAdapter: styioBinary == null
        ? null
        : StyioCompilerAdapter(
            binaryPath: styioBinary,
            processManager: managers.process,
            environment: environment,
          ),
  );
}

final class _ManagedMetadataProjectGraphAdapter implements ProjectGraphAdapter {
  const _ManagedMetadataProjectGraphAdapter({
    required this.workspaceRoot,
    required this.platformManagers,
    required this.pafioAdapter,
    required this.compilerAdapter,
  });

  final String workspaceRoot;
  final PlatformManagerBundle platformManagers;
  final PafioMetadataAdapter? pafioAdapter;
  final StyioCompilerAdapter? compilerAdapter;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cli,
    languageService: AdapterEndpointCapability(
      level: compilerAdapter == null
          ? AdapterCapabilityLevel.unavailable
          : AdapterCapabilityLevel.available,
      detail: compilerAdapter == null
          ? 'Styio is unavailable through the local service.'
          : 'Styio compiler facts are consumed through vityod task supervision.',
      supportedContractVersions: compilerAdapter == null
          ? const <int>[]
          : const <int>[1],
    ),
    projectGraph: AdapterEndpointCapability(
      level: pafioAdapter == null
          ? AdapterCapabilityLevel.unavailable
          : AdapterCapabilityLevel.available,
      detail: pafioAdapter == null
          ? 'Pafio is unavailable; project metadata cannot be loaded.'
          : 'Pafio metadata v1 is consumed through vityod task supervision.',
      supportedContractVersions: pafioAdapter == null
          ? const <int>[]
          : const <int>[1],
    ),
    execution: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail: 'Project workflows use the daemon-owned process service.',
      supportedContractVersions: <int>[1],
    ),
    runtimeEvents: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail: 'Runtime events are consumed from the Styio contract.',
      supportedContractVersions: <int>[1],
    ),
  );

  @override
  Future<ProjectGraphSnapshot> loadProjectGraph() async {
    final compiler = await compilerAdapter?.inspect();
    final manifestPath = platformManagers.fileSystem.joinPath(<String>[
      workspaceRoot,
      'pafio.toml',
    ]);
    if (!await platformManagers.fileSystem.exists(manifestPath)) {
      return ProjectGraphSnapshot.scratch(
        workspaceRoot: workspaceRoot,
        activeFilePath: platformManagers.fileSystem.joinPath(<String>[
          workspaceRoot,
          'scratch',
          'main.styio',
        ]),
        title: 'Scratch Project',
        activeCompiler: compiler,
        toolchain: _systemCompilerToolchain(compiler),
        notes: const <String>[
          'No pafio.toml was found. Vityo remains in scratch mode.',
        ],
      );
    }
    final adapter = pafioAdapter;
    if (adapter == null) {
      return _blockedSnapshot(
        manifestPath: manifestPath,
        compiler: compiler,
        detail: 'Pafio metadata is unavailable through the local service.',
      );
    }
    try {
      return (await adapter.load(
        manifestPath: manifestPath,
      )).toProjectGraph(activeCompiler: compiler);
    } on Object catch (error) {
      return _blockedSnapshot(
        manifestPath: manifestPath,
        compiler: compiler,
        detail: 'pafio metadata --json failed: $error',
      );
    }
  }

  ProjectGraphSnapshot _blockedSnapshot({
    required String manifestPath,
    required CompilerHandshakeSnapshot? compiler,
    required String detail,
  }) {
    return ProjectGraphSnapshot(
      id: manifestPath,
      title: 'Pafio Project',
      kind: ProjectKind.package,
      workspaceRoot: workspaceRoot,
      workspaceMembers: const <String>[],
      manifestPath: manifestPath,
      packages: const <ProjectPackageSnapshot>[],
      dependencies: const <ProjectDependencySnapshot>[],
      targets: const <ProjectTargetDescriptor>[],
      editorFiles: const <String>[],
      toolchain: _systemCompilerToolchain(compiler),
      lockState: ProjectLockState.unknown,
      vendorState: ProjectVendorState.unknown,
      activeCompiler: compiler,
      projectGraphPayloadFailure: PublishedPayloadFailure(
        command: 'pafio metadata --json',
        detail: detail,
      ),
      sourceConfidenceByField:
          const <String, ProjectGraphFieldSourceConfidence>{},
      notes: <String>[detail],
    );
  }
}

final class _ScratchProjectGraphAdapter implements ProjectGraphAdapter {
  const _ScratchProjectGraphAdapter({required this.workspaceRoot});

  final String workspaceRoot;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot =>
      const AdapterCapabilitySnapshot(
        adapterKind: AdapterKind.cli,
        languageService: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'The local service was not injected.',
        ),
        projectGraph: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'The local service was not injected.',
        ),
        execution: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'The local service was not injected.',
        ),
        runtimeEvents: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'The local service was not injected.',
        ),
      );

  @override
  Future<ProjectGraphSnapshot> loadProjectGraph() async =>
      ProjectGraphSnapshot.scratch(
        workspaceRoot: workspaceRoot,
        activeFilePath: _joinPortable(workspaceRoot, 'scratch/main.styio'),
        title: 'Scratch Project',
        toolchain: const ToolchainStatusSnapshot(
          source: ToolchainResolutionSource.unavailable,
          detail: 'The local service was not injected.',
        ),
        notes: const <String>['The local service was not injected.'],
      );
}

ToolchainStatusSnapshot _systemCompilerToolchain(
  CompilerHandshakeSnapshot? compiler,
) {
  if (compiler == null) {
    return const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.unavailable,
      detail: 'System Styio was not resolved through the local service.',
    );
  }
  return ToolchainStatusSnapshot(
    source: ToolchainResolutionSource.environment,
    detail:
        'System Styio ${compiler.compilerVersion} reported machine-info v1.',
    channel: compiler.channel,
    version: compiler.compilerVersion,
  );
}

Future<String> _discoverProjectRoot(
  PlatformManagerBundle managers,
  String startPath,
) async {
  var current = managers.fileSystem.normalizePath(startPath);
  while (true) {
    final manifest = managers.fileSystem.joinPath(<String>[
      current,
      'pafio.toml',
    ]);
    try {
      if (await managers.fileSystem.exists(manifest)) return current;
    } on Object catch (error) {
      final failure = managers.fileSystem.classifyFailure(
        error,
        operation: 'discoverProjectRoot',
        target: manifest,
      );
      if (failure.kind == FileSystemFailureKind.outsideWorkspace) {
        return managers.fileSystem.normalizePath(startPath);
      }
      rethrow;
    }
    final separator = managers.fileSystem.compatibility.pathSeparator;
    final index = current.lastIndexOf(separator);
    if (index <= 0) return managers.fileSystem.normalizePath(startPath);
    final parent = current.substring(0, index);
    if (parent == current || parent.isEmpty) {
      return managers.fileSystem.normalizePath(startPath);
    }
    current = parent;
  }
}

Future<String?> _resolveManagedStyioBinary(
  PlatformManagerBundle managers, {
  required Map<String, String> environment,
}) async {
  final candidates = <String>[
    if (environment['VITYO_STYIO_BIN'] case final explicit?
        when explicit.isNotEmpty)
      explicit,
    if (managers.context.fileSystem.operatingSystem == 'windows')
      r'C:\Program Files\Styio\styio.exe'
    else ...const <String>[
      '/usr/local/bin/styio',
      '/usr/bin/styio',
      '/opt/homebrew/bin/styio',
    ],
  ];
  for (final candidate in candidates) {
    try {
      final result = await managers.process.run(
        ProcessCommandRequest(
          executablePath: candidate,
          arguments: const <String>['--machine-info=json'],
          environment: environment,
          timeout: const Duration(seconds: 5),
          serviceKind: ProcessServiceKind.styio,
        ),
      );
      if (result.succeeded) return candidate;
    } on Object {
      continue;
    }
  }
  return null;
}

String _currentDirectoryPath() {
  final path = Uri.base.toFilePath();
  return path.endsWith('/') && path.length > 1
      ? path.substring(0, path.length - 1)
      : path;
}

String _joinPortable(String left, String right) {
  final separator = left.contains(r'\') ? r'\' : '/';
  final normalizedLeft = left.endsWith(separator)
      ? left.substring(0, left.length - 1)
      : left;
  return '$normalizedLeft$separator${right.replaceAll('/', separator)}';
}
