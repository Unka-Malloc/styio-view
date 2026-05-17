import '../platform/platform_target.dart';
import 'dependency_source_adapter.dart';
import 'hosted_control_plane.dart';
import 'project_graph_contract.dart';
import 'spio_cli_support.dart';

Future<DependencySourceAdapter> createPlatformDependencySourceAdapter({
  required PlatformTarget platformTarget,
}) async {
  final hostedClient = await createHostedControlPlaneClient(
    platformTarget: platformTarget,
  );
  if (hostedClient != null) {
    return _HostedDependencySourceAdapter(hostedClient: hostedClient);
  }
  return _LocalCliDependencySourceAdapter(platformTarget: platformTarget);
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
    try {
      final response = await hostedClient.fetchDependencies(
        workspaceId: workspaceId,
        locked: locked,
        offline: offline,
      );
      return _dependencyResultFromHostedResponse(
        command: 'fetch',
        response: response,
      );
    } catch (error) {
      return DependencySourceCommandResult(
        command: 'fetch',
        status: DependencySourceCommandStatus.failed,
        statusMessage: 'Hosted fetch failed: $error',
        stdout: '',
        stderr: '',
      );
    }
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
    try {
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
    } catch (error) {
      return DependencySourceCommandResult(
        command: 'vendor',
        status: DependencySourceCommandStatus.failed,
        statusMessage: 'Hosted vendor failed: $error',
        stdout: '',
        stderr: '',
      );
    }
  }
}

class _LocalCliDependencySourceAdapter implements DependencySourceAdapter {
  const _LocalCliDependencySourceAdapter({required this.platformTarget});

  final PlatformTarget platformTarget;

  @override
  Future<DependencySourceCommandResult> fetchDependencies({
    required ProjectGraphSnapshot projectGraph,
    bool locked = false,
    bool offline = false,
  }) {
    return _runCommand(
      projectGraph: projectGraph,
      command: 'fetch',
      args: <String>[
        '--json',
        'fetch',
        ..._manifestArgs(projectGraph),
        if (locked) '--locked',
        if (offline) '--offline',
      ],
    );
  }

  @override
  Future<DependencySourceCommandResult> vendorDependencies({
    required ProjectGraphSnapshot projectGraph,
    String? outputPath,
    bool locked = false,
    bool offline = false,
  }) {
    return _runCommand(
      projectGraph: projectGraph,
      command: 'vendor',
      args: <String>[
        '--json',
        'vendor',
        ..._manifestArgs(projectGraph),
        if (outputPath != null && outputPath.isNotEmpty) ...<String>[
          '--output',
          outputPath,
        ],
        if (locked) '--locked',
        if (offline) '--offline',
      ],
    );
  }

  Future<DependencySourceCommandResult> _runCommand({
    required ProjectGraphSnapshot projectGraph,
    required String command,
    required List<String> args,
  }) async {
    final blockedReason = blockedDependencySourceCommandReason(
      platformTarget: platformTarget,
      projectGraph: projectGraph,
      command: command,
    );
    if (blockedReason != null) {
      return blockedSpioCommandResult(
        factory: _dependencyCommandResult,
        command: command,
        statusMessage: blockedReason,
      );
    }

    return runLocalSpioCommand(
      projectGraph: projectGraph,
      command: command,
      args: args,
      factory: _dependencyCommandResult,
    );
  }
}

List<String> _manifestArgs(ProjectGraphSnapshot projectGraph) {
  final manifestPath = projectGraph.manifestPath;
  if (manifestPath == null || manifestPath.isEmpty) {
    return const <String>[];
  }
  return spioManifestArgs(projectGraph);
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

DependencySourceCommandResult _dependencyCommandResult({
  required LocalSpioCommandOutcome outcome,
  required String command,
  required String statusMessage,
  required String stdout,
  required String stderr,
  Map<String, dynamic>? payload,
  Map<String, dynamic>? errorPayload,
}) {
  return DependencySourceCommandResult(
    command: command,
    status: switch (outcome) {
      LocalSpioCommandOutcome.blocked => DependencySourceCommandStatus.blocked,
      LocalSpioCommandOutcome.succeeded =>
        DependencySourceCommandStatus.succeeded,
      LocalSpioCommandOutcome.failed => DependencySourceCommandStatus.failed,
    },
    statusMessage: statusMessage,
    stdout: stdout,
    stderr: stderr,
    payload: payload,
    errorPayload: errorPayload,
  );
}
