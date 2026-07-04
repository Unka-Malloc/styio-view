import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import 'language_service_foundation.dart';
import 'styio_service_capability_detector.dart';
import 'styio_language_service.dart';

class CapabilityRoutedStyioLanguageService implements StyioLanguageService {
  const CapabilityRoutedStyioLanguageService({
    required LanguageProviderRegistry<StyioLanguageService> registry,
    required StyioLanguageService fallback,
    this.languageId = 'styio',
  }) : _registry = registry,
       _fallback = fallback;

  final LanguageProviderRegistry<StyioLanguageService> _registry;
  final StyioLanguageService _fallback;
  final String languageId;

  StyioLanguageService _provider(String capability) {
    return _providerOrNull(capability) ?? _fallback;
  }

  StyioLanguageService? _providerOrNull(String capability) {
    return _registry.resolve(languageId, capability: capability);
  }

  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    final analyses =
        Map<StyioLanguageService, StyioDocumentAnalysis>.identity();
    StyioDocumentAnalysis analysisFor(StyioLanguageService provider) {
      return analyses.putIfAbsent(
        provider,
        () => provider.analyzeDocument(document),
      );
    }

    StyioDocumentAnalysis? optionalAnalysis(String capability) {
      final provider = _providerOrNull(capability);
      return provider == null ? null : analysisFor(provider);
    }

    final base = analysisFor(
      _provider(StyioServiceCapability.analysis.wireValue),
    );
    final syntax = optionalAnalysis(StyioServiceCapability.syntax.wireValue);
    final semantic = optionalAnalysis(
      StyioServiceCapability.semanticTokens.wireValue,
    );
    final diagnostics = optionalAnalysis(
      StyioServiceCapability.diagnostics.wireValue,
    );
    final formatting = optionalAnalysis(
      StyioServiceCapability.formatting.wireValue,
    );
    final semanticBlock = optionalAnalysis(
      StyioServiceCapability.semanticBlocks.wireValue,
    );
    final inlayHint = optionalAnalysis(
      StyioServiceCapability.inlayHints.wireValue,
    );
    final documentSymbol = optionalAnalysis(
      StyioServiceCapability.documentSymbols.wireValue,
    );
    final references = optionalAnalysis(
      StyioServiceCapability.references.wireValue,
    );

    final collectedGaps = <AnalysisCapabilityGap>[];
    collectedGaps.addAll(base.capabilityGaps);
    if (syntax != null) collectedGaps.addAll(syntax.capabilityGaps);
    if (semantic != null) collectedGaps.addAll(semantic.capabilityGaps);
    if (diagnostics != null) collectedGaps.addAll(diagnostics.capabilityGaps);
    if (formatting != null) collectedGaps.addAll(formatting.capabilityGaps);
    if (semanticBlock != null) collectedGaps.addAll(semanticBlock.capabilityGaps);
    if (inlayHint != null) collectedGaps.addAll(inlayHint.capabilityGaps);
    if (documentSymbol != null) collectedGaps.addAll(documentSymbol.capabilityGaps);
    if (references != null) collectedGaps.addAll(references.capabilityGaps);

    return StyioDocumentAnalysis(
      tokenSpans: syntax?.tokenSpans ?? base.tokenSpans,
      semanticSpans: semantic?.semanticSpans ?? base.semanticSpans,
      diagnostics: diagnostics?.diagnostics ?? base.diagnostics,
      formattingEdits: formatting?.formattingEdits ?? base.formattingEdits,
      semanticBlocks: semanticBlock?.semanticBlocks ?? base.semanticBlocks,
      inlayHints: inlayHint?.inlayHints ?? base.inlayHints,
      documentSymbols: documentSymbol?.documentSymbols ?? base.documentSymbols,
      referenceSpans: references?.referenceSpans ?? base.referenceSpans,
      capabilityGaps: collectedGaps,
    );
  }

  @override
  List<CompletionItem> completeAt(DocumentState document, int offset) {
    return _provider(
      StyioServiceCapability.completion.wireValue,
    ).completeAt(document, offset);
  }

  @override
  DefinitionTarget? definitionAt(DocumentState document, int offset) {
    return _provider(
      StyioServiceCapability.definition.wireValue,
    ).definitionAt(document, offset);
  }

  @override
  ExtractFunctionPlan? extractFunction(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    return _provider(
      StyioServiceCapability.extractFunction.wireValue,
    ).extractFunction(document, range, name);
  }

  @override
  List<FormattingEdit> formatDocument(DocumentState document) {
    return _provider(
      StyioServiceCapability.formatting.wireValue,
    ).formatDocument(document);
  }

  @override
  ChangeSignaturePlan? changeSignatureAt(
    DocumentState document,
    int offset, {
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  }) {
    return _provider(
      StyioServiceCapability.changeSignature.wireValue,
    ).changeSignatureAt(
      document,
      offset,
      newName: newName,
      parameters: parameters,
    );
  }

  @override
  HoverPayload? hoverAt(DocumentState document, int offset) {
    return _provider(
      StyioServiceCapability.hover.wireValue,
    ).hoverAt(document, offset);
  }

  @override
  List<InlayHint> inlayHints(DocumentState document) {
    return _provider(
      StyioServiceCapability.inlayHints.wireValue,
    ).inlayHints(document);
  }

  @override
  InlineVariablePlan? inlineVariableAt(DocumentState document, int offset) {
    return _provider(
      StyioServiceCapability.inlineVariable.wireValue,
    ).inlineVariableAt(document, offset);
  }

  @override
  List<DiagnosticQuickFix> intentionsAt(DocumentState document, int offset) {
    return _provider(
      StyioServiceCapability.codeActions.wireValue,
    ).intentionsAt(document, offset);
  }

  @override
  IntroduceVariablePlan? introduceVariable(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    return _provider(
      StyioServiceCapability.introduceVariable.wireValue,
    ).introduceVariable(document, range, name);
  }

  @override
  ParameterInfoPayload? parameterInfoAt(DocumentState document, int offset) {
    return _provider(
      StyioServiceCapability.parameterInfo.wireValue,
    ).parameterInfoAt(document, offset);
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return _provider(
      StyioServiceCapability.codeActions.wireValue,
    ).quickFixesForDiagnostic(document, diagnostic);
  }

  @override
  List<ReferenceSpan> referencesAt(DocumentState document, int offset) {
    return _provider(
      StyioServiceCapability.references.wireValue,
    ).referencesAt(document, offset);
  }

  @override
  RenamePlan? renameAt(DocumentState document, int offset, String newName) {
    return _provider(
      StyioServiceCapability.rename.wireValue,
    ).renameAt(document, offset, newName);
  }

  @override
  SafeDeletePlan? safeDeleteAt(DocumentState document, int offset) {
    return _provider(
      StyioServiceCapability.safeDelete.wireValue,
    ).safeDeleteAt(document, offset);
  }

  @override
  List<SurroundTemplate> surroundTemplatesAt(
    DocumentState document,
    SourceRange range,
  ) {
    return _provider(
      StyioServiceCapability.surround.wireValue,
    ).surroundTemplatesAt(document, range);
  }
}
