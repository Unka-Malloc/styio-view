import '../document/document_state.dart';
import '../selection/selection_state.dart';
import '../transactions/transactions.dart';
import 'editor_owned_controller.dart';

class TransactionController extends EditorOwnedController {
  TransactionController({
    EditorTransactionService service = const EditorTransactionService(),
  }) : _service = service;

  final EditorTransactionService _service;
  int _nextTransactionSequence = 0;

  EditorTransactionService get service => _service;

  WorkspaceEditValidation validateForDocument({
    required DocumentState document,
    required WorkspaceEdit edit,
  }) {
    ensureNotDisposed();
    return _service.validateForDocument(document: document, edit: edit);
  }

  EditorTransactionResult applyToDocument({
    required DocumentState document,
    required WorkspaceEdit edit,
  }) {
    ensureNotDisposed();
    final result = _service.applyToDocument(document: document, edit: edit);
    notifyControllerListeners();
    return result;
  }

  EditorCommandTransaction createCommandTransaction({
    required String commandId,
    required WorkspaceEdit edit,
    SelectionState? selectionAfter,
    String? label,
  }) {
    ensureNotDisposed();
    _nextTransactionSequence += 1;
    return EditorCommandTransaction(
      id: 'editor-command-$_nextTransactionSequence',
      commandId: commandId,
      edit: edit,
      selectionAfter: selectionAfter,
      label: label,
    );
  }

  EditorCommandTransactionResult applyCommandTransaction({
    required DocumentState document,
    required SelectionState selectionBefore,
    required EditorCommandTransaction transaction,
  }) {
    ensureNotDisposed();
    final result = _service.applyToDocument(
      document: document,
      edit: transaction.edit,
    );
    final selectionAfter = transaction.selectionAfter ?? selectionBefore;
    notifyControllerListeners();
    return EditorCommandTransactionResult(
      transaction: transaction,
      result: result,
      selectionBefore: selectionBefore,
      selectionAfter: selectionAfter,
    );
  }
}
