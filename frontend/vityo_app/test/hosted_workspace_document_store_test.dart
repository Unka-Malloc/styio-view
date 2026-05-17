import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/integration/hosted_control_plane.dart';
import 'package:vityo_app/src/view_ide/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_store.dart';

void main() {
  test(
    'hosted workspace document store loads and saves through remote client',
    () async {
      final client = _RecordingHostedControlPlaneClient();
      final store = HostedWorkspaceDocumentStore(
        hostedClient: client,
        workspaceId: 'demo-workspace',
      );

      final document = await store.loadDocument(
        '/workspace/demo/src/main.styio',
      );
      expect(document.documentId, '/workspace/demo/src/main.styio');
      expect(document.text, 'remote := true\n');
      expect(document.revision, 3);
      expect(
        store.filePathForDocumentId('/workspace/demo/src/main.styio'),
        '/workspace/demo/src/main.styio',
      );

      await store.saveDocument(
        const DocumentState(
          documentId: '/workspace/demo/src/main.styio',
          text: 'remote := false\n',
          revision: 4,
        ),
      );

      expect(client.loadedPaths, <String>['/workspace/demo/src/main.styio']);
      expect(client.savedDocuments.single, <String, Object?>{
        'workspaceId': 'demo-workspace',
        'path': '/workspace/demo/src/main.styio',
        'documentText': 'remote := false\n',
        'revision': 4,
      });
    },
  );
}

class _RecordingHostedControlPlaneClient implements HostedControlPlaneClient {
  final List<String> loadedPaths = <String>[];
  final List<Map<String, Object?>> savedDocuments = <Map<String, Object?>>[];

  @override
  HostedControlPlaneConfig get config => const HostedControlPlaneConfig(
    baseUrl: 'https://hosted.example.test',
    workspaceRoot: '/workspace/demo',
    workspaceId: 'demo-workspace',
  );

  @override
  Future<Map<String, dynamic>> loadDocument({
    required String workspaceId,
    required String path,
  }) async {
    loadedPaths.add(path);
    return <String, dynamic>{
      'returncode': 0,
      'message': 'loaded hosted document',
      'payload': <String, Object?>{
        'path': path,
        'document_text': 'remote := true\n',
        'revision': '3',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> saveDocument({
    required String workspaceId,
    required String path,
    required String documentText,
    required int revision,
  }) async {
    savedDocuments.add(<String, Object?>{
      'workspaceId': workspaceId,
      'path': path,
      'documentText': documentText,
      'revision': revision,
    });
    return <String, dynamic>{
      'returncode': 0,
      'message': 'saved hosted document',
      'payload': <String, Object?>{
        'path': path,
        'revision': revision,
        'saved': true,
      },
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
