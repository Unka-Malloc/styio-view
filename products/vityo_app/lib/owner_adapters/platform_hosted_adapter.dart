import '../src/view_ide/backend_toolchain/adapter_contracts.dart';
import '../src/view_ide/backend_toolchain/hosted_control_plane.dart';
import '../src/view_ide/backend_toolchain/hosted_payload_codec.dart';
import '../src/view_ide/backend_toolchain/project_graph_adapter.dart';
import '../src/view_ide/backend_toolchain/project_graph_contract.dart';
import '../src/view_ide/platform/platform_target.dart';

/// Consumes the Platform hosted-workspace v1 contract.
///
/// Hosted workspace lifecycle and execution remain Platform-owned; this
/// adapter does not translate them into Pafio-local state.
class PlatformHostedAdapter implements ProjectGraphAdapter {
  PlatformHostedAdapter({required this.platformTarget, required this.client})
    : _workspaceId = client.config.workspaceId;

  final PlatformTarget platformTarget;
  final HostedControlPlaneClient client;
  String? _workspaceId;

  @override
  AdapterCapabilitySnapshot
  get capabilitySnapshot => const AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cloud,
    languageService: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.partial,
      detail: 'Hosted language service is consumed directly from Platform.',
    ),
    projectGraph: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail:
          'Platform publishes hosted workspace project facts through hosted-workspace v1.',
      supportedContractVersions: <int>[1],
    ),
    execution: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail: 'Hosted execution is owned by Platform.',
      supportedContractVersions: <int>[1],
    ),
    runtimeEvents: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail: 'Hosted runtime events are owned by Platform.',
      supportedContractVersions: <int>[1],
    ),
  );

  @override
  Future<ProjectGraphSnapshot> loadProjectGraph() async {
    final response = _workspaceId == null
        ? await client.openWorkspace(platformTarget: platformTarget)
        : await client.projectGraph(workspaceId: _workspaceId!);
    final snapshot = hostedProjectGraphSnapshotFromEnvelope(response);
    _workspaceId = snapshot.hostedWorkspace?.workspaceId ?? _workspaceId;
    return snapshot;
  }
}
