import '../../editor/document_state.dart';
import '../contract/language_contract.dart';

abstract class ProjectDocumentRuleProvider {
  StyioDocumentAnalysis analysisFactsFor(DocumentState document);

  List<Diagnostic> diagnosticsFor(DocumentState document) {
    return analysisFactsFor(document).diagnostics;
  }

  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  );
}
