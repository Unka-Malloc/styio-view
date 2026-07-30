import 'package:flutter/foundation.dart';

import '../../agent_client/agent.dart';
import '../../../ide/editor/editor.dart';
import '../../interaction/interaction.dart';
import '../../toolchain/toolchain_manager.dart';
import '../../../ide/workspace/workspace.dart';
import 'agent_controller.dart';
import 'debug_controller.dart';
import 'editor_workspace_state_controller.dart';
import 'execution_controller.dart';
import 'project_language_context_controller.dart';
import 'semantic_telemetry_controller.dart';
import 'source_control_controller.dart';
import 'testing_controller.dart';
import 'toolchain_controller.dart';
import 'workspace_diagnostics_runtime_controller.dart';
import 'workspace_quick_fix_controller.dart';

/// Composes the read-only, typed IDE facts exposed to coding agents.
final class AgentSessionContextController {
  const AgentSessionContextController({
    required this.editorController,
    required this.projectLanguageContext,
    required this.agentController,
    required this.workspaceQuickFixController,
    required this.debugController,
    required this.executionController,
    required this.workspaceController,
    required this.editorWorkspaceState,
    required this.workspaceDocuments,
    required this.workspaceDiagnostics,
    required this.sourceControlController,
    required this.testingController,
    required this.toolchainController,
    required this.semanticTelemetryController,
    required this.languageServiceStatus,
    required this.toolchainStatusReport,
    required this.agentCodingController,
    required this.refreshProviderProfiles,
    required this.log,
    required this.notify,
  });

  final EditorSessionController editorController;
  final ProjectLanguageContextController projectLanguageContext;
  final AgentController agentController;
  final WorkspaceQuickFixController workspaceQuickFixController;
  final DebugController debugController;
  final ExecutionController executionController;
  final WorkspaceController workspaceController;
  final EditorWorkspaceStateController editorWorkspaceState;
  final List<DocumentState> Function() workspaceDocuments;
  final WorkspaceDiagnosticsRuntimeController workspaceDiagnostics;
  final SourceControlController sourceControlController;
  final ShellTestingController testingController;
  final ToolchainController toolchainController;
  final SemanticTelemetryController semanticTelemetryController;
  final ValueListenable<LanguageServiceStatusSurface> languageServiceStatus;
  final ValueListenable<ToolchainManagerStatusReport>? toolchainStatusReport;
  final AgentCodingSessionController Function() agentCodingController;
  final Future<AgentPromptProfileManifest> Function() refreshProviderProfiles;
  final void Function(String message) log;
  final void Function() notify;

  AgentSessionContext build() => AgentSessionContext.fromEditorState(
    document: editorController.document,
    selection: editorController.selection,
    diagnostics: editorController.analysis.diagnostics,
    focusedDiagnostics: editorController.diagnosticsAtSelection,
    focusToken: editorController.tokenAtSelection,
    focusSemanticKind: editorController.semanticKindAtSelection,
    hover: projectLanguageContext.mergedHoverAtSelection,
    definition: editorController.definitionAtSelection,
    resolvedElement: editorController.resolvedElementAtSelection,
    resolvedReference: editorController.resolvedReferenceAtSelection,
    parameterInfo: editorController.parameterInfoAtSelection,
    safeDeletePlan: editorController.safeDeletePlanAtSelection,
    inlineVariablePlan: editorController.inlineVariablePlanAtSelection,
    surroundTemplates: editorController.surroundTemplatesAtSelection,
    references: editorController.referencesAtSelection,
    completions: projectLanguageContext.mergedCompletionsAtSelection,
    codeActions: editorController.contextActionsAtSelection,
    semanticSpans: editorController.analysis.semanticSpans,
    documentSymbols: editorController.analysis.documentSymbols,
    inlayHints: editorController.analysis.inlayHints,
    semanticBlocks: editorController.analysis.semanticBlocks,
    semanticFeatureMatrix: editorController.semanticFeatureMatrix,
    languageServiceStatus: languageServiceStatus.value,
    lastCommandResult: agentController.lastCommandResult,
    recentCommandResults: agentController.recentCommandResults,
    lastWorkspaceEditPreview: workspaceQuickFixController.lastPreview,
    lastWorkspaceEditApplyResult: workspaceQuickFixController.lastApplyResult,
    debug: debugController.agentContext,
    lastExecutionSession: executionController.lastExecutionSession,
    lastRuntimeEvents: executionController.lastRuntimeEvents,
    workspaceFiles: workspaceController.files,
    openDocumentIds: workspaceController.openFilePaths,
    dirtyDocumentIds: editorWorkspaceState.dirtyDocumentPaths,
    workspaceDocuments: workspaceDocuments(),
    lastWorkspaceSearch: agentController.lastWorkspaceSearch,
    lastWorkspaceSymbolSearch: agentController.lastWorkspaceSymbolSearch,
    workspaceDiagnostics: workspaceDiagnostics.snapshot,
    sourceControlStatus: sourceControlController.statusSnapshot,
    sourceControlDiff: sourceControlController.diffPreview,
    sourceControlContext:
        sourceControlController.statusController?.agentContextSnapshot,
    testDiscovery: testingController.discovery,
    lastTestRun: testingController.lastRun,
    testRunConfigurationSet: testingController.configurationSet,
    workspaceRoot: workspaceController.activeProject.workspaceRoot,
    activeFilePath: workspaceController.activeFilePath,
    toolchainSnapshot:
        toolchainStatusReport?.value.snapshot ??
        toolchainController.lastSnapshot,
    clangCppVersionPreference: toolchainController.clangCppVersionPreference,
    toolchainBootstrapSummary: toolchainController.bootstrapSummary,
    toolchainBootstrapActionDispatch:
        toolchainController.lastBootstrapActionDispatch,
    semanticPanelViewModels: semanticTelemetryController.panelViewModels,
    recoveryPlan: agentCodingController().sessionRecoveryPlan,
    savedProviderProfiles: agentController.providerProfileManifest.entries,
  );

  Future<Map<String, Object?>> collectCodingCheckpoint() async {
    final diagnosticsSnapshot = await workspaceDiagnostics.refresh();
    final sourceControlSnapshot = await sourceControlController.refreshStatus();
    final projectLanguage = await projectLanguageContext.collect();
    final profileManifest = await refreshProviderProfiles();
    final workspaceEditPreview = await workspaceQuickFixController
        .previewFirst();
    final dirtyPaths = editorWorkspaceState.dirtyDocumentPaths;
    final changedPath = sourceControlSnapshot.changes.isNotEmpty
        ? sourceControlSnapshot.changes.first.path
        : dirtyPaths.isNotEmpty
        ? dirtyPaths.first
        : '';
    final diffSnapshot = changedPath.isEmpty
        ? null
        : await sourceControlController.previewDiff(changedPath);
    final context = build();
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
      'dirtyDocumentIds': dirtyPaths,
      'openDocumentIds': workspaceController.openFilePaths,
      if (diffSnapshot != null) 'sourceControlDiff': diffSnapshot.toJson(),
      if (context.workspace.sourceControlContext != null)
        'sourceControlContext': context.workspace.sourceControlContext!
            .toJson(),
      if (workspaceEditPreview != null)
        'workspaceEditPreview': workspaceEditPreview.toJson(),
    };
    log(
      'Agent coding checkpoint collected: '
      '${diagnosticsSnapshot.totalCount} diagnostic(s), '
      '${sourceControlSnapshot.changes.length} source change(s), '
      '${projectLanguage['referenceCount'] ?? 0} project reference(s), '
      '${context.language.semanticFeatureMatrix?.codeActionFactCount ?? 0} code action fact(s), '
      '${workspaceEditPreview?.editCount ?? 0} workspace edit preview edit(s), '
      '${context.ideCapabilityClosure.runtimeMaturityBlockerCapabilityIds.length} maturity blocker(s).',
    );
    notify();
    return metadata;
  }
}
