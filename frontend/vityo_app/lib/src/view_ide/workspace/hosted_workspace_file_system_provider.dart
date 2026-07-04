import '../backend_toolchain/hosted_control_plane.dart';
import '../editor/document_state.dart';
import '../environment/system_compatibility/file_system/file_system_manager.dart';
import 'hosted_workspace_document_store.dart';

class HostedWorkspaceFileSystemTarget {
  const HostedWorkspaceFileSystemTarget({
    required this.workspaceId,
    required this.documentPath,
    required this.uri,
  });

  final String workspaceId;
  final String documentPath;
  final Uri uri;
}

class HostedWorkspaceFileSystemProvider {
  const HostedWorkspaceFileSystemProvider({required this.hostedClient});

  static const String scheme = 'vityo-hosted';

  final HostedControlPlaneClient hostedClient;

  Uri uriFor(String path, {String? workspaceId}) {
    final effectiveWorkspaceId = workspaceId ?? hostedClient.config.workspaceId;
    if (effectiveWorkspaceId == null || effectiveWorkspaceId.trim().isEmpty) {
      throw const FormatException(
        'Hosted workspace URI requires a workspace id.',
      );
    }
    final effectivePath = path.startsWith('/') ? path : '/$path';
    return Uri(
      scheme: scheme,
      host: effectiveWorkspaceId.trim(),
      path: effectivePath,
    );
  }

  HostedWorkspaceFileSystemTarget route(Uri uri) {
    if (uri.scheme != scheme) {
      throw FormatException(
        'Unsupported hosted workspace URI scheme ${uri.scheme}.',
        uri.toString(),
      );
    }
    final workspaceId = uri.host.trim();
    if (workspaceId.isEmpty) {
      throw FormatException(
        'Hosted workspace URI requires a workspace id.',
        uri.toString(),
      );
    }
    final documentPath = _documentPathFor(uri.path);
    if (documentPath.isEmpty || documentPath == '/') {
      throw FormatException(
        'Hosted workspace URI requires a document path.',
        uri.toString(),
      );
    }
    return HostedWorkspaceFileSystemTarget(
      workspaceId: workspaceId,
      documentPath: documentPath,
      uri: uri,
    );
  }

  Future<String> readText(Uri uri) async {
    final target = route(uri);
    final document = await _storeFor(target).loadDocument(target.documentPath);
    return document.text;
  }

  Future<void> writeText(Uri uri, String contents, {int revision = 0}) async {
    final target = route(uri);
    await _storeFor(target).saveDocument(
      DocumentState(
        documentId: target.documentPath,
        text: contents,
        revision: revision,
      ),
    );
  }

  Future<bool> exists(Uri uri) async {
    final target = route(uri);
    return _storeFor(target).documentExists(target.documentPath);
  }

  FileSystemOperationFailure unsupportedOperation({
    required String operation,
    required Uri target,
  }) {
    return FileSystemOperationFailure(
      kind: FileSystemFailureKind.unsupportedProvider,
      operation: operation,
      target: target.toString(),
      sourceManager: 'HostedWorkspaceFileSystemProvider',
      message:
          'Hosted workspace file system operation `$operation` is not '
          'published by the hosted control-plane contract.',
      recoveryHint:
          'Use hosted document load/save routes or a published lifecycle '
          'action for this workspace.',
    );
  }

  HostedWorkspaceDocumentStore _storeFor(
    HostedWorkspaceFileSystemTarget target,
  ) {
    return HostedWorkspaceDocumentStore(
      hostedClient: hostedClient,
      workspaceId: target.workspaceId,
    );
  }

  String _documentPathFor(String uriPath) {
    final decodedPath = Uri.decodeComponent(uriPath);
    final workspaceRoot = hostedClient.config.workspaceRoot.trim();
    if (decodedPath.isEmpty || decodedPath == '/') {
      return decodedPath;
    }
    if (workspaceRoot.isEmpty ||
        decodedPath == workspaceRoot ||
        decodedPath.startsWith('$workspaceRoot/')) {
      return decodedPath;
    }
    final relative = decodedPath.startsWith('/')
        ? decodedPath.substring(1)
        : decodedPath;
    final normalizedRoot = workspaceRoot.endsWith('/')
        ? workspaceRoot.substring(0, workspaceRoot.length - 1)
        : workspaceRoot;
    return '$normalizedRoot/$relative';
  }
}
