import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/interaction/document_resource_binding.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_store_types.dart';

void main() {
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
