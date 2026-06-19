import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/service.dart';

void main() {
  test('current registry exposes current project diagnostics and fixes', () {
    final source = File(
      'test/fixtures/language_service/missing_assignment.true.styio',
    ).readAsStringSync();
    final document = DocumentState(
      documentId: 'fixture://missing_assignment',
      text: source,
      revision: 1,
    );
    const registry = ProjectDocumentRuleRegistry.current;
    final diagnostic = registry
        .analysisFactsFor(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'missing-assignment');

    final fixes = registry.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes.map((fix) => fix.label), contains('Insert assignment'));
  });

  test('registry merges project facts by provider priority', () {
    const document = DocumentState(
      documentId: 'fixture://registry',
      text: 'value = 1\n',
      revision: 1,
    );
    const registry = ProjectDocumentRuleRegistry(
      registrations: <ProjectDocumentRuleRegistration>[
        ProjectDocumentRuleRegistration(
          descriptor: ProjectDocumentRuleProviderDescriptor(
            providerId: 'low',
            displayName: 'Low provider',
            priority: 0,
          ),
          provider: _StubProjectRuleProvider(
            code: 'low-diagnostic',
            label: 'Low fix',
          ),
        ),
        ProjectDocumentRuleRegistration(
          descriptor: ProjectDocumentRuleProviderDescriptor(
            providerId: 'high',
            displayName: 'High provider',
            priority: 10,
          ),
          provider: _StubProjectRuleProvider(
            code: 'high-diagnostic',
            label: 'High fix',
          ),
        ),
      ],
    );

    final diagnostics = registry.analysisFactsFor(document).diagnostics;
    final fixes = registry.quickFixesForDiagnostic(document, diagnostics.first);

    expect(diagnostics.map((diagnostic) => diagnostic.code), <String>[
      'high-diagnostic',
      'low-diagnostic',
    ]);
    expect(fixes.map((fix) => fix.label), <String>['High fix', 'Low fix']);
  });

  test('registry dedupes fact collections and sorts equal priorities', () {
    const document = DocumentState(
      documentId: 'fixture://registry-dedupe',
      text: 'value = 1\n',
      revision: 1,
    );
    const registry = ProjectDocumentRuleRegistry(
      registrations: <ProjectDocumentRuleRegistration>[
        ProjectDocumentRuleRegistration(
          descriptor: ProjectDocumentRuleProviderDescriptor(
            providerId: 'beta',
            displayName: 'Beta provider',
            priority: 1,
          ),
          provider: _DuplicateFactsProjectRuleProvider(),
        ),
        ProjectDocumentRuleRegistration(
          descriptor: ProjectDocumentRuleProviderDescriptor(
            providerId: 'alpha',
            displayName: 'Alpha provider',
            priority: 1,
          ),
          provider: _DuplicateFactsProjectRuleProvider(),
        ),
      ],
    );

    final facts = registry.analysisFactsFor(document);
    final diagnostics = registry.diagnosticsFor(document);
    final fixes = registry.quickFixesForDiagnostic(
      document,
      diagnostics.single,
    );

    expect(
      registry.orderedRegistrations.map(
        (registration) => registration.descriptor.providerId,
      ),
      <String>['alpha', 'beta'],
    );
    expect(facts.tokenSpans, hasLength(1));
    expect(facts.semanticSpans, hasLength(1));
    expect(facts.diagnostics, hasLength(1));
    expect(facts.formattingEdits, hasLength(1));
    expect(facts.semanticBlocks, hasLength(1));
    expect(facts.inlayHints, hasLength(1));
    expect(facts.documentSymbols, hasLength(1));
    expect(facts.referenceSpans, hasLength(1));
    expect(diagnostics, hasLength(1));
    expect(fixes, hasLength(1));
  });
}

class _StubProjectRuleProvider implements ProjectDocumentRuleProvider {
  const _StubProjectRuleProvider({
    required this.code,
    required this.label,
  });

  final String code;
  final String label;

  @override
  StyioDocumentAnalysis analysisFactsFor(DocumentState document) {
    return StyioDocumentAnalysis(
      tokenSpans: const <TokenSpan>[],
      semanticSpans: const <SemanticSpan>[],
      diagnostics: diagnosticsFor(document),
      formattingEdits: const <FormattingEdit>[],
      semanticBlocks: const <SemanticBlockRange>[],
      inlayHints: const <InlayHint>[],
      documentSymbols: const <DocumentSymbol>[],
      referenceSpans: const <ReferenceSpan>[],
    );
  }

  @override
  List<Diagnostic> diagnosticsFor(DocumentState document) {
    return <Diagnostic>[
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: code,
        message: code,
        range: const SourceRange(start: 0, end: 1),
      ),
    ];
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return <DiagnosticQuickFix>[
      DiagnosticQuickFix(
        label: label,
        edits: const <FormattingEdit>[
          FormattingEdit(
            range: SourceRange(start: 0, end: 1),
            newText: 'value',
          ),
        ],
      ),
    ];
  }
}

class _DuplicateFactsProjectRuleProvider implements ProjectDocumentRuleProvider {
  const _DuplicateFactsProjectRuleProvider();

  static const SourceRange _range = SourceRange(start: 0, end: 5);
  static const Diagnostic _diagnostic = Diagnostic(
    severity: DiagnosticSeverity.warning,
    code: 'duplicate.fact',
    message: 'duplicate fact',
    range: _range,
  );
  static const FormattingEdit _edit = FormattingEdit(
    range: _range,
    newText: 'value',
  );
  static const DiagnosticQuickFix _fix = DiagnosticQuickFix(
    label: 'Duplicate fact fix',
    edits: <FormattingEdit>[_edit],
  );

  @override
  StyioDocumentAnalysis analysisFactsFor(DocumentState document) {
    return const StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[
        TokenSpan(range: _range, kind: TokenKind.identifier, lexeme: 'value'),
        TokenSpan(range: _range, kind: TokenKind.identifier, lexeme: 'value'),
      ],
      semanticSpans: <SemanticSpan>[
        SemanticSpan(
          range: _range,
          kind: SemanticKind.variable,
          modifiers: <String>['declaration'],
        ),
        SemanticSpan(
          range: _range,
          kind: SemanticKind.variable,
          modifiers: <String>['declaration'],
        ),
      ],
      diagnostics: <Diagnostic>[_diagnostic, _diagnostic],
      formattingEdits: <FormattingEdit>[_edit, _edit],
      semanticBlocks: <SemanticBlockRange>[
        SemanticBlockRange(range: _range, label: 'body'),
        SemanticBlockRange(range: _range, label: 'body'),
      ],
      inlayHints: <InlayHint>[
        InlayHint(
          label: ': i64',
          kind: InlayHintKind.type,
          position: 5,
          range: _range,
        ),
        InlayHint(
          label: ': i64',
          kind: InlayHintKind.type,
          position: 5,
          range: _range,
        ),
      ],
      documentSymbols: <DocumentSymbol>[
        DocumentSymbol(
          name: 'value',
          kind: SymbolKind.variable,
          nameRange: _range,
          declarationRange: _range,
        ),
        DocumentSymbol(
          name: 'value',
          kind: SymbolKind.variable,
          nameRange: _range,
          declarationRange: _range,
        ),
      ],
      referenceSpans: <ReferenceSpan>[
        ReferenceSpan(
          name: 'value',
          kind: SymbolKind.variable,
          range: _range,
          targetRange: _range,
          isDeclaration: true,
          access: ReferenceAccess.declaration,
        ),
        ReferenceSpan(
          name: 'value',
          kind: SymbolKind.variable,
          range: _range,
          targetRange: _range,
          isDeclaration: true,
          access: ReferenceAccess.declaration,
        ),
      ],
    );
  }

  @override
  List<Diagnostic> diagnosticsFor(DocumentState document) {
    return const <Diagnostic>[_diagnostic, _diagnostic];
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return const <DiagnosticQuickFix>[_fix, _fix];
  }
}
