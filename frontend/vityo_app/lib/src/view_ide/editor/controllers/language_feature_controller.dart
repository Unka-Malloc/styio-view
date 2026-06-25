import '../../language/language_contract.dart';
import '../../language/styio_language_service.dart';
import '../document/document_state.dart';
import 'editor_owned_controller.dart';

class LanguageFeatureController extends EditorOwnedController {
  LanguageFeatureController({
    required this.languageService,
    required DocumentState initialDocument,
  }) : _analysis = languageService.analyzeDocument(initialDocument);

  final StyioLanguageService languageService;
  StyioDocumentAnalysis _analysis;

  StyioDocumentAnalysis get analysis => _analysis;

  void refresh(DocumentState document) {
    ensureNotDisposed();
    _analysis = languageService.analyzeDocument(document);
    notifyControllerListeners();
  }

  void setAnalysis(StyioDocumentAnalysis analysis) {
    ensureNotDisposed();
    _analysis = analysis;
    notifyControllerListeners();
  }
}
