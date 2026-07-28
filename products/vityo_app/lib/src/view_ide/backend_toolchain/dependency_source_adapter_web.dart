import 'hosted_control_plane.dart';
import 'project_graph_contract.dart';
import 'dependency_source_adapter.dart';
import '../platform/platform_target.dart';

Future<DependencySourceAdapter> createPlatformDependencySourceAdapter({
  required PlatformTarget platformTarget,
}) async {
  final hostedClient = await createHostedControlPlaneClient(
    platformTarget: platformTarget,
  );
  if (hostedClient == null) {
    throw StateError(
      'Hosted dependency management requires a published hosted route.',
    );
  }
  return _HostedDependencySourceAdapter(hostedClient: hostedClient);
}

class _HostedDependencySourceAdapter implements DependencySourceAdapter {
  const _HostedDependencySourceAdapter({required this.hostedClient});

  final HostedControlPlaneClient hostedClient;

  @override
  Future<DependencySourceCommandResult> fetchDependencies({
    required ProjectGraphSnapshot projectGraph,
    bool locked = false,
    bool offline = false,
  }) async {
    final workspaceId = projectGraph.hostedWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      return const DependencySourceCommandResult(
        command: 'fetch',
        status: DependencySourceCommandStatus.blocked,
        statusMessage:
            'Hosted workspace identity is unavailable for dependency fetch.',
        stdout: '',
        stderr: '',
      );
    }
    final response = await hostedClient.fetchDependencies(
      workspaceId: workspaceId,
      locked: locked,
      offline: offline,
    );
    return _dependencyResultFromHostedResponse(
      command: 'fetch',
      response: response,
    );
  }

  @override
  Future<DependencySourceCommandResult> vendorDependencies({
    required ProjectGraphSnapshot projectGraph,
    String? outputPath,
    bool locked = false,
    bool offline = false,
  }) async {
    final workspaceId = projectGraph.hostedWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      return const DependencySourceCommandResult(
        command: 'vendor',
        status: DependencySourceCommandStatus.blocked,
        statusMessage:
            'Hosted workspace identity is unavailable for dependency vendoring.',
        stdout: '',
        stderr: '',
      );
    }
    final response = await hostedClient.vendorDependencies(
      workspaceId: workspaceId,
      outputPath: outputPath,
      locked: locked,
      offline: offline,
    );
    return _dependencyResultFromHostedResponse(
      command: 'vendor',
      response: response,
    );
  }
}

DependencySourceCommandResult _dependencyResultFromHostedResponse({
  required String command,
  required Map<String, dynamic> response,
}) {
  final returnCode = response['returncode'] as int? ?? 1;
  final stdout = response['stdout'] as String? ?? '';
  final stderr = response['stderr'] as String? ?? '';
  if (returnCode == 0) {
    return DependencySourceCommandResult(
      command: command,
      status: DependencySourceCommandStatus.succeeded,
      statusMessage:
          response['message'] as String? ??
          '$command completed through the hosted control plane.',
      stdout: stdout,
      stderr: stderr,
      payload: response['payload'] as Map<String, dynamic>?,
    );
  }
  return DependencySourceCommandResult(
    command: command,
    status: DependencySourceCommandStatus.failed,
    statusMessage:
        response['message'] as String? ??
        '$command failed through the hosted control plane.',
    stdout: stdout,
    stderr: stderr,
    errorPayload: response['error_payload'] as Map<String, dynamic>?,
  );
}
