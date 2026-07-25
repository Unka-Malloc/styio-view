// ignore_for_file: annotate_overrides

part of '../shell_runtime_model.dart';

/// Public workspace-document lifecycle facade backed by focused controllers.
mixin ShellRuntimeWorkspaceDocumentFacade on ShellRuntimeFacadeHost {
  WorkspaceFileCommandRouteResult?
  get pendingWorkspaceFileCommandConfirmation =>
      _workspaceFileCommandController.pendingConfirmation;

  List<String> get cachedDocumentPaths =>
      _editorWorkspaceStateController.cachedDocumentPaths;
  List<String> get dirtyDocumentPaths =>
      _editorWorkspaceStateController.dirtyDocumentPaths;
  DocumentResourceBindingSnapshot get editorFileBindingSnapshot =>
      _editorFileBinding.snapshot;
  WorkspaceFileCloseRequestResult? get lastCloseRequestResult =>
      _workspaceDocumentController.lastCloseRequest;

  EditorCloseRequestSurface? get closeRequestSurface {
    final result = _workspaceDocumentController.lastCloseRequest;
    if (result == null) {
      return null;
    }
    if (result.requiresUserChoice &&
        !_editorWorkspaceStateController.isDirty(result.filePath)) {
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

  DocumentResourceBindingSnapshot markEditorResourceExternalChanged(
    DocumentState externalDocument,
  ) => _workspaceDocumentController.markExternalChanged(externalDocument);

  DocumentResourceBindingSnapshot acceptEditorExternalChange() =>
      _workspaceDocumentController.acceptExternalChange();

  WorkspaceFileCloseRequestResult requestCloseWorkspaceFile(String filePath) =>
      _workspaceDocumentController.requestClose(filePath);

  void clearCloseRequestResult() =>
      _workspaceDocumentController.clearCloseRequest();

  void switchToCloseRequestFile() =>
      _workspaceDocumentController.switchToCloseRequestFile();

  Future<DocumentResourceBindingSnapshot> saveActiveWorkspaceFileChanges() =>
      _workspacePersistenceController.saveActive();

  Future<WorkspaceSaveAllResult> saveAllWorkspaceFileChanges() =>
      _workspacePersistenceController.saveAll();

  Future<WorkspaceFileCloseRequestResult?>
  saveAndCloseRequestedWorkspaceFile() =>
      _workspacePersistenceController.saveAndCloseRequested();

  Future<DocumentResourceBindingSnapshot> discardActiveWorkspaceFileChanges() =>
      _workspaceDocumentController.discardActiveChanges();

  Future<WorkspaceFileCloseRequestResult?>
  discardAndCloseRequestedWorkspaceFile() =>
      _workspaceDocumentController.discardAndCloseRequested();

  Future<WorkspaceFileCommandRouteResult?>
  confirmPendingWorkspaceFileCommand() =>
      _workspaceFileConfirmationController.confirm();

  WorkspaceFileCommandRouteResult? cancelPendingWorkspaceFileCommand() =>
      _workspaceFileConfirmationController.cancel();

  Future<void> persistEditorSession({String key = 'default'}) =>
      _workspaceDocumentController.persistSession(key: key);

  Future<EditorSessionSnapshot?> restoreEditorSession({
    String key = 'default',
  }) => _workspaceDocumentController.restoreSession(key: key);
}
