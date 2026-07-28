import '../platform/platform_target.dart';
import 'adapter_contracts.dart';
import 'hosted_control_plane.dart';
import 'hosted_payload_codec.dart';
import 'project_graph_adapter.dart';
import 'project_graph_contract.dart';

Future<ProjectGraphAdapter> createPlatformProjectGraphAdapter({
  required PlatformTarget platformTarget,
}) async {
  final hostedClient = await createHostedControlPlaneClient(
    platformTarget: platformTarget,
  );
  if (hostedClient == null) {
    throw StateError(
      'Web hosted route requires a published hosted control plane.',
    );
  }
  return _HostedProjectGraphAdapter(
    platformTarget: platformTarget,
    hostedClient: hostedClient,
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
