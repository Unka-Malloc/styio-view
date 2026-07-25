import 'dart:async';

import '../../editor/editor.dart';
import '../../interaction/document_resource_binding.dart';
import '../../workspace/workspace.dart';
import 'editor_workspace_state_controller.dart';
import '../workspace_file_lifecycle.dart';

/// Owns active workspace document loading and editor-session persistence.
final class WorkspaceDocumentController {
  WorkspaceDocumentController({
    required this.workspaceController,
    required this.editorController,
    required this.fileBinding,
    required this.documentStore,
    required this.state,
    required this.sessionStore,
    required this.sessionWorkspaceId,
    required this.log,
    required this.notify,
  }) : _activeDocumentPath = workspaceController.activeFilePath;

  final WorkspaceController workspaceController;
  final EditorSessionController editorController;
  final EditorDocumentResourceBinding fileBinding;
  final WorkspaceDocumentStore documentStore;
  final EditorWorkspaceStateController state;
  final EditorSessionDataStore? sessionStore;
  final String sessionWorkspaceId;
  final void Function(String message) log;
  final void Function() notify;

  String _activeDocumentPath;
  bool _suppressWorkspaceChangedLoad = false;
  bool _suppressSelectionTracking = false;
  int _loadGeneration = 0;
  WorkspaceFileCloseRequestResult? _lastCloseRequest;

  String get activeDocumentPath => _activeDocumentPath;
  WorkspaceFileCloseRequestResult? get lastCloseRequest => _lastCloseRequest;

  void handleWorkspaceChanged() {
    if (_suppressWorkspaceChangedLoad) {
      return;
    }
    unawaited(loadActiveDocument());
  }

  DocumentResourceBindingSnapshot handleDocumentChanged() {
    cacheDocument(_activeDocumentPath, editorController.document);
    rememberSelection(_activeDocumentPath);
    final snapshot = fileBinding.markDocumentChanged(editorController.document);
    state.syncDirtyState(_activeDocumentPath, snapshot);
    return snapshot;
  }

  void cacheDocument(String documentId, DocumentState document) {
    state.cacheDocument(
      documentId,
      document,
      activeDocumentPath: _activeDocumentPath,
      openFilePaths: workspaceController.openFilePaths,
    );
  }

  void rememberSelection(String documentId) {
    if (_suppressSelectionTracking) {
      return;
    }
    state.rememberSelection(documentId, editorController);
  }

  void restoreSelection(String documentId) {
    state.restoreSelection(documentId, editorController);
  }

  Future<void> loadActiveDocument() async {
    final loadGeneration = ++_loadGeneration;
    final currentDocument = editorController.document;
    if (currentDocument.documentId == _activeDocumentPath) {
      cacheDocument(_activeDocumentPath, currentDocument);
      rememberSelection(_activeDocumentPath);
      final currentSnapshot = fileBinding.markDocumentChanged(currentDocument);
      state.syncDirtyState(_activeDocumentPath, currentSnapshot);
    }
    final nextPath = workspaceController.activeFilePath;
    _activeDocumentPath = nextPath;
    final cachedDocument = state.document(nextPath);
    final openResult = cachedDocument == null
        ? await fileBinding.open(nextPath)
        : null;
    final nextDocument =
        cachedDocument ??
        openResult?.snapshot.document ??
        EditorSessionController.seedDocumentForPath(nextPath);
    if (loadGeneration != _loadGeneration ||
        _activeDocumentPath != nextPath ||
        workspaceController.activeFilePath != nextPath) {
      return;
    }
    if (cachedDocument != null) {
      fileBinding.bindLoadedDocument(cachedDocument);
    }
    final previousSelectionTracking = _suppressSelectionTracking;
    _suppressSelectionTracking = true;
    try {
      editorController.loadDocument(nextDocument);
    } finally {
      _suppressSelectionTracking = previousSelectionTracking;
    }
    restoreSelection(nextPath);
    log(
      'Project route -> ${workspaceController.activeProject.title} / '
      '${workspaceController.activeFilePath}',
    );
  }

  Future<bool> openWorkspaceFile(String filePath) async {
    _runWithoutWorkspaceLoad(() => workspaceController.openFile(filePath));
    await loadActiveDocument();
    return workspaceController.activeFilePath == filePath &&
        editorController.document.documentId == filePath;
  }

  bool get activeFileHasUnsavedChanges {
    switch (fileBinding.snapshot.state) {
      case DocumentResourceBindingState.boundDirty:
      case DocumentResourceBindingState.conflicted:
        return true;
      case DocumentResourceBindingState.unbound:
      case DocumentResourceBindingState.binding:
      case DocumentResourceBindingState.boundClean:
      case DocumentResourceBindingState.externalChanged:
      case DocumentResourceBindingState.deletedOnDisk:
      case DocumentResourceBindingState.readonly:
      case DocumentResourceBindingState.providerUnavailable:
        return false;
    }
  }

  bool pathHasUnsavedChanges(String filePath) {
    if (filePath == _activeDocumentPath) {
      return activeFileHasUnsavedChanges || state.isDirty(filePath);
    }
    return state.isDirty(filePath);
  }

  DocumentResourceBindingSnapshot markExternalChanged(
    DocumentState externalDocument,
  ) {
    final snapshot = fileBinding.markExternalChanged(externalDocument);
    log(
      snapshot.state == DocumentResourceBindingState.conflicted
          ? 'External change conflicted for ${externalDocument.documentId} '
                '(rev ${externalDocument.revision}).'
          : 'External change detected for ${externalDocument.documentId} '
                '(rev ${externalDocument.revision}).',
    );
    return snapshot;
  }

  DocumentResourceBindingSnapshot acceptExternalChange() {
    final snapshot = fileBinding.acceptExternalChange();
    final document = snapshot.document;
    if (document == null) {
      notify();
      return snapshot;
    }
    cacheDocument(_activeDocumentPath, document);
    editorController.loadDocument(document);
    state.clearDirty(_activeDocumentPath);
    log(
      'External change accepted for ${document.documentId} '
      '(rev ${document.revision}).',
    );
    return fileBinding.snapshot;
  }

  WorkspaceFileCloseRequestResult requestClose(String filePath) {
    if (pathHasUnsavedChanges(filePath)) {
      final result = WorkspaceFileCloseRequestResult.blockedUnsavedChanges(
        filePath,
        canSave: filePath == _activeDocumentPath,
        canDiscard: filePath == _activeDocumentPath,
        canSwitchToFile: filePath != _activeDocumentPath,
      );
      _lastCloseRequest = result;
      log(result.message);
      return result;
    }
    if (!workspaceController.openFilePaths.contains(filePath)) {
      final result = WorkspaceFileCloseRequestResult.notOpen(filePath);
      _lastCloseRequest = result;
      log(result.message);
      return result;
    }
    workspaceController.closeFile(filePath);
    state.clearDirty(filePath);
    final result = WorkspaceFileCloseRequestResult.closedFile(filePath);
    _lastCloseRequest = result;
    log(result.message);
    return result;
  }

  void clearCloseRequest() {
    _lastCloseRequest = null;
    notify();
  }

  void switchToCloseRequestFile() {
    final pendingClose = _lastCloseRequest;
    if (pendingClose == null || !pendingClose.requiresUserChoice) {
      return;
    }
    workspaceController.openFile(pendingClose.filePath);
    state.markDirty(pendingClose.filePath);
    _lastCloseRequest = WorkspaceFileCloseRequestResult.blockedUnsavedChanges(
      pendingClose.filePath,
    );
    log('Close request focus switched to ${pendingClose.filePath}.');
  }

  DocumentResourceBindingSnapshot completeActiveSave() {
    final snapshot = fileBinding.snapshot;
    if (snapshot.state == DocumentResourceBindingState.boundClean) {
      state.clearDirty(_activeDocumentPath);
      _lastCloseRequest = null;
      notify();
    }
    return snapshot;
  }

  Future<WorkspaceSaveAllResult> saveAll({
    required Future<DocumentResourceBindingSnapshot> Function() saveActive,
  }) async {
    final dirtyDocumentIds = state.dirtyDocumentPaths;
    if (dirtyDocumentIds.isEmpty) {
      const result = WorkspaceSaveAllResult(
        savedDocumentIds: <String>[],
        skippedDocumentIds: <String>[],
        message: 'Save all skipped: no dirty documents.',
      );
      log(result.message);
      return result;
    }

    final savedDocumentIds = <String>[];
    final skippedDocumentIds = <String>[];
    if (dirtyDocumentIds.contains(_activeDocumentPath)) {
      if (editorController.document.documentId == _activeDocumentPath) {
        final snapshot = await saveActive();
        if (snapshot.state == DocumentResourceBindingState.boundClean) {
          savedDocumentIds.add(_activeDocumentPath);
        } else {
          skippedDocumentIds.add(_activeDocumentPath);
        }
      } else {
        final document = state.document(_activeDocumentPath);
        if (document == null) {
          skippedDocumentIds.add(_activeDocumentPath);
          log(
            'Save all skipped $_activeDocumentPath: active document is still loading.',
          );
        } else {
          await documentStore.saveDocument(document);
          state.clearDirty(_activeDocumentPath);
          savedDocumentIds.add(_activeDocumentPath);
          log('Saved active-path cached document $_activeDocumentPath.');
        }
      }
    }

    for (final documentId in dirtyDocumentIds) {
      if (documentId == _activeDocumentPath) {
        continue;
      }
      final document = state.document(documentId);
      if (document == null) {
        skippedDocumentIds.add(documentId);
        log('Save all skipped $documentId: no cached dirty document.');
        continue;
      }
      try {
        await documentStore.saveDocument(document);
        state.clearDirty(documentId);
        savedDocumentIds.add(documentId);
        log('Saved inactive dirty document $documentId.');
      } on Object catch (error) {
        skippedDocumentIds.add(documentId);
        log('Save all failed for $documentId: $error');
      }
    }
    final pendingClose = _lastCloseRequest;
    if (pendingClose != null && skippedDocumentIds.isEmpty) {
      _lastCloseRequest = null;
    } else if (pendingClose != null &&
        pendingClose.requiresUserChoice &&
        !state.isDirty(pendingClose.filePath)) {
      _lastCloseRequest = null;
    }

    final result = WorkspaceSaveAllResult(
      savedDocumentIds: List<String>.unmodifiable(savedDocumentIds),
      skippedDocumentIds: List<String>.unmodifiable(skippedDocumentIds),
      message: skippedDocumentIds.isEmpty
          ? 'Saved ${savedDocumentIds.length} dirty document(s).'
          : 'Saved ${savedDocumentIds.length} dirty document(s); skipped ${skippedDocumentIds.length}.',
    );
    log(result.message);
    notify();
    return result;
  }

  Future<WorkspaceFileCloseRequestResult?> saveAndCloseRequested({
    required Future<DocumentResourceBindingSnapshot> Function() saveActive,
  }) async {
    final pendingClose = _lastCloseRequest;
    if (pendingClose == null || !pendingClose.requiresUserChoice) {
      return pendingClose;
    }
    final filePath = pendingClose.filePath;
    final snapshot = await saveActive();
    if (snapshot.state != DocumentResourceBindingState.boundClean) {
      return _lastCloseRequest;
    }
    return requestClose(filePath);
  }

  Future<DocumentResourceBindingSnapshot> discardActiveChanges() async {
    if (!activeFileHasUnsavedChanges) {
      log('Discard skipped: $_activeDocumentPath has no local changes.');
      return fileBinding.snapshot;
    }
    final activePath = _activeDocumentPath;
    final openResult = await fileBinding.open(activePath);
    final document = openResult.snapshot.document;
    if (document == null) {
      log('Discard failed for $activePath: backing resource unavailable.');
      notify();
      return fileBinding.snapshot;
    }
    cacheDocument(activePath, document);
    editorController.loadDocument(document);
    state.clearDirty(activePath);
    _lastCloseRequest = null;
    log('Discarded local changes for $activePath (rev ${document.revision}).');
    return fileBinding.snapshot;
  }

  Future<WorkspaceFileCloseRequestResult?> discardAndCloseRequested() async {
    final pendingClose = _lastCloseRequest;
    if (pendingClose == null || !pendingClose.requiresUserChoice) {
      return pendingClose;
    }
    final filePath = pendingClose.filePath;
    final snapshot = await discardActiveChanges();
    if (snapshot.state != DocumentResourceBindingState.boundClean) {
      return _lastCloseRequest;
    }
    return requestClose(filePath);
  }

  Future<void> persistSession({String key = 'default'}) async {
    final store = sessionStore;
    if (store == null) {
      log('Editor session persistence unavailable: no DataStore is wired.');
      return;
    }
    final openDocumentIds = <String>{
      ...state.cachedDocumentPaths,
      _activeDocumentPath,
      editorController.document.documentId,
    }.toList(growable: false);
    await store.saveSession(
      workspaceId: sessionWorkspaceId,
      key: key,
      snapshot: editorController.toSessionSnapshot(
        openDocumentIds: openDocumentIds,
        dirtyDocumentIds: state.dirtyDocumentPaths,
        cursorOffsets: state.cursorOffsets,
        selectionAnchors: state.selectionAnchors,
      ),
    );
    log(
      'Editor session persisted for $sessionWorkspaceId with '
      '${openDocumentIds.length} open document(s).',
    );
  }

  Future<EditorSessionSnapshot?> restoreSession({
    String key = 'default',
  }) async {
    final store = sessionStore;
    if (store == null) {
      log('Editor session restore unavailable: no DataStore is wired.');
      return null;
    }
    final snapshot = await store.readSession(
      workspaceId: sessionWorkspaceId,
      key: key,
    );
    if (snapshot == null) {
      log('No editor session snapshot found for $sessionWorkspaceId.');
      return null;
    }

    final restoredDirtyDocumentIds = snapshot.dirtyDocumentIds
        .where(workspaceController.files.contains)
        .toList(growable: false);
    void restoreDirtyDocumentState() {
      state.restoreDirtyDocuments(restoredDirtyDocumentIds);
      if (restoredDirtyDocumentIds.isNotEmpty) {
        log(
          'Editor session restored dirty state for '
          '${restoredDirtyDocumentIds.length} document(s).',
        );
      }
    }

    final restoredOpenDocumentIds = snapshot.openDocumentIds
        .where(workspaceController.files.contains)
        .toList(growable: false);
    if (restoredOpenDocumentIds.isNotEmpty) {
      _runWithoutWorkspaceLoad(
        () => workspaceController.restoreOpenFiles(
          restoredOpenDocumentIds,
          activeFilePath: snapshot.activeDocumentId,
        ),
      );
    }
    state.restoreSelections(
      cursorOffsets: snapshot.cursorOffsets,
      selectionAnchors: snapshot.selectionAnchors,
    );

    var documentId = editorController.document.documentId;
    final activeDocumentId = snapshot.activeDocumentId;
    if (activeDocumentId != null && activeDocumentId != documentId) {
      if (!workspaceController.files.contains(activeDocumentId)) {
        log(
          'Editor session snapshot loaded for $activeDocumentId, '
          'but the document is not available in the workspace.',
        );
        restoreDirtyDocumentState();
        return snapshot;
      }
      _runWithoutWorkspaceLoad(
        () => workspaceController.openFile(activeDocumentId),
      );
      final previousSelectionTracking = _suppressSelectionTracking;
      _suppressSelectionTracking = true;
      try {
        await loadActiveDocument();
      } finally {
        _suppressSelectionTracking = previousSelectionTracking;
      }
      documentId = editorController.document.documentId;
    }

    if (activeDocumentId != null && activeDocumentId != documentId) {
      log(
        'Editor session snapshot loaded for $activeDocumentId, '
        'current document is $documentId.',
      );
      restoreDirtyDocumentState();
      return snapshot;
    }

    restoreDirtyDocumentState();
    restoreSelection(documentId);
    log('Editor session restored for $documentId.');
    return snapshot;
  }

  void _runWithoutWorkspaceLoad(void Function() action) {
    final previous = _suppressWorkspaceChangedLoad;
    _suppressWorkspaceChangedLoad = true;
    try {
      action();
    } finally {
      _suppressWorkspaceChangedLoad = previous;
    }
  }
}
