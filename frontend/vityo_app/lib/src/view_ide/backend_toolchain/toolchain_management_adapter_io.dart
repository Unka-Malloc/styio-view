import '../platform/platform_target.dart';
import 'hosted_control_plane.dart';
import 'project_graph_contract.dart';
import 'spio_cli_support.dart';
import 'toolchain_management_adapter.dart';

ToolchainCommandResult _blockedToolchainCommandResult({
  required String command,
  required String statusMessage,
}) {
  return blockedSpioCommandResult(
    factory: _toolchainCommandResult,
    command: command,
    statusMessage: statusMessage,
  );
}

ToolchainCommandResult? _unsupportedLocalToolchainPlatformResult({
  required PlatformTarget platformTarget,
  required String command,
}) {
  return switch (platformTarget) {
    PlatformTarget.ios || PlatformTarget.web => _blockedToolchainCommandResult(
      command: command,
      statusMessage:
          '${platformTarget.label} does not expose local spio toolchain management.',
    ),
    _ => null,
  };
}

Future<ToolchainManagementAdapter> createPlatformToolchainManagementAdapter({
  required PlatformTarget platformTarget,
}) async {
  final hostedClient = await createHostedControlPlaneClient(
    platformTarget: platformTarget,
  );
  if (hostedClient != null) {
    return _HostedToolchainManagementAdapter(
      platformTarget: platformTarget,
      hostedClient: hostedClient,
    );
  }
  return _LocalCliToolchainManagementAdapter(platformTarget: platformTarget);
}

class _HostedToolchainManagementAdapter implements ToolchainManagementAdapter {
  const _HostedToolchainManagementAdapter({
    required this.platformTarget,
    required this.hostedClient,
  });

  final PlatformTarget platformTarget;
  final HostedControlPlaneClient hostedClient;

  @override
  Future<ToolchainCommandResult> installManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String styioBinaryPath,
  }) => _runHostedToolchainCommand(
    projectGraph: projectGraph,
    command: 'tool install',
    unavailableMessage:
        'Hosted workspace identity is unavailable for tool install.',
    failurePrefix: 'Hosted tool install failed',
    invoke: (workspaceId) => hostedClient.toolInstall(
      workspaceId: workspaceId,
      styioBinaryPath: styioBinaryPath,
    ),
  );

  @override
  Future<ToolchainCommandResult> useManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) => _runHostedToolchainCommand(
    projectGraph: projectGraph,
    command: 'tool use',
    unavailableMessage:
        'Hosted workspace identity is unavailable for tool use.',
    failurePrefix: 'Hosted tool use failed',
    invoke: (workspaceId) => hostedClient.toolUse(
      workspaceId: workspaceId,
      compilerVersion: compilerVersion,
      channel: channel,
    ),
  );

  @override
  Future<ToolchainCommandResult> pinManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) => _runHostedToolchainCommand(
    projectGraph: projectGraph,
    command: 'tool pin',
    unavailableMessage:
        'Hosted workspace identity is unavailable for tool pin.',
    failurePrefix: 'Hosted tool pin failed',
    invoke: (workspaceId) => hostedClient.toolPin(
      workspaceId: workspaceId,
      compilerVersion: compilerVersion,
      channel: channel,
    ),
  );

  @override
  Future<ToolchainCommandResult> clearPinnedCompiler({
    required ProjectGraphSnapshot projectGraph,
  }) => _runHostedToolchainCommand(
    projectGraph: projectGraph,
    command: 'tool pin',
    unavailableMessage:
        'Hosted workspace identity is unavailable for tool pin clear.',
    failurePrefix: 'Hosted tool pin clear failed',
    invoke: (workspaceId) =>
        hostedClient.toolClearPin(workspaceId: workspaceId),
  );

  Future<ToolchainCommandResult> _runHostedToolchainCommand({
    required ProjectGraphSnapshot projectGraph,
    required String command,
    required String unavailableMessage,
    required String failurePrefix,
    required Future<Map<String, dynamic>> Function(String workspaceId) invoke,
  }) async {
    final workspaceId = projectGraph.hostedWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      return ToolchainCommandResult(
        command: command,
        status: ToolchainCommandStatus.blocked,
        statusMessage: unavailableMessage,
        stdout: '',
        stderr: '',
      );
    }
    try {
      final response = await invoke(workspaceId);
      return _toolchainCommandResultFromHostedResponse(
        command: command,
        response: response,
      );
    } catch (error) {
      return ToolchainCommandResult(
        command: command,
        status: ToolchainCommandStatus.failed,
        statusMessage: '$failurePrefix: $error',
        stdout: '',
        stderr: '',
      );
    }
  }
}

class _LocalCliToolchainManagementAdapter
    implements ToolchainManagementAdapter {
  const _LocalCliToolchainManagementAdapter({required this.platformTarget});

  final PlatformTarget platformTarget;

  @override
  Future<ToolchainCommandResult> installManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String styioBinaryPath,
  }) {
    return _runToolchainCommand(
      projectGraph: projectGraph,
      command: 'tool install',
      args: <String>[
        '--json',
        'tool',
        'install',
        '--styio-bin',
        styioBinaryPath,
      ],
    );
  }

  @override
  Future<ToolchainCommandResult> useManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) {
    return _runToolchainCommand(
      projectGraph: projectGraph,
      command: 'tool use',
      args: <String>[
        '--json',
        'tool',
        'use',
        '--version',
        compilerVersion,
        if (channel != null && channel.isNotEmpty) ...<String>[
          '--channel',
          channel,
        ],
      ],
    );
  }

  @override
  Future<ToolchainCommandResult> pinManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) {
    final manifestPath = projectGraph.manifestPath;
    if (manifestPath == null || manifestPath.isEmpty) {
      return Future<ToolchainCommandResult>.value(
        _blockedToolchainCommandResult(
          command: 'tool pin',
          statusMessage:
              'Project pinning requires a resolved spio manifest path.',
        ),
      );
    }
    return _runToolchainCommand(
      projectGraph: projectGraph,
      command: 'tool pin',
      args: <String>[
        '--json',
        'tool',
        'pin',
        '--manifest-path',
        manifestPath,
        '--version',
        compilerVersion,
        if (channel != null && channel.isNotEmpty) ...<String>[
          '--channel',
          channel,
        ],
      ],
    );
  }

  @override
  Future<ToolchainCommandResult> clearPinnedCompiler({
    required ProjectGraphSnapshot projectGraph,
  }) {
    final manifestPath = projectGraph.manifestPath;
    if (manifestPath == null || manifestPath.isEmpty) {
      return Future<ToolchainCommandResult>.value(
        _blockedToolchainCommandResult(
          command: 'tool pin',
          statusMessage:
              'Clearing a project pin requires a resolved spio manifest path.',
        ),
      );
    }
    return _runToolchainCommand(
      projectGraph: projectGraph,
      command: 'tool pin',
      args: <String>[
        '--json',
        'tool',
        'pin',
        '--manifest-path',
        manifestPath,
        '--clear',
      ],
    );
  }

  Future<ToolchainCommandResult> _runToolchainCommand({
    required ProjectGraphSnapshot projectGraph,
    required String command,
    required List<String> args,
  }) async {
    final blockedResult = _unsupportedLocalToolchainPlatformResult(
      platformTarget: platformTarget,
      command: command,
    );
    if (blockedResult != null) {
      return blockedResult;
    }

    return runLocalSpioCommand(
      projectGraph: projectGraph,
      command: command,
      args: args,
      factory: _toolchainCommandResult,
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

ToolchainCommandResult _toolchainCommandResult({
  required LocalSpioCommandOutcome outcome,
  required String command,
  required String statusMessage,
  required String stdout,
  required String stderr,
  Map<String, dynamic>? payload,
  Map<String, dynamic>? errorPayload,
}) {
  return ToolchainCommandResult(
    command: command,
    status: switch (outcome) {
      LocalSpioCommandOutcome.blocked => ToolchainCommandStatus.blocked,
      LocalSpioCommandOutcome.succeeded => ToolchainCommandStatus.succeeded,
      LocalSpioCommandOutcome.failed => ToolchainCommandStatus.failed,
    },
    statusMessage: statusMessage,
    stdout: stdout,
    stderr: stderr,
    payload: payload,
    errorPayload: errorPayload,
  );
}
