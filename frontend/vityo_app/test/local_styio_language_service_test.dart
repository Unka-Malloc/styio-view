import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/features/styio_formatting_feature.dart';
import 'package:vityo_app/src/view_ide/language/features/styio_inlay_hint_feature.dart';
import 'package:vityo_app/src/view_ide/language/features/styio_semantic_token_feature.dart';
import 'package:vityo_app/src/view_ide/language/features/styio_syntax_diagnostic_feature.dart';
import 'package:vityo_app/src/view_ide/language/semantic/styio_symbol_index.dart';
import 'package:vityo_app/src/view_ide/language/service/language_service_foundation.dart';
import 'package:vityo_app/src/view_ide/language/service/local_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/service/project_document_rule_provider.dart';
import 'package:vityo_app/src/view_ide/language/service/project_styio_document_service.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_language_service.dart';

void main() {
  DocumentState fixtureDocument() {
    final source = File(
      'test/fixtures/language_service/semantic_snapshot.true.styio',
    ).readAsStringSync();
    return DocumentState(
      documentId: 'fixture://semantic_snapshot',
      text: source,
      revision: 1,
    );
  }

  test('analyzes local tokens, symbols, references, and hints', () {
    final document = fixtureDocument();
    final service = const LocalStyioLanguageService();

    final analysis = service.analyzeDocument(document);

    expect(analysis.tokenCount, greaterThan(0));
    expect(analysis.diagnosticCount, 0);
    expect(
      analysis.documentSymbols.map((symbol) => symbol.name),
      contains('value'),
    );
    expect(
      analysis.referenceSpans
          .where((span) => span.name == 'value')
          .map((span) => span.isDeclaration),
      containsAll(<bool>[true, false]),
    );
    expect(analysis.inlayHints.map((hint) => hint.label), contains(': i64'));
  });

  test('provides completion, hover, definition, references, and rename', () {
    final document = fixtureDocument();
    final service = const LocalStyioLanguageService();
    final referenceOffset = document.text.lastIndexOf('value');

    final completions = service.completeAt(document, referenceOffset);
    expect(
      completions.map((item) => item.label),
      containsAll(<String>['schema', 'value']),
    );

    final hover = service.hoverAt(document, referenceOffset);
    expect(hover?.markdown, contains('value'));

    final definition = service.definitionAt(document, referenceOffset);
    expect(definition?.symbol.name, 'value');
    expect(definition?.originRange.start, referenceOffset);

    final references = service.referencesAt(document, referenceOffset);
    expect(references, hasLength(2));

    final rename = service.renameAt(document, referenceOffset, 'nextValue');
    expect(rename, isNotNull);
    expect(rename!.hasConflicts, isFalse);
    expect(rename.edits, hasLength(2));
    expect(rename.edits.every((edit) => edit.newText == 'nextValue'), isTrue);
  });

  test('exposes resolved elements and references through service surface', () {
    final document = fixtureDocument();
    final service = const LocalStyioLanguageService();
    final declarationOffset = document.text.indexOf('value') + 1;
    final referenceOffset = document.text.lastIndexOf('value') + 1;

    final declaration = service.resolvedReferenceAt(
      document,
      declarationOffset,
    );
    final reference = service.resolvedReferenceAt(document, referenceOffset);
    final element = service.resolvedElementAt(document, referenceOffset);

    expect(declaration?.isDeclaration, isTrue);
    expect(declaration?.target.name, 'value');
    expect(reference?.isDeclaration, isFalse);
    expect(reference?.target.name, 'value');
    expect(element?.name, 'value');
  });

  test('reports local delimiter diagnostics without claiming Styio truth', () {
    final service = const LocalStyioLanguageService();
    final document = const DocumentState(
      documentId: 'fixture://broken',
      text: '#main := () => {\n  value := 1\n',
      revision: 1,
    );

    final analysis = service.analyzeDocument(document);

    expect(analysis.diagnostics, isNotEmpty);
    expect(analysis.diagnostics.first.severity, DiagnosticSeverity.error);
    expect(
      analysis.diagnostics.map((diagnostic) => diagnostic.code),
      contains('local.unclosed-delimiter'),
    );
  });

  test('updates semantic block ranges when function boundaries change', () {
    const service = LocalStyioLanguageService();
    const initialDocument = DocumentState(
      documentId: 'fixture://semantic-block-initial',
      text: '#main := () => {\n  value := 1\n}\n',
      revision: 1,
    );
    const expandedDocument = DocumentState(
      documentId: 'fixture://semantic-block-expanded',
      text: '#main := () => {\n  value := 1\n  next := value\n}\n',
      revision: 2,
    );

    final initialBlock = service.analyzeDocument(initialDocument).semanticBlocks.single;
    final expandedBlock = service.analyzeDocument(expandedDocument).semanticBlocks.single;

    expect(initialBlock.label, 'main');
    expect(expandedBlock.label, 'main');
    expect(expandedBlock.range.end, greaterThan(initialBlock.range.end));
  });

  test('keeps token facts when optional local language features fail', () {
    const service = LocalStyioLanguageService(
      semanticTokenFeature: _ThrowingSemanticTokenFeature(),
      syntaxDiagnosticFeature: _ThrowingSyntaxDiagnosticFeature(),
      formattingFeature: _ThrowingFormattingFeature(),
      inlayHintFeature: _ThrowingInlayHintFeature(),
    );
    const document = DocumentState(
      documentId: 'fixture://feature-failure',
      text: '#main := () => {\n  value := 1\n}\n',
      revision: 1,
    );

    final analysis = service.analyzeDocument(document);

    expect(analysis.tokenSpans, isNotEmpty);
    expect(analysis.documentSymbols.map((symbol) => symbol.name), contains('main'));
    expect(analysis.semanticSpans, isEmpty);
    expect(analysis.diagnostics, isEmpty);
    expect(analysis.formattingEdits, isEmpty);
    expect(analysis.inlayHints, isEmpty);
  });

  test('routes local syntax diagnostic quick fixes', () {
    const service = LocalStyioLanguageService();
    const document = DocumentState(
      documentId: 'fixture://broken',
      text: '#main := () => {\n  value := 1\n',
      revision: 1,
    );
    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'local.unclosed-delimiter',
        );

    final fixes = service.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes.single.label, startsWith('Insert matching'));
    expect(fixes.single.edits.single.range.start, document.length);
  });

  test('exposes diagnostic quick fixes as local intentions at cursor', () {
    const service = LocalStyioLanguageService();
    const document = DocumentState(
      documentId: 'fixture://broken',
      text: '#main := () => {\n  value := 1\n',
      revision: 1,
    );
    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'local.unclosed-delimiter',
        );

    final intentions = service.intentionsAt(document, diagnostic.range.start);

    expect(
      intentions.map((intention) => intention.label),
      contains(startsWith('Insert matching')),
    );
  });

  test('exposes formatting edits as local intentions', () {
    const service = LocalStyioLanguageService();
    const document = DocumentState(
      documentId: 'fixture://format-intention',
      text: 'value := 1  ',
      revision: 1,
    );

    final intentions = service.intentionsAt(document, 0);

    expect(intentions.single.label, 'Format document whitespace');
    expect(intentions.single.edits.map((edit) => edit.newText), <String>[
      '',
      '\n',
    ]);
  });

  test('treats diagnostic range end as exclusive for local intentions', () {
    const service = LocalStyioLanguageService();
    const document = DocumentState(
      documentId: 'fixture://broken-boundary',
      text: '#main := () => {\n  value := 1\n',
      revision: 1,
    );
    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'local.unclosed-delimiter',
        );

    final labels = service
        .intentionsAt(document, diagnostic.range.end)
        .map((intention) => intention.label);

    expect(labels, isNot(contains(startsWith('Insert matching'))));
  });

  test('treats operator token end as exclusive for local hover', () {
    const service = LocalStyioLanguageService();
    const document = DocumentState(
      documentId: 'fixture://hover-boundary',
      text: 'value+1',
      revision: 1,
    );

    final hover = service.hoverAt(document, document.text.indexOf('+') + 1);

    expect(hover?.markdown, isNot(contains('arithmetic addition')));
  });

  test('treats project diagnostic range end as exclusive for intentions', () {
    const diagnostic = Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: 'project.boundary',
      message: 'Project boundary diagnostic.',
      range: SourceRange(start: 0, end: 5),
    );
    const service = ProjectStyioDocumentService(
      projectRuleProvider: _FixedProjectDocumentRuleProvider(diagnostic),
    );
    const document = DocumentState(
      documentId: 'fixture://project-boundary',
      text: 'value\n',
      revision: 1,
    );

    final labels = service
        .intentionsAt(document, diagnostic.range.end)
        .map((intention) => intention.label);

    expect(labels, isNot(contains('Project boundary fix')));
  });

  test('treats call argument range end as exclusive for named completions', () {
    const source = '''
fn sum(left: i64, right: i64): i64 {
  emit left
}
value = sum(1, 2)
''';
    final firstArgumentEnd = source.indexOf('1,') + 1;

    final completions = const StyioSymbolIndex().namedArgumentCompletionsAt(
      source,
      firstArgumentEnd,
    );

    expect(completions, isEmpty);
  });
}

class _FixedProjectDocumentRuleProvider implements ProjectDocumentRuleProvider {
  const _FixedProjectDocumentRuleProvider(this.diagnostic);

  final Diagnostic diagnostic;

  @override
  StyioDocumentAnalysis analysisFactsFor(DocumentState document) {
    return StyioDocumentAnalysis(
      tokenSpans: const <TokenSpan>[],
      semanticSpans: const <SemanticSpan>[],
      diagnostics: <Diagnostic>[diagnostic],
      formattingEdits: const <FormattingEdit>[],
      semanticBlocks: const <SemanticBlockRange>[],
      inlayHints: const <InlayHint>[],
      documentSymbols: const <DocumentSymbol>[],
      referenceSpans: const <ReferenceSpan>[],
    );
  }

  @override
  List<Diagnostic> diagnosticsFor(DocumentState document) {
    return <Diagnostic>[diagnostic];
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return const <DiagnosticQuickFix>[
      DiagnosticQuickFix(
        label: 'Project boundary fix',
        detail: 'Boundary-only project fix.',
        edits: <FormattingEdit>[],
      ),
    ];
  }
}

class _ThrowingSemanticTokenFeature extends StyioSemanticTokenFeature {
  const _ThrowingSemanticTokenFeature();

  @override
  List<SemanticSpan> semanticSpans({required SemanticSnapshot snapshot}) {
    throw StateError('semantic feature unavailable');
  }
}

class _ThrowingSyntaxDiagnosticFeature extends StyioSyntaxDiagnosticFeature {
  const _ThrowingSyntaxDiagnosticFeature();

  @override
  List<Diagnostic> diagnosticsFor({
    required DocumentState document,
    required List<TokenSpan> tokens,
  }) {
    throw StateError('diagnostic feature unavailable');
  }
}

class _ThrowingFormattingFeature extends StyioFormattingFeature {
  const _ThrowingFormattingFeature();

  @override
  List<FormattingEdit> formatDocument(DocumentState document) {
    throw StateError('formatting feature unavailable');
  }
}

class _ThrowingInlayHintFeature extends StyioInlayHintFeature {
  const _ThrowingInlayHintFeature();

  @override
  List<InlayHint> inlayHints({
    required DocumentState document,
    required SemanticSnapshot snapshot,
  }) {
    throw StateError('inlay hint feature unavailable');
  }
}
