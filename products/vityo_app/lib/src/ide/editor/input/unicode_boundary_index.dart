import 'dart:collection';

// Flutter's SDK dependency supplies the canonical Dart Unicode primitive.
// ignore: depend_on_referenced_packages
import 'package:characters/characters.dart';

import 'editor_composition.dart' show EditorInputRange;

enum UnicodeBoundaryBias { backward, forward }

/// A revision-bound grapheme index over a small UTF-16 source window.
///
/// The index never retains the complete document. Construction uses the
/// Unicode implementation from `package:characters`, while all subsequent
/// navigation is a binary search over immutable, sorted offsets.
final class UnicodeBoundaryIndex {
  UnicodeBoundaryIndex._({
    required this.documentId,
    required this.revision,
    required this.windowStart,
    required String windowText,
    required List<int> boundaries,
  }) : windowText = windowText,
       windowEnd = windowStart + windowText.length,
       _boundaries = List<int>.unmodifiable(boundaries);

  static const int maximumEntryCount = 128;
  static const int maximumCachedCodeUnits = 65536;

  static final LinkedHashMap<_BoundaryCacheKey, UnicodeBoundaryIndex> _cache =
      LinkedHashMap<_BoundaryCacheKey, UnicodeBoundaryIndex>();
  static int _cachedCodeUnits = 0;

  /// Builds an index centered as closely as possible on [anchorOffset].
  factory UnicodeBoundaryIndex.forTextWindow({
    required String documentId,
    required int revision,
    required String text,
    required int anchorOffset,
    int maxCodeUnits = 8192,
  }) {
    final anchor = _validateConstruction(
      documentId: documentId,
      revision: revision,
      text: text,
      offset: anchorOffset,
      maxCodeUnits: maxCodeUnits,
    );
    final before = maxCodeUnits ~/ 2;
    var desiredStart = anchor - before;
    if (desiredStart < 0) desiredStart = 0;
    var desiredEnd = desiredStart + maxCodeUnits;
    if (desiredEnd > text.length) {
      desiredEnd = text.length;
      desiredStart = (desiredEnd - maxCodeUnits).clamp(0, text.length);
    }
    return _build(
      documentId: documentId,
      revision: revision,
      text: text,
      desiredStart: desiredStart,
      desiredEnd: desiredEnd,
      requiredStart: anchor,
      requiredEnd: anchor,
      maxCodeUnits: maxCodeUnits,
    );
  }

  /// Builds a bounded index which preferentially contains [rangeStart] to
  /// [rangeEnd], then balances any remaining capacity around that range.
  factory UnicodeBoundaryIndex.forTextRange({
    required String documentId,
    required int revision,
    required String text,
    required int rangeStart,
    required int rangeEnd,
    int maxCodeUnits = 8192,
  }) {
    _validateConstruction(
      documentId: documentId,
      revision: revision,
      text: text,
      offset: rangeStart,
      maxCodeUnits: maxCodeUnits,
    );
    RangeError.checkValidRange(rangeStart, rangeEnd, text.length);
    final rangeLength = rangeEnd - rangeStart;
    if (rangeLength > maxCodeUnits) {
      return _build(
        documentId: documentId,
        revision: revision,
        text: text,
        desiredStart: rangeStart,
        desiredEnd: rangeStart,
        requiredStart: rangeStart,
        requiredEnd: rangeStart,
        maxCodeUnits: maxCodeUnits,
      );
    }
    final spare = maxCodeUnits - rangeLength;
    var desiredStart = rangeStart - spare ~/ 2;
    var desiredEnd = rangeEnd + (spare - spare ~/ 2);
    if (desiredStart < 0) {
      desiredEnd = (desiredEnd - desiredStart).clamp(0, text.length);
      desiredStart = 0;
    }
    if (desiredEnd > text.length) {
      desiredStart = (desiredStart - (desiredEnd - text.length)).clamp(
        0,
        text.length,
      );
      desiredEnd = text.length;
    }
    return _build(
      documentId: documentId,
      revision: revision,
      text: text,
      desiredStart: desiredStart,
      desiredEnd: desiredEnd,
      requiredStart: rangeStart,
      requiredEnd: rangeEnd,
      maxCodeUnits: maxCodeUnits,
    );
  }

  final String documentId;
  final int revision;
  final int windowStart;
  final int windowEnd;
  final String windowText;
  final List<int> _boundaries;

  int get indexedCodeUnitCount => windowEnd - windowStart;
  int get boundaryCount => _boundaries.length;
  List<int> get boundaries => _boundaries;

  static int get cachedEntryCount => _cache.length;
  static int get cachedCodeUnitCount => _cachedCodeUnits;

  static void clearCache() {
    _cache.clear();
    _cachedCodeUnits = 0;
  }

  bool isBoundary(int offset, {required int documentRevision}) {
    _validateQuery(offset, documentRevision);
    return _binarySearch(offset) >= 0;
  }

  int previousBoundary(int offset, {required int documentRevision}) {
    _validateQuery(offset, documentRevision);
    final insertion = _lowerBound(offset);
    if (insertion == 0) return windowStart;
    return _boundaries[insertion - 1];
  }

  int nextBoundary(int offset, {required int documentRevision}) {
    _validateQuery(offset, documentRevision);
    final insertion = _upperBound(offset);
    if (insertion == _boundaries.length) return windowEnd;
    return _boundaries[insertion];
  }

  int clampBoundary(
    int offset, {
    required UnicodeBoundaryBias bias,
    required int documentRevision,
  }) {
    _validateQuery(offset, documentRevision);
    final found = _binarySearch(offset);
    if (found >= 0) return offset;
    final insertion = _lowerBound(offset);
    return bias == UnicodeBoundaryBias.backward
        ? _boundaries[insertion - 1]
        : _boundaries[insertion];
  }

  EditorInputRange deletionRange(
    int offset, {
    required bool forward,
    required int documentRevision,
  }) {
    _validateQuery(offset, documentRevision);
    final start = clampBoundary(
      offset,
      bias: UnicodeBoundaryBias.backward,
      documentRevision: documentRevision,
    );
    final end = clampBoundary(
      offset,
      bias: UnicodeBoundaryBias.forward,
      documentRevision: documentRevision,
    );
    if (start != end) return EditorInputRange(start: start, end: end);
    return forward
        ? EditorInputRange(
            start: start,
            end: nextBoundary(start, documentRevision: documentRevision),
          )
        : EditorInputRange(
            start: previousBoundary(end, documentRevision: documentRevision),
            end: end,
          );
  }

  void _validateQuery(int offset, int documentRevision) {
    if (documentRevision != revision) {
      throw StateError(
        'Unicode boundary index revision $revision cannot answer revision '
        '$documentRevision.',
      );
    }
    RangeError.checkValueInInterval(offset, windowStart, windowEnd, 'offset');
  }

  int _binarySearch(int value) {
    final candidate = _lowerBound(value);
    return candidate < _boundaries.length && _boundaries[candidate] == value
        ? candidate
        : -1;
  }

  int _lowerBound(int value) {
    var low = 0;
    var high = _boundaries.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_boundaries[middle] < value) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  int _upperBound(int value) {
    var low = 0;
    var high = _boundaries.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (_boundaries[middle] <= value) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return low;
  }

  static int _validateConstruction({
    required String documentId,
    required int revision,
    required String text,
    required int offset,
    required int maxCodeUnits,
  }) {
    if (documentId.isEmpty) {
      throw ArgumentError.value(documentId, 'documentId', 'must not be empty');
    }
    if (revision < 0) {
      throw ArgumentError.value(revision, 'revision', 'must not be negative');
    }
    if (maxCodeUnits <= 0 || maxCodeUnits > maximumCachedCodeUnits) {
      throw RangeError.range(
        maxCodeUnits,
        1,
        maximumCachedCodeUnits,
        'maxCodeUnits',
      );
    }
    return RangeError.checkValueInInterval(offset, 0, text.length, 'offset');
  }

  static UnicodeBoundaryIndex _build({
    required String documentId,
    required int revision,
    required String text,
    required int desiredStart,
    required int desiredEnd,
    required int requiredStart,
    required int requiredEnd,
    required int maxCodeUnits,
  }) {
    _invalidateOtherRevisions(documentId, revision);

    final expanded = CharacterRange.at(text, desiredStart, desiredEnd);
    final expandedStart = expanded.stringBeforeLength;
    final expandedText = expanded.current;
    final candidateBoundaries = <int>[expandedStart];
    var cursor = expandedStart;
    for (final character in expandedText.characters) {
      cursor += character.length;
      candidateBoundaries.add(cursor);
    }

    var selectedStart = _greatestAtMost(candidateBoundaries, desiredStart);
    var selectedEnd = _greatestAtMost(
      candidateBoundaries,
      selectedStart + maxCodeUnits,
    );
    if (selectedStart > requiredStart || selectedEnd < requiredEnd) {
      selectedStart = _greatestAtMost(candidateBoundaries, requiredStart);
      selectedEnd = _greatestAtMost(
        candidateBoundaries,
        selectedStart + maxCodeUnits,
      );
      if (selectedEnd < requiredEnd) {
        // A single extended cluster can legally be larger than the cap. Keep
        // a zero-width safe boundary instead of retaining or splitting it.
        selectedEnd = selectedStart;
      }
    }

    final selectedText = text.substring(selectedStart, selectedEnd);
    final key = _BoundaryCacheKey(
      documentId: documentId,
      revision: revision,
      windowStart: selectedStart,
      windowText: selectedText,
    );
    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }

    final boundaries = <int>[selectedStart];
    cursor = selectedStart;
    for (final character in selectedText.characters) {
      cursor += character.length;
      boundaries.add(cursor);
    }
    final result = UnicodeBoundaryIndex._(
      documentId: documentId,
      revision: revision,
      windowStart: selectedStart,
      windowText: selectedText,
      boundaries: boundaries,
    );
    _cache[key] = result;
    _cachedCodeUnits += result.indexedCodeUnitCount;
    _evictToBounds();
    return result;
  }

  static int _greatestAtMost(List<int> values, int target) {
    var low = 0;
    var high = values.length;
    while (low < high) {
      final middle = low + ((high - low) >> 1);
      if (values[middle] <= target) {
        low = middle + 1;
      } else {
        high = middle;
      }
    }
    return values[(low - 1).clamp(0, values.length - 1)];
  }

  static void _invalidateOtherRevisions(String documentId, int revision) {
    final stale = _cache.keys
        .where(
          (key) => key.documentId == documentId && key.revision != revision,
        )
        .toList(growable: false);
    for (final key in stale) {
      final removed = _cache.remove(key)!;
      _cachedCodeUnits -= removed.indexedCodeUnitCount;
    }
  }

  static void _evictToBounds() {
    while (_cache.length > maximumEntryCount ||
        _cachedCodeUnits > maximumCachedCodeUnits) {
      final oldestKey = _cache.keys.first;
      final removed = _cache.remove(oldestKey)!;
      _cachedCodeUnits -= removed.indexedCodeUnitCount;
    }
  }
}

final class _BoundaryCacheKey {
  const _BoundaryCacheKey({
    required this.documentId,
    required this.revision,
    required this.windowStart,
    required this.windowText,
  });

  final String documentId;
  final int revision;
  final int windowStart;
  final String windowText;

  @override
  bool operator ==(Object other) =>
      other is _BoundaryCacheKey &&
      documentId == other.documentId &&
      revision == other.revision &&
      windowStart == other.windowStart &&
      windowText == other.windowText;

  @override
  int get hashCode =>
      Object.hash(documentId, revision, windowStart, windowText);
}
