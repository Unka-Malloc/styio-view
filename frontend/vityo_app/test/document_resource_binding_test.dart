import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/interaction/document_resource_binding.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_store_types.dart';

void main() {
  test('binds loaded and untitled documents with snapshot helpers', () {
    const loaded = DocumentState(
      documentId: 'src/main.styio',
      text: 'value := 1\n',
      revision: 2,
    );
    const untitled = DocumentState(
      documentId: 'untitled://scratch',
      text: 'scratch',
      revision: 0,
    );
    final binding = EditorDocumentResourceBinding.withResourceStore(
      resourceStore: _WatchingDocumentResourceStore(),
    );

    final loadedSnapshot = binding.bindLoadedDocument(loaded);
    expect(loadedSnapshot.canSave, isTrue);
    expect(binding.isBound, isTrue);
    expect(binding.isDirty, isFalse);

    final dirty = loaded.replaceRange(
      start: loaded.text.indexOf('1'),
      end: loaded.text.indexOf('1') + 1,
      replacement: '2',
    );
    final dirtySnapshot = binding.markDocumentChanged(dirty);
    expect(dirtySnapshot.canSave, isTrue);
    expect(binding.isDirty, isTrue);

    final failedSnapshot = dirtySnapshot.copyWith(
      failureKind: DocumentResourceBindingFailureKind.conflict,
      failureMessage: 'conflict',
      externalDocument: loaded,
    );
    expect(failedSnapshot.hasFailure, isTrue);
    expect(failedSnapshot.hasExternalChange, isTrue);
    final cleared = failedSnapshot.copyWith(
      clearFailure: true,
      clearExternalDocument: true,
    );
    expect(cleared.hasFailure, isFalse);
    expect(cleared.hasExternalChange, isFalse);

    final untitledSnapshot = binding.bindUntitled(untitled);
    expect(untitledSnapshot.canSave, isFalse);
    expect(binding.isBound, isFalse);
  });

  test('opens a workspace document and saves dirty editor content', () async {
    const initial = DocumentState(
      documentId: 'src/main.styio',
      text: 'value := 1\\n',
      revision: 0,
    );
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: <String, DocumentState>{initial.documentId: initial},
    );
    final binding = EditorDocumentResourceBinding(documentStore: store);

    final openResult = await binding.open(initial.documentId);
    expect(openResult.opened, isTrue);
    expect(binding.snapshot.state, DocumentResourceBindingState.boundClean);
    expect(binding.snapshot.document?.text, initial.text);

    final edited = initial.replaceRange(
      start: initial.text.indexOf('1'),
      end: initial.text.indexOf('1') + 1,
      replacement: '2',
    );
    binding.markDocumentChanged(edited);

    expect(binding.snapshot.state, DocumentResourceBindingState.boundDirty);

    final saveResult = await binding.save(edited);
    expect(saveResult.saved, isTrue);
    expect(binding.snapshot.state, DocumentResourceBindingState.boundClean);
    expect(binding.snapshot.lastSavedRevision, edited.revision);

    final persisted = await store.loadDocument(initial.documentId);
    expect(persisted.text, 'value := 2\\n');
    expect(persisted.revision, edited.revision);
  });

  test('blocks save when external changes conflict with dirty content', () async {
    const initial = DocumentState(
      documentId: 'src/main.styio',
      text: 'value := 1\\n',
      revision: 0,
    );
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: <String, DocumentState>{initial.documentId: initial},
    );
    final binding = EditorDocumentResourceBinding(documentStore: store);
    await binding.open(initial.documentId);

    final localEdit = initial.replaceRange(
      start: initial.text.indexOf('1'),
      end: initial.text.indexOf('1') + 1,
      replacement: '2',
    );
    binding.markDocumentChanged(localEdit);

    final externalEdit = initial.replaceRange(
      start: initial.text.indexOf('1'),
      end: initial.text.indexOf('1') + 1,
      replacement: '3',
    );
    await store.saveDocument(externalEdit);
    binding.markExternalChanged(externalEdit);

    expect(binding.snapshot.state, DocumentResourceBindingState.conflicted);
    expect(
      binding.snapshot.failureKind,
      DocumentResourceBindingFailureKind.conflict,
    );

    final blockedSave = await binding.save(localEdit);
    expect(blockedSave.saved, isFalse);
    expect(
      blockedSave.failureKind,
      DocumentResourceBindingFailureKind.conflict,
    );

    final persisted = await store.loadDocument(initial.documentId);
    expect(persisted.text, 'value := 3\\n');

    final overwriteSave = await binding.save(
      localEdit,
      overwriteConflict: true,
    );
    expect(overwriteSave.saved, isTrue);
    expect(binding.snapshot.state, DocumentResourceBindingState.boundClean);

    final overwritten = await store.loadDocument(initial.documentId);
    expect(overwritten.text, 'value := 2\\n');
  });

  test('reports deleted, readonly, and provider unavailable save failures', () async {
    const initial = DocumentState(
      documentId: 'src/main.styio',
      text: 'value := 1\\n',
      revision: 0,
    );
    final store = InMemoryWorkspaceDocumentStore(
      seededDocuments: <String, DocumentState>{initial.documentId: initial},
    );
    final binding = EditorDocumentResourceBinding(documentStore: store);
    await binding.open(initial.documentId);

    binding.markDeletedOnDisk();
    final deletedSave = await binding.save(initial);
    expect(deletedSave.saved, isFalse);
    expect(
      deletedSave.failureKind,
      DocumentResourceBindingFailureKind.deletedOnDisk,
    );

    binding.markReadonly();
    final readonlySave = await binding.save(initial, overwriteConflict: true);
    expect(readonlySave.saved, isFalse);
    expect(
      readonlySave.failureKind,
      DocumentResourceBindingFailureKind.readonly,
    );

    binding.markReadonly(readonly: false);
    binding.markProviderUnavailable();
    final unavailableSave = await binding.save(
      initial,
      overwriteConflict: true,
    );
    expect(unavailableSave.saved, isFalse);
    expect(
      unavailableSave.failureKind,
      DocumentResourceBindingFailureKind.providerUnavailable,
    );
  });

  test('reports open and save preflight failures', () async {
    const initial = DocumentState(
      documentId: 'src/main.styio',
      text: 'value := 1\n',
      revision: 0,
    );
    final binding = EditorDocumentResourceBinding.withResourceStore(
      resourceStore: _FailingDocumentResourceStore(loadFails: true),
    );

    final openResult = await binding.open(initial.documentId);
    expect(openResult.opened, isFalse);
    expect(
      openResult.failureKind,
      DocumentResourceBindingFailureKind.loadFailed,
    );
    expect(openResult.error, isA<StateError>());

    final unboundBinding = EditorDocumentResourceBinding.withResourceStore(
      resourceStore: _WatchingDocumentResourceStore(),
    );
    final unboundSave = await unboundBinding.save(initial);
    expect(unboundSave.failureKind, DocumentResourceBindingFailureKind.unbound);

    final store = _WatchingDocumentResourceStore(
      seededDocuments: <String, DocumentState>{initial.documentId: initial},
    );
    final openedBinding = EditorDocumentResourceBinding.withResourceStore(
      resourceStore: store,
    );
    await openedBinding.open(initial.documentId);
    final mismatchSave = await openedBinding.save(
      const DocumentState(
        documentId: 'src/other.styio',
        text: 'other',
        revision: 0,
      ),
    );
    expect(
      mismatchSave.failureKind,
      DocumentResourceBindingFailureKind.resourceMismatch,
    );
    expect(
      () => openedBinding.markDocumentChanged(
        const DocumentState(
          documentId: 'src/other.styio',
          text: 'other',
          revision: 1,
        ),
      ),
      throwsArgumentError,
    );

    final pendingStore = _PendingDocumentResourceStore(initial);
    final pendingBinding = EditorDocumentResourceBinding.withResourceStore(
      resourceStore: pendingStore,
    );
    final pendingOpen = pendingBinding.open(initial.documentId);
    final bindingSave = await pendingBinding.save(initial);
    expect(bindingSave.failureKind, DocumentResourceBindingFailureKind.binding);
    pendingStore.complete();
    await pendingOpen;

    final saveFailingBinding = EditorDocumentResourceBinding.withResourceStore(
      resourceStore: _FailingDocumentResourceStore(
        seededDocuments: <String, DocumentState>{initial.documentId: initial},
        saveFails: true,
      ),
    );
    await saveFailingBinding.open(initial.documentId);
    final failedSave = await saveFailingBinding.save(initial);
    expect(failedSave.saved, isFalse);
    expect(
      failedSave.failureKind,
      DocumentResourceBindingFailureKind.saveFailed,
    );
    expect(failedSave.error, isA<StateError>());
  });

  test('resource watch events update binding state', () async {
    const initial = DocumentState(
      documentId: 'src/main.styio',
      text: 'value := 1\n',
      revision: 0,
    );
    final store = _WatchingDocumentResourceStore(
      seededDocuments: <String, DocumentState>{initial.documentId: initial},
    );
    final binding = EditorDocumentResourceBinding.withResourceStore(
      resourceStore: store,
    );
    addTearDown(binding.dispose);
    await binding.open(initial.documentId);

    final localEdit = initial.replaceRange(
      start: initial.text.indexOf('1'),
      end: initial.text.indexOf('1') + 1,
      replacement: '2',
    );
    binding.markDocumentChanged(localEdit);

    final externalEdit = initial.replaceRange(
      start: initial.text.indexOf('1'),
      end: initial.text.indexOf('1') + 1,
      replacement: '3',
    );
    store.emit(DocumentResourceEvent.externalChanged(externalEdit));

    expect(binding.snapshot.state, DocumentResourceBindingState.conflicted);
    expect(
      binding.snapshot.failureKind,
      DocumentResourceBindingFailureKind.conflict,
    );

    store.emit(const DocumentResourceEvent.providerUnavailable());
    expect(
      binding.snapshot.state,
      DocumentResourceBindingState.providerUnavailable,
    );

    store.emit(const DocumentResourceEvent.providerAvailable());
    expect(binding.snapshot.state, DocumentResourceBindingState.boundDirty);

    store.emit(const DocumentResourceEvent.readonly());
    expect(binding.snapshot.state, DocumentResourceBindingState.readonly);

    store.emit(const DocumentResourceEvent.writable());
    expect(binding.snapshot.state, DocumentResourceBindingState.boundDirty);

    store.emit(const DocumentResourceEvent.deletedOnDisk());
    expect(binding.snapshot.state, DocumentResourceBindingState.deletedOnDisk);
  });
}

class _WatchingDocumentResourceStore implements DocumentResourceStore {
  _WatchingDocumentResourceStore({
    Map<String, DocumentState>? seededDocuments,
  }) : _documents = Map<String, DocumentState>.from(
         seededDocuments ?? const <String, DocumentState>{},
       );

  final Map<String, DocumentState> _documents;
  final StreamController<DocumentResourceEvent> _events =
      StreamController<DocumentResourceEvent>.broadcast(sync: true);

  void emit(DocumentResourceEvent event) {
    _events.add(event);
  }

  @override
  Future<DocumentState> loadDocument(String resourceId) async {
    return _documents[resourceId] ??
        DocumentState(documentId: resourceId, text: '', revision: 0);
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    _documents[document.documentId] = document;
  }

  @override
  Stream<DocumentResourceEvent> watchResource(String resourceId) {
    return _events.stream;
  }
}

class _FailingDocumentResourceStore extends _WatchingDocumentResourceStore {
  _FailingDocumentResourceStore({
    super.seededDocuments,
    this.loadFails = false,
    this.saveFails = false,
  });

  final bool loadFails;
  final bool saveFails;

  @override
  Future<DocumentState> loadDocument(String resourceId) async {
    if (loadFails) {
      throw StateError('load failed');
    }
    return super.loadDocument(resourceId);
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    if (saveFails) {
      throw StateError('save failed');
    }
    await super.saveDocument(document);
  }
}

class _PendingDocumentResourceStore extends _WatchingDocumentResourceStore {
  _PendingDocumentResourceStore(this.document);

  final DocumentState document;
  final Completer<DocumentState> _loadCompleter = Completer<DocumentState>();

  void complete() {
    _loadCompleter.complete(document);
  }

  @override
  Future<DocumentState> loadDocument(String resourceId) {
    return _loadCompleter.future;
  }
}
