// ignore_for_file: annotate_overrides

part of '../shell_runtime_model.dart';

/// Public semantic telemetry facade backed by its domain controller.
mixin ShellRuntimeSemanticTelemetryFacade on ShellRuntimeFacadeHost {
  SemanticSnapshotPanelEventStateController
  get semanticPanelEventStateController =>
      _semanticTelemetryController.panelStateController;
  SemanticSnapshotPanelEventStore? get semanticPanelEventStore =>
      _semanticTelemetryController.panelEventStore;
  String get semanticPanelEventWorkspaceId =>
      _semanticTelemetryController.panelWorkspaceId;
  WorkspaceQuickFixTelemetryStore? get workspaceQuickFixTelemetryStore =>
      _semanticTelemetryController.quickFixTelemetryStore;
  String get workspaceQuickFixTelemetryWorkspaceId =>
      _semanticTelemetryController.quickFixWorkspaceId;

  SemanticSnapshotPanelViewModel? semanticPanelViewModelFor(
    SemanticSnapshotPanelEventTarget target,
  ) => _semanticTelemetryController.panelViewModelFor(target);

  SemanticSnapshotPanelViewModel? get semanticProblemsPanelViewModel =>
      semanticPanelViewModelFor(SemanticSnapshotPanelEventTarget.problems);
  SemanticSnapshotPanelViewModel? get semanticRefactorPanelViewModel =>
      semanticPanelViewModelFor(SemanticSnapshotPanelEventTarget.refactor);
  List<SemanticSnapshotPanelViewModel> get semanticPanelViewModels =>
      _semanticTelemetryController.panelViewModels;

  Future<List<SemanticSnapshotPanelEventState>> restoreSemanticPanelEvents({
    String? workspaceId,
  }) =>
      _semanticTelemetryController.restorePanelEvents(workspaceId: workspaceId);

  Future<SemanticSnapshotPanelEventState> recordSemanticPanelEvent(
    SemanticSnapshotPanelEvent event, {
    String? workspaceId,
    int? maxEvents,
  }) => _semanticTelemetryController.recordPanelEvent(
    event,
    workspaceId: workspaceId,
    maxEvents: maxEvents,
  );

  Future<SemanticSnapshotPanelEvent?> recordSemanticRuntimeOutputEvent(
    RuntimeOutputEvent event, {
    bool publishToRuntimeOutput = true,
  }) => _semanticTelemetryController.recordRuntimeOutputEvent(
    event,
    publishToRuntimeOutput: publishToRuntimeOutput,
  );

  WorkspaceQuickFixTelemetrySnapshot? get workspaceQuickFixTelemetrySnapshot =>
      _semanticTelemetryController.quickFixTelemetrySnapshot;

  Future<WorkspaceQuickFixTelemetrySnapshot> restoreWorkspaceQuickFixTelemetry({
    String? workspaceId,
  }) => _semanticTelemetryController.restoreQuickFixTelemetry(
    workspaceId: workspaceId,
  );

  Future<WorkspaceQuickFixTelemetrySnapshot> recordWorkspaceQuickFixOutcome(
    WorkspaceQuickFixReviewOutcome outcome, {
    int maxOutcomes = 50,
  }) => _semanticTelemetryController.recordQuickFixOutcome(
    outcome,
    maxOutcomes: maxOutcomes,
  );
}
