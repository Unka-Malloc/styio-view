import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/editor/document/text_buffer/text_buffer.dart';

void main() {
  test('maps unicode and CRLF line endings by UTF-16 offsets', () {
    const text = 'alpha\r\nemoji 😀\rbare\n尾';
    final snapshot = TextBufferSnapshot.fromText(text);

    expect(snapshot.length, text.length);
    expect(snapshot.lineStarts, <int>[0, 7, 16, 21]);
    expect(snapshot.lines, <String>['alpha', 'emoji 😀', 'bare', '尾']);
    expect(snapshot.lineAt(1), 'emoji 😀');
    expect(snapshot.getText(const TextRange(start: 7, end: 15)), 'emoji 😀');

    expect(snapshot.positionAt(5), const TextPosition(line: 0, column: 5));
    expect(snapshot.positionAt(6), const TextPosition(line: 0, column: 5));
    expect(snapshot.positionAt(7), const TextPosition(line: 1, column: 0));
    expect(
      snapshot.offsetAt(const TextPosition(line: 1, column: 99)),
      15,
    );
  });

  test('piece table edits match String.replaceRange for random unicode edits', () {
    final rng = Random(7349);
    final replacements = <String>[
      '',
      'x',
      '\n',
      '\r\n',
      'Ω',
      '😀',
      'left\rbreak',
      '尾\nnext',
    ];

    var oracle = 'α\nbeta\r\ngamma😀\rdelta';
    var buffer = PieceTreeTextBuffer.fromText(oracle);

    for (var editIndex = 0; editIndex < 500; editIndex += 1) {
      final start = oracle.isEmpty ? 0 : rng.nextInt(oracle.length + 1);
      final remaining = oracle.length - start;
      final end = start + (remaining == 0 ? 0 : rng.nextInt(remaining + 1));
      final replacement = replacements[rng.nextInt(replacements.length)];

      buffer = buffer.replace(
        TextRange(start: start, end: end),
        replacement,
      );
      oracle = oracle.replaceRange(start, end, replacement);

      if (editIndex % 11 != 0 && editIndex != 499) {
        continue;
      }

      final snapshot = buffer.snapshot();
      final oracleLines = _OracleLineMap.fromText(oracle);
      expect(snapshot.text, oracle, reason: 'edit $editIndex text');
      expect(snapshot.length, oracle.length, reason: 'edit $editIndex length');
      expect(
        snapshot.lineStarts,
        oracleLines.lineStarts,
        reason: 'edit $editIndex line starts',
      );
      expect(
        snapshot.lines,
        oracleLines.lines,
        reason: 'edit $editIndex lines',
      );

      for (final offset in _sampleOffsets(oracle.length)) {
        expect(
          snapshot.positionAt(offset),
          oracleLines.positionAt(offset),
          reason: 'edit $editIndex offset $offset',
        );
      }
    }
  });

  test('DocumentState facade caches line queries and preserves revision edits', () {
    const document = DocumentState(
      documentId: 'sample.styio',
      text: 'one\r\ntwo\nthree',
      revision: 5,
    );

    expect(document.lines, <String>['one', 'two', 'three']);
    expect(document.lineStarts, <int>[0, 5, 9]);
    expect(identical(document.lineStarts, document.lineStarts), isTrue);
    expect(
      document.positionForOffset(4),
      const DocumentPosition(line: 0, column: 3),
    );
    expect(document.offsetForLineColumn(line: 1, column: 99), 8);

    final next = document.replaceRange(start: 5, end: 8, replacement: 'TWO');

    expect(next.text, 'one\r\nTWO\nthree');
    expect(next.revision, 6);
    expect(next.lines, <String>['one', 'TWO', 'three']);
    expect(identical(next.lineStarts, next.lineStarts), isTrue);
  });

  test('large documents reuse indexed line starts for line-column mapping', () {
    final text = List<String>.generate(
      60000,
      (index) => 'line_$index ${index.isEven ? 'α' : '😀'}',
    ).join('\r\n');
    final document = DocumentState(
      documentId: 'large.styio',
      text: text,
      revision: 0,
    ).withTextBuffer();

    expect(document.lines.length, 60000);
    expect(identical(document.lineStarts, document.lineStarts), isTrue);

    for (var line = 0; line < 60000; line += 7919) {
      final offset = document.offsetForLineColumn(line: line, column: 4);
      final position = document.positionForOffset(offset);
      expect(position.line, line);
      expect(position.column, 4);
    }

    final insertionOffset = document.offsetForLineColumn(
      line: 30000,
      column: 0,
    );
    final next = document.replaceRange(
      start: insertionOffset,
      end: insertionOffset,
      replacement: 'inserted\n',
    );

    expect(next.lines.length, 60001);
    expect(next.lines[30000], 'inserted');
  });
}

List<int> _sampleOffsets(int length) {
  return <int>{
    0,
    length,
    if (length > 0) 1,
    if (length > 1) length - 1,
    length ~/ 2,
  }.toList()
    ..sort();
}

class _OracleLineMap {
  _OracleLineMap._({
    required this.lineStarts,
    required this.lineContentEnds,
    required this.lines,
  });

  factory _OracleLineMap.fromText(String text) {
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

    return _OracleLineMap._(
      lineStarts: List<int>.unmodifiable(starts),
      lineContentEnds: List<int>.unmodifiable(ends),
      lines: List<String>.unmodifiable(
        List<String>.generate(
          starts.length,
          (line) => text.substring(starts[line], ends[line]),
        ),
      ),
    );
  }

  final List<int> lineStarts;
  final List<int> lineContentEnds;
  final List<String> lines;

  TextPosition positionAt(int offset) {
    final safeOffset = offset.clamp(0, lineContentEnds.last).toInt();
    final line = _lineForOffset(safeOffset);
    final lineStart = lineStarts[line];
    final lineContentEnd = lineContentEnds[line];
    final column = safeOffset.clamp(lineStart, lineContentEnd).toInt() -
        lineStart;
    return TextPosition(line: line, column: column);
  }

  int _lineForOffset(int offset) {
    if (offset <= lineStarts.first) {
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
