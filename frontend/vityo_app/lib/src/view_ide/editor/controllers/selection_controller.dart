import '../selection/selection_state.dart';
import 'editor_owned_controller.dart';

class SelectionController extends EditorOwnedController {
  SelectionController(
    SelectionState initialSelection, {
    required int documentLength,
  }) : _selection = _clampSelection(initialSelection, documentLength);

  SelectionState _selection;
  final List<SelectionState> structuredSelectionStack = <SelectionState>[];

  SelectionState get selection => _selection;

  void select(SelectionState selection, {required int documentLength}) {
    ensureNotDisposed();
    _selection = _clampSelection(selection, documentLength);
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

  static SelectionState _clampSelection(
    SelectionState selection,
    int documentLength,
  ) {
    return SelectionState(
      baseOffset: selection.baseOffset.clamp(0, documentLength),
      extentOffset: selection.extentOffset.clamp(0, documentLength),
    );
  }
}
