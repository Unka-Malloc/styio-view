import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import '../semantic/styio_symbol_index.dart';
import '../syntax/styio_syntax_highlighter.dart';
import 'project_document_diagnostics.dart';
import 'project_document_quick_fixes.dart';
import 'project_document_rule_provider.dart';
import 'simple_styio_language_service.dart';
import 'styio_language_service.dart';

class LegacyProjectDocumentRuleProvider implements ProjectDocumentRuleProvider {
  const LegacyProjectDocumentRuleProvider({
    StyioLanguageService service = const SimpleStyioLanguageService(),
    StyioSyntaxHighlighter syntaxHighlighter = const StyioSyntaxHighlighter(),
    StyioSymbolIndex symbolIndex = const StyioSymbolIndex(),
    ProjectDocumentDiagnostics diagnostics =
        const ProjectDocumentDiagnostics(),
    ProjectDocumentQuickFixProvider quickFixes =
        const ProjectDocumentQuickFixProvider(),
  }) : _service = service,
       _syntaxHighlighter = syntaxHighlighter,
       _symbolIndex = symbolIndex,
       _diagnostics = diagnostics,
       _quickFixes = quickFixes;

  final StyioLanguageService _service;
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
    return _dedupeDiagnostics([
      ..._diagnostics.analyze(document),
      ..._service.analyzeDocument(document).diagnostics,
    ]);
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return _dedupeQuickFixes([
      ..._quickFixes.quickFixesForDiagnostic(document, diagnostic),
      ..._service.quickFixesForDiagnostic(document, diagnostic),
    ]);
  }

  List<Diagnostic> _dedupeDiagnostics(Iterable<Diagnostic> diagnostics) {
    final deduped = <Diagnostic>[];
    final seen = <String>{};
    for (final diagnostic in diagnostics) {
      final key =
          '${diagnostic.code}:'
          '${diagnostic.range.start}:${diagnostic.range.end}:'
          '${diagnostic.message}';
      if (seen.add(key)) {
        deduped.add(diagnostic);
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
          .map((edit) => '${edit.range.start}:${edit.range.end}:${edit.newText}')
          .join('|');
      final key = '${fix.label}:$edits';
      if (seen.add(key)) {
        deduped.add(fix);
      }
    }
    return deduped;
  }
}
