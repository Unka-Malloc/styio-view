import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/service.dart';

void main() {
  test('legacy project rule provider merges service facts and dedupes fixes', () {
    const document = DocumentState(
      documentId: 'fixture://legacy-provider',
      text: '''
fn run() {
  value = 1
}
result = run()
''',
      revision: 1,
    );
    const provider = LegacyProjectDocumentRuleProvider(
      service: _DuplicateFactService(),
    );

    final facts = provider.analysisFactsFor(document);
    final diagnostics = provider.diagnosticsFor(document);
    final duplicateDiagnostic = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'legacy.duplicate',
    );
    final fixes = provider.quickFixesForDiagnostic(document, duplicateDiagnostic);

    expect(facts.documentSymbols.map((symbol) => symbol.name), contains('run'));
    expect(facts.referenceSpans, isNotEmpty);
    expect(
      diagnostics.where((diagnostic) => diagnostic.code == 'legacy.duplicate'),
      hasLength(1),
    );
    expect(fixes.map((fix) => fix.label), ['Duplicate fix']);
  });
}

class _DuplicateFactService extends SimpleStyioLanguageService {
  const _DuplicateFactService();

  static const Diagnostic _diagnostic = Diagnostic(
    severity: DiagnosticSeverity.warning,
    code: 'legacy.duplicate',
    message: 'Duplicate diagnostic',
    range: SourceRange(start: 0, end: 3),
  );

  static const DiagnosticQuickFix _fix = DiagnosticQuickFix(
    label: 'Duplicate fix',
    edits: <FormattingEdit>[
      FormattingEdit(range: SourceRange(start: 0, end: 3), newText: 'run'),
    ],
  );

  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    return const StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[_diagnostic, _diagnostic],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[],
      referenceSpans: <ReferenceSpan>[],
    );
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return const <DiagnosticQuickFix>[_fix, _fix];
  }
}
