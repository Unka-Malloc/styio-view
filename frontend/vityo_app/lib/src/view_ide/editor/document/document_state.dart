class DocumentState {
  const DocumentState({
    required this.documentId,
    required this.text,
    required this.revision,
  });

  final String documentId;
  final String text;
  final int revision;

  int get length => text.length;

  List<String> get lines => text.split('\n');

  List<int> get lineStarts {
    final starts = <int>[];
    var cursor = 0;

    for (final line in lines) {
      starts.add(cursor);
      cursor += line.length;
      if (cursor < text.length) {
        cursor += 1;
      }
    }

    return starts;
  }

  DocumentPosition positionForOffset(int offset) {
    final safeOffset = offset.clamp(0, length);
    final starts = lineStarts;

    for (var index = starts.length - 1; index >= 0; index -= 1) {
      final start = starts[index];
      if (safeOffset >= start) {
        return DocumentPosition(
          line: index,
          column: safeOffset - start,
        );
      }
    }

    return const DocumentPosition(line: 0, column: 0);
  }

  int offsetForLineColumn({
    required int line,
    required int column,
  }) {
    final allLines = lines;
    if (allLines.isEmpty) {
      return 0;
    }

    final safeLine = line.clamp(0, allLines.length - 1);
    final safeColumn = column.clamp(0, allLines[safeLine].length);
    return lineStarts[safeLine] + safeColumn;
  }

  DocumentState replaceRange({
    required int start,
    required int end,
    required String replacement,
  }) {
    final normalizedStart = start.clamp(0, length);
    final normalizedEnd = end.clamp(normalizedStart, length);
    final nextText = text.replaceRange(
      normalizedStart,
      normalizedEnd,
      replacement,
    );

    return DocumentState(
      documentId: documentId,
      text: nextText,
      revision: revision + 1,
    );
  }
}

class DocumentPosition {
  const DocumentPosition({
    required this.line,
    required this.column,
  });

  final int line;
  final int column;
}
