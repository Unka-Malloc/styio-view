import 'package:shared_preferences/shared_preferences.dart';

import '../editor/document_state.dart';
import '../editor/editor_controller.dart';

abstract class WorkspaceDocumentStore {
  Future<DocumentState> loadDocument(String path);

  Future<void> saveDocument(DocumentState document);

  Future<bool> deleteDocument(String path);

  Future<bool> documentExists(String path);

  String? filePathForDocumentId(String documentId);
}

abstract class WatchableWorkspaceDocumentStore implements WorkspaceDocumentStore {
  Stream<DocumentState> watchDocument(String documentId);
}

class SharedPreferencesWorkspaceDocumentStore
    implements WorkspaceDocumentStore {
  SharedPreferencesWorkspaceDocumentStore(
    this._preferences, {
    this.keyPrefix = 'vityo.document',
  });

  final SharedPreferences _preferences;
  final String keyPrefix;

  @override
  Future<DocumentState> loadDocument(String path) async {
    final text = _preferences.getString(_textKey(path));
    final revision = _preferences.getInt(_revisionKey(path));

    if (text == null) {
      return EditorSessionController.seedDocumentForPath(path);
    }

    return DocumentState(documentId: path, text: text, revision: revision ?? 0);
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    await _preferences.setString(_textKey(document.documentId), document.text);
    await _preferences.setInt(
      _revisionKey(document.documentId),
      document.revision,
    );
  }

  @override
  Future<bool> deleteDocument(String path) async {
    final removedText = await _preferences.remove(_textKey(path));
    final removedRevision = await _preferences.remove(_revisionKey(path));
    return removedText || removedRevision;
  }

  @override
  Future<bool> documentExists(String path) async {
    return _preferences.getString(_textKey(path)) != null;
  }

  @override
  String? filePathForDocumentId(String documentId) => null;

  String _textKey(String path) => '$keyPrefix.$path.text';

  String _revisionKey(String path) => '$keyPrefix.$path.revision';
}

class InMemoryWorkspaceDocumentStore implements WorkspaceDocumentStore {
  InMemoryWorkspaceDocumentStore({Map<String, DocumentState>? seededDocuments})
    : _documents = Map<String, DocumentState>.from(seededDocuments ?? const {});

  final Map<String, DocumentState> _documents;

  @override
  Future<DocumentState> loadDocument(String path) async {
    return _documents[path] ??
        EditorSessionController.seedDocumentForPath(path);
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    _documents[document.documentId] = document;
  }

  @override
  Future<bool> deleteDocument(String path) async {
    return _documents.remove(path) != null;
  }

  @override
  Future<bool> documentExists(String path) async => _documents.containsKey(path);

  @override
  String? filePathForDocumentId(String documentId) => null;
}
