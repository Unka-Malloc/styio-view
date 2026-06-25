import 'text_position.dart';
import 'text_range.dart';

abstract class TextBuffer {
  int get length;
  int get lineCount;
  List<int> get lineStarts;
  List<String> get lines;

  String getText([TextRange? range]);
  String lineAt(int line);
  TextPosition positionAt(int offset);
  int offsetAt(TextPosition position);
  TextBufferSnapshot snapshot();
  PieceTreeTextBuffer replace(TextRange range, String replacement);
}

class PieceTreeTextBuffer implements TextBuffer {
  PieceTreeTextBuffer._({
    required String original,
    required String add,
    required List<_Piece> pieces,
    required int length,
    TextBufferSnapshot? snapshot,
  }) : _original = original,
       _add = add,
       _pieces = List<_Piece>.unmodifiable(pieces),
       _length = length,
       _snapshot = snapshot;

  factory PieceTreeTextBuffer.fromText(String text) {
    return PieceTreeTextBuffer._(
      original: text,
      add: '',
      pieces: text.isEmpty
          ? const <_Piece>[]
          : <_Piece>[
              _Piece(
                source: _PieceSource.original,
                start: 0,
                length: text.length,
              ),
            ],
      length: text.length,
    );
  }

  factory PieceTreeTextBuffer.fromSnapshot(TextBufferSnapshot snapshot) {
    return PieceTreeTextBuffer._(
      original: snapshot._original,
      add: snapshot._add,
      pieces: snapshot._pieces,
      length: snapshot.length,
      snapshot: snapshot,
    );
  }

  final String _original;
  final String _add;
  final List<_Piece> _pieces;
  final int _length;
  TextBufferSnapshot? _snapshot;

  @override
  int get length => _length;

  @override
  int get lineCount => snapshot().lineCount;

  @override
  List<int> get lineStarts => snapshot().lineStarts;

  @override
  List<String> get lines => snapshot().lines;

  @override
  String getText([TextRange? range]) => snapshot().getText(range);

  @override
  String lineAt(int line) => snapshot().lineAt(line);

  @override
  TextPosition positionAt(int offset) => snapshot().positionAt(offset);

  @override
  int offsetAt(TextPosition position) => snapshot().offsetAt(position);

  @override
  TextBufferSnapshot snapshot() {
    return _snapshot ??= TextBufferSnapshot._(
      original: _original,
      add: _add,
      pieces: _pieces,
      length: _length,
    );
  }

  @override
  PieceTreeTextBuffer replace(TextRange range, String replacement) {
    final normalizedRange = range.clamp(length);
    final nextPieces = <_Piece>[];
    final suffixPieces = <_Piece>[];
    var cursor = 0;

    for (final piece in _pieces) {
      final pieceStart = cursor;
      final pieceEnd = cursor + piece.length;

      if (pieceEnd <= normalizedRange.start) {
        nextPieces.add(piece);
      } else if (pieceStart >= normalizedRange.end) {
        suffixPieces.add(piece);
      } else {
        if (normalizedRange.start > pieceStart) {
          nextPieces.add(piece.slice(0, normalizedRange.start - pieceStart));
        }
        if (normalizedRange.end < pieceEnd) {
          suffixPieces.add(
            piece.slice(
              normalizedRange.end - pieceStart,
              pieceEnd - normalizedRange.end,
            ),
          );
        }
      }

      cursor = pieceEnd;
    }

    final nextAdd = replacement.isEmpty ? _add : _add + replacement;
    if (replacement.isNotEmpty) {
      nextPieces.add(
        _Piece(
          source: _PieceSource.add,
          start: _add.length,
          length: replacement.length,
        ),
      );
    }
    nextPieces.addAll(suffixPieces);

    return PieceTreeTextBuffer._(
      original: _original,
      add: nextAdd,
      pieces: _coalescePieces(nextPieces),
      length: length - normalizedRange.length + replacement.length,
    );
  }

  static List<_Piece> _coalescePieces(List<_Piece> pieces) {
    if (pieces.isEmpty) {
      return const <_Piece>[];
    }

    final merged = <_Piece>[];
    for (final piece in pieces) {
      if (piece.length == 0) {
        continue;
      }
      if (merged.isNotEmpty && merged.last.canMerge(piece)) {
        final previous = merged.removeLast();
        merged.add(
          _Piece(
            source: previous.source,
            start: previous.start,
            length: previous.length + piece.length,
          ),
        );
      } else {
        merged.add(piece);
      }
    }
    return List<_Piece>.unmodifiable(merged);
  }
}

class TextBufferSnapshot implements TextBuffer {
  TextBufferSnapshot._({
    required String original,
    required String add,
    required List<_Piece> pieces,
    required int length,
  }) : _original = original,
       _add = add,
       _pieces = List<_Piece>.unmodifiable(pieces),
       _length = length;

  factory TextBufferSnapshot.fromText(String text) {
    return PieceTreeTextBuffer.fromText(text).snapshot();
  }

  final String _original;
  final String _add;
  final List<_Piece> _pieces;
  final int _length;
  String? _cachedText;
  _LineMap? _cachedLineMap;
  List<String>? _cachedLines;

  String get text => _cachedText ??= _materialize();

  _LineMap get _lineMap => _cachedLineMap ??= _LineMap.fromText(text);

  @override
  int get length => _length;

  @override
  int get lineCount => _lineMap.lineCount;

  @override
  List<int> get lineStarts => _lineMap.lineStarts;

  @override
  List<String> get lines {
    return _cachedLines ??= List<String>.unmodifiable(
      List<String>.generate(lineCount, lineAt),
    );
  }

  @override
  String getText([TextRange? range]) {
    if (range == null) {
      return text;
    }
    final normalizedRange = range.clamp(length);
    return text.substring(normalizedRange.start, normalizedRange.end);
  }

  @override
  String lineAt(int line) {
    if (lineCount == 0) {
      return '';
    }
    final safeLine = line.clamp(0, lineCount - 1).toInt();
    return text.substring(
      _lineMap.lineStarts[safeLine],
      _lineMap.lineContentEnds[safeLine],
    );
  }

  @override
  TextPosition positionAt(int offset) {
    final safeOffset = offset.clamp(0, length).toInt();
    final line = _lineMap.lineForOffset(safeOffset);
    final lineStart = _lineMap.lineStarts[line];
    final lineContentEnd = _lineMap.lineContentEnds[line];
    final column = safeOffset.clamp(lineStart, lineContentEnd).toInt() -
        lineStart;
    return TextPosition(line: line, column: column);
  }

  @override
  int offsetAt(TextPosition position) {
    if (lineCount == 0) {
      return 0;
    }
    final safeLine = position.line.clamp(0, lineCount - 1).toInt();
    final lineStart = _lineMap.lineStarts[safeLine];
    final lineContentEnd = _lineMap.lineContentEnds[safeLine];
    return (lineStart + position.column)
        .clamp(lineStart, lineContentEnd)
        .toInt();
  }

  @override
  TextBufferSnapshot snapshot() => this;

  @override
  PieceTreeTextBuffer replace(TextRange range, String replacement) {
    return PieceTreeTextBuffer.fromSnapshot(this).replace(range, replacement);
  }

  String _materialize() {
    if (_pieces.isEmpty) {
      return '';
    }
    if (_pieces.length == 1) {
      final piece = _pieces.single;
      final sourceText = piece.source == _PieceSource.original
          ? _original
          : _add;
      if (piece.start == 0 && piece.length == sourceText.length) {
        return sourceText;
      }
    }

    final buffer = StringBuffer();
    for (final piece in _pieces) {
      final sourceText = piece.source == _PieceSource.original
          ? _original
          : _add;
      buffer.write(sourceText.substring(piece.start, piece.end));
    }
    return buffer.toString();
  }
}

enum _PieceSource {
  original,
  add,
}

class _Piece {
  const _Piece({
    required this.source,
    required this.start,
    required this.length,
  });

  final _PieceSource source;
  final int start;
  final int length;

  int get end => start + length;

  _Piece slice(int localStart, int sliceLength) {
    return _Piece(
      source: source,
      start: start + localStart,
      length: sliceLength,
    );
  }

  bool canMerge(_Piece other) {
    return source == other.source && end == other.start;
  }
}

class _LineMap {
  _LineMap._({
    required List<int> lineStarts,
    required List<int> lineContentEnds,
  }) : lineStarts = List<int>.unmodifiable(lineStarts),
       lineContentEnds = List<int>.unmodifiable(lineContentEnds);

  factory _LineMap.fromText(String text) {
    final starts = <int>[0];
    final ends = <int>[];

    var index = 0;
    while (index < text.length) {
      final codeUnit = text.codeUnitAt(index);
      if (codeUnit == 0x0A) {
        ends.add(index);
        index += 1;
        starts.add(index);
        continue;
      }
      if (codeUnit == 0x0D) {
        ends.add(index);
        if (index + 1 < text.length && text.codeUnitAt(index + 1) == 0x0A) {
          index += 2;
        } else {
          index += 1;
        }
        starts.add(index);
        continue;
      }
      index += 1;
    }

    ends.add(text.length);
    return _LineMap._(lineStarts: starts, lineContentEnds: ends);
  }

  final List<int> lineStarts;
  final List<int> lineContentEnds;

  int get lineCount => lineStarts.length;

  int lineForOffset(int offset) {
    if (lineStarts.isEmpty || offset <= lineStarts.first) {
      return 0;
    }
    if (offset >= lineStarts.last) {
      return lineStarts.length - 1;
    }

    var low = 0;
    var high = lineStarts.length - 1;
    while (low < high) {
      final mid = (low + high + 1) >> 1;
      if (lineStarts[mid] <= offset) {
        low = mid;
      } else {
        high = mid - 1;
      }
    }
    return low;
  }
}
