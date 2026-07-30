import '../document/document_state.dart';
import '../transactions/transactions.dart';
import 'editor_session_facade.dart';
import 'history_controller.dart';

/// Deprecated compatibility wrapper for the pre-split editor session API.
///
/// New code should depend on [EditorSessionFacade] or the narrower controllers
/// exported from `editor/controllers`.
class EditorSessionController extends EditorSessionFacade {
  EditorSessionController({
    required super.initialDocument,
    required super.languageService,
    super.initialSelection,
    super.renderPlan,
    super.transactionService = const EditorTransactionService(),
    super.historyLimit = HistoryController.defaultMaxEntries,
  });

  static DocumentState seedDocumentForPath(String path) {
    return EditorSessionFacade.seedDocumentForPath(path);
  }
}
