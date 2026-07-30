// ignore_for_file: unused_element

part of '../shell_runtime_model.dart';

/// Typed inheritance surface required by the stateless domain facade mixins.
abstract class ShellRuntimeFacadeHost extends ChangeNotifier {
  PlatformTarget get platformTarget;
  WorkspaceController get workspaceController;
  dynamic get workspaceDocumentStore;
  EditorSessionController get editorController;
  dynamic get toolchainManager;
  AgentClientRegistry? get agentClientRegistry;
  AgentCollaborationService? get agentCollaboration;
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
  dynamic get _ownsRuntimeOutputBuffer;

  String get _activeDocumentPath;
  List<DocumentState> get _workspaceDocumentSamples;

  void appendLog(String message);
  void _notifyShellListeners();
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
