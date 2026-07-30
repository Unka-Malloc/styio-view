// ignore_for_file: annotate_overrides

part of '../shell_runtime_model.dart';

/// Public project graph, execution, tool, dependency, and deployment facade.
mixin ShellRuntimeProjectRuntimeFacade on ShellRuntimeFacadeHost {
  TestingSessionController? get testingSessionController =>
      _testingController.sessionController;
  List<AdapterCapabilitySnapshot> get adapterCapabilities =>
      _projectGraphController.capabilities;
  ModuleRegistry get moduleRegistry => _moduleController.registry;
  NativeModuleLoader get nativeModuleLoader =>
      _moduleController.nativeModuleLoader;
  List<ModuleDefinition> get mountedModules => _moduleController.mountedModules;
  List<ModuleDefinition> get visibleModules => _moduleController.visibleModules;

  List<NativeToolResultRecord> get nativeToolResults =>
      _executionController.nativeToolResults;
  NativeToolResultRecord? get lastNativeToolResult =>
      _executionController.lastNativeToolResult;
  ExecutionAdapter get executionAdapter =>
      _executionController.executionAdapter;
  RuntimeEventAdapter get runtimeEventAdapter =>
      _executionController.runtimeEventAdapter;
  ExecutionSession? get lastExecutionSession =>
      _executionController.lastExecutionSession;
  List<RuntimeEventEnvelope> get lastRuntimeEvents =>
      _executionController.lastRuntimeEvents;

  DependencySourceCommandResult? get lastDependencySourceCommand =>
      _dependencySourceController.lastCommand;
  DeploymentCommandResult? get lastDeploymentCommand =>
      _deploymentController.lastCommand;

  bool openFirstNativeToolDiagnostic(AppCommandId commandId) =>
      _nativeToolRuntimeController.openFirstDiagnostic(commandId);

  Future<ClangCppVersionSelection?> _loadClangCppSelection(
    ToolchainManager manager,
  ) async {
    final snapshot =
        toolchainStatusReport?.value.snapshot ?? await manager.snapshot();
    return ClangCppVersionManager.fromSnapshot(
      snapshot,
      preference: _toolchainController.clangCppVersionPreference,
    ).select();
  }

  Future<void> refreshProjectGraph({String? reason}) =>
      _projectGraphController.refresh(reason: reason);

  Future<DeploymentCommandResult> packProject({
    String? packageName,
    String? outputPath,
  }) => _deploymentController.packProject(
    packageName: packageName,
    outputPath: outputPath,
  );

  Future<DeploymentCommandResult> preparePublish({
    String? packageName,
    String? outputPath,
  }) => _deploymentController.preparePublish(
    packageName: packageName,
    outputPath: outputPath,
  );

  Future<DeploymentCommandResult> publishToRegistry({
    required String registryRoot,
    String? packageName,
    String? outputPath,
  }) => _deploymentController.publishToRegistry(
    registryRoot: registryRoot,
    packageName: packageName,
    outputPath: outputPath,
  );

  Future<DependencySourceCommandResult> syncDependencies({
    bool locked = false,
    bool offline = false,
  }) => _dependencySourceController.syncDependencies(
    locked: locked,
    offline: offline,
  );

  Future<DependencySourceCommandResult> vendorDependencies({
    String? outputPath,
    bool locked = false,
    bool offline = false,
  }) => _dependencySourceController.vendorDependencies(
    outputPath: outputPath,
    locked: locked,
    offline: offline,
  );
}
