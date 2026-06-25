import '../../editor/document/range_index.dart';
import '../contract/language_contract.dart';

class DiagnosticRangeGate {
  DiagnosticRangeGate(this._diagnostics, {this.revision = 0})
    : _index = _buildIndex(_diagnostics, revision);

  final List<Diagnostic> _diagnostics;
  final int revision;
  RangeIndex<Diagnostic> _index;
  final List<Diagnostic> _pending = <Diagnostic>[];

  bool intersects(SourceRange range) {
    return _index.overlapsRange(start: range.start, end: range.end) ||
        _pending.any((diagnostic) => _rangesOverlap(diagnostic.range, range));
  }

  void add(Diagnostic diagnostic) {
    _diagnostics.add(diagnostic);
    _pending.add(diagnostic);
  }

  void addAll(Iterable<Diagnostic> diagnostics) {
    for (final diagnostic in diagnostics) {
      add(diagnostic);
    }
    flush();
  }

  void addIfNoOverlap(Diagnostic diagnostic) {
    if (!intersects(diagnostic.range)) {
      add(diagnostic);
    }
  }

  void addAllIfNoOverlap(Iterable<Diagnostic> diagnostics) {
    for (final diagnostic in diagnostics) {
      addIfNoOverlap(diagnostic);
    }
    flush();
  }

  void flush() {
    if (_pending.isEmpty) {
      return;
    }
    _index = _buildIndex(_diagnostics, revision);
    _pending.clear();
  }

  static RangeIndex<Diagnostic> _buildIndex(
    Iterable<Diagnostic> diagnostics,
    int revision,
  ) {
    return RangeIndex<Diagnostic>.fromValues(
      diagnostics,
      startOf: (diagnostic) => diagnostic.range.start,
      endOf: (diagnostic) => diagnostic.range.end,
      revision: revision,
      priorityOf: (diagnostic) => switch (diagnostic.severity) {
        DiagnosticSeverity.error => 30,
        DiagnosticSeverity.warning => 20,
        DiagnosticSeverity.hint => 10,
      },
      layerOf: (_) => 'diagnostics',
    );
  }

  static bool _rangesOverlap(SourceRange left, SourceRange right) {
    if (right.isCollapsed) {
      return _rangeContainsOffset(left, right.start);
    }
    if (left.isCollapsed) {
      return left.start >= right.start && left.start < right.end;
    }
    return left.start < right.end && right.start < left.end;
  }

  static bool _rangeContainsOffset(SourceRange range, int offset) {
    if (range.isCollapsed) {
      return range.start == offset;
    }
    return range.start <= offset && offset < range.end;
  }
}
