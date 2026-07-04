import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/integration/hosted_control_plane.dart';
import 'package:vityo_app/src/view_ide/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
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

  test(
    'hosted workspace file system provider routes vityo-hosted uris',
    () async {
      final client = _RecordingHostedControlPlaneClient();
      final provider = HostedWorkspaceFileSystemProvider(hostedClient: client);

      final uri = provider.uriFor('src/main.styio');
      expect(uri.toString(), 'vityo-hosted://demo-workspace/src/main.styio');

      final target = provider.route(uri);
      expect(target.workspaceId, 'demo-workspace');
      expect(target.documentPath, '/workspace/demo/src/main.styio');

      expect(await provider.readText(uri), 'remote := true\n');
      await provider.writeText(uri, 'remote := saved\n', revision: 7);
      expect(await provider.exists(uri), isTrue);

      expect(client.loadedPaths, <String>[
        '/workspace/demo/src/main.styio',
        '/workspace/demo/src/main.styio',
      ]);
      expect(client.savedDocuments.single, <String, Object?>{
        'workspaceId': 'demo-workspace',
        'path': '/workspace/demo/src/main.styio',
        'documentText': 'remote := saved\n',
        'revision': 7,
      });
    },
  );

  test(
    'hosted workspace file system provider reports unsupported operations',
    () {
      final client = _RecordingHostedControlPlaneClient();
      final provider = HostedWorkspaceFileSystemProvider(hostedClient: client);
      final uri = Uri.parse('vityo-hosted://demo-workspace/src/main.styio');

      final failure = provider.unsupportedOperation(
        operation: 'delete',
        target: uri,
      );

      expect(failure.kind, FileSystemFailureKind.unsupportedProvider);
      expect(failure.sourceManager, 'HostedWorkspaceFileSystemProvider');
      expect(failure.recoveryHint, contains('hosted document load/save'));
    },
  );

  test('file system provider router recognizes vityo-hosted uri scheme', () {
    final router = FileSystemProviderRouter(
      fileSystemManager: UnsupportedFileSystemManager(
        facts: FileSystemFacts.linuxDebianArm(),
      ),
    );

    final route = router.route(
      Uri.parse('vityo-hosted://demo-workspace/src/main.styio'),
      operation: 'readText',
    );

    expect(route.kind, FileSystemProviderRouteKind.hosted);
    expect(route.workspaceId, 'demo-workspace');
    expect(route.path, '/src/main.styio');
    expect(route.supported, isTrue);

    final invalid = router.route(
      Uri.parse('vityo-hosted:///'),
      operation: 'readText',
    );
    expect(invalid.kind, FileSystemProviderRouteKind.unsupported);
    expect(invalid.failure?.kind, FileSystemFailureKind.invalidPath);
  });
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
