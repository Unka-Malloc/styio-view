import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend_toolchain/backend_toolchain.dart';
import '../agent/agent.dart';
import '../commands/commands.dart';
import '../debugger/debug_adapter_launcher.dart';
import '../debugger/debug_adapter_protocol.dart';
import '../debugger/debug_adapter_session.dart';
import '../debugger/debug_launch_contract.dart';
import '../editor/editor.dart';
import '../environment/configuration/configuration.dart';
import '../interaction/interaction.dart';
import '../language/language_contract.dart';
import '../module_host/module_host.dart';
import '../platform/platform.dart';
import '../toolchain/clang_cpp_version_configuration.dart';
import '../toolchain/clang_cpp_version_manager.dart';
import '../toolchain/toolchain_catalog.dart';
import '../toolchain/toolchain_install_executor.dart'
    hide ToolchainRecoveryAction;
import '../toolchain/toolchain_install_policy.dart';
import '../toolchain/toolchain_manager.dart';
import '../toolchain/toolchain_resolver.dart';
import '../toolchain/toolchain_runtime.dart';
import '../workspace/workspace.dart';
import '../../view_render/theme/vityo_theme.dart';

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
    ClangCppVersionPreference? clangCppVersionPreference,
    AgentCodingSessionController? agentCodingController,
    this.agentProviderConfigurator,
    this.refreshActiveLanguageService,
    ValueListenable<LanguageServiceStatusSurface>? languageServiceStatus,
    this.toolchainStatusReport,
    EditorDocumentResourceBinding? editorFileBinding,
    this.debugAdapterLauncher,
  }) : _activeDocumentPath = workspaceController.activeFilePath,
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
       _adapterCapabilities = normalizeCapabilitySnapshots([
         projectGraphAdapter.capabilitySnapshot,
         executionAdapter.capabilitySnapshot,
         runtimeEventAdapter.capabilitySnapshot,
         ...supplementalAdapterCapabilities,
       ]),
       _clangCppVersionPreference = clangCppVersionPreference {
    this.agentCodingController =
        agentCodingController ??
        AgentCodingSessionController(
          profile: AgentPromptProfile.defaultForPlatform(platformTarget),
          adapter: const LocalOnlyAgentProviderAdapter(),
          contextProvider: () => agentSessionContext,
        );
    this.agentCodingController.contextProvider = () => agentSessionContext;
    this.agentCodingController.addListener(_handleAgentCodingSessionChanged);
    workspaceController.addListener(_handleWorkspaceChanged);
    editorController.addListener(_handleDocumentChanged);
    this.languageServiceStatus.addListener(_handleLanguageServiceStatusChanged);
    toolchainStatusReport?.addListener(_handleToolchainStatusReportChanged);
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
  ClangCppVersionPreference? _clangCppVersionPreference;
  late final AgentCodingSessionController agentCodingController;
  final AgentProviderConfigurator? agentProviderConfigurator;
  final Future<void> Function()? refreshActiveLanguageService;
  final EditorDocumentResourceBinding _editorFileBinding;
  final RuntimeEventAdapter runtimeEventAdapter;
  final ValueListenable<LanguageServiceStatusSurface> languageServiceStatus;
  final ValueListenable<ToolchainManagerStatusReport>? toolchainStatusReport;
  final DapDebugAdapterLauncher? debugAdapterLauncher;
  final bool _ownsLanguageServiceStatus;
  final bool _ownsAgentCodingController;
  StreamSubscription<DocumentResourceBindingSnapshot>?
  _editorFileBindingSubscription;

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
  int _workspaceDocumentLoadGeneration = 0;
  ExecutionSession? _lastExecutionSession;
  List<RuntimeEventEnvelope> _lastRuntimeEvents =
      const <RuntimeEventEnvelope>[];
  VityoThemeOverride _themeOverride = const VityoThemeOverride();
  DependencySourceCommandResult? _lastDependencySourceCommand;
  DeploymentCommandResult? _lastDeploymentCommand;
  ToolchainCommandResult? _lastToolchainCommand;
  ToolchainInstallPlan? _lastToolchainInstallPlan;
  ToolchainInstallExecutionResult? _lastToolchainInstallExecutionResult;
  DebugSessionSnapshot _debugSession = const DebugSessionSnapshot(
    status: DebugSessionStatus.idle,
    message: 'No debug session has been started.',
  );
  ExecutionAdapter executionAdapter;
  List<AdapterCapabilitySnapshot> _adapterCapabilities;
  WorkspaceFileCloseRequestResult? _lastCloseRequestResult;
  AgentWorkspaceSearchResultContext? _lastAgentWorkspaceSearch;
  AgentCommandResultContext? _lastAgentIdeCommandResult;
  final List<AgentCommandResultContext> _agentIdeCommandResults =
      <AgentCommandResultContext>[];
  DapDebugSessionHandle? _dapDebugSession;
  StreamSubscription<DapSessionSnapshot>? _dapDebugSessionSubscription;
  bool _dapInspectionRequestInFlight = false;

  List<AdapterCapabilitySnapshot> get adapterCapabilities =>
      _adapterCapabilities;
  List<String> get debugLog => List<String>.unmodifiable(_debugLog);
  List<NativeToolResultRecord> get nativeToolResults =>
      List<NativeToolResultRecord>.unmodifiable(_nativeToolResults);
  AgentCommandResultContext? get lastAgentIdeCommandResult =>
      _lastAgentIdeCommandResult;
  NativeToolResultRecord? get lastNativeToolResult =>
      _nativeToolResults.isEmpty ? null : _nativeToolResults.first;
  DebugSessionSnapshot get debugSession => _debugSession;
  List<DebugBreakpoint> get debugBreakpoints =>
      List<DebugBreakpoint>.unmodifiable(_debugBreakpoints);
  List<String> get cachedDocumentPaths =>
      List<String>.unmodifiable(_documentCache.keys);
  List<String> get dirtyDocumentPaths =>
      List<String>.unmodifiable(_dirtyDocumentPaths);
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

  AgentSessionContext get agentSessionContext {
    final debugBreakpoints = _debugBreakpoints;
    return AgentSessionContext.fromEditorState(
      document: editorController.document,
      selection: editorController.selection,
      diagnostics: editorController.analysis.diagnostics,
      focusedDiagnostics: editorController.diagnosticsAtSelection,
      focusToken: editorController.tokenAtSelection,
      focusSemanticKind: editorController.semanticKindAtSelection,
      hover: editorController.hoverAtSelection,
      definition: editorController.definitionAtSelection,
      resolvedElement: editorController.resolvedElementAtSelection,
      resolvedReference: editorController.resolvedReferenceAtSelection,
      parameterInfo: editorController.parameterInfoAtSelection,
      safeDeletePlan: editorController.safeDeletePlanAtSelection,
      inlineVariablePlan: editorController.inlineVariablePlanAtSelection,
      surroundTemplates: editorController.surroundTemplatesAtSelection,
      references: editorController.referencesAtSelection,
      completions: editorController.completionsAtSelection,
      codeActions: editorController.contextActionsAtSelection,
      semanticSpans: editorController.analysis.semanticSpans,
      documentSymbols: editorController.analysis.documentSymbols,
      inlayHints: editorController.analysis.inlayHints,
      semanticBlocks: editorController.analysis.semanticBlocks,
      languageServiceStatus: languageServiceStatus.value,
      lastCommandResult: _lastAgentIdeCommandResult,
      recentCommandResults: _agentIdeCommandResults,
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
      activeFilePath: workspaceController.activeFilePath,
      toolchainSnapshot: toolchainStatusReport?.value.snapshot,
      clangCppVersionPreference: _clangCppVersionPreference,
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
  WorkspaceFileCloseRequestResult? get lastCloseRequestResult =>
      _lastCloseRequestResult;
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

  bool renameSymbolAtSelection(String newName) {
    if (editorController.applyRename(newName)) {
      _cacheDocument(_activeDocumentPath, editorController.document);
      _dirtyDocumentPaths.add(_activeDocumentPath);
      appendLog('Rename symbol applied at editor selection.');
      notifyListeners();
      return true;
    }
    appendLog('Rename symbol skipped: no safe rename available at selection.');
    notifyListeners();
    return false;
  }

  Future<bool> applyAgentIdeCommandSuggestion(
    AgentIdeCommandSuggestion suggestion,
  ) async {
    switch (suggestion.commandId) {
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
      case 'searchWorkspace':
        final input = suggestion.input?.trim();
        if (input == null || input.isEmpty) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message: 'Agent command searchWorkspace skipped: missing input.',
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
      case 'renameSymbol':
        final input = suggestion.input?.trim();
        if (input == null || input.isEmpty) {
          _recordAgentIdeCommandResult(
            suggestion,
            applied: false,
            message: 'Agent command renameSymbol skipped: missing input.',
          );
          appendLog(_lastAgentIdeCommandResult!.message);
          return false;
        }
        final applied = renameSymbolAtSelection(input);
        _recordAgentIdeCommandResult(
          suggestion,
          applied: applied,
          message: applied
              ? 'Agent command renameSymbol applied.'
              : 'Agent command renameSymbol skipped.',
        );
        return applied;
      case 'applyQuickFix':
        if (editorController.applyFirstQuickFixAtSelection()) {
          _cacheDocument(_activeDocumentPath, editorController.document);
          _dirtyDocumentPaths.add(_activeDocumentPath);
          appendLog('Agent command applyQuickFix applied at editor selection.');
          _recordAgentIdeCommandResult(
            suggestion,
            applied: true,
            message: 'Agent command applyQuickFix applied at editor selection.',
          );
          notifyListeners();
          return true;
        }
        appendLog(
          'Agent command applyQuickFix skipped: no quick fix available.',
        );
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message:
              'Agent command applyQuickFix skipped: no quick fix available.',
        );
        notifyListeners();
        return false;
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
      default:
        _recordAgentIdeCommandResult(
          suggestion,
          applied: false,
          message:
              'Agent command ${suggestion.commandId} skipped: unsupported command.',
        );
        appendLog(_lastAgentIdeCommandResult!.message);
        return false;
    }
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
      effectiveMetadata['completedRequiredCommandFor'] =
          prerequisiteForCommandId;
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
    return previousResult.metadata['requiredCommand'] == commandId
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
      case AppCommandId.refreshLanguageService:
      case AppCommandId.openWorkspaceFile:
      case AppCommandId.searchWorkspace:
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
    }
  }

  Map<String, Object?> _nativeToolBackendRouteMetadata(
    AppCommandId commandId,
  ) {
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
      case AppCommandId.fetchDependencies:
      case AppCommandId.vendorDependencies:
      case AppCommandId.useActiveCompiler:
      case AppCommandId.pinActiveCompiler:
      case AppCommandId.clearPinnedCompiler:
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
      case AppCommandId.refreshLanguageService:
      case AppCommandId.openWorkspaceFile:
      case AppCommandId.searchWorkspace:
      case AppCommandId.goToDefinition:
      case AppCommandId.nextReference:
      case AppCommandId.previousReference:
      case AppCommandId.renameSymbol:
      case AppCommandId.safeDelete:
      case AppCommandId.inlineVariable:
      case AppCommandId.refreshModules:
      case AppCommandId.openSettings:
        return const <String, Object?>{};
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
        final sessionHandle = await launcher.launch(launchConfiguration);
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
    appendLog(
      'Agent command searchWorkspace found '
      '${_lastAgentWorkspaceSearch!.matchCount} match(es) for "$normalizedQuery".',
    );
    notifyListeners();
    return true;
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
    );
    appendLog(result.message);
    return result;
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

    final result = await manager.selectToolchain(versionId);
    if (result.succeeded) {
      final preference = ClangCppVersionPreference(
        versionId: versionId,
        cppStandard:
            CppLanguageStandard.fromWireValue(cppStandard) ??
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
      case AppCommandId.applyQuickFix:
        if (editorController.applyFirstQuickFixAtSelection()) {
          _cacheDocument(_activeDocumentPath, editorController.document);
          _dirtyDocumentPaths.add(_activeDocumentPath);
          appendLog('Quick fix applied at editor selection.');
        } else {
          appendLog('Quick fix skipped: no action available at selection.');
        }
        notifyListeners();
        return;
      case AppCommandId.goToDefinition:
        if (editorController.selectDefinitionAtSelection()) {
          appendLog('Definition selected in editor.');
        } else {
          appendLog('Definition skipped: no resolved definition at selection.');
        }
        notifyListeners();
        return;
      case AppCommandId.nextReference:
        if (editorController.selectNextReferenceAtSelection()) {
          appendLog('Next reference selected in editor.');
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
    }
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
      case AppCommandId.refreshLanguageService:
      case AppCommandId.goToDefinition:
      case AppCommandId.openWorkspaceFile:
      case AppCommandId.searchWorkspace:
      case AppCommandId.runBuild:
      case AppCommandId.formatActiveDocument:
      case AppCommandId.runStaticAnalysis:
      case AppCommandId.runTests:
      case AppCommandId.nextReference:
      case AppCommandId.previousReference:
      case AppCommandId.renameSymbol:
      case AppCommandId.safeDelete:
      case AppCommandId.inlineVariable:
      case AppCommandId.refreshModules:
      case AppCommandId.openSettings:
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
        return '${platformTarget.label} does not expose local spio toolchain management.';
      }
    }
    if (requiresResolvedCompiler && projectGraph.activeCompiler == null) {
      return 'No active compiler handshake is currently resolved for this project.';
    }
    if (requiresManifest && !projectGraph.hasManifest) {
      return 'Project toolchain commands require a resolved spio manifest path.';
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
        return '${platformTarget.label} does not expose local spio deployment commands.';
      }
    }
    if (!projectGraph.hasManifest) {
      return 'Deployment commands require a resolved spio manifest path.';
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
    final snapshot = _editorFileBinding.markDocumentChanged(
      editorController.document,
    );
    _syncDirtyStateForPath(_activeDocumentPath, snapshot);
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
    agentCodingController.removeListener(_handleAgentCodingSessionChanged);
    workspaceController.removeListener(_handleWorkspaceChanged);
    editorController.removeListener(_handleDocumentChanged);
    languageServiceStatus.removeListener(_handleLanguageServiceStatusChanged);
    toolchainStatusReport?.removeListener(_handleToolchainStatusReportChanged);
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
    if (_ownsLanguageServiceStatus &&
        languageServiceStatus is ValueNotifier<LanguageServiceStatusSurface>) {
      (languageServiceStatus as ValueNotifier<LanguageServiceStatusSurface>)
          .dispose();
    }
    unawaited(_editorFileBinding.dispose());
    super.dispose();
  }
}
