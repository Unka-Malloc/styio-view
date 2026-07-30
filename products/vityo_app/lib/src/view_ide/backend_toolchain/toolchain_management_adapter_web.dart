import '../platform/platform_target.dart';
import 'hosted_control_plane.dart';
import 'project_graph_contract.dart';
import 'toolchain_management_adapter.dart';

Future<ToolchainManagementAdapter> createPlatformToolchainManagementAdapter({
  required PlatformTarget platformTarget,
}) async {
  final hostedClient = await createHostedControlPlaneClient(
    platformTarget: platformTarget,
  );
  if (hostedClient == null) {
    throw StateError(
      'Hosted toolchain management requires a published hosted route.',
    );
  }
  return _HostedToolchainManagementAdapter(hostedClient: hostedClient);
}

class _HostedToolchainManagementAdapter implements ToolchainManagementAdapter {
  const _HostedToolchainManagementAdapter({required this.hostedClient});

  final HostedControlPlaneClient hostedClient;

  @override
  Future<ToolchainCommandResult> installManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String styioBinaryPath,
  }) async {
    final workspaceId = projectGraph.hostedWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      return const ToolchainCommandResult(
        command: 'tool install',
        status: ToolchainCommandStatus.blocked,
        statusMessage:
            'Hosted workspace identity is unavailable for tool install.',
        stdout: '',
        stderr: '',
      );
    }
    final response = await hostedClient.toolInstall(
      workspaceId: workspaceId,
      styioBinaryPath: styioBinaryPath,
    );
    return _toolchainCommandResultFromHostedResponse(
      command: 'tool install',
      response: response,
    );
  }

  @override
  Future<ToolchainCommandResult> useManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async {
    final workspaceId = projectGraph.hostedWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      return const ToolchainCommandResult(
        command: 'tool use',
        status: ToolchainCommandStatus.blocked,
        statusMessage: 'Hosted workspace identity is unavailable for tool use.',
        stdout: '',
        stderr: '',
      );
    }
    final response = await hostedClient.toolUse(
      workspaceId: workspaceId,
      compilerVersion: compilerVersion,
      channel: channel,
    );
    return _toolchainCommandResultFromHostedResponse(
      command: 'tool use',
      response: response,
    );
  }

  @override
  Future<ToolchainCommandResult> pinManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async {
    final workspaceId = projectGraph.hostedWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      return const ToolchainCommandResult(
        command: 'tool pin',
        status: ToolchainCommandStatus.blocked,
        statusMessage: 'Hosted workspace identity is unavailable for tool pin.',
        stdout: '',
        stderr: '',
      );
    }
    final response = await hostedClient.toolPin(
      workspaceId: workspaceId,
      compilerVersion: compilerVersion,
      channel: channel,
    );
    return _toolchainCommandResultFromHostedResponse(
      command: 'tool pin',
      response: response,
    );
  }

  @override
  Future<ToolchainCommandResult> clearPinnedCompiler({
    required ProjectGraphSnapshot projectGraph,
  }) async {
    final workspaceId = projectGraph.hostedWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      return const ToolchainCommandResult(
        command: 'tool pin',
        status: ToolchainCommandStatus.blocked,
        statusMessage:
            'Hosted workspace identity is unavailable for tool pin clear.',
        stdout: '',
        stderr: '',
      );
    }
    final response = await hostedClient.toolClearPin(workspaceId: workspaceId);
    return _toolchainCommandResultFromHostedResponse(
      command: 'tool pin',
      response: response,
    );
  }
}

ToolchainCommandResult _toolchainCommandResultFromHostedResponse({
  required String command,
  required Map<String, dynamic> response,
}) {
  final returnCode = response['returncode'] as int? ?? 1;
  final stdout = response['stdout'] as String? ?? '';
  final stderr = response['stderr'] as String? ?? '';
  if (returnCode == 0) {
    return ToolchainCommandResult(
      command: command,
      status: ToolchainCommandStatus.succeeded,
      statusMessage:
          response['message'] as String? ??
          '$command completed through the hosted control plane.',
      stdout: stdout,
      stderr: stderr,
      payload: response['payload'] as Map<String, dynamic>?,
    );
  }
  return ToolchainCommandResult(
    command: command,
    status: ToolchainCommandStatus.failed,
    statusMessage:
        response['message'] as String? ??
        '$command failed through the hosted control plane.',
    stdout: stdout,
    stderr: stderr,
    errorPayload: response['error_payload'] as Map<String, dynamic>?,
  );
}
