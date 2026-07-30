// ignore_for_file: unused_element

part of '../shell_runtime_model.dart';

/// Typed inheritance surface required by the stateless domain facade mixins.
abstract class ShellRuntimeFacadeHost extends ChangeNotifier {
  PlatformTarget get platformTarget;
  WorkspaceController get workspaceController;
  dynamic get workspaceDocumentStore;
  EditorSessionController get editorController;
  dynamic get toolchainManager;
  dynamic get agentCodingController;
  dynamic get agentExtensionToolExecutionRegistry;
  dynamic get agentProviderConfigurator;
  dynamic get languageServiceStatus;
  dynamic get toolchainStatusReport;
  dynamic get projectLanguageService;
  dynamic get runtimeOutputBuffer;

  dynamic get _editorWorkspaceStateController;
  dynamic get _editorNavigationCommandController;
  dynamic get _editorQuickFixCommandController;
  WorkspaceDocumentController get _workspaceDocumentController;
  dynamic get _workspacePersistenceController;
  dynamic get _workspaceFileCommandController;
  dynamic get _workspaceFileConfirmationController;
  dynamic get _workspaceDiagnosticsRuntimeController;
  dynamic get _workspaceReplaceController;
  dynamic get _workspaceNavigationController;
  dynamic get _projectLanguageContextController;
  dynamic get _workspaceRenameController;
  dynamic get _workspaceQuickFixController;
  dynamic get _workspaceSearchController;
  dynamic get _settingsController;
  dynamic get _executionController;
  dynamic get _projectGraphController;
  dynamic get _deploymentController;
  dynamic get _dependencySourceController;
  dynamic get _languageController;
  dynamic get _languageRefreshCommandController;
  dynamic get _shellInputCommandController;
  dynamic get _shellCommandFallbackController;
  dynamic get _moduleController;
  dynamic get _nativeToolRuntimeController;
  dynamic get _debugController;
  dynamic get _agentController;
  dynamic get _agentCommandReceiptController;
  dynamic get _agentQuickFixCommandController;
  dynamic get _agentDebugCommandController;
  dynamic get _agentContextCommandController;
  dynamic get _agentExecutionCommandController;
  dynamic get _agentRefactorCommandController;
  dynamic get _agentProjectLifecycleCommandController;
  dynamic get _agentNativeToolCommandController;
  dynamic get _agentPatchLifecycleController;
  dynamic get _agentProviderConfigurationController;
  dynamic get _agentProviderRecoveryCommandController;
  dynamic get _agentSourceControlCommandController;
  dynamic get _agentSurfaceCommandController;
  dynamic get _agentTestingCommandController;
  dynamic get _agentToolchainCommandController;
  dynamic get _agentSessionContextController;
  dynamic get _agentWorkspaceCommandController;
  dynamic get _agentWorkspaceReplaceCommandController;
  dynamic get _backendCommandPolicyController;
  dynamic get _sourceControlController;
  dynamic get _testingController;
  dynamic get _semanticTelemetryController;
  dynamic get _toolchainController;
  dynamic get _editorFileBinding;
  StreamSubscription<DocumentResourceBindingSnapshot>?
  get _editorFileBindingSubscription;
  set _editorFileBindingSubscription(
    StreamSubscription<DocumentResourceBindingSnapshot>? value,
  );
  dynamic get _ownsLanguageServiceStatus;
  dynamic get _ownsAgentCodingController;
  dynamic get _ownsRuntimeOutputBuffer;

  String get _activeDocumentPath;
  AgentCommandResultContext? get _lastAgentIdeCommandResult;
  AgentPromptProfileManifest get _agentProviderProfileManifest;
  List<DocumentState> get _agentWorkspaceDocumentSamples;

  void appendLog(String message);
  void _notifyShellListeners();
  void _recordAgentIdeCommandResult(
    AgentIdeCommandSuggestion suggestion, {
    required bool applied,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  });
  bool _blockAgentDiskBackedCommandWhenDirty(
    AgentIdeCommandSuggestion suggestion,
  );
  String _workspaceDiagnosticsRefreshMessage(
    WorkspaceDiagnosticsSnapshot snapshot,
  );
  Future<WorkspaceDiagnosticsSnapshot> refreshWorkspaceDiagnostics();
  Future<WorkspaceSaveAllResult> saveAllWorkspaceFileChanges();
  Future<SemanticSnapshotPanelEventState> recordSemanticPanelEvent(
    SemanticSnapshotPanelEvent event, {
    String? workspaceId,
    int? maxEvents,
  });
  List<AdapterCapabilitySnapshot> get adapterCapabilities;
  Future<DeploymentCommandResult> packProject({
    String? packageName,
    String? outputPath,
  });
  Future<DeploymentCommandResult> preparePublish({
    String? packageName,
    String? outputPath,
  });
  Future<DependencySourceCommandResult> syncDependencies({
    bool locked = false,
    bool offline = false,
  });
  Future<DependencySourceCommandResult> vendorDependencies({
    String? outputPath,
    bool locked = false,
    bool offline = false,
  });
  DebugCommandResult toggleBreakpointAtSelection();
  Future<DebugCommandResult> startDebugging();
  Future<DebugCommandResult> stopDebugging();
  Future<DebugCommandResult> continueDebugging();
  Future<DebugCommandResult> stepOver();
  DocumentResourceBindingSnapshot acceptEditorExternalChange();
}
