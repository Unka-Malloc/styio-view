import '../selection/selection_interaction.dart';
import '../selection/selection_state.dart';
import 'editor_owned_controller.dart';

class SelectionController extends EditorOwnedController {
  SelectionController(
    SelectionState initialSelection, {
    required int documentLength,
  }) : _selectionSet = EditorSelectionSet.single(
         initialSelection,
         documentLength: documentLength,
       ),
       _documentLength = documentLength;

  EditorSelectionSet _selectionSet;
  int _documentLength;
  int _commandSequence = 0;
  EditorSelectionCommandIntent? _pendingInteractionCommand;
  static const EditorSelectionInteraction _interaction =
      EditorSelectionInteraction();
  final List<SelectionState> structuredSelectionStack = <SelectionState>[];

  EditorSelectionSet get selectionSet => _selectionSet;
  SelectionState get selection => _selectionSet.primarySelection;
  EditorSelectionCommandIntent? get pendingInteractionCommand =>
      _pendingInteractionCommand;

  void select(SelectionState selection, {required int documentLength}) {
    selectSelectionSet(
      EditorSelectionSet.single(selection, documentLength: documentLength),
    );
  }

  void selectSelections(
    Iterable<SelectionState> selections, {
    required int primaryIndex,
    required int documentLength,
  }) {
    selectSelectionSet(
      EditorSelectionSet.normalized(
        selections: selections,
        primaryIndex: primaryIndex,
        documentLength: documentLength,
      ),
    );
  }

  void selectSelectionSet(EditorSelectionSet selectionSet) {
    ensureNotDisposed();
    _selectionSet = selectionSet;
    for (final selection in selectionSet.selections) {
      if (selection.end > _documentLength) {
        _documentLength = selection.end;
      }
    }
    _pendingInteractionCommand = null;
    structuredSelectionStack.clear();
    notifyControllerListeners();
  }

  void selectForStructuralNavigation(
    SelectionState selection, {
    required int documentLength,
  }) {
    ensureNotDisposed();
    _selectionSet = EditorSelectionSet.single(
      selection,
      documentLength: documentLength,
    );
    _documentLength = documentLength;
    _pendingInteractionCommand = null;
    notifyControllerListeners();
  }

  void selectCollapsed(int offset, {required int documentLength}) {
    select(SelectionState.collapsed(offset), documentLength: documentLength);
  }

  void selectRange({
    required int baseOffset,
    required int extentOffset,
    required int documentLength,
  }) {
    select(
      SelectionState(baseOffset: baseOffset, extentOffset: extentOffset),
      documentLength: documentLength,
    );
  }

  void clearStructuredSelectionStack() {
    ensureNotDisposed();
    structuredSelectionStack.clear();
  }

  void addOrToggleCursor(
    EditorCaretPosition position, {
    required int documentLength,
    bool makePrimary = true,
  }) {
    final next = _interaction.addOrToggleCursor(
      current: _selectionSet,
      position: position,
      documentLength: documentLength,
      makePrimary: makePrimary,
    );
    if (identical(next, _selectionSet)) {
      return;
    }
    selectSelectionSet(next);
    _documentLength = documentLength;
  }

  void removeSecondaryCursors({int? documentLength}) {
    final resolvedLength = documentLength ?? _documentLength;
    selectSelectionSet(
      _interaction.removeSecondaryCursors(
        current: _selectionSet,
        documentLength: resolvedLength,
      ),
    );
    _documentLength = resolvedLength;
  }

  void projectRectangle({
    required Iterable<EditorRectangularLineProjection> lines,
    required int primaryLineIndex,
    required EditorRectangleHorizontalDirection horizontalDirection,
    required int documentLength,
  }) {
    selectSelectionSet(
      _interaction.projectRectangle(
        lines: lines,
        primaryLineIndex: primaryLineIndex,
        horizontalDirection: horizontalDirection,
        documentLength: documentLength,
      ),
    );
    _documentLength = documentLength;
  }

  /// Publishes a layout-dependent command for the editor layout boundary.
  ///
  /// The renderer resolves positions and returns them through one of the
  /// `applyResolved*` methods; it never mutates selection truth itself.
  void requestInteractionCommand(EditorSelectionCommand command) {
    ensureNotDisposed();
    if (command == EditorSelectionCommand.removeSecondaryCursors) {
      removeSecondaryCursors();
      return;
    }
    _commandSequence += 1;
    _pendingInteractionCommand = EditorSelectionCommandIntent(
      sequence: _commandSequence,
      command: command,
    );
    notifyControllerListeners();
  }

  bool applyResolvedMovementCommand({
    required int sequence,
    required List<EditorCaretPosition> positions,
    required int documentLength,
  }) {
    ensureNotDisposed();
    final pending = _pendingInteractionCommand;
    if (pending == null || pending.sequence != sequence) {
      return false;
    }
    if (pending.command.extendsRectangle ||
        pending.command == EditorSelectionCommand.removeSecondaryCursors) {
      throw StateError(
        '${pending.command.name} does not accept resolved movement positions.',
      );
    }
    final next = pending.command.addsCursor
        ? _interaction.addCursors(
            current: _selectionSet,
            positions: positions,
            documentLength: documentLength,
          )
        : _interaction.moveOrExtend(
            current: _selectionSet,
            positions: positions,
            extend: pending.command.extendsSelection,
            documentLength: documentLength,
          );
    _documentLength = documentLength;
    selectSelectionSet(next);
    return true;
  }

  bool applyResolvedRectangleCommand({
    required int sequence,
    required Iterable<EditorRectangularLineProjection> lines,
    required int primaryLineIndex,
    required EditorRectangleHorizontalDirection horizontalDirection,
    required int documentLength,
  }) {
    ensureNotDisposed();
    final pending = _pendingInteractionCommand;
    if (pending == null ||
        pending.sequence != sequence ||
        !pending.command.extendsRectangle) {
      return false;
    }
    projectRectangle(
      lines: lines,
      primaryLineIndex: primaryLineIndex,
      horizontalDirection: horizontalDirection,
      documentLength: documentLength,
    );
    return true;
  }
}
