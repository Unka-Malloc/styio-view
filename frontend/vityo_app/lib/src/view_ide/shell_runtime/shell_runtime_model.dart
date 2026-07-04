import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend_toolchain/backend_toolchain.dart';
import '../agent/agent.dart';
import '../commands/commands.dart';
import '../debugger/debug_adapter_launcher.dart';
import '../debugger/debug_adapter_protocol.dart';
import '../debugger/debug_adapter_session.dart';
import '../debugger/debug_launch_contract.dart';
import '../debugger/debug_launch_telemetry_store.dart';
import '../debugger/debug_runtime_task_history.dart';
import '../editor/editor.dart' hide WorkspaceEditSource;
import '../environment/configuration/configuration.dart';
import '../interaction/interaction.dart';
import '../language/language_contract.dart';
import '../language/service/semantic_snapshot_event_bridge.dart';
import '../language/service/service.dart';
import '../language/syntax/styio_syntax_highlighter.dart';
import '../language/syntax_validation/syntax_validation.dart';
import '../module_host/module_host.dart';
import '../platform/platform.dart';
import '../runtime/runtime.dart';
import '../toolchain/clang_cpp_version_configuration.dart';
import '../toolchain/clang_cpp_version_manager.dart';
import '../toolchain/toolchain_catalog.dart';
import '../toolchain/toolchain_install_executor.dart'
    hide ToolchainRecoveryAction;
import '../toolchain/toolchain_install_policy.dart';
import '../toolchain/styio_toolchain_lifecycle.dart';
import '../toolchain/toolchain_manager.dart';
import '../toolchain/toolchain_resolver.dart';
import '../toolchain/toolchain_runtime.dart';
import '../testing/testing.dart';
import '../workspace/workspace.dart';

const int _maxNativeToolResultRecords = 24;
const int _maxAgentIdeCommandResultRecords = 12;

enum WorkspaceFileCloseRequestStatus { closed, blockedUnsavedChanges, notOpen }

class WorkspaceFileCloseRequestResult {
  const WorkspaceFileCloseRequestResult({
    required this.status,
    required this.filePath,
    required this.message,
    this.canSave = false,
    this.canDiscard = false,
    this.canSwitchToFile = false,
  });

  final WorkspaceFileCloseRequestStatus status;
  final String filePath;
  final String message;
  final bool canSave;
  final bool canDiscard;
  final bool canSwitchToFile;

  bool get closed => status == WorkspaceFileCloseRequestStatus.closed;
  bool get requiresUserChoice =>
      status == WorkspaceFileCloseRequestStatus.blockedUnsavedChanges;

  factory WorkspaceFileCloseRequestResult.closedFile(String filePath) {
    return WorkspaceFileCloseRequestResult(
      status: WorkspaceFileCloseRequestStatus.closed,
      filePath: filePath,
      message: 'Closed $filePath.',
    );
  }

  factory WorkspaceFileCloseRequestResult.notOpen(String filePath) {
    return WorkspaceFileCloseRequestResult(
      status: WorkspaceFileCloseRequestStatus.notOpen,
      filePath: filePath,
      message: 'Close skipped for $filePath: file is not open.',
    );
  }

  factory WorkspaceFileCloseRequestResult.blockedUnsavedChanges(
    String filePath, {
    bool canSave = true,
    bool canDiscard = true,
    bool canSwitchToFile = false,
  }) {
    return WorkspaceFileCloseRequestResult(
      status: WorkspaceFileCloseRequestStatus.blockedUnsavedChanges,
      filePath: filePath,
      message:
          'Close blocked for $filePath: save or discard local changes first.',
      canSave: canSave,
      canDiscard: canDiscard,
      canSwitchToFile: canSwitchToFile,
    );
  }
}

class WorkspaceSaveAllResult {
  const WorkspaceSaveAllResult({
    required this.savedDocumentIds,
    required this.skippedDocumentIds,
    required this.message,
  });

  final List<String> savedDocumentIds;
  final List<String> skippedDocumentIds;
  final String message;

  bool get savedAll => skippedDocumentIds.isEmpty;
}

class _NativeToolCommandResult {
  const _NativeToolCommandResult({
    required this.applied,
    required this.message,
    this.metadata = const <String, Object?>{},
    this.diagnostics = const <Diagnostic>[],
  });

  final bool applied;
  final String message;
  final Map<String, Object?> metadata;
  final List<Diagnostic> diagnostics;
}

class NativeToolResultRecord {
  const NativeToolResultRecord({
    required this.command,
    required this.label,
    required this.applied,
    required this.message,
    required this.metadata,
    required this.diagnostics,
    required this.completedAt,
  });

  final AppCommandId command;
  final String label;
  final bool applied;
  final String message;
  final Map<String, Object?> metadata;
  final List<Diagnostic> diagnostics;
  final DateTime completedAt;

  String get commandId => command.name;

  WorkspaceDiagnosticsSnapshot toWorkspaceDiagnosticsSnapshot({
    String fallbackDocumentId = '',
    String providerId = '',
    String source = 'native-tool',
    String Function(Diagnostic diagnostic)? documentIdForDiagnostic,
  }) {
    final resolvedProviderId = providerId.isEmpty
        ? 'native-tool.$commandId'
        : providerId;
    final metadataDocumentId =
        _nativeToolDiagnosticDocumentId(metadata) ?? fallbackDocumentId;
    final workspaceDiagnostics = <WorkspaceDiagnostic>[];
    for (final diagnostic in diagnostics) {
      final explicitDocumentId = documentIdForDiagnostic
          ?.call(diagnostic)
          .trim();
      workspaceDiagnostics.add(
        WorkspaceDiagnostic(
          documentId: explicitDocumentId == null || explicitDocumentId.isEmpty
              ? metadataDocumentId.trim()
              : explicitDocumentId,
          providerId: resolvedProviderId,
          source: source,
          diagnostic: diagnostic,
        ),
      );
    }
    return WorkspaceDiagnosticsSnapshot(
      providerId: resolvedProviderId,
      message: message,
      diagnostics: workspaceDiagnostics,
    );
  }

  ExecutionResultContract toResultContract() {
    return ExecutionResultContract(
      source: 'native-tool',
      id: commandId,
      kind: commandId,
      status: applied
          ? ExecutionSessionStatus.succeeded.name
          : ExecutionSessionStatus.failed.name,
      message: message,
      diagnosticCount: diagnostics.length,
      stdoutCount: 0,
      stderrCount: 0,
      metadata: metadata,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'commandId': commandId,
      'label': label,
      'applied': applied,
      'message': message,
      'metadata': metadata,
      'diagnosticCount': diagnostics.length,
      'completedAt': completedAt.toIso8601String(),
      'executionResult': toResultContract().toJson(),
    };
  }
}

String? _nativeToolDiagnosticDocumentId(Map<String, Object?> metadata) {
  for (final key in <String>[
    'documentId',
    'activeDocumentId',
    'filePath',
    'path',
  ]) {
    final value = metadata[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  final workspaceDiagnostics = metadata['workspaceDiagnostics'];
  if (workspaceDiagnostics is Map<String, Object?>) {
    for (final key in <String>['documentId', 'activeDocumentId']) {
      final value = workspaceDiagnostics[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
  }
  return null;
}

enum DebugSessionStatus {
  idle,
  blocked,
  configured,
  launching,
  running,
  paused,
  stopped,
}

class DebugBreakpoint {
  const DebugBreakpoint({
    required this.filePath,
    required this.line,
    this.enabled = true,
  });

  final String filePath;
  final int line;
  final bool enabled;

  String get key => '$filePath:$line';
}

class DebugStackFrame {
  const DebugStackFrame({
    required this.id,
    required this.name,
    required this.filePath,
    required this.line,
    required this.column,
  });

  final String id;
  final String name;
  final String filePath;
  final int line;
  final int column;
}

class DebugThread {
  const DebugThread({required this.id, required this.name});

  final String id;
  final String name;
}

class DebugVariable {
  const DebugVariable({required this.name, required this.value, this.type});

  final String name;
  final String value;
  final String? type;
}

class DebugSessionSnapshot {
  const DebugSessionSnapshot({
    required this.status,
    required this.message,
    this.debuggerId,
    this.debuggerLabel,
    this.breakpoints = const <DebugBreakpoint>[],
    this.threads = const <DebugThread>[],
    this.stackFrames = const <DebugStackFrame>[],
    this.variables = const <DebugVariable>[],
    this.launchConfiguration,
    this.adapterSessionStatus,
    this.adapterPendingRequestCount = 0,
    this.adapterEventCount = 0,
  });

  final DebugSessionStatus status;
  final String message;
  final String? debuggerId;
  final String? debuggerLabel;
  final List<DebugBreakpoint> breakpoints;
  final List<DebugThread> threads;
  final List<DebugStackFrame> stackFrames;
  final List<DebugVariable> variables;
  final DebugLaunchConfiguration? launchConfiguration;
  final String? adapterSessionStatus;
  final int adapterPendingRequestCount;
  final int adapterEventCount;

  bool get hasConfiguredDebugger => debuggerId != null;
}

class DebugCommandResult {
  const DebugCommandResult({required this.applied, required this.message});

  final bool applied;
  final String message;
}

class _ClangCppVersionCommandInput {
  const _ClangCppVersionCommandInput({
    required this.versionId,
    this.cppStandard,
  });

  final String versionId;
  final String? cppStandard;
}

class _SourceControlCommitDraftInput {
  const _SourceControlCommitDraftInput({
    required this.message,
    this.paths = const <String>[],
  });

  final String message;
  final List<String> paths;
}

_ClangCppVersionCommandInput? _parseClangCppVersionCommandInput(String? input) {
  final trimmed = input?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final parts = trimmed.split(RegExp(r'\s+'));
  final versionId = parts.first.trim();
  if (versionId.isEmpty) {
    return null;
  }
  final cppStandard = parts.length <= 1 ? null : parts.skip(1).join(' ').trim();
  return _ClangCppVersionCommandInput(
    versionId: versionId,
    cppStandard: cppStandard == null || cppStandard.isEmpty
        ? null
        : cppStandard,
  );
}

_SourceControlCommitDraftInput? _parseSourceControlCommitDraftInput(
  String? input,
) {
  final trimmed = input?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final arrowIndex = trimmed.indexOf('->');
  if (arrowIndex < 0) {
    return _SourceControlCommitDraftInput(message: trimmed);
  }
  final message = trimmed.substring(0, arrowIndex).trim();
  if (message.isEmpty) {
    return null;
  }
  final paths = trimmed
      .substring(arrowIndex + 2)
      .split(RegExp(r'[\n,]+'))
      .map((path) => path.trim())
      .where((path) => path.isNotEmpty)
      .toList(growable: false);
  return _SourceControlCommitDraftInput(message: message, paths: paths);
}

String? _settingsSectionForAgentRecovery(String? prerequisiteForCommandId) {
  switch (prerequisiteForCommandId) {
    case 'selectClangCppVersion':
    case 'runBuild':
    case 'runStaticAnalysis':
    case 'runTests':
    case 'formatActiveDocument':
      return 'toolchain';
  }
  return null;
}

Map<String, Object?> _agentClangCppSelectionMetadata(
  ClangCppVersionSelection selection,
) {
  final preferredHandoff = selection.preferredBuildEngineHandoff;
  return <String, Object?>{
    'clangCppSelection': selection.toManifest(),
    'buildEngineHandoffCount': selection.buildEngineHandoffs.length,
    if (preferredHandoff != null)
      'preferredBuildEngineHandoff': preferredHandoff.toManifest(),
    if (selection.cmakeExecutablePath != null)
      'cmakeExecutablePath': selection.cmakeExecutablePath,
    if (selection.ninjaExecutablePath != null)
      'ninjaExecutablePath': selection.ninjaExecutablePath,
  };
}

class ShellRuntimeModel extends ChangeNotifier {
  ShellRuntimeModel({
    required this.platformTarget,
    required List<AdapterCapabilitySnapshot> supplementalAdapterCapabilities,
    required ProjectGraphAdapter projectGraphAdapter,
    required this.workspaceController,
    required this.workspaceDocumentStore,
    required this.moduleRegistry,
    required this.nativeModuleLoader,
    required this.editorController,
    required this.executionAdapter,
    required ExecutionAdapterFactory executionAdapterFactory,
    required this.runtimeEventAdapter,
    required DependencySourceAdapter dependencySourceAdapter,
    required DeploymentAdapter deploymentAdapter,
    required ToolchainManagementAdapter toolchainManagementAdapter,
    this.toolchainManager,
    this.editorSessionDataStore,
    this.editorSessionWorkspaceId = 'default',
    this.documentCacheLimit = 32,
    this.themeOverrideStore,
    this.commandPalettePreferencesStore,
    CommandPaletteDisplayPreferences? commandPalettePreferences,
    CommandPaletteLivePreferenceController? commandPalettePreferenceController,
    ClangCppVersionPreference? clangCppVersionPreference,
    AgentCodingSessionController? agentCodingController,
    this.agentExtensionToolExecutionRegistry,
    this.agentProviderConfigurator,
    this.refreshActiveLanguageService,
    this.styioServiceSubscriptionController,
    this.styioServiceDaemonProcessSupervisor,
    ValueListenable<LanguageServiceStatusSurface>? languageServiceStatus,
    this.toolchainStatusReport,
    this.workspaceDiagnosticsController,
    this.testingSessionController,
    this.sourceControlStatusController,
    ProjectStyioLanguageService? projectLanguageService,
    EditorDocumentResourceBinding? editorFileBinding,
    this.debugAdapterLauncher,
    this.debugRuntimeTaskHistoryBinder = const DebugRuntimeTaskHistoryBinder(),
    this.debugRuntimeTaskHistoryStore,
    this.debugRuntimeTaskHistoryWorkspaceId = 'default',
    this.debugRuntimeTaskHistoryMaxEntries = 50,
    RuntimeOutputLiveBuffer? runtimeOutputBuffer,
    SemanticSnapshotPanelEventStateController?
    semanticPanelEventStateController,
    this.semanticPanelEventStore,
    String? semanticPanelEventWorkspaceId,
    this.workspaceQuickFixTelemetryStore,
    String? workspaceQuickFixTelemetryWorkspaceId,
  }) : _activeDocumentPath = workspaceController.activeFilePath,
       projectLanguageService =
           projectLanguageService ?? const ProjectStyioLanguageService(),
       runtimeOutputBuffer = runtimeOutputBuffer ?? RuntimeOutputLiveBuffer(),
       semanticPanelEventStateController =
           semanticPanelEventStateController ??
           SemanticSnapshotPanelEventStateController(),
       semanticPanelEventWorkspaceId =
           semanticPanelEventWorkspaceId ?? editorSessionWorkspaceId,
       workspaceQuickFixTelemetryWorkspaceId =
           workspaceQuickFixTelemetryWorkspaceId ?? editorSessionWorkspaceId,
       _ownsRuntimeOutputBuffer = runtimeOutputBuffer == null,
       languageServiceStatus =
           languageServiceStatus ??
           ValueNotifier<LanguageServiceStatusSurface>(
             LanguageServiceStatusSurface.unavailable(),
           ),
       _ownsLanguageServiceStatus = languageServiceStatus == null,
       _ownsAgentCodingController = agentCodingController == null,
       _supplementalAdapterCapabilities =
           List<AdapterCapabilitySnapshot>.unmodifiable(
             supplementalAdapterCapabilities,
           ),
       _projectGraphAdapter = projectGraphAdapter,
       _executionAdapterFactory = executionAdapterFactory,
       _dependencySourceAdapter = dependencySourceAdapter,
       _deploymentAdapter = deploymentAdapter,
       _toolchainManagementAdapter = toolchainManagementAdapter,
       _editorFileBinding =
           editorFileBinding ??
           EditorDocumentResourceBinding(documentStore: workspaceDocumentStore),
       _ownsCommandPalettePreferenceController =
           commandPalettePreferenceController == null,
       _adapterCapabilities = normalizeCapabilitySnapshots([
         projectGraphAdapter.capabilitySnapshot,
         executionAdapter.capabilitySnapshot,
         runtimeEventAdapter.capabilitySnapshot,
         ...supplementalAdapterCapabilities,
       ]),
       _clangCppVersionPreference = clangCppVersionPreference {
    this.commandPalettePreferenceController =
        commandPalettePreferenceController ??
        CommandPaletteLivePreferenceController(
          initialPreferences:
              commandPalettePreferences ??
              CommandPaletteDisplayPreferences(
                workspaceId: editorSessionWorkspaceId,
              ),
        );
    _commandPalettePreferenceSubscription = this
        .commandPalettePreferenceController
        .stream
        .listen(_handleCommandPalettePreferencesChanged);
    this.agentCodingController =
        agentCodingController ??
        AgentCodingSessionController(
          profile: AgentPromptProfile.defaultForPlatform(platformTarget),
          adapter: const LocalOnlyAgentProviderAdapter(),
          contextProvider: () => agentSessionContext,
          runtimeOutputBuffer: this.runtimeOutputBuffer,
        );
    this.agentCodingController.contextProvider = () => agentSessionContext;
    this.agentCodingController.addListener(_handleAgentCodingSessionChanged);
    if (agentProviderConfigurator != null) {
      unawaited(refreshAgentProviderProfileManifest());
    }
    workspaceController.addListener(_handleWorkspaceChanged);
    editorController.addListener(_handleDocumentChanged);
    this.languageServiceStatus.addListener(_handleLanguageServiceStatusChanged);
    _styioServiceSubscriptionEventSubscription =
        styioServiceSubscriptionController?.events.listen(
          _handleStyioServiceSubscriptionEvent,
        );
    toolchainStatusReport?.addListener(_handleToolchainStatusReportChanged);
    if (toolchainManager != null) {
      unawaited(refreshToolchainBootstrapSummary());
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
  final ModuleRegistry moduleRegistry;
  final NativeModuleLoader nativeModuleLoader;
  final EditorSessionController editorController;
  final ProjectGraphAdapter _projectGraphAdapter;
  final List<AdapterCapabilitySnapshot> _supplementalAdapterCapabilities;
  final ExecutionAdapterFactory _executionAdapterFactory;
  final DependencySourceAdapter _dependencySourceAdapter;
  final DeploymentAdapter _deploymentAdapter;
  final ToolchainManagementAdapter _toolchainManagementAdapter;
  final ToolchainManager? toolchainManager;
  final EditorSessionDataStore? editorSessionDataStore;
  final String editorSessionWorkspaceId;
  final int documentCacheLimit;
  final VityoThemeOverrideStore? themeOverrideStore;
  final CommandPaletteDisplayPreferencesStore? commandPalettePreferencesStore;
  late final CommandPaletteLivePreferenceController
  commandPalettePreferenceController;
  ClangCppVersionPreference? _clangCppVersionPreference;
  late final AgentCodingSessionController agentCodingController;
  final ExtensionAgentToolExecutionRegistry?
  agentExtensionToolExecutionRegistry;
  final AgentProviderConfigurator? agentProviderConfigurator;
  final Future<void> Function()? refreshActiveLanguageService;
  final StyioServiceSubscriptionController? styioServiceSubscriptionController;
  final StyioServiceDaemonProcessSupervisor?
  styioServiceDaemonProcessSupervisor;
  final EditorDocumentResourceBinding _editorFileBinding;
  final RuntimeEventAdapter runtimeEventAdapter;
  final ValueListenable<LanguageServiceStatusSurface> languageServiceStatus;
  final ValueListenable<ToolchainManagerStatusReport>? toolchainStatusReport;
  final WorkspaceDiagnosticsController? workspaceDiagnosticsController;
  final TestingSessionController? testingSessionController;
  final SourceControlStatusController? sourceControlStatusController;
  final ProjectStyioLanguageService projectLanguageService;
  final DapDebugAdapterLauncher? debugAdapterLauncher;
  final DebugRuntimeTaskHistoryBinder debugRuntimeTaskHistoryBinder;
  final RuntimeTaskHistoryStore? debugRuntimeTaskHistoryStore;
  final String debugRuntimeTaskHistoryWorkspaceId;
  final int debugRuntimeTaskHistoryMaxEntries;
  final RuntimeOutputLiveBuffer runtimeOutputBuffer;
  final SemanticSnapshotPanelEventStateController
  semanticPanelEventStateController;
  final SemanticSnapshotPanelEventStore? semanticPanelEventStore;
  final String semanticPanelEventWorkspaceId;
  final WorkspaceQuickFixTelemetryStore? workspaceQuickFixTelemetryStore;
  final String workspaceQuickFixTelemetryWorkspaceId;
  final bool _ownsLanguageServiceStatus;
  final bool _ownsAgentCodingController;
  final bool _ownsCommandPalettePreferenceController;
  final bool _ownsRuntimeOutputBuffer;
  StreamSubscription<DocumentResourceBindingSnapshot>?
  _editorFileBindingSubscription;
  StreamController<DocumentState>? _styioServiceSubscriptionDocuments;
  StreamSubscription<StyioServiceSubscriptionEvent>?
  _styioServiceSubscriptionEventSubscription;
  late final StreamSubscription<CommandPaletteLivePreferenceState>
  _commandPalettePreferenceSubscription;

  final List<String> _debugLog = <String>[];
  final List<NativeToolResultRecord> _nativeToolResults =
      <NativeToolResultRecord>[];
  final List<DebugBreakpoint> _debugBreakpoints = <DebugBreakpoint>[];
  final Map<String, DocumentState> _documentCache = <String, DocumentState>{};
  final Set<String> _dirtyDocumentPaths = <String>{};
  final Map<String, int> _documentCursorOffsets = <String, int>{};
  final Map<String, int> _documentSelectionAnchors = <String, int>{};
  String _activeDocumentPath;
  bool _suppressWorkspaceChangedLoad = false;
  bool _suppressSelectionTracking = false;
  bool _disposed = false;
  int _workspaceDocumentLoadGeneration = 0;
  String _selectedTestRunConfigurationId = '';
  ExecutionSession? _lastExecutionSession;
  List<RuntimeEventEnvelope> _lastRuntimeEvents =
      const <RuntimeEventEnvelope>[];
  VityoThemeOverride _themeOverride = const VityoThemeOverride();
  DependencySourceCommandResult? _lastDependencySourceCommand;
  DeploymentCommandResult? _lastDeploymentCommand;
  ToolchainCommandResult? _lastToolchainCommand;
  ToolchainStateSnapshot? _lastToolchainSnapshot;
  ToolchainInstallPlan? _lastToolchainInstallPlan;
  ToolchainInstallExecutionResult? _lastToolchainInstallExecutionResult;
  ToolchainManagerBootstrapSummary? _toolchainBootstrapSummary;
  ToolchainBootstrapActionDispatchResult? _lastToolchainBootstrapActionDispatch;
  StyioServiceDaemonRestartDispatchResult?
  _lastStyioServiceDaemonRestartDispatch;
  DebugSessionSnapshot _debugSession = const DebugSessionSnapshot(
    status: DebugSessionStatus.idle,
    message: 'No debug session has been started.',
  );
  DebugRuntimeExecutionResult? _lastDebugRuntimeExecutionResult;
  ExecutionAdapter executionAdapter;
  List<AdapterCapabilitySnapshot> _adapterCapabilities;
  WorkspaceFileCloseRequestResult? _lastCloseRequestResult;
  AgentWorkspaceSearchResultContext? _lastAgentWorkspaceSearch;
  AgentWorkspaceSymbolSearchResultContext? _lastAgentWorkspaceSymbolSearch;
  AgentCommandResultContext? _lastAgentIdeCommandResult;
  AgentPromptProfileManifest _agentProviderProfileManifest =
      const AgentPromptProfileManifest();
  WorkspaceFileCommandRouteResult? _pendingWorkspaceFileCommandConfirmation;
  WorkspaceEditPreview? _lastWorkspaceEditPreview;
  WorkspaceEditApplyResultViewModel? _lastWorkspaceEditApplyResult;
  WorkspaceQuickFixTelemetrySnapshot? _workspaceQuickFixTelemetrySnapshot;
  WorkspaceReplacePreview? _lastWorkspaceReplacePreview;
  SourceControlCommitDraft? _sourceControlCommitDraft;
  bool _sourceControlCommitDialogOpen = false;
  final List<AgentCommandResultContext> _agentIdeCommandResults =
      <AgentCommandResultContext>[];
  DapDebugSessionHandle? _dapDebugSession;
  StreamSubscription<DapSessionSnapshot>? _dapDebugSessionSubscription;
  Future<void> _debugRuntimeTaskHistoryAppendQueue = Future<void>.value();
  bool _dapInspectionRequestInFlight = false;

  List<AdapterCapabilitySnapshot> get adapterCapabilities =>
      _adapterCapabilities;
  List<String> get debugLog => List<String>.unmodifiable(_debugLog);
  List<NativeToolResultRecord> get nativeToolResults =>
      List<NativeToolResultRecord>.unmodifiable(_nativeToolResults);
  AgentCommandResultContext? get lastAgentIdeCommandResult =>
      _lastAgentIdeCommandResult;
  AgentPromptProfileManifest get agentProviderProfileManifest =>
      _agentProviderProfileManifest;
  WorkspaceFileCommandRouteResult?
  get pendingWorkspaceFileCommandConfirmation =>
      _pendingWorkspaceFileCommandConfirmation;
  NativeToolResultRecord? get lastNativeToolResult =>
      _nativeToolResults.isEmpty ? null : _nativeToolResults.first;
  DebugSessionSnapshot get debugSession => _debugSession;
  DebugRuntimeExecutionResult? get lastDebugRuntimeExecutionResult =>
      _lastDebugRuntimeExecutionResult;
  List<DebugBreakpoint> get debugBreakpoints =>
      List<DebugBreakpoint>.unmodifiable(_debugBreakpoints);
  List<String> get cachedDocumentPaths =>
      List<String>.unmodifiable(_documentCache.keys);
  List<String> get dirtyDocumentPaths =>
      List<String>.unmodifiable(_dirtyDocumentPaths);
  bool get styioServiceSubscriptionAvailable =>
      styioServiceSubscriptionController != null;
  bool get styioServiceSubscriptionListening =>
      styioServiceSubscriptionController?.listening ?? false;
  StyioServiceDaemonRestartDispatchResult?
  get lastStyioServiceDaemonRestartDispatch =>
      _lastStyioServiceDaemonRestartDispatch;
  ExecutionSession? get lastExecutionSession => _lastExecutionSession;
  List<RuntimeEventEnvelope> get lastRuntimeEvents =>
      List<RuntimeEventEnvelope>.unmodifiable(_lastRuntimeEvents);
  VityoThemeOverride get themeOverride => _themeOverride;
  List<DocumentState> get _agentWorkspaceDocumentSamples {
    return <DocumentState>[
      editorController.document,
      for (final entry in _documentCache.entries)
        if (entry.key != editorController.document.documentId) entry.value,
    ];
  }

  WorkspaceDiagnosticsSnapshot? get workspaceDiagnosticsSnapshot =>
      workspaceDiagnosticsController?.snapshot;
  List<WorkspaceDiagnosticsProducerLifecycleSnapshot>
  get diagnosticsProducerLifecycles =>
      workspaceDiagnosticsController?.diagnosticsProducerLifecycles ??
      const <WorkspaceDiagnosticsProducerLifecycleSnapshot>[];
  TestDiscoveryResult? get testDiscovery => testingSessionController?.discovery;
  TestRunResult? get lastTestRun => testingSessionController?.lastRun;
  List<TestRunResult> get testRunHistory =>
      testingSessionController?.runHistory ?? const <TestRunResult>[];
  List<FailedTestRetryRecord> get failedTestRetryHistory =>
      testingSessionController?.failedRetryHistory ??
      const <FailedTestRetryRecord>[];
  FailedTestDebugCancellationRoute? get failedDebugCancellationRoute =>
      testingSessionController?.lastFailedDebugCancellationRoute;
  TestRunConfigurationSet get testRunConfigurationSet {
    final workspaceRoot = workspaceController.activeProject.workspaceRoot;
    final lastRun = lastTestRun;
    final providerId = lastRun?.providerId ?? 'native-tool-runTests';
    final configurations = <TestRunConfiguration>[
      TestRunConfiguration(
        id: 'all-tests',
        label: 'All Tests',
        workspaceRoot: workspaceRoot,
        providerId: providerId,
      ),
    ];
    final failedDebugConfiguration = testingSessionController?.rerunPlanner
        .plan(lastRun: lastRun, workspaceRoot: workspaceRoot, debug: true);
    if (failedDebugConfiguration != null) {
      configurations.add(failedDebugConfiguration);
    }
    final selectedId =
        configurations.any(
          (configuration) =>
              configuration.id == _selectedTestRunConfigurationId,
        )
        ? _selectedTestRunConfigurationId
        : configurations.first.id;
    return TestRunConfigurationSet(
      workspaceId: workspaceRoot,
      selectedConfigurationId: selectedId,
      configurations: List<TestRunConfiguration>.unmodifiable(configurations),
    );
  }

  SourceControlStatusSnapshot get sourceControlStatusSnapshot =>
      sourceControlStatusController?.snapshot ??
      _localDirtySourceControlStatusSnapshot();
  SourceControlDiffSnapshot? get sourceControlDiffPreview =>
      sourceControlStatusController?.diffPreview;
  SourceControlBranchSnapshot? get sourceControlBranchSnapshot =>
      sourceControlStatusController?.branchSnapshot;
  SourceControlHistorySnapshot? get sourceControlHistorySnapshot =>
      sourceControlStatusController?.historySnapshot;
  SourceControlPartialPatchResult? get sourceControlHunkActionResult =>
      sourceControlStatusController?.lastPartialPatchResult;
  SourceControlCommitDraft? get sourceControlCommitDraft =>
      _sourceControlCommitDraft;
  SourceControlCommitDialogState? get sourceControlCommitDialogState {
    final draft = _sourceControlCommitDraft;
    if (draft == null) {
      return null;
    }
    return SourceControlCommitDialogState.fromDraft(
      draft: draft,
      open: _sourceControlCommitDialogOpen,
    );
  }

  SemanticSnapshotPanelViewModel? semanticPanelViewModelFor(
    SemanticSnapshotPanelEventTarget target,
  ) {
    final viewModel = SemanticSnapshotPanelViewModel.fromState(
      semanticPanelEventStateController.stateFor(target),
    );
    return viewModel.empty ? null : viewModel;
  }

  SemanticSnapshotPanelViewModel? get semanticProblemsPanelViewModel =>
      semanticPanelViewModelFor(SemanticSnapshotPanelEventTarget.problems);

  SemanticSnapshotPanelViewModel? get semanticRefactorPanelViewModel =>
      semanticPanelViewModelFor(SemanticSnapshotPanelEventTarget.refactor);

  List<SemanticSnapshotPanelViewModel> get semanticPanelViewModels {
    return <SemanticSnapshotPanelViewModel>[
      for (final target in SemanticSnapshotPanelEventTarget.values)
        if (semanticPanelViewModelFor(target) != null)
          semanticPanelViewModelFor(target)!,
    ];
  }

  HoverPayload? get projectHoverAtSelection {
    final hover = projectLanguageService.hoverAt(
      documents: _agentWorkspaceDocumentSamples,
      documentId: editorController.document.documentId,
      offset: editorController.selection.extentOffset,
    );
    if (hover == null) {
      return null;
    }
    final range =
        editorController.tokenAtSelection?.range ??
        SourceRange(
          start: editorController.selection.start,
          end: editorController.selection.end,
        );
    return HoverPayload(range: range, markdown: hover.label);
  }

  HoverPayload? get mergedHoverAtSelection {
    return projectHoverAtSelection ?? editorController.hoverAtSelection;
  }

  List<CompletionItem> get projectCompletionsAtSelection {
    return projectLanguageService.completionsAt(
      documents: _agentWorkspaceDocumentSamples,
      documentId: editorController.document.documentId,
      offset: editorController.selection.extentOffset,
    );
  }

  List<CompletionItem> get mergedCompletionsAtSelection {
    final completions = <CompletionItem>[];
    final seen = <String>{};
    for (final completion in [
      ...editorController.completionsAtSelection,
      ...projectCompletionsAtSelection,
    ]) {
      final key =
          '${completion.kind.name}:${completion.label}:${completion.insertText}';
      if (seen.add(key)) {
        completions.add(completion);
      }
    }
    return List<CompletionItem>.unmodifiable(completions);
  }

  AgentSessionContext get agentSessionContext {
    final debugBreakpoints = _debugBreakpoints;
    return AgentSessionContext.fromEditorState(
      document: editorController.document,
      selection: editorController.selection,
      diagnostics: editorController.analysis.diagnostics,
      focusedDiagnostics: editorController.diagnosticsAtSelection,
      focusToken: editorController.tokenAtSelection,
      focusSemanticKind: editorController.semanticKindAtSelection,
      hover: mergedHoverAtSelection,
      definition: editorController.definitionAtSelection,
      resolvedElement: editorController.resolvedElementAtSelection,
      resolvedReference: editorController.resolvedReferenceAtSelection,
      parameterInfo: editorController.parameterInfoAtSelection,
      safeDeletePlan: editorController.safeDeletePlanAtSelection,
      inlineVariablePlan: editorController.inlineVariablePlanAtSelection,
      surroundTemplates: editorController.surroundTemplatesAtSelection,
      references: editorController.referencesAtSelection,
      completions: mergedCompletionsAtSelection,
      codeActions: editorController.contextActionsAtSelection,
      semanticSpans: editorController.analysis.semanticSpans,
      documentSymbols: editorController.analysis.documentSymbols,
      inlayHints: editorController.analysis.inlayHints,
      semanticBlocks: editorController.analysis.semanticBlocks,
      semanticFeatureMatrix: editorController.semanticFeatureMatrix,
      languageServiceStatus: languageServiceStatus.value,
      lastCommandResult: _lastAgentIdeCommandResult,
      recentCommandResults: _agentIdeCommandResults,
      lastWorkspaceEditPreview: _lastWorkspaceEditPreview,
      lastWorkspaceEditApplyResult: _lastWorkspaceEditApplyResult,
      debug: AgentDebugContext(
        status: _debugSession.status.name,
        message: _debugSession.message,
        debuggerId: _debugSession.debuggerId,
        debuggerLabel: _debugSession.debuggerLabel,
        breakpointCount: debugBreakpoints.length,
        breakpoints: debugBreakpoints
            .map(
              (breakpoint) => AgentDebugBreakpointContext(
                filePath: breakpoint.filePath,
                line: breakpoint.line,
                enabled: breakpoint.enabled,
              ),
            )
            .toList(growable: false),
        threadCount: _debugSession.threads.length,
        threads: _debugSession.threads
            .map(
              (thread) =>
                  AgentDebugThreadContext(id: thread.id, name: thread.name),
            )
            .toList(growable: false),
        stackFrameCount: _debugSession.stackFrames.length,
        stackFrames: _debugSession.stackFrames
            .map(
              (frame) => AgentDebugStackFrameContext(
                id: frame.id,
                name: frame.name,
                filePath: frame.filePath,
                line: frame.line,
                column: frame.column,
              ),
            )
            .toList(growable: false),
        variableCount: _debugSession.variables.length,
        variables: _debugSession.variables
            .map(
              (variable) => AgentDebugVariableContext(
                name: variable.name,
                value: variable.value,
                type: variable.type,
              ),
            )
            .toList(growable: false),
        launch: _debugSession.launchConfiguration == null
            ? null
            : AgentDebugLaunchContext(
                ready: _debugSession.launchConfiguration!.ready,
                readiness:
                    _debugSession.launchConfiguration!.readiness.wireValue,
                reason: _debugSession.launchConfiguration!.reason,
                adapterProtocol:
                    _debugSession.launchConfiguration!.adapterProtocol,
                debuggerId: _debugSession.launchConfiguration!.debuggerId,
                debuggerLabel: _debugSession.launchConfiguration!.debuggerLabel,
                debuggerExecutablePath:
                    _debugSession.launchConfiguration!.debuggerExecutablePath,
                debuggerArguments:
                    _debugSession.launchConfiguration!.debuggerArguments,
                programPath: _debugSession.launchConfiguration!.programPath,
                cwd: _debugSession.launchConfiguration!.cwd,
                arguments: _debugSession.launchConfiguration!.arguments,
                environment: _debugSession.launchConfiguration!.environment,
                stopOnEntry: _debugSession.launchConfiguration!.stopOnEntry,
                breakpointCount:
                    _debugSession.launchConfiguration!.breakpoints.length,
              ),
        adapterSessionStatus: _debugSession.adapterSessionStatus,
        adapterPendingRequestCount: _debugSession.adapterPendingRequestCount,
        adapterEventCount: _debugSession.adapterEventCount,
      ),
      lastExecutionSession: _lastExecutionSession,
      lastRuntimeEvents: _lastRuntimeEvents,
      workspaceFiles: workspaceController.files,
      openDocumentIds: workspaceController.openFilePaths,
      dirtyDocumentIds: dirtyDocumentPaths,
      workspaceDocuments: _agentWorkspaceDocumentSamples,
      lastWorkspaceSearch: _lastAgentWorkspaceSearch,
      lastWorkspaceSymbolSearch: _lastAgentWorkspaceSymbolSearch,
      workspaceDiagnostics: workspaceDiagnosticsSnapshot,
      sourceControlStatus: sourceControlStatusSnapshot,
      sourceControlDiff: sourceControlDiffPreview,
      sourceControlContext: sourceControlStatusController?.agentContextSnapshot,
      testDiscovery: testDiscovery,
      lastTestRun: lastTestRun,
      testRunConfigurationSet: testRunConfigurationSet,
      workspaceRoot: workspaceController.activeProject.workspaceRoot,
      activeFilePath: workspaceController.activeFilePath,
      toolchainSnapshot:
          toolchainStatusReport?.value.snapshot ?? _lastToolchainSnapshot,
      clangCppVersionPreference: _clangCppVersionPreference,
      toolchainBootstrapSummary: _toolchainBootstrapSummary,
      toolchainBootstrapActionDispatch: _lastToolchainBootstrapActionDispatch,
      semanticPanelViewModels: semanticPanelViewModels,
      recoveryPlan: agentCodingController.sessionRecoveryPlan,
      savedProviderProfiles: _agentProviderProfileManifest.entries,
    );
  }

  Future<AgentPromptProfileManifest>
  refreshAgentProviderProfileManifest() async {
    final configurator = agentProviderConfigurator;
    if (configurator == null) {
      _agentProviderProfileManifest = const AgentPromptProfileManifest();
      return _agentProviderProfileManifest;
    }
    try {
      _agentProviderProfileManifest = await configurator.savedProfileManifest();
      notifyListeners();
    } on Object catch (error) {
      appendLog(
        'Agent provider profile manifest refresh failed: '
        '${sanitizeAgentError(error.toString())}',
      );
    }
    return _agentProviderProfileManifest;
  }

  Future<List<SemanticSnapshotPanelEventState>> restoreSemanticPanelEvents({
    String? workspaceId,
  }) async {
    final store = semanticPanelEventStore;
    if (store == null) {
      appendLog(
        'Semantic panel event restore unavailable: no DataStore is wired.',
      );
      return <SemanticSnapshotPanelEventState>[
        for (final target in SemanticSnapshotPanelEventTarget.values)
          semanticPanelEventStateController.stateFor(target),
      ];
    }
    final resolvedWorkspaceId = workspaceId ?? semanticPanelEventWorkspaceId;
    final states = <SemanticSnapshotPanelEventState>[];
    for (final target in SemanticSnapshotPanelEventTarget.values) {
      states.add(
        await store.readState(workspaceId: resolvedWorkspaceId, target: target),
      );
    }
    semanticPanelEventStateController.replaceStates(states);
    appendLog(
      'Semantic panel events restored for $resolvedWorkspaceId: '
      '${semanticPanelViewModels.length} active panel(s).',
    );
    notifyListeners();
    return List<SemanticSnapshotPanelEventState>.unmodifiable(states);
  }

  Future<SemanticSnapshotPanelEventState> recordSemanticPanelEvent(
    SemanticSnapshotPanelEvent event, {
    String? workspaceId,
    int? maxEvents,
  }) async {
    final store = semanticPanelEventStore;
    final localMaxEvents =
        maxEvents ?? store?.retentionPolicy.maxEventsPerTarget ?? 50;
    var state = semanticPanelEventStateController.recordEvent(
      event,
      maxEvents: localMaxEvents,
    );
    if (store != null) {
      try {
        state = await store.recordEvent(
          workspaceId: workspaceId ?? semanticPanelEventWorkspaceId,
          event: event,
          maxEvents: maxEvents,
        );
        semanticPanelEventStateController.replaceState(state);
      } on Object catch (error) {
        appendLog('Semantic panel event persistence failed: $error');
      }
    }
    notifyListeners();
    return state;
  }

  Future<SemanticSnapshotPanelEvent?> recordSemanticRuntimeOutputEvent(
    RuntimeOutputEvent event, {
    bool publishToRuntimeOutput = true,
  }) async {
    if (publishToRuntimeOutput) {
      runtimeOutputBuffer.addEvent(event);
    }
    final panelEvent = const SemanticSnapshotPanelEventDispatcher()
        .panelEventFor(event);
    if (panelEvent == null) {
      return null;
    }
    await recordSemanticPanelEvent(panelEvent);
    return panelEvent;
  }

  Future<WorkspaceDiagnosticsProducerLifecycleSnapshot?>
  cancelWorkspaceDiagnosticsProducer(
    WorkspaceDiagnosticsProducerLifecycleSnapshot snapshot,
  ) async {
    final controller = workspaceDiagnosticsController;
    if (controller == null) {
      appendLog(
        'Workspace diagnostics producer cancel unavailable: no controller is wired.',
      );
      return null;
    }
    final result = await controller.cancelDiagnosticsProducer(snapshot);
    if (result == null) {
      appendLog(
        'Workspace diagnostics producer ${snapshot.providerId} cancel unavailable: no lifecycle plan is registered.',
      );
      return null;
    }
    appendLog(
      'Workspace diagnostics producer ${snapshot.providerId} cancel ${result.status.wireValue}: ${result.message}',
    );
    notifyListeners();
    return result;
  }

  Future<void> startStyioServiceDocumentSubscription() async {
    final controller = styioServiceSubscriptionController;
    if (controller == null) {
      appendLog(
        'StyioService document subscription unavailable: no controller is wired.',
      );
      return;
    }
    await _styioServiceSubscriptionDocuments?.close();
    final documents = StreamController<DocumentState>.broadcast(sync: true);
    _styioServiceSubscriptionDocuments = documents;
    controller.bindDocumentStream(
      documents.stream,
      filePathForDocument: _styioServiceDocumentPath,
      workingDirectoryForDocument: (_) =>
          workspaceController.activeProject.workspaceRoot,
    );
    documents.add(editorController.document);
    appendLog('StyioService document subscription started from shell.');
    notifyListeners();
  }

  Future<StyioServiceSubscriptionEvent?> refreshStyioServiceSubscriptionNow() {
    final controller = styioServiceSubscriptionController;
    if (controller == null) {
      appendLog(
        'StyioService document subscription refresh unavailable: no controller is wired.',
      );
      return Future<StyioServiceSubscriptionEvent?>.value();
    }
    return controller.refresh(
      editorController.document,
      filePath: _styioServiceDocumentPath(editorController.document),
      workingDirectory: workspaceController.activeProject.workspaceRoot,
    );
  }

  Future<StyioServiceSubscriptionEvent?>
  cancelStyioServiceDocumentSubscription() async {
    final controller = styioServiceSubscriptionController;
    if (controller == null) {
      appendLog(
        'StyioService document subscription cancel unavailable: no controller is wired.',
      );
      return null;
    }
    await _styioServiceSubscriptionDocuments?.close();
    _styioServiceSubscriptionDocuments = null;
    final event = await controller.cancel(
      message: 'StyioService document subscription cancelled from shell.',
    );
    notifyListeners();
    return event;
  }

  Future<StyioServiceDaemonRestartDispatchResult?>
  dispatchStyioServiceDaemonRestart({
    int failedAttempt = 0,
    StyioServiceDaemonRestartReason reason =
        StyioServiceDaemonRestartReason.manual,
    StyioServiceDaemonRestartPolicy policy =
        const StyioServiceDaemonRestartPolicy(),
    StyioServiceDaemonRestartHandler? restart,
    StyioServiceDaemonProcessSupervisor? processSupervisor,
  }) async {
    final controller = styioServiceSubscriptionController;
    if (controller == null) {
      appendLog(
        'StyioService daemon restart unavailable: no controller is wired.',
      );
      return null;
    }
    final effectiveProcessSupervisor =
        processSupervisor ?? styioServiceDaemonProcessSupervisor;
    final supervisorControls = effectiveProcessSupervisor == null
        ? null
        : StyioServiceDaemonSupervisorControls(
            controller: controller,
            processSupervisor: effectiveProcessSupervisor,
          );
    final restartHandler =
        restart ??
        supervisorControls?.restartHandler ??
        (refreshActiveLanguageService == null
            ? null
            : _restartStyioServiceDaemonFromLanguageRefresh);
    final result = await controller.dispatchDaemonRestart(
      failedAttempt: failedAttempt,
      reason: reason,
      policy: policy,
      restart: restartHandler,
    );
    _lastStyioServiceDaemonRestartDispatch = result;
    appendLog(result.message);
    notifyListeners();
    return result;
  }

  Future<StyioServiceDaemonLifecycleSnapshot>
  _restartStyioServiceDaemonFromLanguageRefresh(
    StyioServiceDaemonRestartPlan plan,
  ) async {
    final refresh = refreshActiveLanguageService;
    if (refresh == null) {
      return StyioServiceDaemonLifecycleSnapshot(
        state: plan.lifecycle.state,
        providerId: plan.providerId,
        message:
            'StyioService daemon restart skipped: no language service refresh callback is configured.',
      );
    }
    await refresh();
    return StyioServiceDaemonLifecycleSnapshot(
      state: StyioServiceDaemonLifecycleState.active,
      providerId: plan.providerId,
      message:
          'StyioService daemon restart dispatched through the language service refresh callback.',
    );
  }

  String? _styioServiceDocumentPath(DocumentState document) {
    final documentId = document.documentId.trim();
    if (documentId.isNotEmpty) {
      return documentId;
    }
    final activePath = _activeDocumentPath.trim();
    return activePath.isEmpty ? null : activePath;
  }

  Future<WorkspaceQuickFixTelemetrySnapshot> restoreWorkspaceQuickFixTelemetry({
    String? workspaceId,
  }) async {
    final resolvedWorkspaceId =
        workspaceId ?? workspaceQuickFixTelemetryWorkspaceId;
    final store = workspaceQuickFixTelemetryStore;
    if (store == null) {
      final snapshot = WorkspaceQuickFixTelemetrySnapshot(
        workspaceId: resolvedWorkspaceId,
      );
      _workspaceQuickFixTelemetrySnapshot = snapshot;
      appendLog(
        'Workspace quick-fix telemetry restore unavailable: no DataStore is wired.',
      );
      return snapshot;
    }
    final snapshot = await store.readSnapshot(workspaceId: resolvedWorkspaceId);
    _workspaceQuickFixTelemetrySnapshot = snapshot;
    appendLog(
      'Workspace quick-fix telemetry restored: '
      '${snapshot.outcomes.length} outcome(s).',
    );
    notifyListeners();
    return snapshot;
  }

  Future<WorkspaceQuickFixTelemetrySnapshot> recordWorkspaceQuickFixOutcome(
    WorkspaceQuickFixReviewOutcome outcome, {
    int maxOutcomes = 50,
  }) async {
    final resolvedWorkspaceId = outcome.workspaceId.isEmpty
        ? workspaceQuickFixTelemetryWorkspaceId
        : outcome.workspaceId;
    final normalizedOutcome = outcome.workspaceId == resolvedWorkspaceId
        ? outcome
        : WorkspaceQuickFixReviewOutcome(
            workspaceId: resolvedWorkspaceId,
            producerId: outcome.producerId,
            documentId: outcome.documentId,
            diagnosticCode: outcome.diagnosticCode,
            quickFixIndex: outcome.quickFixIndex,
            planId: outcome.planId,
            outcomeKind: outcome.outcomeKind,
            confirmationStatus: outcome.confirmationStatus,
            ready: outcome.ready,
            message: outcome.message,
            timestamp: outcome.timestamp,
            affectedDocumentIds: outcome.affectedDocumentIds,
            missingDocumentIds: outcome.missingDocumentIds,
          );
    final store = workspaceQuickFixTelemetryStore;
    final base =
        _workspaceQuickFixTelemetrySnapshot ??
        WorkspaceQuickFixTelemetrySnapshot(workspaceId: resolvedWorkspaceId);
    var snapshot = base.record(normalizedOutcome, maxOutcomes: maxOutcomes);
    if (store != null) {
      snapshot = await store.recordOutcome(
        outcome: normalizedOutcome,
        maxOutcomes: maxOutcomes,
      );
    }
    _workspaceQuickFixTelemetrySnapshot = snapshot;
    notifyListeners();
    return snapshot;
  }

  SourceControlStatusSnapshot _localDirtySourceControlStatusSnapshot() {
    final changes = dirtyDocumentPaths
        .map(
          (documentId) => SourceControlFileChange(
            path: documentId,
            unstagedStatus: SourceControlFileStatus.modified,
          ),
        )
        .toList(growable: false);
    return SourceControlStatusSnapshot(
      providerKind: SourceControlProviderKind.localDirtyDocuments,
      changes: List<SourceControlFileChange>.unmodifiable(changes),
      message: changes.isEmpty
          ? 'No dirty editor documents.'
          : 'Dirty editor documents.',
    );
  }

  Future<SourceControlStatusSnapshot> refreshSourceControlStatus() async {
    final controller = sourceControlStatusController;
    final snapshot = controller == null
        ? _localDirtySourceControlStatusSnapshot()
        : await controller.refresh();
    appendLog(_sourceControlRefreshMessage(snapshot));
    notifyListeners();
    return snapshot;
  }

  String _sourceControlRefreshMessage(SourceControlStatusSnapshot snapshot) {
    if (!snapshot.available) {
      return snapshot.message.isEmpty
          ? 'Source control refresh failed.'
          : 'Source control refresh failed: ${snapshot.message}';
    }
    return 'Source control refreshed: ${snapshot.changes.length} change(s).';
  }

  Future<SourceControlDiffSnapshot> previewSourceControlDiff(
    String path,
  ) async {
    final controller = sourceControlStatusController;
    final snapshot = controller == null
        ? SourceControlDiffSnapshot(
            providerKind: SourceControlProviderKind.localDirtyDocuments,
            path: path.trim(),
            available: false,
            message:
                'Source control diff skipped: no source control controller is configured.',
          )
        : await controller.previewDiff(path);
    appendLog(_sourceControlDiffPreviewMessage(snapshot));
    notifyListeners();
    return snapshot;
  }

  Future<SourceControlActionResult> runSourceControlAction(
    SourceControlActionRequest request,
  ) async {
    final controller = sourceControlStatusController;
    final result = controller == null
        ? SourceControlActionResult(
            kind: request.kind,
            applied: false,
            paths: request.paths,
            message:
                'Source control action skipped: no source control controller is configured.',
          )
        : await controller.runAction(request);
    appendLog(_sourceControlActionMessage(result));
    if (result.applied) {
      await refreshSourceControlStatus();
    } else {
      notifyListeners();
    }
    return result;
  }

  Future<SourceControlActionResult> stageSourceControlPaths(
    List<String> paths,
  ) {
    return runSourceControlAction(
      SourceControlActionRequest(
        kind: SourceControlActionKind.stage,
        paths: paths,
      ),
    );
  }

  Future<SourceControlActionResult> unstageSourceControlPaths(
    List<String> paths,
  ) {
    return runSourceControlAction(
      SourceControlActionRequest(
        kind: SourceControlActionKind.unstage,
        paths: paths,
      ),
    );
  }

  Future<SourceControlBranchSnapshot> refreshSourceControlBranches() async {
    final controller = sourceControlStatusController;
    final snapshot = controller == null
        ? const SourceControlBranchSnapshot(
            providerKind: SourceControlProviderKind.localDirtyDocuments,
            available: false,
            message:
                'Source control branches skipped: no source control controller is configured.',
          )
        : await controller.refreshBranches();
    appendLog(_sourceControlBranchSnapshotMessage(snapshot));
    notifyListeners();
    return snapshot;
  }

  Future<SourceControlBranchSwitchPlan> planSourceControlBranchSwitch(
    String targetBranch,
  ) async {
    final controller = sourceControlStatusController;
    if (controller == null) {
      final plan = SourceControlBranchSwitchPlan.fromSnapshot(
        snapshot: const SourceControlBranchSnapshot(
          providerKind: SourceControlProviderKind.localDirtyDocuments,
          available: false,
          message:
              'Source control branch switch skipped: no source control controller is configured.',
        ),
        targetBranch: targetBranch,
      );
      appendLog(_sourceControlBranchSwitchPlanMessage(plan));
      notifyListeners();
      return plan;
    }
    if (controller.branchSnapshot == null) {
      await controller.refreshBranches();
    }
    final plan = controller.planBranchSwitch(targetBranch);
    appendLog(_sourceControlBranchSwitchPlanMessage(plan));
    notifyListeners();
    return plan;
  }

  String _sourceControlBranchSnapshotMessage(
    SourceControlBranchSnapshot snapshot,
  ) {
    if (!snapshot.available) {
      return snapshot.message.isEmpty
          ? 'Source control branches unavailable.'
          : 'Source control branches unavailable: ${snapshot.message}';
    }
    return 'Source control branches loaded: ${snapshot.branches.length} branch(es).';
  }

  String _sourceControlBranchSwitchPlanMessage(
    SourceControlBranchSwitchPlan plan,
  ) {
    if (!plan.canRun) {
      return plan.blockedReason.isEmpty
          ? 'Source control branch switch plan blocked.'
          : 'Source control branch switch plan blocked: ${plan.blockedReason}';
    }
    return 'Source control branch switch planned: ${plan.summary}.';
  }

  SourceControlCommitDraft planSourceControlCommitDraft({
    required String message,
    List<String>? selectedPaths,
    bool openDialog = true,
  }) {
    final stagedPaths = sourceControlStatusSnapshot.changes
        .where((change) => change.staged)
        .map((change) => change.path)
        .toList(growable: false);
    final draft = SourceControlCommitDraft(
      workspaceId: workspaceController.activeProject.workspaceRoot,
      message: message.trim(),
      selectedPaths: selectedPaths ?? stagedPaths,
    );
    final plan = draft.toCommitActionPlan();
    _sourceControlCommitDraft = draft;
    _sourceControlCommitDialogOpen = openDialog;
    appendLog(
      plan.canRun
          ? 'Source control commit draft planned: ${plan.summary}.'
          : 'Source control commit draft blocked: ${plan.blockedReason}',
    );
    notifyListeners();
    return draft;
  }

  Future<SourceControlActionResult> confirmSourceControlDiffAction(
    SourceControlDiffConfirmationPlan plan,
  ) {
    if (!plan.canRun) {
      final result = SourceControlActionResult(
        kind: plan.kind,
        applied: false,
        paths: <String>[plan.path],
        message: plan.blockedReason,
      );
      appendLog(_sourceControlActionMessage(result));
      notifyListeners();
      return Future<SourceControlActionResult>.value(result);
    }
    return runSourceControlAction(plan.toActionRequest());
  }

  Future<SourceControlPartialPatchResult> confirmSourceControlHunkAction(
    SourceControlDiffHunkActionPlan plan,
  ) async {
    final controller = sourceControlStatusController;
    final result = controller == null
        ? SourceControlPartialPatchResult(
            kind: plan.kind,
            path: plan.path,
            selectedHunkIndexes: plan.selectedHunkIndexes,
            applied: false,
            message:
                'Source control hunk action skipped: no source control controller is configured.',
          )
        : await controller.runHunkAction(plan);
    appendLog(_sourceControlHunkActionMessage(result));
    if (result.applied) {
      await refreshSourceControlStatus();
    } else {
      notifyListeners();
    }
    return result;
  }

  Future<void> planSourceControlHunkAction(
    SourceControlDiffHunkActionPlan plan,
  ) async {
    if (plan.kind != SourceControlActionKind.discard) {
      await confirmSourceControlHunkAction(plan);
      return;
    }
    final controller = sourceControlStatusController;
    if (controller == null) {
      await confirmSourceControlHunkAction(plan);
      return;
    }
    final confirmation = controller.planHunkDiscardConfirmation(plan);
    appendLog(
      confirmation.readyForDialog
          ? 'Source control hunk discard confirmation planned: ${confirmation.confirmLabel} in ${confirmation.path}.'
          : 'Source control hunk discard confirmation blocked: ${confirmation.blockedReason}',
    );
    notifyListeners();
  }

  Future<SourceControlPartialPatchResult>
  confirmPendingSourceControlHunkDiscard() async {
    final controller = sourceControlStatusController;
    final result = controller == null
        ? const SourceControlPartialPatchResult(
            kind: SourceControlActionKind.discard,
            path: '',
            selectedHunkIndexes: <int>[],
            applied: false,
            message:
                'Source control hunk discard skipped: no source control controller is configured.',
          )
        : await controller.confirmPendingHunkDiscard();
    appendLog(_sourceControlHunkActionMessage(result));
    if (result.applied) {
      await refreshSourceControlStatus();
    } else {
      notifyListeners();
    }
    return result;
  }

  String _sourceControlHunkActionMessage(
    SourceControlPartialPatchResult result,
  ) {
    if (result.message.isNotEmpty) {
      return result.message;
    }
    return result.applied
        ? 'Source control hunk action applied: ${result.kind.wireValue} ${result.selectedHunkIndexes.length} hunk(s).'
        : 'Source control hunk action failed: ${result.kind.wireValue} ${result.selectedHunkIndexes.length} hunk(s).';
  }

  Future<void> rerunFailedTests() async {
    final controller = testingSessionController;
    if (controller == null || controller.runProvider == null) {
      await executeCommand(AppCommandId.runTests);
      return;
    }
    final result = await controller.rerunFailed(
      workspaceRoot: workspaceController.activeProject.workspaceRoot,
    );
    appendLog(_testRunResultMessage('Rerun failed tests', result));
    notifyListeners();
  }

  Future<void> debugFailedTests() async {
    final controller = testingSessionController;
    if (controller == null || controller.runProvider == null) {
      await rerunFailedTests();
      return;
    }
    final result = await controller.rerunFailed(
      workspaceRoot: workspaceController.activeProject.workspaceRoot,
      debug: true,
    );
    appendLog(_testRunResultMessage('Debug failed tests', result));
    notifyListeners();
  }

  TestRunConfiguration? _testRunConfigurationForId(String configurationId) {
    final normalizedId = configurationId.trim();
    if (normalizedId.isEmpty) {
      return null;
    }
    for (final configuration in testRunConfigurationSet.configurations) {
      if (configuration.id == normalizedId) {
        return configuration;
      }
    }
    return null;
  }

  void selectTestRunConfiguration(TestRunConfiguration configuration) {
    _selectedTestRunConfigurationId = configuration.id;
    appendLog('Selected test run configuration ${configuration.id}.');
    notifyListeners();
  }

  Future<void> runTestConfiguration(TestRunConfiguration configuration) async {
    final controller = testingSessionController;
    if (controller == null) {
      await executeCommand(AppCommandId.runTests);
      return;
    }
    final result = await controller.runConfiguration(configuration);
    appendLog(_testRunResultMessage('Run test configuration', result));
    notifyListeners();
  }

  Future<void> debugTestConfiguration(
    TestRunConfiguration configuration,
  ) async {
    final debugConfiguration = configuration.debug
        ? configuration
        : configuration.copyWith(debug: true);
    final route = const TestDebugLaunchRoutePlanner().plan(debugConfiguration);
    runtimeOutputBuffer.addEvent(
      RuntimeOutputEvent(
        channelId: route.handoff.outputChannelId ?? 'debug.tests',
        label: 'Test Debug',
        kind: RuntimeOutputChannelKind.debug,
        message:
            '${route.ready ? 'ready' : 'blocked'} ${route.profileId}: ${route.handoff.plan.message}',
        timestamp: DateTime.now().toUtc(),
        metadata: <String, Object?>{
          'testDebugLaunchRoute': route.toJson(),
          'configuration': debugConfiguration.toJson(),
        },
      ),
    );
    final controller = testingSessionController;
    if (controller == null) {
      appendLog('Debug test configuration routed: ${route.profileId}.');
      notifyListeners();
      return;
    }
    final result = await controller.debugConfiguration(debugConfiguration);
    appendLog(_testRunResultMessage('Debug test configuration', result));
    notifyListeners();
  }

  Future<void> cancelFailedTestDebug(Map<String, Object?> failedTest) async {
    final controller = testingSessionController;
    if (controller == null) {
      appendLog('Failed-test debug cancellation skipped: no test controller.');
      notifyListeners();
      return;
    }
    final route = await controller.cancelFailedTestDebug(
      failedTest: failedTest,
    );
    appendLog(route.message);
    notifyListeners();
  }

  String _testRunResultMessage(String action, TestRunResult result) {
    return '$action: ${result.status.wireValue} · ${result.message}';
  }

  bool _agentTestingCommandApplied(TestRunResult? result) {
    return result != null && result.status != TestRunStatus.notRun;
  }

  Map<String, Object?> _agentTestingCommandMetadata(TestRunResult? result) {
    return <String, Object?>{
      if (result != null) 'testResult': result.toJson(),
      'failedRetryHistory': failedTestRetryHistory
          .map((record) => record.toJson())
          .toList(growable: false),
    };
  }

  Map<String, Object?> _testConfigurationCommandMetadata({
    TestRunConfiguration? configuration,
    TestRunResult? result,
  }) {
    return <String, Object?>{
      'availableConfigurationIds': testRunConfigurationSet.configurations
          .map((configuration) => configuration.id)
          .toList(growable: false),
      if (configuration != null) 'configuration': configuration.toJson(),
      ..._agentTestingCommandMetadata(result),
    };
  }

  String _sourceControlActionMessage(SourceControlActionResult result) {
    final action = result.kind.wireValue;
    if (!result.applied) {
      return result.message.isEmpty
          ? 'Source control $action failed.'
          : 'Source control $action failed: ${result.message}';
    }
    return result.message.isEmpty
        ? 'Source control $action applied to ${result.paths.length} path(s).'
        : 'Source control $action applied: ${result.message}';
  }

  String _sourceControlDiffPreviewMessage(SourceControlDiffSnapshot snapshot) {
    if (!snapshot.available) {
      return snapshot.message.isEmpty
          ? 'Source control diff preview failed for ${snapshot.path}.'
          : 'Source control diff preview failed for ${snapshot.path}: ${snapshot.message}';
    }
    return 'Source control diff previewed for ${snapshot.path}: ${snapshot.lineCount} line(s).';
  }

  Future<Map<String, Object?>> collectAgentCodingCheckpoint() async {
    final diagnosticsSnapshot = await refreshWorkspaceDiagnostics();
    final sourceControlSnapshot = await refreshSourceControlStatus();
    final projectLanguage = await collectProjectLanguageContext();
    final profileManifest = await refreshAgentProviderProfileManifest();
    final workspaceEditPreview = await previewFirstProjectWorkspaceQuickFix();
    final changedPath = sourceControlSnapshot.changes.isNotEmpty
        ? sourceControlSnapshot.changes.first.path
        : dirtyDocumentPaths.isNotEmpty
        ? dirtyDocumentPaths.first
        : '';
    final diffSnapshot = changedPath.isEmpty
        ? null
        : await previewSourceControlDiff(changedPath);
    final context = agentSessionContext;
    final metadata = <String, Object?>{
      'agentContextSchemaVersion': context.schemaVersion,
      'ideCapabilities': context.ideCapabilities.toJson(),
      'ideCapabilityClosure': context.ideCapabilityClosure.toJson(),
      'workspaceRoot': workspaceController.activeProject.workspaceRoot,
      'workspaceDiagnostics': diagnosticsSnapshot.toJson(),
      'sourceControl': sourceControlSnapshot.toJson(),
      'projectLanguage': projectLanguage,
      'languageServiceStatus': context.language.serviceStatus?.toJson(),
      if (context.language.semanticFeatureMatrix != null)
        'semanticFeatureMatrix': context.language.semanticFeatureMatrix!
            .toJson(),
      'codeActionFactCount':
          context.language.semanticFeatureMatrix?.codeActionFactCount ?? 0,
      'testing': context.testing.toJson(),
      'savedProviderProfileCount': profileManifest.entries.length,
      if (profileManifest.entries.isNotEmpty)
        'savedProviderProfiles': profileManifest.entries
            .map((profile) => profile.toJson())
            .toList(growable: false),
      'dirtyDocumentIds': dirtyDocumentPaths,
      'openDocumentIds': workspaceController.openFilePaths,
      if (diffSnapshot != null) 'sourceControlDiff': diffSnapshot.toJson(),
      if (context.workspace.sourceControlContext != null)
        'sourceControlContext': context.workspace.sourceControlContext!
            .toJson(),
      if (workspaceEditPreview != null)
        'workspaceEditPreview': workspaceEditPreview.toJson(),
    };
    appendLog(
      'Agent coding checkpoint collected: '
      '${diagnosticsSnapshot.totalCount} diagnostic(s), '
      '${sourceControlSnapshot.changes.length} source change(s), '
      '${projectLanguage['referenceCount'] ?? 0} project reference(s), '
      '${context.language.semanticFeatureMatrix?.codeActionFactCount ?? 0} code action fact(s), '
      '${workspaceEditPreview?.editCount ?? 0} workspace edit preview edit(s), '
      '${context.ideCapabilityClosure.runtimeMaturityBlockerCapabilityIds.length} maturity blocker(s).',
    );
    notifyListeners();
    return metadata;
  }

  Future<Map<String, Object?>> collectProjectLanguageContext() async {
    final documents = await _loadProjectLanguageDocuments();
    final documentId = editorController.document.documentId;
    final offset = editorController.selection.extentOffset;
    for (final document in documents) {
      if (document.documentId != documentId) {
        _cacheDocument(document.documentId, document);
      }
    }
    final hover = projectLanguageService.hoverAt(
      documents: documents,
      documentId: documentId,
      offset: offset,
    );
    final definitions = projectLanguageService.definitionsAt(
      documents: documents,
      documentId: documentId,
      offset: offset,
    );
    final references =
        projectLanguageService
            .referencesAt(
              documents: documents,
              documentId: documentId,
              offset: offset,
            )
            .toList(growable: false)
          ..sort(_compareProjectSymbolReferences);
    final completions = projectLanguageService.completionsAt(
      documents: documents,
      documentId: documentId,
      offset: offset,
    );
    const syntaxHighlighter = StyioSyntaxHighlighter();
    const syntaxValidator = StyioSyntaxValidator();
    final syntaxValidationReport = syntaxValidator.validateWithReport(
      documentId: documentId,
      source: editorController.document.text,
      tokens: syntaxHighlighter.tokenize(editorController.document.text),
    );
    final analysis = projectLanguageService.analyzeProject(documents);
    final fixes = projectLanguageService
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        );
    final status = languageServiceStatus.value;
    final semanticFeatureMatrix = AgentSemanticFeatureMatrixContext.fromMatrix(
      editorController.semanticFeatureMatrix,
    ).toJson();
    final syntaxValidationAuthority = <String, Object?>{
      'preferredSource': status.syntaxValidationReady
          ? 'styio-service'
          : 'vityo-ide-syntax-contract',
      'fallbackSource': 'vityo-ide-syntax-contract',
      'fallbackActive': !status.syntaxValidationReady,
      'conflictPolicy':
          'Prefer StyioService syntax diagnostics when syntaxValidationReady is true; use the IDE syntax contract report only as fallback evidence.',
    };
    final suggestedCommandIds = <String>[
      if (status.refreshRecommended) AppCommandId.refreshLanguageService.name,
      if (definitions.isNotEmpty) AppCommandId.goToDefinition.name,
      if (references.isNotEmpty) AppCommandId.nextReference.name,
      if (fixes.isNotEmpty) AppCommandId.previewQuickFix.name,
      if (fixes.isNotEmpty) AppCommandId.applyQuickFix.name,
    ];
    final metadata = <String, Object?>{
      'documentId': documentId,
      'offset': offset,
      'documentCount': documents.length,
      'languageServiceStatus': status.toJson(),
      'semanticFeatureMatrix': semanticFeatureMatrix,
      'syntaxValidationAuthority': syntaxValidationAuthority,
      'syntaxValidationReport': syntaxValidationReport.toJson(),
      if (_lastStyioServiceDaemonRestartDispatch != null)
        'styioServiceDaemonRestartDispatch':
            _lastStyioServiceDaemonRestartDispatch!.toJson(),
      if (suggestedCommandIds.isNotEmpty)
        'suggestedCommandIds': suggestedCommandIds,
      'diagnosticCount': analysis.diagnostics.length,
      'diagnostics': analysis.diagnostics
          .take(50)
          .map(_projectDiagnosticToJson)
          .toList(growable: false),
      'workspaceQuickFixCount': fixes.length,
      'workspaceQuickFixes': fixes
          .take(20)
          .map(_projectWorkspaceFixToJson)
          .toList(growable: false),
      if (hover != null)
        'hover': <String, Object?>{
          'label': hover.label,
          'definitionCount': hover.definitions.length,
        },
      'definitionCount': definitions.length,
      'definitions': definitions
          .take(20)
          .map(_projectSymbolDefinitionToJson)
          .toList(growable: false),
      'referenceCount': references.length,
      'references': references
          .take(50)
          .map(_projectSymbolReferenceToJson)
          .toList(growable: false),
      'completionCount': completions.length,
      'completions': completions
          .take(50)
          .map(_completionItemToJson)
          .toList(growable: false),
    };
    appendLog(
      'Project language context collected: '
      '${definitions.length} definition(s), '
      '${references.length} reference(s), '
      '${completions.length} completion(s), '
      '${analysis.diagnostics.length} diagnostic(s), '
      '${fixes.length} quick fix candidate(s).',
    );
    _recordSemanticTokensTelemetry(documentId: documentId);
    notifyListeners();
    return metadata;
  }

  Map<String, Object?> _projectDiagnosticToJson(
    StyioProjectDiagnostic diagnostic,
  ) {
    return <String, Object?>{
      'documentId': diagnostic.documentId,
      'severity': diagnostic.diagnostic.severity.name,
      'code': diagnostic.diagnostic.code,
      'message': diagnostic.diagnostic.message,
      'range': <String, int>{
        'start': diagnostic.diagnostic.range.start,
        'end': diagnostic.diagnostic.range.end,
      },
    };
  }

  Map<String, Object?> _projectWorkspaceFixToJson(
    StyioProjectWorkspaceFix fix,
  ) {
    return <String, Object?>{
      'label': fix.label,
      if (fix.detail.isNotEmpty) 'detail': fix.detail,
      'affectedDocumentIds': fix.editsByDocument.keys.toList(growable: false),
      'editCount': fix.editsByDocument.values.fold<int>(
        0,
        (count, edits) => count + edits.length,
      ),
    };
  }

  Future<List<StyioProjectWorkspaceFix>>
  collectProjectWorkspaceQuickFixes() async {
    final documents = await _loadProjectLanguageDocuments();
    for (final document in documents) {
      if (document.documentId != editorController.document.documentId) {
        _cacheDocument(document.documentId, document);
      }
    }
    final analysis = projectLanguageService.analyzeProject(documents);
    final fixes = projectLanguageService
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        );
    appendLog(
      'Project workspace quick fixes collected: ${fixes.length} candidate(s).',
    );
    notifyListeners();
    return fixes;
  }

  void _publishDiagnosticActionTelemetry({
    required String action,
    required bool succeeded,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final timestamp = DateTime.now().toUtc();
    runtimeOutputBuffer.addEvent(
      RuntimeOutputEvent(
        channelId: 'diagnostics.activity',
        label: 'Diagnostics Activity',
        kind: RuntimeOutputChannelKind.languageService,
        message: message,
        timestamp: timestamp,
        metadata: <String, Object?>{
          'action': action,
          'succeeded': succeeded,
          'activeDocumentPath': _activeDocumentPath,
          ...metadata,
        },
      ),
    );
    final semanticKind = switch (action) {
      'previewQuickFix' =>
        SemanticSnapshotTelemetryEventKind.codeActionDiscovery,
      'applyQuickFix' => SemanticSnapshotTelemetryEventKind.codeActionApply,
      _ => null,
    };
    if (semanticKind == null) {
      return;
    }
    unawaited(
      recordSemanticPanelEvent(
        SemanticSnapshotPanelEvent(
          target: SemanticSnapshotPanelEventTarget.problems,
          kind: semanticKind,
          documentId: _activeDocumentPath,
          message: message,
          payload: <String, Object?>{
            'action': action,
            'succeeded': succeeded,
            ...metadata,
          },
          timestamp: timestamp,
        ),
      ),
    );
  }

  Future<bool> applyFirstProjectWorkspaceQuickFix({
    String? expectedPreviewPlanId,
  }) async {
    final fixes = await collectProjectWorkspaceQuickFixes();
    if (fixes.isEmpty) {
      _lastWorkspaceEditApplyResult = null;
      appendLog('Project workspace quick fix skipped: no deterministic fix.');
      notifyListeners();
      return false;
    }
    final fix = fixes.first;
    final plan = _workspaceEditPlanForProjectFix(fix);
    if (expectedPreviewPlanId != null && plan.id != expectedPreviewPlanId) {
      final preview = plan.preview(_agentWorkspaceDocumentSamples);
      final confirmationPlan = WorkspaceEditConfirmationPlan.fromPreview(
        preview,
      );
      const result = WorkspaceEditApplicationResult(
        applied: false,
        message:
            'Project workspace quick fix skipped: preview is stale. Run previewQuickFix again before applying.',
      );
      _lastWorkspaceEditPreview = preview;
      _recordWorkspaceEditApplyResult(
        confirmationPlan: confirmationPlan,
        preview: preview,
        result: result,
      );
      appendLog(result.message);
      notifyListeners();
      return false;
    }
    return _applyProjectWorkspaceFix(fix, plan: plan);
  }

  Future<WorkspaceEditPreview?> previewFirstProjectWorkspaceQuickFix() async {
    final documents = await _loadProjectLanguageDocuments();
    final analysis = projectLanguageService.analyzeProject(documents);
    final fixes = projectLanguageService
        .workspaceQuickFixesForProjectDiagnostics(
          documents: documents,
          diagnostics: analysis.diagnostics,
          analysis: analysis,
        );
    if (fixes.isEmpty) {
      _lastWorkspaceEditPreview = null;
      _lastWorkspaceEditApplyResult = null;
      appendLog(
        'Project workspace quick fix preview skipped: no deterministic fix.',
      );
      notifyListeners();
      return null;
    }
    final preview = _workspaceEditPlanForProjectFix(
      fixes.first,
    ).preview(documents);
    _lastWorkspaceEditPreview = preview;
    _lastWorkspaceEditApplyResult = null;
    appendLog(
      'Project workspace quick fix previewed: ${preview.summary} '
      '(${preview.editCount} edit(s)).',
    );
    notifyListeners();
    return preview;
  }

  Future<bool> _applyProjectWorkspaceFix(
    StyioProjectWorkspaceFix fix, {
    WorkspaceEditPlan? plan,
  }) async {
    final effectivePlan = plan ?? _workspaceEditPlanForProjectFix(fix);
    final preview = effectivePlan.preview(_agentWorkspaceDocumentSamples);
    final confirmationPlan = WorkspaceEditConfirmationPlan.fromPreview(preview);
    _lastWorkspaceEditPreview = preview;
    _lastWorkspaceEditApplyResult = null;
    final activeDocumentId = editorController.document.documentId;
    final activeEdits =
        fix.editsByDocument[activeDocumentId] ?? const <FormattingEdit>[];
    final normalizedActiveEdits = normalizeFormattingEditsForDocument(
      documentLength: editorController.document.length,
      edits: activeEdits,
    );
    if (normalizedActiveEdits.length != activeEdits.length) {
      _recordWorkspaceEditApplyResult(
        confirmationPlan: confirmationPlan,
        preview: preview,
        result: const WorkspaceEditApplicationResult(
          applied: false,
          message:
              'Project workspace quick fix skipped: active document edits are invalid or overlapping.',
        ),
      );
      appendLog(
        'Project workspace quick fix skipped: active document edits are invalid or overlapping.',
      );
      notifyListeners();
      return false;
    }
    final inactiveEditsByDocument = <String, List<FormattingEdit>>{};
    for (final entry in fix.editsByDocument.entries) {
      if (entry.key == activeDocumentId) {
        continue;
      }
      inactiveEditsByDocument[entry.key] = entry.value;
    }

    var inactiveEditCount = 0;
    var appliedInactiveDocumentIds = const <String>[];
    if (inactiveEditsByDocument.isNotEmpty) {
      final result =
          await WorkspaceEditApplier(
            workspaceDocumentStore: workspaceDocumentStore,
          ).apply(
            _workspaceEditPlanForProjectFix(
              StyioProjectWorkspaceFix(
                label: fix.label,
                detail: fix.detail,
                editsByDocument: inactiveEditsByDocument,
              ),
            ),
          );
      if (!result.applied) {
        _recordWorkspaceEditApplyResult(
          confirmationPlan: confirmationPlan,
          preview: preview,
          result: result,
        );
        appendLog('Project workspace quick fix skipped: ${result.message}');
        notifyListeners();
        return false;
      }
      inactiveEditCount = result.appliedEditCount;
      appliedInactiveDocumentIds = result.appliedDocumentIds;
      for (final documentId in result.appliedDocumentIds) {
        _documentCache.remove(documentId);
        _documentCursorOffsets.remove(documentId);
        _documentSelectionAnchors.remove(documentId);
      }
    }

    if (normalizedActiveEdits.isNotEmpty) {
      editorController.applyFormattingEdits(normalizedActiveEdits);
      _cacheDocument(activeDocumentId, editorController.document);
      _dirtyDocumentPaths.add(activeDocumentId);
    }
    final editCount = inactiveEditCount + normalizedActiveEdits.length;
    final appliedDocumentIds = <String>{
      ...appliedInactiveDocumentIds,
      if (normalizedActiveEdits.isNotEmpty) activeDocumentId,
    }.toList(growable: false)..sort();
    final applicationResult = WorkspaceEditApplicationResult(
      applied: editCount > 0,
      message:
          'Project workspace quick fix applied: ${fix.label} ($editCount edit(s)).',
      appliedEditCount: editCount,
      appliedDocumentIds: appliedDocumentIds,
    );
    _recordWorkspaceEditApplyResult(
      confirmationPlan: confirmationPlan,
      preview: preview,
      result: applicationResult,
    );
    appendLog(applicationResult.message);
    notifyListeners();
    return editCount > 0;
  }

  void _recordWorkspaceEditApplyResult({
    required WorkspaceEditConfirmationPlan confirmationPlan,
    required WorkspaceEditPreview preview,
    required WorkspaceEditApplicationResult result,
  }) {
    _lastWorkspaceEditApplyResult =
        WorkspaceEditApplyResultViewModel.fromTelemetry(
          confirmationPlan: confirmationPlan,
          telemetry: WorkspaceEditReviewResultTelemetry.fromApplicationResult(
            confirmationPlan: confirmationPlan,
            result: result,
          ),
          diffWindow: preview.diffWindow(
            documentLimit: 3,
            fileOperationLimit: 3,
          ),
        );
  }

  WorkspaceEditPlan _workspaceEditPlanForProjectFix(
    StyioProjectWorkspaceFix fix,
  ) {
    return WorkspaceEditPlan(
      id: 'project-workspace-fix-${_projectWorkspaceFixFingerprint(fix)}',
      summary: fix.label,
      source: WorkspaceEditSource.codeAction,
      editsByDocument: fix.editsByDocument,
    );
  }

  String _projectWorkspaceFixFingerprint(StyioProjectWorkspaceFix fix) {
    final buffer = StringBuffer(fix.label.trim());
    final entries = fix.editsByDocument.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in entries) {
      buffer.write('|');
      buffer.write(entry.key);
      for (final edit in entry.value) {
        buffer
          ..write('@')
          ..write(edit.range.start)
          ..write('-')
          ..write(edit.range.end)
          ..write(':')
          ..write(edit.newText.length)
          ..write(':')
          ..write(edit.newText);
      }
    }
    return _stableHexFingerprint(buffer.toString());
  }

  String _stableHexFingerprint(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  Map<String, Object?> _projectSymbolDefinitionToJson(
    StyioProjectSymbolDefinition definition,
  ) {
    return <String, Object?>{
      'documentId': definition.documentId,
      'kind': definition.kind.name,
      'name': definition.name,
      'range': _sourceRangeToJson(definition.range),
      if (definition.type != null) 'type': definition.type,
    };
  }

  Map<String, Object?> _projectSymbolReferenceToJson(
    StyioProjectSymbolReference reference,
  ) {
    return <String, Object?>{
      'documentId': reference.documentId,
      'name': reference.name,
      'range': _sourceRangeToJson(reference.range),
      'isDefinition': reference.isDefinition,
    };
  }

  Map<String, Object?> _completionItemToJson(CompletionItem completion) {
    return <String, Object?>{
      'label': completion.label,
      'kind': completion.kind.name,
      'insertText': completion.insertText,
      if (completion.detail.isNotEmpty) 'detail': completion.detail,
      if (completion.documentation.isNotEmpty)
        'documentation': completion.documentation,
      if (completion.replacementRange != null)
        'replacementRange': _sourceRangeToJson(completion.replacementRange!),
    };
  }

  Map<String, Object?> _sourceRangeToJson(SourceRange range) {
    return <String, Object?>{'start': range.start, 'end': range.end};
  }

  WorkspaceDiagnosticsRequest _createWorkspaceDiagnosticsRequest() {
    final documentsById = <String, DocumentState>{
      editorController.document.documentId: editorController.document,
      for (final document in _agentWorkspaceDocumentSamples)
        document.documentId: document,
    };
    final documentIds = <String>{
      ...workspaceController.openFilePaths,
      editorController.document.documentId,
    }.toList(growable: false);
    return WorkspaceDiagnosticsRequest(
      documentIds: documentIds,
      activeDocumentId: editorController.document.documentId,
      documents: documentsById.values.toList(growable: false),
    );
  }

  Future<WorkspaceDiagnosticsSnapshot> refreshWorkspaceDiagnostics() async {
    final controller = workspaceDiagnosticsController;
    final snapshot = controller == null
        ? const WorkspaceDiagnosticsSnapshot(
            providerId: 'unavailable',
            diagnostics: <WorkspaceDiagnostic>[],
            message:
                'Workspace diagnostics refresh skipped: no provider is configured.',
          )
        : await controller.refresh(_createWorkspaceDiagnosticsRequest());
    appendLog(_workspaceDiagnosticsRefreshMessage(snapshot));
    _recordWorkspaceDiagnosticsSemanticTelemetry(snapshot);
    notifyListeners();
    return snapshot;
  }

  String _workspaceDiagnosticsRefreshMessage(
    WorkspaceDiagnosticsSnapshot snapshot,
  ) {
    if (snapshot.message.isNotEmpty && snapshot.providerId == 'unavailable') {
      return snapshot.message;
    }
    return 'Workspace diagnostics refreshed: ${snapshot.totalCount} problem(s).';
  }

  void _recordWorkspaceDiagnosticsSemanticTelemetry(
    WorkspaceDiagnosticsSnapshot snapshot,
  ) {
    unawaited(
      recordSemanticRuntimeOutputEvent(
        const SemanticSnapshotEventBridge().diagnosticsSnapshotEvent(
          documentId: editorController.document.documentId,
          providerId: snapshot.providerId,
          diagnosticCount: snapshot.totalCount,
          hasErrors: snapshot.hasErrors,
          severityCounts: snapshot.severityCounts,
          documentCount: snapshot.documentIds.length,
          sourceCount: snapshot.sourceGroups.length,
          timestamp: DateTime.now().toUtc(),
          message: _workspaceDiagnosticsRefreshMessage(snapshot),
          payload: <String, Object?>{
            'source': 'workspace-diagnostics',
            'activeDocumentId': editorController.document.documentId,
          },
        ),
      ),
    );
  }

  void _recordSemanticTokensTelemetry({required String documentId}) {
    final analysis = editorController.analysis;
    unawaited(
      recordSemanticRuntimeOutputEvent(
        const SemanticSnapshotEventBridge().semanticTokensEvent(
          documentId: documentId,
          semanticSpanCount: analysis.semanticSpans.length,
          semanticBlockCount: analysis.semanticBlocks.length,
          documentSymbolCount: analysis.documentSymbols.length,
          inlayHintCount: analysis.inlayHints.length,
          diagnosticCount: analysis.diagnostics.length,
          timestamp: DateTime.now().toUtc(),
          payload: const <String, Object?>{'source': 'editor-analysis'},
        ),
      ),
    );
  }

  DocumentResourceBindingSnapshot get editorFileBindingSnapshot =>
      _editorFileBinding.snapshot;
  DependencySourceCommandResult? get lastDependencySourceCommand =>
      _lastDependencySourceCommand;
  DeploymentCommandResult? get lastDeploymentCommand => _lastDeploymentCommand;
  ToolchainCommandResult? get lastToolchainCommand => _lastToolchainCommand;
  ToolchainInstallPlan? get lastToolchainInstallPlan =>
      _lastToolchainInstallPlan;
  ToolchainInstallExecutionResult? get lastToolchainInstallExecutionResult =>
      _lastToolchainInstallExecutionResult;
  ToolchainManagerBootstrapSummary? get toolchainBootstrapSummary =>
      _toolchainBootstrapSummary;
  ToolchainBootstrapActionDispatchResult?
  get lastToolchainBootstrapActionDispatch =>
      _lastToolchainBootstrapActionDispatch;
  WorkspaceFileCloseRequestResult? get lastCloseRequestResult =>
      _lastCloseRequestResult;
  WorkspaceEditPreview? get lastWorkspaceEditPreview =>
      _lastWorkspaceEditPreview;
  WorkspaceEditApplyResultViewModel? get lastWorkspaceEditApplyResult =>
      _lastWorkspaceEditApplyResult;
  WorkspaceQuickFixTelemetrySnapshot? get workspaceQuickFixTelemetrySnapshot =>
      _workspaceQuickFixTelemetrySnapshot;
  WorkspaceReplacePreview? get lastWorkspaceReplacePreview =>
      _lastWorkspaceReplacePreview;
  EditorCloseRequestSurface? get closeRequestSurface {
    final result = _lastCloseRequestResult;
    if (result == null) {
      return null;
    }
    if (result.requiresUserChoice &&
        !_dirtyDocumentPaths.contains(result.filePath)) {
      return null;
    }
    return EditorCloseRequestSurface(
      status: switch (result.status) {
        WorkspaceFileCloseRequestStatus.closed =>
          EditorCloseRequestSurfaceStatus.closed,
        WorkspaceFileCloseRequestStatus.blockedUnsavedChanges =>
          EditorCloseRequestSurfaceStatus.blockedUnsavedChanges,
        WorkspaceFileCloseRequestStatus.notOpen =>
          EditorCloseRequestSurfaceStatus.notOpen,
      },
      filePath: result.filePath,
      message: result.message,
      canSave: result.canSave,
      canDiscard: result.canDiscard,
      canSwitchToFile: result.canSwitchToFile,
    );
  }

  ToolchainInstallPlanSurface? get toolchainInstallPlanSurface {
    final plan = _lastToolchainInstallPlan;
    if (plan == null) {
      return null;
    }
    return ToolchainInstallPlanSurface.fromPlan(plan);
  }

  bool get _activeFileHasUnsavedChanges {
    switch (_editorFileBinding.snapshot.state) {
      case DocumentResourceBindingState.boundDirty:
      case DocumentResourceBindingState.conflicted:
        return true;
      case DocumentResourceBindingState.unbound:
      case DocumentResourceBindingState.binding:
      case DocumentResourceBindingState.boundClean:
      case DocumentResourceBindingState.externalChanged:
      case DocumentResourceBindingState.deletedOnDisk:
      case DocumentResourceBindingState.readonly:
      case DocumentResourceBindingState.providerUnavailable:
        return false;
    }
  }

  bool _pathHasUnsavedChanges(String filePath) {
    if (filePath == _activeDocumentPath) {
      return _activeFileHasUnsavedChanges ||
          _dirtyDocumentPaths.contains(filePath);
    }
    return _dirtyDocumentPaths.contains(filePath);
  }

  void _syncDirtyStateForPath(
    String filePath,
    DocumentResourceBindingSnapshot snapshot,
  ) {
    switch (snapshot.state) {
      case DocumentResourceBindingState.boundDirty:
      case DocumentResourceBindingState.conflicted:
        _dirtyDocumentPaths.add(filePath);
        return;
      case DocumentResourceBindingState.unbound:
      case DocumentResourceBindingState.binding:
      case DocumentResourceBindingState.boundClean:
      case DocumentResourceBindingState.externalChanged:
      case DocumentResourceBindingState.deletedOnDisk:
      case DocumentResourceBindingState.readonly:
      case DocumentResourceBindingState.providerUnavailable:
        _dirtyDocumentPaths.remove(filePath);
        return;
    }
  }

  void _restoreSelectionForDocument(String documentId) {
    final cursorOffset = _documentCursorOffsets[documentId];
    final selectionAnchor = _documentSelectionAnchors[documentId];
    if (cursorOffset != null && selectionAnchor != null) {
      editorController.selectRange(
        baseOffset: selectionAnchor,
        extentOffset: cursorOffset,
      );
    } else if (cursorOffset != null) {
      editorController.selectCollapsed(cursorOffset);
    }
  }

  void _rememberSelectionForPath(String documentId) {
    if (_suppressSelectionTracking) {
      return;
    }
    _documentCursorOffsets[documentId] =
        editorController.selection.extentOffset;
    _documentSelectionAnchors[documentId] =
        editorController.selection.baseOffset;
  }

  void _cacheDocument(String documentId, DocumentState document) {
    _documentCache.remove(documentId);
    _documentCache[documentId] = document;
    _evictDocumentCacheIfNeeded();
  }

  void _evictDocumentCacheIfNeeded() {
    if (documentCacheLimit <= 0) {
      return;
    }
    while (_documentCache.length > documentCacheLimit) {
      String? evictableDocumentId;
      for (final documentId in _documentCache.keys) {
        if (documentId == _activeDocumentPath ||
            workspaceController.openFilePaths.contains(documentId) ||
            _dirtyDocumentPaths.contains(documentId)) {
          continue;
        }
        evictableDocumentId = documentId;
        break;
      }
      if (evictableDocumentId == null) {
        return;
      }
      _documentCache.remove(evictableDocumentId);
      _documentCursorOffsets.remove(evictableDocumentId);
      _documentSelectionAnchors.remove(evictableDocumentId);
    }
  }

  void _handleAgentCodingSessionChanged() {
    notifyListeners();
  }

  Future<AgentCodePatchApplicationResult?> applyAgentPendingPatch() async {
    final result = await agentCodingController.applyPendingWorkspacePatch(
      AgentWorkspaceCodePatchApplier(
        editorController: editorController,
        workspaceDocumentStore: workspaceDocumentStore,
        dirtyDocumentIds: dirtyDocumentPaths,
        sampledDocumentIds: _agentWorkspaceDocumentSamples.map(
          (document) => document.documentId,
        ),
      ),
    );
    _syncAgentPatchDocumentCache(result);
    appendLog(result?.message ?? 'No pending agent patch is available.');
    return result;
  }

  Future<AgentCodePatchApplicationResult> applyAgentWorkspacePatchTool(
    AgentCodePatch patch,
  ) async {
    final result = await AgentWorkspaceCodePatchApplier(
      editorController: editorController,
      workspaceDocumentStore: workspaceDocumentStore,
      dirtyDocumentIds: dirtyDocumentPaths,
      sampledDocumentIds: _agentWorkspaceDocumentSamples.map(
        (document) => document.documentId,
      ),
    ).apply(patch);
    _syncAgentPatchDocumentCache(result);
    appendLog(result.message);
    return result;
  }

  Future<bool> renameSymbolAtSelection(String newName) async {
    final documents = await _loadProjectLanguageDocuments();
    final projectPreview = projectLanguageService.renamePreviewAt(
      documents: documents,
      documentId: editorController.document.documentId,
      offset: editorController.selection.extentOffset,
      newName: newName,
    );
    if (projectPreview != null) {
      final applied = await _applyProjectRenamePreview(projectPreview);
      await _recordRenameSafetyTelemetry(
        safe: applied,
        newName: projectPreview.newName,
        targetName: projectPreview.oldName,
        message: applied
            ? 'Rename ${projectPreview.oldName} to ${projectPreview.newName} is safe.'
            : 'Rename ${projectPreview.oldName} to ${projectPreview.newName} is blocked.',
        metadata: <String, Object?>{
          'editCount': projectPreview.editCount,
          'documentCount': projectPreview.editsByDocument.length,
          if (projectPreview.conflict != null)
            'conflict': projectPreview.conflict,
        },
      );
      return applied;
    }
    if (editorController.applyRename(newName)) {
      _cacheDocument(_activeDocumentPath, editorController.document);
      _dirtyDocumentPaths.add(_activeDocumentPath);
      appendLog('Rename symbol applied at editor selection.');
      await _recordRenameSafetyTelemetry(
        safe: true,
        newName: newName,
        message: 'Rename to $newName is safe at editor selection.',
        metadata: const <String, Object?>{'scope': 'editor-selection'},
      );
      notifyListeners();
      return true;
    }
    appendLog('Rename symbol skipped: no safe rename available at selection.');
    await _recordRenameSafetyTelemetry(
      safe: false,
      newName: newName,
      message: 'Rename to $newName is blocked at editor selection.',
      metadata: const <String, Object?>{'scope': 'editor-selection'},
    );
    notifyListeners();
    return false;
  }

  Future<void> _recordRenameSafetyTelemetry({
    required bool safe,
    required String newName,
    required String message,
    String targetName = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return recordSemanticPanelEvent(
      SemanticSnapshotPanelEvent(
        target: SemanticSnapshotPanelEventTarget.refactor,
        kind: SemanticSnapshotTelemetryEventKind.renameSafety,
        documentId: _activeDocumentPath,
        message: message,
        payload: <String, Object?>{
          'safe': safe,
          if (targetName.isNotEmpty) 'targetName': targetName,
          'newName': newName,
          ...metadata,
        },
        timestamp: DateTime.now().toUtc(),
      ),
    );
  }

  Future<bool> _applyProjectRenamePreview(
    StyioProjectRenamePreview preview,
  ) async {
    if (preview.hasConflict) {
      appendLog(
        'Project rename skipped: ${preview.conflict ?? 'rename conflict'}.',
      );
      notifyListeners();
      return false;
    }
    if (preview.editCount == 0) {
      appendLog('Project rename skipped: no edits were produced.');
      notifyListeners();
      return false;
    }

    final activeDocumentId = editorController.document.documentId;
    final activeEdits = _renameFormattingEdits(
      preview.editsByDocument[activeDocumentId] ?? const <SourceRange>[],
      preview.newName,
    );
    final normalizedActiveEdits = normalizeFormattingEditsForDocument(
      documentLength: editorController.document.length,
      edits: activeEdits,
    );
    if (normalizedActiveEdits.length != activeEdits.length) {
      appendLog(
        'Project rename skipped: active document edits are invalid or overlapping.',
      );
      notifyListeners();
      return false;
    }

    final inactiveEditsByDocument = <String, List<FormattingEdit>>{};
    for (final entry in preview.editsByDocument.entries) {
      if (entry.key == activeDocumentId) {
        continue;
      }
      inactiveEditsByDocument[entry.key] = _renameFormattingEdits(
        entry.value,
        preview.newName,
      );
    }
    var inactiveEditCount = 0;
    if (inactiveEditsByDocument.isNotEmpty) {
      final result =
          await WorkspaceEditApplier(
            workspaceDocumentStore: workspaceDocumentStore,
          ).apply(
            WorkspaceEditPlan(
              id: 'project-rename-${DateTime.now().microsecondsSinceEpoch}',
              summary:
                  'Rename ${preview.oldName} to ${preview.newName} across project.',
              source: WorkspaceEditSource.rename,
              editsByDocument: inactiveEditsByDocument,
            ),
          );
      if (!result.applied) {
        appendLog('Project rename skipped: ${result.message}');
        notifyListeners();
        return false;
      }
      inactiveEditCount = result.appliedEditCount;
      for (final documentId in result.appliedDocumentIds) {
        _documentCache.remove(documentId);
        _documentCursorOffsets.remove(documentId);
        _documentSelectionAnchors.remove(documentId);
      }
    }

    if (normalizedActiveEdits.isNotEmpty) {
      editorController.applyFormattingEdits(normalizedActiveEdits);
      _cacheDocument(activeDocumentId, editorController.document);
      _dirtyDocumentPaths.add(activeDocumentId);
    }
    appendLog(
      'Project rename applied: ${preview.oldName} -> ${preview.newName} '
      'across ${preview.editsByDocument.length} document(s), '
      '${inactiveEditCount + normalizedActiveEdits.length} edit(s).',
    );
    notifyListeners();
    return true;
  }

  List<FormattingEdit> _renameFormattingEdits(
    List<SourceRange> ranges,
    String newName,
  ) {
    return ranges
        .map((range) => FormattingEdit(range: range, newText: newName))
        .toList(growable: false);
  }

  Future<bool> applyAgentIdeCommandSuggestion(
    AgentIdeCommandSuggestion suggestion,
  ) async {
    final registeredCommand = StyioCommandRegistry.descriptorForName(
      suggestion.commandId,
    );
    if (registeredCommand == null) {
      _recordAgentIdeCommandResult(
        suggestion,
        applied: false,
        message:
            'Agent command ${suggestion.commandId} skipped: command is not registered in the IDE command catalog.',
        metadata: <String, Object?>{
          'registered': false,
          'knownCommandCount': StyioCommandRegistry.commands.length,
          // TODO(agent-command-registry): include dynamic extension command ids
          // once extension-contributed commands can be safely invoked by agents.
        },
      );
      appendLog(_lastAgentIdeCommandResult!.message);
      return false;
    }

    switch (registeredCommand.id.name) {
      case 'save':
        final snapshot = await saveActiveWorkspaceFileChanges();
        final applied =
            snapshot.state == DocumentResourceBindingState.boundClean;
        _recordAgentIdeCommandResult(
          suggestion,
          applied: applied,
          message: applied
              ? 'Agent command save completed for $_activeDocumentPath.'
              : 'Agent command save failed for $_activeDocumentPath.',
          metadata: <String, Object?>{
            'activeFilePath': _activeDocumentPath,
            'bindingState': snapshot.state.name,
          },
        );
        return applied;
      case 'saveAll':
        final completedRequiredCommandFor = _completedRequiredCommandFor(
          'saveAll',
        );
        final result = await saveAllWorkspaceFileChanges();
        final applied = result.skippedDocumentIds.isEmpty;
        _recordAgentIdeCommandResult(
          suggestion,
          applied: applied,
          message: result.message,
          metadata: <String, Object?>{
            'savedCount': result.savedDocumentIds.length,
            'skippedCount': result.skippedDocumentIds.length,
            'savedDocumentIds': result.savedDocumentIds,
            'skippedDocumentIds': result.skippedDocumentIds,
            if (completedRequiredCommandFor != null)
              'completedRequiredCommandFor': completedRequiredCommandFor,
          },
        );
        return applied;
      case 'openWorkspaceFile':
        final input = suggestion.input?.trim();
        if (input == null || input.isEmpty) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message: 'Agent command openWorkspaceFile skipped: missing input.',
            metadata: _agentCommandInputMetadata(
              AppCommandId.openWorkspaceFile,
            ),
          );
          appendLog(_lastAgentIdeCommandResult!.message);
          return false;
        }
        final applied = await openWorkspaceFileForAgent(input);
        _recordAgentIdeCommandResult(
          suggestion,
          applied: applied,
          message: applied
              ? 'Agent command openWorkspaceFile opened $input.'
              : 'Agent command openWorkspaceFile failed for $input.',
        );
        return applied;
      case 'createWorkspaceFile':
        return _applyAgentWorkspaceFileCommand(
          suggestion: suggestion,
          commandId: AppCommandId.createWorkspaceFile,
        );
      case 'renameWorkspaceFile':
        return _applyAgentWorkspaceFileCommand(
          suggestion: suggestion,
          commandId: AppCommandId.renameWorkspaceFile,
        );
      case 'deleteWorkspaceFile':
        return _applyAgentWorkspaceFileCommand(
          suggestion: suggestion,
          commandId: AppCommandId.deleteWorkspaceFile,
        );
      case 'revealWorkspaceFile':
        return _applyAgentWorkspaceFileCommand(
          suggestion: suggestion,
          commandId: AppCommandId.revealWorkspaceFile,
        );
      case 'searchWorkspace':
        final input = suggestion.input?.trim();
        if (input == null || input.isEmpty) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message: 'Agent command searchWorkspace skipped: missing input.',
            metadata: _agentCommandInputMetadata(AppCommandId.searchWorkspace),
          );
          appendLog(_lastAgentIdeCommandResult!.message);
          return false;
        }
        final applied = await searchWorkspaceForAgent(input);
        _recordAgentIdeCommandResult(
          suggestion,
          applied: applied,
          message: applied
              ? 'Agent command searchWorkspace completed for $input.'
              : 'Agent command searchWorkspace failed for $input.',
        );
        return applied;
      case 'previewWorkspaceReplace':
        final input = _parseWorkspaceReplaceCommandInput(suggestion.input);
        if (input == null) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message:
                'Agent command previewWorkspaceReplace skipped: expected "search query -> replacement" input.',
            metadata: _agentCommandInputMetadata(
              AppCommandId.previewWorkspaceReplace,
            ),
          );
          appendLog(_lastAgentIdeCommandResult!.message);
          return false;
        }
        final preview = await previewWorkspaceReplace(
          query: input[0],
          replacement: input[1],
        );
        _recordAgentIdeCommandResult(
          suggestion,
          applied: preview != null,
          message: preview == null
              ? 'Agent command previewWorkspaceReplace skipped.'
              : 'Agent command previewWorkspaceReplace collected ${preview.replacementCount} replacement(s).',
          metadata: <String, Object?>{
            'query': input[0],
            'replacement': input[1],
            if (preview != null)
              'workspaceReplacePreview': _workspaceReplacePreviewMetadata(
                preview,
              ),
          },
        );
        return preview != null;
      case 'applyWorkspaceReplace':
        return _applyLastWorkspaceReplacePreviewForAgent(suggestion);
      case 'renameSymbol':
        final input = suggestion.input?.trim();
        if (input == null || input.isEmpty) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message: 'Agent command renameSymbol skipped: missing input.',
            metadata: _agentCommandInputMetadata(AppCommandId.renameSymbol),
          );
          appendLog(_lastAgentIdeCommandResult!.message);
          return false;
        }
        final applied = await renameSymbolAtSelection(input);
        _recordAgentIdeCommandResult(
          suggestion,
          applied: applied,
          message: applied
              ? 'Agent command renameSymbol applied.'
              : 'Agent command renameSymbol skipped.',
        );
        return applied;
      case 'applyQuickFix':
        final quickFixInput = suggestion.input?.trim();
        final selectedQuickFix = editorController.quickFixAtSelectionForInput(
          quickFixInput,
        );
        if (selectedQuickFix != null) {
          editorController.applyDiagnosticQuickFix(selectedQuickFix);
          final quickFixMessage = quickFixInput == null || quickFixInput.isEmpty
              ? 'Agent command applyQuickFix applied at editor selection.'
              : 'Agent command applyQuickFix applied matching "$quickFixInput" at editor selection.';
          _cacheDocument(_activeDocumentPath, editorController.document);
          _dirtyDocumentPaths.add(_activeDocumentPath);
          appendLog(quickFixMessage);
          _publishDiagnosticActionTelemetry(
            action: 'agent.applyQuickFix',
            succeeded: true,
            message: quickFixMessage,
            metadata: <String, Object?>{
              'scope': 'selection',
              'selectionMode': quickFixInput == null || quickFixInput.isEmpty
                  ? 'first'
                  : 'input',
              if (quickFixInput != null && quickFixInput.isNotEmpty)
                'input': quickFixInput,
              'quickFixLabel': selectedQuickFix.label,
              'quickFixDetail': selectedQuickFix.detail,
              'quickFixEditCount': selectedQuickFix.edits.length,
            },
          );
          _recordAgentIdeCommandResult(
            suggestion,
            applied: true,
            message: quickFixMessage,
            metadata: <String, Object?>{
              'scope': 'selection',
              'selectionMode': quickFixInput == null || quickFixInput.isEmpty
                  ? 'first'
                  : 'input',
              if (quickFixInput != null && quickFixInput.isNotEmpty)
                'input': quickFixInput,
              'quickFixLabel': selectedQuickFix.label,
              'quickFixDetail': selectedQuickFix.detail,
              'quickFixEditCount': selectedQuickFix.edits.length,
            },
          );
          notifyListeners();
          return true;
        }
        if (quickFixInput != null &&
            quickFixInput.isNotEmpty &&
            editorController.contextActionsAtSelection.isNotEmpty) {
          const message =
              'Agent command applyQuickFix skipped: no editor quick fix matched input.';
          final metadata = <String, Object?>{
            'scope': 'selection',
            'selectionMode': 'input',
            'input': quickFixInput,
            'reason': 'no-matching-quick-fix',
          };
          appendLog('$message input="$quickFixInput"');
          _publishDiagnosticActionTelemetry(
            action: 'agent.applyQuickFix',
            succeeded: false,
            message: message,
            metadata: metadata,
          );
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message: message,
            metadata: metadata,
          );
          notifyListeners();
          return false;
        }
        final workspacePreview = _lastWorkspaceEditPreview;
        if (workspacePreview == null) {
          final preview = await previewFirstProjectWorkspaceQuickFix();
          final message = preview == null
              ? 'Agent command applyQuickFix skipped: no quick fix available.'
              : 'Agent command applyQuickFix requires previewQuickFix before applying project workspace fix.';
          final metadata = <String, Object?>{
            'scope': 'workspace',
            if (preview != null) 'requiredCommand': 'previewQuickFix',
            if (preview != null) 'workspaceEditPreview': preview.toJson(),
          };
          appendLog(message);
          _publishDiagnosticActionTelemetry(
            action: 'agent.applyQuickFix',
            succeeded: false,
            message: message,
            metadata: metadata,
          );
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message: message,
            metadata: metadata,
          );
          notifyListeners();
          return false;
        }
        final confirmationPlan = WorkspaceEditConfirmationPlan.fromPreview(
          workspacePreview,
        );
        if (!confirmationPlan.ready) {
          final message =
              'Agent command applyQuickFix blocked by workspace edit preview: ${confirmationPlan.message}';
          final metadata = <String, Object?>{
            'scope': 'workspace',
            'workspaceEditPreview': workspacePreview.toJson(),
            'workspaceEditConfirmation': confirmationPlan.toJson(),
          };
          appendLog(message);
          _publishDiagnosticActionTelemetry(
            action: 'agent.applyQuickFix',
            succeeded: false,
            message: message,
            metadata: metadata,
          );
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message: message,
            metadata: metadata,
          );
          notifyListeners();
          return false;
        }
        if (await applyFirstProjectWorkspaceQuickFix(
          expectedPreviewPlanId: workspacePreview.planId,
        )) {
          _publishDiagnosticActionTelemetry(
            action: 'agent.applyQuickFix',
            succeeded: true,
            message:
                'Agent command applyQuickFix applied project workspace fix.',
            metadata: const <String, Object?>{'scope': 'workspace'},
          );
          _recordAgentIdeCommandResult(
            suggestion,
            applied: true,
            message:
                'Agent command applyQuickFix applied project workspace fix.',
          );
          return true;
        }
        final failedWorkspaceApply = _lastWorkspaceEditApplyResult;
        if (failedWorkspaceApply != null && !failedWorkspaceApply.successful) {
          final message =
              'Agent command applyQuickFix skipped: ${failedWorkspaceApply.message}';
          final metadata = <String, Object?>{
            'scope': 'workspace',
            if (failedWorkspaceApply.message.contains('preview is stale'))
              'requiredCommand': 'previewQuickFix',
            if (_lastWorkspaceEditPreview != null)
              'workspaceEditPreview': _lastWorkspaceEditPreview!.toJson(),
            'workspaceEditApplyResult': failedWorkspaceApply.toJson(),
          };
          appendLog(message);
          _publishDiagnosticActionTelemetry(
            action: 'agent.applyQuickFix',
            succeeded: false,
            message: message,
            metadata: metadata,
          );
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message: message,
            metadata: metadata,
          );
          notifyListeners();
          return false;
        }
        appendLog(
          'Agent command applyQuickFix skipped: no quick fix available.',
        );
        _publishDiagnosticActionTelemetry(
          action: 'agent.applyQuickFix',
          succeeded: false,
          message:
              'Agent command applyQuickFix skipped: no quick fix available.',
          metadata: const <String, Object?>{'scope': 'selection'},
        );
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message:
              'Agent command applyQuickFix skipped: no quick fix available.',
        );
        notifyListeners();
        return false;
      case 'previewQuickFix':
        final preview = await previewFirstProjectWorkspaceQuickFix();
        final applied = preview?.canApply ?? false;
        _publishDiagnosticActionTelemetry(
          action: 'agent.previewQuickFix',
          succeeded: applied,
          message: applied
              ? 'Agent command previewQuickFix collected workspace edit preview.'
              : 'Agent command previewQuickFix skipped: no quick fix available.',
          metadata: <String, Object?>{
            if (preview != null) 'workspaceEditPreview': preview.toJson(),
          },
        );
        _recordAgentIdeCommandResult(
          suggestion,
          applied: applied,
          message: applied
              ? 'Agent command previewQuickFix collected workspace edit preview.'
              : 'Agent command previewQuickFix skipped: no quick fix available.',
          metadata: <String, Object?>{
            if (preview != null) 'workspaceEditPreview': preview.toJson(),
          },
        );
        notifyListeners();
        return applied;
      case 'nextDiagnostic':
        if (editorController.selectNextDiagnosticAtSelection()) {
          appendLog('Agent command nextDiagnostic selected in editor.');
          _recordAgentIdeCommandResult(
            suggestion,
            applied: true,
            message: 'Agent command nextDiagnostic selected in editor.',
          );
          notifyListeners();
          return true;
        }
        appendLog('Agent command nextDiagnostic skipped: no diagnostics.');
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message: 'Agent command nextDiagnostic skipped: no diagnostics.',
        );
        notifyListeners();
        return false;
      case 'previousDiagnostic':
        if (editorController.selectPreviousDiagnosticAtSelection()) {
          appendLog('Agent command previousDiagnostic selected in editor.');
          _recordAgentIdeCommandResult(
            suggestion,
            applied: true,
            message: 'Agent command previousDiagnostic selected in editor.',
          );
          notifyListeners();
          return true;
        }
        appendLog('Agent command previousDiagnostic skipped: no diagnostics.');
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message: 'Agent command previousDiagnostic skipped: no diagnostics.',
        );
        notifyListeners();
        return false;
      case 'refreshLanguageService':
        return _refreshLanguageServiceForCommand(suggestion: suggestion);
      case 'refreshWorkspaceDiagnostics':
        final snapshot = await refreshWorkspaceDiagnostics();
        _recordAgentIdeCommandResult(
          suggestion,
          applied: workspaceDiagnosticsController != null,
          message: _workspaceDiagnosticsRefreshMessage(snapshot),
          metadata: <String, Object?>{
            'workspaceDiagnostics': snapshot.toJson(),
          },
        );
        return workspaceDiagnosticsController != null;
      case 'refreshSourceControl':
        final snapshot = await refreshSourceControlStatus();
        _recordAgentIdeCommandResult(
          suggestion,
          applied: snapshot.available,
          message: _sourceControlRefreshMessage(snapshot),
          metadata: <String, Object?>{'sourceControl': snapshot.toJson()},
        );
        return snapshot.available;
      case 'previewSourceControlDiff':
        final path = suggestion.input?.trim().isNotEmpty == true
            ? suggestion.input!.trim()
            : workspaceController.activeFilePath;
        final snapshot = await previewSourceControlDiff(path);
        _recordAgentIdeCommandResult(
          suggestion,
          applied: snapshot.available,
          message: _sourceControlDiffPreviewMessage(snapshot),
          metadata: <String, Object?>{'sourceControlDiff': snapshot.toJson()},
        );
        return snapshot.available;
      case 'stageSourceControl':
      case 'unstageSourceControl':
        final paths = (suggestion.input ?? '')
            .split(RegExp(r'[\n,]+'))
            .map((path) => path.trim())
            .where((path) => path.isNotEmpty)
            .toList(growable: false);
        if (paths.isEmpty) {
          final commandId = suggestion.commandId == 'stageSourceControl'
              ? AppCommandId.stageSourceControl
              : AppCommandId.unstageSourceControl;
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message:
                'Agent command ${suggestion.commandId} skipped: changed file path input is required.',
            metadata: _agentCommandInputMetadata(commandId),
          );
          return false;
        }
        final result = suggestion.commandId == 'stageSourceControl'
            ? await stageSourceControlPaths(paths)
            : await unstageSourceControlPaths(paths);
        final sourceControlContext = sourceControlStatusController
            ?.agentContextSnapshot
            .toJson();
        _recordAgentIdeCommandResult(
          suggestion,
          applied: result.applied,
          message: _sourceControlActionMessage(result),
          metadata: <String, Object?>{
            'pathCount': paths.length,
            'sourceControlAction': result.toJson(),
            if (sourceControlContext != null)
              'sourceControlContext': sourceControlContext,
          },
        );
        return result.applied;
      case 'planSourceControlBranchSwitch':
        final targetBranch = suggestion.input?.trim();
        if (targetBranch == null || targetBranch.isEmpty) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message:
                'Agent command planSourceControlBranchSwitch skipped: target branch input is required.',
            metadata: _agentCommandInputMetadata(
              AppCommandId.planSourceControlBranchSwitch,
            ),
          );
          return false;
        }
        final plan = await planSourceControlBranchSwitch(targetBranch);
        final sourceControlContext = sourceControlStatusController
            ?.agentContextSnapshot
            .toJson();
        _recordAgentIdeCommandResult(
          suggestion,
          applied: plan.canRun,
          message: plan.canRun
              ? 'Agent command planSourceControlBranchSwitch prepared ${plan.targetBranch}.'
              : 'Agent command planSourceControlBranchSwitch blocked: ${plan.blockedReason}',
          metadata: <String, Object?>{
            'sourceControlBranchSwitchPlan': plan.toJson(),
            if (sourceControlContext != null)
              'sourceControlContext': sourceControlContext,
          },
        );
        return plan.canRun;
      case 'planSourceControlCommitDraft':
        final input = _parseSourceControlCommitDraftInput(suggestion.input);
        if (input == null) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message:
                'Agent command planSourceControlCommitDraft skipped: commit message input is required.',
            metadata: _agentCommandInputMetadata(
              AppCommandId.planSourceControlCommitDraft,
            ),
          );
          return false;
        }
        final draft = planSourceControlCommitDraft(
          message: input.message,
          selectedPaths: input.paths.isEmpty ? null : input.paths,
        );
        final dialogState = sourceControlCommitDialogState;
        final plan = draft.toCommitActionPlan();
        _recordAgentIdeCommandResult(
          suggestion,
          applied: plan.canRun,
          message: plan.canRun
              ? 'Agent command planSourceControlCommitDraft prepared a commit draft.'
              : 'Agent command planSourceControlCommitDraft blocked: ${plan.blockedReason}',
          metadata: <String, Object?>{
            'sourceControlCommitDraft': draft.toJson(),
            if (dialogState != null)
              'sourceControlCommitDialog': dialogState.toJson(),
          },
        );
        return plan.canRun;
      case 'collectAgentCodingCheckpoint':
        final metadata = await collectAgentCodingCheckpoint();
        _recordAgentIdeCommandResult(
          suggestion,
          applied: true,
          message: 'Agent command collectAgentCodingCheckpoint completed.',
          metadata: metadata,
        );
        return true;
      case 'collectProjectLanguageContext':
        final metadata = await collectProjectLanguageContext();
        _recordAgentIdeCommandResult(
          suggestion,
          applied: true,
          message: 'Agent command collectProjectLanguageContext completed.',
          metadata: <String, Object?>{'projectLanguage': metadata},
        );
        return true;
      case 'retryAgentProvider':
        return _dispatchAgentRecoveryCommand(
          suggestion: suggestion,
          action: AgentCodingSessionRecoveryAction.retrySameProvider,
        );
      case 'replayAgentPrompt':
        return _dispatchAgentRecoveryCommand(
          suggestion: suggestion,
          action: AgentCodingSessionRecoveryAction.replayPrompt,
        );
      case 'failoverAgentProvider':
        return _failoverAgentProviderForSuggestion(suggestion);
      case 'goToDefinition':
        if (editorController.selectDefinitionAtSelection()) {
          appendLog('Agent command goToDefinition selected in editor.');
          _recordAgentIdeCommandResult(
            suggestion,
            applied: true,
            message: 'Agent command goToDefinition selected in editor.',
          );
          notifyListeners();
          return true;
        }
        if (await goToProjectDefinitionAtSelection()) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: true,
            message: 'Agent command goToDefinition opened project definition.',
          );
          return true;
        }
        appendLog(
          'Agent command goToDefinition skipped: no resolved definition.',
        );
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message:
              'Agent command goToDefinition skipped: no resolved definition.',
        );
        notifyListeners();
        return false;
      case 'nextReference':
        if (editorController.selectNextReferenceAtSelection()) {
          appendLog('Agent command nextReference selected in editor.');
          _recordAgentIdeCommandResult(
            suggestion,
            applied: true,
            message: 'Agent command nextReference selected in editor.',
          );
          notifyListeners();
          return true;
        }
        if (await selectProjectReferenceAtSelection(forward: true)) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: true,
            message: 'Agent command nextReference opened project reference.',
          );
          return true;
        }
        appendLog('Agent command nextReference skipped: no references.');
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message: 'Agent command nextReference skipped: no references.',
        );
        notifyListeners();
        return false;
      case 'previousReference':
        if (editorController.selectPreviousReferenceAtSelection()) {
          appendLog('Agent command previousReference selected in editor.');
          _recordAgentIdeCommandResult(
            suggestion,
            applied: true,
            message: 'Agent command previousReference selected in editor.',
          );
          notifyListeners();
          return true;
        }
        if (await selectProjectReferenceAtSelection(forward: false)) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: true,
            message:
                'Agent command previousReference opened project reference.',
          );
          return true;
        }
        appendLog('Agent command previousReference skipped: no references.');
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message: 'Agent command previousReference skipped: no references.',
        );
        notifyListeners();
        return false;
      case 'toggleBreakpoint':
        return _applyAgentDebugCommandSuggestion(
          suggestion,
          toggleBreakpointAtSelection,
        );
      case 'startDebugging':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        return _applyAgentDebugCommandSuggestion(suggestion, startDebugging);
      case 'stopDebugging':
        return _applyAgentDebugCommandSuggestion(suggestion, stopDebugging);
      case 'continueDebugging':
        return _applyAgentDebugCommandSuggestion(suggestion, continueDebugging);
      case 'stepOver':
        return _applyAgentDebugCommandSuggestion(suggestion, stepOver);
      case 'selectDebugThread':
        final input = suggestion.input?.trim();
        if (input == null || input.isEmpty) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message: 'Agent command selectDebugThread skipped: missing input.',
            metadata: _agentCommandInputMetadata(
              AppCommandId.selectDebugThread,
            ),
          );
          appendLog(_lastAgentIdeCommandResult!.message);
          return false;
        }
        final result = await selectDebugThread(input);
        _recordAgentIdeCommandResult(
          suggestion,
          applied: result.applied,
          message: result.message,
          metadata: <String, Object?>{'threadId': input},
        );
        return result.applied;
      case 'selectDebugStackFrame':
        final input = suggestion.input?.trim();
        if (input == null || input.isEmpty) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message:
                'Agent command selectDebugStackFrame skipped: missing input.',
            metadata: _agentCommandInputMetadata(
              AppCommandId.selectDebugStackFrame,
            ),
          );
          appendLog(_lastAgentIdeCommandResult!.message);
          return false;
        }
        final result = await selectDebugStackFrame(input);
        _recordAgentIdeCommandResult(
          suggestion,
          applied: result.applied,
          message: result.message,
          metadata: <String, Object?>{'frameId': input},
        );
        return result.applied;
      case 'safeDelete':
        if (editorController.applySafeDeleteAtSelection()) {
          _cacheDocument(_activeDocumentPath, editorController.document);
          _dirtyDocumentPaths.add(_activeDocumentPath);
          appendLog('Agent command safeDelete applied at editor selection.');
          _recordAgentIdeCommandResult(
            suggestion,
            applied: true,
            message: 'Agent command safeDelete applied at editor selection.',
          );
          notifyListeners();
          return true;
        }
        appendLog(
          'Agent command safeDelete skipped: no safe delete available.',
        );
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message:
              'Agent command safeDelete skipped: no safe delete available.',
        );
        notifyListeners();
        return false;
      case 'inlineVariable':
        if (editorController.applyInlineVariableAtSelection()) {
          _cacheDocument(_activeDocumentPath, editorController.document);
          _dirtyDocumentPaths.add(_activeDocumentPath);
          appendLog(
            'Agent command inlineVariable applied at editor selection.',
          );
          _recordAgentIdeCommandResult(
            suggestion,
            applied: true,
            message:
                'Agent command inlineVariable applied at editor selection.',
          );
          notifyListeners();
          return true;
        }
        appendLog(
          'Agent command inlineVariable skipped: no inline variable available.',
        );
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message:
              'Agent command inlineVariable skipped: no inline variable available.',
        );
        notifyListeners();
        return false;
      case 'openSettings':
        await executeCommand(AppCommandId.openSettings);
        final settingsSection = _settingsSectionForAgentRecovery(
          suggestion.prerequisiteForCommandId,
        );
        _recordAgentIdeCommandResult(
          suggestion,
          applied: true,
          message: 'Agent command openSettings requested settings route.',
          metadata: <String, Object?>{
            'settingsRoute': 'settings',
            if (settingsSection != null) 'settingsSection': settingsSection,
          },
        );
        return true;
      case 'selectClangCppVersion':
        final parsed = _parseClangCppVersionCommandInput(suggestion.input);
        if (parsed == null) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message:
                'Agent command selectClangCppVersion skipped: missing input.',
            metadata: _agentCommandInputMetadata(
              AppCommandId.selectClangCppVersion,
            ),
          );
          notifyListeners();
          return false;
        }
        final result = await selectClangCppVersion(
          parsed.versionId,
          cppStandard: parsed.cppStandard,
        );
        final applied = result?.succeeded ?? false;
        final selection = result?.succeeded == true
            ? ClangCppVersionManager.fromSnapshot(
                result!.snapshot,
                preference: _clangCppVersionPreference,
              ).select()
            : null;
        _recordAgentIdeCommandResult(
          suggestion,
          applied: applied,
          message: applied
              ? 'Agent command selectClangCppVersion selected ${parsed.versionId}.'
              : 'Agent command selectClangCppVersion failed for ${parsed.versionId}: ${result?.message ?? "selection was not applied"}.',
          metadata: <String, Object?>{
            'toolchainId': parsed.versionId,
            if (parsed.cppStandard != null) 'cppStandard': parsed.cppStandard,
            if (result != null) 'toolchainSelectionStatus': result.status.name,
            if (result?.message != null)
              'toolchainSelectionMessage': result!.message,
            if (selection != null)
              ..._agentClangCppSelectionMetadata(selection),
          },
        );
        return applied;
      case 'run':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        await executeCommand(AppCommandId.run);
        final session = _lastExecutionSession;
        final applied =
            session != null && session.status != ExecutionSessionStatus.blocked;
        _recordAgentIdeCommandResult(
          suggestion,
          applied: applied,
          message: session == null
              ? 'Agent command run skipped: no execution session was produced.'
              : 'Agent command run ${session.status.name}: ${session.statusMessage}',
          metadata: <String, Object?>{
            if (session != null) 'executionSession': session.toJson(),
            'runtimeEventCount': _lastRuntimeEvents.length,
            if (_lastRuntimeEvents.isNotEmpty)
              'runtimeEventKinds': _lastRuntimeEvents
                  .take(4)
                  .map((event) => event.eventKind)
                  .toList(growable: false),
            // TODO(agent-runtime): surface cancellation/resume handles once
            // ExecutionSession grows stable process-control identifiers.
          },
        );
        return applied;
      case 'fetchDependencies':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        return _applyAgentDependencySourceCommand(
          suggestion,
          () => fetchDependencies(),
        );
      case 'vendorDependencies':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        return _applyAgentDependencySourceCommand(
          suggestion,
          () => vendorDependencies(),
        );
      case 'packProject':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        return _applyAgentDeploymentCommand(suggestion, () => packProject());
      case 'preparePublish':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        return _applyAgentDeploymentCommand(suggestion, () => preparePublish());
      case 'useActiveCompiler':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        return _applyAgentToolchainCommand(
          suggestion,
          AppCommandId.useActiveCompiler,
        );
      case 'pinActiveCompiler':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        return _applyAgentToolchainCommand(
          suggestion,
          AppCommandId.pinActiveCompiler,
        );
      case 'clearPinnedCompiler':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        return _applyAgentToolchainCommand(
          suggestion,
          AppCommandId.clearPinnedCompiler,
        );
      case 'bootstrapStyioToolchain':
        return _applyAgentToolchainBootstrapCommand(suggestion);
      case 'executeToolchainInstallPlan':
        return _applyAgentToolchainInstallExecutionCommand(suggestion);
      case 'refreshModules':
        await executeCommand(AppCommandId.refreshModules);
        final metadata = await _agentModuleHostRefreshMetadata();
        _recordAgentIdeCommandResult(
          suggestion,
          applied: true,
          message: 'Agent command refreshModules refreshed module host facts.',
          metadata: <String, Object?>{'moduleHostRefresh': metadata},
        );
        return true;
      case 'showRuntime':
      case 'showAgent':
      case 'showDebug':
        final commandId = switch (suggestion.commandId) {
          'showRuntime' => AppCommandId.showRuntime,
          'showAgent' => AppCommandId.showAgent,
          'showDebug' => AppCommandId.showDebug,
          _ => AppCommandId.showRuntime,
        };
        await executeCommand(commandId);
        _recordAgentIdeCommandResult(
          suggestion,
          applied: true,
          message:
              'Agent command ${suggestion.commandId} focused the requested IDE surface.',
          metadata: <String, Object?>{
            'surfaceCommand': <String, Object?>{
              'commandId': suggestion.commandId,
              'targetSurface': switch (suggestion.commandId) {
                'showRuntime' => 'runtime',
                'showAgent' => 'agent',
                'showDebug' => 'debug',
                _ => 'runtime',
              },
            },
          },
        );
        return true;
      case 'runBuild':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        final result = await _runNativeToolCommand(AppCommandId.runBuild);
        _recordAgentIdeCommandResult(
          suggestion,
          applied: result.applied,
          message: result.message,
          metadata: result.metadata,
        );
        return result.applied;
      case 'formatActiveDocument':
        final result = await _runNativeToolCommand(
          AppCommandId.formatActiveDocument,
        );
        _recordAgentIdeCommandResult(
          suggestion,
          applied: result.applied,
          message: result.message,
          metadata: result.metadata,
        );
        return result.applied;
      case 'runStaticAnalysis':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        final result = await _runNativeToolCommand(
          AppCommandId.runStaticAnalysis,
        );
        _recordAgentIdeCommandResult(
          suggestion,
          applied: result.applied,
          message: result.message,
          metadata: result.metadata,
        );
        return result.applied;
      case 'runTests':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        final result = await _runNativeToolCommand(AppCommandId.runTests);
        _recordAgentIdeCommandResult(
          suggestion,
          applied: result.applied,
          message: result.message,
          metadata: result.metadata,
        );
        return result.applied;
      case 'rerunFailedTests':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        await rerunFailedTests();
        final result = lastTestRun;
        final applied = _agentTestingCommandApplied(result);
        _recordAgentIdeCommandResult(
          suggestion,
          applied: applied,
          message: result == null
              ? 'Agent command rerunFailedTests skipped: no test result is available.'
              : _testRunResultMessage('Agent command rerunFailedTests', result),
          metadata: _agentTestingCommandMetadata(result),
        );
        return applied;
      case 'debugFailedTests':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        await debugFailedTests();
        final result = lastTestRun;
        final applied = _agentTestingCommandApplied(result);
        _recordAgentIdeCommandResult(
          suggestion,
          applied: applied,
          message: result == null
              ? 'Agent command debugFailedTests skipped: no test result is available.'
              : _testRunResultMessage('Agent command debugFailedTests', result),
          metadata: _agentTestingCommandMetadata(result),
        );
        return applied;
      case 'runTestConfiguration':
      case 'debugTestConfiguration':
        if (_blockAgentDiskBackedCommandWhenDirty(suggestion)) {
          return false;
        }
        final input = suggestion.input?.trim();
        final configuration = input == null || input.isEmpty
            ? null
            : _testRunConfigurationForId(input);
        if (configuration == null) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message:
                'Agent command ${suggestion.commandId} skipped: valid test configuration id input is required.',
            metadata: _testConfigurationCommandMetadata(),
          );
          return false;
        }
        if (suggestion.commandId == 'debugTestConfiguration') {
          await debugTestConfiguration(configuration);
        } else {
          await runTestConfiguration(configuration);
        }
        final result = lastTestRun;
        final applied = _agentTestingCommandApplied(result);
        _recordAgentIdeCommandResult(
          suggestion,
          applied: applied,
          message: result == null
              ? 'Agent command ${suggestion.commandId} skipped: no test result is available.'
              : _testRunResultMessage(
                  'Agent command ${suggestion.commandId}',
                  result,
                ),
          metadata: _testConfigurationCommandMetadata(
            configuration: configuration,
            result: result,
          ),
        );
        return applied;
      default:
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message:
              'Agent command ${registeredCommand.id.name} skipped: registered command has no agent executor.',
          metadata: <String, Object?>{
            'registered': true,
            'commandCategory': registeredCommand.id.category.wireValue,
            // TODO(agent-command-execution): bind this registered command to an
            // explicit agent executor or mark it as UI-only in the registry.
          },
        );
        appendLog(_lastAgentIdeCommandResult!.message);
        return false;
    }
  }

  Future<bool> _applyAgentWorkspaceFileCommand({
    required AgentIdeCommandSuggestion suggestion,
    required AppCommandId commandId,
  }) async {
    final descriptor = StyioCommandRegistry.descriptorFor(commandId);
    final input = suggestion.input?.trim() ?? '';
    if (input.isEmpty) {
      _recordAgentIdeCommandResult(
        suggestion,
        applied: false,
        message:
            'Agent command ${commandId.name} skipped: ${descriptor.inputLabel} input is required.',
        metadata: _agentCommandInputMetadata(commandId),
      );
      appendLog(_lastAgentIdeCommandResult!.message);
      return false;
    }
    final result = await _executeWorkspaceFileCommandWithInput(
      commandId,
      input,
    );
    _recordAgentIdeCommandResult(
      suggestion,
      applied: result.applied,
      message: result.message,
      metadata: result.toJson(),
    );
    appendLog(result.message);
    notifyListeners();
    return result.applied;
  }

  Map<String, Object?> _agentCommandInputMetadata(AppCommandId commandId) {
    final descriptor = StyioCommandRegistry.descriptorFor(commandId);
    return <String, Object?>{
      'reason': 'missing-input',
      'requiredInput': descriptor.inputLabel,
      'inputLabel': descriptor.inputLabel,
      'inputContract': descriptor.inputContract,
      'inputExamples': descriptor.inputExamples,
    };
  }

  List<String>? _parseWorkspaceReplaceCommandInput(String? rawInput) {
    final input = rawInput?.trim() ?? '';
    final arrowIndex = input.indexOf('->');
    if (arrowIndex <= 0) {
      return null;
    }
    final query = input.substring(0, arrowIndex).trim();
    if (query.isEmpty) {
      return null;
    }
    final replacement = input.substring(arrowIndex + 2).trim();
    return <String>[query, replacement];
  }

  Future<bool> _applyLastWorkspaceReplacePreviewForAgent(
    AgentIdeCommandSuggestion suggestion,
  ) async {
    final preview = _lastWorkspaceReplacePreview;
    if (preview == null) {
      _recordAgentIdeCommandResult(
        suggestion,
        applied: false,
        message:
            'Agent command applyWorkspaceReplace skipped: no workspace replace preview is available.',
        metadata: const <String, Object?>{
          'requiredCommand': 'previewWorkspaceReplace',
        },
      );
      appendLog(_lastAgentIdeCommandResult!.message);
      return false;
    }
    final result = await applyWorkspaceReplacePreview(preview);
    if (result == null) {
      _recordAgentIdeCommandResult(
        suggestion,
        applied: false,
        message:
            'Agent command applyWorkspaceReplace skipped: no preview changes.',
        metadata: <String, Object?>{
          'workspaceReplacePreview': _workspaceReplacePreviewMetadata(preview),
        },
      );
      return false;
    }
    final applied = result.documents.isNotEmpty && result.failures.isEmpty;
    _recordAgentIdeCommandResult(
      suggestion,
      applied: applied,
      message:
          'Agent command applyWorkspaceReplace changed ${result.replacementCount} replacement(s).',
      metadata: <String, Object?>{
        'workspaceReplaceResult': _workspaceReplaceResultMetadata(result),
      },
    );
    return applied;
  }

  Map<String, Object?> _workspaceReplacePreviewMetadata(
    WorkspaceReplacePreview preview,
  ) {
    return <String, Object?>{
      'replacementCount': preview.replacementCount,
      'documentCount': preview.documents.length,
      'failureCount': preview.failures.length,
      'truncated': preview.truncated,
      'documents': preview.documents
          .map(
            (document) => <String, Object?>{
              'documentId': document.documentId,
              'replacementCount': document.replacementCount,
              'revision': document.revision,
            },
          )
          .toList(growable: false),
      if (preview.failures.isNotEmpty)
        'failures': preview.failures
            .map((failure) => failure.toJson())
            .toList(growable: false),
    };
  }

  Map<String, Object?> _workspaceReplaceResultMetadata(
    WorkspaceReplaceResult result,
  ) {
    return <String, Object?>{
      'replacementCount': result.replacementCount,
      'documentCount': result.documents.length,
      'failureCount': result.failures.length,
      'truncated': result.truncated,
      'documents': result.documents
          .map(
            (document) => <String, Object?>{
              'documentId': document.documentId,
              'replacementCount': document.replacementCount,
              'revision': document.revision,
            },
          )
          .toList(growable: false),
      if (result.failures.isNotEmpty)
        'failures': result.failures
            .map((failure) => failure.toJson())
            .toList(growable: false),
    };
  }

  void _recordAgentIdeCommandResult(
    AgentIdeCommandSuggestion suggestion, {
    required bool applied,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final effectiveMetadata = <String, Object?>{...metadata};
    final prerequisiteForCommandId = suggestion.prerequisiteForCommandId;
    if (prerequisiteForCommandId != null &&
        prerequisiteForCommandId.isNotEmpty) {
      if (suggestion.commandId == 'openSettings') {
        effectiveMetadata['recoveryForCommandId'] = prerequisiteForCommandId;
      } else {
        effectiveMetadata['completedRequiredCommandFor'] =
            prerequisiteForCommandId;
      }
    }
    final result = AgentCommandResultContext(
      commandId: suggestion.commandId,
      input: suggestion.input,
      applied: applied,
      message: message,
      metadata: effectiveMetadata,
      completedAt: DateTime.now().toUtc(),
    );
    _lastAgentIdeCommandResult = result;
    _agentIdeCommandResults.insert(0, result);
    if (_agentIdeCommandResults.length > _maxAgentIdeCommandResultRecords) {
      _agentIdeCommandResults.removeRange(
        _maxAgentIdeCommandResultRecords,
        _agentIdeCommandResults.length,
      );
    }
    notifyListeners();
  }

  String? _completedRequiredCommandFor(String commandId) {
    final previousResult = _lastAgentIdeCommandResult;
    if (previousResult == null) {
      return null;
    }
    if (previousResult.commandId == commandId) {
      return null;
    }
    return requiredCommandIdFromAgentMetadata(previousResult.metadata) ==
            commandId
        ? previousResult.commandId
        : null;
  }

  bool _blockAgentDiskBackedCommandWhenDirty(
    AgentIdeCommandSuggestion suggestion,
  ) {
    final dirtyDocuments = dirtyDocumentPaths;
    if (dirtyDocuments.isEmpty) {
      return false;
    }
    final message =
        'Agent command ${suggestion.commandId} blocked: save dirty workspace documents before running disk-backed IDE tools.';
    _recordAgentIdeCommandResult(
      suggestion,
      applied: false,
      message: message,
      metadata: <String, Object?>{
        'dirtyDocumentIds': dirtyDocuments,
        'requiredCommand': 'saveAll',
      },
    );
    appendLog(message);
    return true;
  }

  Future<bool> _applyAgentDebugCommandSuggestion(
    AgentIdeCommandSuggestion suggestion,
    FutureOr<DebugCommandResult> Function() action,
  ) async {
    final result = await Future<DebugCommandResult>.value(action());
    _recordAgentIdeCommandResult(
      suggestion,
      applied: result.applied,
      message: result.message,
      metadata: <String, Object?>{'debugStatus': _debugSession.status.name},
    );
    return result.applied;
  }

  Future<bool> _applyAgentDependencySourceCommand(
    AgentIdeCommandSuggestion suggestion,
    Future<DependencySourceCommandResult> Function() action,
  ) async {
    final result = await action();
    _recordAgentIdeCommandResult(
      suggestion,
      applied: result.succeeded,
      message:
          'Agent command ${suggestion.commandId} ${result.status.name}: ${result.statusMessage}',
      metadata: <String, Object?>{
        'dependencySourceCommand': _dependencySourceCommandResultMetadata(
          result,
        ),
      },
    );
    return result.succeeded;
  }

  Future<bool> _applyAgentDeploymentCommand(
    AgentIdeCommandSuggestion suggestion,
    Future<DeploymentCommandResult> Function() action,
  ) async {
    final result = await action();
    _recordAgentIdeCommandResult(
      suggestion,
      applied: result.succeeded,
      message:
          'Agent command ${suggestion.commandId} ${result.status.name}: ${result.statusMessage}',
      metadata: <String, Object?>{
        'deploymentCommand': _deploymentCommandResultMetadata(result),
      },
    );
    return result.succeeded;
  }

  Future<bool> _applyAgentToolchainCommand(
    AgentIdeCommandSuggestion suggestion,
    AppCommandId commandId,
  ) async {
    final blockedReason = blockedReasonForCommand(commandId);
    if (blockedReason != null) {
      final message =
          'Agent command ${suggestion.commandId} blocked: $blockedReason';
      _recordAgentIdeCommandResult(
        suggestion,
        applied: false,
        message: message,
        metadata: <String, Object?>{
          'blockedReason': blockedReason,
          'requiredCommand': 'openSettings',
        },
      );
      appendLog(message);
      return false;
    }
    await executeCommand(commandId);
    final result = _lastToolchainCommand;
    final applied = result?.succeeded ?? false;
    _recordAgentIdeCommandResult(
      suggestion,
      applied: applied,
      message: result == null
          ? 'Agent command ${suggestion.commandId} skipped: no toolchain command result was produced.'
          : 'Agent command ${suggestion.commandId} ${result.status.name}: ${result.statusMessage}',
      metadata: <String, Object?>{
        if (result != null)
          'toolchainCommand': _toolchainCommandResultMetadata(result),
      },
    );
    return applied;
  }

  Future<bool> _applyAgentToolchainBootstrapCommand(
    AgentIdeCommandSuggestion suggestion,
  ) async {
    final result = await handleToolchainBootstrapAction(
      'bootstrap-styio-toolchain',
    );
    final applied = result?.dispatched ?? false;
    _recordAgentIdeCommandResult(
      suggestion,
      applied: applied,
      message: result == null
          ? 'Agent command bootstrapStyioToolchain skipped: no bootstrap result was produced.'
          : 'Agent command bootstrapStyioToolchain ${result.status.wireValue}: ${result.message}',
      metadata: <String, Object?>{
        if (result != null) 'toolchainBootstrapActionDispatch': result.toJson(),
        if (_toolchainBootstrapSummary != null)
          'toolchainBootstrap': _toolchainBootstrapSummary!.toJson(),
      },
    );
    return applied;
  }

  Future<bool> _applyAgentToolchainInstallExecutionCommand(
    AgentIdeCommandSuggestion suggestion,
  ) async {
    final result = await executeLastToolchainInstallPlan();
    final applied =
        result != null &&
        result.status != ToolchainInstallExecutionStatus.failed &&
        result.status != ToolchainInstallExecutionStatus.blocked;
    _recordAgentIdeCommandResult(
      suggestion,
      applied: applied,
      message: result == null
          ? 'Agent command executeToolchainInstallPlan skipped: no install plan is prepared.'
          : 'Agent command executeToolchainInstallPlan ${result.status.name}: ${result.message ?? result.plan.mode.name}',
      metadata: <String, Object?>{
        if (_lastToolchainInstallPlan != null)
          'toolchainInstallPlan': _lastToolchainInstallPlan!.toJson(),
        if (result != null) 'toolchainInstallExecution': result.toJson(),
      },
    );
    return applied;
  }

  Map<String, Object?> _dependencySourceCommandResultMetadata(
    DependencySourceCommandResult result,
  ) {
    return <String, Object?>{
      'command': result.command,
      'status': result.status.name,
      'statusMessage': result.statusMessage,
      'succeeded': result.succeeded,
      if (result.payload != null) 'payload': result.payload,
      if (result.errorPayload != null) 'errorPayload': result.errorPayload,
      // TODO(agent-project-lifecycle): add bounded stdout/stderr summaries
      // when the command-result contract exposes stable log slicing.
    };
  }

  Map<String, Object?> _deploymentCommandResultMetadata(
    DeploymentCommandResult result,
  ) {
    return <String, Object?>{
      'command': result.command,
      'status': result.status.name,
      'statusMessage': result.statusMessage,
      'succeeded': result.succeeded,
      if (result.payload != null) 'payload': result.payload,
      if (result.errorPayload != null) 'errorPayload': result.errorPayload,
      // TODO(agent-project-lifecycle): add publish recovery hints once
      // registry/auth failure kinds are normalized.
    };
  }

  Map<String, Object?> _toolchainCommandResultMetadata(
    ToolchainCommandResult result,
  ) {
    return <String, Object?>{
      'command': result.command,
      'status': result.status.name,
      'statusMessage': result.statusMessage,
      'succeeded': result.succeeded,
      if (result.payload != null) 'payload': result.payload,
      if (result.errorPayload != null) 'errorPayload': result.errorPayload,
      // TODO(agent-toolchain): add bounded stdout/stderr summaries once
      // toolchain results expose stable log slicing.
    };
  }

  Future<Map<String, Object?>> _agentModuleHostRefreshMetadata() async {
    final bridge = await nativeModuleLoader.describe('local.runtime.desktop');
    return <String, Object?>{
      'visibleModuleCount': visibleModules.length,
      'mountedModuleCount': mountedModules.length,
      'visibleModuleIds': visibleModules
          .map((module) => module.manifest.moduleId)
          .toList(growable: false),
      'mountedModuleIds': mountedModules
          .map((module) => module.manifest.moduleId)
          .toList(growable: false),
      'nativeBridge': <String, Object?>{
        'moduleId': bridge.moduleId,
        'state': bridge.state.name,
        'detail': bridge.detail,
      },
      // TODO(agent-modules): include extension-host manifest digests once the
      // module registry exposes stable per-module refresh timestamps.
    };
  }

  Future<_NativeToolCommandResult> _runNativeToolCommand(
    AppCommandId commandId,
  ) async {
    final backendRouteMetadata = _nativeToolBackendRouteMetadata(commandId);
    final manager = toolchainManager;
    if (manager == null) {
      final message =
          '${_nativeToolCommandLabel(commandId)} skipped: no toolchain manager is available.';
      final result = _NativeToolCommandResult(
        applied: false,
        message: message,
        metadata: backendRouteMetadata,
      );
      _recordNativeToolResult(commandId, result);
      appendLog(message);
      notifyListeners();
      return result;
    }

    switch (commandId) {
      case AppCommandId.runBuild:
        final needsConfigure =
            _hasWorkspaceFile('CMakeLists.txt') && !_hasConfiguredCMakeBuild();
        final buildDirectory = needsConfigure
            ? 'build'
            : _nativeBuildDirectoryArgument();
        if (!needsConfigure &&
            _hasNinjaBuild() &&
            !await _hasBuildToolFamily(manager, 'cmake')) {
          final ninjaArguments = buildDirectory == '.'
              ? const <String>[]
              : <String>['-C', buildDirectory];
          final result = await manager.run(
            kind: ToolchainKind.buildTool,
            requirement: const ToolchainRequirement(
              kind: ToolchainKind.buildTool,
              metadata: <String, Object?>{'toolFamily': 'ninja'},
            ),
            arguments: ninjaArguments,
            workingDirectory: workspaceController.activeProject.workspaceRoot,
            timeout: const Duration(minutes: 5),
          );
          final diagnostics = _clangBuildDiagnosticsFromOutput(
            '${result.stdout}\n${result.stderr}',
          );
          if (diagnostics.isNotEmpty) {
            editorController.applyExternalDiagnostics(diagnostics);
          }
          final buildResult = <String, Object?>{
            'runner': 'ninja',
            'status': result.succeeded ? 'passed' : 'failed',
            'buildDirectory': buildDirectory,
            'configuredBeforeBuild': false,
            'arguments': ninjaArguments,
            'diagnosticCount': diagnostics.length,
            ..._nativeToolProcessMetadata(result),
          };
          final message = result.succeeded
              ? 'Run Build completed.'
              : _nativeToolFailureMessage(commandId, result.message);
          final commandResult = _NativeToolCommandResult(
            applied: result.succeeded,
            message: message,
            metadata: <String, Object?>{
              'buildResult': buildResult,
              ...backendRouteMetadata,
            },
            diagnostics: diagnostics,
          );
          _recordNativeToolResult(commandId, commandResult);
          appendLog(message);
          notifyListeners();
          return commandResult;
        }
        Map<String, Object?>? configureResult;
        if (needsConfigure) {
          final configureArguments = await _nativeCMakeConfigureArguments(
            manager,
            buildDirectory: buildDirectory,
          );
          final configure = await manager.run(
            kind: ToolchainKind.buildTool,
            requirement: const ToolchainRequirement(
              kind: ToolchainKind.buildTool,
              metadata: <String, Object?>{'toolFamily': 'cmake'},
            ),
            arguments: configureArguments,
            workingDirectory: workspaceController.activeProject.workspaceRoot,
            timeout: const Duration(minutes: 5),
          );
          configureResult = <String, Object?>{
            'runner': 'cmake',
            'status': configure.succeeded ? 'passed' : 'failed',
            'arguments': configureArguments,
            ..._nativeToolProcessMetadata(configure),
          };
          if (!configure.succeeded) {
            final message = _nativeToolFailureMessage(
              commandId,
              configure.message,
            );
            final commandResult = _NativeToolCommandResult(
              applied: false,
              message: message,
              metadata: <String, Object?>{
                'buildResult': <String, Object?>{
                  'runner': 'cmake',
                  'status': 'failed',
                  'buildDirectory': buildDirectory,
                  'configuredBeforeBuild': true,
                  'configureResult': configureResult,
                  'diagnosticCount': 0,
                },
                ...backendRouteMetadata,
              },
            );
            _recordNativeToolResult(commandId, commandResult);
            appendLog(message);
            notifyListeners();
            return commandResult;
          }
          _registerGeneratedCMakeBuildArtifacts(
            buildDirectory: buildDirectory,
            configureArguments: configureArguments,
          );
        }
        final buildArguments = <String>['--build', buildDirectory];
        final result = await manager.run(
          kind: ToolchainKind.buildTool,
          requirement: const ToolchainRequirement(
            kind: ToolchainKind.buildTool,
            metadata: <String, Object?>{'toolFamily': 'cmake'},
          ),
          arguments: buildArguments,
          workingDirectory: workspaceController.activeProject.workspaceRoot,
          timeout: const Duration(minutes: 5),
        );
        final diagnostics = _clangBuildDiagnosticsFromOutput(
          '${result.stdout}\n${result.stderr}',
        );
        if (diagnostics.isNotEmpty) {
          editorController.applyExternalDiagnostics(diagnostics);
        }
        final buildResult = <String, Object?>{
          'runner': 'cmake',
          'status': result.succeeded ? 'passed' : 'failed',
          'buildDirectory': buildDirectory,
          'configuredBeforeBuild': configureResult != null,
          if (configureResult != null) 'configureResult': configureResult,
          'arguments': buildArguments,
          'diagnosticCount': diagnostics.length,
          ..._nativeToolProcessMetadata(result),
        };
        final message = result.succeeded
            ? 'Run Build completed.'
            : _nativeToolFailureMessage(commandId, result.message);
        final commandResult = _NativeToolCommandResult(
          applied: result.succeeded,
          message: message,
          metadata: <String, Object?>{
            'buildResult': buildResult,
            ...backendRouteMetadata,
          },
          diagnostics: diagnostics,
        );
        _recordNativeToolResult(commandId, commandResult);
        appendLog(message);
        notifyListeners();
        return commandResult;
      case AppCommandId.formatActiveDocument:
        final result = await manager.run(
          kind: ToolchainKind.formatter,
          requirement: const ToolchainRequirement(
            kind: ToolchainKind.formatter,
            metadata: <String, Object?>{'toolFamily': 'clang-format'},
          ),
          arguments: <String>['--assume-filename=$_activeDocumentPath'],
          standardInput: editorController.document.text,
          timeout: const Duration(seconds: 20),
        );
        if (!result.succeeded) {
          final message = _nativeToolFailureMessage(commandId, result.message);
          final commandResult = _NativeToolCommandResult(
            applied: false,
            message: message,
            metadata: <String, Object?>{
              'formatResult': <String, Object?>{
                'runner': 'clang-format',
                'status': 'failed',
                'changed': false,
                'outputLength': result.stdout.length,
                ..._nativeToolProcessMetadata(result),
              },
            },
          );
          _recordNativeToolResult(commandId, commandResult);
          appendLog(message);
          notifyListeners();
          return commandResult;
        }
        final formattedText = result.stdout;
        final previousText = editorController.document.text;
        final changed =
            formattedText.isNotEmpty && formattedText != previousText;
        if (changed) {
          editorController.applyFormattingEdits(<FormattingEdit>[
            FormattingEdit(
              range: SourceRange(
                start: 0,
                end: editorController.document.length,
              ),
              newText: formattedText,
            ),
          ]);
          _cacheDocument(_activeDocumentPath, editorController.document);
          _dirtyDocumentPaths.add(_activeDocumentPath);
        }
        final message = formattedText.isEmpty
            ? 'Format Active Document completed with empty formatter output.'
            : 'Format Active Document completed.';
        final commandResult = _NativeToolCommandResult(
          applied: true,
          message: message,
          metadata: <String, Object?>{
            'formatResult': <String, Object?>{
              'runner': 'clang-format',
              'status': 'passed',
              'changed': changed,
              'outputLength': formattedText.length,
              ..._nativeToolProcessMetadata(result),
            },
          },
        );
        _recordNativeToolResult(commandId, commandResult);
        appendLog(message);
        notifyListeners();
        return commandResult;
      case AppCommandId.runStaticAnalysis:
        final compilationDatabase = _nativeCompilationDatabaseArgument();
        if (compilationDatabase == '.' &&
            _hasWorkspaceFile('CMakeLists.txt') &&
            !_hasConfiguredCMakeBuild()) {
          final message =
              'Run Static Analysis blocked: run build first to generate compile_commands.json.';
          final commandResult = _NativeToolCommandResult(
            applied: false,
            message: message,
            metadata: const <String, Object?>{
              'requiredCommand': 'runBuild',
              'staticAnalysisResult': <String, Object?>{
                'runner': 'clang-tidy',
                'status': 'blocked',
                'reason': 'missing-compile-commands',
                'requiredCommand': 'runBuild',
              },
            },
          );
          _recordNativeToolResult(commandId, commandResult);
          appendLog(message);
          notifyListeners();
          return commandResult;
        }
        final analysisArguments = <String>[
          if (compilationDatabase != '.') ...<String>[
            '-p',
            compilationDatabase,
          ],
          _activeDocumentPath,
        ];
        final result = await manager.run(
          kind: ToolchainKind.staticAnalyzer,
          requirement: const ToolchainRequirement(
            kind: ToolchainKind.staticAnalyzer,
            metadata: <String, Object?>{'toolFamily': 'clang-tidy'},
          ),
          arguments: analysisArguments,
          workingDirectory: workspaceController.activeProject.workspaceRoot,
          timeout: const Duration(seconds: 45),
        );
        final diagnostics = _clangTidyDiagnosticsFromOutput(
          '${result.stdout}\n${result.stderr}',
        );
        if (diagnostics.isNotEmpty) {
          editorController.applyExternalDiagnostics(diagnostics);
        }
        final message = result.succeeded
            ? 'Run Static Analysis completed.'
            : _nativeToolFailureMessage(commandId, result.message);
        final commandResult = _NativeToolCommandResult(
          applied: result.succeeded,
          message: message,
          metadata: <String, Object?>{
            'staticAnalysisResult': <String, Object?>{
              'runner': 'clang-tidy',
              'status': result.succeeded ? 'passed' : 'failed',
              'compilationDatabase': compilationDatabase,
              'arguments': analysisArguments,
              'diagnosticCount': diagnostics.length,
              ..._nativeToolProcessMetadata(result),
            },
          },
          diagnostics: diagnostics,
        );
        _recordNativeToolResult(commandId, commandResult);
        appendLog(message);
        notifyListeners();
        return commandResult;
      case AppCommandId.runTests:
        final testDirectory = _nativeCTestDirectoryArgument();
        if (testDirectory == '.' &&
            _hasWorkspaceFile('CMakeLists.txt') &&
            !_hasConfiguredCTestBuild()) {
          final message =
              'Run Tests blocked: run build first to generate the CTest build directory.';
          final commandResult = _NativeToolCommandResult(
            applied: false,
            message: message,
            metadata: <String, Object?>{
              'requiredCommand': 'runBuild',
              'testResult': <String, Object?>{
                'runner': 'ctest',
                'status': 'blocked',
                'reason': 'missing-ctest-build-directory',
                'requiredCommand': 'runBuild',
              },
              ...backendRouteMetadata,
            },
          );
          _recordNativeToolResult(commandId, commandResult);
          appendLog(message);
          notifyListeners();
          return commandResult;
        }
        final testArguments = <String>[
          if (testDirectory != '.') ...<String>['--test-dir', testDirectory],
          '--output-on-failure',
        ];
        final result = await manager.run(
          kind: ToolchainKind.testRunner,
          requirement: const ToolchainRequirement(
            kind: ToolchainKind.testRunner,
            metadata: <String, Object?>{'toolFamily': 'ctest'},
          ),
          arguments: testArguments,
          workingDirectory: workspaceController.activeProject.workspaceRoot,
          timeout: const Duration(seconds: 120),
        );
        final testResult = <String, Object?>{
          ..._ctestResultFromOutput(
            '${result.stdout}\n${result.stderr}',
            succeeded: result.succeeded,
          ),
          'testDirectory': testDirectory,
          'arguments': testArguments,
          ..._nativeToolProcessMetadata(result),
        };
        final message = result.succeeded
            ? 'Run Tests completed.'
            : _nativeToolFailureMessage(commandId, result.message);
        final commandResult = _NativeToolCommandResult(
          applied: result.succeeded,
          message: message,
          metadata: <String, Object?>{
            'testResult': testResult,
            ...backendRouteMetadata,
          },
        );
        _recordNativeToolResult(commandId, commandResult);
        appendLog(message);
        notifyListeners();
        return commandResult;
      case AppCommandId.save:
      case AppCommandId.saveAll:
      case AppCommandId.run:
      case AppCommandId.fetchDependencies:
      case AppCommandId.vendorDependencies:
      case AppCommandId.useActiveCompiler:
      case AppCommandId.pinActiveCompiler:
      case AppCommandId.clearPinnedCompiler:
      case AppCommandId.bootstrapStyioToolchain:
      case AppCommandId.executeToolchainInstallPlan:
      case AppCommandId.selectClangCppVersion:
      case AppCommandId.packProject:
      case AppCommandId.preparePublish:
      case AppCommandId.showRuntime:
      case AppCommandId.showAgent:
      case AppCommandId.showDebug:
      case AppCommandId.toggleBreakpoint:
      case AppCommandId.startDebugging:
      case AppCommandId.stopDebugging:
      case AppCommandId.continueDebugging:
      case AppCommandId.stepOver:
      case AppCommandId.selectDebugThread:
      case AppCommandId.selectDebugStackFrame:
      case AppCommandId.nextDiagnostic:
      case AppCommandId.previousDiagnostic:
      case AppCommandId.applyQuickFix:
      case AppCommandId.previewQuickFix:
      case AppCommandId.refreshLanguageService:
      case AppCommandId.refreshWorkspaceDiagnostics:
      case AppCommandId.refreshSourceControl:
      case AppCommandId.previewSourceControlDiff:
      case AppCommandId.stageSourceControl:
      case AppCommandId.unstageSourceControl:
      case AppCommandId.planSourceControlBranchSwitch:
      case AppCommandId.planSourceControlCommitDraft:
      case AppCommandId.collectAgentCodingCheckpoint:
      case AppCommandId.collectProjectLanguageContext:
      case AppCommandId.retryAgentProvider:
      case AppCommandId.failoverAgentProvider:
      case AppCommandId.replayAgentPrompt:
      case AppCommandId.openWorkspaceFile:
      case AppCommandId.createWorkspaceFile:
      case AppCommandId.renameWorkspaceFile:
      case AppCommandId.deleteWorkspaceFile:
      case AppCommandId.revealWorkspaceFile:
      case AppCommandId.searchWorkspace:
      case AppCommandId.previewWorkspaceReplace:
      case AppCommandId.applyWorkspaceReplace:
      case AppCommandId.rerunFailedTests:
      case AppCommandId.debugFailedTests:
      case AppCommandId.runTestConfiguration:
      case AppCommandId.debugTestConfiguration:
      case AppCommandId.goToDefinition:
      case AppCommandId.nextReference:
      case AppCommandId.previousReference:
      case AppCommandId.renameSymbol:
      case AppCommandId.safeDelete:
      case AppCommandId.inlineVariable:
      case AppCommandId.refreshModules:
      case AppCommandId.openSettings:
        final message =
            '${_nativeToolCommandLabel(commandId)} skipped: not a native tool command.';
        final commandResult = _NativeToolCommandResult(
          applied: false,
          message: message,
        );
        _recordNativeToolResult(commandId, commandResult);
        appendLog(message);
        notifyListeners();
        return commandResult;
      default:
        throw UnimplementedError('AppCommandId.$commandId not implemented');
    }
  }

  Map<String, Object?> _nativeToolBackendRouteMetadata(AppCommandId commandId) {
    switch (commandId) {
      case AppCommandId.runBuild:
      case AppCommandId.runTests:
        return <String, Object?>{
          'backendRouteSelection': selectBackendExecutionRoute(
            platformTarget: platformTarget,
            projectGraph: workspaceController.activeProject,
            adapterCapabilities: adapterCapabilities,
          ).toJson(),
        };
      case AppCommandId.formatActiveDocument:
      case AppCommandId.runStaticAnalysis:
      case AppCommandId.save:
      case AppCommandId.saveAll:
      case AppCommandId.run:
      case AppCommandId.rerunFailedTests:
      case AppCommandId.debugFailedTests:
      case AppCommandId.runTestConfiguration:
      case AppCommandId.debugTestConfiguration:
      case AppCommandId.fetchDependencies:
      case AppCommandId.vendorDependencies:
      case AppCommandId.useActiveCompiler:
      case AppCommandId.pinActiveCompiler:
      case AppCommandId.clearPinnedCompiler:
      case AppCommandId.bootstrapStyioToolchain:
      case AppCommandId.executeToolchainInstallPlan:
      case AppCommandId.selectClangCppVersion:
      case AppCommandId.packProject:
      case AppCommandId.preparePublish:
      case AppCommandId.showRuntime:
      case AppCommandId.showAgent:
      case AppCommandId.showDebug:
      case AppCommandId.toggleBreakpoint:
      case AppCommandId.startDebugging:
      case AppCommandId.stopDebugging:
      case AppCommandId.continueDebugging:
      case AppCommandId.stepOver:
      case AppCommandId.selectDebugThread:
      case AppCommandId.selectDebugStackFrame:
      case AppCommandId.nextDiagnostic:
      case AppCommandId.previousDiagnostic:
      case AppCommandId.applyQuickFix:
      case AppCommandId.previewQuickFix:
      case AppCommandId.refreshLanguageService:
      case AppCommandId.refreshWorkspaceDiagnostics:
      case AppCommandId.refreshSourceControl:
      case AppCommandId.previewSourceControlDiff:
      case AppCommandId.stageSourceControl:
      case AppCommandId.unstageSourceControl:
      case AppCommandId.planSourceControlBranchSwitch:
      case AppCommandId.planSourceControlCommitDraft:
      case AppCommandId.collectAgentCodingCheckpoint:
      case AppCommandId.collectProjectLanguageContext:
      case AppCommandId.retryAgentProvider:
      case AppCommandId.failoverAgentProvider:
      case AppCommandId.replayAgentPrompt:
      case AppCommandId.openWorkspaceFile:
      case AppCommandId.createWorkspaceFile:
      case AppCommandId.renameWorkspaceFile:
      case AppCommandId.deleteWorkspaceFile:
      case AppCommandId.revealWorkspaceFile:
      case AppCommandId.searchWorkspace:
      case AppCommandId.previewWorkspaceReplace:
      case AppCommandId.applyWorkspaceReplace:
      case AppCommandId.goToDefinition:
      case AppCommandId.nextReference:
      case AppCommandId.previousReference:
      case AppCommandId.renameSymbol:
      case AppCommandId.safeDelete:
      case AppCommandId.inlineVariable:
      case AppCommandId.refreshModules:
      case AppCommandId.openSettings:
        return const <String, Object?>{};
      default:
        throw UnimplementedError('AppCommandId.$commandId not implemented');
    }
  }

  String _nativeToolCommandLabel(AppCommandId commandId) {
    return StyioCommandRegistry.descriptorFor(commandId).label;
  }

  void _recordNativeToolResult(
    AppCommandId commandId,
    _NativeToolCommandResult result,
  ) {
    _nativeToolResults.insert(
      0,
      NativeToolResultRecord(
        command: commandId,
        label: _nativeToolCommandLabel(commandId),
        applied: result.applied,
        message: result.message,
        metadata: result.metadata,
        diagnostics: List<Diagnostic>.unmodifiable(result.diagnostics),
        completedAt: DateTime.now().toUtc(),
      ),
    );
    if (_nativeToolResults.length > _maxNativeToolResultRecords) {
      _nativeToolResults.removeRange(
        _maxNativeToolResultRecords,
        _nativeToolResults.length,
      );
    }
    _syncTestingSessionFromNativeToolResult(commandId, result);
  }

  void _syncTestingSessionFromNativeToolResult(
    AppCommandId commandId,
    _NativeToolCommandResult result,
  ) {
    if (commandId != AppCommandId.runTests) {
      return;
    }
    final controller = testingSessionController;
    if (controller == null) {
      return;
    }
    final metadata = result.metadata['testResult'];
    if (metadata is Map<String, Object?>) {
      controller.recordRunResult(
        _testRunResultFromNativeToolMetadata(metadata, message: result.message),
      );
      return;
    }
    if (metadata is Map) {
      controller.recordRunResult(
        _testRunResultFromNativeToolMetadata(
          metadata.map((key, value) => MapEntry(key.toString(), value)),
          message: result.message,
        ),
      );
    }
  }

  TestRunResult _testRunResultFromNativeToolMetadata(
    Map<String, Object?> metadata, {
    required String message,
  }) {
    final runner = metadata['runner']?.toString() ?? 'native-tool';
    final cases = _failedTestCasesFromNativeToolMetadata(metadata);
    return TestRunResult(
      providerId: 'native-tool-runTests',
      runner: runner,
      status: _testRunStatusFromNativeToolMetadata(metadata['status']),
      message: message,
      totalCount: _intFromNativeToolMetadata(metadata['totalCount']) ?? 0,
      passedCount: _intFromNativeToolMetadata(metadata['passedCount']) ?? 0,
      failedCount: _intFromNativeToolMetadata(metadata['failedCount']) ?? 0,
      skippedCount: _intFromNativeToolMetadata(metadata['skippedCount']) ?? 0,
      cases: cases,
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  List<TestCaseResult> _failedTestCasesFromNativeToolMetadata(
    Map<String, Object?> metadata,
  ) {
    final value = metadata['failedTests'];
    if (value is! List) {
      return const <TestCaseResult>[];
    }
    return value
        .whereType<Map>()
        .map((entry) {
          final normalized = entry.map(
            (key, value) => MapEntry(key.toString(), value),
          );
          return TestCaseResult(
            id: normalized['id']?.toString() ?? '',
            name: normalized['name']?.toString() ?? 'unknown',
            status: _testRunStatusFromNativeToolMetadata(
              normalized['status'] ?? 'failed',
            ),
            message: normalized['message']?.toString() ?? '',
          );
        })
        .toList(growable: false);
  }

  TestRunStatus _testRunStatusFromNativeToolMetadata(Object? value) {
    return switch (value?.toString()) {
      'passed' => TestRunStatus.passed,
      'failed' => TestRunStatus.failed,
      'skipped' => TestRunStatus.skipped,
      'not-run' || 'blocked' => TestRunStatus.notRun,
      _ => TestRunStatus.error,
    };
  }

  int? _intFromNativeToolMetadata(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '');
  }

  bool openFirstNativeToolDiagnostic(AppCommandId commandId) {
    NativeToolResultRecord? target;
    for (final result in _nativeToolResults) {
      if (result.command == commandId && result.diagnostics.isNotEmpty) {
        target = result;
        break;
      }
    }
    if (target == null) {
      appendLog(
        '${_nativeToolCommandLabel(commandId)} diagnostic navigation skipped: no diagnostic result is available.',
      );
      return false;
    }
    final selected = editorController.selectDiagnostic(
      target.diagnostics.first,
    );
    appendLog(
      selected
          ? '${target.label} diagnostic selected in editor.'
          : '${target.label} diagnostic navigation failed: range is no longer valid.',
    );
    return selected;
  }

  DebugCommandResult toggleBreakpointAtSelection() {
    final position = editorController.document.positionForOffset(
      editorController.selection.extentOffset,
    );
    final breakpoint = DebugBreakpoint(
      filePath: _activeDocumentPath,
      line: position.line,
    );
    final existingIndex = _debugBreakpoints.indexWhere(
      (candidate) => candidate.key == breakpoint.key,
    );
    final added = existingIndex < 0;
    if (added) {
      _debugBreakpoints.add(breakpoint);
    } else {
      _debugBreakpoints.removeAt(existingIndex);
    }
    _refreshDebugSessionBreakpoints();
    final message =
        '${added ? 'Added' : 'Removed'} breakpoint at ${breakpoint.filePath}:${breakpoint.line + 1}.';
    appendLog(message);
    notifyListeners();
    return DebugCommandResult(applied: true, message: message);
  }

  Future<DebugCommandResult> startDebugging() async {
    final manager = toolchainManager;
    if (manager == null) {
      return _setDebugSession(
        const DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message:
              'Start Debugging blocked: no toolchain manager is available.',
        ),
      );
    }
    final catalog = await manager.loadCatalog();
    final activeDebugger =
        catalog.active(ToolchainKind.debugger) ??
        (() {
          final debuggers = catalog.list(kind: ToolchainKind.debugger);
          return debuggers.isEmpty ? null : debuggers.first;
        })();
    if (activeDebugger == null) {
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Start Debugging blocked: no native debugger is registered.',
          breakpoints: debugBreakpoints,
        ),
      );
    }
    final launchConfiguration =
        DebugLaunchConfiguration.fromToolchainDescriptor(
          debugger: activeDebugger,
          workspaceRoot: workspaceController.activeProject.workspaceRoot,
          breakpoints: debugBreakpoints
              .map(
                (breakpoint) => DebugLaunchBreakpoint(
                  filePath: breakpoint.filePath,
                  line: breakpoint.line,
                  enabled: breakpoint.enabled,
                ),
              )
              .toList(growable: false),
        );
    if (!launchConfiguration.ready) {
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: launchConfiguration.reason,
          debuggerId: activeDebugger.id,
          debuggerLabel: activeDebugger.displayName,
          breakpoints: debugBreakpoints,
          launchConfiguration: launchConfiguration,
        ),
      );
    }
    final launcher = debugAdapterLauncher;
    if (launcher != null) {
      try {
        final executionPlan = DapDebugAdapterExecutionPlan.fromConfiguration(
          profileId: activeDebugger.id,
          launchConfiguration: launchConfiguration,
        );
        final executionResult = await DebugRuntimeExecutionAdapter(
          launcher: launcher,
          workspaceId: workspaceController.activeProject.workspaceRoot,
        ).executePlan(plan: executionPlan, buffer: runtimeOutputBuffer);
        _lastDebugRuntimeExecutionResult = executionResult;
        if (!executionResult.launched || executionResult.handle == null) {
          final record = executionResult.telemetry.records.isEmpty
              ? null
              : executionResult.telemetry.records.first;
          return _setDebugSession(
            DebugSessionSnapshot(
              status: DebugSessionStatus.blocked,
              message:
                  record?.message ?? executionResult.dispatchResult.message,
              debuggerId: activeDebugger.id,
              debuggerLabel: activeDebugger.displayName,
              breakpoints: debugBreakpoints,
              launchConfiguration: launchConfiguration,
            ),
          );
        }
        final sessionHandle = executionResult.handle!;
        final previousSession = _dapDebugSession;
        await _dapDebugSessionSubscription?.cancel();
        _dapDebugSessionSubscription = null;
        _dapDebugSession = sessionHandle;
        _dapDebugSessionSubscription = sessionHandle.snapshotEvents.listen(
          _handleDapDebugSessionSnapshot,
        );
        if (previousSession != null) {
          unawaited(previousSession.close());
        }
        final adapterSnapshot = sessionHandle.snapshot;
        return _setDebugSession(
          DebugSessionSnapshot(
            status: _debugStatusFromDapSession(adapterSnapshot.status),
            message:
                'Debug adapter launch plan sent with ${adapterSnapshot.pendingRequests.length} pending DAP request(s).',
            debuggerId: activeDebugger.id,
            debuggerLabel: activeDebugger.displayName,
            breakpoints: debugBreakpoints,
            launchConfiguration: launchConfiguration,
            adapterSessionStatus: adapterSnapshot.status.name,
            adapterPendingRequestCount: adapterSnapshot.pendingRequests.length,
            adapterEventCount: adapterSnapshot.events.length,
          ),
        );
      } on Object catch (error) {
        _dapDebugSession = null;
        return _setDebugSession(
          DebugSessionSnapshot(
            status: DebugSessionStatus.blocked,
            message: 'Start Debugging failed: $error',
            debuggerId: activeDebugger.id,
            debuggerLabel: activeDebugger.displayName,
            breakpoints: debugBreakpoints,
            launchConfiguration: launchConfiguration,
          ),
        );
      }
    }
    return _setDebugSession(
      DebugSessionSnapshot(
        status: DebugSessionStatus.configured,
        message:
            'Debug session configured with ${activeDebugger.displayName} for ${launchConfiguration.programPath}; process launch adapter is not attached yet.',
        debuggerId: activeDebugger.id,
        debuggerLabel: activeDebugger.displayName,
        breakpoints: debugBreakpoints,
        launchConfiguration: launchConfiguration,
      ),
    );
  }

  Future<DebugCommandResult> stopDebugging() async {
    final sessionHandle = _dapDebugSession;
    _dapDebugSession = null;
    await _dapDebugSessionSubscription?.cancel();
    _dapDebugSessionSubscription = null;
    if (sessionHandle != null) {
      await sessionHandle.sendRequest(
        const DapProtocolRequestFactory().disconnect(
          seq: sessionHandle.bridge.session.reserveSeq(),
        ),
      );
      final adapterSnapshot = sessionHandle.snapshot;
      unawaited(sessionHandle.close());
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.stopped,
          message: 'Stop Debugging request sent to DAP adapter.',
          breakpoints: debugBreakpoints,
          launchConfiguration: _debugSession.launchConfiguration,
          adapterSessionStatus: adapterSnapshot.status.name,
          adapterPendingRequestCount: adapterSnapshot.pendingRequests.length,
          adapterEventCount: adapterSnapshot.events.length,
        ),
      );
    }
    return _setDebugSession(
      DebugSessionSnapshot(
        status: DebugSessionStatus.stopped,
        message: 'Debug session stopped.',
        breakpoints: debugBreakpoints,
      ),
    );
  }

  bool refreshDebugAdapterSession() {
    final sessionHandle = _dapDebugSession;
    if (sessionHandle == null) {
      appendLog('Debug adapter refresh skipped: no DAP session is active.');
      notifyListeners();
      return false;
    }
    final adapterSnapshot = sessionHandle.snapshot;
    _syncDebugSessionFromDapSnapshot(
      adapterSnapshot,
      message:
          'Debug adapter session refreshed: ${adapterSnapshot.status.name}.',
    );
    return true;
  }

  Future<DebugCommandResult> continueDebugging() async {
    if (_debugSession.status != DebugSessionStatus.paused) {
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Continue Debugging blocked: no paused debug session.',
          breakpoints: debugBreakpoints,
        ),
      );
    }
    final sessionHandle = _dapDebugSession;
    if (sessionHandle != null) {
      final adapterSnapshot = sessionHandle.snapshot;
      final threadId = adapterSnapshot.activeThreadId;
      if (threadId == null) {
        return _setDebugSession(
          DebugSessionSnapshot(
            status: DebugSessionStatus.blocked,
            message:
                'Continue Debugging blocked: DAP stopped event did not provide a threadId.',
            breakpoints: debugBreakpoints,
            launchConfiguration: _debugSession.launchConfiguration,
            adapterSessionStatus: adapterSnapshot.status.name,
            adapterPendingRequestCount: adapterSnapshot.pendingRequests.length,
            adapterEventCount: adapterSnapshot.events.length,
          ),
        );
      }
      await sessionHandle.sendRequest(
        const DapProtocolRequestFactory().continueThread(
          seq: sessionHandle.bridge.session.reserveSeq(),
          threadId: threadId,
        ),
      );
      final refreshed = sessionHandle.snapshot;
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.running,
          message: 'Continue Debugging request sent to DAP adapter.',
          debuggerId: _debugSession.debuggerId,
          debuggerLabel: _debugSession.debuggerLabel,
          breakpoints: debugBreakpoints,
          threads: _debugSession.threads,
          stackFrames: _debugSession.stackFrames,
          variables: _debugSession.variables,
          launchConfiguration: _debugSession.launchConfiguration,
          adapterSessionStatus: refreshed.status.name,
          adapterPendingRequestCount: refreshed.pendingRequests.length,
          adapterEventCount: refreshed.events.length,
        ),
      );
    }
    return _setDebugSession(
      DebugSessionSnapshot(
        status: DebugSessionStatus.running,
        message: 'Debug session continued.',
        debuggerId: _debugSession.debuggerId,
        debuggerLabel: _debugSession.debuggerLabel,
        breakpoints: debugBreakpoints,
        threads: _debugSession.threads,
        stackFrames: _debugSession.stackFrames,
        variables: _debugSession.variables,
        launchConfiguration: _debugSession.launchConfiguration,
        adapterSessionStatus: _debugSession.adapterSessionStatus,
        adapterPendingRequestCount: _debugSession.adapterPendingRequestCount,
        adapterEventCount: _debugSession.adapterEventCount,
      ),
    );
  }

  Future<DebugCommandResult> stepOver() async {
    if (_debugSession.status != DebugSessionStatus.paused) {
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Step Over blocked: no paused debug session.',
          breakpoints: debugBreakpoints,
        ),
      );
    }
    final sessionHandle = _dapDebugSession;
    if (sessionHandle != null) {
      final adapterSnapshot = sessionHandle.snapshot;
      final threadId = adapterSnapshot.activeThreadId;
      if (threadId == null) {
        return _setDebugSession(
          DebugSessionSnapshot(
            status: DebugSessionStatus.blocked,
            message:
                'Step Over blocked: DAP stopped event did not provide a threadId.',
            breakpoints: debugBreakpoints,
            launchConfiguration: _debugSession.launchConfiguration,
            adapterSessionStatus: adapterSnapshot.status.name,
            adapterPendingRequestCount: adapterSnapshot.pendingRequests.length,
            adapterEventCount: adapterSnapshot.events.length,
          ),
        );
      }
      await sessionHandle.sendRequest(
        const DapProtocolRequestFactory().next(
          seq: sessionHandle.bridge.session.reserveSeq(),
          threadId: threadId,
        ),
      );
      final refreshed = sessionHandle.snapshot;
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.running,
          message: 'Step Over request sent to DAP adapter.',
          debuggerId: _debugSession.debuggerId,
          debuggerLabel: _debugSession.debuggerLabel,
          breakpoints: debugBreakpoints,
          threads: _debugSession.threads,
          stackFrames: _debugSession.stackFrames,
          variables: _debugSession.variables,
          launchConfiguration: _debugSession.launchConfiguration,
          adapterSessionStatus: refreshed.status.name,
          adapterPendingRequestCount: refreshed.pendingRequests.length,
          adapterEventCount: refreshed.events.length,
        ),
      );
    }
    return _setDebugSession(
      DebugSessionSnapshot(
        status: DebugSessionStatus.paused,
        message: 'Step Over completed.',
        debuggerId: _debugSession.debuggerId,
        debuggerLabel: _debugSession.debuggerLabel,
        breakpoints: debugBreakpoints,
        threads: _debugSession.threads,
        stackFrames: _debugSession.stackFrames,
        variables: _debugSession.variables,
        launchConfiguration: _debugSession.launchConfiguration,
        adapterSessionStatus: _debugSession.adapterSessionStatus,
        adapterPendingRequestCount: _debugSession.adapterPendingRequestCount,
        adapterEventCount: _debugSession.adapterEventCount,
      ),
    );
  }

  Future<DebugCommandResult> selectDebugStackFrame(String frameId) async {
    if (_debugSession.status != DebugSessionStatus.paused) {
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Select Debug Stack Frame blocked: no paused debug session.',
          breakpoints: debugBreakpoints,
          threads: _debugSession.threads,
          stackFrames: _debugSession.stackFrames,
          variables: _debugSession.variables,
          launchConfiguration: _debugSession.launchConfiguration,
          adapterSessionStatus: _debugSession.adapterSessionStatus,
          adapterPendingRequestCount: _debugSession.adapterPendingRequestCount,
          adapterEventCount: _debugSession.adapterEventCount,
        ),
      );
    }
    final sessionHandle = _dapDebugSession;
    if (sessionHandle == null) {
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message:
              'Select Debug Stack Frame blocked: no DAP session is active.',
          breakpoints: debugBreakpoints,
          threads: _debugSession.threads,
          stackFrames: _debugSession.stackFrames,
          variables: _debugSession.variables,
          launchConfiguration: _debugSession.launchConfiguration,
          adapterSessionStatus: _debugSession.adapterSessionStatus,
          adapterPendingRequestCount: _debugSession.adapterPendingRequestCount,
          adapterEventCount: _debugSession.adapterEventCount,
        ),
      );
    }
    final frameIdValue = int.tryParse(frameId);
    if (frameIdValue == null) {
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message:
              'Select Debug Stack Frame blocked: invalid frame id $frameId.',
          breakpoints: debugBreakpoints,
          threads: _debugSession.threads,
          stackFrames: _debugSession.stackFrames,
          variables: _debugSession.variables,
          launchConfiguration: _debugSession.launchConfiguration,
          adapterSessionStatus: _debugSession.adapterSessionStatus,
          adapterPendingRequestCount: _debugSession.adapterPendingRequestCount,
          adapterEventCount: _debugSession.adapterEventCount,
        ),
      );
    }
    final adapterSnapshot = sessionHandle.snapshot;
    final frameExists = adapterSnapshot.stackFrames.any(
      (frame) => frame.id == frameIdValue,
    );
    if (!frameExists) {
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message:
              'Select Debug Stack Frame blocked: frame $frameId was not found.',
          breakpoints: debugBreakpoints,
          threads: _debugSession.threads,
          stackFrames: _debugSession.stackFrames,
          variables: _debugSession.variables,
          launchConfiguration: _debugSession.launchConfiguration,
          adapterSessionStatus: adapterSnapshot.status.name,
          adapterPendingRequestCount: adapterSnapshot.pendingRequests.length,
          adapterEventCount: adapterSnapshot.events.length,
        ),
      );
    }
    await sessionHandle.sendRequest(
      const DapProtocolRequestFactory().scopes(
        seq: sessionHandle.bridge.session.reserveSeq(),
        frameId: frameIdValue,
      ),
    );
    final refreshed = sessionHandle.snapshot;
    return _setDebugSession(
      DebugSessionSnapshot(
        status: DebugSessionStatus.paused,
        message:
            'Select Debug Stack Frame request sent to DAP adapter for frame $frameId.',
        debuggerId: _debugSession.debuggerId,
        debuggerLabel: _debugSession.debuggerLabel,
        breakpoints: debugBreakpoints,
        threads: _debugSession.threads,
        stackFrames: _debugSession.stackFrames,
        variables: const <DebugVariable>[],
        launchConfiguration: _debugSession.launchConfiguration,
        adapterSessionStatus: refreshed.status.name,
        adapterPendingRequestCount: refreshed.pendingRequests.length,
        adapterEventCount: refreshed.events.length,
      ),
    );
  }

  Future<DebugCommandResult> selectDebugThread(String threadId) async {
    if (_debugSession.status != DebugSessionStatus.paused) {
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Select Debug Thread blocked: no paused debug session.',
          breakpoints: debugBreakpoints,
          threads: _debugSession.threads,
          stackFrames: _debugSession.stackFrames,
          variables: _debugSession.variables,
          launchConfiguration: _debugSession.launchConfiguration,
          adapterSessionStatus: _debugSession.adapterSessionStatus,
          adapterPendingRequestCount: _debugSession.adapterPendingRequestCount,
          adapterEventCount: _debugSession.adapterEventCount,
        ),
      );
    }
    final sessionHandle = _dapDebugSession;
    if (sessionHandle == null) {
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Select Debug Thread blocked: no DAP session is active.',
          breakpoints: debugBreakpoints,
          threads: _debugSession.threads,
          stackFrames: _debugSession.stackFrames,
          variables: _debugSession.variables,
          launchConfiguration: _debugSession.launchConfiguration,
          adapterSessionStatus: _debugSession.adapterSessionStatus,
          adapterPendingRequestCount: _debugSession.adapterPendingRequestCount,
          adapterEventCount: _debugSession.adapterEventCount,
        ),
      );
    }
    final threadIdValue = int.tryParse(threadId);
    if (threadIdValue == null) {
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message: 'Select Debug Thread blocked: invalid thread id $threadId.',
          breakpoints: debugBreakpoints,
          threads: _debugSession.threads,
          stackFrames: _debugSession.stackFrames,
          variables: _debugSession.variables,
          launchConfiguration: _debugSession.launchConfiguration,
          adapterSessionStatus: _debugSession.adapterSessionStatus,
          adapterPendingRequestCount: _debugSession.adapterPendingRequestCount,
          adapterEventCount: _debugSession.adapterEventCount,
        ),
      );
    }
    final adapterSnapshot = sessionHandle.snapshot;
    final threadExists = adapterSnapshot.threads.any(
      (thread) => thread.id == threadIdValue,
    );
    if (!threadExists) {
      return _setDebugSession(
        DebugSessionSnapshot(
          status: DebugSessionStatus.blocked,
          message:
              'Select Debug Thread blocked: thread $threadId was not found.',
          breakpoints: debugBreakpoints,
          threads: _debugSession.threads,
          stackFrames: _debugSession.stackFrames,
          variables: _debugSession.variables,
          launchConfiguration: _debugSession.launchConfiguration,
          adapterSessionStatus: adapterSnapshot.status.name,
          adapterPendingRequestCount: adapterSnapshot.pendingRequests.length,
          adapterEventCount: adapterSnapshot.events.length,
        ),
      );
    }
    await sessionHandle.sendRequest(
      const DapProtocolRequestFactory().stackTrace(
        seq: sessionHandle.bridge.session.reserveSeq(),
        threadId: threadIdValue,
      ),
    );
    final refreshed = sessionHandle.snapshot;
    return _setDebugSession(
      DebugSessionSnapshot(
        status: DebugSessionStatus.paused,
        message:
            'Select Debug Thread request sent to DAP adapter for thread $threadId.',
        debuggerId: _debugSession.debuggerId,
        debuggerLabel: _debugSession.debuggerLabel,
        breakpoints: debugBreakpoints,
        threads: _debugSession.threads,
        stackFrames: const <DebugStackFrame>[],
        variables: const <DebugVariable>[],
        launchConfiguration: _debugSession.launchConfiguration,
        adapterSessionStatus: refreshed.status.name,
        adapterPendingRequestCount: refreshed.pendingRequests.length,
        adapterEventCount: refreshed.events.length,
      ),
    );
  }

  DebugCommandResult _setDebugSession(DebugSessionSnapshot snapshot) {
    _debugSession = DebugSessionSnapshot(
      status: snapshot.status,
      message: snapshot.message,
      debuggerId: snapshot.debuggerId,
      debuggerLabel: snapshot.debuggerLabel,
      breakpoints: List<DebugBreakpoint>.unmodifiable(snapshot.breakpoints),
      threads: List<DebugThread>.unmodifiable(snapshot.threads),
      stackFrames: List<DebugStackFrame>.unmodifiable(snapshot.stackFrames),
      variables: List<DebugVariable>.unmodifiable(snapshot.variables),
      launchConfiguration: snapshot.launchConfiguration,
      adapterSessionStatus: snapshot.adapterSessionStatus,
      adapterPendingRequestCount: snapshot.adapterPendingRequestCount,
      adapterEventCount: snapshot.adapterEventCount,
    );
    appendLog(snapshot.message);
    notifyListeners();
    return DebugCommandResult(
      applied:
          snapshot.status != DebugSessionStatus.blocked &&
          snapshot.status != DebugSessionStatus.idle,
      message: snapshot.message,
    );
  }

  void _handleDapDebugSessionSnapshot(DapSessionSnapshot adapterSnapshot) {
    _syncDebugSessionFromDapSnapshot(
      adapterSnapshot,
      message: 'Debug adapter session updated: ${adapterSnapshot.status.name}.',
    );
    _queueDebugRuntimeTaskHistoryAppend(adapterSnapshot);
    if (adapterSnapshot.status == DapSessionStatus.terminated ||
        adapterSnapshot.status == DapSessionStatus.failed) {
      final sessionHandle = _dapDebugSession;
      _dapDebugSession = null;
      _dapInspectionRequestInFlight = false;
      final subscription = _dapDebugSessionSubscription;
      _dapDebugSessionSubscription = null;
      unawaited(subscription?.cancel());
      if (sessionHandle != null) {
        unawaited(sessionHandle.close());
      }
      return;
    }
    _requestPausedDapInspectionFacts(adapterSnapshot);
  }

  void _queueDebugRuntimeTaskHistoryAppend(DapSessionSnapshot adapterSnapshot) {
    _debugRuntimeTaskHistoryAppendQueue = _debugRuntimeTaskHistoryAppendQueue
        .then((_) => _appendDebugRuntimeTaskHistory(adapterSnapshot));
    unawaited(_debugRuntimeTaskHistoryAppendQueue);
  }

  Future<void> _appendDebugRuntimeTaskHistory(
    DapSessionSnapshot adapterSnapshot,
  ) async {
    final store = debugRuntimeTaskHistoryStore;
    final launch = _debugSession.launchConfiguration;
    if (store == null || launch == null) {
      return;
    }
    try {
      await debugRuntimeTaskHistoryBinder.appendSnapshot(
        store: store,
        workspaceId: debugRuntimeTaskHistoryWorkspaceId,
        launch: launch,
        adapterSnapshot: adapterSnapshot,
        taskId: 'debug.${launch.debuggerId}',
        maxEntries: debugRuntimeTaskHistoryMaxEntries,
      );
    } on Object {
      // TODO: route async debug history persistence failures into a runtime
      // diagnostics channel that is safe after ShellRuntimeModel disposal.
    }
  }

  void _requestPausedDapInspectionFacts(DapSessionSnapshot adapterSnapshot) {
    if (_dapInspectionRequestInFlight) {
      return;
    }
    final sessionHandle = _dapDebugSession;
    if (sessionHandle == null) {
      return;
    }
    final request = _nextDapInspectionRequest(adapterSnapshot, sessionHandle);
    if (request == null) {
      return;
    }
    _dapInspectionRequestInFlight = true;
    unawaited(
      (() async {
        try {
          await sessionHandle.sendRequest(request);
        } on Object catch (error) {
          appendLog('DAP inspection request failed: $error');
          notifyListeners();
        } finally {
          _dapInspectionRequestInFlight = false;
        }
      })(),
    );
  }

  DapRequest? _nextDapInspectionRequest(
    DapSessionSnapshot adapterSnapshot,
    DapDebugSessionHandle sessionHandle,
  ) {
    if (adapterSnapshot.status != DapSessionStatus.paused) {
      return null;
    }
    const requestFactory = DapProtocolRequestFactory();
    if (adapterSnapshot.stackFrames.isEmpty) {
      final threadId =
          adapterSnapshot.activeThreadId ??
          _firstInspectableThreadId(adapterSnapshot.threads);
      if (threadId == null) {
        if (_hasPendingDapCommand(adapterSnapshot, 'threads')) {
          return null;
        }
        return requestFactory.threads(
          seq: sessionHandle.bridge.session.reserveSeq(),
        );
      }
      if (_hasPendingDapCommand(adapterSnapshot, 'stackTrace')) {
        return null;
      }
      return requestFactory.stackTrace(
        seq: sessionHandle.bridge.session.reserveSeq(),
        threadId: threadId,
      );
    }
    if (adapterSnapshot.scopes.isEmpty) {
      if (_hasPendingDapCommand(adapterSnapshot, 'scopes')) {
        return null;
      }
      return requestFactory.scopes(
        seq: sessionHandle.bridge.session.reserveSeq(),
        frameId: adapterSnapshot.stackFrames.first.id,
      );
    }
    if (adapterSnapshot.variables.isEmpty) {
      if (_hasPendingDapCommand(adapterSnapshot, 'variables')) {
        return null;
      }
      final variablesReference = _firstScopeVariablesReference(
        adapterSnapshot.scopes,
      );
      if (variablesReference == null) {
        return null;
      }
      return requestFactory.variables(
        seq: sessionHandle.bridge.session.reserveSeq(),
        variablesReference: variablesReference,
      );
    }
    return null;
  }

  bool _hasPendingDapCommand(
    DapSessionSnapshot adapterSnapshot,
    String command,
  ) {
    return adapterSnapshot.pendingRequests.any(
      (request) => request.command == command,
    );
  }

  int? _firstScopeVariablesReference(List<DapScope> scopes) {
    for (final scope in scopes) {
      if (scope.variablesReference > 0) {
        return scope.variablesReference;
      }
    }
    return null;
  }

  int? _firstInspectableThreadId(List<DapThread> threads) {
    for (final thread in threads) {
      if (thread.id > 0) {
        return thread.id;
      }
    }
    return null;
  }

  void _syncDebugSessionFromDapSnapshot(
    DapSessionSnapshot adapterSnapshot, {
    required String message,
  }) {
    _setDebugSession(
      DebugSessionSnapshot(
        status: _debugStatusFromDapSession(adapterSnapshot.status),
        message: message,
        debuggerId: _debugSession.debuggerId,
        debuggerLabel: _debugSession.debuggerLabel,
        breakpoints: debugBreakpoints,
        threads: adapterSnapshot.threads
            .map(
              (thread) =>
                  DebugThread(id: thread.id.toString(), name: thread.name),
            )
            .toList(growable: false),
        stackFrames: adapterSnapshot.stackFrames
            .map(
              (frame) => DebugStackFrame(
                id: frame.id.toString(),
                name: frame.name,
                filePath: frame.sourcePath,
                line: frame.line,
                column: frame.column,
              ),
            )
            .toList(growable: false),
        variables: adapterSnapshot.variables
            .map(
              (variable) => DebugVariable(
                name: variable.name,
                value: variable.value,
                type: variable.type,
              ),
            )
            .toList(growable: false),
        launchConfiguration: _debugSession.launchConfiguration,
        adapterSessionStatus: adapterSnapshot.status.name,
        adapterPendingRequestCount: adapterSnapshot.pendingRequests.length,
        adapterEventCount: adapterSnapshot.events.length,
      ),
    );
  }

  void _refreshDebugSessionBreakpoints() {
    _debugSession = DebugSessionSnapshot(
      status: _debugSession.status,
      message: _debugSession.message,
      debuggerId: _debugSession.debuggerId,
      debuggerLabel: _debugSession.debuggerLabel,
      breakpoints: debugBreakpoints,
      threads: _debugSession.threads,
      stackFrames: _debugSession.stackFrames,
      variables: _debugSession.variables,
      launchConfiguration: _debugSession.launchConfiguration,
      adapterSessionStatus: _debugSession.adapterSessionStatus,
      adapterPendingRequestCount: _debugSession.adapterPendingRequestCount,
      adapterEventCount: _debugSession.adapterEventCount,
    );
  }

  DebugSessionStatus _debugStatusFromDapSession(DapSessionStatus status) {
    return switch (status) {
      DapSessionStatus.idle => DebugSessionStatus.configured,
      DapSessionStatus.initializing ||
      DapSessionStatus.launching => DebugSessionStatus.launching,
      DapSessionStatus.running => DebugSessionStatus.running,
      DapSessionStatus.paused => DebugSessionStatus.paused,
      DapSessionStatus.terminated => DebugSessionStatus.stopped,
      DapSessionStatus.failed => DebugSessionStatus.blocked,
    };
  }

  String _nativeToolFailureMessage(AppCommandId commandId, String? detail) {
    final suffix = detail == null || detail.trim().isEmpty
        ? ''
        : ': ${detail.trim()}';
    return '${_nativeToolCommandLabel(commandId)} failed$suffix.';
  }

  Map<String, Object?> _nativeToolProcessMetadata(
    ToolchainRuntimeResult result,
  ) {
    return <String, Object?>{
      if (result.exitCode != null) 'exitCode': result.exitCode,
      'stdoutLength': result.stdout.length,
      'stderrLength': result.stderr.length,
      if (result.stdout.trim().isNotEmpty)
        'stdoutPreview': _nativeToolOutputPreview(result.stdout),
      if (result.stderr.trim().isNotEmpty)
        'stderrPreview': _nativeToolOutputPreview(result.stderr),
    };
  }

  String _nativeToolOutputPreview(String output, {int limit = 4000}) {
    final normalized = output.trim();
    if (normalized.length <= limit) {
      return normalized;
    }
    return '${normalized.substring(0, limit)}...';
  }

  String _nativeBuildDirectoryArgument() {
    final files = _normalizedWorkspaceFiles();
    if (files.any(
      (path) =>
          path == 'build/compile_commands.json' ||
          path == 'build/CMakeCache.txt' ||
          path == 'build/build.ninja',
    )) {
      return 'build';
    }
    return '.';
  }

  Set<String> _normalizedWorkspaceFiles() {
    return workspaceController.files
        .map((path) => path.replaceAll('\\', '/'))
        .toSet();
  }

  bool _hasWorkspaceFile(String filePath) {
    return _normalizedWorkspaceFiles().contains(filePath);
  }

  bool _hasConfiguredCMakeBuild() {
    final files = _normalizedWorkspaceFiles();
    return files.contains('build/compile_commands.json') ||
        files.contains('build/CMakeCache.txt');
  }

  bool _hasNinjaBuild() {
    final files = _normalizedWorkspaceFiles();
    return files.contains('build/build.ninja') || files.contains('build.ninja');
  }

  String _nativeCTestDirectoryArgument() {
    final files = _normalizedWorkspaceFiles();
    if (files.contains('build/CTestTestfile.cmake') ||
        files.contains('build/CMakeCache.txt')) {
      return 'build';
    }
    return '.';
  }

  bool _hasConfiguredCTestBuild() {
    final files = _normalizedWorkspaceFiles();
    return files.contains('build/CTestTestfile.cmake') ||
        files.contains('build/CMakeCache.txt');
  }

  String _nativeCompilationDatabaseArgument() {
    final files = _normalizedWorkspaceFiles();
    if (files.contains('build/compile_commands.json')) {
      return 'build';
    }
    return '.';
  }

  Future<bool> _hasBuildToolFamily(
    ToolchainManager manager,
    String toolFamily,
  ) async {
    final catalog = await manager.loadCatalog();
    return catalog.list(kind: ToolchainKind.buildTool).any((descriptor) {
      return descriptor.metadata['toolFamily'] == toolFamily;
    });
  }

  Future<List<String>> _nativeCMakeConfigureArguments(
    ToolchainManager manager, {
    required String buildDirectory,
  }) async {
    final selection = await _loadClangCppSelection(manager);
    return <String>[
      '-S',
      '.',
      '-B',
      buildDirectory,
      ...?selection?.cmakeNinjaConfigureArguments,
    ];
  }

  void _registerGeneratedCMakeBuildArtifacts({
    required String buildDirectory,
    required List<String> configureArguments,
  }) {
    if (buildDirectory == '.') {
      return;
    }
    workspaceController.registerFile('$buildDirectory/CMakeCache.txt');
    workspaceController.registerFile('$buildDirectory/compile_commands.json');
    if (configureArguments.contains('Ninja')) {
      workspaceController.registerFile('$buildDirectory/build.ninja');
    }
  }

  Future<ClangCppVersionSelection?> _loadClangCppSelection(
    ToolchainManager manager,
  ) async {
    final snapshot =
        toolchainStatusReport?.value.snapshot ?? await manager.snapshot();
    return ClangCppVersionManager.fromSnapshot(
      snapshot,
      preference: _clangCppVersionPreference,
    ).select();
  }

  List<Diagnostic> _clangBuildDiagnosticsFromOutput(String output) {
    final diagnostics = <Diagnostic>[];
    final pattern = RegExp(
      r'^(.+?):(\d+):(\d+):\s*(warning|error|fatal error|note):\s*(.+)$',
    );
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final match = pattern.firstMatch(line.trim());
      if (match == null) {
        continue;
      }
      final path = match.group(1) ?? '';
      if (!_isActiveDocumentPath(path)) {
        continue;
      }
      final lineNumber = int.tryParse(match.group(2) ?? '');
      final columnNumber = int.tryParse(match.group(3) ?? '');
      if (lineNumber == null || columnNumber == null) {
        continue;
      }
      final start = _offsetForLineColumn(lineNumber, columnNumber);
      if (start == null) {
        continue;
      }
      diagnostics.add(
        Diagnostic(
          severity: _clangBuildSeverity(match.group(4) ?? ''),
          code: 'native-build',
          message: (match.group(5) ?? '').trim(),
          range: SourceRange(
            start: start,
            end: start < editorController.document.length ? start + 1 : start,
          ),
        ),
      );
    }
    return diagnostics;
  }

  List<Diagnostic> _clangTidyDiagnosticsFromOutput(String output) {
    final diagnostics = <Diagnostic>[];
    final pattern = RegExp(
      r'^(.+?):(\d+):(\d+):\s*(warning|error|note):\s*(.+)$',
    );
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final match = pattern.firstMatch(line.trim());
      if (match == null) {
        continue;
      }
      final path = match.group(1) ?? '';
      if (!_isActiveDocumentPath(path)) {
        continue;
      }
      final lineNumber = int.tryParse(match.group(2) ?? '');
      final columnNumber = int.tryParse(match.group(3) ?? '');
      if (lineNumber == null || columnNumber == null) {
        continue;
      }
      final start = _offsetForLineColumn(lineNumber, columnNumber);
      if (start == null) {
        continue;
      }
      final rawMessage = match.group(5) ?? '';
      final checkMatch = RegExp(r'\s+\[([^\]]+)\]\s*$').firstMatch(rawMessage);
      final code = checkMatch?.group(1) ?? 'clang-tidy';
      final message = checkMatch == null
          ? rawMessage.trim()
          : rawMessage.substring(0, checkMatch.start).trim();
      diagnostics.add(
        Diagnostic(
          severity: _clangTidySeverity(match.group(4) ?? ''),
          code: code,
          message: message.isEmpty ? 'clang-tidy diagnostic' : message,
          range: SourceRange(
            start: start,
            end: start < editorController.document.length ? start + 1 : start,
          ),
        ),
      );
    }
    return diagnostics;
  }

  bool _isActiveDocumentPath(String path) {
    final normalized = path.replaceAll('\\', '/');
    final active = _activeDocumentPath.replaceAll('\\', '/');
    final documentId = editorController.document.documentId.replaceAll(
      '\\',
      '/',
    );
    return normalized == active ||
        normalized == documentId ||
        normalized.endsWith('/$active') ||
        normalized.endsWith('/$documentId');
  }

  int? _offsetForLineColumn(int lineNumber, int columnNumber) {
    if (lineNumber < 1 || columnNumber < 1) {
      return null;
    }
    final text = editorController.document.text;
    var line = 1;
    var lineStart = 0;
    while (line < lineNumber) {
      final nextBreak = text.indexOf('\n', lineStart);
      if (nextBreak < 0) {
        return null;
      }
      lineStart = nextBreak + 1;
      line += 1;
    }
    final lineEnd = text.indexOf('\n', lineStart);
    final end = lineEnd < 0 ? text.length : lineEnd;
    final offset = lineStart + columnNumber - 1;
    if (offset < lineStart) {
      return lineStart;
    }
    if (offset > end) {
      return end;
    }
    return offset;
  }

  DiagnosticSeverity _clangTidySeverity(String severity) {
    return switch (severity) {
      'error' => DiagnosticSeverity.error,
      'note' => DiagnosticSeverity.hint,
      _ => DiagnosticSeverity.warning,
    };
  }

  DiagnosticSeverity _clangBuildSeverity(String severity) {
    return switch (severity) {
      'error' || 'fatal error' => DiagnosticSeverity.error,
      'note' => DiagnosticSeverity.hint,
      _ => DiagnosticSeverity.warning,
    };
  }

  Map<String, Object?> _ctestResultFromOutput(
    String output, {
    required bool succeeded,
  }) {
    int? totalCount;
    int? failedCount;
    int? passedCount;
    final failedTests = <Map<String, Object?>>[];
    final summaryPattern = RegExp(
      r'(\d+)% tests passed,\s*(\d+) tests failed out of\s*(\d+)',
    );
    final failedTestPattern = RegExp(r'^\s*\d+\s+-\s+(.+?)\s+\((.+)\)\s*$');
    for (final line in output.split(RegExp(r'\r?\n'))) {
      final summary = summaryPattern.firstMatch(line);
      if (summary != null) {
        failedCount = int.tryParse(summary.group(2) ?? '');
        totalCount = int.tryParse(summary.group(3) ?? '');
        if (totalCount != null && failedCount != null) {
          passedCount = totalCount - failedCount;
        }
        continue;
      }
      final failedTest = failedTestPattern.firstMatch(line);
      if (failedTest != null) {
        failedTests.add(<String, Object?>{
          'name': failedTest.group(1)?.trim() ?? '',
          'status': failedTest.group(2)?.trim() ?? 'failed',
        });
      }
    }
    return <String, Object?>{
      'runner': 'ctest',
      'status': succeeded && (failedCount ?? 0) == 0 ? 'passed' : 'failed',
      if (totalCount != null) 'totalCount': totalCount,
      if (passedCount != null) 'passedCount': passedCount,
      if (failedCount != null) 'failedCount': failedCount,
      if (failedTests.isNotEmpty) 'failedTests': failedTests,
    };
  }

  Future<bool> openWorkspaceFileForAgent(String filePath) async {
    final normalizedPath = filePath.trim();
    if (normalizedPath.isEmpty) {
      appendLog('Agent command openWorkspaceFile skipped: missing input.');
      return false;
    }
    if (!workspaceController.files.contains(normalizedPath)) {
      appendLog(
        'Agent command openWorkspaceFile skipped: $normalizedPath is not in the workspace file list.',
      );
      notifyListeners();
      return false;
    }
    _suppressWorkspaceChangedLoad = true;
    try {
      workspaceController.openFile(normalizedPath);
    } finally {
      _suppressWorkspaceChangedLoad = false;
    }
    await _loadActiveWorkspaceDocument();
    if (workspaceController.activeFilePath == normalizedPath &&
        editorController.document.documentId == normalizedPath) {
      appendLog('Agent command openWorkspaceFile opened $normalizedPath.');
      notifyListeners();
      return true;
    }
    appendLog('Agent command openWorkspaceFile failed for $normalizedPath.');
    notifyListeners();
    return false;
  }

  Future<bool> selectWorkspaceDiagnostic(WorkspaceDiagnostic entry) async {
    final opened = entry.documentId == editorController.document.documentId
        ? true
        : await openWorkspaceFileForAgent(entry.documentId);
    if (!opened) {
      appendLog(
        'Workspace diagnostic selection skipped: ${entry.documentId} could not be opened.',
      );
      notifyListeners();
      return false;
    }
    editorController.selectRange(
      baseOffset: entry.diagnostic.range.start,
      extentOffset: entry.diagnostic.range.end,
    );
    appendLog(
      'Workspace diagnostic selected: ${entry.diagnostic.code} in ${entry.documentId}.',
    );
    notifyListeners();
    return true;
  }

  Future<bool> goToProjectDefinitionAtSelection() async {
    final activeDocumentId = editorController.document.documentId;
    final offset = editorController.selection.extentOffset;
    final documents = await _loadProjectLanguageDocuments();
    final definitions = projectLanguageService.definitionsAt(
      documents: documents,
      documentId: activeDocumentId,
      offset: offset,
    );
    if (definitions.isEmpty) {
      appendLog(
        'Project definition skipped: no visible project definition at selection.',
      );
      notifyListeners();
      return false;
    }
    final definition = definitions.first;
    if (definition.documentId != workspaceController.activeFilePath) {
      final opened = await openWorkspaceFileForAgent(definition.documentId);
      if (!opened) {
        appendLog(
          'Project definition skipped: ${definition.documentId} could not be opened.',
        );
        notifyListeners();
        return false;
      }
    }
    editorController.selectRange(
      baseOffset: definition.range.start,
      extentOffset: definition.range.end,
    );
    appendLog(
      'Project definition selected: ${definition.name} in ${definition.documentId}.',
    );
    notifyListeners();
    return true;
  }

  Future<bool> selectProjectReferenceAtSelection({
    required bool forward,
  }) async {
    final activeDocumentId = editorController.document.documentId;
    final offset = editorController.selection.extentOffset;
    final documents = await _loadProjectLanguageDocuments();
    final references =
        projectLanguageService
            .referencesAt(
              documents: documents,
              documentId: activeDocumentId,
              offset: offset,
            )
            .toList(growable: false)
          ..sort(_compareProjectSymbolReferences);
    if (references.isEmpty) {
      appendLog(
        'Project reference skipped: no visible project references at selection.',
      );
      notifyListeners();
      return false;
    }

    final target = _projectReferenceNavigationTarget(
      references: references,
      activeDocumentId: activeDocumentId,
      offset: offset,
      forward: forward,
    );
    if (target.documentId != editorController.document.documentId) {
      final opened = await openWorkspaceFileForAgent(target.documentId);
      if (!opened) {
        appendLog(
          'Project reference skipped: ${target.documentId} could not be opened.',
        );
        notifyListeners();
        return false;
      }
    }
    editorController.selectRange(
      baseOffset: target.range.start,
      extentOffset: target.range.end,
    );
    appendLog(
      'Project reference selected: ${target.name} in ${target.documentId}.',
    );
    notifyListeners();
    return true;
  }

  StyioProjectSymbolReference _projectReferenceNavigationTarget({
    required List<StyioProjectSymbolReference> references,
    required String activeDocumentId,
    required int offset,
    required bool forward,
  }) {
    final currentIndex = references.indexWhere(
      (reference) =>
          reference.documentId == activeDocumentId &&
          _rangeContainsNavigationOffset(reference.range, offset),
    );
    if (currentIndex >= 0) {
      final targetIndex = forward
          ? (currentIndex + 1) % references.length
          : (currentIndex - 1 + references.length) % references.length;
      return references[targetIndex];
    }

    if (forward) {
      return references.firstWhere(
        (reference) =>
            _compareProjectReferencePosition(
              reference.documentId,
              reference.range.start,
              activeDocumentId,
              offset,
            ) >
            0,
        orElse: () => references.first,
      );
    }
    return references.lastWhere(
      (reference) =>
          _compareProjectReferencePosition(
            reference.documentId,
            reference.range.end,
            activeDocumentId,
            offset,
          ) <
          0,
      orElse: () => references.last,
    );
  }

  int _compareProjectSymbolReferences(
    StyioProjectSymbolReference left,
    StyioProjectSymbolReference right,
  ) {
    final documentCompare = left.documentId.compareTo(right.documentId);
    if (documentCompare != 0) {
      return documentCompare;
    }
    final startCompare = left.range.start.compareTo(right.range.start);
    if (startCompare != 0) {
      return startCompare;
    }
    return left.range.end.compareTo(right.range.end);
  }

  int _compareProjectReferencePosition(
    String leftDocumentId,
    int leftOffset,
    String rightDocumentId,
    int rightOffset,
  ) {
    final documentCompare = leftDocumentId.compareTo(rightDocumentId);
    if (documentCompare != 0) {
      return documentCompare;
    }
    return leftOffset.compareTo(rightOffset);
  }

  bool _rangeContainsNavigationOffset(SourceRange range, int offset) {
    return range.contains(offset) || offset == range.end;
  }

  Future<List<DocumentState>> _loadProjectLanguageDocuments() async {
    final documentsById = <String, DocumentState>{
      for (final document in _agentWorkspaceDocumentSamples)
        document.documentId: document,
    };
    for (final filePath in workspaceController.files) {
      if (documentsById.containsKey(filePath)) {
        continue;
      }
      if (!await workspaceDocumentStore.documentExists(filePath)) {
        continue;
      }
      documentsById[filePath] = await workspaceDocumentStore.loadDocument(
        filePath,
      );
    }
    return documentsById.values.toList(growable: false);
  }

  Future<bool> searchWorkspaceForAgent(String query) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      appendLog('Agent command searchWorkspace skipped: missing input.');
      return false;
    }
    final documents = <DocumentState>[];
    final seen = <String>{};
    for (final document in _agentWorkspaceDocumentSamples) {
      if (seen.add(document.documentId)) {
        documents.add(document);
      }
    }
    for (final filePath in workspaceController.files) {
      if (documents.length >= 100) {
        break;
      }
      if (!seen.add(filePath)) {
        continue;
      }
      try {
        documents.add(await workspaceDocumentStore.loadDocument(filePath));
      } on Object catch (error) {
        appendLog('Agent command searchWorkspace skipped $filePath: $error');
      }
    }
    _lastAgentWorkspaceSearch = AgentWorkspaceSearchResultContext.fromDocuments(
      query: normalizedQuery,
      documents: documents,
    );
    final symbolResult =
        await WorkspaceSymbolSearchService(
          documentStore: InMemoryWorkspaceDocumentStore(
            seededDocuments: <String, DocumentState>{
              for (final document in documents) document.documentId: document,
            },
          ),
          semanticSnapshotProvider: SemanticSnapshotProvider(
            languageService: projectLanguageService.documentService,
          ),
        ).searchSymbols(
          documentIds: documents.map((document) => document.documentId),
          query: normalizedQuery,
        );
    _lastAgentWorkspaceSymbolSearch =
        AgentWorkspaceSymbolSearchResultContext.fromWorkspaceResult(
          query: normalizedQuery,
          scannedDocumentCount: documents.length,
          result: symbolResult,
        );
    appendLog(
      'Agent command searchWorkspace found '
      '${_lastAgentWorkspaceSearch!.matchCount} text match(es) and '
      '${_lastAgentWorkspaceSymbolSearch!.matchCount} symbol match(es) for "$normalizedQuery".',
    );
    notifyListeners();
    return true;
  }

  Future<WorkspaceReplacePreview?> previewWorkspaceReplace({
    required String query,
    required String replacement,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      appendLog('Workspace replace preview skipped: missing search query.');
      return null;
    }
    final preview =
        await WorkspaceSearchService(
          documentStore: workspaceDocumentStore,
        ).previewReplaceAll(
          documentIds: workspaceController.files,
          query: normalizedQuery,
          replacement: replacement,
        );
    _lastWorkspaceReplacePreview = preview;
    appendLog(
      'Workspace replace preview found ${preview.replacementCount} '
      'replacement(s) across ${preview.documents.length} document(s).',
    );
    notifyListeners();
    return preview;
  }

  Future<WorkspaceReplaceResult?> applyWorkspaceReplacePreview(
    WorkspaceReplacePreview preview,
  ) async {
    if (preview.documents.isEmpty) {
      appendLog('Workspace replace apply skipped: no preview changes.');
      return null;
    }
    final result = await WorkspaceSearchService(
      documentStore: workspaceDocumentStore,
    ).applyReplacePreview(preview);
    for (final document in result.documents) {
      _documentCache.remove(document.documentId);
      _dirtyDocumentPaths.add(document.documentId);
    }
    WorkspaceReplacePreviewDocument? activePreviewDocument;
    for (final document in preview.documents) {
      if (document.documentId == workspaceController.activeFilePath) {
        activePreviewDocument = document;
        break;
      }
    }
    if (activePreviewDocument != null) {
      editorController.loadDocument(
        DocumentState(
          documentId: activePreviewDocument.documentId,
          text: activePreviewDocument.afterText,
          revision: activePreviewDocument.revision + 1,
        ),
      );
    }
    if (result.failures.isEmpty) {
      _lastWorkspaceReplacePreview = null;
    }
    appendLog(
      'Workspace replace apply changed ${result.replacementCount} '
      'replacement(s) across ${result.documents.length} document(s), '
      '${result.failures.length} failure(s).',
    );
    notifyListeners();
    return result;
  }

  void _syncAgentPatchDocumentCache(AgentCodePatchApplicationResult? result) {
    if (result == null || !result.applied) {
      return;
    }
    for (final documentId in result.createdDocumentIds) {
      workspaceController.registerFile(documentId);
    }
    for (final documentId in result.deletedDocumentIds) {
      if (documentId == _activeDocumentPath) {
        continue;
      }
      workspaceController.unregisterFile(documentId);
      _dirtyDocumentPaths.remove(documentId);
    }
    for (final documentId in result.appliedDocumentIds) {
      if (documentId == _activeDocumentPath) {
        continue;
      }
      _documentCache.remove(documentId);
      _documentCursorOffsets.remove(documentId);
      _documentSelectionAnchors.remove(documentId);
    }
  }

  Future<AgentProviderConfigurationResult?> saveAndMountAgentProfile(
    AgentPromptProfile profile, {
    String? bearerToken,
  }) async {
    final configurator = agentProviderConfigurator;
    if (configurator == null) {
      appendLog(
        'Agent provider profile save unavailable: no configurator is wired.',
      );
      return null;
    }
    final result = await configurator.saveAndMount(
      profile: profile,
      controller: agentCodingController,
      bearerToken: bearerToken,
      retryTelemetrySink: _publishAgentProviderRetryTelemetry,
    );
    await refreshAgentProviderProfileManifest();
    appendLog(result.message);
    return result;
  }

  Future<AgentProviderConfigurationResult?> failoverAgentProviderProfile(
    String profileKey,
  ) async {
    final configurator = agentProviderConfigurator;
    if (configurator == null) {
      appendLog(
        'Agent provider failover unavailable: no configurator is wired.',
      );
      return null;
    }
    final result = await configurator.mountSavedProfile(
      key: profileKey,
      controller: agentCodingController,
      retryTelemetrySink: _publishAgentProviderRetryTelemetry,
    );
    await refreshAgentProviderProfileManifest();
    appendLog(result.message);
    return result;
  }

  Future<bool> _dispatchAgentRecoveryCommand({
    required AgentIdeCommandSuggestion suggestion,
    required AgentCodingSessionRecoveryAction action,
    String? targetProviderProfileKey,
  }) async {
    final result = await agentCodingController.dispatchRecoveryRequestDraft(
      action,
      targetProviderProfileKey: targetProviderProfileKey,
      confirmed: true,
    );
    _recordAgentIdeCommandResult(
      suggestion,
      applied: result.dispatched,
      message: result.message,
      metadata: <String, Object?>{'recoveryDispatch': result.toJson()},
    );
    appendLog(result.message);
    notifyListeners();
    return result.dispatched;
  }

  Future<bool> _failoverAgentProviderForSuggestion(
    AgentIdeCommandSuggestion suggestion,
  ) async {
    final profileKey = suggestion.input?.trim() ?? '';
    if (profileKey.isEmpty) {
      const message =
          'Agent provider failover skipped: missing provider profile key.';
      _recordAgentIdeCommandResult(
        suggestion,
        applied: false,
        message: message,
        metadata: const <String, Object?>{'reason': 'missing-input'},
      );
      appendLog(message);
      notifyListeners();
      return false;
    }
    final result = await failoverAgentProviderProfile(profileKey);
    final message =
        result?.message ??
        'Agent provider failover unavailable: no configurator is wired.';
    _recordAgentIdeCommandResult(
      suggestion,
      applied: result?.mounted ?? false,
      message: message,
      metadata: <String, Object?>{
        'targetProviderProfileId': result?.profile.profileId,
        'targetProviderProfileKey': profileKey,
        'adapterKind': result?.adapterKind.wireValue,
        'adapterId': result?.adapterId,
        'retryEnabled': result?.retryEnabled,
      },
    );
    notifyListeners();
    return result?.mounted ?? false;
  }

  void _publishAgentProviderRetryTelemetry(
    AgentProviderRequest request,
    AgentProviderRetryExecution<AgentProviderResponseEnvelope> execution,
  ) {
    const binding = AgentProviderStreamRuntimeOutputBinding();
    runtimeOutputBuffer.addEvent(
      binding.retryEventFor(execution, requestId: request.requestId),
    );
  }

  Future<void> loadThemeOverride({String key = 'default'}) async {
    final store = themeOverrideStore;
    if (store == null) {
      appendLog('Theme override restore unavailable: no DataStore is wired.');
      return;
    }
    final override = await store.readOverride(
      workspaceId: workspaceController.activeProject.id,
      key: key,
    );
    if (override == null) {
      return;
    }
    _themeOverride = override;
    appendLog(
      'Theme override restored for ${workspaceController.activeProject.id}.',
    );
    notifyListeners();
  }

  Future<void> saveThemeOverride(
    VityoThemeOverride override, {
    String key = 'default',
  }) async {
    _themeOverride = override;
    final store = themeOverrideStore;
    if (store == null) {
      appendLog('Theme override applied without persistence.');
      notifyListeners();
      return;
    }
    await store.saveOverride(
      workspaceId: workspaceController.activeProject.id,
      key: key,
      override: override,
    );
    appendLog(
      'Theme override persisted for ${workspaceController.activeProject.id}.',
    );
    notifyListeners();
  }

  ToolchainInstallExecutionSurface? get toolchainInstallExecutionSurface {
    final result = _lastToolchainInstallExecutionResult;
    if (result == null) {
      return null;
    }
    return ToolchainInstallExecutionSurface.fromResult(result);
  }

  ToolchainStatusSurface get toolchainStatusSurface {
    final report = toolchainStatusReport?.value;
    if (report != null) {
      return ToolchainStatusSurface.fromManagerStatusReport(
        report,
        lastCommand: _lastToolchainCommand,
      );
    }
    return ToolchainStatusSurface.fromProjectToolchain(
      workspaceController.activeProject.toolchain,
      lastCommand: _lastToolchainCommand,
    );
  }

  ToolchainSettingsSurface get toolchainSettingsSurface {
    final report = toolchainStatusReport?.value;
    if (report != null) {
      return ToolchainSettingsSurface.fromManagerStatusReport(
        report,
        lastCommand: _lastToolchainCommand,
        clangCppVersionPreference: _clangCppVersionPreference,
      );
    }
    return ToolchainSettingsSurface.fromStatus(toolchainStatusSurface);
  }

  CommandPaletteDisplayPreferences get commandPalettePreferences {
    return commandPalettePreferenceController.state.preferences;
  }

  Future<CommandPaletteDisplayPreferences> loadCommandPalettePreferences({
    String? workspaceId,
  }) async {
    final store = commandPalettePreferencesStore;
    final targetWorkspaceId = workspaceId ?? editorSessionWorkspaceId;
    if (store == null) {
      final preferences = commandPalettePreferences.workspaceId.isEmpty
          ? CommandPaletteDisplayPreferences(workspaceId: targetWorkspaceId)
          : commandPalettePreferences;
      commandPalettePreferenceController.updatePreferences(preferences);
      appendLog(
        'Command palette preferences loaded from live defaults for ${preferences.workspaceId}.',
      );
      notifyListeners();
      return preferences;
    }
    try {
      final preferences = await store.readPreferences(
        workspaceId: targetWorkspaceId,
      );
      commandPalettePreferenceController.updatePreferences(preferences);
      appendLog(
        'Command palette preferences loaded for ${preferences.workspaceId}.',
      );
      notifyListeners();
      return preferences;
    } on Object catch (error) {
      appendLog('Command palette preferences load failed: $error');
      notifyListeners();
      return commandPalettePreferences;
    }
  }

  Future<void> saveCommandPalettePreferences(
    CommandPaletteDisplayPreferences preferences,
  ) async {
    var next = preferences;
    final store = commandPalettePreferencesStore;
    if (store != null) {
      try {
        next = await store.savePreferences(preferences);
      } on Object catch (error) {
        appendLog('Command palette preferences save failed: $error');
      }
    }
    commandPalettePreferenceController.updatePreferences(next);
    appendLog('Command palette preferences saved for ${next.workspaceId}.');
    notifyListeners();
  }

  void _handleCommandPalettePreferencesChanged(
    CommandPaletteLivePreferenceState state,
  ) {
    notifyListeners();
  }

  Future<ToolchainSelectionResult?> selectToolchainCandidate(String id) async {
    final manager = toolchainManager;
    if (manager == null) {
      appendLog(
        'Toolchain selection unavailable: no ToolchainManager is wired.',
      );
      notifyListeners();
      return null;
    }

    final result = await manager.selectToolchain(id);
    appendLog(
      result.succeeded
          ? 'Toolchain selected: ${result.toolchainId} (${result.kind?.wireValue ?? "unknown"}).'
          : 'Toolchain selection failed: ${result.message ?? result.status.name}.',
    );
    await _refreshToolchainStatusReportAfterSelection(result);
    notifyListeners();
    return result;
  }

  Future<ToolchainSelectionResult?> selectClangCppVersion(
    String versionId, {
    String? cppStandard,
  }) async {
    final manager = toolchainManager;
    if (manager == null) {
      appendLog(
        'Clang/C++ version selection unavailable: no ToolchainManager is wired.',
      );
      notifyListeners();
      return null;
    }

    final snapshotBeforeSelection =
        toolchainStatusReport?.value.snapshot ?? await manager.snapshot();
    final clangCppManager = ClangCppVersionManager.fromSnapshot(
      snapshotBeforeSelection,
      preference: _clangCppVersionPreference,
    );
    if (clangCppManager.candidateFor(versionId) == null) {
      final message =
          'Clang/C++ version selection failed: $versionId is not a registered Clang/C++ compiler candidate.';
      appendLog(message);
      notifyListeners();
      return ToolchainSelectionResult(
        status: ToolchainSelectionStatus.missing,
        kind: ToolchainKind.compiler,
        toolchainId: versionId,
        message: message,
        snapshot: snapshotBeforeSelection,
      );
    }

    final requestedCppStandard = cppStandard == null
        ? null
        : CppLanguageStandard.fromWireValue(cppStandard);
    if (cppStandard != null &&
        cppStandard.trim().isNotEmpty &&
        requestedCppStandard == null) {
      final supportedStandards = CppLanguageStandard.values
          .map((standard) => 'c++${standard.cmakeValue}')
          .join(', ');
      final message =
          'Clang/C++ version selection failed: unsupported C++ standard $cppStandard. Supported standards: $supportedStandards.';
      appendLog(message);
      notifyListeners();
      return ToolchainSelectionResult(
        status: ToolchainSelectionStatus.missing,
        kind: ToolchainKind.compiler,
        toolchainId: versionId,
        message: message,
        snapshot: snapshotBeforeSelection,
      );
    }

    final result = await manager.selectToolchain(versionId);
    if (result.succeeded) {
      final preference = ClangCppVersionPreference(
        versionId: versionId,
        cppStandard:
            requestedCppStandard ??
            _clangCppVersionPreference?.cppStandard ??
            CppLanguageStandard.cpp20,
      );
      await manager.saveClangCppVersionPreference(preference);
      _clangCppVersionPreference = preference;
    }
    appendLog(
      result.succeeded
          ? 'Clang/C++ version selected: ${result.toolchainId}.'
          : 'Clang/C++ version selection failed: ${result.message ?? result.status.name}.',
    );
    await _refreshToolchainStatusReportAfterSelection(result);
    notifyListeners();
    return result;
  }

  Future<ToolchainSelectionResult?> clearToolchainCandidate(
    ToolchainKind kind,
  ) async {
    final manager = toolchainManager;
    if (manager == null) {
      appendLog('Toolchain clear unavailable: no ToolchainManager is wired.');
      notifyListeners();
      return null;
    }

    final result = await manager.clearActiveToolchain(kind);
    appendLog(
      result.succeeded
          ? 'Toolchain active selection cleared: ${kind.wireValue}.'
          : 'Toolchain clear failed: ${result.message ?? result.status.name}.',
    );
    await _refreshToolchainStatusReportAfterSelection(result);
    notifyListeners();
    return result;
  }

  ToolchainInstallPlan? planManagedToolchainInstallation({
    ToolchainKind kind = ToolchainKind.languageService,
    ToolchainInstallPolicy policy = const ToolchainInstallPolicy(),
  }) {
    final manager = toolchainManager;
    if (manager == null) {
      appendLog(
        'Toolchain install planning unavailable: no ToolchainManager is wired.',
      );
      notifyListeners();
      return null;
    }
    final plan = manager.planInstallation(
      ToolchainInstallRequest(requirement: ToolchainRequirement(kind: kind)),
      policy: policy,
    );
    _lastToolchainInstallPlan = plan;
    appendLog(
      'Toolchain install plan ${plan.status.name}: ${plan.mode.name}'
      '${plan.message == null ? '' : ' (${plan.message})'}.',
    );
    notifyListeners();
    return plan;
  }

  Future<ToolchainInstallExecutionResult?>
  executeLastToolchainInstallPlan() async {
    final manager = toolchainManager;
    final plan = _lastToolchainInstallPlan;
    if (manager == null) {
      appendLog(
        'Toolchain install execution unavailable: no ToolchainManager is wired.',
      );
      notifyListeners();
      return null;
    }
    if (plan == null) {
      appendLog(
        'Toolchain install execution unavailable: no install plan is prepared.',
      );
      notifyListeners();
      return null;
    }
    if (plan.mode != ToolchainInstallMode.manualSelection) {
      appendLog(
        'Toolchain install execution blocked: ${plan.mode.name} requires an explicit confirmation flow.',
      );
      notifyListeners();
      return null;
    }

    final result = await manager.executeInstallPlan(plan);
    _lastToolchainInstallExecutionResult = result;
    appendLog(
      'Toolchain install execution ${result.status.name}: ${result.message ?? result.plan.mode.name}.',
    );
    await _refreshToolchainStatusReportAfterInstall(result);
    notifyListeners();
    return result;
  }

  Future<ToolchainManagerBootstrapSummary?> refreshToolchainBootstrapSummary({
    String reason = 'toolchain bootstrap refresh',
  }) async {
    final manager = toolchainManager;
    if (manager == null) {
      if (!_disposed) {
        appendLog(
          'Toolchain bootstrap summary unavailable: no ToolchainManager is wired.',
        );
      }
      return null;
    }
    try {
      final summary = await manager.bootstrapSummary();
      if (_disposed) {
        return summary;
      }
      _toolchainBootstrapSummary = summary;
      appendLog(
        'Toolchain bootstrap summary refreshed: '
        '${summary.ready ? 'ready' : 'actionable'} ($reason).',
      );
      return summary;
    } on Object catch (error) {
      if (!_disposed) {
        appendLog('Toolchain bootstrap summary refresh failed: $error');
      }
      return null;
    }
  }

  Future<ToolchainBootstrapActionDispatchResult?>
  handleToolchainBootstrapAction(String actionId) async {
    final summary =
        _toolchainBootstrapSummary ??
        await refreshToolchainBootstrapSummary(reason: 'action $actionId');
    if (summary == null) {
      final result = ToolchainBootstrapActionDispatchResult(
        status: ToolchainBootstrapActionDispatchStatus.blocked,
        actionId: actionId,
        message:
            'Toolchain bootstrap action blocked: no bootstrap summary is available.',
        todo:
            'TODO: provide a ToolchainManager before routing bootstrap actions.',
      );
      _lastToolchainBootstrapActionDispatch = result;
      notifyListeners();
      return result;
    }

    final fallbackInstallKind =
        _firstMissingStyioToolchainKind(summary) ??
        ToolchainKind.languageService;
    final router = ToolchainBootstrapActionRouter(
      onSettingsAction: _dispatchToolchainBootstrapSettingsAction,
      onInstallerAction: (step) {
        return _dispatchToolchainBootstrapInstallerAction(
          step,
          fallbackInstallKind: fallbackInstallKind,
        );
      },
      onProjectAction: (step) {
        return _dispatchToolchainBootstrapProjectAction(
          step,
          fallbackInstallKind: fallbackInstallKind,
        );
      },
    );
    final result = await router.dispatch(summary.executionPlan(), actionId);
    _lastToolchainBootstrapActionDispatch = result;
    appendLog(
      'Toolchain bootstrap action ${result.status.wireValue}: '
      '${result.actionId}${result.message.isEmpty ? '' : ' (${result.message})'}.',
    );
    notifyListeners();
    return result;
  }

  Future<ToolchainBootstrapActionDispatchResult>
  _dispatchToolchainBootstrapSettingsAction(
    ToolchainBootstrapActionStep step,
  ) async {
    if (step.actionId.startsWith('select-styio-')) {
      appendLog(
        'Toolchain bootstrap selection route requested: ${step.actionId}.',
      );
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Selection route requested.',
      );
    }
    if (step.actionId.startsWith('install-styio-')) {
      final kind =
          _toolchainKindForStyioBootstrapAction(step.actionId) ??
          ToolchainKind.languageService;
      final plan = planManagedToolchainInstallation(kind: kind);
      if (plan == null) {
        return ToolchainBootstrapActionDispatchResult.blocked(
          step,
          message: 'No managed install plan could be prepared.',
          todo:
              'TODO: bind Styio role install actions to the production installer flow.',
        );
      }
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Managed install plan prepared for ${kind.wireValue}.',
      );
    }
    if (step.actionId == 'open-toolchain-settings') {
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Toolchain settings route requested.',
      );
    }
    return ToolchainBootstrapActionDispatchResult.blocked(
      step,
      message: 'Settings bootstrap action is not implemented.',
      todo: 'TODO: bind ${step.actionId} to the concrete Settings UI action.',
    );
  }

  Future<ToolchainBootstrapActionDispatchResult>
  _dispatchToolchainBootstrapInstallerAction(
    ToolchainBootstrapActionStep step, {
    required ToolchainKind fallbackInstallKind,
  }) async {
    if (step.actionId == 'install-managed-styio-toolchain') {
      final plan = planManagedToolchainInstallation(kind: fallbackInstallKind);
      if (plan == null) {
        return ToolchainBootstrapActionDispatchResult.blocked(
          step,
          message: 'No managed install plan could be prepared.',
          todo:
              'TODO: bind managed Styio installer to production installer UX.',
        );
      }
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message:
            'Managed install plan prepared for ${fallbackInstallKind.wireValue}.',
      );
    }
    if (step.actionId == 'verify-styio-toolchain') {
      await refreshToolchainBootstrapSummary(reason: 'verify action');
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Styio toolchain verification refreshed.',
      );
    }
    return ToolchainBootstrapActionDispatchResult.blocked(
      step,
      message: 'Installer bootstrap action is not implemented.',
      todo: 'TODO: bind ${step.actionId} to the concrete installer executor.',
    );
  }

  Future<ToolchainBootstrapActionDispatchResult>
  _dispatchToolchainBootstrapProjectAction(
    ToolchainBootstrapActionStep step, {
    required ToolchainKind fallbackInstallKind,
  }) async {
    if (step.actionId == 'open-toolchain-settings') {
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Toolchain settings panel should stay focused.',
      );
    }
    if (step.actionId == 'bootstrap-styio-toolchain') {
      final summary = await refreshToolchainBootstrapSummary(
        reason: step.actionId,
      );
      if (summary?.ready ?? false) {
        return ToolchainBootstrapActionDispatchResult.dispatched(
          step,
          message: 'Project Styio toolchain bootstrap is already ready.',
        );
      }
      final plan = planManagedToolchainInstallation(kind: fallbackInstallKind);
      if (plan == null) {
        return ToolchainBootstrapActionDispatchResult.blocked(
          step,
          message: 'No project bootstrap install plan could be prepared.',
          todo:
              'TODO: bind project bootstrap to the production Styio installer runner.',
        );
      }
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message:
            'Project bootstrap prepared managed install plan for ${fallbackInstallKind.wireValue}.',
      );
    }
    if (step.actionId == 'validate-project-toolchain') {
      await refreshToolchainBootstrapSummary(reason: step.actionId);
      return ToolchainBootstrapActionDispatchResult.dispatched(
        step,
        message: 'Project toolchain bootstrap facts refreshed.',
      );
    }
    return ToolchainBootstrapActionDispatchResult.blocked(
      step,
      message: 'Project bootstrap action is not implemented.',
      todo:
          'TODO: bind ${step.actionId} to the concrete project bootstrap runner.',
    );
  }

  ToolchainKind? _toolchainKindForStyioBootstrapAction(String actionId) {
    for (final role in StyioToolchainRole.values) {
      if (actionId.endsWith(role.wireValue)) {
        return role.toolchainKind;
      }
    }
    return null;
  }

  ToolchainKind? _firstMissingStyioToolchainKind(
    ToolchainManagerBootstrapSummary summary,
  ) {
    for (final role in summary.styioLifecycle.missingRequiredRoles) {
      return role.role.toolchainKind;
    }
    return null;
  }

  Future<void> _refreshToolchainStatusReportAfterInstall(
    ToolchainInstallExecutionResult result,
  ) async {
    final manager = toolchainManager;
    final notifier = toolchainStatusReport;
    if (manager == null ||
        notifier is! ValueNotifier<ToolchainManagerStatusReport>) {
      return;
    }
    notifier.value = await manager.statusReport(
      kind: result.plan.requirement.kind,
    );
  }

  Future<void> _refreshToolchainStatusReportAfterSelection(
    ToolchainSelectionResult result,
  ) async {
    _lastToolchainSnapshot = result.snapshot;
    final manager = toolchainManager;
    final notifier = toolchainStatusReport;
    if (manager == null ||
        notifier is! ValueNotifier<ToolchainManagerStatusReport>) {
      return;
    }
    final kind = result.kind ?? notifier.value.requirement.kind;
    notifier.value = await manager.statusReport(kind: kind);
  }

  List<ModuleDefinition> get mountedModules => moduleRegistry.mountedModules;
  List<ModuleDefinition> get visibleModules => moduleRegistry.visibleModules;

  DocumentResourceBindingSnapshot markEditorResourceExternalChanged(
    DocumentState externalDocument,
  ) {
    final snapshot = _editorFileBinding.markExternalChanged(externalDocument);
    appendLog(
      snapshot.state == DocumentResourceBindingState.conflicted
          ? 'External change conflicted for ${externalDocument.documentId} '
                '(rev ${externalDocument.revision}).'
          : 'External change detected for ${externalDocument.documentId} '
                '(rev ${externalDocument.revision}).',
    );
    return snapshot;
  }

  DocumentResourceBindingSnapshot acceptEditorExternalChange() {
    final snapshot = _editorFileBinding.acceptExternalChange();
    final document = snapshot.document;
    if (document == null) {
      notifyListeners();
      return snapshot;
    }
    _cacheDocument(_activeDocumentPath, document);
    editorController.loadDocument(document);
    _dirtyDocumentPaths.remove(_activeDocumentPath);
    appendLog(
      'External change accepted for ${document.documentId} '
      '(rev ${document.revision}).',
    );
    return _editorFileBinding.snapshot;
  }

  WorkspaceFileCloseRequestResult requestCloseWorkspaceFile(String filePath) {
    if (_pathHasUnsavedChanges(filePath)) {
      final result = WorkspaceFileCloseRequestResult.blockedUnsavedChanges(
        filePath,
        canSave: filePath == _activeDocumentPath,
        canDiscard: filePath == _activeDocumentPath,
        canSwitchToFile: filePath != _activeDocumentPath,
      );
      _lastCloseRequestResult = result;
      appendLog(result.message);
      return result;
    }
    if (!workspaceController.openFilePaths.contains(filePath)) {
      final result = WorkspaceFileCloseRequestResult.notOpen(filePath);
      _lastCloseRequestResult = result;
      appendLog(result.message);
      return result;
    }
    workspaceController.closeFile(filePath);
    _dirtyDocumentPaths.remove(filePath);
    final result = WorkspaceFileCloseRequestResult.closedFile(filePath);
    _lastCloseRequestResult = result;
    appendLog(result.message);
    return result;
  }

  void clearCloseRequestResult() {
    _lastCloseRequestResult = null;
    notifyListeners();
  }

  void switchToCloseRequestFile() {
    final pendingClose = _lastCloseRequestResult;
    if (pendingClose == null || !pendingClose.requiresUserChoice) {
      return;
    }
    workspaceController.openFile(pendingClose.filePath);
    _dirtyDocumentPaths.add(pendingClose.filePath);
    _lastCloseRequestResult =
        WorkspaceFileCloseRequestResult.blockedUnsavedChanges(
          pendingClose.filePath,
        );
    appendLog('Close request focus switched to ${pendingClose.filePath}.');
  }

  Future<DocumentResourceBindingSnapshot>
  saveActiveWorkspaceFileChanges() async {
    await executeCommand(AppCommandId.save);
    final snapshot = _editorFileBinding.snapshot;
    if (snapshot.state == DocumentResourceBindingState.boundClean) {
      _dirtyDocumentPaths.remove(_activeDocumentPath);
      _lastCloseRequestResult = null;
      notifyListeners();
    }
    return snapshot;
  }

  Future<WorkspaceSaveAllResult> saveAllWorkspaceFileChanges() async {
    final dirtyDocumentIds = _dirtyDocumentPaths.toList(growable: false);
    if (dirtyDocumentIds.isEmpty) {
      const result = WorkspaceSaveAllResult(
        savedDocumentIds: <String>[],
        skippedDocumentIds: <String>[],
        message: 'Save all skipped: no dirty documents.',
      );
      appendLog(result.message);
      return result;
    }

    final savedDocumentIds = <String>[];
    final skippedDocumentIds = <String>[];
    if (dirtyDocumentIds.contains(_activeDocumentPath)) {
      if (editorController.document.documentId == _activeDocumentPath) {
        final snapshot = await saveActiveWorkspaceFileChanges();
        if (snapshot.state == DocumentResourceBindingState.boundClean) {
          savedDocumentIds.add(_activeDocumentPath);
        } else {
          skippedDocumentIds.add(_activeDocumentPath);
        }
      } else {
        final document = _documentCache[_activeDocumentPath];
        if (document == null) {
          skippedDocumentIds.add(_activeDocumentPath);
          appendLog(
            'Save all skipped $_activeDocumentPath: active document is still loading.',
          );
        } else {
          await workspaceDocumentStore.saveDocument(document);
          _dirtyDocumentPaths.remove(_activeDocumentPath);
          savedDocumentIds.add(_activeDocumentPath);
          appendLog('Saved active-path cached document $_activeDocumentPath.');
        }
      }
    }

    for (final documentId in dirtyDocumentIds) {
      if (documentId == _activeDocumentPath) {
        continue;
      }
      final document = _documentCache[documentId];
      if (document == null) {
        skippedDocumentIds.add(documentId);
        appendLog('Save all skipped $documentId: no cached dirty document.');
        continue;
      }
      try {
        await workspaceDocumentStore.saveDocument(document);
        _dirtyDocumentPaths.remove(documentId);
        savedDocumentIds.add(documentId);
        appendLog('Saved inactive dirty document $documentId.');
      } on Object catch (error) {
        skippedDocumentIds.add(documentId);
        appendLog('Save all failed for $documentId: $error');
      }
    }
    final pendingClose = _lastCloseRequestResult;
    if (pendingClose != null && skippedDocumentIds.isEmpty) {
      _lastCloseRequestResult = null;
    } else if (pendingClose != null &&
        pendingClose.requiresUserChoice &&
        !_dirtyDocumentPaths.contains(pendingClose.filePath)) {
      _lastCloseRequestResult = null;
    }

    final result = WorkspaceSaveAllResult(
      savedDocumentIds: List<String>.unmodifiable(savedDocumentIds),
      skippedDocumentIds: List<String>.unmodifiable(skippedDocumentIds),
      message: skippedDocumentIds.isEmpty
          ? 'Saved ${savedDocumentIds.length} dirty document(s).'
          : 'Saved ${savedDocumentIds.length} dirty document(s); skipped ${skippedDocumentIds.length}.',
    );
    appendLog(result.message);
    notifyListeners();
    return result;
  }

  Future<WorkspaceFileCloseRequestResult?>
  saveAndCloseRequestedWorkspaceFile() async {
    final pendingClose = _lastCloseRequestResult;
    if (pendingClose == null || !pendingClose.requiresUserChoice) {
      return pendingClose;
    }
    final filePath = pendingClose.filePath;
    final snapshot = await saveActiveWorkspaceFileChanges();
    if (snapshot.state != DocumentResourceBindingState.boundClean) {
      return _lastCloseRequestResult;
    }
    return requestCloseWorkspaceFile(filePath);
  }

  Future<DocumentResourceBindingSnapshot>
  discardActiveWorkspaceFileChanges() async {
    if (!_activeFileHasUnsavedChanges) {
      appendLog('Discard skipped: $_activeDocumentPath has no local changes.');
      return _editorFileBinding.snapshot;
    }

    final activePath = _activeDocumentPath;
    final openResult = await _editorFileBinding.open(activePath);
    final document = openResult.snapshot.document;
    if (document == null) {
      appendLog(
        'Discard failed for $activePath: backing resource unavailable.',
      );
      notifyListeners();
      return _editorFileBinding.snapshot;
    }

    _cacheDocument(activePath, document);
    editorController.loadDocument(document);
    _dirtyDocumentPaths.remove(activePath);
    _lastCloseRequestResult = null;
    appendLog(
      'Discarded local changes for $activePath (rev ${document.revision}).',
    );
    return _editorFileBinding.snapshot;
  }

  Future<WorkspaceFileCloseRequestResult?>
  discardAndCloseRequestedWorkspaceFile() async {
    final pendingClose = _lastCloseRequestResult;
    if (pendingClose == null || !pendingClose.requiresUserChoice) {
      return pendingClose;
    }
    final filePath = pendingClose.filePath;
    final snapshot = await discardActiveWorkspaceFileChanges();
    if (snapshot.state != DocumentResourceBindingState.boundClean) {
      return _lastCloseRequestResult;
    }
    return requestCloseWorkspaceFile(filePath);
  }

  Future<void> executeCommand(AppCommandId commandId) async {
    final blockedReason = blockedReasonForCommand(commandId);
    if (blockedReason != null) {
      appendLog(
        '${StyioCommandRegistry.descriptorFor(commandId).label} blocked: $blockedReason',
      );
      return;
    }

    switch (commandId) {
      case AppCommandId.save:
        _cacheDocument(_activeDocumentPath, editorController.document);
        _editorFileBinding.markDocumentChanged(editorController.document);
        final saveResult = await _editorFileBinding.save(
          editorController.document,
        );
        if (!saveResult.saved) {
          _dirtyDocumentPaths.add(_activeDocumentPath);
          appendLog(
            'Save blocked for ${workspaceController.activeFilePath}: '
            '${saveResult.message ?? saveResult.failureKind?.name ?? 'unknown failure'}.',
          );
          return;
        }
        _dirtyDocumentPaths.remove(_activeDocumentPath);
        appendLog(
          'Save requested for ${workspaceController.activeFilePath} '
          '(rev ${editorController.document.revision}).',
        );
        if (saveResult.snapshot.state ==
            DocumentResourceBindingState.boundClean) {
          await _refreshLanguageServiceAfterSave(
            workspaceController.activeFilePath,
          );
        }
        return;
      case AppCommandId.saveAll:
        await saveAllWorkspaceFileChanges();
        return;
      case AppCommandId.refreshLanguageService:
        await _refreshLanguageServiceForCommand();
        return;
      case AppCommandId.refreshWorkspaceDiagnostics:
        final snapshot = await refreshWorkspaceDiagnostics();
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: workspaceDiagnosticsController != null,
          message: _workspaceDiagnosticsRefreshMessage(snapshot),
          metadata: <String, Object?>{
            'workspaceDiagnostics': snapshot.toJson(),
          },
        );
        return;
      case AppCommandId.refreshSourceControl:
        final snapshot = await refreshSourceControlStatus();
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: snapshot.available,
          message: _sourceControlRefreshMessage(snapshot),
          metadata: <String, Object?>{'sourceControl': snapshot.toJson()},
        );
        return;
      case AppCommandId.previewSourceControlDiff:
        final snapshot = await previewSourceControlDiff(
          workspaceController.activeFilePath,
        );
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: snapshot.available,
          message: _sourceControlDiffPreviewMessage(snapshot),
          metadata: <String, Object?>{'sourceControlDiff': snapshot.toJson()},
        );
        return;
      case AppCommandId.stageSourceControl:
      case AppCommandId.unstageSourceControl:
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: false,
          message:
              '${StyioCommandRegistry.descriptorFor(commandId).label} requires changed file path input.',
          metadata: _agentCommandInputMetadata(commandId),
        );
        return;
      case AppCommandId.planSourceControlBranchSwitch:
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: false,
          message:
              '${StyioCommandRegistry.descriptorFor(commandId).label} requires target branch input.',
          metadata: _agentCommandInputMetadata(commandId),
        );
        return;
      case AppCommandId.planSourceControlCommitDraft:
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: false,
          message:
              '${StyioCommandRegistry.descriptorFor(commandId).label} requires commit message input.',
          metadata: _agentCommandInputMetadata(commandId),
        );
        return;
      case AppCommandId.collectAgentCodingCheckpoint:
        final metadata = await collectAgentCodingCheckpoint();
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: true,
          message: 'Agent coding checkpoint collected.',
          metadata: metadata,
        );
        return;
      case AppCommandId.collectProjectLanguageContext:
        final metadata = await collectProjectLanguageContext();
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: true,
          message: 'Project language context collected.',
          metadata: <String, Object?>{'projectLanguage': metadata},
        );
        return;
      case AppCommandId.retryAgentProvider:
        await _dispatchAgentRecoveryCommand(
          suggestion: AgentIdeCommandSuggestion(commandId: commandId.name),
          action: AgentCodingSessionRecoveryAction.retrySameProvider,
        );
        return;
      case AppCommandId.replayAgentPrompt:
        await _dispatchAgentRecoveryCommand(
          suggestion: AgentIdeCommandSuggestion(commandId: commandId.name),
          action: AgentCodingSessionRecoveryAction.replayPrompt,
        );
        return;
      case AppCommandId.failoverAgentProvider:
        appendLog('Fail Over Agent Provider requires caller-provided input.');
        return;
      case AppCommandId.run:
        final routeSelection = selectBackendExecutionRoute(
          platformTarget: platformTarget,
          projectGraph: workspaceController.activeProject,
          adapterCapabilities: adapterCapabilities,
        );
        if (!routeSelection.allowed) {
          _lastExecutionSession = ExecutionSession(
            sessionId: 'route-gate:${workspaceController.activeProject.id}',
            kind: 'run',
            status: ExecutionSessionStatus.blocked,
            statusMessage:
                routeSelection.blockedReason ?? 'Execution route blocked.',
            diagnostics: const <Diagnostic>[],
            stdoutEvents: const <ExecutionLogEvent>[],
            stderrEvents: const <ExecutionLogEvent>[],
          );
          _lastRuntimeEvents = const <RuntimeEventEnvelope>[];
          appendLog(
            'Run blocked by backend route selection '
            '(${routeSelection.routeKind.wireValue}/'
            '${routeSelection.adapterKind.wireValue}): '
            '${_lastExecutionSession!.statusMessage}',
          );
          notifyListeners();
          return;
        }
        appendLog(
          'Run route selected: ${routeSelection.routeKind.wireValue} '
          'via ${routeSelection.adapterKind.wireValue}.',
        );
        final runUnit = selectRunUnitForEditor(
          document: editorController.document,
          selection: editorController.selection,
        );
        final session = await executionAdapter.runActiveDocument(
          platformTarget: platformTarget,
          projectGraph: workspaceController.activeProject,
          document: editorController.document,
          activeFilePath: workspaceController.activeFilePath,
        );
        final rangedSession = _sessionWithRunUnit(session, runUnit);
        _lastExecutionSession = rangedSession;
        _lastRuntimeEvents = await runtimeEventAdapter
            .sessionEvents(rangedSession.sessionId)
            .toList();
        appendLog(
          'Run unit ${runUnit.kind.name}: '
          '${runUnit.range.start}-${runUnit.range.end}.',
        );
        appendLog(
          'Run ${rangedSession.status.name}: ${rangedSession.statusMessage}',
        );
        for (final event in rangedSession.stdoutEvents.take(3)) {
          appendLog('stdout: ${event.message}');
        }
        for (final event in rangedSession.stderrEvents.take(3)) {
          appendLog('stderr: ${event.message}');
        }
        if (rangedSession.diagnostics.isNotEmpty) {
          editorController.applyExternalDiagnostics(rangedSession.diagnostics);
          appendLog(
            'diagnostics: ${rangedSession.diagnostics.length} issue(s) returned by the execution route.',
          );
        }
        if (_lastRuntimeEvents.isNotEmpty) {
          appendLog(
            'runtime events: ${_lastRuntimeEvents.length} event(s) for session ${rangedSession.sessionId}.',
          );
          for (final event in _lastRuntimeEvents.take(4)) {
            appendLog('runtime: ${event.eventKind}');
          }
        }
        notifyListeners();
        return;
      case AppCommandId.fetchDependencies:
        await fetchDependencies();
        return;
      case AppCommandId.vendorDependencies:
        await vendorDependencies();
        return;
      case AppCommandId.useActiveCompiler:
        final compiler = workspaceController.activeProject.activeCompiler!;
        await useManagedCompiler(
          compilerVersion: compiler.compilerVersion,
          channel: compiler.channel,
        );
        return;
      case AppCommandId.pinActiveCompiler:
        final compiler = workspaceController.activeProject.activeCompiler!;
        await pinManagedCompiler(
          compilerVersion: compiler.compilerVersion,
          channel: compiler.channel,
        );
        return;
      case AppCommandId.clearPinnedCompiler:
        await clearPinnedCompiler();
        return;
      case AppCommandId.bootstrapStyioToolchain:
        await _applyAgentToolchainBootstrapCommand(
          AgentIdeCommandSuggestion(commandId: commandId.name),
        );
        return;
      case AppCommandId.executeToolchainInstallPlan:
        await _applyAgentToolchainInstallExecutionCommand(
          AgentIdeCommandSuggestion(commandId: commandId.name),
        );
        return;
      case AppCommandId.packProject:
        await packProject();
        return;
      case AppCommandId.preparePublish:
        await preparePublish();
        return;
      case AppCommandId.nextDiagnostic:
        if (editorController.selectNextDiagnosticAtSelection()) {
          appendLog('Next diagnostic selected in editor.');
        } else {
          appendLog('Next diagnostic skipped: no diagnostics available.');
        }
        notifyListeners();
        return;
      case AppCommandId.previousDiagnostic:
        if (editorController.selectPreviousDiagnosticAtSelection()) {
          appendLog('Previous diagnostic selected in editor.');
        } else {
          appendLog('Previous diagnostic skipped: no diagnostics available.');
        }
        notifyListeners();
        return;
      case AppCommandId.toggleBreakpoint:
        toggleBreakpointAtSelection();
        return;
      case AppCommandId.startDebugging:
        await startDebugging();
        return;
      case AppCommandId.stopDebugging:
        await stopDebugging();
        return;
      case AppCommandId.continueDebugging:
        await continueDebugging();
        return;
      case AppCommandId.stepOver:
        await stepOver();
        return;
      case AppCommandId.selectDebugThread:
        appendLog('Select Debug Thread requires caller-provided input.');
        return;
      case AppCommandId.selectDebugStackFrame:
        appendLog('Select Debug Stack Frame requires caller-provided input.');
        return;
      case AppCommandId.selectClangCppVersion:
        appendLog('Select Clang/C++ Version requires caller-provided input.');
        return;
      case AppCommandId.previewQuickFix:
        final preview = await previewFirstProjectWorkspaceQuickFix();
        _publishDiagnosticActionTelemetry(
          action: 'previewQuickFix',
          succeeded: preview?.canApply ?? false,
          message: preview?.canApply ?? false
              ? 'Quick fix preview collected.'
              : 'Quick fix preview skipped: no action available.',
          metadata: <String, Object?>{
            if (preview != null) 'workspaceEditPreview': preview.toJson(),
          },
        );
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: preview?.canApply ?? false,
          message: preview?.canApply ?? false
              ? 'Quick fix preview collected.'
              : 'Quick fix preview skipped: no action available.',
          metadata: <String, Object?>{
            if (preview != null) 'workspaceEditPreview': preview.toJson(),
          },
        );
        notifyListeners();
        return;
      case AppCommandId.applyQuickFix:
        if (editorController.applyFirstQuickFixAtSelection()) {
          _cacheDocument(_activeDocumentPath, editorController.document);
          _dirtyDocumentPaths.add(_activeDocumentPath);
          appendLog('Quick fix applied at editor selection.');
          _publishDiagnosticActionTelemetry(
            action: 'applyQuickFix',
            succeeded: true,
            message: 'Quick fix applied at editor selection.',
            metadata: const <String, Object?>{'scope': 'selection'},
          );
        } else if (await applyFirstProjectWorkspaceQuickFix()) {
          appendLog('Project workspace quick fix applied from editor command.');
          _publishDiagnosticActionTelemetry(
            action: 'applyQuickFix',
            succeeded: true,
            message: 'Project workspace quick fix applied from editor command.',
            metadata: const <String, Object?>{'scope': 'workspace'},
          );
        } else {
          appendLog('Quick fix skipped: no action available at selection.');
          _publishDiagnosticActionTelemetry(
            action: 'applyQuickFix',
            succeeded: false,
            message: 'Quick fix skipped: no action available at selection.',
            metadata: const <String, Object?>{'scope': 'selection'},
          );
        }
        notifyListeners();
        return;
      case AppCommandId.goToDefinition:
        if (editorController.selectDefinitionAtSelection()) {
          appendLog('Definition selected in editor.');
        } else if (await goToProjectDefinitionAtSelection()) {
          appendLog('Project definition selected in editor.');
        } else {
          appendLog('Definition skipped: no resolved definition at selection.');
        }
        notifyListeners();
        return;
      case AppCommandId.nextReference:
        if (editorController.selectNextReferenceAtSelection()) {
          appendLog('Next reference selected in editor.');
        } else if (await selectProjectReferenceAtSelection(forward: true)) {
          appendLog('Project next reference selected in editor.');
        } else {
          appendLog(
            'Next reference skipped: no resolved references at selection.',
          );
        }
        notifyListeners();
        return;
      case AppCommandId.previousReference:
        if (editorController.selectPreviousReferenceAtSelection()) {
          appendLog('Previous reference selected in editor.');
        } else if (await selectProjectReferenceAtSelection(forward: false)) {
          appendLog('Project previous reference selected in editor.');
        } else {
          appendLog(
            'Previous reference skipped: no resolved references at selection.',
          );
        }
        notifyListeners();
        return;
      case AppCommandId.openWorkspaceFile:
        appendLog('Open Workspace File requires caller-provided input.');
        return;
      case AppCommandId.searchWorkspace:
        appendLog('Search Workspace requires caller-provided input.');
        return;
      case AppCommandId.previewWorkspaceReplace:
        appendLog('Preview Workspace Replace requires caller-provided input.');
        return;
      case AppCommandId.applyWorkspaceReplace:
        await _applyLastWorkspaceReplacePreviewForAgent(
          AgentIdeCommandSuggestion(commandId: commandId.name),
        );
        return;
      case AppCommandId.runBuild:
      case AppCommandId.formatActiveDocument:
      case AppCommandId.runStaticAnalysis:
      case AppCommandId.runTests:
        final result = await _runNativeToolCommand(commandId);
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: result.applied,
          message: result.message,
          metadata: result.metadata,
        );
        return;
      case AppCommandId.rerunFailedTests:
        await rerunFailedTests();
        final result = lastTestRun;
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: _agentTestingCommandApplied(result),
          message: result == null
              ? 'Rerun Failed Tests skipped: no test result is available.'
              : _testRunResultMessage('Rerun Failed Tests', result),
          metadata: _agentTestingCommandMetadata(result),
        );
        return;
      case AppCommandId.debugFailedTests:
        await debugFailedTests();
        final result = lastTestRun;
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: _agentTestingCommandApplied(result),
          message: result == null
              ? 'Debug Failed Tests skipped: no test result is available.'
              : _testRunResultMessage('Debug Failed Tests', result),
          metadata: _agentTestingCommandMetadata(result),
        );
        return;
      case AppCommandId.runTestConfiguration:
      case AppCommandId.debugTestConfiguration:
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: false,
          message:
              '${StyioCommandRegistry.descriptorFor(commandId).label} requires test configuration id input.',
          metadata: _testConfigurationCommandMetadata(),
        );
        return;
      case AppCommandId.renameSymbol:
        appendLog('Rename Symbol requires caller-provided input.');
        return;
      case AppCommandId.safeDelete:
        if (editorController.applySafeDeleteAtSelection()) {
          _cacheDocument(_activeDocumentPath, editorController.document);
          _dirtyDocumentPaths.add(_activeDocumentPath);
          appendLog('Safe delete applied at editor selection.');
        } else {
          appendLog(
            'Safe delete skipped: no safe delete available at selection.',
          );
        }
        notifyListeners();
        return;
      case AppCommandId.inlineVariable:
        if (editorController.applyInlineVariableAtSelection()) {
          _cacheDocument(_activeDocumentPath, editorController.document);
          _dirtyDocumentPaths.add(_activeDocumentPath);
          appendLog('Inline variable applied at editor selection.');
        } else {
          appendLog(
            'Inline variable skipped: no inline variable available at selection.',
          );
        }
        notifyListeners();
        return;
      case AppCommandId.showRuntime:
      case AppCommandId.showAgent:
      case AppCommandId.showDebug:
        return;
      case AppCommandId.refreshModules:
        appendLog('Module host refresh requested on ${platformTarget.label}.');
        await refreshProjectGraph(
          reason: 'manual refresh requested from the shell command registry',
        );
        final bridge = await nativeModuleLoader.describe(
          'local.runtime.desktop',
        );
        appendLog(
          'Native bridge ${bridge.moduleId}: ${bridge.state.name} '
          '(${bridge.detail})',
        );
        return;
      case AppCommandId.openSettings:
        appendLog('Settings route is reserved for M7 theme/profile system.');
        return;
      case AppCommandId.createWorkspaceFile:
      case AppCommandId.renameWorkspaceFile:
      case AppCommandId.deleteWorkspaceFile:
      case AppCommandId.revealWorkspaceFile:
        appendLog(
          '${StyioCommandRegistry.descriptorFor(commandId).label} requires a File Explorer dialog route.',
        );
        return;
      default:
        appendLog(
          '${StyioCommandRegistry.descriptorFor(commandId).label} route requested.',
        );
        notifyListeners();
        return;
    }
  }

  Future<void> executeCommandWithInput(
    AppCommandId commandId,
    String input,
  ) async {
    final normalizedInput = input.trim();
    final blockedReason = blockedReasonForCommand(commandId);
    if (blockedReason != null) {
      appendLog(
        '${StyioCommandRegistry.descriptorFor(commandId).label} blocked: $blockedReason',
      );
      return;
    }
    switch (commandId) {
      case AppCommandId.openWorkspaceFile:
      case AppCommandId.searchWorkspace:
      case AppCommandId.previewWorkspaceReplace:
      case AppCommandId.renameSymbol:
      case AppCommandId.previewSourceControlDiff:
      case AppCommandId.stageSourceControl:
      case AppCommandId.unstageSourceControl:
      case AppCommandId.planSourceControlBranchSwitch:
      case AppCommandId.planSourceControlCommitDraft:
      case AppCommandId.selectClangCppVersion:
      case AppCommandId.runTestConfiguration:
      case AppCommandId.debugTestConfiguration:
        await applyAgentIdeCommandSuggestion(
          AgentIdeCommandSuggestion(
            commandId: commandId.name,
            input: normalizedInput,
          ),
        );
        return;
      case AppCommandId.failoverAgentProvider:
        final suggestion = AgentIdeCommandSuggestion(
          commandId: commandId.name,
          input: normalizedInput,
        );
        final result = await failoverAgentProviderProfile(normalizedInput);
        final message =
            result?.message ??
            'Agent provider failover unavailable: no configurator is wired.';
        _recordAgentIdeCommandResult(
          suggestion,
          applied: result?.mounted ?? false,
          message: message,
          metadata: <String, Object?>{
            'targetProviderProfileId': result?.profile.profileId,
            'targetProviderProfileKey': normalizedInput,
            'adapterKind': result?.adapterKind.wireValue,
            'adapterId': result?.adapterId,
            'retryEnabled': result?.retryEnabled,
          },
        );
        return;
      case AppCommandId.createWorkspaceFile:
      case AppCommandId.renameWorkspaceFile:
      case AppCommandId.deleteWorkspaceFile:
      case AppCommandId.revealWorkspaceFile:
        final result = await _executeWorkspaceFileCommandWithInput(
          commandId,
          normalizedInput,
        );
        final operationResult = result.operationResult;
        _recordAgentIdeCommandResult(
          AgentIdeCommandSuggestion(commandId: commandId.name, input: input),
          applied: operationResult?.applied ?? false,
          message: result.message,
          metadata: result.toJson(),
        );
        appendLog(result.message);
        notifyListeners();
        return;
      case AppCommandId.save:
      case AppCommandId.saveAll:
      case AppCommandId.run:
      case AppCommandId.fetchDependencies:
      case AppCommandId.vendorDependencies:
      case AppCommandId.useActiveCompiler:
      case AppCommandId.pinActiveCompiler:
      case AppCommandId.clearPinnedCompiler:
      case AppCommandId.bootstrapStyioToolchain:
      case AppCommandId.executeToolchainInstallPlan:
      case AppCommandId.packProject:
      case AppCommandId.preparePublish:
      case AppCommandId.showRuntime:
      case AppCommandId.showAgent:
      case AppCommandId.showDebug:
      case AppCommandId.toggleBreakpoint:
      case AppCommandId.startDebugging:
      case AppCommandId.stopDebugging:
      case AppCommandId.continueDebugging:
      case AppCommandId.stepOver:
      case AppCommandId.selectDebugThread:
      case AppCommandId.selectDebugStackFrame:
      case AppCommandId.nextDiagnostic:
      case AppCommandId.previousDiagnostic:
      case AppCommandId.applyQuickFix:
      case AppCommandId.previewQuickFix:
      case AppCommandId.refreshLanguageService:
      case AppCommandId.refreshWorkspaceDiagnostics:
      case AppCommandId.refreshSourceControl:
      case AppCommandId.applyWorkspaceReplace:
      case AppCommandId.collectAgentCodingCheckpoint:
      case AppCommandId.collectProjectLanguageContext:
      case AppCommandId.retryAgentProvider:
      case AppCommandId.replayAgentPrompt:
      case AppCommandId.goToDefinition:
      case AppCommandId.nextReference:
      case AppCommandId.previousReference:
      case AppCommandId.safeDelete:
      case AppCommandId.inlineVariable:
      case AppCommandId.refreshModules:
      case AppCommandId.openSettings:
      case AppCommandId.runBuild:
      case AppCommandId.formatActiveDocument:
      case AppCommandId.runStaticAnalysis:
      case AppCommandId.runTests:
      case AppCommandId.rerunFailedTests:
      case AppCommandId.debugFailedTests:
        await executeCommand(commandId);
        return;
      default:
        throw UnimplementedError('AppCommandId.$commandId not implemented');
    }
  }

  Future<WorkspaceFileCommandRouteResult> _executeWorkspaceFileCommandWithInput(
    AppCommandId commandId,
    String input,
  ) async {
    final routed = const WorkspaceFileCommandRouter().route(
      commandId: commandId,
      input: input,
      context: WorkspaceFileCommandRouteContext(
        activeFilePath: workspaceController.activeFilePath,
        selectedFilePath: workspaceController.activeFilePath,
        openCreatedFiles: true,
      ),
    );
    final request = routed.request;
    if (request == null) {
      return routed;
    }
    if (routed.confirmationPlan?.destructive ?? false) {
      final staged = WorkspaceFileCommandRouteResult(
        commandId: commandId,
        status: WorkspaceFileCommandRouteStatus.routed,
        input: input,
        request: request,
        confirmationPlan: routed.confirmationPlan,
        message:
            '${routed.confirmationPlan!.title} staged for confirmation. Use the workspace file confirmation controls to apply or cancel it.',
      );
      _pendingWorkspaceFileCommandConfirmation = staged;
      return staged;
    }
    final operationResult = await _runWorkspaceFileOperationRequest(request);
    return routed.withOperationResult(operationResult);
  }

  Future<WorkspaceFileCommandRouteResult?>
  confirmPendingWorkspaceFileCommand() async {
    final pending = _pendingWorkspaceFileCommandConfirmation;
    final request = pending?.request;
    if (pending == null || request == null) {
      return null;
    }
    _pendingWorkspaceFileCommandConfirmation = null;
    final operationResult = await _runWorkspaceFileOperationRequest(request);
    final result = pending.withOperationResult(operationResult);
    _recordAgentIdeCommandResult(
      AgentIdeCommandSuggestion(
        commandId: pending.commandId.name,
        input: pending.input,
      ),
      applied: operationResult.applied,
      message: result.message,
      metadata: <String, Object?>{
        ...result.toJson(),
        'confirmationAccepted': true,
      },
    );
    appendLog(result.message);
    notifyListeners();
    return result;
  }

  WorkspaceFileCommandRouteResult? cancelPendingWorkspaceFileCommand() {
    final pending = _pendingWorkspaceFileCommandConfirmation;
    if (pending == null) {
      return null;
    }
    _pendingWorkspaceFileCommandConfirmation = null;
    final result = WorkspaceFileCommandRouteResult(
      commandId: pending.commandId,
      status: WorkspaceFileCommandRouteStatus.blocked,
      input: pending.input,
      request: pending.request,
      confirmationPlan: pending.confirmationPlan,
      message:
          '${pending.confirmationPlan?.title ?? 'Workspace file command'} cancelled.',
    );
    _recordAgentIdeCommandResult(
      AgentIdeCommandSuggestion(
        commandId: pending.commandId.name,
        input: pending.input,
      ),
      applied: false,
      message: result.message,
      metadata: <String, Object?>{
        ...result.toJson(),
        'confirmationAccepted': false,
      },
    );
    appendLog(result.message);
    notifyListeners();
    return result;
  }

  Future<WorkspaceFileOperationResult> _runWorkspaceFileOperationRequest(
    WorkspaceFileExplorerActionRequest request,
  ) async {
    if (request.kind == WorkspaceFileOperationKind.reveal) {
      final opened = await openWorkspaceFileForAgent(request.path);
      return WorkspaceFileOperationResult(
        kind: WorkspaceFileOperationKind.reveal,
        applied: opened,
        path: request.path,
        message: opened
            ? 'Workspace file revealed.'
            : 'Workspace file reveal failed.',
      );
    }
    final service = WorkspaceFileOperationService(
      workspaceController: workspaceController,
      documentStore: workspaceDocumentStore,
    );
    final operationResult = switch (request.kind) {
      WorkspaceFileOperationKind.create => await service.createFile(
        path: request.path,
        text: request.text,
        open: request.open,
      ),
      WorkspaceFileOperationKind.rename => await service.renameFile(
        path: request.path,
        nextPath: request.nextPath,
        open: request.open,
      ),
      WorkspaceFileOperationKind.delete => await service.deleteFile(
        request.path,
      ),
      WorkspaceFileOperationKind.reveal => service.revealFile(request.path),
    };
    if (operationResult.applied &&
        (workspaceController.activeFilePath == operationResult.nextPath ||
            workspaceController.activeFilePath == operationResult.path)) {
      await _loadActiveWorkspaceDocument();
    }
    return operationResult;
  }

  String? blockedReasonForCommand(AppCommandId commandId) {
    final projectGraph = workspaceController.activeProject;
    switch (commandId) {
      case AppCommandId.fetchDependencies:
        return blockedDependencySourceCommandReason(
          platformTarget: platformTarget,
          projectGraph: projectGraph,
          command: 'fetch',
        );
      case AppCommandId.vendorDependencies:
        return blockedDependencySourceCommandReason(
          platformTarget: platformTarget,
          projectGraph: projectGraph,
          command: 'vendor',
        );
      case AppCommandId.useActiveCompiler:
        return _blockedToolchainCommandReason(
          projectGraph: projectGraph,
          requiresResolvedCompiler: true,
        );
      case AppCommandId.pinActiveCompiler:
        return _blockedToolchainCommandReason(
          projectGraph: projectGraph,
          requiresResolvedCompiler: true,
          requiresManifest: true,
        );
      case AppCommandId.clearPinnedCompiler:
        return _blockedToolchainCommandReason(
          projectGraph: projectGraph,
          requiresManifest: true,
          requiresPin: true,
        );
      case AppCommandId.bootstrapStyioToolchain:
        return null;
      case AppCommandId.executeToolchainInstallPlan:
        return null;
      case AppCommandId.packProject:
        return _blockedDeploymentCommandReason(projectGraph: projectGraph);
      case AppCommandId.preparePublish:
        return _blockedDeploymentCommandReason(
          projectGraph: projectGraph,
          requireResolvedPublishTarget: true,
        );
      case AppCommandId.save:
      case AppCommandId.saveAll:
      case AppCommandId.run:
      case AppCommandId.showRuntime:
      case AppCommandId.showAgent:
      case AppCommandId.showDebug:
      case AppCommandId.toggleBreakpoint:
      case AppCommandId.startDebugging:
      case AppCommandId.stopDebugging:
      case AppCommandId.continueDebugging:
      case AppCommandId.stepOver:
      case AppCommandId.selectDebugThread:
      case AppCommandId.selectDebugStackFrame:
      case AppCommandId.nextDiagnostic:
      case AppCommandId.previousDiagnostic:
      case AppCommandId.applyQuickFix:
      case AppCommandId.previewQuickFix:
      case AppCommandId.refreshLanguageService:
      case AppCommandId.refreshWorkspaceDiagnostics:
      case AppCommandId.refreshSourceControl:
      case AppCommandId.previewSourceControlDiff:
      case AppCommandId.stageSourceControl:
      case AppCommandId.unstageSourceControl:
      case AppCommandId.planSourceControlBranchSwitch:
      case AppCommandId.planSourceControlCommitDraft:
      case AppCommandId.collectAgentCodingCheckpoint:
      case AppCommandId.collectProjectLanguageContext:
      case AppCommandId.retryAgentProvider:
      case AppCommandId.failoverAgentProvider:
      case AppCommandId.replayAgentPrompt:
      case AppCommandId.goToDefinition:
      case AppCommandId.openWorkspaceFile:
      case AppCommandId.createWorkspaceFile:
      case AppCommandId.renameWorkspaceFile:
      case AppCommandId.deleteWorkspaceFile:
      case AppCommandId.revealWorkspaceFile:
      case AppCommandId.searchWorkspace:
      case AppCommandId.previewWorkspaceReplace:
      case AppCommandId.applyWorkspaceReplace:
      case AppCommandId.runBuild:
      case AppCommandId.formatActiveDocument:
      case AppCommandId.runStaticAnalysis:
      case AppCommandId.runTests:
      case AppCommandId.rerunFailedTests:
      case AppCommandId.debugFailedTests:
      case AppCommandId.runTestConfiguration:
      case AppCommandId.debugTestConfiguration:
      case AppCommandId.nextReference:
      case AppCommandId.previousReference:
      case AppCommandId.renameSymbol:
      case AppCommandId.safeDelete:
      case AppCommandId.inlineVariable:
      case AppCommandId.refreshModules:
      case AppCommandId.selectClangCppVersion:
      case AppCommandId.openSettings:
        return null;
      default:
        return null;
    }
  }

  ExecutionSession _sessionWithRunUnit(
    ExecutionSession session,
    RunUnitSelection runUnit,
  ) {
    return ExecutionSession(
      sessionId: session.sessionId,
      kind: session.kind,
      status: session.status,
      statusMessage: session.statusMessage,
      diagnostics: session.diagnostics,
      stdoutEvents: session.stdoutEvents,
      stderrEvents: session.stderrEvents,
      unitRange: runUnit.range,
    );
  }

  Future<void> _refreshLanguageServiceAfterSave(String documentId) async {
    final refresh = refreshActiveLanguageService;
    if (refresh == null) {
      return;
    }
    try {
      await refresh();
      appendLog('Language service refresh requested after saving $documentId.');
    } on Object catch (error) {
      appendLog(
        'Language service refresh failed after saving $documentId: $error',
      );
    }
  }

  Future<bool> _refreshLanguageServiceForCommand({
    AgentIdeCommandSuggestion? suggestion,
  }) async {
    final refresh = refreshActiveLanguageService;
    if (refresh == null) {
      const message =
          'Language service refresh skipped: no refresh callback is configured.';
      appendLog(message);
      if (suggestion != null) {
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message: 'Agent command refreshLanguageService skipped.',
          metadata: <String, Object?>{'reason': 'missing-refresh-callback'},
        );
      }
      return false;
    }
    try {
      await refresh();
      final status = languageServiceStatus.value;
      final metadata = <String, Object?>{
        'languageServiceSeverity': status.severity.name,
        'languageServiceUsableCapabilityCount': status.usableCapabilityCount,
        'languageServiceFreshCapabilityCount': status.freshCapabilityCount,
        'languageServicePrimaryCapabilityStates':
            status.primaryCapabilityStates,
        if (status.parserEngine != null)
          'languageServiceParserEngine': status.parserEngine,
        if (status.grammarVersion != null)
          'languageServiceGrammarVersion': status.grammarVersion,
      };
      const message = 'Language service refresh requested.';
      appendLog(message);
      if (suggestion != null) {
        _recordAgentIdeCommandResult(
          suggestion,
          applied: true,
          message: 'Agent command refreshLanguageService completed.',
          metadata: metadata,
        );
      }
      return true;
    } on Object catch (error) {
      final message = 'Language service refresh failed: $error';
      appendLog(message);
      if (suggestion != null) {
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message: 'Agent command refreshLanguageService failed.',
          metadata: <String, Object?>{'error': error.toString()},
        );
      }
      return false;
    }
  }

  String? _blockedToolchainCommandReason({
    required ProjectGraphSnapshot projectGraph,
    bool requiresResolvedCompiler = false,
    bool requiresManifest = false,
    bool requiresPin = false,
  }) {
    if (platformTarget == PlatformTarget.ios ||
        platformTarget == PlatformTarget.web) {
      if (!projectGraph.hasHostedWorkspace) {
        return '${platformTarget.label} does not expose local pafio toolchain management.';
      }
    }
    if (requiresResolvedCompiler && projectGraph.activeCompiler == null) {
      return 'No active compiler handshake is currently resolved for this project.';
    }
    if (requiresManifest && !projectGraph.hasManifest) {
      return 'Project toolchain commands require a resolved pafio manifest path.';
    }
    if (requiresPin && projectGraph.toolchainPinPath == null) {
      return 'No project toolchain pin is currently resolved.';
    }
    return null;
  }

  String? _blockedDeploymentCommandReason({
    required ProjectGraphSnapshot projectGraph,
    bool requireResolvedPublishTarget = false,
  }) {
    if (platformTarget == PlatformTarget.ios ||
        platformTarget == PlatformTarget.web) {
      if (!projectGraph.hasHostedWorkspace) {
        return '${platformTarget.label} does not expose local pafio deployment commands.';
      }
    }
    if (!projectGraph.hasManifest) {
      return 'Deployment commands require a resolved pafio manifest path.';
    }
    if (!requireResolvedPublishTarget) {
      return null;
    }
    final distribution = projectGraph.packageDistribution;
    if (distribution == null || distribution.packages.isEmpty) {
      return null;
    }
    final publishablePackages = distribution.packages
        .where((package) => package.publishReady)
        .toList(growable: false);
    if (publishablePackages.length == 1) {
      return null;
    }
    if (publishablePackages.isEmpty) {
      final blockedPackages = distribution.packages
          .where((package) => !package.publishReady)
          .toList(growable: false);
      if (blockedPackages.isEmpty) {
        return 'No publish-ready package is available for deployment.';
      }
      final headline =
          'No publish-ready package is available: ${blockedPackages.map((package) => package.packageName).join(', ')}.';
      final details = blockedPackages
          .take(2)
          .expand((package) {
            if (package.blockingReasons.isEmpty) {
              return <String>[];
            }
            return <String>[
              '${package.packageName}: ${package.blockingReasons.join(' | ')}',
            ];
          })
          .join(' ');
      return details.isEmpty ? headline : '$headline $details';
    }
    return 'Multiple publish-ready packages are available. Select a package before publish: ${publishablePackages.map((package) => package.packageName).join(', ')}.';
  }

  void appendLog(String message) {
    final timestamp = DateTime.now().toIso8601String().substring(11, 19);
    _debugLog.insert(0, '$timestamp  $message');
    if (_debugLog.length > 48) {
      _debugLog.removeRange(48, _debugLog.length);
    }
    notifyListeners();
  }

  void _handleWorkspaceChanged() {
    if (_suppressWorkspaceChangedLoad) {
      return;
    }
    unawaited(_loadActiveWorkspaceDocument());
  }

  void _handleDocumentChanged() {
    _cacheDocument(_activeDocumentPath, editorController.document);
    _rememberSelectionForPath(_activeDocumentPath);
    final subscriptionDocuments = _styioServiceSubscriptionDocuments;
    if (subscriptionDocuments != null && !subscriptionDocuments.isClosed) {
      subscriptionDocuments.add(editorController.document);
    }
    final snapshot = _editorFileBinding.markDocumentChanged(
      editorController.document,
    );
    _syncDirtyStateForPath(_activeDocumentPath, snapshot);
  }

  void _handleStyioServiceSubscriptionEvent(
    StyioServiceSubscriptionEvent event,
  ) {
    appendLog(event.message);
    for (final runtimeEvent in event.semanticPanelEvents()) {
      unawaited(recordSemanticRuntimeOutputEvent(runtimeEvent));
    }
    notifyListeners();
  }

  void _handleLanguageServiceStatusChanged() {
    notifyListeners();
  }

  void _handleToolchainStatusReportChanged() {
    notifyListeners();
  }

  void _handleEditorFileBindingSnapshot(
    DocumentResourceBindingSnapshot snapshot,
  ) {
    switch (snapshot.state) {
      case DocumentResourceBindingState.externalChanged:
        if (snapshot.externalDocument != null) {
          acceptEditorExternalChange();
          return;
        }
        notifyListeners();
        return;
      case DocumentResourceBindingState.conflicted:
        appendLog(
          'External change conflicted for '
          '${snapshot.externalDocument?.documentId ?? _activeDocumentPath}.',
        );
        return;
      case DocumentResourceBindingState.deletedOnDisk:
      case DocumentResourceBindingState.readonly:
      case DocumentResourceBindingState.providerUnavailable:
        appendLog(
          'Editor file binding ${snapshot.state.name} for $_activeDocumentPath.',
        );
        return;
      case DocumentResourceBindingState.unbound:
      case DocumentResourceBindingState.binding:
      case DocumentResourceBindingState.boundClean:
      case DocumentResourceBindingState.boundDirty:
        notifyListeners();
        return;
    }
  }

  Future<void> refreshProjectGraph({String? reason}) async {
    final previousProject = workspaceController.activeProject;
    final refreshedProject = await _projectGraphAdapter.loadProjectGraph();
    executionAdapter = await _executionAdapterFactory(refreshedProject);
    _adapterCapabilities = normalizeCapabilitySnapshots([
      _projectGraphAdapter.capabilitySnapshot,
      executionAdapter.capabilitySnapshot,
      runtimeEventAdapter.capabilitySnapshot,
      ..._supplementalAdapterCapabilities,
    ]);
    workspaceController.replaceProject(
      refreshedProject,
      activeFilePath: workspaceController.activeFilePath,
    );
    final previousCompiler = previousProject.activeCompiler?.compilerVersion;
    final refreshedCompiler = refreshedProject.activeCompiler?.compilerVersion;
    appendLog(
      'Project graph refreshed: ${refreshedProject.title}'
      '${reason == null ? '' : ' ($reason)'}'
      '${previousCompiler == refreshedCompiler ? '' : ' · compiler ${previousCompiler ?? 'unresolved'} -> ${refreshedCompiler ?? 'unresolved'}'}.',
    );
  }

  Future<ToolchainCommandResult> installManagedCompiler({
    required String styioBinaryPath,
  }) async {
    final result = await _toolchainManagementAdapter.installManagedCompiler(
      projectGraph: workspaceController.activeProject,
      styioBinaryPath: styioBinaryPath,
    );
    return _completeToolchainCommand(
      result,
      refreshReason: 'tool install completed',
    );
  }

  Future<ToolchainCommandResult> useManagedCompiler({
    required String compilerVersion,
    String? channel,
  }) async {
    final result = await _toolchainManagementAdapter.useManagedCompiler(
      projectGraph: workspaceController.activeProject,
      compilerVersion: compilerVersion,
      channel: channel,
    );
    return _completeToolchainCommand(
      result,
      refreshReason: 'tool use completed',
    );
  }

  Future<ToolchainCommandResult> pinManagedCompiler({
    required String compilerVersion,
    String? channel,
  }) async {
    final result = await _toolchainManagementAdapter.pinManagedCompiler(
      projectGraph: workspaceController.activeProject,
      compilerVersion: compilerVersion,
      channel: channel,
    );
    return _completeToolchainCommand(
      result,
      refreshReason: 'tool pin completed',
    );
  }

  Future<ToolchainCommandResult> clearPinnedCompiler() async {
    final result = await _toolchainManagementAdapter.clearPinnedCompiler(
      projectGraph: workspaceController.activeProject,
    );
    return _completeToolchainCommand(
      result,
      refreshReason: 'tool pin clear completed',
    );
  }

  Future<void> handleToolchainRecoveryAction(
    ToolchainRecoveryAction action,
  ) async {
    appendLog('Toolchain recovery requested: ${action.id}.');
    if (action.id == 'show-toolchain-logs') {
      appendLog('Toolchain log view requested.');
      notifyListeners();
      return;
    }
    if (action.id == 'select-existing-toolchain') {
      appendLog('Toolchain selection route requested.');
      notifyListeners();
      return;
    }
    if (action.id == 'configure-managed-download') {
      appendLog('Toolchain managed download configuration route requested.');
      notifyListeners();
      return;
    }
    if (action.id == 'enable-toolchain-installation') {
      appendLog('Toolchain installation policy settings route requested.');
      notifyListeners();
      return;
    }
    if (action.id == 'retry-external-installer') {
      await executeLastToolchainInstallPlan();
      return;
    }
    if (action.id == 'install-managed-toolchain') {
      planManagedToolchainInstallation();
      return;
    }
    if (action.id == 'use-degraded-mode') {
      appendLog('Toolchain degraded mode requested.');
      notifyListeners();
      return;
    }
    if (action.id == 'fix-toolchain-precondition') {
      appendLog('Toolchain precondition recovery: ${action.description}');
      notifyListeners();
      return;
    }
    if (action.id == 'retry-tool-use') {
      final compiler = workspaceController.activeProject.activeCompiler;
      if (compiler == null) {
        appendLog('Toolchain retry blocked: no active compiler is resolved.');
        notifyListeners();
        return;
      }
      await useManagedCompiler(
        compilerVersion: compiler.compilerVersion,
        channel: compiler.channel,
      );
      return;
    }
    if (action.id == 'retry-tool-pin') {
      final compiler = workspaceController.activeProject.activeCompiler;
      if (compiler == null) {
        appendLog('Toolchain retry blocked: no active compiler is resolved.');
        notifyListeners();
        return;
      }
      await pinManagedCompiler(
        compilerVersion: compiler.compilerVersion,
        channel: compiler.channel,
      );
      return;
    }
    appendLog('Toolchain recovery action is not wired: ${action.id}.');
    notifyListeners();
  }

  Future<ToolchainCommandResult> _completeToolchainCommand(
    ToolchainCommandResult result, {
    required String refreshReason,
  }) async {
    _lastToolchainCommand = result;
    appendLog(
      '${result.command} ${result.status.name}: ${result.statusMessage}',
    );
    if (result.succeeded) {
      await refreshProjectGraph(reason: refreshReason);
    } else {
      notifyListeners();
    }
    return result;
  }

  Future<DeploymentCommandResult> packProject({
    String? packageName,
    String? outputPath,
  }) async {
    final result = await _deploymentAdapter.packProject(
      projectGraph: workspaceController.activeProject,
      packageName: packageName,
      outputPath: outputPath,
    );
    return _completeDeploymentCommand(result);
  }

  Future<DeploymentCommandResult> preparePublish({
    String? packageName,
    String? outputPath,
  }) async {
    final result = await _deploymentAdapter.preparePublish(
      projectGraph: workspaceController.activeProject,
      packageName: packageName,
      outputPath: outputPath,
    );
    return _completeDeploymentCommand(result);
  }

  Future<DeploymentCommandResult> publishToRegistry({
    required String registryRoot,
    String? packageName,
    String? outputPath,
  }) async {
    final result = await _deploymentAdapter.publishToRegistry(
      projectGraph: workspaceController.activeProject,
      registryRoot: registryRoot,
      packageName: packageName,
      outputPath: outputPath,
    );
    return _completeDeploymentCommand(result);
  }

  Future<DeploymentCommandResult> _completeDeploymentCommand(
    DeploymentCommandResult result,
  ) async {
    _lastDeploymentCommand = result;
    appendLog(
      '${result.command} ${result.status.name}: ${result.statusMessage}',
    );
    if (result.payload case final payload?) {
      final packageName = payload['package'] as String?;
      final archivePath = payload['archive_path'] as String?;
      if (packageName != null && packageName.isNotEmpty) {
        appendLog('deploy package: $packageName');
      }
      if (archivePath != null && archivePath.isNotEmpty) {
        appendLog('deploy archive: $archivePath');
      }
    }
    notifyListeners();
    return result;
  }

  Future<DependencySourceCommandResult> fetchDependencies({
    bool locked = false,
    bool offline = false,
  }) async {
    final result = await _dependencySourceAdapter.fetchDependencies(
      projectGraph: workspaceController.activeProject,
      locked: locked,
      offline: offline,
    );
    return _completeDependencySourceCommand(
      result,
      refreshReason: 'fetch completed',
    );
  }

  Future<DependencySourceCommandResult> vendorDependencies({
    String? outputPath,
    bool locked = false,
    bool offline = false,
  }) async {
    final result = await _dependencySourceAdapter.vendorDependencies(
      projectGraph: workspaceController.activeProject,
      outputPath: outputPath,
      locked: locked,
      offline: offline,
    );
    return _completeDependencySourceCommand(
      result,
      refreshReason: 'vendor completed',
    );
  }

  Future<DependencySourceCommandResult> _completeDependencySourceCommand(
    DependencySourceCommandResult result, {
    required String refreshReason,
  }) async {
    _lastDependencySourceCommand = result;
    appendLog(
      '${result.command} ${result.status.name}: ${result.statusMessage}',
    );
    if (result.payload case final payload?) {
      final packages = payload['packages'];
      final vendorRoot = payload['vendor_root'] as String?;
      final metadataPath = payload['metadata_path'] as String?;
      if (packages is num) {
        appendLog('${result.command} packages: ${packages.toInt()}');
      }
      if (vendorRoot != null && vendorRoot.isNotEmpty) {
        appendLog('vendor root: $vendorRoot');
      }
      if (metadataPath != null && metadataPath.isNotEmpty) {
        appendLog('vendor metadata: $metadataPath');
      }
    }
    if (result.succeeded) {
      await refreshProjectGraph(reason: refreshReason);
    } else {
      notifyListeners();
    }
    return result;
  }

  Future<void> _loadActiveWorkspaceDocument() async {
    final loadGeneration = ++_workspaceDocumentLoadGeneration;
    final currentDocument = editorController.document;
    if (currentDocument.documentId == _activeDocumentPath) {
      _cacheDocument(_activeDocumentPath, currentDocument);
      _rememberSelectionForPath(_activeDocumentPath);
      final currentSnapshot = _editorFileBinding.markDocumentChanged(
        currentDocument,
      );
      _syncDirtyStateForPath(_activeDocumentPath, currentSnapshot);
    }
    final nextPath = workspaceController.activeFilePath;
    _activeDocumentPath = nextPath;
    final cachedDocument = _documentCache[nextPath];
    final openResult = cachedDocument == null
        ? await _editorFileBinding.open(nextPath)
        : null;
    final nextDocument =
        cachedDocument ??
        openResult?.snapshot.document ??
        EditorSessionController.seedDocumentForPath(nextPath);
    if (loadGeneration != _workspaceDocumentLoadGeneration ||
        _activeDocumentPath != nextPath ||
        workspaceController.activeFilePath != nextPath) {
      return;
    }
    if (cachedDocument != null) {
      _editorFileBinding.bindLoadedDocument(cachedDocument);
    }
    _suppressSelectionTracking = true;
    try {
      editorController.loadDocument(nextDocument);
    } finally {
      _suppressSelectionTracking = false;
    }
    _restoreSelectionForDocument(nextPath);
    appendLog(
      'Project route -> ${workspaceController.activeProject.title} / '
      '${workspaceController.activeFilePath}',
    );
  }

  Future<void> persistEditorSession({String key = 'default'}) async {
    final store = editorSessionDataStore;
    if (store == null) {
      appendLog(
        'Editor session persistence unavailable: no DataStore is wired.',
      );
      return;
    }
    final openDocumentIds = <String>{
      ..._documentCache.keys,
      _activeDocumentPath,
      editorController.document.documentId,
    }.toList(growable: false);
    await store.saveSession(
      workspaceId: editorSessionWorkspaceId,
      key: key,
      snapshot: editorController.toSessionSnapshot(
        openDocumentIds: openDocumentIds,
        dirtyDocumentIds: _dirtyDocumentPaths.toList(growable: false),
        cursorOffsets: _documentCursorOffsets,
        selectionAnchors: _documentSelectionAnchors,
      ),
    );
    appendLog(
      'Editor session persisted for $editorSessionWorkspaceId with '
      '${openDocumentIds.length} open document(s).',
    );
  }

  Future<EditorSessionSnapshot?> restoreEditorSession({
    String key = 'default',
  }) async {
    final store = editorSessionDataStore;
    if (store == null) {
      appendLog('Editor session restore unavailable: no DataStore is wired.');
      return null;
    }
    final snapshot = await store.readSession(
      workspaceId: editorSessionWorkspaceId,
      key: key,
    );
    if (snapshot == null) {
      appendLog(
        'No editor session snapshot found for $editorSessionWorkspaceId.',
      );
      return null;
    }

    final restoredDirtyDocumentIds = snapshot.dirtyDocumentIds
        .where(workspaceController.files.contains)
        .toList(growable: false);
    void restoreDirtyDocumentState() {
      _dirtyDocumentPaths
        ..clear()
        ..addAll(restoredDirtyDocumentIds);
      if (restoredDirtyDocumentIds.isNotEmpty) {
        appendLog(
          'Editor session restored dirty state for '
          '${restoredDirtyDocumentIds.length} document(s).',
        );
      }
    }

    final restoredOpenDocumentIds = snapshot.openDocumentIds
        .where(workspaceController.files.contains)
        .toList(growable: false);
    if (restoredOpenDocumentIds.isNotEmpty) {
      _suppressWorkspaceChangedLoad = true;
      try {
        workspaceController.restoreOpenFiles(
          restoredOpenDocumentIds,
          activeFilePath: snapshot.activeDocumentId,
        );
      } finally {
        _suppressWorkspaceChangedLoad = false;
      }
    }
    _documentCursorOffsets
      ..clear()
      ..addAll(snapshot.cursorOffsets);
    _documentSelectionAnchors
      ..clear()
      ..addAll(snapshot.selectionAnchors);

    var documentId = editorController.document.documentId;
    final activeDocumentId = snapshot.activeDocumentId;
    if (activeDocumentId != null && activeDocumentId != documentId) {
      if (!workspaceController.files.contains(activeDocumentId)) {
        appendLog(
          'Editor session snapshot loaded for $activeDocumentId, '
          'but the document is not available in the workspace.',
        );
        restoreDirtyDocumentState();
        return snapshot;
      }
      _suppressWorkspaceChangedLoad = true;
      try {
        workspaceController.openFile(activeDocumentId);
      } finally {
        _suppressWorkspaceChangedLoad = false;
      }
      final previousSelectionTracking = _suppressSelectionTracking;
      _suppressSelectionTracking = true;
      try {
        await _loadActiveWorkspaceDocument();
      } finally {
        _suppressSelectionTracking = previousSelectionTracking;
      }
      documentId = editorController.document.documentId;
    }

    if (activeDocumentId != null && activeDocumentId != documentId) {
      appendLog(
        'Editor session snapshot loaded for $activeDocumentId, '
        'current document is $documentId.',
      );
      restoreDirtyDocumentState();
      return snapshot;
    }

    restoreDirtyDocumentState();
    _restoreSelectionForDocument(documentId);
    appendLog('Editor session restored for $documentId.');
    return snapshot;
  }

  @override
  void dispose() {
    _disposed = true;
    agentCodingController.removeListener(_handleAgentCodingSessionChanged);
    workspaceController.removeListener(_handleWorkspaceChanged);
    editorController.removeListener(_handleDocumentChanged);
    languageServiceStatus.removeListener(_handleLanguageServiceStatusChanged);
    toolchainStatusReport?.removeListener(_handleToolchainStatusReportChanged);
    unawaited(_styioServiceSubscriptionEventSubscription?.cancel());
    _styioServiceSubscriptionEventSubscription = null;
    unawaited(_styioServiceSubscriptionDocuments?.close());
    _styioServiceSubscriptionDocuments = null;
    final sessionHandle = _dapDebugSession;
    _dapDebugSession = null;
    unawaited(_dapDebugSessionSubscription?.cancel());
    _dapDebugSessionSubscription = null;
    if (sessionHandle != null) {
      unawaited(sessionHandle.close());
    }
    unawaited(_editorFileBindingSubscription?.cancel());
    _editorFileBindingSubscription = null;
    if (_ownsAgentCodingController) {
      agentCodingController.dispose();
    }
    unawaited(_commandPalettePreferenceSubscription.cancel());
    if (_ownsCommandPalettePreferenceController) {
      unawaited(commandPalettePreferenceController.dispose());
    }
    if (_ownsRuntimeOutputBuffer) {
      unawaited(runtimeOutputBuffer.dispose());
    }
    if (_ownsLanguageServiceStatus &&
        languageServiceStatus is ValueNotifier<LanguageServiceStatusSurface>) {
      (languageServiceStatus as ValueNotifier<LanguageServiceStatusSurface>)
          .dispose();
    }
    unawaited(_editorFileBinding.dispose());
    super.dispose();
  }
}
