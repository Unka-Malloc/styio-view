class TextRange {
  const TextRange({
    required this.start,
    required this.end,
  }) : assert(start >= 0),
       assert(end >= start);

  final int start;
  final int end;

  int get length => end - start;
  bool get isCollapsed => start == end;

  bool containsOffset(int offset) {
    if (isCollapsed) {
      return offset == start;
    }
    return offset >= start && offset < end;
  }

  bool intersects(TextRange other) {
    return start < other.end && other.start < end;
  }

  TextRange clamp(int documentLength) {
    final safeLength = documentLength < 0 ? 0 : documentLength;
    final safeStart = start.clamp(0, safeLength).toInt();
    final safeEnd = end.clamp(safeStart, safeLength).toInt();
    return TextRange(start: safeStart, end: safeEnd);
  }

  @override
  bool operator ==(Object other) {
    return other is TextRange &&
        other.start == start &&
        other.end == end;
  }

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'TextRange(start: $start, end: $end)';
}
