import 'package:vityo_daemon_protocol/vityo_daemon_protocol.dart';

import '../editor/document/document_encoding.dart';
import '../editor/document/document_state.dart';
import '../editor/editor_controller.dart';
import '../local_service/vityod_client.dart';
import 'workspace_document_store_types.dart';

Future<WorkspaceDocumentStore> createPlatformWorkspaceDocumentStore({
  VityodClient? vityodClient,
  String? workspaceId,
  String? workspaceRoot,
}) async {
  if (vityodClient == null) return InMemoryWorkspaceDocumentStore();
  final store = VityodWorkspaceDocumentStore(
    client: vityodClient,
    workspaceId: workspaceId,
    workspaceRoot: workspaceRoot,
  );
  await store.open();
  return store;
}

final class VityodWorkspaceDocumentStore
    implements AtomicWorkspaceDocumentStore {
  VityodWorkspaceDocumentStore({
    required VityodClient client,
    this.workspaceId,
    this.workspaceRoot,
  }) : _client = client,
       _workspaceRevision = client.snapshot?.workspaceRevision ?? 0;

  final VityodClient _client;
  final String? workspaceId;
  final String? workspaceRoot;
  final Map<String, int> _documentRevisions = <String, int>{};
  int _workspaceRevision;
  var _sequence = 0;

  Future<void> open() async {
    final id = workspaceId;
    final root = workspaceRoot;
    if (id == null || root == null) return;
    final response = await _client.request(
      method: 'workspace.open',
      idempotencyKey: _nextKey('open'),
      workspaceId: id,
      params: <String, Object?>{'rootPath': root},
    );
    _throwIfError(response);
    final workspaceRevision = response.params['workspaceRevision'];
    if (workspaceRevision is! int) {
      throw const VityodWorkspaceStoreFailure('invalid_workspace_snapshot');
    }
    _workspaceRevision = workspaceRevision;
  }

  @override
  Future<DocumentState> loadDocument(String path) async {
    final relativePath = _relativePath(path);
    try {
      final response = await _client.request(
        method: 'workspace.read',
        idempotencyKey: _nextKey('read'),
        workspaceId: workspaceId,
        params: <String, Object?>{'relativePath': relativePath},
      );
      _throwIfError(response);
      final contents = response.params['contents'];
      final documentRevision = response.params['documentRevision'];
      final workspaceRevision = response.params['workspaceRevision'];
      final encoding = response.params['encoding'];
      if (contents is! String ||
          documentRevision is! int ||
          workspaceRevision is! int) {
        throw const VityodWorkspaceStoreFailure('invalid_workspace_snapshot');
      }
      _documentRevisions[relativePath] = documentRevision;
      _workspaceRevision = workspaceRevision;
      return DocumentState(
        documentId: relativePath,
        text: contents,
        revision: documentRevision,
        encoding: encoding is String
            ? DocumentEncoding.fromWireValue(encoding)
            : null,
      );
    } on VityodWorkspaceStoreFailure catch (error) {
      if (error.code != 'document_missing') rethrow;
      final seeded = EditorSessionController.seedDocumentForPath(path);
      await saveDocument(seeded);
      return seeded;
    }
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    await saveDocumentsAtomically(<DocumentState>[document]);
  }

  @override
  Future<Map<String, int>> saveDocumentsAtomically(
    Iterable<DocumentState> documents,
  ) async {
    final pending = documents.toList(growable: false);
    if (pending.isEmpty) return const <String, int>{};
    final seen = <String>{};
    final changes = <Map<String, Object?>>[];
    for (final document in pending) {
      final relativePath = _relativePath(document.documentId);
      if (!seen.add(relativePath)) {
        throw const VityodWorkspaceStoreFailure('duplicate_document_change');
      }
      changes.add(<String, Object?>{
        'relativePath': relativePath,
        'expectedDocumentRevision': _documentRevisions[relativePath] ?? 0,
        'contents': document.text,
        if (document.encoding != null) 'encoding': document.encoding!.wireValue,
      });
    }
    final response = await _client.request(
      method: 'workspace.transaction.commit',
      idempotencyKey: _nextKey('commit'),
      workspaceId: workspaceId,
      params: <String, Object?>{
        'expectedWorkspaceRevision': _workspaceRevision,
        'changes': changes,
      },
    );
    _throwIfError(response);
    final workspaceRevision = response.params['workspaceRevision'];
    final revisions = response.params['documentRevisions'];
    if (workspaceRevision is! int || revisions is! Map) {
      throw const VityodWorkspaceStoreFailure('invalid_commit_receipt');
    }
    final committed = <String, int>{};
    for (final relativePath in seen) {
      final documentRevision = revisions[relativePath];
      if (documentRevision is! int) {
        throw const VityodWorkspaceStoreFailure('invalid_commit_receipt');
      }
      committed[relativePath] = documentRevision;
    }
    _workspaceRevision = workspaceRevision;
    _documentRevisions.addAll(committed);
    return Map<String, int>.unmodifiable(committed);
  }

  @override
  Future<bool> deleteDocument(String path) async {
    final relativePath = _relativePath(path);
    final revision = _documentRevisions[relativePath];
    if (revision == null && !await documentExists(relativePath)) return false;
    final response = await _client.request(
      method: 'workspace.delete',
      idempotencyKey: _nextKey('delete'),
      workspaceId: workspaceId,
      params: <String, Object?>{
        'relativePath': relativePath,
        'expectedWorkspaceRevision': _workspaceRevision,
        'expectedDocumentRevision': _documentRevisions[relativePath],
      },
    );
    _throwIfError(response);
    final deleted = response.params['deleted'];
    final workspaceRevision = response.params['workspaceRevision'];
    if (deleted is! bool || workspaceRevision is! int) {
      throw const VityodWorkspaceStoreFailure('invalid_delete_receipt');
    }
    _workspaceRevision = workspaceRevision;
    if (deleted) _documentRevisions.remove(relativePath);
    return deleted;
  }

  @override
  Future<bool> documentExists(String path) async {
    final relativePath = _relativePath(path);
    try {
      final response = await _client.request(
        method: 'workspace.read',
        idempotencyKey: _nextKey('exists'),
        workspaceId: workspaceId,
        params: <String, Object?>{'relativePath': relativePath},
      );
      _throwIfError(response);
      final documentRevision = response.params['documentRevision'];
      final workspaceRevision = response.params['workspaceRevision'];
      if (documentRevision is! int || workspaceRevision is! int) {
        throw const VityodWorkspaceStoreFailure('invalid_workspace_snapshot');
      }
      _documentRevisions[relativePath] = documentRevision;
      _workspaceRevision = workspaceRevision;
      return true;
    } on VityodWorkspaceStoreFailure catch (error) {
      if (error.code == 'document_missing') return false;
      rethrow;
    }
  }

  @override
  String? filePathForDocumentId(String documentId) {
    final root = workspaceRoot;
    if (root == null) return null;
    final separator = root.contains(r'\') ? r'\' : '/';
    final normalizedRoot = root.endsWith(separator)
        ? root.substring(0, root.length - 1)
        : root;
    return '$normalizedRoot$separator'
        '${_relativePath(documentId).replaceAll('/', separator)}';
  }

  String _relativePath(String path) {
    final root = workspaceRoot;
    final normalizedPath = path.replaceAll(r'\', '/');
    if (root == null) return normalizedPath;
    final normalizedRoot = root
        .replaceAll(r'\', '/')
        .replaceFirst(RegExp(r'/+$'), '');
    final comparePath = normalizedPath.toLowerCase();
    final compareRoot = normalizedRoot.toLowerCase();
    if (comparePath == compareRoot) {
      throw const VityodWorkspaceStoreFailure('workspace_root_is_not_document');
    }
    if (comparePath.startsWith('$compareRoot/')) {
      return normalizedPath.substring(normalizedRoot.length + 1);
    }
    final absolute =
        normalizedPath.startsWith('/') ||
        RegExp(r'^[A-Za-z]:/').hasMatch(normalizedPath);
    if (absolute || normalizedPath.split('/').contains('..')) {
      throw const VityodWorkspaceStoreFailure('workspace_root_escape');
    }
    return normalizedPath;
  }

  String _nextKey(String operation) =>
      'workspace-$operation-${++_sequence}-${_client.clientInstanceId}';
}

final class VityodWorkspaceStoreFailure implements Exception {
  const VityodWorkspaceStoreFailure(this.code);

  final String code;

  @override
  String toString() => 'VityodWorkspaceStoreFailure($code)';
}

void _throwIfError(VityodControlEnvelope response) {
  if (!response.method.endsWith('.error')) return;
  final code = response.params['errorCode'];
  throw VityodWorkspaceStoreFailure(
    code is String ? code : 'workspace_service_error',
  );
}
