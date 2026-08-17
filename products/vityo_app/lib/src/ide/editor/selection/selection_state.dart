enum EditorCaretAffinity { upstream, downstream }

class SelectionState {
  const SelectionState({
    required this.baseOffset,
    required this.extentOffset,
    this.baseAffinity = EditorCaretAffinity.downstream,
    this.extentAffinity = EditorCaretAffinity.downstream,
    this.desiredVisualX,
  });

  const SelectionState.collapsed(
    int offset, {
    EditorCaretAffinity affinity = EditorCaretAffinity.downstream,
    this.desiredVisualX,
  }) : baseOffset = offset,
       extentOffset = offset,
       baseAffinity = affinity,
       extentAffinity = affinity;

  final int baseOffset;
  final int extentOffset;
  final EditorCaretAffinity baseAffinity;
  final EditorCaretAffinity extentAffinity;

  /// Layout-owned preferred visual coordinate used by vertical movement.
  ///
  /// The selection model only carries this resolved fact; it never derives it
  /// from source columns or estimated glyph widths.
  final double? desiredVisualX;

  bool get isCollapsed => baseOffset == extentOffset;
  int get start => baseOffset < extentOffset ? baseOffset : extentOffset;
  int get end => baseOffset > extentOffset ? baseOffset : extentOffset;
  EditorCaretAffinity get startAffinity =>
      baseOffset <= extentOffset ? baseAffinity : extentAffinity;
  EditorCaretAffinity get endAffinity =>
      baseOffset > extentOffset ? baseAffinity : extentAffinity;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SelectionState &&
            baseOffset == other.baseOffset &&
            extentOffset == other.extentOffset &&
            baseAffinity == other.baseAffinity &&
            extentAffinity == other.extentAffinity &&
            desiredVisualX == other.desiredVisualX;
  }

  @override
  int get hashCode => Object.hash(
    baseOffset,
    extentOffset,
    baseAffinity,
    extentAffinity,
    desiredVisualX,
  );
}

class EditorSelectionSet {
  EditorSelectionSet._({
    required List<SelectionState> selections,
    required this.primaryIndex,
  }) : selections = List<SelectionState>.unmodifiable(selections);

  factory EditorSelectionSet.normalized({
    required Iterable<SelectionState> selections,
    required int primaryIndex,
    required int documentLength,
  }) {
    if (documentLength < 0) {
      throw ArgumentError.value(
        documentLength,
        'documentLength',
        'must not be negative',
      );
    }
    if (primaryIndex < 0) {
      throw ArgumentError.value(
        primaryIndex,
        'primaryIndex',
        'must identify an input selection',
      );
    }

    final normalized = <_NormalizedSelection>[];
    var ordinal = 0;
    for (final selection in selections) {
      normalized.add(
        _NormalizedSelection(
          selection: SelectionState(
            baseOffset: selection.baseOffset.clamp(0, documentLength),
            extentOffset: selection.extentOffset.clamp(0, documentLength),
            baseAffinity: selection.baseAffinity,
            extentAffinity: selection.extentAffinity,
            desiredVisualX: selection.desiredVisualX,
          ),
          isPrimary: ordinal == primaryIndex,
        ),
      );
      ordinal += 1;
    }

    if (normalized.isEmpty) {
      throw ArgumentError.value(
        selections,
        'selections',
        'must contain at least one selection',
      );
    }
    if (primaryIndex >= normalized.length) {
      throw ArgumentError.value(
        primaryIndex,
        'primaryIndex',
        'must identify an input selection',
      );
    }

    normalized.sort(_compareNormalizedSelections);

    final output = <SelectionState>[];
    var outputPrimaryIndex = -1;
    var clusterStart = normalized.first.selection.start;
    var clusterEnd = normalized.first.selection.end;
    var clusterStartAffinity = normalized.first.selection.startAffinity;
    var clusterEndAffinity = normalized.first.selection.endAffinity;
    var clusterDirection = normalized.first.selection;
    var clusterContainsPrimary = normalized.first.isPrimary;

    for (var index = 1; index < normalized.length; index += 1) {
      final next = normalized[index];
      if (next.selection.start <= clusterEnd) {
        if (next.selection.end > clusterEnd) {
          clusterEnd = next.selection.end;
          clusterEndAffinity = next.selection.endAffinity;
        }
        if (next.isPrimary) {
          clusterContainsPrimary = true;
          clusterDirection = next.selection;
        }
        continue;
      }

      if (clusterContainsPrimary) {
        outputPrimaryIndex = output.length;
      }
      output.add(
        _selectionWithDirection(
          start: clusterStart,
          end: clusterEnd,
          startAffinity: clusterStartAffinity,
          endAffinity: clusterEndAffinity,
          direction: clusterDirection,
        ),
      );
      clusterStart = next.selection.start;
      clusterEnd = next.selection.end;
      clusterStartAffinity = next.selection.startAffinity;
      clusterEndAffinity = next.selection.endAffinity;
      clusterDirection = next.selection;
      clusterContainsPrimary = next.isPrimary;
    }

    if (clusterContainsPrimary) {
      outputPrimaryIndex = output.length;
    }
    output.add(
      _selectionWithDirection(
        start: clusterStart,
        end: clusterEnd,
        startAffinity: clusterStartAffinity,
        endAffinity: clusterEndAffinity,
        direction: clusterDirection,
      ),
    );

    return EditorSelectionSet._(
      selections: output,
      primaryIndex: outputPrimaryIndex,
    );
  }

  factory EditorSelectionSet.single(
    SelectionState selection, {
    required int documentLength,
  }) {
    return EditorSelectionSet.normalized(
      selections: <SelectionState>[selection],
      primaryIndex: 0,
      documentLength: documentLength,
    );
  }

  final List<SelectionState> selections;
  final int primaryIndex;

  SelectionState get primarySelection => selections[primaryIndex];

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! EditorSelectionSet ||
        primaryIndex != other.primaryIndex ||
        selections.length != other.selections.length) {
      return false;
    }
    for (var index = 0; index < selections.length; index += 1) {
      if (selections[index] != other.selections[index]) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(primaryIndex, Object.hashAll(selections));

  static int _compareNormalizedSelections(
    _NormalizedSelection left,
    _NormalizedSelection right,
  ) {
    var comparison = left.selection.start.compareTo(right.selection.start);
    if (comparison != 0) {
      return comparison;
    }
    comparison = left.selection.end.compareTo(right.selection.end);
    if (comparison != 0) {
      return comparison;
    }
    comparison = left.selection.baseOffset.compareTo(
      right.selection.baseOffset,
    );
    if (comparison != 0) {
      return comparison;
    }
    return left.selection.extentOffset.compareTo(right.selection.extentOffset);
  }

  static SelectionState _selectionWithDirection({
    required int start,
    required int end,
    required EditorCaretAffinity startAffinity,
    required EditorCaretAffinity endAffinity,
    required SelectionState direction,
  }) {
    return direction.baseOffset > direction.extentOffset
        ? SelectionState(
            baseOffset: end,
            extentOffset: start,
            baseAffinity: endAffinity,
            extentAffinity: startAffinity,
            desiredVisualX: direction.desiredVisualX,
          )
        : SelectionState(
            baseOffset: start,
            extentOffset: end,
            baseAffinity: startAffinity,
            extentAffinity: endAffinity,
            desiredVisualX: direction.desiredVisualX,
          );
  }
}

class _NormalizedSelection {
  const _NormalizedSelection({
    required this.selection,
    required this.isPrimary,
  });

  final SelectionState selection;
  final bool isPrimary;
}
