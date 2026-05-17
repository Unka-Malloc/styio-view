import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/language/language.dart';
import 'package:vityo_app/src/view_ide/language/simple_styio_language_service.dart';

void main() {
  test('declares the current Styio diagnostic code contract', () {
    expect(
      StyioDiagnosticCatalog.codes,
      equals({
        'ambiguous-imported-symbol',
        'argument-type-mismatch',
        'await-fallback-type-mismatch',
        'assignment-type-mismatch',
        'await-result-type-mismatch',
        'binary-operator-type-mismatch',
        'condition-type-mismatch',
        'conditional-task-return',
        'conflicting-task-return-context',
        'constant-condition',
        'division-by-zero',
        'duplicate-declaration',
        'duplicate-function-declaration',
        'duplicate-import',
        'duplicate-named-argument',
        'duplicate-parameter-declaration',
        'duplicate-resource-declaration',
        'duplicate-task-declaration',
        'import-block-not-optimized',
        'import-cycle',
        'invalid-task-return-expression',
        'initializer-type-mismatch',
        'missing-assignment',
        'missing-call-argument',
        'missing-function-return',
        'missing-task-return',
        'missing-task-return-value',
        'parameter-shadowing',
        'read-only-resource-write',
        'redundant-parentheses',
        'redundant-type-annotation',
        'resource-write-type-mismatch',
        'return-type-mismatch',
        'simplifiable-boolean-comparison',
        'simplifiable-boolean-expression',
        'simplifiable-boolean-negation',
        'simplifiable-demorgan-expression',
        'simplifiable-negated-comparison',
        'simplifiable-numeric-expression',
        'task-return-type-mismatch',
        'todo-comment',
        'too-many-call-arguments',
        'unary-operator-type-mismatch',
        'unclosed-block',
        'unclosed-bracket',
        'unclosed-delimiter',
        'unclosed-parenthesis',
        'unreachable-code',
        'unexpected-closing-brace',
        'unexpected-closing-bracket',
        'unexpected-closing-delimiter',
        'unexpected-closing-parenthesis',
        'unknown-named-argument',
        'unknown-token',
        'unresolved-import',
        'unresolved-reference',
        'unresolved-resource',
        'unresolved-task-await',
        'unresolved-task-return-value',
        'unterminated-block-comment',
        'unterminated-string',
        'unused-exported-symbol',
        'unused-import',
        'unused-local-symbol',
        'unused-parameter',
      }),
    );
  });

  test('keeps descriptor codes unique and indexed by code', () {
    final descriptors = StyioDiagnosticCatalog.all;
    final codes = descriptors.map((descriptor) => descriptor.code).toList();

    expect(codes.toSet(), hasLength(codes.length));
    for (final descriptor in descriptors) {
      expect(StyioDiagnosticCatalog.descriptorFor(descriptor.code), descriptor);
    }
  });

  test('matches emitted document diagnostics to catalog descriptors', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'catalog-current-file.styio',
      text: '''
value = "open
cost = €
fn blend(left: f64, right: f64): f64 {
  emit "bad"
}
count: i64 = 1.5
result = blend(count)
when count -> state ready
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    expect(diagnostics, isNotEmpty);
    for (final diagnostic in diagnostics) {
      final descriptor = StyioDiagnosticCatalog.descriptorFor(diagnostic.code);
      expect(descriptor, isNotNull, reason: diagnostic.code);
      expect(
        diagnostic.severity,
        descriptor!.severity,
        reason: diagnostic.code,
      );
    }
  });

  test('keeps quick fix metadata aligned with actual document fixes', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'catalog-quick-fix-contract.styio',
      text: '''
@import { beta }
@import { alpha }
@import { alpha }
fn price(): f64 {
  emit 3
  stale = 1
}
fn missing(): i64 {
  value = 1
}
result = unknown + 1
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    expect(diagnostics, isNotEmpty);
    for (final diagnostic in diagnostics) {
      final fixes = service.quickFixesForDiagnostic(document, diagnostic);
      if (fixes.isEmpty) {
        continue;
      }

      expect(
        StyioDiagnosticCatalog.descriptorFor(diagnostic.code)!.hasQuickFix,
        isTrue,
        reason:
            '${diagnostic.code} returned quick fixes: '
            '${fixes.map((fix) => fix.label).join(', ')}',
      );
    }
  });

  test('keeps quick fix metadata aligned with actual project fixes', () {
    const service = ProjectStyioLanguageService();
    const documents = [
      DocumentState(
        documentId: 'lib/math.styio',
        text: 'fn blend(left: f64, right: f64): f64 { emit left + right }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'lib/text.styio',
        text: 'fn parse(value: i64): i64 { emit value }\n',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { lib/math }
@import { lib/missing }
value = parse(1)
''',
        revision: 0,
      ),
    ];

    final analysis = service.analyzeProject(documents);
    expect(analysis.diagnostics, isNotEmpty);
    for (final diagnostic in analysis.diagnostics) {
      final fixes = service.quickFixesForProjectDiagnostic(
        documents: documents,
        diagnostic: diagnostic,
      );
      if (fixes.isEmpty) {
        continue;
      }

      expect(
        StyioDiagnosticCatalog.descriptorFor(
          diagnostic.diagnostic.code,
        )!.hasQuickFix,
        isTrue,
        reason:
            '${diagnostic.diagnostic.code} returned project quick fixes: '
            '${fixes.map((fix) => fix.label).join(', ')}',
      );
    }
  });

  test('matches emitted project diagnostics to catalog descriptors', () {
    const service = ProjectStyioLanguageService();
    final analysis = service.analyzeProject(const [
      DocumentState(
        documentId: 'math.styio',
        text: '''
fn scale(value: f64, factor: f64): f64 {
  emit value
}
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'main.styio',
        text: '''
@import { math }
price = 1.0
result = scale(price)
''',
        revision: 0,
      ),
      DocumentState(
        documentId: 'broken.styio',
        text: '@import { missing }',
        revision: 0,
      ),
    ]);

    expect(analysis.diagnostics, isNotEmpty);
    for (final projectDiagnostic in analysis.diagnostics) {
      final diagnostic = projectDiagnostic.diagnostic;
      final descriptor = StyioDiagnosticCatalog.descriptorFor(diagnostic.code);
      expect(descriptor, isNotNull, reason: diagnostic.code);
      expect(
        diagnostic.severity,
        descriptor!.severity,
        reason: diagnostic.code,
      );
    }
  });

  test('exposes compiler diagnostics through the language barrel', () {
    expect(
      StyioDiagnosticCatalog.descriptorFor('missing-function-return')!.phase,
      StyioDiagnosticPhase.controlFlow,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor('unknown-token')!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'missing-function-return',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor('missing-task-return')!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor('missing-task-return-value')!.phase,
      StyioDiagnosticPhase.taskFlow,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'missing-task-return-value',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'invalid-task-return-expression',
      )!.phase,
      StyioDiagnosticPhase.taskFlow,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor('task-return-type-mismatch')!.phase,
      StyioDiagnosticPhase.taskFlow,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'task-return-type-mismatch',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor('return-type-mismatch')!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'duplicate-resource-declaration',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'duplicate-task-declaration',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'resource-write-type-mismatch',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'read-only-resource-write',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'await-result-type-mismatch',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'await-fallback-type-mismatch',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'unresolved-task-return-value',
      )!.phase,
      StyioDiagnosticPhase.taskFlow,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'unresolved-task-return-value',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'conflicting-task-return-context',
      )!.phase,
      StyioDiagnosticPhase.taskFlow,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'conflicting-task-return-context',
      )!.hasQuickFix,
      isFalse,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'redundant-type-annotation',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'redundant-parentheses',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor('constant-condition')!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor('division-by-zero')!.severity,
      DiagnosticSeverity.error,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'simplifiable-numeric-expression',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'simplifiable-boolean-negation',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'simplifiable-boolean-comparison',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'simplifiable-boolean-expression',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'simplifiable-negated-comparison',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'simplifiable-demorgan-expression',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'ambiguous-imported-symbol',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor('import-cycle')!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'unused-exported-symbol',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor('unresolved-resource')!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor(
        'unresolved-task-await',
      )!.hasQuickFix,
      isTrue,
    );
    expect(
      StyioDiagnosticCatalog.descriptorFor('unreachable-code')!.hasQuickFix,
      isTrue,
    );
  });
}
