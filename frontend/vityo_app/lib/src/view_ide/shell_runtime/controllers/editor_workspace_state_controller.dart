import '../../editor/editor.dart';
import '../../interaction/document_resource_binding.dart';

/// Owns cached workspace documents, dirty paths, and per-document selections.
final class EditorWorkspaceStateController {
  EditorWorkspaceStateController({required this.documentCacheLimit});

  final int documentCacheLimit;
  final Map<String, DocumentState> _documentCache = <String, DocumentState>{};
  final Set<String> _dirtyDocumentPaths = <String>{};
  final Map<String, int> _cursorOffsets = <String, int>{};
  final Map<String, int> _selectionAnchors = <String, int>{};

  List<String> get cachedDocumentPaths =>
      List<String>.unmodifiable(_documentCache.keys);
  List<String> get dirtyDocumentPaths =>
      List<String>.unmodifiable(_dirtyDocumentPaths);
  Iterable<MapEntry<String, DocumentState>> get cachedDocumentEntries =>
      List<MapEntry<String, DocumentState>>.unmodifiable(
        _documentCache.entries,
      );
  Map<String, int> get cursorOffsets =>
      Map<String, int>.unmodifiable(_cursorOffsets);
  Map<String, int> get selectionAnchors =>
      Map<String, int>.unmodifiable(_selectionAnchors);

  DocumentState? document(String documentId) => _documentCache[documentId];
  bool isDirty(String documentId) => _dirtyDocumentPaths.contains(documentId);

  void markDirty(String documentId) {
    _dirtyDocumentPaths.add(documentId);
  }

  void clearDirty(String documentId) {
    _dirtyDocumentPaths.remove(documentId);
  }

  void restoreDirtyDocuments(Iterable<String> documentIds) {
    _dirtyDocumentPaths
      ..clear()
      ..addAll(documentIds);
  }

  void restoreSelections({
    required Map<String, int> cursorOffsets,
    required Map<String, int> selectionAnchors,
  }) {
    _cursorOffsets
      ..clear()
      ..addAll(cursorOffsets);
    _selectionAnchors
      ..clear()
      ..addAll(selectionAnchors);
  }

  void removeDocument(String documentId) {
    _documentCache.remove(documentId);
    _cursorOffsets.remove(documentId);
    _selectionAnchors.remove(documentId);
  }

  void cacheDocument(
    String documentId,
    DocumentState document, {
    required String activeDocumentPath,
    required Iterable<String> openFilePaths,
  }) {
    _documentCache.remove(documentId);
    _documentCache[documentId] = document;
    if (documentCacheLimit <= 0) {
      return;
    }
    final openPaths = openFilePaths.toSet();
    while (_documentCache.length > documentCacheLimit) {
      String? evictableDocumentId;
      for (final candidate in _documentCache.keys) {
        if (candidate == activeDocumentPath ||
            openPaths.contains(candidate) ||
            _dirtyDocumentPaths.contains(candidate)) {
          continue;
        }
        evictableDocumentId = candidate;
        break;
      }
      if (evictableDocumentId == null) {
        return;
      }
      removeDocument(evictableDocumentId);
    }
  }

  void syncDirtyState(
    String filePath,
    DocumentResourceBindingSnapshot snapshot,
  ) {
    switch (snapshot.state) {
      case DocumentResourceBindingState.boundDirty:
      case DocumentResourceBindingState.conflicted:
        markDirty(filePath);
        return;
      case DocumentResourceBindingState.unbound:
      case DocumentResourceBindingState.binding:
      case DocumentResourceBindingState.boundClean:
      case DocumentResourceBindingState.externalChanged:
      case DocumentResourceBindingState.deletedOnDisk:
      case DocumentResourceBindingState.readonly:
      case DocumentResourceBindingState.providerUnavailable:
        clearDirty(filePath);
        return;
    }
  }

  void rememberSelection(
    String documentId,
    EditorSessionController editorController,
  ) {
    if (documentId.isEmpty) {
      return;
    }
    _cursorOffsets[documentId] = editorController.selection.extentOffset;
    _selectionAnchors[documentId] = editorController.selection.baseOffset;
  }

  void restoreSelection(
    String documentId,
    EditorSessionController editorController,
  ) {
    final cursorOffset = _cursorOffsets[documentId];
    final selectionAnchor = _selectionAnchors[documentId];
    if (cursorOffset != null && selectionAnchor != null) {
      editorController.selectRange(
        baseOffset: selectionAnchor,
        extentOffset: cursorOffset,
      );
    } else if (cursorOffset != null) {
      editorController.selectCollapsed(cursorOffset);
    }
  }
}
