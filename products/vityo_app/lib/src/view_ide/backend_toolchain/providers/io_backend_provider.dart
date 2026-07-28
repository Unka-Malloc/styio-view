import '../../platform/platform_target.dart';
import '../backend_provider.dart';
import '../dependency_source_adapter.dart';
import '../dependency_source_adapter_io.dart';
import '../deployment_adapter.dart';
import '../deployment_adapter_io.dart';
import '../execution_adapter.dart';
import '../execution_adapter_io.dart';
import '../project_graph_adapter.dart';
import '../project_graph_adapter_io.dart';
import '../project_graph_contract.dart';
import '../runtime_event_adapter.dart';
import '../toolchain_management_adapter.dart';
import '../toolchain_management_adapter_io.dart';

abstract class IoBackendProvider implements BackendProvider {
  const IoBackendProvider({
    required this.id,
    required this.platformTarget,
    this.priority = 0,
  });

  @override
  final String id;

  final PlatformTarget platformTarget;

  @override
  final int priority;

  @override
  Set<PlatformTarget> get supportedPlatforms => <PlatformTarget>{
    platformTarget,
  };

  @override
  Future<ProjectGraphAdapter> createProjectGraphAdapter() {
    return createPlatformProjectGraphAdapter(platformTarget: platformTarget);
  }

  @override
  Future<ExecutionAdapter> createExecutionAdapter(
    ProjectGraphSnapshot projectGraph,
  ) {
    return createPlatformExecutionAdapter(
      platformTarget: platformTarget,
      projectGraph: projectGraph,
    );
  }

  @override
  RuntimeEventAdapter createRuntimeEventAdapter() {
    return createRuntimeEventAdapterForPlatform(platformTarget: platformTarget);
  }

  @override
  Future<DependencySourceAdapter> createDependencySourceAdapter() {
    return createPlatformDependencySourceAdapter(
      platformTarget: platformTarget,
    );
  }

  @override
  Future<DeploymentAdapter> createDeploymentAdapter() {
    return createPlatformDeploymentAdapter(platformTarget: platformTarget);
  }

  @override
  Future<ToolchainManagementAdapter> createToolchainManagementAdapter() {
    return createPlatformToolchainManagementAdapter(
      platformTarget: platformTarget,
    );
  }
}
