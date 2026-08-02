class SelectionState {
  const SelectionState({required this.baseOffset, required this.extentOffset});

  const SelectionState.collapsed(int offset)
    : baseOffset = offset,
      extentOffset = offset;

  final int baseOffset;
  final int extentOffset;

  bool get isCollapsed => baseOffset == extentOffset;
  int get start => baseOffset < extentOffset ? baseOffset : extentOffset;
  int get end => baseOffset > extentOffset ? baseOffset : extentOffset;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is SelectionState &&
            baseOffset == other.baseOffset &&
            extentOffset == other.extentOffset;
  }

  @override
  int get hashCode => Object.hash(baseOffset, extentOffset);
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
    var clusterDirection = normalized.first.selection;
    var clusterContainsPrimary = normalized.first.isPrimary;

    for (var index = 1; index < normalized.length; index += 1) {
      final next = normalized[index];
      if (next.selection.start <= clusterEnd) {
        if (next.selection.end > clusterEnd) {
          clusterEnd = next.selection.end;
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
          direction: clusterDirection,
        ),
      );
      clusterStart = next.selection.start;
      clusterEnd = next.selection.end;
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
    required SelectionState direction,
  }) {
    return direction.baseOffset > direction.extentOffset
        ? SelectionState(baseOffset: end, extentOffset: start)
        : SelectionState(baseOffset: start, extentOffset: end);
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
