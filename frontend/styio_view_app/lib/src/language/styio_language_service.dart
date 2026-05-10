import '../editor/document_state.dart';
import 'language_contract.dart';

abstract class StyioLanguageService {
  StyioDocumentAnalysis analyzeDocument(DocumentState document);

  List<FormattingEdit> formatDocument(DocumentState document);

  List<CompletionItem> completeAt(DocumentState document, int offset);

  List<SurroundTemplate> surroundTemplatesAt(
    DocumentState document,
    SourceRange range,
  );

  HoverPayload? hoverAt(DocumentState document, int offset);

  DefinitionTarget? definitionAt(DocumentState document, int offset);

  List<ReferenceSpan> referencesAt(DocumentState document, int offset);

  RenamePlan? renameAt(DocumentState document, int offset, String newName);

  SafeDeletePlan? safeDeleteAt(DocumentState document, int offset);

  InlineVariablePlan? inlineVariableAt(DocumentState document, int offset);

  IntroduceVariablePlan? introduceVariable(
    DocumentState document,
    SourceRange range,
    String name,
  );

  ExtractFunctionPlan? extractFunction(
    DocumentState document,
    SourceRange range,
    String name,
  );

  ParameterInfoPayload? parameterInfoAt(DocumentState document, int offset);

  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  );
}
