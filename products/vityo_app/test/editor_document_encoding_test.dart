import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/editor/document/document_encoding.dart';
import 'package:vityo_app/src/ide/editor/document/document_state.dart';
import 'package:vityo_app/src/ide/editor/document/text_buffer/text_buffer.dart';

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
}
