import 'dart:async';

import 'package:flutter/foundation.dart';

import '../backend_toolchain/backend_toolchain.dart';
import '../commands/commands.dart';
import '../editor/editor.dart';
import '../interaction/interaction.dart';
import '../module_host/module_host.dart';
import '../platform/platform.dart';
import '../toolchain/toolchain_catalog.dart';
import '../toolchain/toolchain_install_executor.dart'
    hide ToolchainRecoveryAction;
import '../toolchain/toolchain_install_policy.dart';
import '../toolchain/toolchain_manager.dart';
import '../toolchain/toolchain_resolver.dart';
import '../workspace/workspace.dart';

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
    ValueListenable<LanguageServiceStatusSurface>? languageServiceStatus,
    this.toolchainStatusReport,
    EditorDocumentResourceBinding? editorFileBinding,
  }) : _activeDocumentPath = workspaceController.activeFilePath,
       languageServiceStatus =
           languageServiceStatus ??
           ValueNotifier<LanguageServiceStatusSurface>(
             LanguageServiceStatusSurface.unavailable(),
           ),
       _ownsLanguageServiceStatus = languageServiceStatus == null,
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
       ]) {
    workspaceController.addListener(_handleWorkspaceChanged);
    editorController.addListener(_handleDocumentChanged);
    this.languageServiceStatus.addListener(_handleLanguageServiceStatusChanged);
    toolchainStatusReport?.addListener(_handleToolchainStatusReportChanged);
    _editorFileBindingSubscription = _editorFileBinding.snapshotEvents.listen(
      _handleEditorFileBindingSnapshot,
    );
    _documentCache[_activeDocumentPath] = editorController.document;
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
  final EditorDocumentResourceBinding _editorFileBinding;
  final RuntimeEventAdapter runtimeEventAdapter;
  final ValueListenable<LanguageServiceStatusSurface> languageServiceStatus;
  final ValueListenable<ToolchainManagerStatusReport>? toolchainStatusReport;
  final bool _ownsLanguageServiceStatus;
  StreamSubscription<DocumentResourceBindingSnapshot>?
  _editorFileBindingSubscription;

  final List<String> _debugLog = <String>[];
  final Map<String, DocumentState> _documentCache = <String, DocumentState>{};
  String _activeDocumentPath;
  bool _suppressWorkspaceChangedLoad = false;
  final List<AppCommandId> _recentCommandIds = <AppCommandId>[];
  ExecutionSession? _lastExecutionSession;
  List<RuntimeEventEnvelope> _lastRuntimeEvents =
      const <RuntimeEventEnvelope>[];
  CommandPaletteResult? _lastCommandPalette;
  WorkspaceQuickOpenResult? _lastWorkspaceQuickOpen;
  WorkspaceDefinitionResult? _lastWorkspaceDefinition;
  WorkspaceSymbolSearchResult? _lastWorkspaceSymbolSearch;
  WorkspaceReferenceSearchResult? _lastWorkspaceReferenceSearch;
  WorkspaceCallHierarchyResult? _lastWorkspaceCallHierarchy;
  WorkspaceProblemsResult? _lastWorkspaceProblems;
  WorkspaceTextSearchResult? _lastWorkspaceSearch;
  DependencySourceCommandResult? _lastDependencySourceCommand;
  DeploymentCommandResult? _lastDeploymentCommand;
  ToolchainCommandResult? _lastToolchainCommand;
  ToolchainInstallPlan? _lastToolchainInstallPlan;
  ToolchainInstallExecutionResult? _lastToolchainInstallExecutionResult;
  ExecutionAdapter executionAdapter;
  List<AdapterCapabilitySnapshot> _adapterCapabilities;

  List<AdapterCapabilitySnapshot> get adapterCapabilities =>
      _adapterCapabilities;
  List<String> get debugLog => List<String>.unmodifiable(_debugLog);
  List<AppCommandId> get recentCommandIds =>
      List<AppCommandId>.unmodifiable(_recentCommandIds);
  ExecutionSession? get lastExecutionSession => _lastExecutionSession;
  List<RuntimeEventEnvelope> get lastRuntimeEvents =>
      List<RuntimeEventEnvelope>.unmodifiable(_lastRuntimeEvents);
  CommandPaletteResult? get lastCommandPalette => _lastCommandPalette;
  WorkspaceQuickOpenResult? get lastWorkspaceQuickOpen =>
      _lastWorkspaceQuickOpen;
  WorkspaceDefinitionResult? get lastWorkspaceDefinition =>
      _lastWorkspaceDefinition;
  WorkspaceSymbolSearchResult? get lastWorkspaceSymbolSearch =>
      _lastWorkspaceSymbolSearch;
  WorkspaceReferenceSearchResult? get lastWorkspaceReferenceSearch =>
      _lastWorkspaceReferenceSearch;
  WorkspaceCallHierarchyResult? get lastWorkspaceCallHierarchy =>
      _lastWorkspaceCallHierarchy;
  WorkspaceProblemsResult? get lastWorkspaceProblems =>
      _lastWorkspaceProblems;
  WorkspaceTextSearchResult? get lastWorkspaceSearch => _lastWorkspaceSearch;
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
  ToolchainInstallPlanSurface? get toolchainInstallPlanSurface {
    final plan = _lastToolchainInstallPlan;
    if (plan == null) {
      return null;
    }
    return ToolchainInstallPlanSurface.fromPlan(plan);
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
      );
    }
    return ToolchainSettingsSurface.fromStatus(toolchainStatusSurface);
  }

  String get workspaceDefinitionQuerySeed {
    final selection = editorController.selection;
    if (!selection.isCollapsed) {
      final selectedText = editorController.document.text.substring(
        selection.start,
        selection.end,
      );
      final selectedSeed = _normalizeDefinitionQuerySeed(selectedText);
      if (selectedSeed.isNotEmpty) {
        return selectedSeed;
      }
    }
    final definition = editorController.definitionAtSelection;
    if (definition != null) {
      return definition.symbol.name;
    }
    final token = editorController.tokenAtSelection;
    if (token == null) {
      return '';
    }
    return _normalizeDefinitionQuerySeed(token.lexeme);
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
    _documentCache[_activeDocumentPath] = document;
    editorController.loadDocument(document);
    appendLog(
      'External change accepted for ${document.documentId} '
      '(rev ${document.revision}).',
    );
    return _editorFileBinding.snapshot;
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
        _documentCache[_activeDocumentPath] = editorController.document;
        _editorFileBinding.markDocumentChanged(editorController.document);
        final saveResult = await _editorFileBinding.save(
          editorController.document,
        );
        if (!saveResult.saved) {
          appendLog(
            'Save blocked for ${workspaceController.activeFilePath}: '
            '${saveResult.message ?? saveResult.failureKind?.name ?? 'unknown failure'}.',
          );
          return;
        }
        appendLog(
          'Save requested for ${workspaceController.activeFilePath} '
          '(rev ${editorController.document.revision}).',
        );
        return;
      case AppCommandId.run:
        final session = await executionAdapter.runActiveDocument(
          platformTarget: platformTarget,
          projectGraph: workspaceController.activeProject,
          document: editorController.document,
          activeFilePath: workspaceController.activeFilePath,
        );
        _lastExecutionSession = session;
        _lastRuntimeEvents = await runtimeEventAdapter
            .sessionEvents(session.sessionId)
            .toList();
        appendLog('Run ${session.status.name}: ${session.statusMessage}');
        for (final event in session.stdoutEvents.take(3)) {
          appendLog('stdout: ${event.message}');
        }
        for (final event in session.stderrEvents.take(3)) {
          appendLog('stderr: ${event.message}');
        }
        if (session.diagnostics.isNotEmpty) {
          appendLog(
            'diagnostics: ${session.diagnostics.length} issue(s) returned by the execution route.',
          );
        }
        if (_lastRuntimeEvents.isNotEmpty) {
          appendLog(
            'runtime events: ${_lastRuntimeEvents.length} event(s) for session ${session.sessionId}.',
          );
          for (final event in _lastRuntimeEvents.take(4)) {
            appendLog('runtime: ${event.eventKind}');
          }
        }
        notifyListeners();
        return;
      case AppCommandId.commandPalette:
        appendLog('Command Palette route requested.');
        return;
      case AppCommandId.quickOpen:
        appendLog('Quick Open route requested.');
        return;
      case AppCommandId.goToWorkspaceDefinition:
        appendLog('Go to Definition route requested.');
        return;
      case AppCommandId.searchWorkspaceSymbols:
        appendLog('Workspace Symbols route requested.');
        return;
      case AppCommandId.findWorkspaceReferences:
        appendLog('Find Usages route requested.');
        return;
      case AppCommandId.showWorkspaceCallHierarchy:
        appendLog('Call Hierarchy route requested.');
        return;
      case AppCommandId.searchWorkspace:
        appendLog('Find in Files route requested.');
        return;
      case AppCommandId.showWorkspaceProblems:
        appendLog('Problems route requested.');
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
      case AppCommandId.run:
      case AppCommandId.commandPalette:
      case AppCommandId.quickOpen:
      case AppCommandId.goToWorkspaceDefinition:
      case AppCommandId.searchWorkspaceSymbols:
      case AppCommandId.findWorkspaceReferences:
      case AppCommandId.showWorkspaceCallHierarchy:
      case AppCommandId.searchWorkspace:
      case AppCommandId.showWorkspaceProblems:
      case AppCommandId.showRuntime:
      case AppCommandId.showAgent:
      case AppCommandId.showDebug:
      case AppCommandId.refreshModules:
      case AppCommandId.openSettings:
        return null;
    }
  }

  Future<WorkspaceTextSearchResult> searchWorkspaceText(
    WorkspaceTextSearchQuery query,
  ) async {
    final service = WorkspaceTextSearchService(
      documentStore: workspaceDocumentStore,
    );
    final overlayDocuments = <String, DocumentState>{
      ..._documentCache,
      _activeDocumentPath: editorController.document,
    };
    final result = await service.searchFiles(
      filePaths: workspaceController.files,
      query: query,
      overlayDocuments: overlayDocuments,
    );
    _lastWorkspaceSearch = result;
    appendLog(
      result.status == WorkspaceTextSearchStatus.invalidPattern
          ? 'Workspace search rejected invalid pattern.'
          : 'Workspace search "${query.pattern}" found '
                '${result.matchCount} match(es) in '
                '${result.matchedFileCount} file(s).',
    );
    return result;
  }

  Future<WorkspaceSymbolSearchResult> searchWorkspaceSymbols(
    WorkspaceSymbolSearchQuery query,
  ) async {
    final service = WorkspaceSymbolSearchService(
      documentStore: workspaceDocumentStore,
    );
    final overlayDocuments = <String, DocumentState>{
      ..._documentCache,
      _activeDocumentPath: editorController.document,
    };
    final result = await service.searchSymbols(
      filePaths: workspaceController.files,
      query: query,
      overlayDocuments: overlayDocuments,
    );
    _lastWorkspaceSymbolSearch = result;
    appendLog(
      'Workspace symbol search "${query.pattern}" found '
      '${result.matchCount} match(es) across '
      '${result.matchedFileCount} file(s).',
    );
    return result;
  }

  Future<WorkspaceDefinitionResult> findWorkspaceDefinitions(
    WorkspaceDefinitionQuery query,
  ) async {
    final service = WorkspaceDefinitionService(
      documentStore: workspaceDocumentStore,
    );
    final overlayDocuments = <String, DocumentState>{
      ..._documentCache,
      _activeDocumentPath: editorController.document,
    };
    final result = await service.findDefinitions(
      filePaths: workspaceController.files,
      query: query,
      overlayDocuments: overlayDocuments,
    );
    _lastWorkspaceDefinition = result;
    appendLog(
      'Go to Definition "${query.pattern}" found '
      '${result.matchCount} definition(s) across '
      '${result.matchedFileCount} file(s).',
    );
    return result;
  }

  Future<WorkspaceReferenceSearchResult> findWorkspaceReferences(
    WorkspaceReferenceSearchQuery query,
  ) async {
    final service = WorkspaceReferenceSearchService(
      documentStore: workspaceDocumentStore,
    );
    final overlayDocuments = <String, DocumentState>{
      ..._documentCache,
      _activeDocumentPath: editorController.document,
    };
    final result = await service.findReferences(
      filePaths: workspaceController.files,
      query: query,
      overlayDocuments: overlayDocuments,
    );
    _lastWorkspaceReferenceSearch = result;
    appendLog(
      'Find Usages "${query.pattern}" found '
      '${result.matchCount} reference(s) across '
      '${result.matchedFileCount} file(s).',
    );
    return result;
  }

  Future<WorkspaceCallHierarchyResult> buildWorkspaceCallHierarchy(
    WorkspaceCallHierarchyQuery query,
  ) async {
    final service = WorkspaceCallHierarchyService(
      documentStore: workspaceDocumentStore,
    );
    final overlayDocuments = <String, DocumentState>{
      ..._documentCache,
      _activeDocumentPath: editorController.document,
    };
    final result = await service.buildHierarchy(
      filePaths: workspaceController.files,
      query: query,
      overlayDocuments: overlayDocuments,
    );
    _lastWorkspaceCallHierarchy = result;
    final target = result.target;
    appendLog(
      target == null
          ? 'Call Hierarchy "${query.pattern}" found no callable target.'
          : 'Call Hierarchy ${query.direction.name} for ${target.name} found '
                '${result.callCount} caller/callee node(s) across '
                '${result.referenceCount} reference(s).',
    );
    return result;
  }

  Future<WorkspaceProblemsResult> collectWorkspaceProblems(
    WorkspaceProblemsQuery query,
  ) async {
    final service = WorkspaceProblemsService(
      documentStore: workspaceDocumentStore,
    );
    final overlayDocuments = <String, DocumentState>{
      ..._documentCache,
      _activeDocumentPath: editorController.document,
    };
    final result = await service.collectProblems(
      filePaths: workspaceController.files,
      query: query,
      overlayDocuments: overlayDocuments,
    );
    _lastWorkspaceProblems = result;
    appendLog(
      'Workspace Problems found ${result.problemCount} diagnostic(s) '
      'across ${result.matchedFileCount} file(s).',
    );
    return result;
  }

  CommandPaletteResult searchCommandPalette(CommandPaletteQuery query) {
    final result = const CommandPaletteService().findCommands(
      commands: StyioCommandRegistry.commands,
      query: query,
      recentCommandIds: _recentCommandIds,
      blockedReasonForCommand: blockedReasonForCommand,
    );
    _lastCommandPalette = result;
    return result;
  }

  Future<void> executeCommandPaletteItem(CommandPaletteItem item) async {
    final blockedReason = blockedReasonForCommand(item.commandId);
    if (blockedReason != null) {
      appendLog('${item.label} blocked: $blockedReason');
      return;
    }

    _rememberCommand(item.commandId);
    await executeCommand(item.commandId);
  }

  WorkspaceQuickOpenResult quickOpenWorkspace(
    WorkspaceQuickOpenQuery query,
  ) {
    final result = const WorkspaceQuickOpenService().findFiles(
      filePaths: workspaceController.files,
      query: query,
      recentFilePaths: workspaceController.recentFiles,
    );
    _lastWorkspaceQuickOpen = result;
    return result;
  }

  Future<void> openWorkspaceQuickOpenItem(
    WorkspaceQuickOpenItem item,
  ) async {
    if (!workspaceController.files.contains(item.filePath)) {
      appendLog(
        'Quick Open file unavailable: ${item.filePath} '
        'is not in the current project graph.',
      );
      return;
    }

    if (workspaceController.activeFilePath != item.filePath) {
      _suppressWorkspaceChangedLoad = true;
      try {
        workspaceController.openFile(item.filePath);
      } finally {
        _suppressWorkspaceChangedLoad = false;
      }
      await _loadActiveWorkspaceDocument();
    }

    editorController.selectCollapsed(0);
    appendLog('Quick Open file opened: ${item.filePath}.');
  }

  void _rememberCommand(AppCommandId commandId) {
    final existingIndex = _recentCommandIds.indexOf(commandId);
    if (existingIndex == 0) {
      return;
    }
    if (existingIndex > 0) {
      _recentCommandIds.removeAt(existingIndex);
    }
    _recentCommandIds.insert(0, commandId);
    if (_recentCommandIds.length > 20) {
      _recentCommandIds.removeRange(20, _recentCommandIds.length);
    }
  }

  Future<void> openWorkspaceSearchMatch(
    WorkspaceTextSearchMatch match,
  ) async {
    if (!workspaceController.files.contains(match.filePath)) {
      appendLog(
        'Workspace search match unavailable: ${match.filePath} '
        'is not in the current project graph.',
      );
      return;
    }

    if (workspaceController.activeFilePath != match.filePath) {
      _suppressWorkspaceChangedLoad = true;
      try {
        workspaceController.openFile(match.filePath);
      } finally {
        _suppressWorkspaceChangedLoad = false;
      }
      await _loadActiveWorkspaceDocument();
    }

    editorController.selectRange(
      baseOffset: match.range.start,
      extentOffset: match.range.end,
    );
    appendLog(
      'Workspace search match opened: ${match.filePath} '
      'line ${match.line + 1}.',
    );
  }

  Future<void> openWorkspaceSymbol(
    WorkspaceSymbolSearchItem item,
  ) async {
    if (!workspaceController.files.contains(item.filePath)) {
      appendLog(
        'Workspace symbol unavailable: ${item.filePath} '
        'is not in the current project graph.',
      );
      return;
    }

    if (workspaceController.activeFilePath != item.filePath) {
      _suppressWorkspaceChangedLoad = true;
      try {
        workspaceController.openFile(item.filePath);
      } finally {
        _suppressWorkspaceChangedLoad = false;
      }
      await _loadActiveWorkspaceDocument();
    }

    editorController.selectRange(
      baseOffset: item.nameRange.start,
      extentOffset: item.nameRange.end,
    );
    appendLog(
      'Workspace symbol opened: ${item.name} in ${item.filePath} '
      'line ${item.line + 1}.',
    );
  }

  Future<void> openWorkspaceDefinition(WorkspaceDefinitionItem item) async {
    if (!workspaceController.files.contains(item.filePath)) {
      appendLog(
        'Workspace definition unavailable: ${item.filePath} '
        'is not in the current project graph.',
      );
      return;
    }

    if (workspaceController.activeFilePath != item.filePath) {
      _suppressWorkspaceChangedLoad = true;
      try {
        workspaceController.openFile(item.filePath);
      } finally {
        _suppressWorkspaceChangedLoad = false;
      }
      await _loadActiveWorkspaceDocument();
    }

    editorController.selectRange(
      baseOffset: item.range.start,
      extentOffset: item.range.end,
    );
    appendLog(
      'Workspace definition opened: ${item.name} in ${item.filePath} '
      'line ${item.line + 1}.',
    );
  }

  Future<void> openWorkspaceReference(
    WorkspaceReferenceSearchItem item,
  ) async {
    if (!workspaceController.files.contains(item.filePath)) {
      appendLog(
        'Workspace usage unavailable: ${item.filePath} '
        'is not in the current project graph.',
      );
      return;
    }

    if (workspaceController.activeFilePath != item.filePath) {
      _suppressWorkspaceChangedLoad = true;
      try {
        workspaceController.openFile(item.filePath);
      } finally {
        _suppressWorkspaceChangedLoad = false;
      }
      await _loadActiveWorkspaceDocument();
    }

    editorController.selectRange(
      baseOffset: item.range.start,
      extentOffset: item.range.end,
    );
    appendLog(
      'Workspace reference opened: ${item.name} in ${item.filePath} '
      'line ${item.line + 1}.',
    );
  }

  Future<void> openWorkspaceCallHierarchyLocation(
    WorkspaceCallHierarchyLocation location,
  ) async {
    if (!workspaceController.files.contains(location.filePath)) {
      appendLog(
        'Call hierarchy location unavailable: ${location.filePath} '
        'is not in the current project graph.',
      );
      return;
    }

    if (workspaceController.activeFilePath != location.filePath) {
      _suppressWorkspaceChangedLoad = true;
      try {
        workspaceController.openFile(location.filePath);
      } finally {
        _suppressWorkspaceChangedLoad = false;
      }
      await _loadActiveWorkspaceDocument();
    }

    editorController.selectRange(
      baseOffset: location.range.start,
      extentOffset: location.range.end,
    );
    appendLog(
      'Call hierarchy location opened: ${location.filePath} '
      'line ${location.line + 1}.',
    );
  }

  Future<void> openWorkspaceProblem(WorkspaceProblemItem problem) async {
    if (!workspaceController.files.contains(problem.filePath)) {
      appendLog(
        'Workspace problem unavailable: ${problem.filePath} '
        'is not in the current project graph.',
      );
      return;
    }

    if (workspaceController.activeFilePath != problem.filePath) {
      _suppressWorkspaceChangedLoad = true;
      try {
        workspaceController.openFile(problem.filePath);
      } finally {
        _suppressWorkspaceChangedLoad = false;
      }
      await _loadActiveWorkspaceDocument();
    }

    editorController.selectRange(
      baseOffset: problem.range.start,
      extentOffset: problem.range.end,
    );
    appendLog(
      'Workspace problem opened: ${problem.diagnostic.code} in '
      '${problem.filePath} line ${problem.line + 1}.',
    );
  }

  static String _normalizeDefinitionQuerySeed(String value) {
    var normalized = value.trim();
    if (normalized.contains('\n')) {
      return '';
    }
    while (normalized.startsWith('@') || normalized.startsWith('#')) {
      normalized = normalized.substring(1);
    }
    final match = RegExp(
      r'[A-Za-z_][A-Za-z0-9_]*',
    ).firstMatch(normalized);
    return match?.group(0) ?? '';
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
    _documentCache[_activeDocumentPath] = editorController.document;
    _editorFileBinding.markDocumentChanged(editorController.document);
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
    _documentCache[_activeDocumentPath] = editorController.document;
    _editorFileBinding.markDocumentChanged(editorController.document);
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
    if (_activeDocumentPath != nextPath) {
      return;
    }
    if (cachedDocument != null) {
      _editorFileBinding.bindLoadedDocument(cachedDocument);
    }
    editorController.loadDocument(nextDocument);
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

    var documentId = editorController.document.documentId;
    final activeDocumentId = snapshot.activeDocumentId;
    if (activeDocumentId != null && activeDocumentId != documentId) {
      if (!workspaceController.files.contains(activeDocumentId)) {
        appendLog(
          'Editor session snapshot loaded for $activeDocumentId, '
          'but the document is not available in the workspace.',
        );
        return snapshot;
      }
      _suppressWorkspaceChangedLoad = true;
      try {
        workspaceController.openFile(activeDocumentId);
      } finally {
        _suppressWorkspaceChangedLoad = false;
      }
      await _loadActiveWorkspaceDocument();
      documentId = editorController.document.documentId;
    }

    if (activeDocumentId != null && activeDocumentId != documentId) {
      appendLog(
        'Editor session snapshot loaded for $activeDocumentId, '
        'current document is $documentId.',
      );
      return snapshot;
    }

    final cursorOffset = snapshot.cursorOffsets[documentId];
    final selectionAnchor = snapshot.selectionAnchors[documentId];
    if (cursorOffset != null && selectionAnchor != null) {
      editorController.selectRange(
        baseOffset: selectionAnchor,
        extentOffset: cursorOffset,
      );
    } else if (cursorOffset != null) {
      editorController.selectCollapsed(cursorOffset);
    }
    appendLog('Editor session restored for $documentId.');
    return snapshot;
  }

  @override
  void dispose() {
    workspaceController.removeListener(_handleWorkspaceChanged);
    editorController.removeListener(_handleDocumentChanged);
    languageServiceStatus.removeListener(_handleLanguageServiceStatusChanged);
    toolchainStatusReport?.removeListener(_handleToolchainStatusReportChanged);
    unawaited(_editorFileBindingSubscription?.cancel());
    _editorFileBindingSubscription = null;
    if (_ownsLanguageServiceStatus &&
        languageServiceStatus is ValueNotifier<LanguageServiceStatusSurface>) {
      (languageServiceStatus as ValueNotifier<LanguageServiceStatusSurface>)
          .dispose();
    }
    unawaited(_editorFileBinding.dispose());
    super.dispose();
  }
}
