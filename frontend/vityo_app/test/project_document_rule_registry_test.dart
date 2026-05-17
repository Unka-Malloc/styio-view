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
