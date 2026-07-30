// ignore_for_file: annotate_overrides

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend_toolchain/backend_toolchain.dart';
import '../commands/commands.dart';
import '../debugger/debug_adapter_launcher.dart';
import '../debugger/debug_launch_telemetry_store.dart';
import '../debugger/debug_runtime_task_history.dart';
import '../../ide/editor/editor.dart' hide WorkspaceEditSource;
import '../environment/configuration/configuration.dart';
import '../interaction/interaction.dart';
import '../language/language_contract.dart';
import '../language/service/semantic_snapshot_event_bridge.dart';
import '../language/service/service.dart';
import '../module_host/module_host.dart';
import '../platform/platform.dart';
import '../runtime/runtime.dart' hide DebugSessionSnapshot, DebugSessionStatus;
import '../toolchain/clang_cpp_version_configuration.dart';
import '../toolchain/clang_cpp_version_manager.dart';
import '../toolchain/toolchain_catalog.dart';
import '../toolchain/toolchain_install_executor.dart'
    hide ToolchainRecoveryAction;
import '../toolchain/toolchain_install_policy.dart';
import '../toolchain/toolchain_manager.dart';
import '../testing/testing.dart';
import '../../ide/workspace/workspace.dart';
import '../../ide/agent_client/agent_client.dart';
import '../../ide/workbench/agent_collaboration/agent_collaboration_service.dart';
import 'controllers/backend_command_policy_controller.dart';
import 'controllers/deployment_controller.dart';
import 'controllers/dependency_source_controller.dart';
import 'controllers/execution_controller.dart';
import 'controllers/editor_workspace_state_controller.dart';
import 'controllers/editor_navigation_command_controller.dart';
import 'controllers/editor_quick_fix_command_controller.dart';
import 'controllers/debug_controller.dart';
import 'controllers/language_controller.dart';
import 'controllers/language_refresh_command_controller.dart';
import 'controllers/module_controller.dart';
import 'controllers/native_tool_runtime_controller.dart';
import 'controllers/project_graph_controller.dart';
import 'controllers/project_language_context_controller.dart';
import 'controllers/settings_controller.dart';
import 'controllers/shell_input_command_controller.dart';
import 'controllers/shell_command_fallback_controller.dart';
import 'controllers/semantic_telemetry_controller.dart';
import 'controllers/source_control_controller.dart';
import 'controllers/testing_controller.dart';
import 'controllers/toolchain_controller.dart';
import 'controllers/workspace_document_controller.dart';
import 'controllers/workspace_diagnostics_runtime_controller.dart';
import 'controllers/workspace_file_command_controller.dart';
import 'controllers/workspace_file_confirmation_controller.dart';
import 'controllers/workspace_navigation_controller.dart';
import 'controllers/workspace_persistence_controller.dart';
import 'controllers/workspace_quick_fix_controller.dart';
import 'controllers/workspace_rename_controller.dart';
import 'controllers/workspace_replace_controller.dart';
import 'controllers/workspace_search_controller.dart';
import 'workspace_file_lifecycle.dart';

part 'facades/source_control_facade.dart';
part 'facades/facade_host.dart';
part 'facades/testing_facade.dart';
part 'facades/debug_facade.dart';
part 'facades/command_dispatch_facade.dart';
part 'facades/language_facade.dart';
part 'facades/project_runtime_facade.dart';
part 'facades/shell_lifecycle_facade.dart';
part 'facades/toolchain_facade.dart';
part 'facades/settings_facade.dart';
part 'facades/semantic_telemetry_facade.dart';
part 'facades/workspace_document_facade.dart';
part 'facades/workspace_intelligence_facade.dart';

class ShellRuntimeModel extends ShellRuntimeFacadeHost
    with
        ShellRuntimeSourceControlFacade,
        ShellRuntimeTestingFacade,
        ShellRuntimeDebugFacade,
        ShellRuntimeLanguageFacade,
        ShellRuntimeProjectRuntimeFacade,
        ShellRuntimeToolchainFacade,
        ShellRuntimeSettingsFacade,
        ShellRuntimeSemanticTelemetryFacade,
        ShellRuntimeWorkspaceDocumentFacade,
        ShellRuntimeWorkspaceIntelligenceFacade,
        ShellRuntimeCommandDispatchFacade,
        ShellRuntimeLifecycleFacade {
  ShellRuntimeModel({
    required this.platformTarget,
    required List<AdapterCapabilitySnapshot> supplementalAdapterCapabilities,
    required ProjectGraphAdapter projectGraphAdapter,
    required this.workspaceController,
    required this.workspaceDocumentStore,
    required ModuleRegistry moduleRegistry,
    required NativeModuleLoader nativeModuleLoader,
    required this.editorController,
    required ExecutionAdapter executionAdapter,
    required ExecutionAdapterFactory executionAdapterFactory,
    required RuntimeEventAdapter runtimeEventAdapter,
    required DependencySourceAdapter dependencySourceAdapter,
    required DeploymentAdapter deploymentAdapter,
    this.toolchainManager,
    EditorSessionDataStore? editorSessionDataStore,
    String editorSessionWorkspaceId = 'default',
    int documentCacheLimit = 32,
    VityoThemeOverrideStore? themeOverrideStore,
    CommandPaletteDisplayPreferencesStore? commandPalettePreferencesStore,
    CommandPaletteDisplayPreferences? commandPalettePreferences,
    CommandPaletteLivePreferenceController? commandPalettePreferenceController,
    ClangCppVersionPreference? clangCppVersionPreference,
    this.agentClientRegistry,
    this.agentCollaboration,
    Future<void> Function()? refreshActiveLanguageService,
    StyioServiceSubscriptionController? styioServiceSubscriptionController,
    StyioServiceDaemonProcessSupervisor? styioServiceDaemonProcessSupervisor,
    ValueListenable<LanguageServiceStatusSurface>? languageServiceStatus,
    this.toolchainStatusReport,
    WorkspaceDiagnosticsController? workspaceDiagnosticsController,
    TestingSessionController? testingSessionController,
    SourceControlStatusController? sourceControlStatusController,
    ProjectStyioLanguageService? projectLanguageService,
    EditorDocumentResourceBinding? editorFileBinding,
    DapDebugAdapterLauncher? debugAdapterLauncher,
    DebugRuntimeTaskHistoryBinder debugRuntimeTaskHistoryBinder =
        const DebugRuntimeTaskHistoryBinder(),
    RuntimeTaskHistoryStore? debugRuntimeTaskHistoryStore,
    String debugRuntimeTaskHistoryWorkspaceId = 'default',
    int debugRuntimeTaskHistoryMaxEntries = 50,
    RuntimeOutputLiveBuffer? runtimeOutputBuffer,
    SemanticSnapshotPanelEventStateController?
    semanticPanelEventStateController,
    SemanticSnapshotPanelEventStore? semanticPanelEventStore,
    String? semanticPanelEventWorkspaceId,
    WorkspaceQuickFixTelemetryStore? workspaceQuickFixTelemetryStore,
    String? workspaceQuickFixTelemetryWorkspaceId,
  }) : projectLanguageService =
           projectLanguageService ?? const ProjectStyioLanguageService(),
       runtimeOutputBuffer = runtimeOutputBuffer ?? RuntimeOutputLiveBuffer(),
       _ownsRuntimeOutputBuffer = runtimeOutputBuffer == null,
       languageServiceStatus =
           languageServiceStatus ??
           ValueNotifier<LanguageServiceStatusSurface>(
             LanguageServiceStatusSurface.unavailable(),
           ),
       _ownsLanguageServiceStatus = languageServiceStatus == null,
       _editorFileBinding =
           editorFileBinding ??
           EditorDocumentResourceBinding(
             documentStore: workspaceDocumentStore,
           ) {
    _editorWorkspaceStateController = EditorWorkspaceStateController(
      documentCacheLimit: documentCacheLimit,
    );
    _workspaceDocumentController = WorkspaceDocumentController(
      workspaceController: workspaceController,
      editorController: editorController,
      fileBinding: _editorFileBinding,
      documentStore: workspaceDocumentStore,
      state: _editorWorkspaceStateController,
      sessionStore: editorSessionDataStore,
      sessionWorkspaceId: editorSessionWorkspaceId,
      log: appendLog,
      notify: notifyListeners,
    );
    _workspaceFileCommandController = WorkspaceFileCommandController(
      workspaceController: workspaceController,
      documentStore: workspaceDocumentStore,
      openWorkspaceFile: openWorkspaceFile,
      reloadActiveDocument: _workspaceDocumentController.loadActiveDocument,
    );
    _workspaceDiagnosticsRuntimeController =
        WorkspaceDiagnosticsRuntimeController(
          controller: workspaceDiagnosticsController,
          activeDocument: () => editorController.document,
          workspaceDocuments: () => _workspaceDocumentSamples,
          openFilePaths: () => workspaceController.openFilePaths,
          log: appendLog,
        )..addListener(_handleWorkspaceDiagnosticsChanged);
    _workspaceReplaceController = WorkspaceReplaceController(
      workspaceController: workspaceController,
      documentStore: workspaceDocumentStore,
      editorController: editorController,
      editorWorkspaceState: _editorWorkspaceStateController,
      log: appendLog,
    )..addListener(_handleWorkspaceReplaceChanged);
    _workspaceNavigationController = WorkspaceNavigationController(
      workspaceController: workspaceController,
      documentStore: workspaceDocumentStore,
      editorController: editorController,
      languageService: this.projectLanguageService,
      documentSamples: () => _workspaceDocumentSamples,
      openWorkspaceFile: openWorkspaceFile,
      log: appendLog,
    )..addListener(_handleWorkspaceNavigationChanged);
    _editorNavigationCommandController = EditorNavigationCommandController(
      selectNextDiagnostic: editorController.selectNextDiagnosticAtSelection,
      selectPreviousDiagnostic:
          editorController.selectPreviousDiagnosticAtSelection,
      selectLocalDefinition: editorController.selectDefinitionAtSelection,
      selectProjectDefinition: goToProjectDefinitionAtSelection,
      selectNextLocalReference: editorController.selectNextReferenceAtSelection,
      selectPreviousLocalReference:
          editorController.selectPreviousReferenceAtSelection,
      selectProjectReference: selectProjectReferenceAtSelection,
      log: appendLog,
      notify: notifyListeners,
    );
    _projectLanguageContextController = ProjectLanguageContextController(
      languageService: this.projectLanguageService,
      editorController: editorController,
      documentSamples: () => _workspaceDocumentSamples,
      loadDocuments: _workspaceNavigationController.loadDocuments,
      cacheDocument: _cacheDocument,
      languageServiceStatus: () => this.languageServiceStatus.value,
      lastDaemonRestartDispatch: () => lastStyioServiceDaemonRestartDispatch,
      compareReferences: _workspaceNavigationController.compareReferences,
      log: appendLog,
      recordSemanticTokensTelemetry: ({required documentId}) {
        final analysis = editorController.analysis;
        _semanticTelemetryController.recordSemanticTokens(
          documentId: documentId,
          semanticSpanCount: analysis.semanticSpans.length,
          semanticBlockCount: analysis.semanticBlocks.length,
          documentSymbolCount: analysis.documentSymbols.length,
          inlayHintCount: analysis.inlayHints.length,
          diagnosticCount: analysis.diagnostics.length,
        );
      },
    )..addListener(_handleProjectLanguageContextChanged);
    _workspaceRenameController = WorkspaceRenameController(
      languageService: this.projectLanguageService,
      loadDocuments: _workspaceNavigationController.loadDocuments,
      editorController: editorController,
      documentStore: workspaceDocumentStore,
      editorWorkspaceState: _editorWorkspaceStateController,
      cacheDocument: _cacheDocument,
      activeDocumentPath: () => _activeDocumentPath,
      log: appendLog,
      recordSafety: _recordRenameSafetyTelemetry,
    )..addListener(_handleWorkspaceRenameChanged);
    _workspaceQuickFixController = WorkspaceQuickFixController(
      languageService: this.projectLanguageService,
      loadDocuments: _workspaceNavigationController.loadDocuments,
      documentSamples: () => _workspaceDocumentSamples,
      documentStore: workspaceDocumentStore,
      editorController: editorController,
      editorWorkspaceState: _editorWorkspaceStateController,
      cacheDocument: _cacheDocument,
      log: appendLog,
    )..addListener(_handleWorkspaceQuickFixChanged);
    _settingsController = SettingsController(
      workspaceId: () => workspaceController.activeProject.id,
      defaultWorkspaceId: editorSessionWorkspaceId,
      log: appendLog,
      themeOverrideStore: themeOverrideStore,
      commandPalettePreferencesStore: commandPalettePreferencesStore,
      commandPalettePreferences: commandPalettePreferences,
      commandPalettePreferenceController: commandPalettePreferenceController,
    )..addListener(_handleSettingsChanged);
    _executionController = ExecutionController(
      executionAdapter: executionAdapter,
      executionAdapterFactory: executionAdapterFactory,
      runtimeEventAdapter: runtimeEventAdapter,
      log: appendLog,
      applyDiagnostics: editorController.applyExternalDiagnostics,
    )..addListener(_handleExecutionChanged);
    _projectGraphController = ProjectGraphController(
      adapter: projectGraphAdapter,
      workspaceController: workspaceController,
      refreshExecutionAdapter: _executionController.refreshAdapter,
      executionCapability: () =>
          _executionController.executionAdapter.capabilitySnapshot,
      runtimeEventCapability: () =>
          _executionController.runtimeEventAdapter.capabilitySnapshot,
      supplementalCapabilities: List<AdapterCapabilitySnapshot>.unmodifiable(
        supplementalAdapterCapabilities,
      ),
      log: appendLog,
    );
    _deploymentController = DeploymentController(
      adapter: deploymentAdapter,
      projectGraph: () => workspaceController.activeProject,
      log: appendLog,
    )..addListener(_handleDeploymentChanged);
    _dependencySourceController = DependencySourceController(
      adapter: dependencySourceAdapter,
      projectGraph: () => workspaceController.activeProject,
      refreshProjectGraph: refreshProjectGraph,
      log: appendLog,
    )..addListener(_handleDependencySourceChanged);
    _toolchainController = ToolchainController(
      projectGraph: () => workspaceController.activeProject,
      manager: toolchainManager,
      statusReport: toolchainStatusReport,
      log: appendLog,
      clangCppVersionPreference: clangCppVersionPreference,
    )..addListener(_handleToolchainControllerChanged);
    _semanticTelemetryController = SemanticTelemetryController(
      panelStateController:
          semanticPanelEventStateController ??
          SemanticSnapshotPanelEventStateController(),
      panelEventStore: semanticPanelEventStore,
      panelWorkspaceId:
          semanticPanelEventWorkspaceId ?? editorSessionWorkspaceId,
      quickFixTelemetryStore: workspaceQuickFixTelemetryStore,
      quickFixWorkspaceId:
          workspaceQuickFixTelemetryWorkspaceId ?? editorSessionWorkspaceId,
      runtimeOutputBuffer: this.runtimeOutputBuffer,
      activeDocumentPath: () => _activeDocumentPath,
      log: appendLog,
    )..addListener(_handleSemanticTelemetryChanged);
    _languageController = LanguageController(
      subscriptionController: styioServiceSubscriptionController,
      processSupervisor: styioServiceDaemonProcessSupervisor,
      refreshLanguageService: refreshActiveLanguageService,
      activeDocument: () => editorController.document,
      activeDocumentPath: () => _activeDocumentPath,
      workspaceRoot: () => workspaceController.activeProject.workspaceRoot,
      log: appendLog,
      recordSemanticRuntimeEvent: (event) async {
        await recordSemanticRuntimeOutputEvent(event);
      },
    )..addListener(_handleLanguageControllerChanged);
    _workspacePersistenceController = WorkspacePersistenceController(
      editorController: editorController,
      fileBinding: _editorFileBinding,
      editorWorkspaceState: _editorWorkspaceStateController,
      workspaceDocuments: _workspaceDocumentController,
      activeDocumentPath: () => _activeDocumentPath,
      activeFilePath: () => workspaceController.activeFilePath,
      cacheDocument: _cacheDocument,
      languageRefreshAvailable: () => _languageController.refreshAvailable,
      refreshLanguageService: _languageController.refresh,
      log: appendLog,
    );
    _moduleController = ModuleController(
      registry: moduleRegistry,
      nativeModuleLoader: nativeModuleLoader,
      platformTarget: platformTarget,
      refreshProjectGraph: (reason) => refreshProjectGraph(reason: reason),
      log: appendLog,
    )..addListener(_handleModuleChanged);
    _debugController = DebugController.configured(
      toolchainManager: toolchainManager,
      workspaceRoot: () => workspaceController.activeProject.workspaceRoot,
      launcher: debugAdapterLauncher,
      runtimeOutputBuffer: this.runtimeOutputBuffer,
      runtimeTaskHistoryBinder: debugRuntimeTaskHistoryBinder,
      runtimeTaskHistoryStore: debugRuntimeTaskHistoryStore,
      runtimeTaskHistoryWorkspaceId: debugRuntimeTaskHistoryWorkspaceId,
      runtimeTaskHistoryMaxEntries: debugRuntimeTaskHistoryMaxEntries,
      log: appendLog,
    );
    _debugController.addListener(_handleDebugChanged);
    _shellCommandFallbackController = ShellCommandFallbackController(
      log: appendLog,
      notify: notifyListeners,
    );
    _editorQuickFixCommandController = EditorQuickFixCommandController(
      previewProjectQuickFix: previewFirstProjectWorkspaceQuickFix,
      applyLocalQuickFix: editorController.applyFirstQuickFixAtSelection,
      applyProjectQuickFix: applyFirstProjectWorkspaceQuickFix,
      markActiveDocumentDirty: () {
        _cacheDocument(_activeDocumentPath, editorController.document);
        _editorWorkspaceStateController.markDirty(_activeDocumentPath);
      },
      recordTelemetry: (action, succeeded, message, metadata) {
        _publishDiagnosticActionTelemetry(
          action: action,
          succeeded: succeeded,
          message: message,
          metadata: metadata,
        );
      },
      log: appendLog,
      notify: notifyListeners,
    );
    _workspaceFileConfirmationController = WorkspaceFileConfirmationController(
      fileCommands: _workspaceFileCommandController,
      log: appendLog,
      notify: notifyListeners,
    );
    _shellInputCommandController = ShellInputCommandController(
      workspaceFileCommands: _workspaceFileCommandController,
      blockedReasonForCommand: blockedReasonForCommand,
      executeCommand: executeCommand,
      searchWorkspace: searchWorkspace,
      openWorkspaceFile: openWorkspaceFile,
      log: appendLog,
      notify: notifyListeners,
    );
    _languageRefreshCommandController = LanguageRefreshCommandController(
      refreshAvailable: () => _languageController.refreshAvailable,
      refresh: _languageController.refresh,
      status: () => this.languageServiceStatus.value,
      log: appendLog,
    );
    _workspaceSearchController = WorkspaceSearchController(
      workspaceController: workspaceController,
      documentStore: workspaceDocumentStore,
      languageService: this.projectLanguageService,
      documentSamples: () => _workspaceDocumentSamples,
      log: appendLog,
    );
    _backendCommandPolicyController = BackendCommandPolicyController(
      platformTarget: platformTarget,
    );
    _sourceControlController = SourceControlController(
      statusController: sourceControlStatusController,
      workspaceId: () => workspaceController.activeProject.workspaceRoot,
      dirtyDocumentPaths: () => dirtyDocumentPaths,
      log: appendLog,
    )..addListener(_handleSourceControlChanged);
    _testingController = ShellTestingController(
      sessionController: testingSessionController,
      workspaceRoot: () => workspaceController.activeProject.workspaceRoot,
      runTestsFallback: () => executeCommand(AppCommandId.runTests),
      runtimeOutputBuffer: this.runtimeOutputBuffer,
      log: appendLog,
    )..addListener(_handleTestingChanged);
    _nativeToolRuntimeController = NativeToolRuntimeController(
      executionController: _executionController,
      testingController: _testingController,
      toolchainManager: toolchainManager,
      platformTarget: platformTarget,
      workspaceController: workspaceController,
      editorController: editorController,
      editorWorkspaceState: _editorWorkspaceStateController,
      activeDocumentPath: () => _activeDocumentPath,
      adapterCapabilities: () => adapterCapabilities,
      loadClangCppSelection: _loadClangCppSelection,
      cacheDocument: _cacheDocument,
      log: appendLog,
      notify: notifyListeners,
    );
    workspaceController.addListener(_handleWorkspaceChanged);
    editorController.addListener(_handleDocumentChanged);
    this.languageServiceStatus.addListener(_handleLanguageServiceStatusChanged);
    if (toolchainManager != null) {
      unawaited(_toolchainController.refreshBootstrapSummary());
    }
    _editorFileBindingSubscription = _editorFileBinding.snapshotEvents.listen(
      _handleEditorFileBindingSnapshot,
    );
    _cacheDocument(_activeDocumentPath, editorController.document);
    _editorFileBinding.bindLoadedDocument(editorController.document);
    appendLog(
      'Shell booted for ${platformTarget.label} with '
      '${moduleRegistry.visibleModules.length} visible modules and '
      '${adapterCapabilities.length} adapter route(s).',
    );
  }

  final PlatformTarget platformTarget;
  final WorkspaceController workspaceController;
  final WorkspaceDocumentStore workspaceDocumentStore;
  final EditorSessionController editorController;
  final ToolchainManager? toolchainManager;
  late final EditorWorkspaceStateController _editorWorkspaceStateController;
  late final EditorNavigationCommandController
  _editorNavigationCommandController;
  late final EditorQuickFixCommandController _editorQuickFixCommandController;
  late final WorkspaceDocumentController _workspaceDocumentController;
  late final WorkspacePersistenceController _workspacePersistenceController;
  late final WorkspaceFileCommandController _workspaceFileCommandController;
  late final WorkspaceFileConfirmationController
  _workspaceFileConfirmationController;
  late final WorkspaceDiagnosticsRuntimeController
  _workspaceDiagnosticsRuntimeController;
  late final WorkspaceReplaceController _workspaceReplaceController;
  late final WorkspaceNavigationController _workspaceNavigationController;
  late final ProjectLanguageContextController _projectLanguageContextController;
  late final WorkspaceRenameController _workspaceRenameController;
  late final WorkspaceQuickFixController _workspaceQuickFixController;
  late final WorkspaceSearchController _workspaceSearchController;
  late final SettingsController _settingsController;
  late final ExecutionController _executionController;
  late final ProjectGraphController _projectGraphController;
  late final DeploymentController _deploymentController;
  late final DependencySourceController _dependencySourceController;
  late final LanguageController _languageController;
  late final LanguageRefreshCommandController _languageRefreshCommandController;
  late final ShellInputCommandController _shellInputCommandController;
  late final ShellCommandFallbackController _shellCommandFallbackController;
  late final ModuleController _moduleController;
  late final NativeToolRuntimeController _nativeToolRuntimeController;
  late final DebugController _debugController;
  late final BackendCommandPolicyController _backendCommandPolicyController;
  late final SourceControlController _sourceControlController;
  late final ShellTestingController _testingController;
  late final SemanticTelemetryController _semanticTelemetryController;
  late final ToolchainController _toolchainController;
  final EditorDocumentResourceBinding _editorFileBinding;
  final ValueListenable<LanguageServiceStatusSurface> languageServiceStatus;
  final ValueListenable<ToolchainManagerStatusReport>? toolchainStatusReport;
  final ProjectStyioLanguageService projectLanguageService;
  final RuntimeOutputLiveBuffer runtimeOutputBuffer;
  final AgentClientRegistry? agentClientRegistry;
  final AgentCollaborationService? agentCollaboration;
  final bool _ownsLanguageServiceStatus;
  final bool _ownsRuntimeOutputBuffer;
  StreamSubscription<DocumentResourceBindingSnapshot>?
  _editorFileBindingSubscription;

  final List<String> _debugLog = <String>[];
  String get _activeDocumentPath =>
      _workspaceDocumentController.activeDocumentPath;

  List<String> get debugLog => List<String>.unmodifiable(_debugLog);
  void _cacheDocument(String documentId, DocumentState document) {
    _workspaceDocumentController.cacheDocument(documentId, document);
  }

  List<DocumentState> get _workspaceDocumentSamples => <DocumentState>[
    editorController.document,
    for (final entry in _editorWorkspaceStateController.cachedDocumentEntries)
      if (entry.key != editorController.document.documentId) entry.value,
  ];

  WorkspaceSearchResult? get lastWorkspaceSearch =>
      _workspaceSearchController.lastTextSearch;
  WorkspaceSymbolSearchResult? get lastWorkspaceSymbolSearch =>
      _workspaceSearchController.lastSymbolSearch;
  String? get lastWorkspaceSearchQuery => _workspaceSearchController.lastQuery;
  int get lastWorkspaceSearchScannedCount =>
      _workspaceSearchController.lastScannedDocumentCount;

  void appendLog(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    _debugLog.insert(0, '$timestamp  $message');
    if (_debugLog.length > 48) {
      _debugLog.removeRange(48, _debugLog.length);
    }
    notifyListeners();
  }

  void _notifyShellListeners() => notifyListeners();

  @override
  void dispose() {
    _disposeOwnedResources();
    super.dispose();
  }
}
