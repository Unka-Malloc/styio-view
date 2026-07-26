import 'package:flutter/foundation.dart';

import '../../../ide/editor/editor.dart' hide WorkspaceEditSource;
import '../../language/language_contract.dart';
import '../../language/service/service.dart';
import '../../../ide/workspace/workspace.dart';
import 'editor_workspace_state_controller.dart';

typedef RenameSafetyRecorder =
    Future<void> Function({
      required bool safe,
      required String newName,
      required String message,
      required String targetName,
      required Map<String, Object?> metadata,
    });

/// Owns project rename validation, application, and safety evidence.
final class WorkspaceRenameController extends ChangeNotifier {
  WorkspaceRenameController({
    required this.languageService,
    required this.loadDocuments,
    required this.editorController,
    required this.documentStore,
    required this.editorWorkspaceState,
    required this.cacheDocument,
    required this.activeDocumentPath,
    required this.log,
    required this.recordSafety,
  });

  final ProjectStyioLanguageService languageService;
  final Future<List<DocumentState>> Function() loadDocuments;
  final EditorSessionController editorController;
  final WorkspaceDocumentStore documentStore;
  final EditorWorkspaceStateController editorWorkspaceState;
  final void Function(String documentId, DocumentState document) cacheDocument;
  final String Function() activeDocumentPath;
  final void Function(String message) log;
  final RenameSafetyRecorder recordSafety;

  Future<bool> renameAtSelection(String newName) async {
    final preview = languageService.renamePreviewAt(
      documents: await loadDocuments(),
      documentId: editorController.document.documentId,
      offset: editorController.selection.extentOffset,
      newName: newName,
    );
    if (preview != null) {
      final applied = await _applyProjectPreview(preview);
      await recordSafety(
        safe: applied,
        newName: preview.newName,
        targetName: preview.oldName,
        message: applied
            ? 'Rename ${preview.oldName} to ${preview.newName} is safe.'
            : 'Rename ${preview.oldName} to ${preview.newName} is blocked.',
        metadata: <String, Object?>{
          'editCount': preview.editCount,
          'documentCount': preview.editsByDocument.length,
          if (preview.conflict != null) 'conflict': preview.conflict,
        },
      );
      return applied;
    }
    if (editorController.applyRename(newName)) {
      final activePath = activeDocumentPath();
      cacheDocument(activePath, editorController.document);
      editorWorkspaceState.markDirty(activePath);
      log('Rename symbol applied at editor selection.');
      await recordSafety(
        safe: true,
        newName: newName,
        targetName: '',
        message: 'Rename to $newName is safe at editor selection.',
        metadata: const <String, Object?>{'scope': 'editor-selection'},
      );
      notifyListeners();
      return true;
    }
    log('Rename symbol skipped: no safe rename available at selection.');
    await recordSafety(
      safe: false,
      newName: newName,
      targetName: '',
      message: 'Rename to $newName is blocked at editor selection.',
      metadata: const <String, Object?>{'scope': 'editor-selection'},
    );
    notifyListeners();
    return false;
  }

  Future<bool> _applyProjectPreview(StyioProjectRenamePreview preview) async {
    if (preview.hasConflict) {
      log('Project rename skipped: ${preview.conflict ?? 'rename conflict'}.');
      notifyListeners();
      return false;
    }
    if (preview.editCount == 0) {
      log('Project rename skipped: no edits were produced.');
      notifyListeners();
      return false;
    }

    final activeDocumentId = editorController.document.documentId;
    final activeEdits = _formattingEdits(
      preview.editsByDocument[activeDocumentId] ?? const <SourceRange>[],
      preview.newName,
    );
    final normalizedActiveEdits = normalizeFormattingEditsForDocument(
      documentLength: editorController.document.length,
      edits: activeEdits,
    );
    if (normalizedActiveEdits.length != activeEdits.length) {
      log(
        'Project rename skipped: active document edits are invalid or overlapping.',
      );
      notifyListeners();
      return false;
    }

    final inactiveEditsByDocument = <String, List<FormattingEdit>>{
      for (final entry in preview.editsByDocument.entries)
        if (entry.key != activeDocumentId)
          entry.key: _formattingEdits(entry.value, preview.newName),
    };
    var inactiveEditCount = 0;
    if (inactiveEditsByDocument.isNotEmpty) {
      final result =
          await WorkspaceEditApplier(
            workspaceDocumentStore: documentStore,
          ).apply(
            WorkspaceEditPlan(
              id: 'project-rename-${_fingerprint(preview)}',
              summary:
                  'Rename ${preview.oldName} to ${preview.newName} across project.',
              source: WorkspaceEditSource.rename,
              editsByDocument: inactiveEditsByDocument,
            ),
          );
      if (!result.applied) {
        log('Project rename skipped: ${result.message}');
        notifyListeners();
        return false;
      }
      inactiveEditCount = result.appliedEditCount;
      for (final documentId in result.appliedDocumentIds) {
        editorWorkspaceState.removeDocument(documentId);
      }
    }

    if (normalizedActiveEdits.isNotEmpty) {
      editorController.applyFormattingEdits(normalizedActiveEdits);
      cacheDocument(activeDocumentId, editorController.document);
      editorWorkspaceState.markDirty(activeDocumentId);
    }
    log(
      'Project rename applied: ${preview.oldName} -> ${preview.newName} '
      'across ${preview.editsByDocument.length} document(s), '
      '${inactiveEditCount + normalizedActiveEdits.length} edit(s).',
    );
    notifyListeners();
    return true;
  }

  List<FormattingEdit> _formattingEdits(
    List<SourceRange> ranges,
    String newName,
  ) => ranges
      .map((range) => FormattingEdit(range: range, newText: newName))
      .toList(growable: false);

  String _fingerprint(StyioProjectRenamePreview preview) {
    final buffer = StringBuffer('${preview.oldName}->${preview.newName}');
    final entries = preview.editsByDocument.entries.toList(growable: false)
      ..sort((left, right) => left.key.compareTo(right.key));
    for (final entry in entries) {
      buffer.write('|${entry.key}');
      for (final range in entry.value) {
        buffer.write('@${range.start}-${range.end}');
      }
    }
    var hash = 0x811c9dc5;
    for (final unit in buffer.toString().codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }
}
