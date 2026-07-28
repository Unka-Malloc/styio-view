import '../platform/platform_target.dart';
import 'deployment_adapter.dart';
import 'hosted_control_plane.dart';
import 'project_graph_contract.dart';

Future<DeploymentAdapter> createPlatformDeploymentAdapter({
  required PlatformTarget platformTarget,
}) async {
  final hostedClient = await createHostedControlPlaneClient(
    platformTarget: platformTarget,
  );
  if (hostedClient == null) {
    throw StateError('Hosted deployment requires a published hosted route.');
  }
  return _HostedDeploymentAdapter(hostedClient: hostedClient);
}

class _HostedDeploymentAdapter implements DeploymentAdapter {
  const _HostedDeploymentAdapter({required this.hostedClient});

  final HostedControlPlaneClient hostedClient;

  @override
  Future<DeploymentCommandResult> packProject({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) async {
    final workspaceId = projectGraph.hostedWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      return const DeploymentCommandResult(
        command: 'pack',
        status: DeploymentCommandStatus.blocked,
        statusMessage: 'Hosted workspace identity is unavailable for pack.',
        stdout: '',
        stderr: '',
      );
    }
    final response = await hostedClient.packProject(
      workspaceId: workspaceId,
      packageName: packageName,
      outputPath: outputPath,
    );
    return _deploymentResultFromHostedResponse(
      command: 'pack',
      response: response,
    );
  }

  @override
  Future<DeploymentCommandResult> preparePublish({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) async {
    final workspaceId = projectGraph.hostedWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      return const DeploymentCommandResult(
        command: 'publish',
        status: DeploymentCommandStatus.blocked,
        statusMessage:
            'Hosted workspace identity is unavailable for publish preflight.',
        stdout: '',
        stderr: '',
      );
    }
    final response = await hostedClient.preparePublish(
      workspaceId: workspaceId,
      packageName: packageName,
      outputPath: outputPath,
    );
    return _deploymentResultFromHostedResponse(
      command: 'publish',
      response: response,
    );
  }

  @override
  Future<DeploymentCommandResult> publishToRegistry({
    required ProjectGraphSnapshot projectGraph,
    required String registryRoot,
    String? packageName,
    String? outputPath,
  }) async {
    final workspaceId = projectGraph.hostedWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      return const DeploymentCommandResult(
        command: 'publish',
        status: DeploymentCommandStatus.blocked,
        statusMessage:
            'Hosted workspace identity is unavailable for registry publish.',
        stdout: '',
        stderr: '',
      );
    }
    final response = await hostedClient.publishToRegistry(
      workspaceId: workspaceId,
      registryRoot: registryRoot,
      packageName: packageName,
      outputPath: outputPath,
    );
    return _deploymentResultFromHostedResponse(
      command: 'publish',
      response: response,
    );
  }
}

DeploymentCommandResult _deploymentResultFromHostedResponse({
  required String command,
  required Map<String, dynamic> response,
}) {
  final returnCode = response['returncode'] as int? ?? 1;
  final stdout = response['stdout'] as String? ?? '';
  final stderr = response['stderr'] as String? ?? '';
  if (returnCode == 0) {
    return DeploymentCommandResult(
      command: command,
      status: DeploymentCommandStatus.succeeded,
      statusMessage:
          response['message'] as String? ??
          '$command completed through the hosted control plane.',
      stdout: stdout,
      stderr: stderr,
      payload: response['payload'] as Map<String, dynamic>?,
    );
  }
  return DeploymentCommandResult(
    command: command,
    status: DeploymentCommandStatus.failed,
    statusMessage:
        response['message'] as String? ??
        '$command failed through the hosted control plane.',
    stdout: stdout,
    stderr: stderr,
    errorPayload: response['error_payload'] as Map<String, dynamic>?,
  );
}
