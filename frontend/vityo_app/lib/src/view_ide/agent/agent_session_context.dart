import '../backend_toolchain/execution_adapter.dart';
import '../commands/app_commands.dart';
import '../debugger/debug_launch_contract.dart';
import '../editor/document_state.dart';
import '../editor/selection_state.dart';
import '../foundation/foundation.dart';
import '../interaction/language_service_status_surface.dart';
import '../language/language_contract.dart';
import '../language/service/language_service_foundation.dart';
import '../language/service/semantic_snapshot_event_bridge.dart';
import '../language/service/semantic_snapshot_provider.dart';
import '../testing/testing.dart';
import '../toolchain/clang_cpp_version_configuration.dart';
import '../toolchain/clang_cpp_version_manager.dart';
import '../toolchain/toolchain_catalog.dart';
import '../toolchain/toolchain_manager.dart';
import '../workspace/workspace.dart';
import 'agent_coding_skill.dart';
import 'agent_profile.dart';
import 'agent_provider_adapter.dart';
import 'agent_provider_registry.dart';
import 'agent_provider_route_executor.dart';

const int _maxAgentCommandResultHistory = 12;
const int _maxAgentPatchApplicationHistory = 12;

class AgentSessionContext {
  const AgentSessionContext({
    required this.schemaVersion,
    required this.document,
    required this.selection,
    required this.diagnostics,
    required this.diagnosticCount,
    required this.diagnosticsTruncated,
    required this.runtime,
    required this.debug,
    required this.workspace,
    required this.agent,
    required this.commands,
    required this.language,
    required this.skills,
    required this.testing,
    required this.toolchains,
    required this.ideCapabilities,
    required this.ideCapabilityClosure,
  });

  final int schemaVersion;
  final AgentDocumentContext document;
  final AgentSelectionContext selection;
  final List<AgentDiagnosticContext> diagnostics;
  final int diagnosticCount;
  final bool diagnosticsTruncated;
  final AgentRuntimeContext runtime;
  final AgentDebugContext debug;
  final AgentWorkspaceContext workspace;
  final AgentCodingLoopContext agent;
  final AgentCommandCatalogContext commands;
  final AgentLanguageContext language;
  final AgentSkillContext skills;
  final AgentTestingContext testing;
  final AgentToolchainContext toolchains;
  final IdeCapabilityFrameworkSnapshot ideCapabilities;
  final IdeCapabilityClosureReport ideCapabilityClosure;

  factory AgentSessionContext.fromEditorState({
    required DocumentState document,
    required SelectionState selection,
    required Iterable<Diagnostic> diagnostics,
    Iterable<Diagnostic> focusedDiagnostics = const <Diagnostic>[],
    ExecutionSession? lastExecutionSession,
    Iterable<RuntimeEventEnvelope> lastRuntimeEvents =
        const <RuntimeEventEnvelope>[],
    Iterable<String> workspaceFiles = const <String>[],
    Iterable<String> openDocumentIds = const <String>[],
    Iterable<String> dirtyDocumentIds = const <String>[],
    Iterable<DocumentState> workspaceDocuments = const <DocumentState>[],
    String workspaceRoot = '',
    AgentWorkspaceSearchResultContext? lastWorkspaceSearch,
    AgentWorkspaceSymbolSearchResultContext? lastWorkspaceSymbolSearch,
    WorkspaceDiagnosticsSnapshot? workspaceDiagnostics,
    SourceControlStatusSnapshot? sourceControlStatus,
    SourceControlDiffSnapshot? sourceControlDiff,
    TestDiscoveryResult? testDiscovery,
    TestRunResult? lastTestRun,
    TokenSpan? focusToken,
    SemanticKind? focusSemanticKind,
    HoverPayload? hover,
    DefinitionTarget? definition,
    ResolvedElement? resolvedElement,
    ResolvedReference? resolvedReference,
    ParameterInfoPayload? parameterInfo,
    SafeDeletePlan? safeDeletePlan,
    InlineVariablePlan? inlineVariablePlan,
    Iterable<SurroundTemplate> surroundTemplates = const <SurroundTemplate>[],
    Iterable<ReferenceSpan> references = const <ReferenceSpan>[],
    Iterable<CompletionItem> completions = const <CompletionItem>[],
    Iterable<DiagnosticQuickFix> codeActions = const <DiagnosticQuickFix>[],
    Iterable<SemanticSpan> semanticSpans = const <SemanticSpan>[],
    Iterable<DocumentSymbol> documentSymbols = const <DocumentSymbol>[],
    Iterable<InlayHint> inlayHints = const <InlayHint>[],
    Iterable<SemanticBlockRange> semanticBlocks = const <SemanticBlockRange>[],
    Iterable<SemanticSnapshotPanelViewModel> semanticPanelViewModels =
        const <SemanticSnapshotPanelViewModel>[],
    LanguageServiceStatusSurface? languageServiceStatus,
    IdeCapabilityFrameworkSnapshot? ideCapabilityFramework,
    ToolchainStateSnapshot? toolchainSnapshot,
    ClangCppVersionPreference? clangCppVersionPreference,
    AgentCommandResultContext? lastCommandResult,
    Iterable<AgentCommandResultContext> recentCommandResults =
        const <AgentCommandResultContext>[],
    AgentPendingPatchContext? pendingPatch,
    Iterable<AgentPendingPatchContext> recentPatchProposals =
        const <AgentPendingPatchContext>[],
    Iterable<AgentPendingIdeCommandContext> pendingIdeCommands =
        const <AgentPendingIdeCommandContext>[],
    Iterable<AgentPendingIdeCommandContext> recentIdeCommandSuggestions =
        const <AgentPendingIdeCommandContext>[],
    AgentProviderFailureContext? lastProviderFailure,
    AgentProviderSelectionPlan? providerSelectionPlan,
    AgentProviderExecutionResolution? providerExecutionResolution,
    AgentPatchApplicationContext? lastPatchApplication,
    Iterable<AgentPatchApplicationContext> recentPatchApplications =
        const <AgentPatchApplicationContext>[],
    Iterable<AgentCodingPlanContext> recentCodingPlans =
        const <AgentCodingPlanContext>[],
    Iterable<AgentDiagnosticSummaryContext> recentDiagnosticSummaries =
        const <AgentDiagnosticSummaryContext>[],
    AgentDebugContext debug = const AgentDebugContext.idle(),
    String? activeFilePath,
    int maxDiagnostics = 100,
  }) {
    final diagnosticList = diagnostics.toList(growable: false);
    final diagnosticsTruncated = diagnosticList.length > maxDiagnostics;
    final toolchainContext = AgentToolchainContext.fromSnapshot(
      toolchainSnapshot,
      clangCppVersionPreference: clangCppVersionPreference,
    );
    final workspaceContext = AgentWorkspaceContext.fromWorkspaceState(
      activeFilePath: activeFilePath ?? document.documentId,
      files: workspaceFiles,
      openDocumentIds: openDocumentIds,
      dirtyDocumentIds: dirtyDocumentIds,
      documentSamples: _workspaceDocumentSamplesWithActive(
        activeDocument: document,
        workspaceDocuments: workspaceDocuments,
      ),
      workspaceRoot: workspaceRoot,
      lastSearch: lastWorkspaceSearch,
      lastSymbolSearch: lastWorkspaceSymbolSearch,
      diagnostics: workspaceDiagnostics,
      sourceControlStatus: sourceControlStatus,
      sourceControlDiff: sourceControlDiff,
    );
    final capabilitySnapshot =
        ideCapabilityFramework ??
        const VityoIdeCapabilityFramework().snapshot();
    return AgentSessionContext(
      schemaVersion: 48,
      document: AgentDocumentContext.fromDocument(
        document,
        selection: selection,
      ),
      selection: AgentSelectionContext.fromDocumentSelection(
        document: document,
        selection: selection,
      ),
      diagnostics: diagnosticList
          .take(maxDiagnostics)
          .map(
            (diagnostic) => AgentDiagnosticContext.fromDiagnostic(
              diagnostic,
              document: document,
            ),
          )
          .toList(growable: false),
      diagnosticCount: diagnosticList.length,
      diagnosticsTruncated: diagnosticsTruncated,
      runtime: AgentRuntimeContext.fromRuntimeState(
        lastExecutionSession: lastExecutionSession,
        lastRuntimeEvents: lastRuntimeEvents,
      ),
      debug: debug,
      workspace: workspaceContext,
      agent: AgentCodingLoopContext.fromPatchApplications(
        pendingPatch: pendingPatch,
        recentPatchProposals: recentPatchProposals,
        pendingIdeCommands: pendingIdeCommands,
        recentIdeCommandSuggestions: recentIdeCommandSuggestions,
        lastProviderFailure: lastProviderFailure,
        providerSelection: providerSelectionPlan == null
            ? null
            : AgentProviderSelectionContext.fromPlan(providerSelectionPlan),
        providerExecution: providerExecutionResolution == null
            ? null
            : AgentProviderExecutionContext.fromResolution(
                providerExecutionResolution,
              ),
        lastPatchApplication: lastPatchApplication,
        recentPatchApplications: recentPatchApplications,
        recentCodingPlans: recentCodingPlans,
        recentDiagnosticSummaries: recentDiagnosticSummaries,
      ),
      commands: AgentCommandCatalogContext.fromRegistry(
        lastResult: lastCommandResult,
        recentResults: recentCommandResults,
        toolchains: toolchainContext,
        debug: debug,
        dirtyDocumentIds: workspaceContext.dirtyDocumentIds,
        buildFacts: workspaceContext.buildFacts,
      ),
      language: AgentLanguageContext.fromSelection(
        document: document,
        focusToken: focusToken,
        focusSemanticKind: focusSemanticKind,
        focusedDiagnostics: focusedDiagnostics,
        hover: hover,
        definition: definition,
        resolvedElement: resolvedElement,
        resolvedReference: resolvedReference,
        parameterInfo: parameterInfo,
        safeDeletePlan: safeDeletePlan,
        inlineVariablePlan: inlineVariablePlan,
        surroundTemplates: surroundTemplates,
        references: references,
        completions: completions,
        codeActions: codeActions,
        semanticSpans: semanticSpans,
        documentSymbols: documentSymbols,
        inlayHints: inlayHints,
        semanticBlocks: semanticBlocks,
        semanticPanelViewModels: semanticPanelViewModels,
        serviceStatus: languageServiceStatus == null
            ? null
            : AgentLanguageServiceStatusContext.fromSurface(
                languageServiceStatus,
              ),
      ),
      skills: AgentCodingSkillCatalog.contextForWorkspace(
        activeDocumentId: activeFilePath ?? document.documentId,
        workspaceFiles: workspaceFiles,
        styioServiceAvailable:
            languageServiceStatus != null &&
            (languageServiceStatus.usableCapabilityCount > 0 ||
                languageServiceStatus.toolchainId.isNotEmpty ||
                languageServiceStatus.primaryCapabilityStates.isNotEmpty),
      ),
      testing: AgentTestingContext.fromState(
        discovery: testDiscovery,
        lastRun: lastTestRun,
        workspaceRoot: workspaceRoot,
      ),
      toolchains: toolchainContext,
      ideCapabilities: capabilitySnapshot,
      ideCapabilityClosure: const IdeCapabilityClosureGate().evaluate(
        capabilitySnapshot,
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'document': document.toJson(),
      'selection': selection.toJson(),
      'diagnostics': diagnostics
          .map((diagnostic) => diagnostic.toJson())
          .toList(growable: false),
      'diagnosticCount': diagnosticCount,
      'diagnosticsTruncated': diagnosticsTruncated,
      'runtime': runtime.toJson(),
      'debug': debug.toJson(),
      'workspace': workspace.toJson(),
      'agent': agent.toJson(),
      'commands': commands.toJson(),
      'language': language.toJson(),
      'skills': skills.toJson(),
      'testing': testing.toJson(),
      'toolchains': toolchains.toJson(),
      'ideCapabilities': ideCapabilities.toJson(),
      'ideCapabilityClosure': ideCapabilityClosure.toJson(),
    };
  }

  Map<String, Object?> toJsonForChannels(Iterable<String> channels) {
    final channelSet = channels.toSet();
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      if (channelSet.contains('file')) 'document': document.toJson(),
      if (channelSet.contains('selection')) 'selection': selection.toJson(),
      if (channelSet.contains('diagnostics'))
        'diagnostics': diagnostics
            .map((diagnostic) => diagnostic.toJson())
            .toList(growable: false),
      if (channelSet.contains('diagnostics'))
        'diagnosticCount': diagnosticCount,
      if (channelSet.contains('diagnostics'))
        'diagnosticsTruncated': diagnosticsTruncated,
      if (channelSet.contains('runtime')) 'runtime': runtime.toJson(),
      if (channelSet.contains('debug')) 'debug': debug.toJson(),
      if (channelSet.contains('workspace')) 'workspace': workspace.toJson(),
      if (channelSet.contains('agent')) 'agent': agent.toJson(),
      if (channelSet.contains('language')) 'language': language.toJson(),
      if (channelSet.contains('commands')) 'commands': commands.toJson(),
      if (channelSet.contains('skills')) 'skills': skills.toJson(),
      if (channelSet.contains('testing')) 'testing': testing.toJson(),
      if (channelSet.contains('toolchains')) 'toolchains': toolchains.toJson(),
      if (channelSet.contains('ideCapabilities'))
        'ideCapabilities': ideCapabilities.toJson(),
      if (channelSet.contains('ideCapabilityClosure'))
        'ideCapabilityClosure': ideCapabilityClosure.toJson(),
    };
  }

  AgentSessionContext withLastPatchApplication(
    AgentPatchApplicationContext? lastPatchApplication,
  ) {
    return withAgentCodingState(lastPatchApplication: lastPatchApplication);
  }

  AgentSessionContext withAgentCodingState({
    AgentCommandResultContext? lastCommandResult,
    Iterable<AgentCommandResultContext> recentCommandResults =
        const <AgentCommandResultContext>[],
    AgentPendingPatchContext? pendingPatch,
    Iterable<AgentPendingPatchContext> recentPatchProposals =
        const <AgentPendingPatchContext>[],
    Iterable<AgentPendingIdeCommandContext> pendingIdeCommands =
        const <AgentPendingIdeCommandContext>[],
    Iterable<AgentPendingIdeCommandContext> recentIdeCommandSuggestions =
        const <AgentPendingIdeCommandContext>[],
    AgentProviderFailureContext? lastProviderFailure,
    AgentProviderSelectionPlan? providerSelectionPlan,
    AgentProviderExecutionResolution? providerExecutionResolution,
    AgentPatchApplicationContext? lastPatchApplication,
    Iterable<AgentPatchApplicationContext> recentPatchApplications =
        const <AgentPatchApplicationContext>[],
    Iterable<AgentCodingPlanContext> recentCodingPlans =
        const <AgentCodingPlanContext>[],
    Iterable<AgentDiagnosticSummaryContext> recentDiagnosticSummaries =
        const <AgentDiagnosticSummaryContext>[],
  }) {
    final pendingIdeCommandList = pendingIdeCommands.toList(growable: false);
    final recentPatchProposalList = recentPatchProposals.toList(
      growable: false,
    );
    final recentIdeCommandSuggestionList = recentIdeCommandSuggestions.toList(
      growable: false,
    );
    final recentCommandResultList = recentCommandResults.toList(
      growable: false,
    );
    final recentCodingPlanList = recentCodingPlans.toList(growable: false);
    final recentDiagnosticSummaryList = recentDiagnosticSummaries.toList(
      growable: false,
    );
    if (pendingPatch == null &&
        recentPatchProposalList.isEmpty &&
        lastCommandResult == null &&
        recentCommandResultList.isEmpty &&
        pendingIdeCommandList.isEmpty &&
        recentIdeCommandSuggestionList.isEmpty &&
        recentCodingPlanList.isEmpty &&
        recentDiagnosticSummaryList.isEmpty &&
        lastProviderFailure == null &&
        providerSelectionPlan == null &&
        providerExecutionResolution == null &&
        lastPatchApplication == null) {
      final recentPatchApplicationList = recentPatchApplications.toList(
        growable: false,
      );
      if (recentPatchApplicationList.isEmpty) {
        return this;
      }
    }
    final commandResultHistory =
        lastCommandResult == null && recentCommandResultList.isEmpty
        ? commands.recentResults
        : _agentCommandResultHistory(
            lastResult: lastCommandResult,
            recentResults: recentCommandResultList,
          );
    return AgentSessionContext(
      schemaVersion: schemaVersion,
      document: document,
      selection: selection,
      diagnostics: diagnostics,
      diagnosticCount: diagnosticCount,
      diagnosticsTruncated: diagnosticsTruncated,
      runtime: runtime,
      debug: debug,
      workspace: workspace,
      agent: AgentCodingLoopContext.fromPatchApplications(
        pendingPatch: pendingPatch,
        recentPatchProposals: recentPatchProposalList,
        pendingIdeCommands: pendingIdeCommandList,
        recentIdeCommandSuggestions: recentIdeCommandSuggestionList,
        lastProviderFailure: lastProviderFailure,
        providerSelection: providerSelectionPlan == null
            ? agent.providerSelection
            : AgentProviderSelectionContext.fromPlan(providerSelectionPlan),
        providerExecution: providerExecutionResolution == null
            ? agent.providerExecution
            : AgentProviderExecutionContext.fromResolution(
                providerExecutionResolution,
              ),
        lastPatchApplication: lastPatchApplication,
        recentPatchApplications: recentPatchApplications,
        recentCodingPlans: recentCodingPlanList,
        recentDiagnosticSummaries: recentDiagnosticSummaryList,
      ),
      commands: AgentCommandCatalogContext(
        persistenceCommands: commands.persistenceCommands,
        diagnosticCommands: commands.diagnosticCommands,
        languageServiceCommands: commands.languageServiceCommands,
        sourceControlCommands: commands.sourceControlCommands,
        codingCommands: commands.codingCommands,
        navigationCommands: commands.navigationCommands,
        refactorCommands: commands.refactorCommands,
        toolchainCommands: commands.toolchainCommands,
        nativeToolCommands: commands.nativeToolCommands,
        nativeToolCommandReadiness: commands.nativeToolCommandReadiness,
        debugCommands: commands.debugCommands,
        debugCommandReadiness: commands.debugCommandReadiness,
        settingsCommands: commands.settingsCommands,
        recentResults: commandResultHistory,
        lastResult: lastCommandResult ?? commands.lastResult,
      ),
      language: language,
      skills: skills,
      testing: testing,
      toolchains: toolchains,
      ideCapabilities: ideCapabilities,
      ideCapabilityClosure: ideCapabilityClosure,
    );
  }
}

class AgentCodingLoopContext {
  const AgentCodingLoopContext({
    this.pendingPatch,
    this.recentPatchProposals = const <AgentPendingPatchContext>[],
    this.pendingIdeCommands = const <AgentPendingIdeCommandContext>[],
    this.recentIdeCommandSuggestions = const <AgentPendingIdeCommandContext>[],
    this.lastProviderFailure,
    this.providerSelection,
    this.providerExecution,
    this.lastPatchApplication,
    this.recentPatchApplications = const <AgentPatchApplicationContext>[],
    this.recentCodingPlans = const <AgentCodingPlanContext>[],
    this.recentDiagnosticSummaries = const <AgentDiagnosticSummaryContext>[],
  });

  factory AgentCodingLoopContext.fromPatchApplications({
    AgentPendingPatchContext? pendingPatch,
    Iterable<AgentPendingPatchContext> recentPatchProposals =
        const <AgentPendingPatchContext>[],
    Iterable<AgentPendingIdeCommandContext> pendingIdeCommands =
        const <AgentPendingIdeCommandContext>[],
    Iterable<AgentPendingIdeCommandContext> recentIdeCommandSuggestions =
        const <AgentPendingIdeCommandContext>[],
    AgentProviderFailureContext? lastProviderFailure,
    AgentProviderSelectionContext? providerSelection,
    AgentProviderExecutionContext? providerExecution,
    AgentPatchApplicationContext? lastPatchApplication,
    Iterable<AgentPatchApplicationContext> recentPatchApplications =
        const <AgentPatchApplicationContext>[],
    Iterable<AgentCodingPlanContext> recentCodingPlans =
        const <AgentCodingPlanContext>[],
    Iterable<AgentDiagnosticSummaryContext> recentDiagnosticSummaries =
        const <AgentDiagnosticSummaryContext>[],
  }) {
    final history = _agentPatchApplicationHistory(
      lastPatchApplication: lastPatchApplication,
      recentPatchApplications: recentPatchApplications,
    );
    return AgentCodingLoopContext(
      pendingPatch: pendingPatch,
      recentPatchProposals: recentPatchProposals.toList(growable: false),
      pendingIdeCommands: pendingIdeCommands.toList(growable: false),
      recentIdeCommandSuggestions: recentIdeCommandSuggestions.toList(
        growable: false,
      ),
      lastProviderFailure: lastProviderFailure,
      providerSelection: providerSelection,
      providerExecution: providerExecution,
      lastPatchApplication: history.isEmpty ? null : history.first,
      recentPatchApplications: history,
      recentCodingPlans: recentCodingPlans.toList(growable: false),
      recentDiagnosticSummaries: recentDiagnosticSummaries.toList(
        growable: false,
      ),
    );
  }

  final AgentPendingPatchContext? pendingPatch;
  final List<AgentPendingPatchContext> recentPatchProposals;
  final List<AgentPendingIdeCommandContext> pendingIdeCommands;
  final List<AgentPendingIdeCommandContext> recentIdeCommandSuggestions;
  final AgentProviderFailureContext? lastProviderFailure;
  final AgentProviderSelectionContext? providerSelection;
  final AgentProviderExecutionContext? providerExecution;
  final AgentPatchApplicationContext? lastPatchApplication;
  final List<AgentPatchApplicationContext> recentPatchApplications;
  final List<AgentCodingPlanContext> recentCodingPlans;
  final List<AgentDiagnosticSummaryContext> recentDiagnosticSummaries;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (pendingPatch != null) 'pendingPatch': pendingPatch!.toJson(),
      if (recentPatchProposals.isNotEmpty)
        'recentPatchProposals': recentPatchProposals
            .map((patch) => patch.toJson())
            .toList(growable: false),
      if (pendingIdeCommands.isNotEmpty)
        'pendingIdeCommands': pendingIdeCommands
            .map((command) => command.toJson())
            .toList(growable: false),
      if (recentIdeCommandSuggestions.isNotEmpty)
        'recentIdeCommandSuggestions': recentIdeCommandSuggestions
            .map((command) => command.toJson())
            .toList(growable: false),
      if (lastProviderFailure != null)
        'lastProviderFailure': lastProviderFailure!.toJson(),
      if (providerSelection != null)
        'providerSelection': providerSelection!.toJson(),
      if (providerExecution != null)
        'providerExecution': providerExecution!.toJson(),
      if (lastPatchApplication != null)
        'lastPatchApplication': lastPatchApplication!.toJson(),
      if (recentPatchApplications.isNotEmpty)
        'recentPatchApplications': recentPatchApplications
            .map((application) => application.toJson())
            .toList(growable: false),
      if (recentCodingPlans.isNotEmpty)
        'recentCodingPlans': recentCodingPlans
            .map((plan) => plan.toJson())
            .toList(growable: false),
      if (recentDiagnosticSummaries.isNotEmpty)
        'recentDiagnosticSummaries': recentDiagnosticSummaries
            .map((summary) => summary.toJson())
            .toList(growable: false),
    };
  }
}

class AgentCodingPlanContext {
  const AgentCodingPlanContext({
    required this.summary,
    required this.steps,
    required this.acceptanceCriteria,
    this.risks = const <String>[],
    this.text = '',
  });

  final String summary;
  final List<String> steps;
  final List<String> acceptanceCriteria;
  final List<String> risks;
  final String text;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (summary.trim().isNotEmpty) 'summary': summary,
      'steps': steps,
      'acceptanceCriteria': acceptanceCriteria,
      if (risks.isNotEmpty) 'risks': risks,
      if (text.trim().isNotEmpty) 'text': text,
    };
  }
}

class AgentDiagnosticSummaryContext {
  const AgentDiagnosticSummaryContext({
    required this.title,
    required this.summary,
    this.severity = 'info',
    this.diagnosticCount = 0,
    this.affectedDocuments = const <String>[],
    this.suggestedCommandIds = const <String>[],
    this.text = '',
  });

  final String title;
  final String summary;
  final String severity;
  final int diagnosticCount;
  final List<String> affectedDocuments;
  final List<String> suggestedCommandIds;
  final String text;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (title.trim().isNotEmpty) 'title': title,
      if (summary.trim().isNotEmpty) 'summary': summary,
      'severity': severity,
      'diagnosticCount': diagnosticCount,
      if (affectedDocuments.isNotEmpty) 'affectedDocuments': affectedDocuments,
      if (suggestedCommandIds.isNotEmpty)
        'suggestedCommandIds': suggestedCommandIds,
      if (text.trim().isNotEmpty) 'text': text,
    };
  }
}

class AgentProviderExecutionContext {
  const AgentProviderExecutionContext({
    required this.status,
    this.selectedEndpointIndex,
    this.endpoints = const <AgentProviderEndpointExecutionContext>[],
  });

  factory AgentProviderExecutionContext.fromResolution(
    AgentProviderExecutionResolution resolution,
  ) {
    return AgentProviderExecutionContext(
      status: resolution.status.wireValue,
      selectedEndpointIndex: resolution.selectedEndpointIndex,
      endpoints: resolution.endpoints
          .map(AgentProviderEndpointExecutionContext.fromReadiness)
          .toList(growable: false),
    );
  }

  final String status;
  final int? selectedEndpointIndex;
  final List<AgentProviderEndpointExecutionContext> endpoints;

  AgentProviderEndpointExecutionContext? get selectedEndpoint {
    final selected = selectedEndpointIndex;
    if (selected == null) {
      return null;
    }
    for (final endpoint in endpoints) {
      if (endpoint.endpointIndex == selected) {
        return endpoint;
      }
    }
    return null;
  }

  int get missingCredentialEndpointCount {
    return endpoints
        .where(
          (endpoint) =>
              endpoint.requiresCredential &&
              endpoint.credentialReadiness ==
                  AgentProviderCredentialReadiness.unavailable.wireValue,
        )
        .length;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status,
      if (selectedEndpointIndex != null)
        'selectedEndpointIndex': selectedEndpointIndex,
      'missingCredentialEndpointCount': missingCredentialEndpointCount,
      'endpoints': endpoints
          .map((endpoint) => endpoint.toJson())
          .toList(growable: false),
    };
  }
}

class AgentProviderEndpointExecutionContext {
  const AgentProviderEndpointExecutionContext({
    required this.endpointIndex,
    required this.fallback,
    required this.routeKind,
    required this.providerKind,
    required this.route,
    required this.baseUrl,
    required this.model,
    required this.requiresCredential,
    required this.credentialReadiness,
    required this.probeStatus,
    required this.executable,
    this.blockReason,
  });

  factory AgentProviderEndpointExecutionContext.fromReadiness(
    AgentProviderEndpointReadiness readiness,
  ) {
    return AgentProviderEndpointExecutionContext(
      endpointIndex: readiness.endpointIndex,
      fallback: readiness.fallback,
      routeKind: readiness.plan.routeKind.wireValue,
      providerKind: readiness.plan.providerKind.wireValue,
      route: readiness.endpoint.route.wireValue,
      baseUrl: readiness.endpoint.baseUrl,
      model: readiness.endpoint.model,
      requiresCredential: readiness.endpoint.requiresCredential,
      credentialReadiness: readiness.credentialReadiness.wireValue,
      probeStatus: readiness.probeResult.status.wireValue,
      executable: readiness.executable,
      blockReason: readiness.plan.blockReason?.wireValue,
    );
  }

  final int endpointIndex;
  final bool fallback;
  final String routeKind;
  final String providerKind;
  final String route;
  final String baseUrl;
  final String model;
  final bool requiresCredential;
  final String credentialReadiness;
  final String probeStatus;
  final bool executable;
  final String? blockReason;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'endpointIndex': endpointIndex,
      'fallback': fallback,
      'routeKind': routeKind,
      'providerKind': providerKind,
      'route': route,
      'baseUrl': baseUrl,
      'model': model,
      'requiresCredential': requiresCredential,
      'credentialReadiness': credentialReadiness,
      'probeStatus': probeStatus,
      'executable': executable,
      if (blockReason != null) 'blockReason': blockReason,
    };
  }
}

class AgentProviderSelectionContext {
  const AgentProviderSelectionContext({
    required this.status,
    required this.route,
    required this.protocol,
    required this.requiresCredential,
    required this.ready,
    this.executable = false,
    this.credentialReadiness = '',
    this.executionStatus = '',
    this.selectedEndpointIndex,
    this.selectedProvider,
    this.candidates = const <AgentProviderRegistrationManifest>[],
    this.message = '',
    this.todo = '',
  });

  factory AgentProviderSelectionContext.fromPlan(
    AgentProviderSelectionPlan plan,
  ) {
    return AgentProviderSelectionContext(
      status: plan.status.wireValue,
      route: plan.route.wireValue,
      protocol: plan.protocol,
      requiresCredential: plan.requiresCredential,
      ready: plan.ready,
      executable: plan.executable,
      credentialReadiness: plan.credentialReadiness?.wireValue ?? '',
      executionStatus: plan.executionStatus?.wireValue ?? '',
      selectedEndpointIndex: plan.selectedEndpointIndex,
      selectedProvider: plan.selectedProvider,
      candidates: plan.candidates,
      message: plan.message,
      todo: plan.todo,
    );
  }

  final String status;
  final String route;
  final String protocol;
  final bool requiresCredential;
  final bool ready;
  final bool executable;
  final String credentialReadiness;
  final String executionStatus;
  final int? selectedEndpointIndex;
  final AgentProviderRegistrationManifest? selectedProvider;
  final List<AgentProviderRegistrationManifest> candidates;
  final String message;
  final String todo;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status,
      'route': route,
      'protocol': protocol,
      'requiresCredential': requiresCredential,
      'ready': ready,
      'executable': executable,
      if (credentialReadiness.isNotEmpty)
        'credentialReadiness': credentialReadiness,
      if (executionStatus.isNotEmpty) 'executionStatus': executionStatus,
      if (selectedEndpointIndex != null)
        'selectedEndpointIndex': selectedEndpointIndex,
      if (selectedProvider != null)
        'selectedProvider': selectedProvider!.toJson(),
      'candidateCount': candidates.length,
      if (candidates.isNotEmpty)
        'candidates': candidates
            .map((candidate) => candidate.toJson())
            .toList(growable: false),
      if (message.isNotEmpty) 'message': message,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class AgentPendingPatchContext {
  const AgentPendingPatchContext({
    required this.patchId,
    required this.summary,
    this.baseRevision,
    required this.documentIds,
    required this.editCount,
    required this.operationCounts,
    required this.edits,
    required this.editsTruncated,
  });

  final String patchId;
  final String summary;
  final int? baseRevision;
  final List<String> documentIds;
  final int editCount;
  final Map<String, int> operationCounts;
  final List<AgentPendingPatchEditContext> edits;
  final bool editsTruncated;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'patchId': patchId,
      if (summary.trim().isNotEmpty) 'summary': summary,
      if (baseRevision != null) 'baseRevision': baseRevision,
      'documentIds': documentIds,
      'editCount': editCount,
      'operationCounts': operationCounts,
      'edits': edits.map((edit) => edit.toJson()).toList(growable: false),
      'editsTruncated': editsTruncated,
    };
  }
}

class AgentPendingPatchEditContext {
  const AgentPendingPatchEditContext({
    required this.documentId,
    required this.operation,
    required this.start,
    required this.end,
    required this.replacementTextSample,
    required this.replacementTextLength,
    required this.replacementTextTruncated,
    this.baseRevision,
  });

  final String documentId;
  final String operation;
  final int start;
  final int end;
  final String replacementTextSample;
  final int replacementTextLength;
  final bool replacementTextTruncated;
  final int? baseRevision;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'operation': operation,
      if (baseRevision != null) 'baseRevision': baseRevision,
      'start': start,
      'end': end,
      'replacementTextSample': replacementTextSample,
      'replacementTextLength': replacementTextLength,
      'replacementTextTruncated': replacementTextTruncated,
    };
  }
}

class AgentPendingIdeCommandContext {
  const AgentPendingIdeCommandContext({
    required this.commandId,
    required this.reason,
    this.input,
    this.prerequisiteForCommandId,
    this.text = '',
  });

  final String commandId;
  final String? input;
  final String reason;
  final String? prerequisiteForCommandId;
  final String text;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'commandId': commandId,
      if (input != null) 'input': input,
      'reason': reason,
      if (prerequisiteForCommandId != null)
        'prerequisiteForCommandId': prerequisiteForCommandId,
      if (text.trim().isNotEmpty) 'text': text,
    };
  }
}

class AgentProviderFailureContext {
  const AgentProviderFailureContext({
    required this.kind,
    required this.message,
    required this.operation,
    this.statusCode,
    this.target,
    this.recoveryHint,
  });

  final String kind;
  final String message;
  final String operation;
  final int? statusCode;
  final String? target;
  final String? recoveryHint;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind,
      'message': message,
      'operation': operation,
      if (statusCode != null) 'statusCode': statusCode,
      if (target != null) 'target': target,
      if (recoveryHint != null) 'recoveryHint': recoveryHint,
    };
  }
}

class AgentPatchApplicationContext {
  const AgentPatchApplicationContext({
    required this.patchId,
    required this.applied,
    required this.pendingPatchRetained,
    required this.message,
    required this.editCount,
    this.summary = '',
    this.baseRevision,
    this.documentIds = const <String>[],
    this.operationCounts = const <String, int>{},
    this.appliedEditCount = 0,
    this.appliedOperationCounts = const <String, int>{},
    this.changedDocumentIds = const <String>[],
    this.createdDocumentIds = const <String>[],
    this.deletedDocumentIds = const <String>[],
    this.skippedNoOpDocumentIds = const <String>[],
    this.recordedAt,
  });

  final String patchId;
  final String summary;
  final int? baseRevision;
  final List<String> documentIds;
  final int editCount;
  final Map<String, int> operationCounts;
  final bool applied;
  final bool pendingPatchRetained;
  final String message;
  final int appliedEditCount;
  final Map<String, int> appliedOperationCounts;
  final List<String> changedDocumentIds;
  final List<String> createdDocumentIds;
  final List<String> deletedDocumentIds;
  final List<String> skippedNoOpDocumentIds;
  final DateTime? recordedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'patchId': patchId,
      if (summary.trim().isNotEmpty) 'summary': summary,
      if (baseRevision != null) 'baseRevision': baseRevision,
      'documentIds': documentIds,
      'editCount': editCount,
      'operationCounts': operationCounts,
      'applied': applied,
      'pendingPatchRetained': pendingPatchRetained,
      'message': message,
      'appliedEditCount': appliedEditCount,
      'appliedOperationCounts': appliedOperationCounts,
      'changedDocumentIds': changedDocumentIds,
      'createdDocumentIds': createdDocumentIds,
      'deletedDocumentIds': deletedDocumentIds,
      'skippedNoOpDocumentIds': skippedNoOpDocumentIds,
      if (recordedAt != null)
        'recordedAt': recordedAt!.toUtc().toIso8601String(),
    };
  }
}

class AgentDebugContext {
  const AgentDebugContext({
    required this.status,
    required this.message,
    this.debuggerId,
    this.debuggerLabel,
    required this.breakpointCount,
    required this.breakpoints,
    required this.threadCount,
    required this.threads,
    required this.stackFrameCount,
    required this.stackFrames,
    required this.variableCount,
    required this.variables,
    this.launch,
    this.adapterSessionStatus,
    this.adapterPendingRequestCount = 0,
    this.adapterEventCount = 0,
  });

  const AgentDebugContext.idle()
    : status = 'idle',
      message = 'No debug session has been started.',
      debuggerId = null,
      debuggerLabel = null,
      breakpointCount = 0,
      breakpoints = const <AgentDebugBreakpointContext>[],
      threadCount = 0,
      threads = const <AgentDebugThreadContext>[],
      stackFrameCount = 0,
      stackFrames = const <AgentDebugStackFrameContext>[],
      variableCount = 0,
      variables = const <AgentDebugVariableContext>[],
      launch = null,
      adapterSessionStatus = null,
      adapterPendingRequestCount = 0,
      adapterEventCount = 0;

  final String status;
  final String message;
  final String? debuggerId;
  final String? debuggerLabel;
  final int breakpointCount;
  final List<AgentDebugBreakpointContext> breakpoints;
  final int threadCount;
  final List<AgentDebugThreadContext> threads;
  final int stackFrameCount;
  final List<AgentDebugStackFrameContext> stackFrames;
  final int variableCount;
  final List<AgentDebugVariableContext> variables;
  final AgentDebugLaunchContext? launch;
  final String? adapterSessionStatus;
  final int adapterPendingRequestCount;
  final int adapterEventCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status,
      'message': message,
      if (debuggerId != null) 'debuggerId': debuggerId,
      if (debuggerLabel != null) 'debuggerLabel': debuggerLabel,
      'breakpointCount': breakpointCount,
      'breakpoints': breakpoints
          .map((breakpoint) => breakpoint.toJson())
          .toList(growable: false),
      'threadCount': threadCount,
      'threads': threads
          .map((thread) => thread.toJson())
          .toList(growable: false),
      'stackFrameCount': stackFrameCount,
      'stackFrames': stackFrames
          .map((frame) => frame.toJson())
          .toList(growable: false),
      'variableCount': variableCount,
      'variables': variables
          .map((variable) => variable.toJson())
          .toList(growable: false),
      if (launch != null) 'launch': launch!.toJson(),
      if (adapterSessionStatus != null)
        'adapterSessionStatus': adapterSessionStatus,
      'adapterPendingRequestCount': adapterPendingRequestCount,
      'adapterEventCount': adapterEventCount,
    };
  }
}

class AgentDebugLaunchContext {
  const AgentDebugLaunchContext({
    required this.ready,
    required this.readiness,
    required this.reason,
    required this.adapterProtocol,
    required this.debuggerId,
    required this.debuggerLabel,
    required this.debuggerExecutablePath,
    this.debuggerArguments = const <String>[],
    this.programPath,
    required this.cwd,
    this.arguments = const <String>[],
    this.environment = const <String, String>{},
    this.stopOnEntry = false,
    required this.breakpointCount,
  });

  final bool ready;
  final String readiness;
  final String reason;
  final String adapterProtocol;
  final String debuggerId;
  final String debuggerLabel;
  final String debuggerExecutablePath;
  final List<String> debuggerArguments;
  final String? programPath;
  final String cwd;
  final List<String> arguments;
  final Map<String, String> environment;
  final bool stopOnEntry;
  final int breakpointCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ready': ready,
      'readiness': readiness,
      'reason': reason,
      'adapterProtocol': adapterProtocol,
      'debuggerId': debuggerId,
      'debuggerLabel': debuggerLabel,
      'debuggerExecutablePath': debuggerExecutablePath,
      'debuggerArguments': debuggerArguments,
      if (programPath != null) 'programPath': programPath,
      'cwd': cwd,
      'arguments': arguments,
      'environment': environment,
      'stopOnEntry': stopOnEntry,
      'breakpointCount': breakpointCount,
    };
  }
}

class AgentDebugBreakpointContext {
  const AgentDebugBreakpointContext({
    required this.filePath,
    required this.line,
    required this.enabled,
  });

  final String filePath;
  final int line;
  final bool enabled;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'filePath': filePath,
      'line': line,
      'enabled': enabled,
    };
  }
}

class AgentDebugThreadContext {
  const AgentDebugThreadContext({required this.id, required this.name});

  final String id;
  final String name;

  Map<String, Object?> toJson() {
    return <String, Object?>{'id': id, 'name': name};
  }
}

class AgentDebugStackFrameContext {
  const AgentDebugStackFrameContext({
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'name': name,
      'filePath': filePath,
      'line': line,
      'column': column,
    };
  }
}

class AgentDebugVariableContext {
  const AgentDebugVariableContext({
    required this.name,
    required this.value,
    this.type,
  });

  final String name;
  final String value;
  final String? type;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'value': value,
      if (type != null) 'type': type,
    };
  }
}

class AgentToolchainContext {
  const AgentToolchainContext({
    required this.entries,
    required this.activeCompiler,
    this.clangCpp,
  });

  factory AgentToolchainContext.fromSnapshot(
    ToolchainStateSnapshot? snapshot, {
    int maxEntries = 20,
    ClangCppVersionPreference? clangCppVersionPreference,
  }) {
    if (snapshot == null) {
      return const AgentToolchainContext(
        entries: <AgentToolchainEntryContext>[],
        activeCompiler: null,
      );
    }
    final entries = snapshot.entries
        .take(maxEntries)
        .map(AgentToolchainEntryContext.fromStateEntry)
        .toList(growable: false);
    final activeCompiler = snapshot.active(ToolchainKind.compiler);
    return AgentToolchainContext(
      entries: entries,
      activeCompiler: activeCompiler == null
          ? null
          : AgentToolchainEntryContext.fromStateEntry(activeCompiler),
      clangCpp: AgentClangCppToolchainContext.fromSnapshot(
        snapshot,
        preference: clangCppVersionPreference,
      ),
    );
  }

  final List<AgentToolchainEntryContext> entries;
  final AgentToolchainEntryContext? activeCompiler;
  final AgentClangCppToolchainContext? clangCpp;

  int get entryCount => entries.length;
  bool get hasNativeCompiler =>
      activeCompiler?.metadata['defaultForNativeCode'] == true;
  AgentNativeToolchainSummaryContext get nativeTools {
    return AgentNativeToolchainSummaryContext.fromEntries(entries);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'entryCount': entryCount,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      'hasNativeCompiler': hasNativeCompiler,
      if (activeCompiler != null) 'activeCompiler': activeCompiler!.toJson(),
      if (clangCpp != null) 'clangCpp': clangCpp!.toJson(),
      'nativeTools': nativeTools.toJson(),
    };
  }
}

class AgentClangCppToolchainContext {
  const AgentClangCppToolchainContext({
    required this.candidates,
    required this.defaultCppStandard,
    required this.cmakeAvailable,
    required this.ninjaAvailable,
    required this.preferenceStatus,
    this.activeVersionId,
    this.requestedVersionId,
    this.preferenceMessage,
    this.cmakeToolchainId,
    this.cmakeExecutablePath,
    this.ninjaToolchainId,
    this.ninjaExecutablePath,
    this.selection,
  });

  static AgentClangCppToolchainContext? fromSnapshot(
    ToolchainStateSnapshot snapshot, {
    ClangCppVersionPreference? preference,
  }) {
    final manager = ClangCppVersionManager.fromSnapshot(
      snapshot,
      preference: preference,
    );
    if (!manager.hasCandidates) {
      return null;
    }
    return AgentClangCppToolchainContext(
      candidates: manager.candidates,
      activeVersionId: manager.activeVersionId,
      requestedVersionId: manager.requestedVersionId,
      defaultCppStandard: manager.defaultCppStandard,
      cmakeAvailable: manager.cmakeAvailable,
      ninjaAvailable: manager.ninjaAvailable,
      preferenceStatus: manager.preferenceStatus,
      preferenceMessage: manager.preferenceMessage,
      cmakeToolchainId: manager.cmakeToolchainId,
      cmakeExecutablePath: manager.cmakeExecutablePath,
      ninjaToolchainId: manager.ninjaToolchainId,
      ninjaExecutablePath: manager.ninjaExecutablePath,
      selection: manager.select(),
    );
  }

  final List<ClangCppVersionCandidate> candidates;
  final String? activeVersionId;
  final String? requestedVersionId;
  final CppLanguageStandard defaultCppStandard;
  final bool cmakeAvailable;
  final bool ninjaAvailable;
  final ClangCppVersionPreferenceStatus preferenceStatus;
  final String? preferenceMessage;
  final String? cmakeToolchainId;
  final String? cmakeExecutablePath;
  final String? ninjaToolchainId;
  final String? ninjaExecutablePath;
  final ClangCppVersionSelection? selection;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'candidateCount': candidates.length,
      'candidates': candidates
          .map((candidate) => candidate.toManifest())
          .toList(growable: false),
      if (activeVersionId != null) 'activeVersionId': activeVersionId,
      if (requestedVersionId != null) 'requestedVersionId': requestedVersionId,
      'preferenceStatus': preferenceStatus.name,
      if (preferenceMessage != null) 'preferenceMessage': preferenceMessage,
      'defaultCppStandard': <String, Object?>{
        'cmakeValue': defaultCppStandard.cmakeValue,
        'compilerFlag': defaultCppStandard.compilerFlag,
      },
      'cmakeAvailable': cmakeAvailable,
      if (cmakeToolchainId != null) 'cmakeToolchainId': cmakeToolchainId,
      if (cmakeExecutablePath != null)
        'cmakeExecutablePath': cmakeExecutablePath,
      'ninjaAvailable': ninjaAvailable,
      if (ninjaToolchainId != null) 'ninjaToolchainId': ninjaToolchainId,
      if (ninjaExecutablePath != null)
        'ninjaExecutablePath': ninjaExecutablePath,
      if (selection != null) 'selection': selection!.toManifest(),
    };
  }
}

class AgentNativeToolchainSummaryContext {
  const AgentNativeToolchainSummaryContext({
    required this.buildTools,
    required this.debuggers,
    required this.formatters,
    required this.staticAnalyzers,
    required this.testRunners,
    required this.languageServices,
  });

  factory AgentNativeToolchainSummaryContext.fromEntries(
    Iterable<AgentToolchainEntryContext> entries,
  ) {
    final buildTools = <AgentToolchainEntryContext>[];
    final debuggers = <AgentToolchainEntryContext>[];
    final formatters = <AgentToolchainEntryContext>[];
    final staticAnalyzers = <AgentToolchainEntryContext>[];
    final testRunners = <AgentToolchainEntryContext>[];
    final languageServices = <AgentToolchainEntryContext>[];
    for (final entry in entries) {
      if (entry.kind == 'build-tool') {
        buildTools.add(entry);
      } else if (entry.kind == 'debugger') {
        debuggers.add(entry);
      } else if (entry.kind == 'formatter') {
        formatters.add(entry);
      } else if (entry.kind == 'static-analyzer') {
        staticAnalyzers.add(entry);
      } else if (entry.kind == 'test-runner') {
        testRunners.add(entry);
      } else if (entry.kind == 'language-service' &&
          entry.metadata['toolRole'] == 'native-language-service') {
        languageServices.add(entry);
      }
    }
    return AgentNativeToolchainSummaryContext(
      buildTools: List<AgentToolchainEntryContext>.unmodifiable(buildTools),
      debuggers: List<AgentToolchainEntryContext>.unmodifiable(debuggers),
      formatters: List<AgentToolchainEntryContext>.unmodifiable(formatters),
      staticAnalyzers: List<AgentToolchainEntryContext>.unmodifiable(
        staticAnalyzers,
      ),
      testRunners: List<AgentToolchainEntryContext>.unmodifiable(testRunners),
      languageServices: List<AgentToolchainEntryContext>.unmodifiable(
        languageServices,
      ),
    );
  }

  final List<AgentToolchainEntryContext> buildTools;
  final List<AgentToolchainEntryContext> debuggers;
  final List<AgentToolchainEntryContext> formatters;
  final List<AgentToolchainEntryContext> staticAnalyzers;
  final List<AgentToolchainEntryContext> testRunners;
  final List<AgentToolchainEntryContext> languageServices;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'buildToolCount': buildTools.length,
      'debuggerCount': debuggers.length,
      'formatterCount': formatters.length,
      'staticAnalyzerCount': staticAnalyzers.length,
      'testRunnerCount': testRunners.length,
      'languageServiceCount': languageServices.length,
      'hasBuildTool': buildTools.isNotEmpty,
      'hasDebugger': debuggers.isNotEmpty,
      'hasFormatter': formatters.isNotEmpty,
      'hasStaticAnalyzer': staticAnalyzers.isNotEmpty,
      'hasTestRunner': testRunners.isNotEmpty,
      'hasLanguageService': languageServices.isNotEmpty,
      'buildTools': buildTools
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'debuggers': debuggers
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'formatters': formatters
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'staticAnalyzers': staticAnalyzers
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'testRunners': testRunners
          .map((entry) => entry.toJson())
          .toList(growable: false),
      'languageServices': languageServices
          .map((entry) => entry.toJson())
          .toList(growable: false),
    };
  }
}

class AgentToolchainEntryContext {
  const AgentToolchainEntryContext({
    required this.id,
    required this.kind,
    required this.displayName,
    required this.executablePath,
    required this.active,
    required this.metadata,
    this.version,
    this.channel,
  });

  factory AgentToolchainEntryContext.fromStateEntry(ToolchainStateEntry entry) {
    return AgentToolchainEntryContext(
      id: entry.id,
      kind: entry.kind.wireValue,
      displayName: entry.displayName,
      executablePath: entry.executablePath,
      active: entry.active,
      version: entry.version,
      channel: entry.channel,
      metadata: Map<String, Object?>.unmodifiable(entry.metadata),
    );
  }

  final String id;
  final String kind;
  final String displayName;
  final String executablePath;
  final bool active;
  final String? version;
  final String? channel;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind,
      'displayName': displayName,
      'executablePath': executablePath,
      'active': active,
      if (version != null) 'version': version,
      if (channel != null) 'channel': channel,
      'metadata': metadata,
    };
  }
}

class AgentLanguageContext {
  const AgentLanguageContext({
    required this.hasHover,
    this.hoverMarkdown,
    this.hoverStart,
    this.hoverEnd,
    this.hoverRange,
    this.definition,
    this.resolvedElement,
    this.resolvedReference,
    this.parameterInfo,
    this.focusToken,
    required this.focusedDiagnosticCount,
    required this.focusedDiagnostics,
    required this.focusedDiagnosticsTruncated,
    required this.referenceCount,
    required this.references,
    required this.referencesTruncated,
    required this.completionCount,
    required this.completions,
    required this.completionsTruncated,
    required this.codeActionCount,
    required this.codeActions,
    required this.codeActionsTruncated,
    required this.semanticSpanCount,
    required this.semanticSpans,
    required this.semanticSpansTruncated,
    required this.documentSymbolCount,
    required this.documentSymbols,
    required this.documentSymbolsTruncated,
    required this.inlayHintCount,
    required this.inlayHints,
    required this.inlayHintsTruncated,
    required this.semanticBlockCount,
    required this.semanticBlocks,
    required this.semanticBlocksTruncated,
    required this.refactorPreviewCount,
    required this.refactorPreviews,
    required this.semanticPanelViewModelCount,
    required this.semanticPanelViewModels,
    required this.semanticPanelViewModelsTruncated,
    required this.surroundTemplateCount,
    required this.surroundTemplates,
    required this.surroundTemplatesTruncated,
    this.serviceStatus,
  });

  final bool hasHover;
  final String? hoverMarkdown;
  final int? hoverStart;
  final int? hoverEnd;
  final AgentSourceRangeContext? hoverRange;
  final AgentDefinitionContext? definition;
  final AgentResolvedElementContext? resolvedElement;
  final AgentResolvedReferenceContext? resolvedReference;
  final AgentParameterInfoContext? parameterInfo;
  final AgentFocusTokenContext? focusToken;
  final int focusedDiagnosticCount;
  final List<AgentDiagnosticContext> focusedDiagnostics;
  final bool focusedDiagnosticsTruncated;
  final int referenceCount;
  final List<AgentReferenceContext> references;
  final bool referencesTruncated;
  final int completionCount;
  final List<AgentCompletionContext> completions;
  final bool completionsTruncated;
  final int codeActionCount;
  final List<AgentCodeActionContext> codeActions;
  final bool codeActionsTruncated;
  final int semanticSpanCount;
  final List<AgentSemanticSpanContext> semanticSpans;
  final bool semanticSpansTruncated;
  final int documentSymbolCount;
  final List<AgentDocumentSymbolContext> documentSymbols;
  final bool documentSymbolsTruncated;
  final int inlayHintCount;
  final List<AgentInlayHintContext> inlayHints;
  final bool inlayHintsTruncated;
  final int semanticBlockCount;
  final List<AgentSemanticBlockContext> semanticBlocks;
  final bool semanticBlocksTruncated;
  final int refactorPreviewCount;
  final List<AgentRefactorPreviewContext> refactorPreviews;
  final int semanticPanelViewModelCount;
  final List<AgentSemanticPanelViewModelContext> semanticPanelViewModels;
  final bool semanticPanelViewModelsTruncated;
  final int surroundTemplateCount;
  final List<AgentSurroundTemplateContext> surroundTemplates;
  final bool surroundTemplatesTruncated;
  final AgentLanguageServiceStatusContext? serviceStatus;

  factory AgentLanguageContext.fromSelection({
    required DocumentState document,
    HoverPayload? hover,
    DefinitionTarget? definition,
    ResolvedElement? resolvedElement,
    ResolvedReference? resolvedReference,
    ParameterInfoPayload? parameterInfo,
    SafeDeletePlan? safeDeletePlan,
    InlineVariablePlan? inlineVariablePlan,
    TokenSpan? focusToken,
    SemanticKind? focusSemanticKind,
    Iterable<SurroundTemplate> surroundTemplates = const <SurroundTemplate>[],
    Iterable<Diagnostic> focusedDiagnostics = const <Diagnostic>[],
    Iterable<ReferenceSpan> references = const <ReferenceSpan>[],
    Iterable<CompletionItem> completions = const <CompletionItem>[],
    Iterable<DiagnosticQuickFix> codeActions = const <DiagnosticQuickFix>[],
    Iterable<SemanticSpan> semanticSpans = const <SemanticSpan>[],
    Iterable<DocumentSymbol> documentSymbols = const <DocumentSymbol>[],
    Iterable<InlayHint> inlayHints = const <InlayHint>[],
    Iterable<SemanticBlockRange> semanticBlocks = const <SemanticBlockRange>[],
    Iterable<SemanticSnapshotPanelViewModel> semanticPanelViewModels =
        const <SemanticSnapshotPanelViewModel>[],
    AgentLanguageServiceStatusContext? serviceStatus,
    int maxReferences = 50,
    int maxFocusedDiagnostics = 20,
    int maxCompletions = 50,
    int maxCodeActions = 50,
    int maxSemanticSpans = 80,
    int maxDocumentSymbols = 120,
    int maxInlayHints = 120,
    int maxSemanticBlocks = 120,
    int maxSemanticPanelViewModels = 12,
    int maxSurroundTemplates = 24,
  }) {
    final surroundTemplateList = surroundTemplates.toList(growable: false);
    final focusedDiagnosticList = focusedDiagnostics.toList(growable: false);
    final referenceList = references.toList(growable: false);
    final completionList = completions.toList(growable: false);
    final codeActionList = codeActions.toList(growable: false);
    final semanticSpanList = semanticSpans.toList(growable: false);
    final documentSymbolList = documentSymbols.toList(growable: false);
    final inlayHintList = inlayHints.toList(growable: false);
    final semanticBlockList = semanticBlocks.toList(growable: false);
    final semanticPanelViewModelList = semanticPanelViewModels.toList(
      growable: false,
    );
    final refactorPreviewList = <AgentRefactorPreviewContext>[
      if (safeDeletePlan != null)
        AgentRefactorPreviewContext.fromSafeDeletePlan(
          safeDeletePlan,
          document: document,
        ),
      if (inlineVariablePlan != null)
        AgentRefactorPreviewContext.fromInlineVariablePlan(
          inlineVariablePlan,
          document: document,
        ),
    ];
    return AgentLanguageContext(
      hasHover: hover != null,
      hoverMarkdown: hover?.markdown,
      hoverStart: hover?.range.start,
      hoverEnd: hover?.range.end,
      hoverRange: hover == null
          ? null
          : AgentSourceRangeContext.fromOffsets(
              document: document,
              start: hover.range.start,
              end: hover.range.end,
            ),
      definition: definition == null
          ? null
          : AgentDefinitionContext.fromDefinitionTarget(
              definition,
              document: document,
            ),
      resolvedElement: resolvedElement == null
          ? null
          : AgentResolvedElementContext.fromResolvedElement(
              resolvedElement,
              document: document,
            ),
      resolvedReference: resolvedReference == null
          ? null
          : AgentResolvedReferenceContext.fromResolvedReference(
              resolvedReference,
              document: document,
            ),
      parameterInfo: parameterInfo == null
          ? null
          : AgentParameterInfoContext.fromParameterInfoPayload(
              parameterInfo,
              document: document,
            ),
      focusToken: focusToken == null
          ? null
          : AgentFocusTokenContext.fromTokenSpan(
              focusToken,
              document: document,
              semanticKind: focusSemanticKind,
            ),
      focusedDiagnosticCount: focusedDiagnosticList.length,
      focusedDiagnostics: focusedDiagnosticList
          .take(maxFocusedDiagnostics)
          .map(
            (diagnostic) => AgentDiagnosticContext.fromDiagnostic(
              diagnostic,
              document: document,
            ),
          )
          .toList(growable: false),
      focusedDiagnosticsTruncated:
          focusedDiagnosticList.length > maxFocusedDiagnostics,
      referenceCount: referenceList.length,
      references: referenceList
          .take(maxReferences)
          .map(
            (reference) => AgentReferenceContext.fromReferenceSpan(
              reference,
              document: document,
            ),
          )
          .toList(growable: false),
      referencesTruncated: referenceList.length > maxReferences,
      completionCount: completionList.length,
      completions: completionList
          .take(maxCompletions)
          .map(
            (completion) => AgentCompletionContext.fromCompletionItem(
              completion,
              document: document,
            ),
          )
          .toList(growable: false),
      completionsTruncated: completionList.length > maxCompletions,
      codeActionCount: codeActionList.length,
      codeActions: codeActionList
          .take(maxCodeActions)
          .map(
            (action) => AgentCodeActionContext.fromDiagnosticQuickFix(
              action,
              document: document,
            ),
          )
          .toList(growable: false),
      codeActionsTruncated: codeActionList.length > maxCodeActions,
      semanticSpanCount: semanticSpanList.length,
      semanticSpans: semanticSpanList
          .take(maxSemanticSpans)
          .map(
            (span) => AgentSemanticSpanContext.fromSemanticSpan(
              span,
              document: document,
            ),
          )
          .toList(growable: false),
      semanticSpansTruncated: semanticSpanList.length > maxSemanticSpans,
      documentSymbolCount: documentSymbolList.length,
      documentSymbols: documentSymbolList
          .take(maxDocumentSymbols)
          .map(
            (symbol) => AgentDocumentSymbolContext.fromDocumentSymbol(
              symbol,
              document: document,
            ),
          )
          .toList(growable: false),
      documentSymbolsTruncated: documentSymbolList.length > maxDocumentSymbols,
      inlayHintCount: inlayHintList.length,
      inlayHints: inlayHintList
          .take(maxInlayHints)
          .map(
            (hint) =>
                AgentInlayHintContext.fromInlayHint(hint, document: document),
          )
          .toList(growable: false),
      inlayHintsTruncated: inlayHintList.length > maxInlayHints,
      semanticBlockCount: semanticBlockList.length,
      semanticBlocks: semanticBlockList
          .take(maxSemanticBlocks)
          .map(
            (block) => AgentSemanticBlockContext.fromSemanticBlockRange(
              block,
              document: document,
            ),
          )
          .toList(growable: false),
      semanticBlocksTruncated: semanticBlockList.length > maxSemanticBlocks,
      refactorPreviewCount: refactorPreviewList.length,
      refactorPreviews: refactorPreviewList,
      semanticPanelViewModelCount: semanticPanelViewModelList.length,
      semanticPanelViewModels: semanticPanelViewModelList
          .take(maxSemanticPanelViewModels)
          .map(AgentSemanticPanelViewModelContext.fromViewModel)
          .toList(growable: false),
      semanticPanelViewModelsTruncated:
          semanticPanelViewModelList.length > maxSemanticPanelViewModels,
      surroundTemplateCount: surroundTemplateList.length,
      surroundTemplates: surroundTemplateList
          .take(maxSurroundTemplates)
          .map(AgentSurroundTemplateContext.fromSurroundTemplate)
          .toList(growable: false),
      surroundTemplatesTruncated:
          surroundTemplateList.length > maxSurroundTemplates,
      serviceStatus: serviceStatus,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'hasHover': hasHover,
      if (hoverMarkdown != null) 'hoverMarkdown': hoverMarkdown,
      if (hoverStart != null) 'hoverStart': hoverStart,
      if (hoverEnd != null) 'hoverEnd': hoverEnd,
      if (hoverRange != null) 'hoverRange': hoverRange!.toJson(),
      if (definition != null) 'definition': definition!.toJson(),
      if (resolvedElement != null) 'resolvedElement': resolvedElement!.toJson(),
      if (resolvedReference != null)
        'resolvedReference': resolvedReference!.toJson(),
      if (parameterInfo != null) 'parameterInfo': parameterInfo!.toJson(),
      if (focusToken != null) 'focusToken': focusToken!.toJson(),
      'focusedDiagnosticCount': focusedDiagnosticCount,
      'focusedDiagnostics': focusedDiagnostics
          .map((diagnostic) => diagnostic.toJson())
          .toList(growable: false),
      'focusedDiagnosticsTruncated': focusedDiagnosticsTruncated,
      'referenceCount': referenceCount,
      'references': references
          .map((reference) => reference.toJson())
          .toList(growable: false),
      'referencesTruncated': referencesTruncated,
      'completionCount': completionCount,
      'completions': completions
          .map((completion) => completion.toJson())
          .toList(growable: false),
      'completionsTruncated': completionsTruncated,
      'codeActionCount': codeActionCount,
      'codeActions': codeActions
          .map((action) => action.toJson())
          .toList(growable: false),
      'codeActionsTruncated': codeActionsTruncated,
      'semanticSpanCount': semanticSpanCount,
      'semanticSpans': semanticSpans
          .map((span) => span.toJson())
          .toList(growable: false),
      'semanticSpansTruncated': semanticSpansTruncated,
      'documentSymbolCount': documentSymbolCount,
      'documentSymbols': documentSymbols
          .map((symbol) => symbol.toJson())
          .toList(growable: false),
      'documentSymbolsTruncated': documentSymbolsTruncated,
      'inlayHintCount': inlayHintCount,
      'inlayHints': inlayHints
          .map((hint) => hint.toJson())
          .toList(growable: false),
      'inlayHintsTruncated': inlayHintsTruncated,
      'semanticBlockCount': semanticBlockCount,
      'semanticBlocks': semanticBlocks
          .map((block) => block.toJson())
          .toList(growable: false),
      'semanticBlocksTruncated': semanticBlocksTruncated,
      'refactorPreviewCount': refactorPreviewCount,
      'refactorPreviews': refactorPreviews
          .map((preview) => preview.toJson())
          .toList(growable: false),
      'semanticPanelViewModelCount': semanticPanelViewModelCount,
      'semanticPanelViewModels': semanticPanelViewModels
          .map((model) => model.toJson())
          .toList(growable: false),
      'semanticPanelViewModelsTruncated': semanticPanelViewModelsTruncated,
      'surroundTemplateCount': surroundTemplateCount,
      'surroundTemplates': surroundTemplates
          .map((template) => template.toJson())
          .toList(growable: false),
      'surroundTemplatesTruncated': surroundTemplatesTruncated,
      if (serviceStatus != null) 'serviceStatus': serviceStatus!.toJson(),
    };
  }
}

class AgentSemanticPanelViewModelContext {
  const AgentSemanticPanelViewModelContext({
    required this.target,
    required this.title,
    required this.revision,
    required this.itemCount,
    required this.codeActionCount,
    required this.renameSafetyCount,
    required this.items,
    required this.itemsTruncated,
  });

  factory AgentSemanticPanelViewModelContext.fromViewModel(
    SemanticSnapshotPanelViewModel model, {
    int maxItems = 12,
  }) {
    return AgentSemanticPanelViewModelContext(
      target: model.target.wireValue,
      title: model.title,
      revision: model.revision,
      itemCount: model.itemCount,
      codeActionCount: model.codeActionCount,
      renameSafetyCount: model.renameSafetyCount,
      items: model.items
          .take(maxItems)
          .map(AgentSemanticPanelViewItemContext.fromItem)
          .toList(growable: false),
      itemsTruncated: model.items.length > maxItems,
    );
  }

  final String target;
  final String title;
  final int revision;
  final int itemCount;
  final int codeActionCount;
  final int renameSafetyCount;
  final List<AgentSemanticPanelViewItemContext> items;
  final bool itemsTruncated;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'target': target,
      'title': title,
      'revision': revision,
      'itemCount': itemCount,
      'codeActionCount': codeActionCount,
      'renameSafetyCount': renameSafetyCount,
      'items': items.map((item) => item.toJson()).toList(growable: false),
      'itemsTruncated': itemsTruncated,
    };
  }
}

class AgentSemanticPanelViewItemContext {
  const AgentSemanticPanelViewItemContext({
    required this.id,
    required this.kind,
    required this.documentId,
    required this.title,
    required this.message,
    required this.severity,
    required this.actionLabel,
  });

  factory AgentSemanticPanelViewItemContext.fromItem(
    SemanticSnapshotPanelEventViewItem item,
  ) {
    return AgentSemanticPanelViewItemContext(
      id: item.id,
      kind: item.kind.wireValue,
      documentId: item.documentId,
      title: item.title,
      message: item.message,
      severity: item.severity,
      actionLabel: item.actionLabel,
    );
  }

  final String id;
  final String kind;
  final String documentId;
  final String title;
  final String message;
  final String severity;
  final String actionLabel;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'kind': kind,
      'documentId': documentId,
      'title': title,
      'message': message,
      'severity': severity,
      if (actionLabel.isNotEmpty) 'actionLabel': actionLabel,
    };
  }
}

class AgentParameterInfoContext {
  const AgentParameterInfoContext({
    required this.callableName,
    required this.signature,
    required this.documentation,
    required this.activeParameterIndex,
    required this.invocationStart,
    required this.invocationEnd,
    required this.callableStart,
    required this.callableEnd,
    required this.invocationRange,
    required this.callableRange,
    required this.parameterCount,
    required this.parameters,
    required this.parametersTruncated,
    this.activeParameter,
  });

  final String callableName;
  final String signature;
  final String documentation;
  final int activeParameterIndex;
  final int invocationStart;
  final int invocationEnd;
  final int callableStart;
  final int callableEnd;
  final AgentSourceRangeContext invocationRange;
  final AgentSourceRangeContext callableRange;
  final int parameterCount;
  final List<AgentParameterInfoParameterContext> parameters;
  final bool parametersTruncated;
  final AgentParameterInfoParameterContext? activeParameter;

  factory AgentParameterInfoContext.fromParameterInfoPayload(
    ParameterInfoPayload payload, {
    required DocumentState document,
    int maxParameters = 24,
  }) {
    final activeParameter = payload.activeParameter;
    return AgentParameterInfoContext(
      callableName: payload.callableName,
      signature: payload.signature,
      documentation: payload.documentation,
      activeParameterIndex: payload.activeParameterIndex,
      invocationStart: payload.invocationRange.start,
      invocationEnd: payload.invocationRange.end,
      callableStart: payload.callableRange.start,
      callableEnd: payload.callableRange.end,
      invocationRange: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: payload.invocationRange.start,
        end: payload.invocationRange.end,
      ),
      callableRange: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: payload.callableRange.start,
        end: payload.callableRange.end,
      ),
      parameterCount: payload.parameters.length,
      parameters: payload.parameters
          .take(maxParameters)
          .map(
            (parameter) =>
                AgentParameterInfoParameterContext.fromParameterInfoParameter(
                  parameter,
                  document: document,
                ),
          )
          .toList(growable: false),
      parametersTruncated: payload.parameters.length > maxParameters,
      activeParameter: activeParameter == null
          ? null
          : AgentParameterInfoParameterContext.fromParameterInfoParameter(
              activeParameter,
              document: document,
            ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'callableName': callableName,
      'signature': signature,
      if (documentation.isNotEmpty) 'documentation': documentation,
      'activeParameterIndex': activeParameterIndex,
      'invocationStart': invocationStart,
      'invocationEnd': invocationEnd,
      'callableStart': callableStart,
      'callableEnd': callableEnd,
      'invocationRange': invocationRange.toJson(),
      'callableRange': callableRange.toJson(),
      'parameterCount': parameterCount,
      'parameters': parameters
          .map((parameter) => parameter.toJson())
          .toList(growable: false),
      'parametersTruncated': parametersTruncated,
      if (activeParameter != null) 'activeParameter': activeParameter!.toJson(),
    };
  }
}

class AgentParameterInfoParameterContext {
  const AgentParameterInfoParameterContext({
    required this.name,
    required this.start,
    required this.end,
    required this.range,
    required this.type,
    required this.defaultValue,
    required this.documentation,
    required this.displayText,
  });

  final String name;
  final int start;
  final int end;
  final AgentSourceRangeContext range;
  final String type;
  final String defaultValue;
  final String documentation;
  final String displayText;

  factory AgentParameterInfoParameterContext.fromParameterInfoParameter(
    ParameterInfoParameter parameter, {
    required DocumentState document,
  }) {
    return AgentParameterInfoParameterContext(
      name: parameter.name,
      start: parameter.range.start,
      end: parameter.range.end,
      range: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: parameter.range.start,
        end: parameter.range.end,
      ),
      type: parameter.type,
      defaultValue: parameter.defaultValue,
      documentation: parameter.documentation,
      displayText: parameter.displayText,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'start': start,
      'end': end,
      'range': range.toJson(),
      if (type.isNotEmpty) 'type': type,
      if (defaultValue.isNotEmpty) 'defaultValue': defaultValue,
      if (documentation.isNotEmpty) 'documentation': documentation,
      'displayText': displayText,
    };
  }
}

class AgentFocusTokenContext {
  const AgentFocusTokenContext({
    required this.lexeme,
    required this.kind,
    required this.start,
    required this.end,
    required this.range,
    this.semanticKind,
  });

  final String lexeme;
  final String kind;
  final int start;
  final int end;
  final AgentSourceRangeContext range;
  final String? semanticKind;

  factory AgentFocusTokenContext.fromTokenSpan(
    TokenSpan token, {
    required DocumentState document,
    SemanticKind? semanticKind,
  }) {
    return AgentFocusTokenContext(
      lexeme: token.lexeme,
      kind: token.kind.name,
      start: token.range.start,
      end: token.range.end,
      range: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: token.range.start,
        end: token.range.end,
      ),
      semanticKind: semanticKind?.name,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'lexeme': lexeme,
      'kind': kind,
      'start': start,
      'end': end,
      'range': range.toJson(),
      if (semanticKind != null) 'semanticKind': semanticKind,
    };
  }
}

class AgentSemanticSpanContext {
  const AgentSemanticSpanContext({
    required this.kind,
    required this.start,
    required this.end,
    required this.range,
    required this.modifiers,
  });

  final String kind;
  final int start;
  final int end;
  final AgentSourceRangeContext range;
  final List<String> modifiers;

  factory AgentSemanticSpanContext.fromSemanticSpan(
    SemanticSpan span, {
    required DocumentState document,
  }) {
    return AgentSemanticSpanContext(
      kind: span.kind.name,
      start: span.range.start,
      end: span.range.end,
      range: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: span.range.start,
        end: span.range.end,
      ),
      modifiers: span.modifiers,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind,
      'start': start,
      'end': end,
      'range': range.toJson(),
      if (modifiers.isNotEmpty) 'modifiers': modifiers,
    };
  }
}

class AgentSourceRangeContext {
  const AgentSourceRangeContext({
    required this.start,
    required this.end,
    required this.coordinateBase,
    required this.startLine,
    required this.startColumn,
    required this.endLine,
    required this.endColumn,
  });

  final int start;
  final int end;
  final String coordinateBase;
  final int startLine;
  final int startColumn;
  final int endLine;
  final int endColumn;

  factory AgentSourceRangeContext.fromOffsets({
    required DocumentState document,
    required int start,
    required int end,
  }) {
    final startPosition = document.positionForOffset(
      _clampOffset(start, document.length),
    );
    final endPosition = document.positionForOffset(
      _clampOffset(end, document.length),
    );
    return AgentSourceRangeContext(
      start: start,
      end: end,
      coordinateBase: 'zero-based',
      startLine: startPosition.line,
      startColumn: startPosition.column,
      endLine: endPosition.line,
      endColumn: endPosition.column,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'start': start,
      'end': end,
      'coordinateBase': coordinateBase,
      'startLine': startLine,
      'startColumn': startColumn,
      'endLine': endLine,
      'endColumn': endColumn,
    };
  }
}

class AgentDocumentSymbolContext {
  const AgentDocumentSymbolContext({
    required this.name,
    required this.kind,
    required this.nameStart,
    required this.nameEnd,
    required this.declarationStart,
    required this.declarationEnd,
    required this.nameRange,
    required this.declarationRange,
    required this.detail,
    required this.documentation,
  });

  final String name;
  final String kind;
  final int nameStart;
  final int nameEnd;
  final int declarationStart;
  final int declarationEnd;
  final AgentSourceRangeContext nameRange;
  final AgentSourceRangeContext declarationRange;
  final String detail;
  final String documentation;

  factory AgentDocumentSymbolContext.fromDocumentSymbol(
    DocumentSymbol symbol, {
    required DocumentState document,
  }) {
    return AgentDocumentSymbolContext(
      name: symbol.name,
      kind: symbol.kind.name,
      nameStart: symbol.nameRange.start,
      nameEnd: symbol.nameRange.end,
      declarationStart: symbol.declarationRange.start,
      declarationEnd: symbol.declarationRange.end,
      nameRange: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: symbol.nameRange.start,
        end: symbol.nameRange.end,
      ),
      declarationRange: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: symbol.declarationRange.start,
        end: symbol.declarationRange.end,
      ),
      detail: symbol.detail,
      documentation: symbol.documentation,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'kind': kind,
      'nameStart': nameStart,
      'nameEnd': nameEnd,
      'declarationStart': declarationStart,
      'declarationEnd': declarationEnd,
      'nameRange': nameRange.toJson(),
      'declarationRange': declarationRange.toJson(),
      if (detail.isNotEmpty) 'detail': detail,
      if (documentation.isNotEmpty) 'documentation': documentation,
    };
  }
}

class AgentInlayHintContext {
  const AgentInlayHintContext({
    required this.label,
    required this.kind,
    required this.position,
    required this.positionLine,
    required this.positionColumn,
    required this.start,
    required this.end,
    required this.range,
  });

  final String label;
  final String kind;
  final int position;
  final int positionLine;
  final int positionColumn;
  final int start;
  final int end;
  final AgentSourceRangeContext range;

  factory AgentInlayHintContext.fromInlayHint(
    InlayHint hint, {
    required DocumentState document,
  }) {
    final position = document.positionForOffset(
      _clampOffset(hint.position, document.length),
    );
    return AgentInlayHintContext(
      label: hint.label,
      kind: hint.kind.name,
      position: hint.position,
      positionLine: position.line,
      positionColumn: position.column,
      start: hint.range.start,
      end: hint.range.end,
      range: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: hint.range.start,
        end: hint.range.end,
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      'kind': kind,
      'position': position,
      'positionLine': positionLine,
      'positionColumn': positionColumn,
      'start': start,
      'end': end,
      'range': range.toJson(),
    };
  }
}

class AgentSemanticBlockContext {
  const AgentSemanticBlockContext({
    required this.label,
    required this.start,
    required this.end,
    required this.range,
  });

  final String label;
  final int start;
  final int end;
  final AgentSourceRangeContext range;

  factory AgentSemanticBlockContext.fromSemanticBlockRange(
    SemanticBlockRange block, {
    required DocumentState document,
  }) {
    return AgentSemanticBlockContext(
      label: block.label,
      start: block.range.start,
      end: block.range.end,
      range: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: block.range.start,
        end: block.range.end,
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      'start': start,
      'end': end,
      'range': range.toJson(),
    };
  }
}

class AgentRefactorPreviewContext {
  const AgentRefactorPreviewContext({
    required this.kind,
    required this.target,
    required this.referenceCount,
    required this.references,
    required this.referencesTruncated,
    required this.editCount,
    required this.edits,
    required this.editsTruncated,
    required this.conflictCount,
    required this.conflicts,
    this.initializerStart,
    this.initializerEnd,
    this.initializerText,
  });

  final String kind;
  final AgentDocumentSymbolContext target;
  final int referenceCount;
  final List<AgentReferenceContext> references;
  final bool referencesTruncated;
  final int editCount;
  final List<AgentFormattingEditContext> edits;
  final bool editsTruncated;
  final int conflictCount;
  final List<AgentRefactorConflictContext> conflicts;
  final int? initializerStart;
  final int? initializerEnd;
  final String? initializerText;

  factory AgentRefactorPreviewContext.fromSafeDeletePlan(
    SafeDeletePlan plan, {
    required DocumentState document,
    int maxReferences = 24,
    int maxEdits = 24,
    int maxConflicts = 12,
  }) {
    return AgentRefactorPreviewContext(
      kind: 'safeDelete',
      target: AgentDocumentSymbolContext.fromDocumentSymbol(
        plan.target,
        document: document,
      ),
      referenceCount: plan.references.length,
      references: plan.references
          .take(maxReferences)
          .map(
            (reference) => AgentReferenceContext.fromReferenceSpan(
              reference,
              document: document,
            ),
          )
          .toList(growable: false),
      referencesTruncated: plan.references.length > maxReferences,
      editCount: plan.edits.length,
      edits: plan.edits
          .take(maxEdits)
          .map(
            (edit) => AgentFormattingEditContext.fromFormattingEdit(
              edit,
              document: document,
            ),
          )
          .toList(growable: false),
      editsTruncated: plan.edits.length > maxEdits,
      conflictCount: plan.conflicts.length,
      conflicts: plan.conflicts
          .take(maxConflicts)
          .map(AgentRefactorConflictContext.fromSafeDeleteConflict)
          .toList(growable: false),
    );
  }

  factory AgentRefactorPreviewContext.fromInlineVariablePlan(
    InlineVariablePlan plan, {
    required DocumentState document,
    int maxReferences = 24,
    int maxEdits = 24,
    int maxConflicts = 12,
  }) {
    return AgentRefactorPreviewContext(
      kind: 'inlineVariable',
      target: AgentDocumentSymbolContext.fromDocumentSymbol(
        plan.target,
        document: document,
      ),
      referenceCount: plan.references.length,
      references: plan.references
          .take(maxReferences)
          .map(
            (reference) => AgentReferenceContext.fromReferenceSpan(
              reference,
              document: document,
            ),
          )
          .toList(growable: false),
      referencesTruncated: plan.references.length > maxReferences,
      editCount: plan.edits.length,
      edits: plan.edits
          .take(maxEdits)
          .map(
            (edit) => AgentFormattingEditContext.fromFormattingEdit(
              edit,
              document: document,
            ),
          )
          .toList(growable: false),
      editsTruncated: plan.edits.length > maxEdits,
      conflictCount: plan.conflicts.length,
      conflicts: plan.conflicts
          .take(maxConflicts)
          .map(AgentRefactorConflictContext.fromInlineVariableConflict)
          .toList(growable: false),
      initializerStart: plan.initializerRange.start,
      initializerEnd: plan.initializerRange.end,
      initializerText: plan.initializerText,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind,
      'target': target.toJson(),
      'referenceCount': referenceCount,
      'references': references
          .map((reference) => reference.toJson())
          .toList(growable: false),
      'referencesTruncated': referencesTruncated,
      'editCount': editCount,
      'edits': edits.map((edit) => edit.toJson()).toList(growable: false),
      'editsTruncated': editsTruncated,
      'conflictCount': conflictCount,
      'conflicts': conflicts
          .map((conflict) => conflict.toJson())
          .toList(growable: false),
      if (initializerStart != null) 'initializerStart': initializerStart,
      if (initializerEnd != null) 'initializerEnd': initializerEnd,
      if (initializerText != null) 'initializerText': initializerText,
    };
  }
}

class AgentRefactorConflictContext {
  const AgentRefactorConflictContext({
    required this.message,
    required this.start,
    required this.end,
  });

  final String message;
  final int start;
  final int end;

  factory AgentRefactorConflictContext.fromSafeDeleteConflict(
    SafeDeleteConflict conflict,
  ) {
    return AgentRefactorConflictContext(
      message: conflict.message,
      start: conflict.range.start,
      end: conflict.range.end,
    );
  }

  factory AgentRefactorConflictContext.fromInlineVariableConflict(
    InlineVariableConflict conflict,
  ) {
    return AgentRefactorConflictContext(
      message: conflict.message,
      start: conflict.range.start,
      end: conflict.range.end,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'message': message, 'start': start, 'end': end};
  }
}

class AgentSurroundTemplateContext {
  const AgentSurroundTemplateContext({
    required this.id,
    required this.label,
    required this.openingLine,
    required this.closingLine,
    required this.bodyIndent,
    required this.detail,
  });

  final String id;
  final String label;
  final String openingLine;
  final String closingLine;
  final String bodyIndent;
  final String detail;

  factory AgentSurroundTemplateContext.fromSurroundTemplate(
    SurroundTemplate template,
  ) {
    return AgentSurroundTemplateContext(
      id: template.id,
      label: template.label,
      openingLine: template.openingLine,
      closingLine: template.closingLine,
      bodyIndent: template.bodyIndent,
      detail: template.detail,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'openingLine': openingLine,
      'closingLine': closingLine,
      'bodyIndent': bodyIndent,
      if (detail.isNotEmpty) 'detail': detail,
    };
  }
}

class AgentLanguageServiceStatusContext {
  const AgentLanguageServiceStatusContext({
    required this.runtimeState,
    required this.severity,
    required this.title,
    required this.message,
    required this.usableCapabilityCount,
    required this.freshCapabilityCount,
    required this.primaryCapabilityStates,
    required this.capabilities,
    required this.localFallbackEnabled,
    required this.actionable,
    required this.syntaxValidationReady,
    required this.semanticFactsReady,
    required this.unavailablePrimaryCapabilities,
    this.toolchainId = '',
    this.parserEngine,
    this.grammarVersion,
  });

  final String runtimeState;
  final String severity;
  final String title;
  final String message;
  final String toolchainId;
  final String? parserEngine;
  final String? grammarVersion;
  final int usableCapabilityCount;
  final int freshCapabilityCount;
  final Map<String, String> primaryCapabilityStates;
  final List<AgentLanguageCapabilityStatusContext> capabilities;
  final bool localFallbackEnabled;
  final bool actionable;
  final bool syntaxValidationReady;
  final bool semanticFactsReady;
  final List<String> unavailablePrimaryCapabilities;

  factory AgentLanguageServiceStatusContext.fromSurface(
    LanguageServiceStatusSurface surface,
  ) {
    return AgentLanguageServiceStatusContext(
      runtimeState: surface.runtimeState,
      severity: surface.severity.name,
      title: surface.title,
      message: surface.message,
      toolchainId: surface.toolchainId,
      parserEngine: surface.parserEngine,
      grammarVersion: surface.grammarVersion,
      usableCapabilityCount: surface.usableCapabilityCount,
      freshCapabilityCount: surface.freshCapabilityCount,
      primaryCapabilityStates: Map<String, String>.unmodifiable(
        surface.primaryCapabilityStates,
      ),
      capabilities: surface.capabilities
          .map(AgentLanguageCapabilityStatusContext.fromSurface)
          .toList(growable: false),
      localFallbackEnabled: surface.localFallbackEnabled,
      actionable: surface.actionable,
      syntaxValidationReady: surface.syntaxValidationReady,
      semanticFactsReady: surface.semanticFactsReady,
      unavailablePrimaryCapabilities: surface.unavailablePrimaryCapabilities,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'runtimeState': runtimeState,
      'severity': severity,
      'title': title,
      'message': message,
      if (toolchainId.isNotEmpty) 'toolchainId': toolchainId,
      if (parserEngine != null) 'parserEngine': parserEngine,
      if (grammarVersion != null) 'grammarVersion': grammarVersion,
      'usableCapabilityCount': usableCapabilityCount,
      'freshCapabilityCount': freshCapabilityCount,
      'primaryCapabilityStates': primaryCapabilityStates,
      'capabilities': capabilities
          .map((capability) => capability.toJson())
          .toList(growable: false),
      'localFallbackEnabled': localFallbackEnabled,
      'actionable': actionable,
      'syntaxValidationReady': syntaxValidationReady,
      'semanticFactsReady': semanticFactsReady,
      'unavailablePrimaryCapabilities': unavailablePrimaryCapabilities,
    };
  }
}

class AgentLanguageCapabilityStatusContext {
  const AgentLanguageCapabilityStatusContext({
    required this.capability,
    required this.state,
    required this.usable,
    required this.fresh,
  });

  final String capability;
  final String state;
  final bool usable;
  final bool fresh;

  factory AgentLanguageCapabilityStatusContext.fromSurface(
    LanguageServiceCapabilityStatusItem item,
  ) {
    return AgentLanguageCapabilityStatusContext(
      capability: item.capability,
      state: item.state,
      usable: item.usable,
      fresh: item.fresh,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'capability': capability,
      'state': state,
      'usable': usable,
      'fresh': fresh,
    };
  }
}

class AgentCodeActionContext {
  const AgentCodeActionContext({
    required this.label,
    required this.detail,
    required this.editCount,
    required this.edits,
    required this.editsTruncated,
    this.firstEditStart,
    this.firstEditEnd,
    this.firstEditRange,
  });

  final String label;
  final String detail;
  final int editCount;
  final List<AgentFormattingEditContext> edits;
  final bool editsTruncated;
  final int? firstEditStart;
  final int? firstEditEnd;
  final AgentSourceRangeContext? firstEditRange;

  factory AgentCodeActionContext.fromDiagnosticQuickFix(
    DiagnosticQuickFix action, {
    required DocumentState document,
  }) {
    const maxEdits = 24;
    final firstEdit = action.edits.isEmpty ? null : action.edits.first;
    return AgentCodeActionContext(
      label: action.label,
      detail: action.detail,
      editCount: action.edits.length,
      edits: action.edits
          .take(maxEdits)
          .map(
            (edit) => AgentFormattingEditContext.fromFormattingEdit(
              edit,
              document: document,
            ),
          )
          .toList(growable: false),
      editsTruncated: action.edits.length > maxEdits,
      firstEditStart: firstEdit?.range.start,
      firstEditEnd: firstEdit?.range.end,
      firstEditRange: firstEdit == null
          ? null
          : AgentSourceRangeContext.fromOffsets(
              document: document,
              start: firstEdit.range.start,
              end: firstEdit.range.end,
            ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      'detail': detail,
      'editCount': editCount,
      'edits': edits.map((edit) => edit.toJson()).toList(growable: false),
      'editsTruncated': editsTruncated,
      if (firstEditStart != null) 'firstEditStart': firstEditStart,
      if (firstEditEnd != null) 'firstEditEnd': firstEditEnd,
      if (firstEditRange != null) 'firstEditRange': firstEditRange!.toJson(),
    };
  }
}

class AgentFormattingEditContext {
  const AgentFormattingEditContext({
    required this.start,
    required this.end,
    required this.range,
    required this.newText,
  });

  final int start;
  final int end;
  final AgentSourceRangeContext range;
  final String newText;

  factory AgentFormattingEditContext.fromFormattingEdit(
    FormattingEdit edit, {
    required DocumentState document,
  }) {
    return AgentFormattingEditContext(
      start: edit.range.start,
      end: edit.range.end,
      range: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: edit.range.start,
        end: edit.range.end,
      ),
      newText: edit.newText,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'start': start,
      'end': end,
      'range': range.toJson(),
      'newText': newText,
    };
  }
}

class AgentCompletionContext {
  const AgentCompletionContext({
    required this.label,
    required this.kind,
    required this.insertText,
    required this.detail,
    required this.documentation,
    this.replacementStart,
    this.replacementEnd,
    this.replacementRange,
  });

  final String label;
  final String kind;
  final String insertText;
  final String detail;
  final String documentation;
  final int? replacementStart;
  final int? replacementEnd;
  final AgentSourceRangeContext? replacementRange;

  factory AgentCompletionContext.fromCompletionItem(
    CompletionItem item, {
    required DocumentState document,
  }) {
    return AgentCompletionContext(
      label: item.label,
      kind: item.kind.name,
      insertText: item.insertText,
      detail: item.detail,
      documentation: item.documentation,
      replacementStart: item.replacementRange?.start,
      replacementEnd: item.replacementRange?.end,
      replacementRange: item.replacementRange == null
          ? null
          : AgentSourceRangeContext.fromOffsets(
              document: document,
              start: item.replacementRange!.start,
              end: item.replacementRange!.end,
            ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'label': label,
      'kind': kind,
      'insertText': insertText,
      'detail': detail,
      'documentation': documentation,
      if (replacementStart != null) 'replacementStart': replacementStart,
      if (replacementEnd != null) 'replacementEnd': replacementEnd,
      if (replacementRange != null)
        'replacementRange': replacementRange!.toJson(),
    };
  }
}

class AgentDefinitionContext {
  const AgentDefinitionContext({
    required this.name,
    required this.kind,
    required this.nameStart,
    required this.nameEnd,
    required this.declarationStart,
    required this.declarationEnd,
    required this.originStart,
    required this.originEnd,
    required this.nameRange,
    required this.declarationRange,
    required this.originRange,
    required this.detail,
    required this.documentation,
  });

  final String name;
  final String kind;
  final int nameStart;
  final int nameEnd;
  final int declarationStart;
  final int declarationEnd;
  final int originStart;
  final int originEnd;
  final AgentSourceRangeContext nameRange;
  final AgentSourceRangeContext declarationRange;
  final AgentSourceRangeContext originRange;
  final String detail;
  final String documentation;

  factory AgentDefinitionContext.fromDefinitionTarget(
    DefinitionTarget target, {
    required DocumentState document,
  }) {
    final symbol = target.symbol;
    return AgentDefinitionContext(
      name: symbol.name,
      kind: symbol.kind.name,
      nameStart: symbol.nameRange.start,
      nameEnd: symbol.nameRange.end,
      declarationStart: symbol.declarationRange.start,
      declarationEnd: symbol.declarationRange.end,
      originStart: target.originRange.start,
      originEnd: target.originRange.end,
      nameRange: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: symbol.nameRange.start,
        end: symbol.nameRange.end,
      ),
      declarationRange: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: symbol.declarationRange.start,
        end: symbol.declarationRange.end,
      ),
      originRange: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: target.originRange.start,
        end: target.originRange.end,
      ),
      detail: symbol.detail,
      documentation: symbol.documentation,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'kind': kind,
      'nameStart': nameStart,
      'nameEnd': nameEnd,
      'declarationStart': declarationStart,
      'declarationEnd': declarationEnd,
      'originStart': originStart,
      'originEnd': originEnd,
      'nameRange': nameRange.toJson(),
      'declarationRange': declarationRange.toJson(),
      'originRange': originRange.toJson(),
      'detail': detail,
      'documentation': documentation,
    };
  }
}

class AgentResolvedElementContext {
  const AgentResolvedElementContext({
    required this.name,
    required this.kind,
    required this.nameStart,
    required this.nameEnd,
    required this.declarationStart,
    required this.declarationEnd,
    required this.nameRange,
    required this.declarationRange,
    required this.detail,
    required this.documentation,
  });

  final String name;
  final String kind;
  final int nameStart;
  final int nameEnd;
  final int declarationStart;
  final int declarationEnd;
  final AgentSourceRangeContext nameRange;
  final AgentSourceRangeContext declarationRange;
  final String? detail;
  final String? documentation;

  factory AgentResolvedElementContext.fromResolvedElement(
    ResolvedElement element, {
    required DocumentState document,
  }) {
    return AgentResolvedElementContext(
      name: element.name,
      kind: element.kind.name,
      nameStart: element.nameRange.start,
      nameEnd: element.nameRange.end,
      declarationStart: element.declarationRange.start,
      declarationEnd: element.declarationRange.end,
      nameRange: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: element.nameRange.start,
        end: element.nameRange.end,
      ),
      declarationRange: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: element.declarationRange.start,
        end: element.declarationRange.end,
      ),
      detail: element.detail,
      documentation: element.documentation,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'kind': kind,
      'nameStart': nameStart,
      'nameEnd': nameEnd,
      'declarationStart': declarationStart,
      'declarationEnd': declarationEnd,
      'nameRange': nameRange.toJson(),
      'declarationRange': declarationRange.toJson(),
      if (detail != null) 'detail': detail,
      if (documentation != null) 'documentation': documentation,
    };
  }
}

class AgentResolvedReferenceContext {
  const AgentResolvedReferenceContext({
    required this.name,
    required this.start,
    required this.end,
    required this.range,
    required this.access,
    required this.isDeclaration,
    required this.target,
  });

  final String name;
  final int start;
  final int end;
  final AgentSourceRangeContext range;
  final String access;
  final bool isDeclaration;
  final AgentResolvedElementContext target;

  factory AgentResolvedReferenceContext.fromResolvedReference(
    ResolvedReference reference, {
    required DocumentState document,
  }) {
    return AgentResolvedReferenceContext(
      name: reference.name,
      start: reference.range.start,
      end: reference.range.end,
      range: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: reference.range.start,
        end: reference.range.end,
      ),
      access: reference.access.name,
      isDeclaration: reference.isDeclaration,
      target: AgentResolvedElementContext.fromResolvedElement(
        reference.target,
        document: document,
      ),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'start': start,
      'end': end,
      'range': range.toJson(),
      'access': access,
      'isDeclaration': isDeclaration,
      'target': target.toJson(),
    };
  }
}

class AgentReferenceContext {
  const AgentReferenceContext({
    required this.name,
    required this.kind,
    required this.start,
    required this.end,
    required this.targetStart,
    required this.targetEnd,
    required this.range,
    required this.targetRange,
    required this.isDeclaration,
    required this.access,
  });

  final String name;
  final String kind;
  final int start;
  final int end;
  final int targetStart;
  final int targetEnd;
  final AgentSourceRangeContext range;
  final AgentSourceRangeContext targetRange;
  final bool isDeclaration;
  final String access;

  factory AgentReferenceContext.fromReferenceSpan(
    ReferenceSpan reference, {
    required DocumentState document,
  }) {
    return AgentReferenceContext(
      name: reference.name,
      kind: reference.kind.name,
      start: reference.range.start,
      end: reference.range.end,
      targetStart: reference.targetRange.start,
      targetEnd: reference.targetRange.end,
      range: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: reference.range.start,
        end: reference.range.end,
      ),
      targetRange: AgentSourceRangeContext.fromOffsets(
        document: document,
        start: reference.targetRange.start,
        end: reference.targetRange.end,
      ),
      isDeclaration: reference.isDeclaration,
      access: reference.access.name,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'kind': kind,
      'start': start,
      'end': end,
      'targetStart': targetStart,
      'targetEnd': targetEnd,
      'range': range.toJson(),
      'targetRange': targetRange.toJson(),
      'isDeclaration': isDeclaration,
      'access': access,
    };
  }
}

class AgentCommandCatalogContext {
  const AgentCommandCatalogContext({
    required this.persistenceCommands,
    required this.diagnosticCommands,
    required this.languageServiceCommands,
    required this.sourceControlCommands,
    required this.codingCommands,
    required this.navigationCommands,
    required this.refactorCommands,
    required this.toolchainCommands,
    required this.nativeToolCommands,
    required this.nativeToolCommandReadiness,
    required this.debugCommands,
    required this.debugCommandReadiness,
    required this.settingsCommands,
    this.recentResults = const <AgentCommandResultContext>[],
    this.lastResult,
  });

  final List<AgentCommandContext> persistenceCommands;
  final List<AgentCommandContext> diagnosticCommands;
  final List<AgentCommandContext> languageServiceCommands;
  final List<AgentCommandContext> sourceControlCommands;
  final List<AgentCommandContext> codingCommands;
  final List<AgentCommandContext> navigationCommands;
  final List<AgentCommandContext> refactorCommands;
  final List<AgentCommandContext> toolchainCommands;
  final List<AgentCommandContext> nativeToolCommands;
  final List<AgentNativeToolCommandReadinessContext> nativeToolCommandReadiness;
  final List<AgentCommandContext> debugCommands;
  final List<AgentDebugCommandReadinessContext> debugCommandReadiness;
  final List<AgentCommandContext> settingsCommands;
  final List<AgentCommandResultContext> recentResults;
  final AgentCommandResultContext? lastResult;

  factory AgentCommandCatalogContext.fromRegistry({
    AgentCommandResultContext? lastResult,
    Iterable<AgentCommandResultContext> recentResults =
        const <AgentCommandResultContext>[],
    AgentToolchainContext toolchains = const AgentToolchainContext(
      entries: <AgentToolchainEntryContext>[],
      activeCompiler: null,
    ),
    AgentDebugContext debug = const AgentDebugContext.idle(),
    Iterable<String> dirtyDocumentIds = const <String>[],
    AgentWorkspaceBuildFactsContext? buildFacts,
  }) {
    final nativeToolCommands = StyioCommandRegistry.nativeToolCommands
        .map(AgentCommandContext.fromDescriptor)
        .toList(growable: false);
    final debugCommands = StyioCommandRegistry.debugCommands
        .map(AgentCommandContext.fromDescriptor)
        .toList(growable: false);
    final resultHistory = _agentCommandResultHistory(
      lastResult: lastResult,
      recentResults: recentResults,
    );
    return AgentCommandCatalogContext(
      persistenceCommands: StyioCommandRegistry.persistenceCommands
          .map(AgentCommandContext.fromDescriptor)
          .toList(growable: false),
      diagnosticCommands: StyioCommandRegistry.diagnosticCommands
          .map(AgentCommandContext.fromDescriptor)
          .toList(growable: false),
      languageServiceCommands: StyioCommandRegistry.languageServiceCommands
          .map(AgentCommandContext.fromDescriptor)
          .toList(growable: false),
      sourceControlCommands: StyioCommandRegistry.sourceControlCommands
          .map(AgentCommandContext.fromDescriptor)
          .toList(growable: false),
      codingCommands: StyioCommandRegistry.agentCodingCommands
          .map(AgentCommandContext.fromDescriptor)
          .toList(growable: false),
      navigationCommands: StyioCommandRegistry.navigationCommands
          .map(AgentCommandContext.fromDescriptor)
          .toList(growable: false),
      refactorCommands: StyioCommandRegistry.refactorCommands
          .map(AgentCommandContext.fromDescriptor)
          .toList(growable: false),
      toolchainCommands: StyioCommandRegistry.toolchainCommands
          .map(AgentCommandContext.fromDescriptor)
          .toList(growable: false),
      nativeToolCommands: nativeToolCommands,
      nativeToolCommandReadiness: _nativeToolCommandReadinessFor(
        nativeToolCommands: nativeToolCommands,
        toolchains: toolchains,
        dirtyDocumentIds: dirtyDocumentIds,
        buildFacts: buildFacts,
      ),
      debugCommands: debugCommands,
      debugCommandReadiness: _debugCommandReadinessFor(
        debugCommands: debugCommands,
        debug: debug,
        dirtyDocumentIds: dirtyDocumentIds,
      ),
      settingsCommands: StyioCommandRegistry.settingsCommands
          .map(AgentCommandContext.fromDescriptor)
          .toList(growable: false),
      recentResults: resultHistory,
      lastResult: lastResult,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'persistenceCommands': persistenceCommands
          .map((command) => command.toJson())
          .toList(growable: false),
      'diagnosticCommands': diagnosticCommands
          .map((command) => command.toJson())
          .toList(growable: false),
      'languageServiceCommands': languageServiceCommands
          .map((command) => command.toJson())
          .toList(growable: false),
      'sourceControlCommands': sourceControlCommands
          .map((command) => command.toJson())
          .toList(growable: false),
      'codingCommands': codingCommands
          .map((command) => command.toJson())
          .toList(growable: false),
      'navigationCommands': navigationCommands
          .map((command) => command.toJson())
          .toList(growable: false),
      'refactorCommands': refactorCommands
          .map((command) => command.toJson())
          .toList(growable: false),
      'toolchainCommands': toolchainCommands
          .map((command) => command.toJson())
          .toList(growable: false),
      'nativeToolCommands': nativeToolCommands
          .map((command) => command.toJson())
          .toList(growable: false),
      'nativeToolCommandReadiness': nativeToolCommandReadiness
          .map((readiness) => readiness.toJson())
          .toList(growable: false),
      'debugCommands': debugCommands
          .map((command) => command.toJson())
          .toList(growable: false),
      'debugCommandReadiness': debugCommandReadiness
          .map((readiness) => readiness.toJson())
          .toList(growable: false),
      'settingsCommands': settingsCommands
          .map((command) => command.toJson())
          .toList(growable: false),
      if (recentResults.isNotEmpty)
        'recentResults': recentResults
            .map((result) => result.toJson())
            .toList(growable: false),
      if (lastResult != null) 'lastResult': lastResult!.toJson(),
    };
  }

  int get nativeToolReadyCommandCount {
    return nativeToolCommandReadiness
        .where((readiness) => readiness.ready)
        .length;
  }

  int get nativeToolBlockedCommandCount {
    return nativeToolCommandReadiness.length - nativeToolReadyCommandCount;
  }

  int get debugReadyCommandCount {
    return debugCommandReadiness.where((readiness) => readiness.ready).length;
  }

  int get debugBlockedCommandCount {
    return debugCommandReadiness.length - debugReadyCommandCount;
  }

  static List<AgentNativeToolCommandReadinessContext>
  _nativeToolCommandReadinessFor({
    required List<AgentCommandContext> nativeToolCommands,
    required AgentToolchainContext toolchains,
    required Iterable<String> dirtyDocumentIds,
    AgentWorkspaceBuildFactsContext? buildFacts,
  }) {
    final registeredCommandIds = nativeToolCommands
        .map((command) => command.id)
        .toSet();
    final nativeTools = toolchains.nativeTools;
    final readiness = <AgentNativeToolCommandReadinessContext>[
      AgentNativeToolCommandReadinessContext.fromCandidates(
        commandId: AppCommandId.runBuild.name,
        registered: registeredCommandIds.contains(AppCommandId.runBuild.name),
        requiredKind: ToolchainKind.buildTool,
        requiredToolFamilies: const <String>['cmake', 'ninja'],
        candidates: nativeTools.buildTools,
        requiresCleanWorkspace: true,
        dirtyDocumentIds: dirtyDocumentIds,
      ),
      AgentNativeToolCommandReadinessContext.fromCandidates(
        commandId: AppCommandId.formatActiveDocument.name,
        registered: registeredCommandIds.contains(
          AppCommandId.formatActiveDocument.name,
        ),
        requiredKind: ToolchainKind.formatter,
        requiredToolFamily: 'clang-format',
        candidates: nativeTools.formatters,
        dirtyDocumentIds: dirtyDocumentIds,
      ),
      AgentNativeToolCommandReadinessContext.fromCandidates(
        commandId: AppCommandId.runStaticAnalysis.name,
        registered: registeredCommandIds.contains(
          AppCommandId.runStaticAnalysis.name,
        ),
        requiredKind: ToolchainKind.staticAnalyzer,
        requiredToolFamily: 'clang-tidy',
        candidates: nativeTools.staticAnalyzers,
        requiresCleanWorkspace: true,
        dirtyDocumentIds: dirtyDocumentIds,
      ),
      AgentNativeToolCommandReadinessContext.fromCandidates(
        commandId: AppCommandId.runTests.name,
        registered: registeredCommandIds.contains(AppCommandId.runTests.name),
        requiredKind: ToolchainKind.testRunner,
        requiredToolFamily: 'ctest',
        candidates: nativeTools.testRunners,
        requiresCleanWorkspace: true,
        dirtyDocumentIds: dirtyDocumentIds,
      ),
    ];
    return readiness
        .map(
          (entry) => _nativeToolCommandReadinessWithBuildFacts(
            readiness: entry,
            buildFacts: buildFacts,
          ),
        )
        .toList(growable: false);
  }

  static AgentNativeToolCommandReadinessContext
  _nativeToolCommandReadinessWithBuildFacts({
    required AgentNativeToolCommandReadinessContext readiness,
    required AgentWorkspaceBuildFactsContext? buildFacts,
  }) {
    if (!readiness.ready || buildFacts == null || !buildFacts.hasCMakeLists) {
      return readiness;
    }
    if (readiness.commandId == AppCommandId.runStaticAnalysis.name &&
        !buildFacts.hasCompilationDatabase) {
      return readiness.blockedByRequiredCommand(
        requiredCommandId: AppCommandId.runBuild.name,
        reason:
            'Requires runBuild before runStaticAnalysis because compile_commands.json is missing for this CMake workspace.',
      );
    }
    if (readiness.commandId == AppCommandId.runTests.name &&
        !buildFacts.hasCTestConfig) {
      return readiness.blockedByRequiredCommand(
        requiredCommandId: AppCommandId.runBuild.name,
        reason:
            'Requires runBuild before runTests because CTest build files are missing for this CMake workspace.',
      );
    }
    return readiness;
  }

  static List<AgentDebugCommandReadinessContext> _debugCommandReadinessFor({
    required List<AgentCommandContext> debugCommands,
    required AgentDebugContext debug,
    required Iterable<String> dirtyDocumentIds,
  }) {
    final registeredCommandIds = debugCommands
        .map((command) => command.id)
        .toSet();
    final paused = debug.status == 'paused';
    final runningOrPaused = debug.status == 'running' || paused;
    final launchReady = debug.launch?.ready == true;
    final dirtyDocumentIdList = _normalizedCommandDirtyDocumentIds(
      dirtyDocumentIds,
    );
    final startDebuggingReady = launchReady && dirtyDocumentIdList.isEmpty;
    return <AgentDebugCommandReadinessContext>[
      AgentDebugCommandReadinessContext(
        commandId: AppCommandId.toggleBreakpoint.name,
        registered: registeredCommandIds.contains(
          AppCommandId.toggleBreakpoint.name,
        ),
        ready: true,
        reason: 'Breakpoint toggling is available for the active editor line.',
      ),
      AgentDebugCommandReadinessContext(
        commandId: AppCommandId.startDebugging.name,
        registered: registeredCommandIds.contains(
          AppCommandId.startDebugging.name,
        ),
        ready: startDebuggingReady,
        requiredState: 'launch.ready',
        requiredCommandId: launchReady && dirtyDocumentIdList.isNotEmpty
            ? AppCommandId.saveAll.name
            : null,
        dirtyDocumentIds: launchReady ? dirtyDocumentIdList : const <String>[],
        reason: launchReady
            ? dirtyDocumentIdList.isEmpty
                  ? 'Debug launch configuration is ready.'
                  : _dirtyWorkspaceReadinessReason(
                      AppCommandId.startDebugging.name,
                      dirtyDocumentIdList.length,
                    )
            : debug.launch?.reason ??
                  'Requires a ready debug launch configuration.',
      ),
      AgentDebugCommandReadinessContext(
        commandId: AppCommandId.stopDebugging.name,
        registered: registeredCommandIds.contains(
          AppCommandId.stopDebugging.name,
        ),
        ready: runningOrPaused,
        requiredState: 'running-or-paused',
        reason: runningOrPaused
            ? 'Debug session can be stopped.'
            : 'Requires a running or paused debug session.',
      ),
      AgentDebugCommandReadinessContext(
        commandId: AppCommandId.continueDebugging.name,
        registered: registeredCommandIds.contains(
          AppCommandId.continueDebugging.name,
        ),
        ready: paused,
        requiredState: 'paused',
        reason: paused
            ? 'Paused debug session can continue.'
            : 'Requires a paused debug session.',
      ),
      AgentDebugCommandReadinessContext(
        commandId: AppCommandId.stepOver.name,
        registered: registeredCommandIds.contains(AppCommandId.stepOver.name),
        ready: paused,
        requiredState: 'paused',
        reason: paused
            ? 'Paused debug session can step over.'
            : 'Requires a paused debug session.',
      ),
      AgentDebugCommandReadinessContext(
        commandId: AppCommandId.selectDebugThread.name,
        registered: registeredCommandIds.contains(
          AppCommandId.selectDebugThread.name,
        ),
        ready: debug.threads.isNotEmpty,
        requiredState: 'thread.available',
        candidateIds: debug.threads
            .map((thread) => thread.id)
            .toList(growable: false),
        reason: debug.threads.isNotEmpty
            ? 'Use an id from debug.threads.'
            : 'Requires at least one debug thread id.',
      ),
      AgentDebugCommandReadinessContext(
        commandId: AppCommandId.selectDebugStackFrame.name,
        registered: registeredCommandIds.contains(
          AppCommandId.selectDebugStackFrame.name,
        ),
        ready: debug.stackFrames.isNotEmpty,
        requiredState: 'stack-frame.available',
        candidateIds: debug.stackFrames
            .map((frame) => frame.id)
            .toList(growable: false),
        reason: debug.stackFrames.isNotEmpty
            ? 'Use an id from debug.stackFrames.'
            : 'Requires at least one debug stack frame id.',
      ),
    ];
  }
}

List<AgentCommandResultContext> _agentCommandResultHistory({
  AgentCommandResultContext? lastResult,
  Iterable<AgentCommandResultContext> recentResults =
      const <AgentCommandResultContext>[],
}) {
  final history = recentResults
      .take(_maxAgentCommandResultHistory)
      .toList(growable: false);
  if (history.isNotEmpty) {
    return history;
  }
  if (lastResult == null) {
    return const <AgentCommandResultContext>[];
  }
  return <AgentCommandResultContext>[lastResult];
}

List<AgentPatchApplicationContext> _agentPatchApplicationHistory({
  AgentPatchApplicationContext? lastPatchApplication,
  Iterable<AgentPatchApplicationContext> recentPatchApplications =
      const <AgentPatchApplicationContext>[],
}) {
  final history = recentPatchApplications
      .take(_maxAgentPatchApplicationHistory)
      .toList(growable: false);
  if (history.isNotEmpty) {
    return history;
  }
  if (lastPatchApplication == null) {
    return const <AgentPatchApplicationContext>[];
  }
  return <AgentPatchApplicationContext>[lastPatchApplication];
}

List<String> _normalizedCommandDirtyDocumentIds(
  Iterable<String> dirtyDocumentIds,
) {
  final normalized = <String>[];
  for (final documentId in dirtyDocumentIds) {
    final trimmed = documentId.trim();
    if (trimmed.isEmpty || normalized.contains(trimmed)) {
      continue;
    }
    normalized.add(trimmed);
  }
  return List<String>.unmodifiable(normalized);
}

String _dirtyWorkspaceReadinessReason(String commandId, int dirtyCount) {
  return 'Requires saveAll before $commandId because $dirtyCount workspace document(s) are dirty.';
}

class AgentNativeToolCommandReadinessContext {
  const AgentNativeToolCommandReadinessContext({
    required this.commandId,
    required this.registered,
    required this.requiredKind,
    required this.ready,
    required this.candidateToolchainIds,
    required this.reason,
    this.requiredToolFamily,
    this.requiredToolFamilies = const <String>[],
    this.toolFamily,
    this.toolchainId,
    this.requiredCommandId,
    this.dirtyDocumentIds = const <String>[],
  });

  factory AgentNativeToolCommandReadinessContext.fromCandidates({
    required String commandId,
    required bool registered,
    required ToolchainKind requiredKind,
    required Iterable<AgentToolchainEntryContext> candidates,
    String? requiredToolFamily,
    Iterable<String> requiredToolFamilies = const <String>[],
    bool requiresCleanWorkspace = false,
    Iterable<String> dirtyDocumentIds = const <String>[],
  }) {
    final dirtyDocumentIdList = _normalizedCommandDirtyDocumentIds(
      dirtyDocumentIds,
    );
    final requiredToolFamilyList = _normalizedRequiredToolFamilies(
      requiredToolFamily: requiredToolFamily,
      requiredToolFamilies: requiredToolFamilies,
    );
    final matchingCandidates = candidates
        .where((candidate) {
          return requiredToolFamilyList.isEmpty ||
              requiredToolFamilyList.contains(candidate.metadata['toolFamily']);
        })
        .toList(growable: false);
    AgentToolchainEntryContext? selectedCandidate;
    for (final candidate in matchingCandidates) {
      if (candidate.active) {
        selectedCandidate = candidate;
        break;
      }
    }
    selectedCandidate ??= matchingCandidates.isEmpty
        ? null
        : matchingCandidates.first;
    final toolchainReady = registered && selectedCandidate != null;
    final blockedByDirtyWorkspace =
        toolchainReady &&
        requiresCleanWorkspace &&
        dirtyDocumentIdList.isNotEmpty;
    final ready = toolchainReady && !blockedByDirtyWorkspace;
    final requiredLabel = requiredToolFamilyList.isEmpty
        ? requiredKind.wireValue
        : '${_toolFamilyRequirementLabel(requiredToolFamilyList)} ${requiredKind.wireValue}';
    return AgentNativeToolCommandReadinessContext(
      commandId: commandId,
      registered: registered,
      requiredKind: requiredKind.wireValue,
      requiredToolFamily: requiredToolFamilyList.length == 1
          ? requiredToolFamilyList.single
          : null,
      requiredToolFamilies: requiredToolFamilyList,
      ready: ready,
      toolFamily: _stringMetadata(selectedCandidate, 'toolFamily'),
      toolchainId: selectedCandidate?.id,
      requiredCommandId: blockedByDirtyWorkspace
          ? AppCommandId.saveAll.name
          : null,
      dirtyDocumentIds: blockedByDirtyWorkspace
          ? dirtyDocumentIdList
          : const <String>[],
      candidateToolchainIds: matchingCandidates
          .map((candidate) => candidate.id)
          .toList(growable: false),
      reason: !registered
          ? 'Command $commandId is not registered in the IDE command catalog.'
          : selectedCandidate == null
          ? 'Requires a registered $requiredLabel toolchain.'
          : blockedByDirtyWorkspace
          ? _dirtyWorkspaceReadinessReason(
              commandId,
              dirtyDocumentIdList.length,
            )
          : 'Uses ${selectedCandidate.id}.',
    );
  }

  final String commandId;
  final bool registered;
  final String requiredKind;
  final String? requiredToolFamily;
  final List<String> requiredToolFamilies;
  final bool ready;
  final String? toolFamily;
  final String? toolchainId;
  final String? requiredCommandId;
  final List<String> dirtyDocumentIds;
  final List<String> candidateToolchainIds;
  final String reason;

  AgentNativeToolCommandReadinessContext blockedByRequiredCommand({
    required String requiredCommandId,
    required String reason,
  }) {
    return AgentNativeToolCommandReadinessContext(
      commandId: commandId,
      registered: registered,
      requiredKind: requiredKind,
      requiredToolFamily: requiredToolFamily,
      requiredToolFamilies: requiredToolFamilies,
      ready: false,
      toolFamily: toolFamily,
      toolchainId: toolchainId,
      requiredCommandId: requiredCommandId,
      dirtyDocumentIds: dirtyDocumentIds,
      candidateToolchainIds: candidateToolchainIds,
      reason: reason,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'commandId': commandId,
      'registered': registered,
      'requiredKind': requiredKind,
      if (requiredToolFamily != null) 'requiredToolFamily': requiredToolFamily,
      if (requiredToolFamilies.length > 1)
        'requiredToolFamilies': requiredToolFamilies,
      'ready': ready,
      if (toolFamily != null) 'toolFamily': toolFamily,
      if (toolchainId != null) 'toolchainId': toolchainId,
      if (requiredCommandId != null) 'requiredCommandId': requiredCommandId,
      if (dirtyDocumentIds.isNotEmpty) 'dirtyDocumentIds': dirtyDocumentIds,
      'candidateToolchainIds': candidateToolchainIds,
      'reason': reason,
    };
  }
}

String? _stringMetadata(AgentToolchainEntryContext? entry, String key) {
  final value = entry?.metadata[key];
  return value is String && value.trim().isNotEmpty ? value.trim() : null;
}

List<String> _normalizedRequiredToolFamilies({
  String? requiredToolFamily,
  Iterable<String> requiredToolFamilies = const <String>[],
}) {
  final families = <String>[];
  void addFamily(String? family) {
    final normalized = family?.trim();
    if (normalized == null || normalized.isEmpty) {
      return;
    }
    if (!families.contains(normalized)) {
      families.add(normalized);
    }
  }

  addFamily(requiredToolFamily);
  for (final family in requiredToolFamilies) {
    addFamily(family);
  }
  return List<String>.unmodifiable(families);
}

String _toolFamilyRequirementLabel(List<String> families) {
  if (families.length == 1) {
    return families.single;
  }
  return '${families.take(families.length - 1).join(', ')} or ${families.last}';
}

class AgentDebugCommandReadinessContext {
  const AgentDebugCommandReadinessContext({
    required this.commandId,
    required this.registered,
    required this.ready,
    required this.reason,
    this.requiredState,
    this.requiredCommandId,
    this.dirtyDocumentIds = const <String>[],
    this.candidateIds = const <String>[],
  });

  final String commandId;
  final bool registered;
  final bool ready;
  final String reason;
  final String? requiredState;
  final String? requiredCommandId;
  final List<String> dirtyDocumentIds;
  final List<String> candidateIds;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'commandId': commandId,
      'registered': registered,
      'ready': ready,
      if (requiredState != null) 'requiredState': requiredState,
      if (requiredCommandId != null) 'requiredCommandId': requiredCommandId,
      if (dirtyDocumentIds.isNotEmpty) 'dirtyDocumentIds': dirtyDocumentIds,
      'candidateIds': candidateIds,
      'reason': reason,
    };
  }
}

class AgentCommandResultContext {
  const AgentCommandResultContext({
    required this.commandId,
    required this.applied,
    required this.message,
    this.input,
    this.metadata = const <String, Object?>{},
    this.completedAt,
  });

  final String commandId;
  final String? input;
  final bool applied;
  final String message;
  final Map<String, Object?> metadata;
  final DateTime? completedAt;

  Map<String, Object?> toJson() {
    final metadataJson = _agentCommandResultMetadataJson(metadata);
    return <String, Object?>{
      'commandId': commandId,
      if (input != null) 'input': input,
      'applied': applied,
      'message': message,
      if (metadataJson.isNotEmpty) 'metadata': metadataJson,
      if (completedAt != null)
        'completedAt': completedAt!.toUtc().toIso8601String(),
    };
  }
}

Map<String, Object?> _agentCommandResultMetadataJson(
  Map<String, Object?> metadata,
) {
  final result = <String, Object?>{};
  for (final entry in metadata.entries) {
    final value = _agentCommandResultMetadataValueJson(entry.value);
    if (!identical(value, _unsupportedAgentCommandResultMetadataValue)) {
      result[entry.key] = value;
    }
  }
  return result;
}

Object? _agentCommandResultMetadataValueJson(Object? value) {
  if (value == null || value is String || value is num || value is bool) {
    return value;
  }
  if (value is DateTime) {
    return value.toUtc().toIso8601String();
  }
  if (value is Iterable) {
    final items = <Object?>[];
    for (final item in value) {
      final itemJson = _agentCommandResultMetadataValueJson(item);
      if (!identical(itemJson, _unsupportedAgentCommandResultMetadataValue)) {
        items.add(itemJson);
      }
    }
    return items;
  }
  if (value is Map) {
    final map = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        continue;
      }
      final entryJson = _agentCommandResultMetadataValueJson(entry.value);
      if (!identical(entryJson, _unsupportedAgentCommandResultMetadataValue)) {
        map[key] = entryJson;
      }
    }
    return map;
  }
  return _unsupportedAgentCommandResultMetadataValue;
}

const Object _unsupportedAgentCommandResultMetadataValue = Object();

class AgentCommandContext {
  const AgentCommandContext({
    required this.id,
    required this.label,
    required this.shortcutHint,
    required this.description,
    required this.requiresInput,
    required this.inputLabel,
  });

  final String id;
  final String label;
  final String shortcutHint;
  final String description;
  final bool requiresInput;
  final String inputLabel;

  factory AgentCommandContext.fromDescriptor(AppCommandDescriptor command) {
    return AgentCommandContext(
      id: command.id.name,
      label: command.label,
      shortcutHint: command.shortcutHint,
      description: command.description,
      requiresInput: command.requiresInput,
      inputLabel: command.inputLabel,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'shortcutHint': shortcutHint,
      'description': description,
      'requiresInput': requiresInput,
      'inputLabel': inputLabel,
    };
  }
}

class AgentWorkspaceContext {
  const AgentWorkspaceContext({
    required this.activeFilePath,
    required this.fileCount,
    required this.files,
    required this.filesTruncated,
    required this.openDocumentIds,
    required this.dirtyDocumentIds,
    required this.documentSampleCount,
    required this.documentSamples,
    required this.documentSamplesTruncated,
    required this.buildFacts,
    this.workspaceRoot = '',
    this.lastSearch,
    this.lastSymbolSearch,
    this.diagnostics,
    this.sourceControlStatus,
    this.sourceControlDiff,
    this.sourceControlContext,
  });

  final String activeFilePath;
  final int fileCount;
  final List<String> files;
  final bool filesTruncated;
  final List<String> openDocumentIds;
  final List<String> dirtyDocumentIds;
  final int documentSampleCount;
  final List<AgentWorkspaceDocumentSampleContext> documentSamples;
  final bool documentSamplesTruncated;
  final AgentWorkspaceBuildFactsContext buildFacts;
  final String workspaceRoot;
  final AgentWorkspaceSearchResultContext? lastSearch;
  final AgentWorkspaceSymbolSearchResultContext? lastSymbolSearch;
  final WorkspaceDiagnosticsSnapshot? diagnostics;
  final SourceControlStatusSnapshot? sourceControlStatus;
  final SourceControlDiffSnapshot? sourceControlDiff;
  final SourceControlAgentContextSnapshot? sourceControlContext;

  factory AgentWorkspaceContext.fromWorkspaceState({
    required String activeFilePath,
    required Iterable<String> files,
    Iterable<String> openDocumentIds = const <String>[],
    Iterable<String> dirtyDocumentIds = const <String>[],
    Iterable<DocumentState> documentSamples = const <DocumentState>[],
    String workspaceRoot = '',
    AgentWorkspaceSearchResultContext? lastSearch,
    AgentWorkspaceSymbolSearchResultContext? lastSymbolSearch,
    WorkspaceDiagnosticsSnapshot? diagnostics,
    SourceControlStatusSnapshot? sourceControlStatus,
    SourceControlDiffSnapshot? sourceControlDiff,
    int maxFiles = 200,
    int maxDocumentSamples = 10,
  }) {
    final seenFiles = <String>{};
    final allFiles = <String>[
      for (final file in files)
        if (seenFiles.add(file)) file,
    ];
    final truncated = allFiles.length > maxFiles;
    final visibleFiles = truncated
        ? allFiles.take(maxFiles).toList(growable: false)
        : allFiles;
    if (truncated &&
        activeFilePath.isNotEmpty &&
        !visibleFiles.contains(activeFilePath)) {
      if (visibleFiles.isEmpty) {
        visibleFiles.add(activeFilePath);
      } else {
        visibleFiles[visibleFiles.length - 1] = activeFilePath;
      }
    }
    final seenOpenDocuments = <String>{};
    final normalizedOpenDocumentIds = <String>[
      for (final documentId in openDocumentIds)
        if (seenOpenDocuments.add(documentId)) documentId,
    ];
    final seenDirtyDocuments = <String>{};
    final normalizedDirtyDocumentIds = <String>[
      for (final documentId in dirtyDocumentIds)
        if (seenDirtyDocuments.add(documentId)) documentId,
    ];
    final sampledDocuments = <DocumentState>[];
    final seenSampledDocuments = <String>{};
    for (final document in documentSamples) {
      if (document.documentId.trim().isEmpty ||
          !seenSampledDocuments.add(document.documentId)) {
        continue;
      }
      sampledDocuments.add(document);
    }
    final sampleTruncated = sampledDocuments.length > maxDocumentSamples;
    final openSet = normalizedOpenDocumentIds.toSet();
    final dirtySet = normalizedDirtyDocumentIds.toSet();
    final normalizedWorkspaceRoot = workspaceRoot.trim();
    final sourceControlContext =
        sourceControlStatus == null && sourceControlDiff == null
        ? null
        : SourceControlAgentContextSnapshot.fromState(
            workspaceRoot: normalizedWorkspaceRoot,
            status: sourceControlStatus,
            diffPreview: sourceControlDiff,
          );
    return AgentWorkspaceContext(
      activeFilePath: activeFilePath,
      fileCount: allFiles.length,
      files: visibleFiles,
      filesTruncated: truncated,
      openDocumentIds: normalizedOpenDocumentIds,
      dirtyDocumentIds: normalizedDirtyDocumentIds,
      documentSampleCount: sampledDocuments.length,
      documentSamples: sampledDocuments
          .take(maxDocumentSamples)
          .map(
            (document) => AgentWorkspaceDocumentSampleContext.fromDocument(
              document,
              active: document.documentId == activeFilePath,
              open: openSet.contains(document.documentId),
              dirty: dirtySet.contains(document.documentId),
            ),
          )
          .toList(growable: false),
      documentSamplesTruncated: sampleTruncated,
      buildFacts: AgentWorkspaceBuildFactsContext.fromFiles(allFiles),
      workspaceRoot: normalizedWorkspaceRoot,
      lastSearch: lastSearch,
      lastSymbolSearch: lastSymbolSearch,
      diagnostics: diagnostics,
      sourceControlStatus: sourceControlStatus,
      sourceControlDiff: sourceControlDiff,
      sourceControlContext: sourceControlContext,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'activeFilePath': activeFilePath,
      if (workspaceRoot.isNotEmpty) 'workspaceRoot': workspaceRoot,
      'fileCount': fileCount,
      'files': files,
      'filesTruncated': filesTruncated,
      'openDocumentIds': openDocumentIds,
      'dirtyDocumentIds': dirtyDocumentIds,
      'documentSampleCount': documentSampleCount,
      'documentSamples': documentSamples
          .map((sample) => sample.toJson())
          .toList(growable: false),
      'documentSamplesTruncated': documentSamplesTruncated,
      'buildFacts': buildFacts.toJson(),
      if (lastSearch != null) 'lastSearch': lastSearch!.toJson(),
      if (lastSymbolSearch != null)
        'lastSymbolSearch': lastSymbolSearch!.toJson(),
      if (diagnostics != null) 'diagnostics': diagnostics!.toJson(),
      if (sourceControlStatus != null)
        'sourceControl': sourceControlStatus!.toJson(),
      if (sourceControlDiff != null)
        'sourceControlDiff': sourceControlDiff!.toJson(),
      if (sourceControlContext != null)
        'sourceControlContext': sourceControlContext!.toJson(),
    };
  }
}

class AgentTestingContext {
  const AgentTestingContext({
    this.discovery,
    this.lastRun,
    this.rerunFailed,
    this.debugFailed,
    this.debugFailedRoutePlan,
  });

  factory AgentTestingContext.fromState({
    TestDiscoveryResult? discovery,
    TestRunResult? lastRun,
    String workspaceRoot = '',
    FailedTestRerunPlanner rerunPlanner = const FailedTestRerunPlanner(),
  }) {
    final debugFailed = rerunPlanner.plan(
      lastRun: lastRun,
      workspaceRoot: workspaceRoot,
      debug: true,
    );
    return AgentTestingContext(
      discovery: discovery,
      lastRun: lastRun,
      rerunFailed: rerunPlanner.plan(
        lastRun: lastRun,
        workspaceRoot: workspaceRoot,
      ),
      debugFailed: debugFailed,
      debugFailedRoutePlan: debugFailed == null
          ? null
          : const TestDebugLaunchRoutePlanner().plan(debugFailed),
    );
  }

  final TestDiscoveryResult? discovery;
  final TestRunResult? lastRun;
  final TestRunConfiguration? rerunFailed;
  final TestRunConfiguration? debugFailed;
  final DebugLaunchRoutePlan? debugFailedRoutePlan;

  bool get hasFailingTests {
    return lastRun != null &&
        (lastRun!.failedCount > 0 || lastRun!.failedTests.isNotEmpty);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'hasDiscovery': discovery != null,
      'hasLastRun': lastRun != null,
      'hasFailingTests': hasFailingTests,
      if (discovery != null) 'discovered': discovery!.toJson(),
      if (lastRun != null) 'lastRun': lastRun!.toJson(),
      if (rerunFailed != null) 'rerunFailed': rerunFailed!.toJson(),
      if (debugFailed != null) 'debugFailed': debugFailed!.toJson(),
      if (debugFailedRoutePlan != null)
        'debugFailedRoutePlan': debugFailedRoutePlan!.toJson(),
    };
  }
}

class AgentWorkspaceSymbolSearchResultContext {
  const AgentWorkspaceSymbolSearchResultContext({
    required this.query,
    required this.scannedDocumentCount,
    required this.matchCount,
    required this.matches,
    required this.matchesTruncated,
  });

  final String query;
  final int scannedDocumentCount;
  final int matchCount;
  final List<AgentWorkspaceSymbolMatchContext> matches;
  final bool matchesTruncated;

  factory AgentWorkspaceSymbolSearchResultContext.fromWorkspaceResult({
    required String query,
    required int scannedDocumentCount,
    required WorkspaceSymbolSearchResult result,
    int maxMatches = 50,
  }) {
    final matches = result.matches
        .take(maxMatches)
        .map(AgentWorkspaceSymbolMatchContext.fromWorkspaceSymbolMatch)
        .toList(growable: false);
    return AgentWorkspaceSymbolSearchResultContext(
      query: query.trim(),
      scannedDocumentCount: scannedDocumentCount,
      matchCount: result.matches.length,
      matches: List<AgentWorkspaceSymbolMatchContext>.unmodifiable(matches),
      matchesTruncated: result.matches.length > matches.length,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'query': query,
      'scannedDocumentCount': scannedDocumentCount,
      'matchCount': matchCount,
      'matches': matches.map((match) => match.toJson()).toList(growable: false),
      'matchesTruncated': matchesTruncated,
    };
  }
}

class AgentWorkspaceSymbolMatchContext {
  const AgentWorkspaceSymbolMatchContext({
    required this.documentId,
    required this.name,
    required this.kind,
    required this.lineNumber,
    required this.start,
    required this.end,
    required this.lineText,
    this.snapshotSource = 'service-analysis',
    this.snapshotConfidence = 'service-backed',
    this.detail,
  });

  final String documentId;
  final String name;
  final String kind;
  final int lineNumber;
  final int start;
  final int end;
  final String lineText;
  final String snapshotSource;
  final String snapshotConfidence;
  final String? detail;

  bool get usedFallback => snapshotSource == 'local-builder-fallback';

  factory AgentWorkspaceSymbolMatchContext.fromWorkspaceSymbolMatch(
    WorkspaceSymbolMatch match,
  ) {
    return AgentWorkspaceSymbolMatchContext(
      documentId: match.documentId,
      name: match.name,
      kind: match.kind.name,
      lineNumber: match.lineNumber,
      start: match.nameRange.start,
      end: match.nameRange.end,
      lineText: match.lineText,
      snapshotSource: match.snapshotSource.wireValue,
      snapshotConfidence: match.snapshotConfidence.wireValue,
      detail: match.detail,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'name': name,
      'kind': kind,
      'lineNumber': lineNumber,
      'start': start,
      'end': end,
      'lineText': lineText,
      'snapshotSource': snapshotSource,
      'snapshotConfidence': snapshotConfidence,
      'usedFallback': usedFallback,
      if (detail != null) 'detail': detail,
    };
  }
}

class AgentWorkspaceSearchResultContext {
  const AgentWorkspaceSearchResultContext({
    required this.query,
    required this.scannedDocumentCount,
    required this.matchCount,
    required this.matches,
    required this.matchesTruncated,
  });

  final String query;
  final int scannedDocumentCount;
  final int matchCount;
  final List<AgentWorkspaceSearchMatchContext> matches;
  final bool matchesTruncated;

  factory AgentWorkspaceSearchResultContext.fromDocuments({
    required String query,
    required Iterable<DocumentState> documents,
    int maxMatches = 50,
  }) {
    final normalizedQuery = query.trim();
    final documentList = documents.toList(growable: false);
    if (normalizedQuery.isEmpty) {
      return AgentWorkspaceSearchResultContext(
        query: normalizedQuery,
        scannedDocumentCount: documentList.length,
        matchCount: 0,
        matches: const <AgentWorkspaceSearchMatchContext>[],
        matchesTruncated: false,
      );
    }
    final matches = <AgentWorkspaceSearchMatchContext>[];
    var matchCount = 0;
    for (final document in documentList) {
      final documentMatches = _searchDocumentForAgent(
        document: document,
        query: normalizedQuery,
      );
      for (final match in documentMatches) {
        matchCount += 1;
        if (matches.length < maxMatches) {
          matches.add(match);
        }
      }
    }
    return AgentWorkspaceSearchResultContext(
      query: normalizedQuery,
      scannedDocumentCount: documentList.length,
      matchCount: matchCount,
      matches: List<AgentWorkspaceSearchMatchContext>.unmodifiable(matches),
      matchesTruncated: matchCount > matches.length,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'query': query,
      'scannedDocumentCount': scannedDocumentCount,
      'matchCount': matchCount,
      'matches': matches.map((match) => match.toJson()).toList(growable: false),
      'matchesTruncated': matchesTruncated,
    };
  }
}

class AgentWorkspaceSearchMatchContext {
  const AgentWorkspaceSearchMatchContext({
    required this.documentId,
    required this.lineNumber,
    required this.start,
    required this.end,
    required this.lineText,
  });

  final String documentId;
  final int lineNumber;
  final int start;
  final int end;
  final String lineText;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'lineNumber': lineNumber,
      'start': start,
      'end': end,
      'lineText': lineText,
    };
  }
}

class AgentWorkspaceBuildFactsContext {
  const AgentWorkspaceBuildFactsContext({
    required this.hasCompilationDatabase,
    required this.compilationDatabasePaths,
    required this.hasCMakeLists,
    required this.cmakeListsPaths,
    required this.hasCMakePresets,
    required this.cmakePresetPaths,
    required this.hasCMakeUserPresets,
    required this.cmakeUserPresetPaths,
    required this.hasNinjaBuild,
    required this.ninjaBuildPaths,
    required this.hasClangdConfig,
    required this.clangdConfigPaths,
    required this.hasClangFormatConfig,
    required this.clangFormatConfigPaths,
    required this.hasClangTidyConfig,
    required this.clangTidyConfigPaths,
    required this.hasCTestConfig,
    required this.ctestConfigPaths,
    required this.buildSystemHints,
    required this.toolingHints,
    required this.pathsTruncated,
  });

  final bool hasCompilationDatabase;
  final List<String> compilationDatabasePaths;
  final bool hasCMakeLists;
  final List<String> cmakeListsPaths;
  final bool hasCMakePresets;
  final List<String> cmakePresetPaths;
  final bool hasCMakeUserPresets;
  final List<String> cmakeUserPresetPaths;
  final bool hasNinjaBuild;
  final List<String> ninjaBuildPaths;
  final bool hasClangdConfig;
  final List<String> clangdConfigPaths;
  final bool hasClangFormatConfig;
  final List<String> clangFormatConfigPaths;
  final bool hasClangTidyConfig;
  final List<String> clangTidyConfigPaths;
  final bool hasCTestConfig;
  final List<String> ctestConfigPaths;
  final List<String> buildSystemHints;
  final List<String> toolingHints;
  final bool pathsTruncated;

  factory AgentWorkspaceBuildFactsContext.fromFiles(
    Iterable<String> files, {
    int maxPathsPerKind = 20,
  }) {
    final normalizedFiles = files
        .map(_normalizeWorkspacePath)
        .toList(growable: false);
    final compilationDatabases = _pathsWithBasename(
      normalizedFiles,
      'compile_commands.json',
      maxPathsPerKind,
    );
    final cmakeLists = _pathsWithBasename(
      normalizedFiles,
      'CMakeLists.txt',
      maxPathsPerKind,
    );
    final cmakePresets = _pathsWithBasename(
      normalizedFiles,
      'CMakePresets.json',
      maxPathsPerKind,
    );
    final cmakeUserPresets = _pathsWithBasename(
      normalizedFiles,
      'CMakeUserPresets.json',
      maxPathsPerKind,
    );
    final ninjaBuilds = _pathsWithBasename(
      normalizedFiles,
      'build.ninja',
      maxPathsPerKind,
    );
    final clangdConfigs = _pathsWithBasename(
      normalizedFiles,
      '.clangd',
      maxPathsPerKind,
    );
    final clangFormatConfigs = _pathsWithBasenames(
      normalizedFiles,
      const <String>{'.clang-format', '_clang-format'},
      maxPathsPerKind,
    );
    final clangTidyConfigs = _pathsWithBasename(
      normalizedFiles,
      '.clang-tidy',
      maxPathsPerKind,
    );
    final ctestConfigs = _pathsWithBasenames(normalizedFiles, const <String>{
      'CTestTestfile.cmake',
      'CTestConfig.cmake',
    }, maxPathsPerKind);
    final allMatchedPathCount =
        _countPathsWithBasename(normalizedFiles, 'compile_commands.json') +
        _countPathsWithBasename(normalizedFiles, 'CMakeLists.txt') +
        _countPathsWithBasename(normalizedFiles, 'CMakePresets.json') +
        _countPathsWithBasename(normalizedFiles, 'CMakeUserPresets.json') +
        _countPathsWithBasename(normalizedFiles, 'build.ninja') +
        _countPathsWithBasename(normalizedFiles, '.clangd') +
        _countPathsWithBasenames(normalizedFiles, const <String>{
          '.clang-format',
          '_clang-format',
        }) +
        _countPathsWithBasename(normalizedFiles, '.clang-tidy') +
        _countPathsWithBasenames(normalizedFiles, const <String>{
          'CTestTestfile.cmake',
          'CTestConfig.cmake',
        });
    final visibleMatchedPathCount =
        compilationDatabases.length +
        cmakeLists.length +
        cmakePresets.length +
        cmakeUserPresets.length +
        ninjaBuilds.length +
        clangdConfigs.length +
        clangFormatConfigs.length +
        clangTidyConfigs.length +
        ctestConfigs.length;
    return AgentWorkspaceBuildFactsContext(
      hasCompilationDatabase: compilationDatabases.isNotEmpty,
      compilationDatabasePaths: compilationDatabases,
      hasCMakeLists: cmakeLists.isNotEmpty,
      cmakeListsPaths: cmakeLists,
      hasCMakePresets: cmakePresets.isNotEmpty,
      cmakePresetPaths: cmakePresets,
      hasCMakeUserPresets: cmakeUserPresets.isNotEmpty,
      cmakeUserPresetPaths: cmakeUserPresets,
      hasNinjaBuild: ninjaBuilds.isNotEmpty,
      ninjaBuildPaths: ninjaBuilds,
      hasClangdConfig: clangdConfigs.isNotEmpty,
      clangdConfigPaths: clangdConfigs,
      hasClangFormatConfig: clangFormatConfigs.isNotEmpty,
      clangFormatConfigPaths: clangFormatConfigs,
      hasClangTidyConfig: clangTidyConfigs.isNotEmpty,
      clangTidyConfigPaths: clangTidyConfigs,
      hasCTestConfig: ctestConfigs.isNotEmpty,
      ctestConfigPaths: ctestConfigs,
      buildSystemHints: _buildSystemHints(
        hasCompilationDatabase: compilationDatabases.isNotEmpty,
        hasCMakeLists: cmakeLists.isNotEmpty,
        hasCMakePresets: cmakePresets.isNotEmpty,
        hasCMakeUserPresets: cmakeUserPresets.isNotEmpty,
        hasNinjaBuild: ninjaBuilds.isNotEmpty,
        hasClangdConfig: clangdConfigs.isNotEmpty,
      ),
      toolingHints: _workspaceToolingHints(
        hasCompilationDatabase: compilationDatabases.isNotEmpty,
        hasCMakeLists: cmakeLists.isNotEmpty,
        hasCMakePresets: cmakePresets.isNotEmpty,
        hasCMakeUserPresets: cmakeUserPresets.isNotEmpty,
        hasNinjaBuild: ninjaBuilds.isNotEmpty,
        hasClangdConfig: clangdConfigs.isNotEmpty,
        hasClangFormatConfig: clangFormatConfigs.isNotEmpty,
        hasClangTidyConfig: clangTidyConfigs.isNotEmpty,
        hasCTestConfig: ctestConfigs.isNotEmpty,
      ),
      pathsTruncated: allMatchedPathCount > visibleMatchedPathCount,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'hasCompilationDatabase': hasCompilationDatabase,
      'compilationDatabasePaths': compilationDatabasePaths,
      'hasCMakeLists': hasCMakeLists,
      'cmakeListsPaths': cmakeListsPaths,
      'hasCMakePresets': hasCMakePresets,
      'cmakePresetPaths': cmakePresetPaths,
      'hasCMakeUserPresets': hasCMakeUserPresets,
      'cmakeUserPresetPaths': cmakeUserPresetPaths,
      'hasNinjaBuild': hasNinjaBuild,
      'ninjaBuildPaths': ninjaBuildPaths,
      'hasClangdConfig': hasClangdConfig,
      'clangdConfigPaths': clangdConfigPaths,
      'hasClangFormatConfig': hasClangFormatConfig,
      'clangFormatConfigPaths': clangFormatConfigPaths,
      'hasClangTidyConfig': hasClangTidyConfig,
      'clangTidyConfigPaths': clangTidyConfigPaths,
      'hasCTestConfig': hasCTestConfig,
      'ctestConfigPaths': ctestConfigPaths,
      'buildSystemHints': buildSystemHints,
      'toolingHints': toolingHints,
      'pathsTruncated': pathsTruncated,
    };
  }
}

class AgentWorkspaceDocumentSampleContext {
  const AgentWorkspaceDocumentSampleContext({
    required this.documentId,
    required this.revision,
    required this.length,
    required this.lineCount,
    required this.text,
    required this.textStart,
    required this.textEnd,
    required this.textTruncated,
    required this.active,
    required this.open,
    required this.dirty,
  });

  final String documentId;
  final int revision;
  final int length;
  final int lineCount;
  final String text;
  final int textStart;
  final int textEnd;
  final bool textTruncated;
  final bool active;
  final bool open;
  final bool dirty;

  factory AgentWorkspaceDocumentSampleContext.fromDocument(
    DocumentState document, {
    required bool active,
    required bool open,
    required bool dirty,
    int maxTextLength = 12000,
  }) {
    final textWindow = _documentTextWindow(
      textLength: document.text.length,
      selection: null,
      maxTextLength: maxTextLength,
    );
    return AgentWorkspaceDocumentSampleContext(
      documentId: document.documentId,
      revision: document.revision,
      length: document.length,
      lineCount: document.lines.length,
      text: document.text.substring(textWindow.start, textWindow.end),
      textStart: textWindow.start,
      textEnd: textWindow.end,
      textTruncated: document.text.length > maxTextLength,
      active: active,
      open: open,
      dirty: dirty,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'revision': revision,
      'length': length,
      'lineCount': lineCount,
      'text': text,
      'textStart': textStart,
      'textEnd': textEnd,
      'textTruncated': textTruncated,
      'active': active,
      'open': open,
      'dirty': dirty,
    };
  }
}

class AgentDocumentContext {
  const AgentDocumentContext({
    required this.documentId,
    required this.revision,
    required this.length,
    required this.lineCount,
    required this.text,
    required this.textStart,
    required this.textEnd,
    required this.textTruncated,
  });

  final String documentId;
  final int revision;
  final int length;
  final int lineCount;
  final String text;
  final int textStart;
  final int textEnd;
  final bool textTruncated;

  factory AgentDocumentContext.fromDocument(
    DocumentState document, {
    SelectionState? selection,
    int maxTextLength = 50000,
  }) {
    final truncated = document.text.length > maxTextLength;
    final textWindow = _documentTextWindow(
      textLength: document.text.length,
      selection: selection,
      maxTextLength: maxTextLength,
    );
    return AgentDocumentContext(
      documentId: document.documentId,
      revision: document.revision,
      length: document.length,
      lineCount: document.lines.length,
      text: document.text.substring(textWindow.start, textWindow.end),
      textStart: textWindow.start,
      textEnd: textWindow.end,
      textTruncated: truncated,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'revision': revision,
      'length': length,
      'lineCount': lineCount,
      'text': text,
      'textStart': textStart,
      'textEnd': textEnd,
      'textTruncated': textTruncated,
    };
  }
}

class _AgentDocumentTextWindow {
  const _AgentDocumentTextWindow({required this.start, required this.end});

  final int start;
  final int end;
}

_AgentDocumentTextWindow _documentTextWindow({
  required int textLength,
  required SelectionState? selection,
  required int maxTextLength,
}) {
  if (textLength <= maxTextLength) {
    return _AgentDocumentTextWindow(start: 0, end: textLength);
  }
  final anchor = _clampOffset(selection?.start ?? 0, textLength);
  final maxStart = textLength - maxTextLength;
  var start = anchor - maxTextLength ~/ 2;
  if (start < 0) {
    start = 0;
  }
  if (start > maxStart) {
    start = maxStart;
  }
  return _AgentDocumentTextWindow(start: start, end: start + maxTextLength);
}

class AgentSelectionContext {
  const AgentSelectionContext({
    required this.baseOffset,
    required this.extentOffset,
    required this.start,
    required this.end,
    required this.coordinateBase,
    required this.baseLine,
    required this.baseColumn,
    required this.extentLine,
    required this.extentColumn,
    required this.startLine,
    required this.startColumn,
    required this.endLine,
    required this.endColumn,
    required this.isCollapsed,
    required this.selectedText,
    required this.selectedTextTruncated,
  });

  final int baseOffset;
  final int extentOffset;
  final int start;
  final int end;
  final String coordinateBase;
  final int baseLine;
  final int baseColumn;
  final int extentLine;
  final int extentColumn;
  final int startLine;
  final int startColumn;
  final int endLine;
  final int endColumn;
  final bool isCollapsed;
  final String selectedText;
  final bool selectedTextTruncated;

  factory AgentSelectionContext.fromDocumentSelection({
    required DocumentState document,
    required SelectionState selection,
    int maxSelectedTextLength = 12000,
  }) {
    final start = _clampOffset(selection.start, document.length);
    final end = _clampOffset(selection.end, document.length);
    final baseOffset = _clampOffset(selection.baseOffset, document.length);
    final extentOffset = _clampOffset(selection.extentOffset, document.length);
    final basePosition = document.positionForOffset(baseOffset);
    final extentPosition = document.positionForOffset(extentOffset);
    final startPosition = document.positionForOffset(start);
    final endPosition = document.positionForOffset(end);
    final selectedText = document.text.substring(start, end);
    final truncated = selectedText.length > maxSelectedTextLength;
    return AgentSelectionContext(
      baseOffset: baseOffset,
      extentOffset: extentOffset,
      start: start,
      end: end,
      coordinateBase: 'zero-based',
      baseLine: basePosition.line,
      baseColumn: basePosition.column,
      extentLine: extentPosition.line,
      extentColumn: extentPosition.column,
      startLine: startPosition.line,
      startColumn: startPosition.column,
      endLine: endPosition.line,
      endColumn: endPosition.column,
      isCollapsed: selection.isCollapsed,
      selectedText: truncated
          ? selectedText.substring(0, maxSelectedTextLength)
          : selectedText,
      selectedTextTruncated: truncated,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'baseOffset': baseOffset,
      'extentOffset': extentOffset,
      'start': start,
      'end': end,
      'coordinateBase': coordinateBase,
      'baseLine': baseLine,
      'baseColumn': baseColumn,
      'extentLine': extentLine,
      'extentColumn': extentColumn,
      'startLine': startLine,
      'startColumn': startColumn,
      'endLine': endLine,
      'endColumn': endColumn,
      'isCollapsed': isCollapsed,
      'selectedText': selectedText,
      'selectedTextTruncated': selectedTextTruncated,
    };
  }
}

class AgentDiagnosticContext {
  const AgentDiagnosticContext({
    required this.severity,
    required this.code,
    required this.message,
    required this.start,
    required this.end,
    required this.coordinateBase,
    required this.startLine,
    required this.startColumn,
    required this.endLine,
    required this.endColumn,
  });

  final String severity;
  final String code;
  final String message;
  final int start;
  final int end;
  final String coordinateBase;
  final int startLine;
  final int startColumn;
  final int endLine;
  final int endColumn;

  factory AgentDiagnosticContext.fromDiagnostic(
    Diagnostic diagnostic, {
    required DocumentState document,
  }) {
    final start = diagnostic.range.start;
    final end = diagnostic.range.end;
    final startPosition = document.positionForOffset(
      _clampOffset(start, document.length),
    );
    final endPosition = document.positionForOffset(
      _clampOffset(end, document.length),
    );
    return AgentDiagnosticContext(
      severity: diagnostic.severity.name,
      code: diagnostic.code,
      message: diagnostic.message,
      start: start,
      end: end,
      coordinateBase: 'zero-based',
      startLine: startPosition.line,
      startColumn: startPosition.column,
      endLine: endPosition.line,
      endColumn: endPosition.column,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'severity': severity,
      'code': code,
      'message': message,
      'start': start,
      'end': end,
      'coordinateBase': coordinateBase,
      'startLine': startLine,
      'startColumn': startColumn,
      'endLine': endLine,
      'endColumn': endColumn,
    };
  }
}

class AgentRuntimeContext {
  const AgentRuntimeContext({
    required this.hasSession,
    this.sessionId,
    this.kind,
    this.status,
    this.statusMessage,
    this.stdoutTail = const <String>[],
    this.stdoutEventCount = 0,
    this.stdoutTruncated = false,
    this.stderrTail = const <String>[],
    this.stderrEventCount = 0,
    this.stderrTruncated = false,
    this.eventKinds = const <String>[],
    this.eventKindCount = 0,
    this.eventKindsTruncated = false,
  });

  final bool hasSession;
  final String? sessionId;
  final String? kind;
  final String? status;
  final String? statusMessage;
  final List<String> stdoutTail;
  final int stdoutEventCount;
  final bool stdoutTruncated;
  final List<String> stderrTail;
  final int stderrEventCount;
  final bool stderrTruncated;
  final List<String> eventKinds;
  final int eventKindCount;
  final bool eventKindsTruncated;

  factory AgentRuntimeContext.fromRuntimeState({
    ExecutionSession? lastExecutionSession,
    Iterable<RuntimeEventEnvelope> lastRuntimeEvents =
        const <RuntimeEventEnvelope>[],
    int maxLogTail = 50,
    int maxEventKinds = 50,
  }) {
    final session = lastExecutionSession;
    if (session == null) {
      return const AgentRuntimeContext(hasSession: false);
    }
    final stdoutMessages = session.stdoutEvents
        .map((event) => event.message)
        .toList(growable: false);
    final stderrMessages = session.stderrEvents
        .map((event) => event.message)
        .toList(growable: false);
    final runtimeEvents = lastRuntimeEvents.toList(growable: false);
    final uniqueEventKindCount = _uniqueEventKindCount(runtimeEvents);
    return AgentRuntimeContext(
      hasSession: true,
      sessionId: session.sessionId,
      kind: session.kind,
      status: session.status.name,
      statusMessage: session.statusMessage,
      stdoutTail: _logTail(stdoutMessages, maxLogTail),
      stdoutEventCount: stdoutMessages.length,
      stdoutTruncated: stdoutMessages.length > maxLogTail,
      stderrTail: _logTail(stderrMessages, maxLogTail),
      stderrEventCount: stderrMessages.length,
      stderrTruncated: stderrMessages.length > maxLogTail,
      eventKinds: _eventKindSample(runtimeEvents, maxEventKinds),
      eventKindCount: uniqueEventKindCount,
      eventKindsTruncated: uniqueEventKindCount > maxEventKinds,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'hasSession': hasSession,
      if (sessionId != null) 'sessionId': sessionId,
      if (kind != null) 'kind': kind,
      if (status != null) 'status': status,
      if (statusMessage != null) 'statusMessage': statusMessage,
      'stdoutTail': stdoutTail,
      'stdoutEventCount': stdoutEventCount,
      'stdoutTruncated': stdoutTruncated,
      'stderrTail': stderrTail,
      'stderrEventCount': stderrEventCount,
      'stderrTruncated': stderrTruncated,
      'eventKinds': eventKinds,
      'eventKindCount': eventKindCount,
      'eventKindsTruncated': eventKindsTruncated,
    };
  }
}

List<String> _logTail(List<String> messages, int maxLogTail) {
  if (messages.length <= maxLogTail) {
    return messages;
  }
  return messages.sublist(messages.length - maxLogTail);
}

int _uniqueEventKindCount(Iterable<RuntimeEventEnvelope> events) {
  return events.map((event) => event.eventKind).toSet().length;
}

List<String> _eventKindSample(
  Iterable<RuntimeEventEnvelope> events,
  int maxEventKinds,
) {
  final seen = <String>{};
  final eventKinds = <String>[];
  for (final event in events) {
    if (!seen.add(event.eventKind)) {
      continue;
    }
    eventKinds.add(event.eventKind);
    if (eventKinds.length >= maxEventKinds) {
      break;
    }
  }
  return eventKinds;
}

int _clampOffset(int value, int documentLength) {
  return value.clamp(0, documentLength).toInt();
}

List<DocumentState> _workspaceDocumentSamplesWithActive({
  required DocumentState activeDocument,
  required Iterable<DocumentState> workspaceDocuments,
}) {
  return <DocumentState>[
    activeDocument,
    for (final document in workspaceDocuments)
      if (document.documentId != activeDocument.documentId) document,
  ];
}

String _normalizeWorkspacePath(String path) {
  return path.replaceAll('\\', '/');
}

List<String> _pathsWithBasename(
  List<String> paths,
  String basename,
  int maxPaths,
) {
  return paths
      .where((path) => _pathBasename(path) == basename)
      .take(maxPaths)
      .toList(growable: false);
}

List<String> _pathsWithBasenames(
  List<String> paths,
  Set<String> basenames,
  int maxPaths,
) {
  return paths
      .where((path) => basenames.contains(_pathBasename(path)))
      .take(maxPaths)
      .toList(growable: false);
}

int _countPathsWithBasename(List<String> paths, String basename) {
  return paths.where((path) => _pathBasename(path) == basename).length;
}

int _countPathsWithBasenames(List<String> paths, Set<String> basenames) {
  return paths.where((path) => basenames.contains(_pathBasename(path))).length;
}

String _pathBasename(String path) {
  final normalized = _normalizeWorkspacePath(path);
  final lastSeparator = normalized.lastIndexOf('/');
  if (lastSeparator < 0) {
    return normalized;
  }
  return normalized.substring(lastSeparator + 1);
}

List<String> _buildSystemHints({
  required bool hasCompilationDatabase,
  required bool hasCMakeLists,
  required bool hasCMakePresets,
  required bool hasCMakeUserPresets,
  required bool hasNinjaBuild,
  required bool hasClangdConfig,
}) {
  return <String>[
    if (hasCompilationDatabase) 'compilation-database',
    if (hasCMakeLists) 'cmake',
    if (hasCMakePresets) 'cmake-presets',
    if (hasCMakeUserPresets) 'cmake-user-presets',
    if (hasNinjaBuild) 'ninja',
    if (hasClangdConfig) 'clangd',
  ];
}

List<String> _workspaceToolingHints({
  required bool hasCompilationDatabase,
  required bool hasCMakeLists,
  required bool hasCMakePresets,
  required bool hasCMakeUserPresets,
  required bool hasNinjaBuild,
  required bool hasClangdConfig,
  required bool hasClangFormatConfig,
  required bool hasClangTidyConfig,
  required bool hasCTestConfig,
}) {
  return <String>[
    ..._buildSystemHints(
      hasCompilationDatabase: hasCompilationDatabase,
      hasCMakeLists: hasCMakeLists,
      hasCMakePresets: hasCMakePresets,
      hasCMakeUserPresets: hasCMakeUserPresets,
      hasNinjaBuild: hasNinjaBuild,
      hasClangdConfig: hasClangdConfig,
    ),
    if (hasClangFormatConfig) 'clang-format',
    if (hasClangTidyConfig) 'clang-tidy',
    if (hasCTestConfig) 'ctest',
  ];
}

List<AgentWorkspaceSearchMatchContext> _searchDocumentForAgent({
  required DocumentState document,
  required String query,
}) {
  final matches = <AgentWorkspaceSearchMatchContext>[];
  final lowerQuery = query.toLowerCase();
  var lineStart = 0;
  var lineNumber = 1;
  while (lineStart <= document.text.length) {
    var lineEnd = document.text.indexOf('\n', lineStart);
    if (lineEnd < 0) {
      lineEnd = document.text.length;
    }
    final lineText = document.text.substring(lineStart, lineEnd);
    final lowerLine = lineText.toLowerCase();
    var matchStartInLine = lowerLine.indexOf(lowerQuery);
    while (matchStartInLine >= 0) {
      final start = lineStart + matchStartInLine;
      matches.add(
        AgentWorkspaceSearchMatchContext(
          documentId: document.documentId,
          lineNumber: lineNumber,
          start: start,
          end: start + query.length,
          lineText: _truncateSearchLine(lineText),
        ),
      );
      matchStartInLine = lowerLine.indexOf(
        lowerQuery,
        matchStartInLine + lowerQuery.length,
      );
    }
    if (lineEnd == document.text.length) {
      break;
    }
    lineStart = lineEnd + 1;
    lineNumber += 1;
  }
  return matches;
}

String _truncateSearchLine(String lineText, {int maxLength = 240}) {
  if (lineText.length <= maxLength) {
    return lineText;
  }
  return '${lineText.substring(0, maxLength)}...';
}
