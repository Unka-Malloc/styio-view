import '../../../view_ide/language/language_contract.dart';
import '../../../view_ide/language/styio_language_service.dart';
import '../document/document_state.dart';
import 'editor_owned_controller.dart';

class LanguageFeatureController extends EditorOwnedController {
  LanguageFeatureController({
    required this.languageService,
    required DocumentState initialDocument,
  }) : _analysis = initialDocument.lineCount >= 10000
           ? _emptyAnalysis
           : languageService.analyzeDocument(initialDocument);

  static const StyioDocumentAnalysis _emptyAnalysis = StyioDocumentAnalysis(
    tokenSpans: <TokenSpan>[],
    semanticSpans: <SemanticSpan>[],
    diagnostics: <Diagnostic>[],
    formattingEdits: <FormattingEdit>[],
    semanticBlocks: <SemanticBlockRange>[],
    inlayHints: <InlayHint>[],
    documentSymbols: <DocumentSymbol>[],
    referenceSpans: <ReferenceSpan>[],
  );

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
