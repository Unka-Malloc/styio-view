import '../../backend_toolchain/dependency_source_adapter.dart';
import '../../backend_toolchain/project_graph_contract.dart';
import '../../commands/commands.dart';
import '../../platform/platform_target.dart';

/// Owns platform and project-fact policy for backend-mutating commands.
final class BackendCommandPolicyController {
  const BackendCommandPolicyController({required this.platformTarget});

  final PlatformTarget platformTarget;

  String? blockedReason({
    required AppCommandId commandId,
    required ProjectGraphSnapshot projectGraph,
  }) {
    switch (commandId) {
      case AppCommandId.fetchDependencies:
        return blockedDependencySourceCommandReason(
          platformTarget: platformTarget,
          projectGraph: projectGraph,
          command: 'fetch',
        );
      case AppCommandId.vendorDependencies:
        return blockedDependencySourceCommandReason(
          platformTarget: platformTarget,
          projectGraph: projectGraph,
          command: 'vendor',
        );
      case AppCommandId.useActiveCompiler:
        return blockedToolchainReason(
          projectGraph: projectGraph,
          requiresResolvedCompiler: true,
        );
      case AppCommandId.pinActiveCompiler:
        return blockedToolchainReason(
          projectGraph: projectGraph,
          requiresResolvedCompiler: true,
          requiresManifest: true,
        );
      case AppCommandId.clearPinnedCompiler:
        return blockedToolchainReason(
          projectGraph: projectGraph,
          requiresManifest: true,
          requiresPin: true,
        );
      case AppCommandId.packProject:
        return blockedDeploymentReason(projectGraph: projectGraph);
      case AppCommandId.preparePublish:
        return blockedDeploymentReason(
          projectGraph: projectGraph,
          requireResolvedPublishTarget: true,
        );
      default:
        return null;
    }
  }

  String? blockedToolchainReason({
    required ProjectGraphSnapshot projectGraph,
    bool requiresResolvedCompiler = false,
    bool requiresManifest = false,
    bool requiresPin = false,
  }) {
    if (_requiresHostedBackend(projectGraph)) {
      return '${platformTarget.label} does not expose local pafio toolchain management.';
    }
    if (requiresResolvedCompiler && projectGraph.activeCompiler == null) {
      return 'No active compiler handshake is currently resolved for this project.';
    }
    if (requiresManifest && !projectGraph.hasManifest) {
      return 'Project toolchain commands require a resolved pafio manifest path.';
    }
    if (requiresPin && projectGraph.toolchainPinPath == null) {
      return 'No project toolchain pin is currently resolved.';
    }
    return null;
  }

  String? blockedDeploymentReason({
    required ProjectGraphSnapshot projectGraph,
    bool requireResolvedPublishTarget = false,
  }) {
    if (_requiresHostedBackend(projectGraph)) {
      return '${platformTarget.label} does not expose local pafio deployment commands.';
    }
    if (!projectGraph.hasManifest) {
      return 'Deployment commands require a resolved pafio manifest path.';
    }
    if (!requireResolvedPublishTarget) return null;
    final packages = projectGraph.packageDistribution?.packages;
    if (packages == null || packages.isEmpty) return null;
    final publishable = packages
        .where((package) => package.publishReady)
        .toList(growable: false);
    if (publishable.length == 1) return null;
    if (publishable.isNotEmpty) {
      return 'Multiple publish-ready packages are available. Select a package before publish: '
          '${publishable.map((package) => package.packageName).join(', ')}.';
    }
    final blocked = packages
        .where((package) => !package.publishReady)
        .toList(growable: false);
    if (blocked.isEmpty) {
      return 'No publish-ready package is available for deployment.';
    }
    final headline =
        'No publish-ready package is available: '
        '${blocked.map((package) => package.packageName).join(', ')}.';
    final details = blocked
        .take(2)
        .where((package) => package.blockingReasons.isNotEmpty)
        .map(
          (package) =>
              '${package.packageName}: ${package.blockingReasons.join(' | ')}',
        )
        .join(' ');
    return details.isEmpty ? headline : '$headline $details';
  }

  bool _requiresHostedBackend(ProjectGraphSnapshot projectGraph) {
    return (platformTarget == PlatformTarget.ios ||
            platformTarget == PlatformTarget.web) &&
        !projectGraph.hasHostedWorkspace;
  }
}
