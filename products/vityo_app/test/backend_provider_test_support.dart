import 'package:vityo_app/src/view_ide/backend_toolchain/backend_provider.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/default_backend_providers.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/dependency_source_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/deployment_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/runtime_event_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/toolchain_management_adapter.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';

BackendProvider backendProviderFor(PlatformTarget platformTarget) {
  return createDefaultBackendProviderRegistry().resolve(platformTarget);
}

Future<ProjectGraphAdapter> createProjectGraphAdapter({
  required PlatformTarget platformTarget,
}) {
  return backendProviderFor(platformTarget).createProjectGraphAdapter();
}

Future<ExecutionAdapter> createExecutionAdapter({
  required PlatformTarget platformTarget,
  required ProjectGraphSnapshot projectGraph,
}) {
  return backendProviderFor(
    platformTarget,
  ).createExecutionAdapter(projectGraph);
}

RuntimeEventAdapter createRuntimeEventAdapter({
  required PlatformTarget platformTarget,
}) {
  return backendProviderFor(platformTarget).createRuntimeEventAdapter();
}

Future<DependencySourceAdapter> createDependencySourceAdapter({
  required PlatformTarget platformTarget,
}) {
  return backendProviderFor(platformTarget).createDependencySourceAdapter();
}

Future<DeploymentAdapter> createDeploymentAdapter({
  required PlatformTarget platformTarget,
}) {
  return backendProviderFor(platformTarget).createDeploymentAdapter();
}

Future<ToolchainManagementAdapter> createToolchainManagementAdapter({
  required PlatformTarget platformTarget,
}) {
  return backendProviderFor(platformTarget).createToolchainManagementAdapter();
}
