import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import 'local_styio_language_service.dart';
import 'project_document_rule_registry.dart';
import 'project_document_rule_provider.dart';
import 'styio_language_service.dart';

class ProjectStyioDocumentService implements StyioLanguageService {
  const ProjectStyioDocumentService({
    this.currentService = const LocalStyioLanguageService(),
    this.projectRuleProvider = ProjectDocumentRuleRegistry.current,
  });

  final StyioLanguageService currentService;
  final ProjectDocumentRuleProvider projectRuleProvider;

  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    final current = currentService.analyzeDocument(document);
    final projectFacts = projectRuleProvider.analysisFactsFor(document);
    return StyioDocumentAnalysis(
      tokenSpans: current.tokenSpans,
      semanticSpans: current.semanticSpans,
      diagnostics: _dedupeDiagnostics([
        ...current.diagnostics,
        ...projectFacts.diagnostics,
      ]),
      formattingEdits: current.formattingEdits,
      semanticBlocks: current.semanticBlocks,
      inlayHints: current.inlayHints,
      documentSymbols: _dedupeDocumentSymbols([
        ...current.documentSymbols,
        ...projectFacts.documentSymbols,
      ]),
      referenceSpans: _dedupeReferenceSpans([
        ...current.referenceSpans,
        ...projectFacts.referenceSpans,
      ]),
    );
  }

  @override
  List<CompletionItem> completeAt(DocumentState document, int offset) {
    return currentService.completeAt(document, offset);
  }

  @override
  List<FormattingEdit> formatDocument(DocumentState document) {
    return currentService.formatDocument(document);
  }

  @override
  List<InlayHint> inlayHints(DocumentState document) {
    return currentService.inlayHints(document);
  }

  @override
  List<SurroundTemplate> surroundTemplatesAt(
    DocumentState document,
    SourceRange range,
  ) {
    return currentService.surroundTemplatesAt(document, range);
  }

  @override
  HoverPayload? hoverAt(DocumentState document, int offset) {
    return currentService.hoverAt(document, offset);
  }

  @override
  DefinitionTarget? definitionAt(DocumentState document, int offset) {
    return currentService.definitionAt(document, offset);
  }

  @override
  List<ReferenceSpan> referencesAt(DocumentState document, int offset) {
    return currentService.referencesAt(document, offset);
  }

  @override
  RenamePlan? renameAt(DocumentState document, int offset, String newName) {
    return currentService.renameAt(document, offset, newName);
  }

  @override
  SafeDeletePlan? safeDeleteAt(DocumentState document, int offset) {
    return currentService.safeDeleteAt(document, offset);
  }

  @override
  InlineVariablePlan? inlineVariableAt(DocumentState document, int offset) {
    return currentService.inlineVariableAt(document, offset);
  }

  @override
  IntroduceVariablePlan? introduceVariable(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    return currentService.introduceVariable(document, range, name);
  }

  @override
  ExtractFunctionPlan? extractFunction(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    return currentService.extractFunction(document, range, name);
  }

  @override
  ChangeSignaturePlan? changeSignatureAt(
    DocumentState document,
    int offset, {
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  }) {
    return currentService.changeSignatureAt(
      document,
      offset,
      newName: newName,
      parameters: parameters,
    );
  }

  @override
  ParameterInfoPayload? parameterInfoAt(DocumentState document, int offset) {
    return currentService.parameterInfoAt(document, offset);
  }

  @override
  List<DiagnosticQuickFix> intentionsAt(DocumentState document, int offset) {
    final currentIntentions = currentService.intentionsAt(document, offset);
    final analysis = analyzeDocument(document);
    final diagnosticFixes = <DiagnosticQuickFix>[];
    for (final diagnostic in analysis.diagnostics) {
      if (!_contains(diagnostic.range, offset)) {
        continue;
      }
      diagnosticFixes.addAll(quickFixesForDiagnostic(document, diagnostic));
    }
    return _dedupeQuickFixes([...currentIntentions, ...diagnosticFixes]);
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final current = currentService.quickFixesForDiagnostic(
      document,
      diagnostic,
    );
    final projectRuleFixes = projectRuleProvider.quickFixesForDiagnostic(
      document,
      diagnostic,
    );
    return _dedupeQuickFixes([...current, ...projectRuleFixes]);
  }

  List<Diagnostic> _dedupeDiagnostics(Iterable<Diagnostic> diagnostics) {
    final deduped = <Diagnostic>[];
    final seen = <String>{};
    for (final diagnostic in diagnostics) {
      final key =
          '${diagnostic.code}:${diagnostic.range.start}:${diagnostic.range.end}:${diagnostic.message}';
      if (seen.add(key)) {
        deduped.add(diagnostic);
      }
    }
    return deduped;
  }

  List<DocumentSymbol> _dedupeDocumentSymbols(
    Iterable<DocumentSymbol> symbols,
  ) {
    final deduped = <DocumentSymbol>[];
    final seen = <String>{};
    for (final symbol in symbols) {
      final key =
          '${symbol.kind.name}:${symbol.name}:'
          '${symbol.nameRange.start}:${symbol.nameRange.end}:'
          '${symbol.declarationRange.start}:${symbol.declarationRange.end}';
      if (seen.add(key)) {
        deduped.add(symbol);
      }
    }
    return deduped;
  }

  List<ReferenceSpan> _dedupeReferenceSpans(
    Iterable<ReferenceSpan> references,
  ) {
    final deduped = <ReferenceSpan>[];
    final seen = <String>{};
    for (final reference in references) {
      final key =
          '${reference.name}:'
          '${reference.range.start}:${reference.range.end}:'
          '${reference.targetRange.start}:${reference.targetRange.end}';
      if (seen.add(key)) {
        deduped.add(reference);
      }
    }
    return deduped;
  }

  List<DiagnosticQuickFix> _dedupeQuickFixes(
    Iterable<DiagnosticQuickFix> fixes,
  ) {
    final deduped = <DiagnosticQuickFix>[];
    final seen = <String>{};
    for (final fix in fixes) {
      final edits = fix.edits
          .map(
            (edit) => '${edit.range.start}:${edit.range.end}:${edit.newText}',
          )
          .join('|');
      final key = '${fix.label}:$edits';
      if (seen.add(key)) {
        deduped.add(fix);
      }
    }
    return deduped;
  }

  bool _contains(SourceRange range, int offset) {
    return range.contains(offset);
  }
}
