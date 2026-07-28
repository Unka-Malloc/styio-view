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
