import '../platform/platform_target.dart';
import 'deployment_adapter.dart';
import 'hosted_control_plane.dart';
import 'project_graph_contract.dart';
import 'spio_cli_support.dart';

Future<DeploymentAdapter> createPlatformDeploymentAdapter({
  required PlatformTarget platformTarget,
}) async {
  final hostedClient = await createHostedControlPlaneClient(
    platformTarget: platformTarget,
  );
  if (hostedClient != null) {
    return _HostedDeploymentAdapter(hostedClient: hostedClient);
  }
  return _LocalCliDeploymentAdapter(platformTarget: platformTarget);
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
    try {
      final response = await hostedClient.packProject(
        workspaceId: workspaceId,
        packageName: packageName,
        outputPath: outputPath,
      );
      return _deploymentResultFromHostedResponse(
        command: 'pack',
        response: response,
      );
    } catch (error) {
      return DeploymentCommandResult(
        command: 'pack',
        status: DeploymentCommandStatus.failed,
        statusMessage: 'Hosted pack failed: $error',
        stdout: '',
        stderr: '',
      );
    }
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
    final resolvedPublishPackage = _resolvePublishPackage(
      projectGraph: projectGraph,
      explicitPackageName: packageName,
    );
    if (resolvedPublishPackage.blockedResult case final blockedResult?) {
      return blockedResult;
    }
    try {
      final response = await hostedClient.preparePublish(
        workspaceId: workspaceId,
        packageName: resolvedPublishPackage.packageName,
        outputPath: outputPath,
      );
      return _deploymentResultFromHostedResponse(
        command: 'publish',
        response: response,
      );
    } catch (error) {
      return DeploymentCommandResult(
        command: 'publish',
        status: DeploymentCommandStatus.failed,
        statusMessage: 'Hosted publish preflight failed: $error',
        stdout: '',
        stderr: '',
      );
    }
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
    final resolvedPublishPackage = _resolvePublishPackage(
      projectGraph: projectGraph,
      explicitPackageName: packageName,
    );
    if (resolvedPublishPackage.blockedResult case final blockedResult?) {
      return blockedResult;
    }
    try {
      final response = await hostedClient.publishToRegistry(
        workspaceId: workspaceId,
        registryRoot: registryRoot,
        packageName: resolvedPublishPackage.packageName,
        outputPath: outputPath,
      );
      return _deploymentResultFromHostedResponse(
        command: 'publish',
        response: response,
      );
    } catch (error) {
      return DeploymentCommandResult(
        command: 'publish',
        status: DeploymentCommandStatus.failed,
        statusMessage: 'Hosted publish failed: $error',
        stdout: '',
        stderr: '',
      );
    }
  }
}

class _LocalCliDeploymentAdapter implements DeploymentAdapter {
  const _LocalCliDeploymentAdapter({required this.platformTarget});

  final PlatformTarget platformTarget;

  @override
  Future<DeploymentCommandResult> packProject({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) {
    return _runDeploymentCommand(
      projectGraph: projectGraph,
      command: 'pack',
      args: <String>[
        '--json',
        'pack',
        ..._manifestArgs(projectGraph),
        if (packageName != null && packageName.isNotEmpty) ...<String>[
          '--package',
          packageName,
        ],
        if (outputPath != null && outputPath.isNotEmpty) ...<String>[
          '--output',
          outputPath,
        ],
      ],
    );
  }

  @override
  Future<DeploymentCommandResult> preparePublish({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) {
    final resolvedPublishPackage = _resolvePublishPackage(
      projectGraph: projectGraph,
      explicitPackageName: packageName,
    );
    if (resolvedPublishPackage.blockedResult case final blockedResult?) {
      return Future<DeploymentCommandResult>.value(blockedResult);
    }
    return _runDeploymentCommand(
      projectGraph: projectGraph,
      command: 'publish',
      args: <String>[
        '--json',
        'publish',
        ..._manifestArgs(projectGraph),
        if (resolvedPublishPackage.packageName
            case final resolvedPackageName?) ...<String>[
          '--package',
          resolvedPackageName,
        ],
        if (outputPath != null && outputPath.isNotEmpty) ...<String>[
          '--output',
          outputPath,
        ],
        '--dry-run',
      ],
    );
  }

  @override
  Future<DeploymentCommandResult> publishToRegistry({
    required ProjectGraphSnapshot projectGraph,
    required String registryRoot,
    String? packageName,
    String? outputPath,
  }) {
    final resolvedPublishPackage = _resolvePublishPackage(
      projectGraph: projectGraph,
      explicitPackageName: packageName,
    );
    if (resolvedPublishPackage.blockedResult case final blockedResult?) {
      return Future<DeploymentCommandResult>.value(blockedResult);
    }
    return _runDeploymentCommand(
      projectGraph: projectGraph,
      command: 'publish',
      args: <String>[
        '--json',
        'publish',
        ..._manifestArgs(projectGraph),
        if (resolvedPublishPackage.packageName
            case final resolvedPackageName?) ...<String>[
          '--package',
          resolvedPackageName,
        ],
        if (outputPath != null && outputPath.isNotEmpty) ...<String>[
          '--output',
          outputPath,
        ],
        '--registry',
        registryRoot,
      ],
    );
  }

  Future<DeploymentCommandResult> _runDeploymentCommand({
    required ProjectGraphSnapshot projectGraph,
    required String command,
    required List<String> args,
  }) async {
    if (platformTarget == PlatformTarget.ios ||
        platformTarget == PlatformTarget.web) {
      return blockedSpioCommandResult(
        factory: _deploymentCommandResult,
        command: command,
        statusMessage:
            '${platformTarget.label} does not expose local spio deployment commands.',
      );
    }

    final manifestPath = projectGraph.manifestPath;
    if (manifestPath == null || manifestPath.isEmpty) {
      return blockedSpioCommandResult(
        factory: _deploymentCommandResult,
        command: command,
        statusMessage:
            'Deployment commands require a resolved spio manifest path.',
      );
    }

    return runLocalSpioCommand(
      projectGraph: projectGraph,
      command: command,
      args: args,
      factory: _deploymentCommandResult,
    );
  }
}

class _ResolvedPublishPackage {
  const _ResolvedPublishPackage({this.packageName, this.blockedResult});

  final String? packageName;
  final DeploymentCommandResult? blockedResult;
}

_ResolvedPublishPackage _resolvePublishPackage({
  required ProjectGraphSnapshot projectGraph,
  required String? explicitPackageName,
}) {
  if (explicitPackageName != null && explicitPackageName.isNotEmpty) {
    return _ResolvedPublishPackage(packageName: explicitPackageName);
  }

  final distribution = projectGraph.packageDistribution;
  if (distribution == null || distribution.packages.isEmpty) {
    return const _ResolvedPublishPackage();
  }

  final publishablePackages = distribution.packages
      .where((package) => package.publishReady)
      .toList(growable: false);
  if (publishablePackages.length == 1) {
    return _ResolvedPublishPackage(
      packageName: publishablePackages.single.packageName,
    );
  }
  if (publishablePackages.isEmpty) {
    final blockedPackages = distribution.packages
        .where((package) => !package.publishReady)
        .toList(growable: false);
    final headline = blockedPackages.isEmpty
        ? 'No publish-ready package is available for deployment.'
        : 'No publish-ready package is available: ${blockedPackages.map((package) => package.packageName).join(', ')}.';
    final details = blockedPackages
        .take(2)
        .expand((package) {
          if (package.blockingReasons.isEmpty) {
            return <String>[];
          }
          return <String>[
            '${package.packageName}: ${package.blockingReasons.join(' | ')}',
          ];
        })
        .join(' ');
    return _ResolvedPublishPackage(
      blockedResult: DeploymentCommandResult(
        command: 'publish',
        status: DeploymentCommandStatus.blocked,
        statusMessage: details.isEmpty ? headline : '$headline $details',
        stdout: '',
        stderr: '',
      ),
    );
  }

  return _ResolvedPublishPackage(
    blockedResult: DeploymentCommandResult(
      command: 'publish',
      status: DeploymentCommandStatus.blocked,
      statusMessage:
          'Multiple publish-ready packages are available. Select a package before publish: ${publishablePackages.map((package) => package.packageName).join(', ')}.',
      stdout: '',
      stderr: '',
    ),
  );
}

List<String> _manifestArgs(ProjectGraphSnapshot projectGraph) {
  final manifestPath = projectGraph.manifestPath;
  if (manifestPath == null || manifestPath.isEmpty) {
    return const <String>[];
  }
  return spioManifestArgs(projectGraph);
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

DeploymentCommandResult _deploymentCommandResult({
  required LocalSpioCommandOutcome outcome,
  required String command,
  required String statusMessage,
  required String stdout,
  required String stderr,
  Map<String, dynamic>? payload,
  Map<String, dynamic>? errorPayload,
}) {
  return DeploymentCommandResult(
    command: command,
    status: switch (outcome) {
      LocalSpioCommandOutcome.blocked => DeploymentCommandStatus.blocked,
      LocalSpioCommandOutcome.succeeded => DeploymentCommandStatus.succeeded,
      LocalSpioCommandOutcome.failed => DeploymentCommandStatus.failed,
    },
    statusMessage: statusMessage,
    stdout: stdout,
    stderr: stderr,
    payload: payload,
    errorPayload: errorPayload,
  );
}
