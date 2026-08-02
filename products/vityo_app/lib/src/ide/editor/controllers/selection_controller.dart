import '../selection/selection_state.dart';
import 'editor_owned_controller.dart';

class SelectionController extends EditorOwnedController {
  SelectionController(
    SelectionState initialSelection, {
    required int documentLength,
  }) : _selectionSet = EditorSelectionSet.single(
         initialSelection,
         documentLength: documentLength,
       );

  EditorSelectionSet _selectionSet;
  final List<SelectionState> structuredSelectionStack = <SelectionState>[];

  EditorSelectionSet get selectionSet => _selectionSet;
  SelectionState get selection => _selectionSet.primarySelection;

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
}
