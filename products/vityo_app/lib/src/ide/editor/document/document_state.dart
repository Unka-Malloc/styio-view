import 'document_encoding.dart';
import 'text_buffer/text_buffer.dart';

class DocumentState {
  const DocumentState({
    required this.documentId,
    required this.text,
    required this.revision,
    this.encoding,
  });

  factory DocumentState.fromTextBuffer({
    required String documentId,
    required TextBufferSnapshot textBufferSnapshot,
    required int revision,
    DocumentEncoding? encoding,
  }) {
    final document = DocumentState(
      documentId: documentId,
      text: textBufferSnapshot.text,
      revision: revision,
      encoding: encoding,
    );
    _snapshotCache[document] = textBufferSnapshot;
    return document;
  }

  static final Expando<TextBufferSnapshot> _snapshotCache =
      Expando<TextBufferSnapshot>('DocumentState.textBufferSnapshot');

  final String documentId;
  final String text;
  final int revision;
  final DocumentEncoding? encoding;

  int get length => text.length;

  TextBufferSnapshot get textBufferSnapshot {
    final cached = _snapshotCache[this];
    if (cached != null) {
      return cached;
    }
    final snapshot = TextBufferSnapshot.fromText(text);
    _snapshotCache[this] = snapshot;
    return snapshot;
  }

  PieceTreeTextBuffer get textBuffer {
    return PieceTreeTextBuffer.fromSnapshot(textBufferSnapshot);
  }

  DocumentState withTextBuffer() {
    textBufferSnapshot;
    return this;
  }

  List<String> get lines => textBufferSnapshot.lines;

  List<int> get lineStarts => textBufferSnapshot.lineStarts;

  DocumentPosition positionForOffset(int offset) {
    final position = textBufferSnapshot.positionAt(offset);
    return DocumentPosition(line: position.line, column: position.column);
  }

  int offsetForLineColumn({required int line, required int column}) {
    return textBufferSnapshot.offsetAt(
      TextPosition(line: line < 0 ? 0 : line, column: column < 0 ? 0 : column),
    );
  }

  DocumentState replaceRange({
    required int start,
    required int end,
    required String replacement,
  }) {
    final normalizedStart = start.clamp(0, length);
    final normalizedEnd = end.clamp(normalizedStart, length);
    final nextSnapshot = textBuffer
        .replace(
          TextRange(start: normalizedStart.toInt(), end: normalizedEnd.toInt()),
          replacement,
        )
        .snapshot();

    return DocumentState.fromTextBuffer(
      documentId: documentId,
      textBufferSnapshot: nextSnapshot,
      revision: revision + 1,
      encoding: encoding,
    );
  }
}

class DocumentPosition extends TextPosition {
  const DocumentPosition({required super.line, required super.column});
}
