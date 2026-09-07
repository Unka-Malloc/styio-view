import 'package:vityo_app/src/view_ide/backend_toolchain/backend_provider.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/default_backend_providers.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/dependency_source_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/deployment_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/runtime_event_adapter.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';

import 'support/vityod_test_harness.dart';

VityodTestHarness? _backendHarness;
PlatformManagerBundle? _backendPlatformManagers;

Future<void> startBackendProviderTestServices() async {
  if (!VityodTestHarness.isSupported || _backendHarness != null) return;
  _backendHarness = await VityodTestHarness.start(
    clientId: 'backend-provider-tests',
  );
  _backendPlatformManagers = await createDetectedPlatformManagerBundle(
    vityodClient: _backendHarness!.client,
  );
}

Future<void> stopBackendProviderTestServices() async {
  final harness = _backendHarness;
  _backendHarness = null;
  _backendPlatformManagers = null;
  await harness?.close();
}

BackendProvider backendProviderFor(PlatformTarget platformTarget) {
  return createDefaultBackendProviderRegistry().resolve(platformTarget);
}

Future<ProjectGraphAdapter> createProjectGraphAdapter({
  required PlatformTarget platformTarget,
  String? workspaceRoot,
}) async {
  final harness = _backendHarness;
  final managers = harness == null || workspaceRoot == null
      ? _backendPlatformManagers
      : await createDetectedPlatformManagerBundle(
          vityodClient: harness.client,
          workspaceRoot: workspaceRoot,
        );
  return backendProviderFor(
    platformTarget,
  ).createProjectGraphAdapter(platformManagers: managers);
}

Future<ExecutionAdapter> createExecutionAdapter({
  required PlatformTarget platformTarget,
  required ProjectGraphSnapshot projectGraph,
}) async {
  final harness = _backendHarness;
  final managers = harness == null
      ? _backendPlatformManagers
      : await createDetectedPlatformManagerBundle(
          vityodClient: harness.client,
          workspaceRoot: projectGraph.workspaceRoot,
        );
  return backendProviderFor(
    platformTarget,
  ).createExecutionAdapter(projectGraph, platformManagers: managers);
}

RuntimeEventAdapter createRuntimeEventAdapter({
  required PlatformTarget platformTarget,
}) {
  return backendProviderFor(platformTarget).createRuntimeEventAdapter();
}

Future<DependencySourceAdapter> createDependencySourceAdapter({
  required PlatformTarget platformTarget,
}) {
  return backendProviderFor(
    platformTarget,
  ).createDependencySourceAdapter(platformManagers: _backendPlatformManagers);
}

Future<DeploymentAdapter> createDeploymentAdapter({
  required PlatformTarget platformTarget,
}) {
  return backendProviderFor(
    platformTarget,
  ).createDeploymentAdapter(platformManagers: _backendPlatformManagers);
}
