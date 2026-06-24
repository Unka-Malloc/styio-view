/// Maintains a list of line start offsets for O(log n) line queries.
///
/// Supports LF, CRLF, and bare CR line endings and provides efficient
/// [offsetToLine] via binary search and O(1) [lineToOffset] lookups.
///
/// The index can be fully rebuilt via [rebuild] or incrementally invalidated
/// via [invalidateRange] for future piecewise rebuild optimization.
class LineIndex {
  List<int> _lineStarts;
  bool _isDirty = false;

  /// Creates an empty [LineIndex] (single line starting at offset 0).
  LineIndex() : _lineStarts = [0];

  /// Creates a [LineIndex] fully initialized from [text].
  LineIndex.fromText(String text) : _lineStarts = _computeLineStarts(text);

  /// Returns a read-only snapshot of the line start offsets.
  ///
  /// The first entry is always 0. Each subsequent entry is the
  /// UTF-16 code-unit offset at which the corresponding line begins.
  List<int> get lineStarts => List<int>.unmodifiable(_lineStarts);

  /// The number of lines in the document.
  int get lineCount => _lineStarts.length;

  /// Returns the line number (0-based) that contains the given UTF-16
  /// code-unit [offset].
  ///
  /// Runs in O(log n) via binary search on [lineStarts].
  ///
  /// If [offset] is out of range it is clamped: offsets below 0 return
  /// line 0, offsets beyond the document length return the last line.
  int offsetToLine(int offset) {
    if (_lineStarts.isEmpty) return 0;
    if (offset <= _lineStarts.first) return 0;
    if (offset >= _lineStarts.last) {
      // Walk forward for correct trailing-empty-line semantics.
      int line = _lineStarts.length - 1;
      while (line > 0 && offset > _lineStarts[line]) {
        // If offset is past the start of the last line it belongs there.
        break;
      }
      // If offset is ≥ the last recorded start, it's the last line.
      return line;
    }

    int lo = 0;
    int hi = _lineStarts.length - 1;
    while (lo < hi) {
      // Upper-mid to guarantee progress.
      final mid = (lo + hi + 1) >> 1;
      if (_lineStarts[mid] <= offset) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// Returns the UTF-16 code-unit offset of the start of the given [line]
  /// (0-based). Runs in O(1).
  ///
  /// If [line] is out of range it is clamped.
  int lineToOffset(int line) {
    if (_lineStarts.isEmpty) return 0;
    if (line <= 0) return _lineStarts.first;
    if (line >= _lineStarts.length) return _lineStarts.last;
    return _lineStarts[line];
  }

  /// Rebuilds the entire line index from [text].
  ///
  /// After calling this the index is fully synchronized and the dirty flag
  /// is cleared.
  void rebuild(String text) {
    _lineStarts = _computeLineStarts(text);
    _isDirty = false;
  }

  /// Marks the range [start, start + [length]) as needing recomputation.
  ///
  /// This is a no-op in the current simple implementation — call [rebuild]
  /// to re-synchronise.  In a future version the index may apply
  /// incremental updates based on dirty ranges.
  void invalidateRange(int start, int length) {
    // Tracking for future incremental rebuild.
    _isDirty = true;
  }

  /// Whether the index is stale and needs a [rebuild] call.
  bool get isDirty => _isDirty;

  @override
  String toString() => 'LineIndex(count: $lineCount, starts: $_lineStarts)';

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Scans [text] and returns a sorted list of UTF-16 code-unit offsets
  /// at which each line begins.
  ///
  /// Recognises LF (`\n`), CRLF (`\r\n`), and bare CR (`\r`) as line
  /// terminators.  A trailing line terminator produces a final empty-line
  /// entry (the offset after the terminator).
  static List<int> _computeLineStarts(String text) {
    // Most documents have at least one line.
    final starts = <int>[0];
    int i = 0;
    while (i < text.length) {
      final cu = text.codeUnitAt(i);
      if (cu == 0x0A) {
        // LF
        starts.add(i + 1);
        i += 1;
      } else if (cu == 0x0D) {
        // CR or CRLF
        if (i + 1 < text.length && text.codeUnitAt(i + 1) == 0x0A) {
          // CRLF — count as one break, skip both code units.
          starts.add(i + 2);
          i += 2;
        } else {
          // Bare CR
          starts.add(i + 1);
          i += 1;
        }
      } else {
        i += 1;
      }
    }
    return starts;
  }
}
