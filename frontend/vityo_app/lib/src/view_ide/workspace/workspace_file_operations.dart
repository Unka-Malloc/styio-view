import '../editor/document_state.dart';
import 'workspace_controller.dart';
import 'workspace_document_store_types.dart';

enum WorkspaceFileOperationKind { create, rename, delete, reveal }

extension WorkspaceFileOperationKindX on WorkspaceFileOperationKind {
  String get wireValue {
    return switch (this) {
      WorkspaceFileOperationKind.create => 'create',
      WorkspaceFileOperationKind.rename => 'rename',
      WorkspaceFileOperationKind.delete => 'delete',
      WorkspaceFileOperationKind.reveal => 'reveal',
    };
  }
}

class WorkspaceFileOperationResult {
  const WorkspaceFileOperationResult({
    required this.kind,
    required this.applied,
    this.path = '',
    this.nextPath = '',
    this.message = '',
  });

  final WorkspaceFileOperationKind kind;
  final bool applied;
  final String path;
  final String nextPath;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'applied': applied,
      if (path.isNotEmpty) 'path': path,
      if (nextPath.isNotEmpty) 'nextPath': nextPath,
      if (message.isNotEmpty) 'message': message,
    };
  }
}

class WorkspaceFileOperationService {
  const WorkspaceFileOperationService({
    required this.workspaceController,
    required this.documentStore,
  });

  final WorkspaceController workspaceController;
  final WorkspaceDocumentStore documentStore;

  Future<WorkspaceFileOperationResult> createFile({
    required String path,
    String text = '',
    bool open = false,
  }) async {
    final normalizedPath = _normalizeWorkspaceFilePath(path);
    final pathFailure = _validateWorkspaceFilePath(normalizedPath);
    if (pathFailure != null) {
      return _blocked(WorkspaceFileOperationKind.create, path, pathFailure);
    }
    if (await documentStore.documentExists(normalizedPath) ||
        workspaceController.files.contains(normalizedPath)) {
      return _blocked(
        WorkspaceFileOperationKind.create,
        normalizedPath,
        'Workspace file already exists.',
      );
    }
    await documentStore.saveDocument(
      DocumentState(documentId: normalizedPath, text: text, revision: 1),
    );
    workspaceController.registerFile(normalizedPath, open: open);
    return WorkspaceFileOperationResult(
      kind: WorkspaceFileOperationKind.create,
      applied: true,
      path: normalizedPath,
      message: 'Workspace file created.',
    );
  }

  Future<WorkspaceFileOperationResult> renameFile({
    required String path,
    required String nextPath,
    bool open = false,
  }) async {
    final normalizedPath = _normalizeWorkspaceFilePath(path);
    final normalizedNextPath = _normalizeWorkspaceFilePath(nextPath);
    final pathFailure =
        _validateWorkspaceFilePath(normalizedPath) ??
        _validateWorkspaceFilePath(normalizedNextPath);
    if (pathFailure != null) {
      return _blocked(WorkspaceFileOperationKind.rename, path, pathFailure);
    }
    if (normalizedPath == normalizedNextPath) {
      return WorkspaceFileOperationResult(
        kind: WorkspaceFileOperationKind.rename,
        applied: false,
        path: normalizedPath,
        nextPath: normalizedNextPath,
        message: 'Workspace file rename skipped: path did not change.',
      );
    }
    if (!await documentStore.documentExists(normalizedPath)) {
      return _blocked(
        WorkspaceFileOperationKind.rename,
        normalizedPath,
        'Workspace file does not exist.',
      );
    }
    if (await documentStore.documentExists(normalizedNextPath) ||
        workspaceController.files.contains(normalizedNextPath)) {
      return _blocked(
        WorkspaceFileOperationKind.rename,
        normalizedPath,
        'Target workspace file already exists.',
        nextPath: normalizedNextPath,
      );
    }

    final document = await documentStore.loadDocument(normalizedPath);
    await documentStore.saveDocument(
      DocumentState(
        documentId: normalizedNextPath,
        text: document.text,
        revision: document.revision + 1,
      ),
    );
    await documentStore.deleteDocument(normalizedPath);
    final shouldOpen = open || workspaceController.activeFilePath == normalizedPath;
    workspaceController.unregisterFile(normalizedPath);
    workspaceController.registerFile(normalizedNextPath, open: shouldOpen);
    return WorkspaceFileOperationResult(
      kind: WorkspaceFileOperationKind.rename,
      applied: true,
      path: normalizedPath,
      nextPath: normalizedNextPath,
      message: 'Workspace file renamed.',
    );
  }

  Future<WorkspaceFileOperationResult> deleteFile(String path) async {
    final normalizedPath = _normalizeWorkspaceFilePath(path);
    final pathFailure = _validateWorkspaceFilePath(normalizedPath);
    if (pathFailure != null) {
      return _blocked(WorkspaceFileOperationKind.delete, path, pathFailure);
    }
    if (!await documentStore.documentExists(normalizedPath) &&
        !workspaceController.files.contains(normalizedPath)) {
      return _blocked(
        WorkspaceFileOperationKind.delete,
        normalizedPath,
        'Workspace file does not exist.',
      );
    }
    await documentStore.deleteDocument(normalizedPath);
    workspaceController.unregisterFile(normalizedPath);
    return WorkspaceFileOperationResult(
      kind: WorkspaceFileOperationKind.delete,
      applied: true,
      path: normalizedPath,
      message: 'Workspace file deleted.',
    );
  }

  WorkspaceFileOperationResult revealFile(String path) {
    final normalizedPath = _normalizeWorkspaceFilePath(path);
    final pathFailure = _validateWorkspaceFilePath(normalizedPath);
    if (pathFailure != null) {
      return _blocked(WorkspaceFileOperationKind.reveal, path, pathFailure);
    }
    if (!workspaceController.files.contains(normalizedPath)) {
      return _blocked(
        WorkspaceFileOperationKind.reveal,
        normalizedPath,
        'Workspace file is not part of the project file list.',
      );
    }
    workspaceController.openFile(normalizedPath);
    return WorkspaceFileOperationResult(
      kind: WorkspaceFileOperationKind.reveal,
      applied: true,
      path: normalizedPath,
      message: 'Workspace file revealed.',
    );
  }

  WorkspaceFileOperationResult _blocked(
    WorkspaceFileOperationKind kind,
    String path,
    String message, {
    String nextPath = '',
  }) {
    return WorkspaceFileOperationResult(
      kind: kind,
      applied: false,
      path: path,
      nextPath: nextPath,
      message: message,
    );
  }
}

String _normalizeWorkspaceFilePath(String path) {
  return path.trim().replaceAll('\\', '/');
}

String? _validateWorkspaceFilePath(String path) {
  if (path.isEmpty) {
    return 'Workspace file path is empty.';
  }
  if (path.startsWith('/') || path.contains('..')) {
    return 'Workspace file path must stay inside the workspace.';
  }
  return null;
}
