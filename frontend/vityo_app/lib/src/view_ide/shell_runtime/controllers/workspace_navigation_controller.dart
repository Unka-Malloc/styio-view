import 'package:flutter/foundation.dart';

import '../../editor/editor.dart';
import '../../language/service/service.dart';
import '../../workspace/workspace.dart';

/// Owns project document loading and cross-document navigation.
final class WorkspaceNavigationController extends ChangeNotifier {
  WorkspaceNavigationController({
    required this.workspaceController,
    required this.documentStore,
    required this.editorController,
    required this.languageService,
    required this.documentSamples,
    required this.openWorkspaceFile,
    required this.log,
  });

  final WorkspaceController workspaceController;
  final WorkspaceDocumentStore documentStore;
  final EditorSessionController editorController;
  final ProjectStyioLanguageService languageService;
  final List<DocumentState> Function() documentSamples;
  final Future<bool> Function(String filePath) openWorkspaceFile;
  final void Function(String message) log;

  Future<List<DocumentState>> loadDocuments() async {
    final documentsById = <String, DocumentState>{
      for (final document in documentSamples()) document.documentId: document,
    };
    for (final filePath in workspaceController.files) {
      if (documentsById.containsKey(filePath) ||
          !await documentStore.documentExists(filePath)) {
        continue;
      }
      documentsById[filePath] = await documentStore.loadDocument(filePath);
    }
    return documentsById.values.toList(growable: false);
  }

  Future<bool> selectDiagnostic(WorkspaceDiagnostic entry) async {
    final opened = entry.documentId == editorController.document.documentId
        ? true
        : await openWorkspaceFile(entry.documentId);
    if (!opened) {
      log(
        'Workspace diagnostic selection skipped: ${entry.documentId} could not be opened.',
      );
      notifyListeners();
      return false;
    }
    editorController.selectRange(
      baseOffset: entry.diagnostic.range.start,
      extentOffset: entry.diagnostic.range.end,
    );
    log(
      'Workspace diagnostic selected: ${entry.diagnostic.code} in ${entry.documentId}.',
    );
    notifyListeners();
    return true;
  }

  Future<bool> goToDefinition() async {
    final activeDocumentId = editorController.document.documentId;
    final definitions = languageService.definitionsAt(
      documents: await loadDocuments(),
      documentId: activeDocumentId,
      offset: editorController.selection.extentOffset,
    );
    if (definitions.isEmpty) {
      log(
        'Project definition skipped: no visible project definition at selection.',
      );
      notifyListeners();
      return false;
    }
    final definition = definitions.first;
    if (definition.documentId != workspaceController.activeFilePath &&
        !await openWorkspaceFile(definition.documentId)) {
      log(
        'Project definition skipped: ${definition.documentId} could not be opened.',
      );
      notifyListeners();
      return false;
    }
    editorController.selectRange(
      baseOffset: definition.range.start,
      extentOffset: definition.range.end,
    );
    log(
      'Project definition selected: ${definition.name} in ${definition.documentId}.',
    );
    notifyListeners();
    return true;
  }

  Future<bool> selectReference({required bool forward}) async {
    final activeDocumentId = editorController.document.documentId;
    final offset = editorController.selection.extentOffset;
    final references =
        languageService
            .referencesAt(
              documents: await loadDocuments(),
              documentId: activeDocumentId,
              offset: offset,
            )
            .toList(growable: false)
          ..sort(compareReferences);
    if (references.isEmpty) {
      log(
        'Project reference skipped: no visible project references at selection.',
      );
      notifyListeners();
      return false;
    }
    final target = _navigationTarget(
      references: references,
      activeDocumentId: activeDocumentId,
      offset: offset,
      forward: forward,
    );
    if (target.documentId != editorController.document.documentId &&
        !await openWorkspaceFile(target.documentId)) {
      log(
        'Project reference skipped: ${target.documentId} could not be opened.',
      );
      notifyListeners();
      return false;
    }
    editorController.selectRange(
      baseOffset: target.range.start,
      extentOffset: target.range.end,
    );
    log('Project reference selected: ${target.name} in ${target.documentId}.');
    notifyListeners();
    return true;
  }

  StyioProjectSymbolReference _navigationTarget({
    required List<StyioProjectSymbolReference> references,
    required String activeDocumentId,
    required int offset,
    required bool forward,
  }) {
    final currentIndex = references.indexWhere(
      (reference) =>
          reference.documentId == activeDocumentId &&
          (reference.range.contains(offset) || offset == reference.range.end),
    );
    if (currentIndex >= 0) {
      final targetIndex = forward
          ? (currentIndex + 1) % references.length
          : (currentIndex - 1 + references.length) % references.length;
      return references[targetIndex];
    }
    if (forward) {
      return references.firstWhere(
        (reference) =>
            _comparePosition(
              reference.documentId,
              reference.range.start,
              activeDocumentId,
              offset,
            ) >
            0,
        orElse: () => references.first,
      );
    }
    return references.lastWhere(
      (reference) =>
          _comparePosition(
            reference.documentId,
            reference.range.end,
            activeDocumentId,
            offset,
          ) <
          0,
      orElse: () => references.last,
    );
  }

  int compareReferences(
    StyioProjectSymbolReference left,
    StyioProjectSymbolReference right,
  ) {
    final documentCompare = left.documentId.compareTo(right.documentId);
    if (documentCompare != 0) {
      return documentCompare;
    }
    final startCompare = left.range.start.compareTo(right.range.start);
    return startCompare != 0
        ? startCompare
        : left.range.end.compareTo(right.range.end);
  }

  int _comparePosition(
    String leftDocumentId,
    int leftOffset,
    String rightDocumentId,
    int rightOffset,
  ) {
    final documentCompare = leftDocumentId.compareTo(rightDocumentId);
    return documentCompare != 0
        ? documentCompare
        : leftOffset.compareTo(rightOffset);
  }
}
