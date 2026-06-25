class TextPosition implements Comparable<TextPosition> {
  const TextPosition({
    required this.line,
    required this.column,
  }) : assert(line >= 0),
       assert(column >= 0);

  final int line;
  final int column;

  @override
  int compareTo(TextPosition other) {
    final lineCompare = line.compareTo(other.line);
    if (lineCompare != 0) {
      return lineCompare;
    }
    return column.compareTo(other.column);
  }

  @override
  bool operator ==(Object other) {
    return other is TextPosition &&
        other.line == line &&
        other.column == column;
  }

  @override
  int get hashCode => Object.hash(line, column);

  @override
  String toString() => 'TextPosition(line: $line, column: $column)';
}
