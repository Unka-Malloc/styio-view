import '../../../ide/editor/editor.dart';
import '../../interaction/document_resource_binding.dart';
import '../workspace_file_lifecycle.dart';
import 'editor_workspace_state_controller.dart';
import 'workspace_document_controller.dart';

/// Owns the active-buffer save transaction and save-all orchestration.
final class WorkspacePersistenceController {
  const WorkspacePersistenceController({
    required this.editorController,
    required this.fileBinding,
    required this.editorWorkspaceState,
    required this.workspaceDocuments,
    required this.activeDocumentPath,
    required this.activeFilePath,
    required this.cacheDocument,
    required this.languageRefreshAvailable,
    required this.refreshLanguageService,
    required this.log,
  });

  final EditorSessionController editorController;
  final EditorDocumentResourceBinding fileBinding;
  final EditorWorkspaceStateController editorWorkspaceState;
  final WorkspaceDocumentController workspaceDocuments;
  final String Function() activeDocumentPath;
  final String Function() activeFilePath;
  final void Function(String documentId, DocumentState document) cacheDocument;
  final bool Function() languageRefreshAvailable;
  final Future<void> Function() refreshLanguageService;
  final void Function(String message) log;

  Future<DocumentResourceBindingSnapshot> saveActive() async {
    await executeActiveSave();
    return workspaceDocuments.completeActiveSave();
  }

  Future<void> executeActiveSave() async {
    final documentId = activeDocumentPath();
    final document = editorController.document;
    cacheDocument(documentId, document);
    fileBinding.markDocumentChanged(document);
    final saveResult = await fileBinding.save(document);
    if (!saveResult.saved) {
      editorWorkspaceState.markDirty(documentId);
      log(
        'Save blocked for ${activeFilePath()}: '
        '${saveResult.message ?? saveResult.failureKind?.name ?? 'unknown failure'}.',
      );
      return;
    }
    editorWorkspaceState.clearDirty(documentId);
    log(
      'Save requested for ${activeFilePath()} '
      '(rev ${document.revision}).',
    );
    if (saveResult.snapshot.state == DocumentResourceBindingState.boundClean) {
      await _refreshLanguageServiceAfterSave(activeFilePath());
    }
  }

  Future<WorkspaceSaveAllResult> saveAll() =>
      workspaceDocuments.saveAll(saveActive: saveActive);

  Future<WorkspaceFileCloseRequestResult?> saveAndCloseRequested() =>
      workspaceDocuments.saveAndCloseRequested(saveActive: saveActive);

  Future<void> _refreshLanguageServiceAfterSave(String documentId) async {
    if (!languageRefreshAvailable()) {
      return;
    }
    try {
      await refreshLanguageService();
      log('Language service refresh requested after saving $documentId.');
    } on Object catch (error) {
      log('Language service refresh failed after saving $documentId: $error');
    }
  }
}
