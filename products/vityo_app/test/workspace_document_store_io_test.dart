import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/document/document_encoding.dart';
import 'package:vityo_app/src/ide/editor/document/document_state.dart';
import 'package:vityo_app/src/ide/local_service/vityod_client.dart';
import 'package:vityo_app/src/ide/workspace/workspace_document_store_io.dart';

void main() {
  test(
    'vityod document store persists revisions and encoding across daemon restart',
    () async {
      if (Platform.isWindows) return;
      final executable = _findVityodExecutable();
      expect(executable.existsSync(), isTrue);
      final temporary = await Directory.systemTemp.createTemp('vd-store-');
      final endpoint = '${temporary.path}/service.sock';

      var daemon = await _startDaemon(executable, endpoint);
      var client = await _connect(endpoint, 'store-client-1');
      var store = VityodWorkspaceDocumentStore(client: client);
      const document = DocumentState(
        documentId: 'lib/main.styio',
        text: 'value = 1',
        revision: 0,
        encoding: DocumentEncoding.utf8WithBom,
      );
      await store.saveDocument(document);
      final loaded = await store.loadDocument(document.documentId);
      expect(loaded.text, document.text);
      expect(loaded.revision, 1);
      expect(loaded.encoding, DocumentEncoding.utf8WithBom);

      await client.dispose();
      daemon.kill();
      await daemon.exitCode.timeout(const Duration(seconds: 5));

      daemon = await _startDaemon(executable, endpoint);
      client = await _connect(endpoint, 'store-client-2');
      store = VityodWorkspaceDocumentStore(client: client);
      final reopened = await store.loadDocument(document.documentId);
      expect(reopened.text, document.text);
      expect(reopened.revision, 1);
      expect(reopened.encoding, DocumentEncoding.utf8WithBom);
      expect(await store.documentExists(document.documentId), isTrue);
      expect(await store.deleteDocument(document.documentId), isTrue);
      expect(await store.documentExists(document.documentId), isFalse);

      await expectLater(
        store.saveDocument(
          const DocumentState(
            documentId: '../outside',
            text: 'denied',
            revision: 0,
          ),
        ),
        throwsA(
          isA<VityodWorkspaceStoreFailure>().having(
            (failure) => failure.code,
            'code',
            'workspace_root_escape',
          ),
        ),
      );

      await client.dispose();
      daemon.kill();
      await daemon.exitCode.timeout(const Duration(seconds: 5));
      await temporary.delete(recursive: true);
    },
    skip: !(Platform.isMacOS || Platform.isLinux)
        ? 'Unix local-service transport only.'
        : false,
  );
}

Future<Process> _startDaemon(File executable, String endpoint) async {
  final daemon = await Process.start(executable.path, <String>[
    '--serve',
    '--endpoint',
    endpoint,
  ]);
  await _waitForEndpoint(endpoint);
  return daemon;
}

Future<VityodClient> _connect(String endpoint, String clientId) async {
  final client = VityodClient(
    transport: SocketVityodTransport(endpointPath: endpoint),
    clientInstanceId: clientId,
  );
  await client.connect();
  return client;
}

File _findVityodExecutable() {
  var directory = Directory.current.absolute;
  for (var depth = 0; depth < 12; depth += 1) {
    final candidate = File(
      '${directory.path}/native/vityod/target/debug/vityod',
    );
    if (candidate.existsSync()) return candidate;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  return File('native/vityod/target/debug/vityod');
}

Future<void> _waitForEndpoint(String endpoint) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (true) {
    try {
      final probe = await Socket.connect(
        InternetAddress(endpoint, type: InternetAddressType.unix),
        0,
      );
      await probe.close();
      return;
    } on SocketException {
      // A stale endpoint may remain until the new daemon owns the lock.
    }
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('vityod workspace endpoint was not created');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
