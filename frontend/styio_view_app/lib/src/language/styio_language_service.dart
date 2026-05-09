import '../editor/document_state.dart';
import 'language_contract.dart';

abstract class StyioLanguageService {
  StyioDocumentAnalysis analyzeDocument(DocumentState document);

  List<FormattingEdit> formatDocument(DocumentState document);

  List<CompletionItem> completeAt(DocumentState document, int offset);

  HoverPayload? hoverAt(DocumentState document, int offset);

  DefinitionTarget? definitionAt(DocumentState document, int offset);

  List<ReferenceSpan> referencesAt(DocumentState document, int offset);

  RenamePlan? renameAt(DocumentState document, int offset, String newName);

  ParameterInfoPayload? parameterInfoAt(DocumentState document, int offset);

  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  );
}
