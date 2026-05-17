import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import '../semantic/styio_symbol_index.dart';
import '../syntax/styio_syntax_highlighter.dart';
import 'project_document_diagnostics.dart';
import 'project_document_quick_fixes.dart';
import 'project_document_rule_provider.dart';

class CurrentProjectDocumentRuleProvider implements ProjectDocumentRuleProvider {
  const CurrentProjectDocumentRuleProvider({
    StyioSyntaxHighlighter syntaxHighlighter = const StyioSyntaxHighlighter(),
    StyioSymbolIndex symbolIndex = const StyioSymbolIndex(),
    ProjectDocumentDiagnostics diagnostics =
        const ProjectDocumentDiagnostics(),
    ProjectDocumentQuickFixProvider quickFixes =
        const ProjectDocumentQuickFixProvider(),
  }) : _syntaxHighlighter = syntaxHighlighter,
       _symbolIndex = symbolIndex,
       _diagnostics = diagnostics,
       _quickFixes = quickFixes;

  final StyioSyntaxHighlighter _syntaxHighlighter;
  final StyioSymbolIndex _symbolIndex;
  final ProjectDocumentDiagnostics _diagnostics;
  final ProjectDocumentQuickFixProvider _quickFixes;

  @override
  StyioDocumentAnalysis analysisFactsFor(DocumentState document) {
    final tokens = _syntaxHighlighter.tokenize(document.text);
    final symbolSnapshot = _symbolIndex.build(tokens);
    return StyioDocumentAnalysis(
      tokenSpans: const <TokenSpan>[],
      semanticSpans: const <SemanticSpan>[],
      diagnostics: diagnosticsFor(document),
      formattingEdits: const <FormattingEdit>[],
      semanticBlocks: const <SemanticBlockRange>[],
      inlayHints: const <InlayHint>[],
      documentSymbols: symbolSnapshot.symbols,
      referenceSpans: symbolSnapshot.references,
    );
  }

  @override
  List<Diagnostic> diagnosticsFor(DocumentState document) {
    return _diagnostics.analyze(document);
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return _quickFixes.quickFixesForDiagnostic(document, diagnostic);
  }
}
