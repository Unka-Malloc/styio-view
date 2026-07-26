part of '../shell_runtime_model.dart';

/// Public source-control facade backed by the domain controller.
mixin ShellRuntimeSourceControlFacade on ShellRuntimeFacadeHost {
  SourceControlStatusController? get sourceControlStatusController =>
      _sourceControlController.statusController;

  SourceControlStatusSnapshot get sourceControlStatusSnapshot =>
      _sourceControlController.statusSnapshot;
  SourceControlDiffSnapshot? get sourceControlDiffPreview =>
      _sourceControlController.diffPreview;
  SourceControlBranchSnapshot? get sourceControlBranchSnapshot =>
      _sourceControlController.branchSnapshot;
  SourceControlHistorySnapshot? get sourceControlHistorySnapshot =>
      _sourceControlController.historySnapshot;
  SourceControlPartialPatchResult? get sourceControlHunkActionResult =>
      _sourceControlController.hunkActionResult;
  SourceControlCommitDraft? get sourceControlCommitDraft =>
      _sourceControlController.commitDraft;
  SourceControlCommitDialogState? get sourceControlCommitDialogState =>
      _sourceControlController.commitDialogState;

  Future<SourceControlStatusSnapshot> refreshSourceControlStatus() =>
      _sourceControlController.refreshStatus();

  Future<SourceControlDiffSnapshot> previewSourceControlDiff(String path) =>
      _sourceControlController.previewDiff(path);

  Future<SourceControlActionResult> runSourceControlAction(
    SourceControlActionRequest request,
  ) => _sourceControlController.runAction(request);

  Future<SourceControlActionResult> stageSourceControlPaths(
    List<String> paths,
  ) => runSourceControlAction(
    SourceControlActionRequest(
      kind: SourceControlActionKind.stage,
      paths: paths,
    ),
  );

  Future<SourceControlActionResult> unstageSourceControlPaths(
    List<String> paths,
  ) => runSourceControlAction(
    SourceControlActionRequest(
      kind: SourceControlActionKind.unstage,
      paths: paths,
    ),
  );

  Future<SourceControlBranchSnapshot> refreshSourceControlBranches() =>
      _sourceControlController.refreshBranches();

  Future<SourceControlBranchSwitchPlan> planSourceControlBranchSwitch(
    String targetBranch,
  ) => _sourceControlController.planBranchSwitch(targetBranch);

  SourceControlCommitDraft planSourceControlCommitDraft({
    required String message,
    List<String>? selectedPaths,
    bool openDialog = true,
  }) => _sourceControlController.planCommitDraft(
    message: message,
    selectedPaths: selectedPaths,
    openDialog: openDialog,
  );

  Future<SourceControlActionResult> confirmSourceControlDiffAction(
    SourceControlDiffConfirmationPlan plan,
  ) => _sourceControlController.confirmDiffAction(plan);

  Future<SourceControlPartialPatchResult> confirmSourceControlHunkAction(
    SourceControlDiffHunkActionPlan plan,
  ) => _sourceControlController.confirmHunkAction(plan);

  Future<void> planSourceControlHunkAction(
    SourceControlDiffHunkActionPlan plan,
  ) => _sourceControlController.planHunkAction(plan);

  Future<SourceControlPartialPatchResult>
  confirmPendingSourceControlHunkDiscard() =>
      _sourceControlController.confirmPendingHunkDiscard();
}
