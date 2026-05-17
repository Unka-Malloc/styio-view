import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import 'language_service_foundation.dart';

abstract class StyioLanguageService {
  StyioDocumentAnalysis analyzeDocument(DocumentState document);

  List<FormattingEdit> formatDocument(DocumentState document);

  List<InlayHint> inlayHints(DocumentState document);

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

  ChangeSignaturePlan? changeSignatureAt(
    DocumentState document,
    int offset, {
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  });

  ParameterInfoPayload? parameterInfoAt(DocumentState document, int offset);

  List<DiagnosticQuickFix> intentionsAt(DocumentState document, int offset);

  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  );
}

extension StyioLanguageServiceResolution on StyioLanguageService {
  SemanticSnapshot semanticSnapshot(DocumentState document) {
    return SemanticSnapshot.fromAnalysis(
      document: document,
      analysis: analyzeDocument(document),
    );
  }

  ResolvedElement? resolvedElementAt(DocumentState document, int offset) {
    return semanticSnapshot(document).elementAt(offset);
  }

  ResolvedReference? resolvedReferenceAt(DocumentState document, int offset) {
    return semanticSnapshot(document).referenceAt(offset);
  }
}
