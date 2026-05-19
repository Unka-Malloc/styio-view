import '../backend_toolchain/hosted_control_plane.dart';
import '../editor/document_state.dart';
import 'workspace_document_store_types.dart';

class HostedWorkspaceDocumentStore implements WorkspaceDocumentStore {
  const HostedWorkspaceDocumentStore({
    required this.hostedClient,
    required this.workspaceId,
  });

  final HostedControlPlaneClient hostedClient;
  final String workspaceId;

  @override
  Future<DocumentState> loadDocument(String path) async {
    final response = await hostedClient.loadDocument(
      workspaceId: workspaceId,
      path: path,
    );
    final payload = _payloadObject(response);
    return DocumentState(
      documentId:
          _stringValue(payload, const <String>[
            'document_id',
            'documentId',
            'path',
            'file_path',
            'filePath',
          ]) ??
          path,
      text:
          _stringValue(payload, const <String>[
            'document_text',
            'documentText',
            'text',
            'content',
          ]) ??
          '',
      revision: _intValue(payload, const <String>['revision', 'version']) ?? 0,
    );
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    await hostedClient.saveDocument(
      workspaceId: workspaceId,
      path: document.documentId,
      documentText: document.text,
      revision: document.revision,
    );
  }

  @override
  Future<bool> deleteDocument(String path) {
    throw UnsupportedError('Hosted workspace document deletion is not supported.');
  }

  @override
  Future<bool> documentExists(String path) async {
    try {
      await loadDocument(path);
      return true;
    } on Object {
      return false;
    }
  }

  @override
  String? filePathForDocumentId(String documentId) => documentId;
}

Map<String, Object?> _payloadObject(Map<String, dynamic> response) {
  final payload = response['payload'];
  if (payload is Map<String, dynamic>) {
    return payload;
  }
  if (payload is Map<Object?, Object?>) {
    return payload.map((key, value) => MapEntry(key?.toString() ?? '', value));
  }
  return response;
}

String? _stringValue(Map<String, Object?> payload, List<String> keys) {
  for (final key in keys) {
    final value = payload[key];
    if (value is String) {
      return value;
    }
  }
  return null;
}

int? _intValue(Map<String, Object?> payload, List<String> keys) {
  for (final key in keys) {
    final value = payload[key];
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
  }
  return null;
}
