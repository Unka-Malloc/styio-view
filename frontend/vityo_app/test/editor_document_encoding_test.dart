import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_encoding.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/editor/document/text_buffer/text_buffer.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_store_io.dart';

void main() {
  group('DocumentEncoding', () {
    test('default encoding is utf8', () {
      expect(DocumentEncoding.utf8.wireValue, 'utf-8');
      expect(DocumentEncoding.utf8.label, 'UTF-8');
    });

    test('utf8WithBom has distinct wire value', () {
      expect(DocumentEncoding.utf8WithBom.wireValue, 'utf-8-bom');
    });

    test('round-trips through fromWireValue', () {
      for (final encoding in DocumentEncoding.values) {
        final restored = DocumentEncoding.fromWireValue(encoding.wireValue);
        expect(
          restored,
          encoding,
          reason: '${encoding.wireValue} should round-trip',
        );
      }
    });

    test('fromWireValue returns null for unknown value', () {
      expect(DocumentEncoding.fromWireValue('unknown-enc'), isNull);
      expect(DocumentEncoding.fromWireValue('utf-7'), isNull);
    });
  });

  group('DocumentState encoding', () {
    test('DocumentState preserves encoding through replaceRange', () {
      const doc = DocumentState(
        documentId: 'test.styio',
        text: 'original',
        revision: 1,
        encoding: DocumentEncoding.utf8WithBom,
      );

      expect(doc.encoding, DocumentEncoding.utf8WithBom);

      final next = doc.replaceRange(start: 0, end: 8, replacement: 'modified');
      expect(next.encoding, DocumentEncoding.utf8WithBom);
      expect(next.text, 'modified');
    });

    test('DocumentState defaults to null encoding', () {
      const doc = DocumentState(
        documentId: 'test.styio',
        text: 'plain',
        revision: 0,
      );
      expect(doc.encoding, isNull);
    });

    test('fromTextBuffer preserves encoding', () {
      const encoding = DocumentEncoding.utf16le;
      final snapshot = TextBufferSnapshot.fromText('test');
      final doc = DocumentState.fromTextBuffer(
        documentId: 'test.styio',
        textBufferSnapshot: snapshot,
        revision: 0,
        encoding: encoding,
      );
      expect(doc.encoding, encoding);
    });
  });

  group('FileSystemWorkspaceDocumentStore encoding round-trip', () {
    Future<FileSystemWorkspaceDocumentStore> createStore(
      Directory tempRoot,
    ) async {
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final storeDir = Directory('${tempRoot.path}/store');
      final rootDir = Directory('${storeDir.path}/workspace');
      return FileSystemWorkspaceDocumentStore(
        rootDir,
        fileSystemManager: fileSystemManager,
      );
    }

    test('save and load preserves utf8WithBom encoding', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_encode_roundtrip_test1_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final store = await createStore(tempRoot);

      const doc = DocumentState(
        documentId: 'test.styio',
        text: 'value = 1',
        revision: 0,
        encoding: DocumentEncoding.utf8WithBom,
      );
      await store.saveDocument(doc);
      final loaded = await store.loadDocument('test.styio');

      expect(loaded.text, doc.text);
      expect(loaded.encoding, DocumentEncoding.utf8WithBom);
    });

    test('save and load omits encoding for default utf8', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_encode_roundtrip_test2_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final store = await createStore(tempRoot);

      const doc = DocumentState(
        documentId: 'test.styio',
        text: 'value = 1',
        revision: 0,
      );
      await store.saveDocument(doc);
      final loaded = await store.loadDocument('test.styio');

      expect(loaded.text, doc.text);
      expect(loaded.encoding, isNull);
    });

    test('save and load preserves latin1 encoding', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_encode_roundtrip_test3_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final store = await createStore(tempRoot);

      const doc = DocumentState(
        documentId: 'test.styio',
        text: 'value = 1',
        revision: 0,
        encoding: DocumentEncoding.latin1,
      );
      await store.saveDocument(doc);
      final loaded = await store.loadDocument('test.styio');

      expect(loaded.text, doc.text);
      expect(loaded.encoding, DocumentEncoding.latin1);
    });
  });
}
