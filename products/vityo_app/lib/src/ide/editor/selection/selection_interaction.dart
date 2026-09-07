import 'selection_state.dart';

enum EditorRectangleHorizontalDirection { leftToRight, rightToLeft }

/// Stable domain command understood by [SelectionController]'s layout handoff.
enum EditorSelectionCommand {
  addCursorAbove,
  addCursorBelow,
  removeSecondaryCursors,
  moveCursorsLeft,
  moveCursorsRight,
  moveCursorsUp,
  moveCursorsDown,
  extendSelectionsLeft,
  extendSelectionsRight,
  extendSelectionsUp,
  extendSelectionsDown,
  extendColumnSelectionLeft,
  extendColumnSelectionRight,
  extendColumnSelectionUp,
  extendColumnSelectionDown,
}

extension EditorSelectionCommandX on EditorSelectionCommand {
  bool get addsCursor => switch (this) {
    EditorSelectionCommand.addCursorAbove ||
    EditorSelectionCommand.addCursorBelow => true,
    _ => false,
  };

  bool get extendsSelection => switch (this) {
    EditorSelectionCommand.extendSelectionsLeft ||
    EditorSelectionCommand.extendSelectionsRight ||
    EditorSelectionCommand.extendSelectionsUp ||
    EditorSelectionCommand.extendSelectionsDown => true,
    _ => false,
  };

  bool get extendsRectangle => switch (this) {
    EditorSelectionCommand.extendColumnSelectionLeft ||
    EditorSelectionCommand.extendColumnSelectionRight ||
    EditorSelectionCommand.extendColumnSelectionUp ||
    EditorSelectionCommand.extendColumnSelectionDown => true,
    _ => false,
  };
}

final class EditorSelectionCommandIntent {
  const EditorSelectionCommandIntent({
    required this.sequence,
    required this.command,
  });

  final int sequence;
  final EditorSelectionCommand command;
}

final class EditorCaretPosition {
  const EditorCaretPosition({
    required this.offset,
    this.affinity = EditorCaretAffinity.downstream,
    this.desiredVisualX,
  });

  final int offset;
  final EditorCaretAffinity affinity;
  final double? desiredVisualX;
}

/// One line's layout-resolved visual rectangle edges.
///
/// Tabs, short lines, empty lines, and bidi runs have already been resolved by
/// the layout owner. This value deliberately contains no source text or column
/// arithmetic for the interaction layer to reinterpret.
final class EditorRectangularLineProjection {
  const EditorRectangularLineProjection({
    required this.lineIndex,
    required this.left,
    required this.right,
  });

  final int lineIndex;
  final EditorCaretPosition left;
  final EditorCaretPosition right;
}

/// Pure, immutable transforms over [EditorSelectionSet].
final class EditorSelectionInteraction {
  const EditorSelectionInteraction();

  EditorSelectionSet addOrToggleCursor({
    required EditorSelectionSet current,
    required EditorCaretPosition position,
    required int documentLength,
    bool makePrimary = true,
  }) {
    final offset = position.offset.clamp(0, documentLength);
    final matchingIndex = current.selections.indexWhere(
      (selection) => selection.isCollapsed && selection.extentOffset == offset,
    );
    if (matchingIndex == current.primaryIndex) {
      return current;
    }

    if (matchingIndex >= 0) {
      final selections = current.selections.toList(growable: true)
        ..removeAt(matchingIndex);
      final primaryIndex = matchingIndex < current.primaryIndex
          ? current.primaryIndex - 1
          : current.primaryIndex;
      return EditorSelectionSet.normalized(
        selections: selections,
        primaryIndex: primaryIndex,
        documentLength: documentLength,
      );
    }

    final selections = <SelectionState>[
      ...current.selections,
      SelectionState.collapsed(
        offset,
        affinity: position.affinity,
        desiredVisualX: position.desiredVisualX,
      ),
    ];
    return EditorSelectionSet.normalized(
      selections: selections,
      primaryIndex: makePrimary ? selections.length - 1 : current.primaryIndex,
      documentLength: documentLength,
    );
  }

  EditorSelectionSet addCursors({
    required EditorSelectionSet current,
    required Iterable<EditorCaretPosition> positions,
    required int documentLength,
  }) {
    final additions = positions
        .map(
          (position) => SelectionState.collapsed(
            position.offset,
            affinity: position.affinity,
            desiredVisualX: position.desiredVisualX,
          ),
        )
        .toList(growable: false);
    if (additions.isEmpty) {
      return current;
    }
    return EditorSelectionSet.normalized(
      selections: <SelectionState>[...current.selections, ...additions],
      primaryIndex: current.primaryIndex,
      documentLength: documentLength,
    );
  }

  EditorSelectionSet removeSecondaryCursors({
    required EditorSelectionSet current,
    required int documentLength,
  }) {
    if (current.selections.length == 1) {
      return current;
    }
    return EditorSelectionSet.single(
      current.primarySelection,
      documentLength: documentLength,
    );
  }

  /// Applies one layout-resolved target per current selection.
  EditorSelectionSet moveOrExtend({
    required EditorSelectionSet current,
    required List<EditorCaretPosition> positions,
    required bool extend,
    required int documentLength,
  }) {
    if (positions.length != current.selections.length) {
      throw ArgumentError.value(
        positions.length,
        'positions',
        'must contain one resolved target per selection',
      );
    }
    final selections = <SelectionState>[];
    for (var index = 0; index < positions.length; index += 1) {
      final currentSelection = current.selections[index];
      final position = positions[index];
      selections.add(
        extend
            ? SelectionState(
                baseOffset: currentSelection.baseOffset,
                extentOffset: position.offset,
                baseAffinity: currentSelection.baseAffinity,
                extentAffinity: position.affinity,
                desiredVisualX: position.desiredVisualX,
              )
            : SelectionState.collapsed(
                position.offset,
                affinity: position.affinity,
                desiredVisualX: position.desiredVisualX,
              ),
      );
    }
    return EditorSelectionSet.normalized(
      selections: selections,
      primaryIndex: current.primaryIndex,
      documentLength: documentLength,
    );
  }

  EditorSelectionSet projectRectangle({
    required Iterable<EditorRectangularLineProjection> lines,
    required int primaryLineIndex,
    required EditorRectangleHorizontalDirection horizontalDirection,
    required int documentLength,
  }) {
    final ordered = lines.toList(growable: false);
    if (ordered.isEmpty) {
      throw ArgumentError.value(lines, 'lines', 'must not be empty');
    }
    for (var index = 1; index < ordered.length; index += 1) {
      if (ordered[index - 1].lineIndex >= ordered[index].lineIndex) {
        throw ArgumentError.value(
          ordered[index].lineIndex,
          'lines',
          'must be strictly ordered by line index',
        );
      }
    }
    final primaryIndex = ordered.indexWhere(
      (line) => line.lineIndex == primaryLineIndex,
    );
    if (primaryIndex < 0) {
      throw ArgumentError.value(
        primaryLineIndex,
        'primaryLineIndex',
        'must identify an included projected line',
      );
    }

    final selections = ordered.map((line) {
      final base =
          horizontalDirection == EditorRectangleHorizontalDirection.leftToRight
          ? line.left
          : line.right;
      final extent =
          horizontalDirection == EditorRectangleHorizontalDirection.leftToRight
          ? line.right
          : line.left;
      return SelectionState(
        baseOffset: base.offset,
        extentOffset: extent.offset,
        baseAffinity: base.affinity,
        extentAffinity: extent.affinity,
        desiredVisualX: extent.desiredVisualX,
      );
    });
    return EditorSelectionSet.normalized(
      selections: selections,
      primaryIndex: primaryIndex,
      documentLength: documentLength,
    );
  }
}
