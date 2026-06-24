import '../editor/document/document_state.dart';
import '../editor/selection/selection_state.dart';
import '../language/contract/language_contract.dart';

enum RunUnitSelectionKind {
  explicitSelection,
  topLevelBlock,
  paragraph,
  wholeDocument,
}

class RunUnitSelection {
  const RunUnitSelection({
    required this.kind,
    required this.range,
    required this.text,
  });

  final RunUnitSelectionKind kind;
  final SourceRange range;
  final String text;
}

RunUnitSelection selectRunUnitForEditor({
  required DocumentState document,
  required SelectionState selection,
}) {
  if (!selection.isCollapsed) {
    final start = selection.start.clamp(0, document.length).toInt();
    final end = selection.end.clamp(start, document.length).toInt();
    return _selection(
      document: document,
      kind: RunUnitSelectionKind.explicitSelection,
      start: start,
      end: end,
    );
  }

  if (document.text.trim().isEmpty) {
    return _selection(
      document: document,
      kind: RunUnitSelectionKind.wholeDocument,
      start: 0,
      end: document.length,
    );
  }

  final lineRanges = _lineRanges(document);
  final seedLine = _nearestContentLine(
    document: document,
    lineRanges: lineRanges,
    offset: selection.extentOffset,
  );
  final topLevelLines = _topLevelDeclarationLines(document, lineRanges);
  final topLevelStart = _lastLineAtOrBefore(topLevelLines, seedLine);
  if (topLevelStart != null) {
    final nextTopLevelStart = _firstLineAfter(topLevelLines, topLevelStart);
    return _selection(
      document: document,
      kind: RunUnitSelectionKind.topLevelBlock,
      start: lineRanges[topLevelStart].start,
      end: _trimTrailingBlankLines(
        document,
        lineRanges,
        nextTopLevelStart == null
            ? document.length
            : lineRanges[nextTopLevelStart].start,
      ),
    );
  }

  final paragraph = _paragraphAroundLine(document, lineRanges, seedLine);
  if (paragraph != null) {
    return _selection(
      document: document,
      kind: RunUnitSelectionKind.paragraph,
      start: paragraph.start,
      end: paragraph.end,
    );
  }

  return _selection(
    document: document,
    kind: RunUnitSelectionKind.wholeDocument,
    start: 0,
    end: document.length,
  );
}

RunUnitSelection _selection({
  required DocumentState document,
  required RunUnitSelectionKind kind,
  required int start,
  required int end,
}) {
  final range = SourceRange(start: start, end: end);
  return RunUnitSelection(
    kind: kind,
    range: range,
    text: document.text.substring(start, end),
  );
}

List<SourceRange> _lineRanges(DocumentState document) {
  final ranges = <SourceRange>[];
  final starts = document.lineStarts;
  final lines = document.lines;
  for (var index = 0; index < lines.length; index += 1) {
    final start = starts[index];
    ranges.add(SourceRange(start: start, end: start + lines[index].length));
  }
  return ranges;
}

int _nearestContentLine({
  required DocumentState document,
  required List<SourceRange> lineRanges,
  required int offset,
}) {
  final position = document.positionForOffset(offset);
  final line = position.line.clamp(0, lineRanges.length - 1).toInt();
  if (_lineText(document, lineRanges[line]).trim().isNotEmpty) {
    return line;
  }

  for (var index = line - 1; index >= 0; index -= 1) {
    if (_lineText(document, lineRanges[index]).trim().isNotEmpty) {
      return index;
    }
  }
  for (var index = line + 1; index < lineRanges.length; index += 1) {
    if (_lineText(document, lineRanges[index]).trim().isNotEmpty) {
      return index;
    }
  }
  return line;
}

List<int> _topLevelDeclarationLines(
  DocumentState document,
  List<SourceRange> lineRanges,
) {
  final result = <int>[];
  var depth = 0;
  for (var index = 0; index < lineRanges.length; index += 1) {
    final line = _lineText(document, lineRanges[index]);
    final trimmed = line.trimLeft();
    if (depth == 0 && _looksLikeTopLevelDeclaration(line, trimmed)) {
      result.add(index);
    }
    depth = _nextBraceDepth(depth, line);
  }
  return result;
}

bool _looksLikeTopLevelDeclaration(String line, String trimmed) {
  if (trimmed.isEmpty || trimmed.startsWith('//')) {
    return false;
  }
  if (line.length != trimmed.length) {
    return false;
  }
  return trimmed.startsWith('#') ||
      trimmed.startsWith('@') ||
      trimmed.contains(':=') ||
      trimmed.contains('=>') ||
      trimmed.contains('||>');
}

int _nextBraceDepth(int current, String line) {
  var depth = current;
  for (final unit in line.codeUnits) {
    if (unit == 123) {
      depth += 1;
    } else if (unit == 125 && depth > 0) {
      depth -= 1;
    }
  }
  return depth;
}

int? _lastLineAtOrBefore(List<int> lines, int target) {
  int? selected;
  for (final line in lines) {
    if (line > target) {
      break;
    }
    selected = line;
  }
  return selected;
}

int? _firstLineAfter(List<int> lines, int target) {
  for (final line in lines) {
    if (line > target) {
      return line;
    }
  }
  return null;
}

SourceRange? _paragraphAroundLine(
  DocumentState document,
  List<SourceRange> lineRanges,
  int seedLine,
) {
  var startLine = seedLine;
  while (startLine > 0 &&
      _lineText(document, lineRanges[startLine - 1]).trim().isNotEmpty) {
    startLine -= 1;
  }

  var endLine = seedLine;
  while (endLine + 1 < lineRanges.length &&
      _lineText(document, lineRanges[endLine + 1]).trim().isNotEmpty) {
    endLine += 1;
  }

  final start = lineRanges[startLine].start;
  final end = lineRanges[endLine].end;
  if (start >= end) {
    return null;
  }
  return SourceRange(start: start, end: end);
}

int _trimTrailingBlankLines(
  DocumentState document,
  List<SourceRange> lineRanges,
  int end,
) {
  var selectedEnd = end.clamp(0, document.length).toInt();
  for (var index = lineRanges.length - 1; index >= 0; index -= 1) {
    final range = lineRanges[index];
    if (range.start >= selectedEnd) {
      continue;
    }
    final text = _lineText(document, range);
    if (text.trim().isNotEmpty) {
      return range.end;
    }
    selectedEnd = range.start;
  }
  return selectedEnd;
}

String _lineText(DocumentState document, SourceRange range) {
  return document.text.substring(range.start, range.end);
}
