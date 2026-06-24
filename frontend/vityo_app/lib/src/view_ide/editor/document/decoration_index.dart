import 'dart:math' show max;

/// Static definitions for decoration layer identifiers and their rendering
/// priority order.
///
/// Layers are ordered from highest visual priority to lowest:
///   1. selection     (text selection highlights)
///   2. diagnostics   (error/warning squiggles)
///   3. semantic      (syntax token colors)
///   4. search        (search result match highlights)
///   5. inlayHint     (inlay parameter hints)
///   6. ghostText     (inline completion previews)
class DecorationLayers {
  DecorationLayers._();

  /// Selection highlights (highest visual priority).
  static const String selection = 'selection';

  /// Diagnostic squiggles (errors, warnings, hints).
  static const String diagnostics = 'diagnostics';

  /// Semantic token colors.
  static const String semantic = 'semantic';

  /// Search result match highlights.
  static const String search = 'search';

  /// Inlay hint annotations (parameter names, type hints).
  static const String inlayHint = 'inlayHint';

  /// Ghost text inline completion previews (lowest visual priority).
  static const String ghostText = 'ghostText';

  /// Returns the rendering priority for [layerId].
  ///
  /// Lower values are painted on top of (i.e. above) higher values.
  /// Unknown layer IDs receive priority 999 (bottom-most).
  static int priority(String layerId) => switch (layerId) {
    'selection' => 0,
    'diagnostics' => 1,
    'semantic' => 2,
    'search' => 3,
    'inlayHint' => 4,
    'ghostText' => 5,
    _ => 999,
  };
}

/// A single decoration span in the document.
///
/// Each span covers a half-open range `[start, end)` in code-unit offsets and
/// carries a [layerId], a user-defined sub-priority, the document [revision] at
/// creation time, and an opaque [payload] map.
class DecorationSpan {
  /// Creates a decoration span.
  const DecorationSpan({
    required this.layerId,
    required this.start,
    required this.end,
    this.priority = 0,
    this.revision = 0,
    this.payload,
  });

  /// The decoration layer identifier (e.g. `'selection'`, `'diagnostics'`).
  final String layerId;

  /// Start offset (code-unit index, inclusive).
  final int start;

  /// End offset (code-unit index, exclusive).
  final int end;

  /// Sub-priority within the same layer.
  ///
  /// Higher values are rendered on top.
  final int priority;

  /// Document revision when this span was created.
  ///
  /// Used by [DecorationIndex.invalidateStale] to batch-expire obsolete spans.
  final int revision;

  /// Optional payload associated with the decoration.
  ///
  /// Typical keys include `'color'`, `'tooltip'`, `'className'`, etc.
  final Map<String, Object?>? payload;

  /// The length of this span in code units.
  int get length => end - start;

  /// Returns `true` when [offset] falls inside `[start, end)`.
  bool contains(int offset) => offset >= start && offset < end;

  /// Returns `true` when this span overlaps [other] in range.
  ///
  /// Two spans intersect when their ranges share at least one code unit.
  bool intersects(DecorationSpan other) =>
      start < other.end && other.start < end;

  @override
  bool operator ==(Object other) =>
      other is DecorationSpan &&
      layerId == other.layerId &&
      start == other.start &&
      end == other.end &&
      priority == other.priority &&
      revision == other.revision;

  @override
  int get hashCode => Object.hash(layerId, start, end, priority, revision);

  @override
  String toString() =>
      'DecorationSpan(layerId: $layerId, [$start, $end), '
      'priority: $priority, revision: $revision)';
}

/// An indexed collection of [DecorationSpan]s supporting viewport queries and
/// offset adjustment on text edits.
///
/// ## Ordering
///
/// Spans are stored in a stable sorted order:
/// 1. Layer priority (0 = top-most, see [DecorationLayers]).
/// 2. Sub-priority (higher values first).
/// 3. Start offset (ascending).
/// 4. End offset (ascending, tie-breaker).
///
/// ## Complexity
///
/// | Operation            | Complexity         |
/// |----------------------|--------------------|
/// | `add`                | O(n) insertion     |
/// | `query`              | O(log n + k)       |
/// | `handleInsert`       | O(n) shift         |
/// | `handleDelete`       | O(n) shift+remove  |
/// | `removeWhere`        | O(n)               |
/// | `invalidateStale`    | O(n)               |
///
/// (n = total span count, k = matched spans in range.)
class DecorationIndex {
  /// Creates an empty decoration index.
  ///
  /// [documentRevision] is the starting revision number used when comparing
  /// spans during invalidation.
  DecorationIndex({int documentRevision = 0})
      : _documentRevision = documentRevision;

  /// The internal sorted span list (always sorted per [compareSpan]).
  final List<DecorationSpan> _spans = [];

  /// The current document revision tracked by this index.
  int _documentRevision;

  // ---------------------------------------------------------------------------
  // Comparator
  // ---------------------------------------------------------------------------

  /// Compares two spans according to the stable ordering rules.
  ///
  /// Returns a negative value when [a] should appear before [b].
  static int compareSpan(DecorationSpan a, DecorationSpan b) {
    // 1. Layer priority (ascending).
    final layerCmp = DecorationLayers.priority(a.layerId)
        .compareTo(DecorationLayers.priority(b.layerId));
    if (layerCmp != 0) return layerCmp;

    // 2. Sub-priority (descending — higher on top).
    final prioCmp = b.priority.compareTo(a.priority);
    if (prioCmp != 0) return prioCmp;

    // 3. Start offset (ascending).
    final startCmp = a.start.compareTo(b.start);
    if (startCmp != 0) return startCmp;

    // 4. End offset (ascending, tie-breaker).
    return a.end.compareTo(b.end);
  }

  // ---------------------------------------------------------------------------
  // Mutation
  // ---------------------------------------------------------------------------

  /// Adds [span] to the index, maintaining sorted order.
  ///
  /// Duplicates (spans equal via `==`) are silently ignored.
  void add(DecorationSpan span) {
    final index = _lowerBound(span);
    if (index < _spans.length && _spans[index] == span) {
      return; // duplicate
    }
    _spans.insert(index, span);
  }

  /// Removes every span that satisfies [predicate].
  void removeWhere(bool Function(DecorationSpan) predicate) {
    _spans.removeWhere(predicate);
  }

  /// Removes all spans from the index.
  void clear() {
    _spans.clear();
  }

  // ---------------------------------------------------------------------------
  // Query
  // ---------------------------------------------------------------------------

  /// Returns every span whose range intersects `[start, end)`.
  ///
  /// The result is sorted in the stable layer-priority order.
  /// Complexity: O(log n + k).
  List<DecorationSpan> query(int start, int end) {
    assert(start <= end, 'start ($start) must be <= end ($end)');
    if (_spans.isEmpty || end <= _spans.first.start) return const [];

    // Use binary search to locate the first span whose end > start.
    final firstIndex = _firstIntersecting(start);
    if (firstIndex == _spans.length) return const [];

    final result = <DecorationSpan>[];
    for (var i = firstIndex; i < _spans.length; i++) {
      final span = _spans[i];
      if (span.start >= end) break;       // past the viewport
      if (span.end > start) {
        result.add(span);                 // intersects
      }
    }
    return result;
  }

  /// Returns spans intersecting `[start, end)` that belong to [layerId].
  ///
  /// The result is sorted in the stable layer-priority order (which means all
  /// returned spans are naturally grouped by their sub-priority).
  List<DecorationSpan> queryByLayer(int start, int end, String layerId) {
    assert(start <= end, 'start ($start) must be <= end ($end)');
    return query(start, end)
        .where((span) => span.layerId == layerId)
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Text-change offset adjustment
  // ---------------------------------------------------------------------------

  /// Adjusts all span offsets when text is *inserted* at [offset].
  ///
  /// Spans that start at or after [offset] have their positions shifted forward
  /// by [length]. Spans that contain [offset] are extended.
  void handleInsert(int offset, int length) {
    if (length <= 0) return;

    for (var i = 0; i < _spans.length; i++) {
      final span = _spans[i];
      if (span.start >= offset) {
        // Span starts at or after the insertion point — shift it.
        _spans[i] = DecorationSpan(
          layerId: span.layerId,
          start: span.start + length,
          end: span.end + length,
          priority: span.priority,
          revision: span.revision,
          payload: span.payload,
        );
      } else if (span.end > offset) {
        // Insertion falls inside an existing span — extend the end.
        _spans[i] = DecorationSpan(
          layerId: span.layerId,
          start: span.start,
          end: span.end + length,
          priority: span.priority,
          revision: span.revision,
          payload: span.payload,
        );
      }
      // else: span ends before offset — no change.
    }

    // After shifting, re-sort.  In practice, insertion preserves the relative
    // order of shifted spans among themselves, but we need a full sort to be
    // safe against edge cases.
    _sortAndDeduplicate();
  }

  /// Adjusts all span offsets when text is *deleted* at [offset].
  ///
  /// Spans that start at or after [offset] are shifted backward (clamped to
  /// zero). Spans that span across the deleted region are shrunk. Spans that
  /// fall entirely within the deleted region are removed.
  void handleDelete(int offset, int length) {
    if (length <= 0) return;

    final end = offset + length;

    _spans.removeWhere((span) {
      // Entirely inside deleted region.
      if (span.start >= offset && span.end <= end) return true;
      return false;
    });

    for (var i = 0; i < _spans.length; i++) {
      final span = _spans[i];
      if (span.start >= end) {
        // Starts after deleted region — shift back.
        _spans[i] = DecorationSpan(
          layerId: span.layerId,
          start: max(0, span.start - length),
          end: max(0, span.end - length),
          priority: span.priority,
          revision: span.revision,
          payload: span.payload,
        );
      } else if (span.end > offset) {
        // Spans across the deleted region — shrink from the end.
        final newEnd = max(offset, span.end - length);
        _spans[i] = DecorationSpan(
          layerId: span.layerId,
          start: span.start,
          end: newEnd,
          priority: span.priority,
          revision: span.revision,
          payload: span.payload,
        );
      }
      // else: ends before deleted region — no change.
    }

    _sortAndDeduplicate();
  }

  /// Handles a text replacement (delete followed by insert) at [offset].
  ///
  /// This is equivalent to calling [handleDelete] then [handleInsert], but
  /// more efficient since it avoids a redundant sort.
  void handleReplace(int offset, int deleteLength, int insertLength) {
    if (deleteLength <= 0 && insertLength <= 0) return;

    if (deleteLength > 0) {
      final deleteEnd = offset + deleteLength;
      _spans.removeWhere(
        (span) => span.start >= offset && span.end <= deleteEnd,
      );
    }

    final delta = insertLength - deleteLength;

    if (delta != 0) {
      for (var i = 0; i < _spans.length; i++) {
        final span = _spans[i];
        if (span.start >= offset) {
          _spans[i] = DecorationSpan(
            layerId: span.layerId,
            start: max(0, span.start + delta),
            end: max(0, span.end + delta),
            priority: span.priority,
            revision: span.revision,
            payload: span.payload,
          );
        } else if (span.end > offset) {
          _spans[i] = DecorationSpan(
            layerId: span.layerId,
            start: span.start,
            end: max(offset, span.end + delta),
            priority: span.priority,
            revision: span.revision,
            payload: span.payload,
          );
        }
      }
    }

    _sortAndDeduplicate();
  }

  // ---------------------------------------------------------------------------
  // Revision management
  // ---------------------------------------------------------------------------

  /// Removes all spans whose [DecorationSpan.revision] is less than
  /// [currentRevision].
  ///
  /// Call this after the document advances to a new revision so that
  /// decorations from older revisions are cleaned up in batch.
  void invalidateStale(int currentRevision) {
    _documentRevision = currentRevision;
    _spans.removeWhere((span) => span.revision < currentRevision);
  }

  // ---------------------------------------------------------------------------
  // Accessors
  // ---------------------------------------------------------------------------

  /// The current document revision tracked by this index.
  int get documentRevision => _documentRevision;

  /// Returns all spans in stable sorted order.
  List<DecorationSpan> get all => List.unmodifiable(_spans);

  /// The total number of spans stored in this index.
  int get count => _spans.length;

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Binary search: returns the index of the first span whose end > [offset].
  ///
  /// This is the first span that *could* intersect a query starting at
  /// [offset]. Returns [_spans.length] when no such span exists.
  int _firstIntersecting(int offset) {
    int lo = 0;
    int hi = _spans.length;

    while (lo < hi) {
      final mid = lo + (hi - lo) ~/ 2;
      if (_spans[mid].end > offset) {
        hi = mid;
      } else {
        lo = mid + 1;
      }
    }
    return lo;
  }

  /// Binary search: returns the index at which [span] should be inserted to
  /// maintain sorted order.
  int _lowerBound(DecorationSpan span) {
    int lo = 0;
    int hi = _spans.length;

    while (lo < hi) {
      final mid = lo + (hi - lo) ~/ 2;
      if (compareSpan(_spans[mid], span) < 0) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Sorts the span list and removes any strict duplicates.
  void _sortAndDeduplicate() {
    _spans.sort(compareSpan);
    var write = 0;
    for (var read = 1; read < _spans.length; read++) {
      if (_spans[read] != _spans[write]) {
        write++;
        if (write != read) {
          _spans[write] = _spans[read];
        }
      }
    }
    if (_spans.isNotEmpty) {
      _spans.length = write + 1;
    }
  }
}
