typedef RangeIndexOffsetOf<T> = int Function(T value);

class RangeIndexEntry<T> {
  const RangeIndexEntry({
    required this.start,
    required this.end,
    required this.value,
    this.revision = 0,
    this.priority = 0,
    this.layer = '',
    this.ordinal = 0,
  });

  final int start;
  final int end;
  final T value;
  final int revision;
  final int priority;
  final String layer;
  final int ordinal;

  bool get isCollapsed => start == end;

  bool containsOffset(int offset) {
    if (isCollapsed) {
      return offset == start;
    }
    return offset >= start && offset < end;
  }

  bool overlaps(int queryStart, int queryEnd) {
    if (queryStart == queryEnd) {
      return containsOffset(queryStart);
    }
    if (isCollapsed) {
      return start >= queryStart && start < queryEnd;
    }
    return start < queryEnd && queryStart < end;
  }
}

class RangeIndex<T> {
  RangeIndex._({required _RangeIndexNode<T>? root, required this.revision})
    : _root = root;

  factory RangeIndex.empty({int revision = 0}) {
    return RangeIndex<T>._(root: null, revision: revision);
  }

  factory RangeIndex.fromEntries(
    Iterable<RangeIndexEntry<T>> entries, {
    int revision = 0,
  }) {
    final normalized =
        entries
            .where((entry) => entry.start >= 0 && entry.end >= entry.start)
            .toList(growable: false)
          ..sort(_compareEntries);
    return RangeIndex<T>._(
      root: _RangeIndexNode.build(normalized),
      revision: revision,
    );
  }

  factory RangeIndex.fromValues(
    Iterable<T> values, {
    required RangeIndexOffsetOf<T> startOf,
    required RangeIndexOffsetOf<T> endOf,
    int revision = 0,
    int Function(T value)? priorityOf,
    String Function(T value)? layerOf,
  }) {
    var ordinal = 0;
    final entries = <RangeIndexEntry<T>>[];
    for (final value in values) {
      entries.add(
        RangeIndexEntry<T>(
          start: startOf(value),
          end: endOf(value),
          value: value,
          revision: revision,
          priority: priorityOf?.call(value) ?? 0,
          layer: layerOf?.call(value) ?? '',
          ordinal: ordinal,
        ),
      );
      ordinal += 1;
    }
    return RangeIndex<T>.fromEntries(entries, revision: revision);
  }

  final _RangeIndexNode<T>? _root;
  final int revision;

  bool get isEmpty => _root == null;
  bool get isNotEmpty => _root != null;

  List<RangeIndexEntry<T>> get entries {
    final result = <RangeIndexEntry<T>>[];
    _root?.collect(result);
    result.sort(_compareEntries);
    return List<RangeIndexEntry<T>>.unmodifiable(result);
  }

  List<T> pointQuery(int offset, {String? layer}) {
    return _entriesToValues(pointEntries(offset, layer: layer));
  }

  List<RangeIndexEntry<T>> pointEntries(int offset, {String? layer}) {
    final result = <RangeIndexEntry<T>>[];
    _root?.queryPoint(offset, result, layer);
    result.sort(_compareEntries);
    return List<RangeIndexEntry<T>>.unmodifiable(result);
  }

  List<T> overlapQuery({required int start, required int end, String? layer}) {
    return _entriesToValues(
      overlapEntries(start: start, end: end, layer: layer),
    );
  }

  List<RangeIndexEntry<T>> overlapEntries({
    required int start,
    required int end,
    String? layer,
  }) {
    final safeStart = start <= end ? start : end;
    final safeEnd = end >= start ? end : start;
    final result = <RangeIndexEntry<T>>[];
    if (safeStart == safeEnd) {
      _root?.queryPoint(safeStart, result, layer);
    } else {
      _root?.queryOverlap(safeStart, safeEnd, result, layer);
    }
    result.sort(_compareEntries);
    return List<RangeIndexEntry<T>>.unmodifiable(result);
  }

  bool overlapsPoint(int offset, {String? layer}) {
    return _root?.hasPoint(offset, layer) ?? false;
  }

  bool overlapsRange({required int start, required int end, String? layer}) {
    final safeStart = start <= end ? start : end;
    final safeEnd = end >= start ? end : start;
    if (safeStart == safeEnd) {
      return overlapsPoint(safeStart, layer: layer);
    }
    return _root?.hasOverlap(safeStart, safeEnd, layer) ?? false;
  }

  RangeIndex<T> invalidateStale(int currentRevision) {
    return RangeIndex<T>.fromEntries(
      entries.where((entry) => entry.revision >= currentRevision),
      revision: currentRevision,
    );
  }

  RangeIndex<T> replaceRevision(
    int nextRevision,
    Iterable<RangeIndexEntry<T>> entries,
  ) {
    return RangeIndex<T>.fromEntries(entries, revision: nextRevision);
  }

  static List<T> _entriesToValues<T>(List<RangeIndexEntry<T>> entries) {
    return List<T>.unmodifiable(entries.map((entry) => entry.value));
  }

  static int _compareEntries<T>(
    RangeIndexEntry<T> left,
    RangeIndexEntry<T> right,
  ) {
    final startCompare = left.start.compareTo(right.start);
    if (startCompare != 0) {
      return startCompare;
    }
    final endCompare = left.end.compareTo(right.end);
    if (endCompare != 0) {
      return endCompare;
    }
    final layerCompare = left.layer.compareTo(right.layer);
    if (layerCompare != 0) {
      return layerCompare;
    }
    final priorityCompare = right.priority.compareTo(left.priority);
    if (priorityCompare != 0) {
      return priorityCompare;
    }
    return left.ordinal.compareTo(right.ordinal);
  }
}

class _RangeIndexNode<T> {
  _RangeIndexNode({
    required this.center,
    required this.entries,
    required this.left,
    required this.right,
  });

  final int center;
  final List<RangeIndexEntry<T>> entries;
  final _RangeIndexNode<T>? left;
  final _RangeIndexNode<T>? right;

  static _RangeIndexNode<T>? build<T>(List<RangeIndexEntry<T>> entries) {
    if (entries.isEmpty) {
      return null;
    }
    final centers = <int>[
      for (final entry in entries) entry.start,
      for (final entry in entries) entry.end,
    ]..sort();
    final center = centers[centers.length >> 1];
    final left = <RangeIndexEntry<T>>[];
    final right = <RangeIndexEntry<T>>[];
    final crossing = <RangeIndexEntry<T>>[];

    for (final entry in entries) {
      if (entry.isCollapsed && entry.start < center) {
        left.add(entry);
      } else if (entry.isCollapsed && entry.start > center) {
        right.add(entry);
      } else if (!entry.isCollapsed && entry.end < center) {
        left.add(entry);
      } else if (entry.start > center) {
        right.add(entry);
      } else {
        crossing.add(entry);
      }
    }

    return _RangeIndexNode<T>(
      center: center,
      entries: crossing,
      left: build(left),
      right: build(right),
    );
  }

  void queryPoint(int offset, List<RangeIndexEntry<T>> result, String? layer) {
    for (final entry in entries) {
      if (_layerMatches(entry, layer) && entry.containsOffset(offset)) {
        result.add(entry);
      }
    }
    if (offset < center) {
      left?.queryPoint(offset, result, layer);
    } else if (offset > center) {
      right?.queryPoint(offset, result, layer);
    } else {
      left?.queryPoint(offset, result, layer);
      right?.queryPoint(offset, result, layer);
    }
  }

  void queryOverlap(
    int start,
    int end,
    List<RangeIndexEntry<T>> result,
    String? layer,
  ) {
    for (final entry in entries) {
      if (_layerMatches(entry, layer) && entry.overlaps(start, end)) {
        result.add(entry);
      }
    }
    if (start <= center) {
      left?.queryOverlap(start, end, result, layer);
    }
    if (end > center) {
      right?.queryOverlap(start, end, result, layer);
    }
  }

  bool hasPoint(int offset, String? layer) {
    for (final entry in entries) {
      if (_layerMatches(entry, layer) && entry.containsOffset(offset)) {
        return true;
      }
    }
    if (offset < center) {
      return left?.hasPoint(offset, layer) ?? false;
    }
    if (offset > center) {
      return right?.hasPoint(offset, layer) ?? false;
    }
    return (left?.hasPoint(offset, layer) ?? false) ||
        (right?.hasPoint(offset, layer) ?? false);
  }

  bool hasOverlap(int start, int end, String? layer) {
    for (final entry in entries) {
      if (_layerMatches(entry, layer) && entry.overlaps(start, end)) {
        return true;
      }
    }
    if (start <= center && (left?.hasOverlap(start, end, layer) ?? false)) {
      return true;
    }
    return end > center && (right?.hasOverlap(start, end, layer) ?? false);
  }

  void collect(List<RangeIndexEntry<T>> result) {
    left?.collect(result);
    result.addAll(entries);
    right?.collect(result);
  }

  bool _layerMatches(RangeIndexEntry<T> entry, String? layer) {
    return layer == null || entry.layer == layer;
  }
}
