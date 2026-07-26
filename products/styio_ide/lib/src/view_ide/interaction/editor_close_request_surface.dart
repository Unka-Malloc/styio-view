enum EditorCloseRequestSurfaceStatus {
  closed,
  blockedUnsavedChanges,
  notOpen,
}

class EditorCloseRequestSurface {
  const EditorCloseRequestSurface({
    required this.status,
    required this.filePath,
    required this.message,
    this.canSave = false,
    this.canDiscard = false,
    this.canSwitchToFile = false,
  });

  final EditorCloseRequestSurfaceStatus status;
  final String filePath;
  final String message;
  final bool canSave;
  final bool canDiscard;
  final bool canSwitchToFile;

  bool get requiresUserChoice =>
      status == EditorCloseRequestSurfaceStatus.blockedUnsavedChanges;
}
