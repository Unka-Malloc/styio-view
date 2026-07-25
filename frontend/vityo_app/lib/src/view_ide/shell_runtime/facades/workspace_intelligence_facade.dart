// ignore_for_file: annotate_overrides

part of '../shell_runtime_model.dart';

/// Public workspace diagnostics, navigation, refactor, and edit facade.
mixin ShellRuntimeWorkspaceIntelligenceFacade on ShellRuntimeFacadeHost {
  WorkspaceDiagnosticsSnapshot? get workspaceDiagnosticsSnapshot =>
      _workspaceDiagnosticsRuntimeController.snapshot;
  WorkspaceDiagnosticsController? get workspaceDiagnosticsController =>
      _workspaceDiagnosticsRuntimeController.controller;
  List<WorkspaceDiagnosticsProducerLifecycleSnapshot>
  get diagnosticsProducerLifecycles =>
      _workspaceDiagnosticsRuntimeController.producerLifecycles;
  WorkspaceEditPreview? get lastWorkspaceEditPreview =>
      _workspaceQuickFixController.lastPreview;
  WorkspaceEditApplyResultViewModel? get lastWorkspaceEditApplyResult =>
      _workspaceQuickFixController.lastApplyResult;
  WorkspaceReplacePreview? get lastWorkspaceReplacePreview =>
      _workspaceReplaceController.lastPreview;

  Future<WorkspaceDiagnosticsProducerLifecycleSnapshot?>
  cancelWorkspaceDiagnosticsProducer(
    WorkspaceDiagnosticsProducerLifecycleSnapshot snapshot,
  ) => _workspaceDiagnosticsRuntimeController.cancelProducer(snapshot);

  Future<WorkspaceDiagnosticsSnapshot> refreshWorkspaceDiagnostics() async {
    final snapshot = await _workspaceDiagnosticsRuntimeController.refresh();
    _semanticTelemetryController.recordWorkspaceDiagnostics(
      snapshot: snapshot,
      activeDocumentId: editorController.document.documentId,
      message: _workspaceDiagnosticsRefreshMessage(snapshot),
    );
    return snapshot;
  }

  String _workspaceDiagnosticsRefreshMessage(
    WorkspaceDiagnosticsSnapshot snapshot,
  ) => _workspaceDiagnosticsRuntimeController.refreshMessage(snapshot);

  Future<List<StyioProjectWorkspaceFix>> collectProjectWorkspaceQuickFixes() =>
      _workspaceQuickFixController.collect();

  Future<bool> applyFirstProjectWorkspaceQuickFix({
    String? expectedPreviewPlanId,
  }) => _workspaceQuickFixController.applyFirst(
    expectedPreviewPlanId: expectedPreviewPlanId,
  );

  Future<WorkspaceEditPreview?> previewFirstProjectWorkspaceQuickFix() =>
      _workspaceQuickFixController.previewFirst();

  void _publishDiagnosticActionTelemetry({
    required String action,
    required bool succeeded,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => _semanticTelemetryController.publishDiagnosticAction(
    action: action,
    succeeded: succeeded,
    message: message,
    metadata: metadata,
  );

  Future<bool> renameSymbolAtSelection(String newName) =>
      _workspaceRenameController.renameAtSelection(newName);

  Future<void> _recordRenameSafetyTelemetry({
    required bool safe,
    required String newName,
    required String message,
    String targetName = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) => recordSemanticPanelEvent(
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
      _notifyShellListeners();
      return false;
    }
    if (await _workspaceDocumentController.openWorkspaceFile(normalizedPath)) {
      appendLog('Agent command openWorkspaceFile opened $normalizedPath.');
      _notifyShellListeners();
      return true;
    }
    appendLog('Agent command openWorkspaceFile failed for $normalizedPath.');
    _notifyShellListeners();
    return false;
  }

  Future<bool> selectWorkspaceDiagnostic(WorkspaceDiagnostic entry) =>
      _workspaceNavigationController.selectDiagnostic(entry);
  Future<bool> goToProjectDefinitionAtSelection() =>
      _workspaceNavigationController.goToDefinition();
  Future<bool> selectProjectReferenceAtSelection({required bool forward}) =>
      _workspaceNavigationController.selectReference(forward: forward);
  Future<bool> searchWorkspaceForAgent(String query) =>
      _workspaceSearchController.search(query);

  Future<WorkspaceReplacePreview?> previewWorkspaceReplace({
    required String query,
    required String replacement,
  }) => _workspaceReplaceController.preview(
    query: query,
    replacement: replacement,
  );

  Future<WorkspaceReplaceResult?> applyWorkspaceReplacePreview(
    WorkspaceReplacePreview preview,
  ) => _workspaceReplaceController.apply(preview);
}
