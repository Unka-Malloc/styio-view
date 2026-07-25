import 'package:flutter/foundation.dart';

import '../../editor/editor.dart';
import '../../workspace/workspace.dart';
import 'editor_workspace_state_controller.dart';

/// Owns reviewed workspace replace previews and their application lifecycle.
final class WorkspaceReplaceController extends ChangeNotifier {
  WorkspaceReplaceController({
    required this.workspaceController,
    required this.documentStore,
    required this.editorController,
    required this.editorWorkspaceState,
    required this.log,
  });

  final WorkspaceController workspaceController;
  final WorkspaceDocumentStore documentStore;
  final EditorSessionController editorController;
  final EditorWorkspaceStateController editorWorkspaceState;
  final void Function(String message) log;

  WorkspaceReplacePreview? _lastPreview;

  WorkspaceReplacePreview? get lastPreview => _lastPreview;

  Future<WorkspaceReplacePreview?> preview({
    required String query,
    required String replacement,
  }) async {
    final normalizedQuery = query.trim();
    if (normalizedQuery.isEmpty) {
      log('Workspace replace preview skipped: missing search query.');
      return null;
    }
    final preview = await WorkspaceSearchService(documentStore: documentStore)
        .previewReplaceAll(
          documentIds: workspaceController.files,
          query: normalizedQuery,
          replacement: replacement,
        );
    _lastPreview = preview;
    log(
      'Workspace replace preview found ${preview.replacementCount} '
      'replacement(s) across ${preview.documents.length} document(s).',
    );
    notifyListeners();
    return preview;
  }

  Future<WorkspaceReplaceResult?> apply(WorkspaceReplacePreview preview) async {
    if (preview.documents.isEmpty) {
      log('Workspace replace apply skipped: no preview changes.');
      return null;
    }
    final result = await WorkspaceSearchService(
      documentStore: documentStore,
    ).applyReplacePreview(preview);
    for (final document in result.documents) {
      editorWorkspaceState
        ..removeDocument(document.documentId)
        ..markDirty(document.documentId);
    }
    final activePath = workspaceController.activeFilePath;
    WorkspaceReplacePreviewDocument? activePreviewDocument;
    for (final document in preview.documents) {
      if (document.documentId == activePath &&
          result.documents.any(
            (applied) => applied.documentId == document.documentId,
          )) {
        activePreviewDocument = document;
        break;
      }
    }
    if (activePreviewDocument != null) {
      editorController.loadDocument(
        DocumentState(
          documentId: activePreviewDocument.documentId,
          text: activePreviewDocument.afterText,
          revision: activePreviewDocument.revision + 1,
        ),
      );
    }
    if (result.failures.isEmpty) {
      _lastPreview = null;
    }
    log(
      'Workspace replace apply changed ${result.replacementCount} '
      'replacement(s) across ${result.documents.length} document(s), '
      '${result.failures.length} failure(s).',
    );
    notifyListeners();
    return result;
  }
}
