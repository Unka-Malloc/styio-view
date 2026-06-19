import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/service.dart';

void main() {
  test('returns diagnostic quick fixes as intentions at cursor', () {
    final source = File(
      'test/fixtures/language_service/missing_assignment.true.styio',
    ).readAsStringSync();
    final document = DocumentState(
      documentId: 'fixture://missing_assignment',
      text: source,
      revision: 1,
    );
    const service = ProjectStyioDocumentService();
    final diagnostic = service
        .analyzeDocument(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'missing-assignment');

    final intentions = service.intentionsAt(document, diagnostic.range.start);

    expect(
      intentions.map((fix) => fix.label),
      contains('Insert assignment'),
    );
  });

  test('forwards document language operations to current service', () {
    const document = DocumentState(
      documentId: 'fixture://project-document-forwarding',
      text: 'value = 1\n',
      revision: 1,
    );
    final current = _RecordingLanguageService();
    final service = ProjectStyioDocumentService(
      currentService: current,
      projectRuleProvider: const _EmptyProjectRuleProvider(),
    );
    const range = SourceRange(start: 0, end: 1);
    const diagnostic = Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: 'project.forwarding',
      message: 'Forwarding diagnostic',
      range: range,
    );

    expect(service.completeAt(document, 0).single.label, 'recorded');
    expect(service.formatDocument(document), isEmpty);
    expect(service.inlayHints(document), isEmpty);
    expect(service.surroundTemplatesAt(document, range), isEmpty);
    expect(service.hoverAt(document, 0)?.markdown, 'recorded-hover');
    expect(service.definitionAt(document, 0)?.symbol.name, 'recorded-symbol');
    expect(service.referencesAt(document, 0).single.name, 'recorded-symbol');
    expect(service.renameAt(document, 0, 'renamed'), isNull);
    expect(service.safeDeleteAt(document, 0), isNull);
    expect(service.inlineVariableAt(document, 0), isNull);
    expect(service.introduceVariable(document, range, 'introduced'), isNull);
    expect(service.extractFunction(document, range, 'extracted'), isNull);
    expect(
      service.changeSignatureAt(
        document,
        0,
        newName: 'changed',
        parameters: const <ChangeSignatureParameterUpdate>[],
      ),
      isNull,
    );
    expect(service.parameterInfoAt(document, 0), isNull);
    expect(service.intentionsAt(document, 0), isEmpty);
    expect(service.quickFixesForDiagnostic(document, diagnostic), isEmpty);

    expect(current.calls, containsAll(<String>[
      'complete',
      'format',
      'inlay',
      'surround',
      'hover',
      'definition',
      'references',
      'rename',
      'safeDelete',
      'inlineVariable',
      'introduceVariable',
      'extractFunction',
      'changeSignature',
      'parameterInfo',
      'intentions',
      'quickFixes',
    ]));
  });
}

class _RecordingLanguageService implements StyioLanguageService {
  final List<String> calls = <String>[];

  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    calls.add('analyze');
    return const StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[],
      referenceSpans: <ReferenceSpan>[],
    );
  }

  @override
  List<CompletionItem> completeAt(DocumentState document, int offset) {
    calls.add('complete');
    return const <CompletionItem>[
      CompletionItem(
        label: 'recorded',
        kind: CompletionItemKind.variable,
        insertText: 'recorded',
      ),
    ];
  }

  @override
  List<FormattingEdit> formatDocument(DocumentState document) {
    calls.add('format');
    return const <FormattingEdit>[];
  }

  @override
  List<InlayHint> inlayHints(DocumentState document) {
    calls.add('inlay');
    return const <InlayHint>[];
  }

  @override
  List<SurroundTemplate> surroundTemplatesAt(
    DocumentState document,
    SourceRange range,
  ) {
    calls.add('surround');
    return const <SurroundTemplate>[];
  }

  @override
  HoverPayload? hoverAt(DocumentState document, int offset) {
    calls.add('hover');
    return const HoverPayload(
      range: SourceRange(start: 0, end: 1),
      markdown: 'recorded-hover',
    );
  }

  @override
  DefinitionTarget? definitionAt(DocumentState document, int offset) {
    calls.add('definition');
    return const DefinitionTarget(
      symbol: DocumentSymbol(
        name: 'recorded-symbol',
        kind: SymbolKind.variable,
        nameRange: SourceRange(start: 0, end: 1),
        declarationRange: SourceRange(start: 0, end: 1),
      ),
      originRange: SourceRange(start: 0, end: 1),
    );
  }

  @override
  List<ReferenceSpan> referencesAt(DocumentState document, int offset) {
    calls.add('references');
    return const <ReferenceSpan>[
      ReferenceSpan(
        name: 'recorded-symbol',
        kind: SymbolKind.variable,
        range: SourceRange(start: 0, end: 1),
        targetRange: SourceRange(start: 0, end: 1),
      ),
    ];
  }

  @override
  RenamePlan? renameAt(DocumentState document, int offset, String newName) {
    calls.add('rename');
    return null;
  }

  @override
  SafeDeletePlan? safeDeleteAt(DocumentState document, int offset) {
    calls.add('safeDelete');
    return null;
  }

  @override
  InlineVariablePlan? inlineVariableAt(DocumentState document, int offset) {
    calls.add('inlineVariable');
    return null;
  }

  @override
  IntroduceVariablePlan? introduceVariable(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    calls.add('introduceVariable');
    return null;
  }

  @override
  ExtractFunctionPlan? extractFunction(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    calls.add('extractFunction');
    return null;
  }

  @override
  ChangeSignaturePlan? changeSignatureAt(
    DocumentState document,
    int offset, {
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  }) {
    calls.add('changeSignature');
    return null;
  }

  @override
  ParameterInfoPayload? parameterInfoAt(DocumentState document, int offset) {
    calls.add('parameterInfo');
    return null;
  }

  @override
  List<DiagnosticQuickFix> intentionsAt(DocumentState document, int offset) {
    calls.add('intentions');
    return const <DiagnosticQuickFix>[];
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    calls.add('quickFixes');
    return const <DiagnosticQuickFix>[];
  }
}

class _EmptyProjectRuleProvider implements ProjectDocumentRuleProvider {
  const _EmptyProjectRuleProvider();

  @override
  StyioDocumentAnalysis analysisFactsFor(DocumentState document) {
    return const StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[],
      referenceSpans: <ReferenceSpan>[],
    );
  }

  @override
  List<Diagnostic> diagnosticsFor(DocumentState document) {
    return const <Diagnostic>[];
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return const <DiagnosticQuickFix>[];
  }
}
