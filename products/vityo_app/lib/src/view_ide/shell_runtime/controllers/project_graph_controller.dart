import '../../backend_toolchain/backend_toolchain.dart';
import '../../../ide/workspace/workspace.dart';

/// Owns authoritative project-graph refresh and adapter capability snapshots.
final class ProjectGraphController {
  ProjectGraphController({
    required this.adapter,
    required this.workspaceController,
    required this.refreshExecutionAdapter,
    required this.executionCapability,
    required this.runtimeEventCapability,
    required this.supplementalCapabilities,
    required this.log,
  }) : _capabilities = _resolveCapabilities(
         projectGraphCapability: adapter.capabilitySnapshot,
         downstreamCapabilities: <AdapterCapabilitySnapshot>[
           executionCapability(),
           runtimeEventCapability(),
           ...supplementalCapabilities,
         ],
       );

  final ProjectGraphAdapter adapter;
  final WorkspaceController workspaceController;
  final Future<void> Function(ProjectGraphSnapshot projectGraph)
  refreshExecutionAdapter;
  final AdapterCapabilitySnapshot Function() executionCapability;
  final AdapterCapabilitySnapshot Function() runtimeEventCapability;
  final List<AdapterCapabilitySnapshot> supplementalCapabilities;
  final void Function(String message) log;

  List<AdapterCapabilitySnapshot> _capabilities;

  List<AdapterCapabilitySnapshot> get capabilities => _capabilities;

  Future<void> refresh({String? reason}) async {
    final previousProject = workspaceController.activeProject;
    final refreshedProject = await adapter.loadProjectGraph();
    await refreshExecutionAdapter(refreshedProject);
    _capabilities = _resolveCapabilities(
      projectGraphCapability: adapter.capabilitySnapshot,
      downstreamCapabilities: <AdapterCapabilitySnapshot>[
        executionCapability(),
        runtimeEventCapability(),
        ...supplementalCapabilities,
      ],
    );
    workspaceController.replaceProject(
      refreshedProject,
      activeFilePath: workspaceController.activeFilePath,
    );
    final previousCompiler = previousProject.activeCompiler?.compilerVersion;
    final refreshedCompiler = refreshedProject.activeCompiler?.compilerVersion;
    log(
      'Project graph refreshed: ${refreshedProject.title}'
      '${reason == null ? '' : ' ($reason)'}'
      '${previousCompiler == refreshedCompiler ? '' : ' · compiler ${previousCompiler ?? 'unresolved'} -> ${refreshedCompiler ?? 'unresolved'}'}.',
    );
  }
}

List<AdapterCapabilitySnapshot> _resolveCapabilities({
  required AdapterCapabilitySnapshot projectGraphCapability,
  required Iterable<AdapterCapabilitySnapshot> downstreamCapabilities,
}) {
  final projectRouteUnavailable =
      projectGraphCapability.projectGraph.level ==
      AdapterCapabilityLevel.unavailable;
  return normalizeCapabilitySnapshots(<AdapterCapabilitySnapshot>[
    projectGraphCapability,
    for (final capability in downstreamCapabilities)
      if (!projectRouteUnavailable ||
          capability.adapterKind != projectGraphCapability.adapterKind)
        capability,
  ]);
}
