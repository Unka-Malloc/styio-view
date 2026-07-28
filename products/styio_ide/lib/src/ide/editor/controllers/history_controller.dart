import '../document/document_state.dart';
import '../selection/selection_state.dart';
import 'editor_owned_controller.dart';

class EditorHistorySnapshot {
  const EditorHistorySnapshot({
    required this.document,
    required this.selection,
  });

  final DocumentState document;
  final SelectionState selection;
}

class HistoryController extends EditorOwnedController {
  HistoryController({this.maxEntries = defaultMaxEntries}) {
    if (maxEntries < 1) {
      throw ArgumentError.value(maxEntries, 'maxEntries', 'must be positive');
    }
  }

  static const int defaultMaxEntries = 128;

  final int maxEntries;
  final List<EditorHistorySnapshot> _undoStack = <EditorHistorySnapshot>[];
  final List<EditorHistorySnapshot> _redoStack = <EditorHistorySnapshot>[];

  List<EditorHistorySnapshot> get undoStack =>
      List<EditorHistorySnapshot>.unmodifiable(_undoStack);
  List<EditorHistorySnapshot> get redoStack =>
      List<EditorHistorySnapshot>.unmodifiable(_redoStack);
  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;
  int get undoDepth => _undoStack.length;
  int get redoDepth => _redoStack.length;

  void clear() {
    ensureNotDisposed();
    _undoStack.clear();
    _redoStack.clear();
    notifyControllerListeners();
  }

  void clearRedo() {
    ensureNotDisposed();
    _redoStack.clear();
    notifyControllerListeners();
  }

  void pushUndo(EditorHistorySnapshot snapshot) {
    ensureNotDisposed();
    _pushBounded(_undoStack, snapshot);
    notifyControllerListeners();
  }

  void pushRedo(EditorHistorySnapshot snapshot) {
    ensureNotDisposed();
    _pushBounded(_redoStack, snapshot);
    notifyControllerListeners();
  }

  EditorHistorySnapshot? popUndo() {
    ensureNotDisposed();
    if (_undoStack.isEmpty) {
      return null;
    }
    final snapshot = _undoStack.removeLast();
    notifyControllerListeners();
    return snapshot;
  }

  EditorHistorySnapshot? popRedo() {
    ensureNotDisposed();
    if (_redoStack.isEmpty) {
      return null;
    }
    final snapshot = _redoStack.removeLast();
    notifyControllerListeners();
    return snapshot;
  }

  void _pushBounded(
    List<EditorHistorySnapshot> stack,
    EditorHistorySnapshot snapshot,
  ) {
    stack.add(snapshot);
    while (stack.length > maxEntries) {
      stack.removeAt(0);
    }
  }
}
