import 'dart:io';

import '../../../owner_adapters/pafio_metadata_adapter.dart';
import '../../../owner_adapters/platform_hosted_adapter.dart';
import '../../../owner_adapters/styio_compiler_adapter.dart';
import '../platform/platform_target.dart';
import 'adapter_contracts.dart';
import 'hosted_control_plane.dart';
import 'pafio_cli_discovery.dart';
import 'project_graph_adapter.dart';
import 'project_graph_contract.dart';

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
    return PlatformHostedAdapter(
      platformTarget: platformTarget,
      client: hostedClient,
    );
  }

  final workspaceRoot = _discoverProjectRoot(Directory.current);
  final environment = _environmentProvider();
  final pafioBinary = await resolvePafioBinary(environment: environment);
  return _LocalMetadataProjectGraphAdapter(
    workspaceRoot: workspaceRoot,
    pafioBinary: pafioBinary,
    compilerAdapter: StyioCompilerAdapter(environment: environment),
  );
}

class _LocalMetadataProjectGraphAdapter implements ProjectGraphAdapter {
  const _LocalMetadataProjectGraphAdapter({
    required this.workspaceRoot,
    required this.pafioBinary,
    required this.compilerAdapter,
  });

  final Directory workspaceRoot;
  final String? pafioBinary;
  final StyioCompilerAdapter compilerAdapter;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cli,
    languageService: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail:
          'Language-service compiler facts are consumed directly from system Styio.',
      supportedContractVersions: <int>[1],
    ),
    projectGraph: AdapterEndpointCapability(
      level: pafioBinary == null
          ? AdapterCapabilityLevel.unavailable
          : AdapterCapabilityLevel.available,
      detail: pafioBinary == null
          ? 'Pafio is unavailable; project metadata cannot be loaded.'
          : 'Project facts are consumed from Pafio metadata v1.',
      supportedContractVersions: pafioBinary == null
          ? const <int>[]
          : const <int>[1],
    ),
    execution: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail:
          'Project workflows consume Pafio workflow JSON through the execution adapter.',
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
    final compiler = await compilerAdapter.inspect();
    final manifestPath = _joinPath(workspaceRoot.path, 'pafio.toml');
    if (!await File(manifestPath).exists()) {
      return ProjectGraphSnapshot.scratch(
        workspaceRoot: workspaceRoot.path,
        activeFilePath: _joinPath(
          _joinPath(workspaceRoot.path, 'scratch'),
          'main.styio',
        ),
        title: 'Scratch Project',
        activeCompiler: compiler,
        toolchain: _systemCompilerToolchain(compiler),
        notes: const <String>[
          'No pafio.toml was found. Vityo remains in scratch mode.',
        ],
      );
    }
    if (pafioBinary == null) {
      return _blockedSnapshot(
        manifestPath: manifestPath,
        compiler: compiler,
        detail:
            'pafio metadata --json is unavailable because Pafio was not found via VITYO_PAFIO_BIN or PATH.',
      );
    }

    try {
      return (await PafioMetadataAdapter(binaryPath: pafioBinary!).load(
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
      workspaceRoot: workspaceRoot.path,
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

ToolchainStatusSnapshot _systemCompilerToolchain(
  CompilerHandshakeSnapshot? compiler,
) {
  if (compiler == null) {
    return const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.unavailable,
      detail: 'System Styio was not found via VITYO_STYIO_BIN or PATH.',
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

Directory _discoverProjectRoot(Directory start) {
  var current = start.absolute;
  while (true) {
    if (File(_joinPath(current.path, 'pafio.toml')).existsSync()) {
      return current;
    }
    final parent = current.parent;
    if (parent.path == current.path) {
      return start.absolute;
    }
    current = parent;
  }
}

String _joinPath(String left, String right) {
  final separator = Platform.pathSeparator;
  final normalizedLeft = left.endsWith(separator)
      ? left.substring(0, left.length - separator.length)
      : left;
  final normalizedRight = right.startsWith(separator)
      ? right.substring(separator.length)
      : right;
  return '$normalizedLeft$separator$normalizedRight';
}
