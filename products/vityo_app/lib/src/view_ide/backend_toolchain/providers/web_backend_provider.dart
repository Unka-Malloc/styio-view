import '../../platform/platform_target.dart';
import '../backend_provider.dart';
import '../dependency_source_adapter.dart';
import '../dependency_source_adapter_web.dart';
import '../deployment_adapter.dart';
import '../deployment_adapter_web.dart';
import '../execution_adapter.dart';
import '../execution_adapter_web.dart';
import '../project_graph_adapter.dart';
import '../project_graph_adapter_web.dart';
import '../project_graph_contract.dart';
import '../runtime_event_adapter.dart';
import '../toolchain_management_adapter.dart';
import '../toolchain_management_adapter_web.dart';

final class WebBackendProvider implements BackendProvider {
  const WebBackendProvider();

  @override
  String get id => 'web.hosted';

  @override
  int get priority => 0;

  @override
  Set<PlatformTarget> get supportedPlatforms => const <PlatformTarget>{
    PlatformTarget.web,
  };

  @override
  Future<ProjectGraphAdapter> createProjectGraphAdapter() {
    return createPlatformProjectGraphAdapter(
      platformTarget: PlatformTarget.web,
    );
  }

  @override
  Future<ExecutionAdapter> createExecutionAdapter(
    ProjectGraphSnapshot projectGraph,
  ) {
    return createPlatformExecutionAdapter(
      platformTarget: PlatformTarget.web,
      projectGraph: projectGraph,
    );
  }

  @override
  RuntimeEventAdapter createRuntimeEventAdapter() {
    return createRuntimeEventAdapterForPlatform(
      platformTarget: PlatformTarget.web,
    );
  }

  @override
  Future<DependencySourceAdapter> createDependencySourceAdapter() {
    return createPlatformDependencySourceAdapter(
      platformTarget: PlatformTarget.web,
    );
  }

  @override
  Future<DeploymentAdapter> createDeploymentAdapter() {
    return createPlatformDeploymentAdapter(platformTarget: PlatformTarget.web);
  }

  @override
  Future<ToolchainManagementAdapter> createToolchainManagementAdapter() {
    return createPlatformToolchainManagementAdapter(
      platformTarget: PlatformTarget.web,
    );
  }
}
