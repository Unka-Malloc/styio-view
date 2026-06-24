import 'dart:async';

import '../editor/document/document_state.dart';
import '../workspace/workspace_document_store_types.dart';

/// Editor-side binding between an open document and a workspace resource.
///
/// This is the Interaction-layer owner for editor file binding state. It
/// coordinates editor document state with the workspace document store without
/// owning file-system implementation details.
class EditorDocumentResourceBinding {
  EditorDocumentResourceBinding({required WorkspaceDocumentStore documentStore})
    : this.withResourceStore(
        resourceStore: WorkspaceDocumentResourceStore(documentStore),
      );

  EditorDocumentResourceBinding.withResourceStore({
    required DocumentResourceStore resourceStore,
  }) : _resourceStore = resourceStore;

  final DocumentResourceStore _resourceStore;
  StreamSubscription<DocumentResourceEvent>? _resourceEventSubscription;
  final StreamController<DocumentResourceBindingSnapshot> _snapshotEvents =
      StreamController<DocumentResourceBindingSnapshot>.broadcast(sync: true);
  int _openGeneration = 0;

  DocumentResourceBindingSnapshot _snapshot =
      const DocumentResourceBindingSnapshot(state: DocumentResourceBindingState.unbound);

  DocumentResourceBindingSnapshot get snapshot => _snapshot;

  Stream<DocumentResourceBindingSnapshot> get snapshotEvents =>
      _snapshotEvents.stream;

  bool get isBound => _snapshot.resourceId != null;

  bool get isDirty => _snapshot.state == DocumentResourceBindingState.boundDirty;

  DocumentResourceBindingSnapshot bindLoadedDocument(DocumentState document) {
    _openGeneration += 1;
    _snapshot = DocumentResourceBindingSnapshot(
      state: DocumentResourceBindingState.boundClean,
      resourceId: document.documentId,
      document: document,
      lastSavedRevision: document.revision,
      lastSavedText: document.text,
    );
    _watchResource(document.documentId);
    return _snapshot;
  }

  Future<DocumentResourceBindingOpenResult> open(String resourceId) async {
    final openGeneration = ++_openGeneration;
    _snapshot = _snapshot.copyWith(
      state: DocumentResourceBindingState.binding,
      resourceId: resourceId,
      clearFailure: true,
      clearExternalDocument: true,
    );

    try {
      final document = await _resourceStore.loadDocument(resourceId);
      if (openGeneration != _openGeneration) {
        return DocumentResourceBindingOpenResult.failed(
          snapshot: _snapshot,
          failureKind: DocumentResourceBindingFailureKind.binding,
          message: 'Stale workspace resource load ignored.',
        );
      }
      _snapshot = DocumentResourceBindingSnapshot(
        state: DocumentResourceBindingState.boundClean,
        resourceId: resourceId,
        document: document,
        lastSavedRevision: document.revision,
        lastSavedText: document.text,
      );
      _watchResource(resourceId);
      return DocumentResourceBindingOpenResult.opened(_snapshot);
    } catch (error) {
      if (openGeneration != _openGeneration) {
        return DocumentResourceBindingOpenResult.failed(
          snapshot: _snapshot,
          failureKind: DocumentResourceBindingFailureKind.binding,
          message: 'Stale workspace resource load ignored.',
          error: error,
        );
      }
      _snapshot = DocumentResourceBindingSnapshot(
        state: DocumentResourceBindingState.providerUnavailable,
        resourceId: resourceId,
        failureKind: DocumentResourceBindingFailureKind.loadFailed,
        failureMessage: 'Unable to load workspace resource.',
        error: error,
      );
      return DocumentResourceBindingOpenResult.failed(
        snapshot: _snapshot,
        failureKind: DocumentResourceBindingFailureKind.loadFailed,
        message: 'Unable to load workspace resource.',
        error: error,
      );
    }
  }

  DocumentResourceBindingSnapshot bindUntitled(DocumentState document) {
    _openGeneration += 1;
    _snapshot = DocumentResourceBindingSnapshot(
      state: DocumentResourceBindingState.unbound,
      document: document,
    );
    return _snapshot;
  }

  DocumentResourceBindingSnapshot markDocumentChanged(DocumentState document) {
    _ensureSameResource(document);
    final state = _isDirtyAgainstLastSave(document)
        ? DocumentResourceBindingState.boundDirty
        : DocumentResourceBindingState.boundClean;
    _snapshot = _snapshot.copyWith(
      state: state,
      document: document,
      clearFailure: true,
    );
    return _snapshot;
  }

  DocumentResourceBindingSnapshot markExternalChanged(
    DocumentState externalDocument,
  ) {
    final localDocument = _snapshot.document;
    final hasLocalDirtyState = localDocument != null &&
        _snapshot.resourceId == externalDocument.documentId &&
        _isDirtyAgainstLastSave(localDocument);

    _snapshot = _snapshot.copyWith(
      state: hasLocalDirtyState
          ? DocumentResourceBindingState.conflicted
          : DocumentResourceBindingState.externalChanged,
      externalDocument: externalDocument,
      failureKind: hasLocalDirtyState
          ? DocumentResourceBindingFailureKind.conflict
          : null,
      failureMessage: hasLocalDirtyState
          ? 'External changes conflict with local unsaved edits.'
          : null,
    );
    return _snapshot;
  }

  DocumentResourceBindingSnapshot acceptExternalChange() {
    final externalDocument = _snapshot.externalDocument;
    if (externalDocument == null) {
      return _snapshot;
    }
    _snapshot = DocumentResourceBindingSnapshot(
      state: DocumentResourceBindingState.boundClean,
      resourceId: externalDocument.documentId,
      document: externalDocument,
      lastSavedRevision: externalDocument.revision,
      lastSavedText: externalDocument.text,
    );
    return _snapshot;
  }

  DocumentResourceBindingSnapshot markDeletedOnDisk() {
    _snapshot = _snapshot.copyWith(
      state: DocumentResourceBindingState.deletedOnDisk,
      failureKind: DocumentResourceBindingFailureKind.deletedOnDisk,
      failureMessage: 'The backing resource was deleted or became unavailable.',
    );
    return _snapshot;
  }

  DocumentResourceBindingSnapshot markReadonly({bool readonly = true}) {
    if (readonly) {
      _snapshot = _snapshot.copyWith(
        state: DocumentResourceBindingState.readonly,
        failureKind: DocumentResourceBindingFailureKind.readonly,
        failureMessage: 'The backing resource is read-only.',
      );
      return _snapshot;
    }

    final document = _snapshot.document;
    _snapshot = _snapshot.copyWith(
      state: document != null && _isDirtyAgainstLastSave(document)
          ? DocumentResourceBindingState.boundDirty
          : DocumentResourceBindingState.boundClean,
      clearFailure: true,
    );
    return _snapshot;
  }

  DocumentResourceBindingSnapshot markProviderUnavailable() {
    _snapshot = _snapshot.copyWith(
      state: DocumentResourceBindingState.providerUnavailable,
      failureKind: DocumentResourceBindingFailureKind.providerUnavailable,
      failureMessage: 'The resource provider is unavailable.',
    );
    return _snapshot;
  }

  DocumentResourceBindingSnapshot markProviderAvailable() {
    final document = _snapshot.document;
    _snapshot = _snapshot.copyWith(
      state: document != null && _isDirtyAgainstLastSave(document)
          ? DocumentResourceBindingState.boundDirty
          : DocumentResourceBindingState.boundClean,
      clearFailure: true,
    );
    return _snapshot;
  }

  Future<DocumentResourceBindingSaveResult> save(
    DocumentState document, {
    bool overwriteConflict = false,
  }) async {
    final resourceFailure = _savePreflight(document, overwriteConflict);
    if (resourceFailure != null) {
      _snapshot = _snapshot.copyWith(
        document: document,
        failureKind: resourceFailure.kind,
        failureMessage: resourceFailure.message,
      );
      return DocumentResourceBindingSaveResult.failed(
        snapshot: _snapshot,
        failureKind: resourceFailure.kind,
        message: resourceFailure.message,
      );
    }

    try {
      await _resourceStore.saveDocument(document);
      _snapshot = DocumentResourceBindingSnapshot(
        state: DocumentResourceBindingState.boundClean,
        resourceId: document.documentId,
        document: document,
        lastSavedRevision: document.revision,
        lastSavedText: document.text,
      );
      return DocumentResourceBindingSaveResult.saved(_snapshot);
    } catch (error) {
      _snapshot = _snapshot.copyWith(
        state: DocumentResourceBindingState.providerUnavailable,
        document: document,
        failureKind: DocumentResourceBindingFailureKind.saveFailed,
        failureMessage: 'Unable to save workspace resource.',
        error: error,
      );
      return DocumentResourceBindingSaveResult.failed(
        snapshot: _snapshot,
        failureKind: DocumentResourceBindingFailureKind.saveFailed,
        message: 'Unable to save workspace resource.',
        error: error,
      );
    }
  }

  Future<void> dispose() async {
    await _resourceEventSubscription?.cancel();
    _resourceEventSubscription = null;
    await _snapshotEvents.close();
  }

  void _watchResource(String resourceId) {
    unawaited(_resourceEventSubscription?.cancel());
    _resourceEventSubscription = _resourceStore
        .watchResource(resourceId)
        .listen(_handleResourceEvent);
  }

  void _handleResourceEvent(DocumentResourceEvent event) {
    switch (event.kind) {
      case DocumentResourceEventKind.externalChanged:
        final document = event.document;
        if (document != null) {
          markExternalChanged(document);
        }
        break;
      case DocumentResourceEventKind.deletedOnDisk:
        markDeletedOnDisk();
        break;
      case DocumentResourceEventKind.readonly:
        markReadonly();
        break;
      case DocumentResourceEventKind.writable:
        markReadonly(readonly: false);
        break;
      case DocumentResourceEventKind.providerUnavailable:
        markProviderUnavailable();
        break;
      case DocumentResourceEventKind.providerAvailable:
        markProviderAvailable();
        break;
    }
    _snapshotEvents.add(_snapshot);
  }

  _SavePreflightFailure? _savePreflight(
    DocumentState document,
    bool overwriteConflict,
  ) {
    if (_snapshot.resourceId == null) {
      return const _SavePreflightFailure(
        DocumentResourceBindingFailureKind.unbound,
        'The document is not bound to a workspace resource.',
      );
    }
    if (_snapshot.resourceId != document.documentId) {
      return const _SavePreflightFailure(
        DocumentResourceBindingFailureKind.resourceMismatch,
        'The document does not match the bound workspace resource.',
      );
    }
    switch (_snapshot.state) {
      case DocumentResourceBindingState.readonly:
        return const _SavePreflightFailure(
          DocumentResourceBindingFailureKind.readonly,
          'The backing resource is read-only.',
        );
      case DocumentResourceBindingState.providerUnavailable:
        return const _SavePreflightFailure(
          DocumentResourceBindingFailureKind.providerUnavailable,
          'The resource provider is unavailable.',
        );
      case DocumentResourceBindingState.deletedOnDisk:
        return overwriteConflict
            ? null
            : const _SavePreflightFailure(
                DocumentResourceBindingFailureKind.deletedOnDisk,
                'The backing resource was deleted or became unavailable.',
              );
      case DocumentResourceBindingState.conflicted:
      case DocumentResourceBindingState.externalChanged:
        return overwriteConflict
            ? null
            : const _SavePreflightFailure(
                DocumentResourceBindingFailureKind.conflict,
                'External changes conflict with the pending save.',
              );
      case DocumentResourceBindingState.unbound:
        return const _SavePreflightFailure(
          DocumentResourceBindingFailureKind.unbound,
          'The document is not bound to a workspace resource.',
        );
      case DocumentResourceBindingState.binding:
        return const _SavePreflightFailure(
          DocumentResourceBindingFailureKind.binding,
          'The workspace resource is still binding.',
        );
      case DocumentResourceBindingState.boundClean:
      case DocumentResourceBindingState.boundDirty:
        return null;
    }
  }

  bool _isDirtyAgainstLastSave(DocumentState document) {
    return _snapshot.lastSavedText != null &&
        document.text != _snapshot.lastSavedText;
  }

  void _ensureSameResource(DocumentState document) {
    final resourceId = _snapshot.resourceId;
    if (resourceId == null || resourceId == document.documentId) {
      return;
    }
    throw ArgumentError.value(
      document.documentId,
      'document.documentId',
      'Document does not match bound resource $resourceId.',
    );
  }
}

class DocumentResourceBindingSnapshot {
  const DocumentResourceBindingSnapshot({
    required this.state,
    this.resourceId,
    this.document,
    this.lastSavedRevision,
    this.lastSavedText,
    this.externalDocument,
    this.failureKind,
    this.failureMessage,
    this.error,
  });

  final DocumentResourceBindingState state;
  final String? resourceId;
  final DocumentState? document;
  final int? lastSavedRevision;
  final String? lastSavedText;
  final DocumentState? externalDocument;
  final DocumentResourceBindingFailureKind? failureKind;
  final String? failureMessage;
  final Object? error;

  bool get hasFailure => failureKind != null;

  bool get hasExternalChange => externalDocument != null;

  bool get canSave => switch (state) {
    DocumentResourceBindingState.boundClean ||
    DocumentResourceBindingState.boundDirty => resourceId != null,
    _ => false,
  };

  DocumentResourceBindingSnapshot copyWith({
    DocumentResourceBindingState? state,
    String? resourceId,
    DocumentState? document,
    int? lastSavedRevision,
    String? lastSavedText,
    DocumentState? externalDocument,
    DocumentResourceBindingFailureKind? failureKind,
    String? failureMessage,
    Object? error,
    bool clearFailure = false,
    bool clearExternalDocument = false,
  }) {
    return DocumentResourceBindingSnapshot(
      state: state ?? this.state,
      resourceId: resourceId ?? this.resourceId,
      document: document ?? this.document,
      lastSavedRevision: lastSavedRevision ?? this.lastSavedRevision,
      lastSavedText: lastSavedText ?? this.lastSavedText,
      externalDocument: clearExternalDocument
          ? null
          : externalDocument ?? this.externalDocument,
      failureKind: clearFailure ? null : failureKind ?? this.failureKind,
      failureMessage: clearFailure
          ? null
          : failureMessage ?? this.failureMessage,
      error: clearFailure ? null : error ?? this.error,
    );
  }
}

enum DocumentResourceBindingState {
  unbound,
  binding,
  boundClean,
  boundDirty,
  externalChanged,
  deletedOnDisk,
  conflicted,
  readonly,
  providerUnavailable,
}

enum DocumentResourceBindingFailureKind {
  unbound,
  binding,
  resourceMismatch,
  conflict,
  readonly,
  deletedOnDisk,
  providerUnavailable,
  loadFailed,
  saveFailed,
}

class DocumentResourceBindingOpenResult {
  const DocumentResourceBindingOpenResult._({
    required this.snapshot,
    this.failureKind,
    this.message,
    this.error,
  });

  factory DocumentResourceBindingOpenResult.opened(
    DocumentResourceBindingSnapshot snapshot,
  ) {
    return DocumentResourceBindingOpenResult._(snapshot: snapshot);
  }

  factory DocumentResourceBindingOpenResult.failed({
    required DocumentResourceBindingSnapshot snapshot,
    required DocumentResourceBindingFailureKind failureKind,
    required String message,
    Object? error,
  }) {
    return DocumentResourceBindingOpenResult._(
      snapshot: snapshot,
      failureKind: failureKind,
      message: message,
      error: error,
    );
  }

  final DocumentResourceBindingSnapshot snapshot;
  final DocumentResourceBindingFailureKind? failureKind;
  final String? message;
  final Object? error;

  bool get opened => failureKind == null;
}

class DocumentResourceBindingSaveResult {
  const DocumentResourceBindingSaveResult._({
    required this.snapshot,
    this.failureKind,
    this.message,
    this.error,
  });

  factory DocumentResourceBindingSaveResult.saved(
    DocumentResourceBindingSnapshot snapshot,
  ) {
    return DocumentResourceBindingSaveResult._(snapshot: snapshot);
  }

  factory DocumentResourceBindingSaveResult.failed({
    required DocumentResourceBindingSnapshot snapshot,
    required DocumentResourceBindingFailureKind failureKind,
    required String message,
    Object? error,
  }) {
    return DocumentResourceBindingSaveResult._(
      snapshot: snapshot,
      failureKind: failureKind,
      message: message,
      error: error,
    );
  }

  final DocumentResourceBindingSnapshot snapshot;
  final DocumentResourceBindingFailureKind? failureKind;
  final String? message;
  final Object? error;

  bool get saved => failureKind == null;
}

abstract class DocumentResourceStore {
  Future<DocumentState> loadDocument(String resourceId);

  Future<void> saveDocument(DocumentState document);

  Stream<DocumentResourceEvent> watchResource(String resourceId) {
    return const Stream<DocumentResourceEvent>.empty();
  }
}

class WorkspaceDocumentResourceStore extends DocumentResourceStore {
  WorkspaceDocumentResourceStore(this._documentStore);

  final WorkspaceDocumentStore _documentStore;

  @override
  Future<DocumentState> loadDocument(String resourceId) {
    return _documentStore.loadDocument(resourceId);
  }

  @override
  Future<void> saveDocument(DocumentState document) {
    return _documentStore.saveDocument(document);
  }

  @override
  Stream<DocumentResourceEvent> watchResource(String resourceId) {
    final documentStore = _documentStore;
    if (documentStore is! WatchableWorkspaceDocumentStore) {
      return const Stream<DocumentResourceEvent>.empty();
    }
    return documentStore.watchDocument(resourceId).map(
      DocumentResourceEvent.externalChanged,
    );
  }
}

class DocumentResourceEvent {
  const DocumentResourceEvent._({
    required this.kind,
    this.document,
  });

  factory DocumentResourceEvent.externalChanged(DocumentState document) {
    return DocumentResourceEvent._(
      kind: DocumentResourceEventKind.externalChanged,
      document: document,
    );
  }

  const factory DocumentResourceEvent.deletedOnDisk() =
      _DeletedOnDiskDocumentResourceEvent;

  const factory DocumentResourceEvent.readonly() =
      _ReadonlyDocumentResourceEvent;

  const factory DocumentResourceEvent.writable() =
      _WritableDocumentResourceEvent;

  const factory DocumentResourceEvent.providerUnavailable() =
      _ProviderUnavailableDocumentResourceEvent;

  const factory DocumentResourceEvent.providerAvailable() =
      _ProviderAvailableDocumentResourceEvent;

  final DocumentResourceEventKind kind;
  final DocumentState? document;
}

class _DeletedOnDiskDocumentResourceEvent extends DocumentResourceEvent {
  const _DeletedOnDiskDocumentResourceEvent()
    : super._(kind: DocumentResourceEventKind.deletedOnDisk);
}

class _ReadonlyDocumentResourceEvent extends DocumentResourceEvent {
  const _ReadonlyDocumentResourceEvent()
    : super._(kind: DocumentResourceEventKind.readonly);
}

class _WritableDocumentResourceEvent extends DocumentResourceEvent {
  const _WritableDocumentResourceEvent()
    : super._(kind: DocumentResourceEventKind.writable);
}

class _ProviderUnavailableDocumentResourceEvent
    extends DocumentResourceEvent {
  const _ProviderUnavailableDocumentResourceEvent()
    : super._(kind: DocumentResourceEventKind.providerUnavailable);
}

class _ProviderAvailableDocumentResourceEvent extends DocumentResourceEvent {
  const _ProviderAvailableDocumentResourceEvent()
    : super._(kind: DocumentResourceEventKind.providerAvailable);
}

enum DocumentResourceEventKind {
  externalChanged,
  deletedOnDisk,
  readonly,
  writable,
  providerUnavailable,
  providerAvailable,
}

class _SavePreflightFailure {
  const _SavePreflightFailure(this.kind, this.message);

  final DocumentResourceBindingFailureKind kind;
  final String message;
}
