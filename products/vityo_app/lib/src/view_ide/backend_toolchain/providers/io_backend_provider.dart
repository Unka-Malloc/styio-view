import '../../platform/platform_target.dart';
import '../../environment/system_compatibility/platform_manager/platform_manager.dart';
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
  Future<ProjectGraphAdapter> createProjectGraphAdapter({
    PlatformManagerBundle? platformManagers,
  }) {
    return createPlatformProjectGraphAdapter(
      platformTarget: platformTarget,
      platformManagers: platformManagers,
    );
  }

  @override
  Future<ExecutionAdapter> createExecutionAdapter(
    ProjectGraphSnapshot projectGraph, {
    PlatformManagerBundle? platformManagers,
  }) {
    return createPlatformExecutionAdapter(
      platformTarget: platformTarget,
      projectGraph: projectGraph,
      platformManagers: platformManagers,
    );
  }

  @override
  RuntimeEventAdapter createRuntimeEventAdapter() {
    return createRuntimeEventAdapterForPlatform(platformTarget: platformTarget);
  }

  @override
  Future<DependencySourceAdapter> createDependencySourceAdapter({
    PlatformManagerBundle? platformManagers,
  }) {
    return createPlatformDependencySourceAdapter(
      platformTarget: platformTarget,
      platformManagers: platformManagers,
    );
  }

  @override
  Future<DeploymentAdapter> createDeploymentAdapter({
    PlatformManagerBundle? platformManagers,
  }) {
    return createPlatformDeploymentAdapter(
      platformTarget: platformTarget,
      platformManagers: platformManagers,
    );
  }
}
