import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:styio_ide/src/view_ide/commands/commands.dart';
import 'package:styio_ide/src/view_ide/platform/platform_target.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/backend_command_policy_controller.dart';

void main() {
  test('mobile and web local backend mutations fail closed', () {
    final graph = _graph(manifestPath: '/workspace/pafio.toml');
    const policy = BackendCommandPolicyController(
      platformTarget: PlatformTarget.ios,
    );

    expect(
      policy.blockedToolchainReason(projectGraph: graph),
      contains('local pafio'),
    );
    expect(
      policy.blockedDeploymentReason(projectGraph: graph),
      contains('local pafio'),
    );
  });

  test('desktop toolchain policy requires declared facts', () {
    const policy = BackendCommandPolicyController(
      platformTarget: PlatformTarget.windows,
    );
    final graph = _graph();

    expect(
      policy.blockedToolchainReason(
        projectGraph: graph,
        requiresResolvedCompiler: true,
      ),
      contains('compiler handshake'),
    );
    expect(
      policy.blockedToolchainReason(
        projectGraph: graph,
        requiresManifest: true,
      ),
      contains('manifest'),
    );
  });

  test('publish policy reports ambiguity and blocking reasons', () {
    const policy = BackendCommandPolicyController(
      platformTarget: PlatformTarget.linux,
    );
    final ambiguous = _graph(
      manifestPath: '/workspace/pafio.toml',
      distribution: _distribution(<PackageDistributionPackageSnapshot>[
        _package('a', ready: true),
        _package('b', ready: true),
      ]),
    );
    final blocked = _graph(
      manifestPath: '/workspace/pafio.toml',
      distribution: _distribution(<PackageDistributionPackageSnapshot>[
        _package('a', ready: false, reasons: const <String>['path dependency']),
      ]),
    );

    expect(
      policy.blockedDeploymentReason(
        projectGraph: ambiguous,
        requireResolvedPublishTarget: true,
      ),
      contains('Multiple publish-ready packages'),
    );
    expect(
      policy.blockedDeploymentReason(
        projectGraph: blocked,
        requireResolvedPublishTarget: true,
      ),
      contains('path dependency'),
    );
  });

  test('command mapping applies backend policy only to mutating routes', () {
    const policy = BackendCommandPolicyController(
      platformTarget: PlatformTarget.windows,
    );
    final graph = _graph();

    expect(
      policy.blockedReason(
        commandId: AppCommandId.pinActiveCompiler,
        projectGraph: graph,
      ),
      contains('compiler handshake'),
    );
    expect(
      policy.blockedReason(
        commandId: AppCommandId.refreshWorkspaceDiagnostics,
        projectGraph: graph,
      ),
      isNull,
    );
  });
}

ProjectGraphSnapshot _graph({
  String? manifestPath,
  PackageDistributionSnapshot? distribution,
}) => ProjectGraphSnapshot(
  id: manifestPath ?? 'scratch',
  title: 'fixture',
  kind: manifestPath == null ? ProjectKind.scratch : ProjectKind.package,
  workspaceRoot: '/workspace',
  workspaceMembers: const <String>[],
  manifestPath: manifestPath,
  packages: const <ProjectPackageSnapshot>[],
  dependencies: const <ProjectDependencySnapshot>[],
  targets: const <ProjectTargetDescriptor>[],
  editorFiles: const <String>[],
  toolchain: const ToolchainStatusSnapshot(
    source: ToolchainResolutionSource.unavailable,
    detail: 'fixture',
  ),
  lockState: ProjectLockState.unknown,
  vendorState: ProjectVendorState.missing,
  packageDistribution: distribution,
  notes: const <String>[],
);

PackageDistributionPackageSnapshot _package(
  String name, {
  required bool ready,
  List<String> reasons = const <String>[],
}) => PackageDistributionPackageSnapshot(
  packageName: name,
  manifestPath: '/workspace/$name/pafio.toml',
  publishEnabled: true,
  publishReady: ready,
  blockingReasons: reasons,
  runtimeRegistryDependencies: 0,
  runtimePathDependencies: 0,
  runtimeGitDependencies: 0,
  devRegistryDependencies: 0,
  devPathDependencies: 0,
  devGitDependencies: 0,
);

PackageDistributionSnapshot _distribution(
  List<PackageDistributionPackageSnapshot> packages,
) => PackageDistributionSnapshot(
  schemaVersion: 1,
  packages: packages,
  registrySources: const <RegistrySourceSnapshot>[],
  publishablePackages: packages.where((package) => package.publishReady).length,
  blockedPackages: packages.where((package) => !package.publishReady).length,
);
