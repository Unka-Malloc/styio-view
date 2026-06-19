import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/service.dart';

void main() {
  test('project rule provider gets current diagnostics without legacy facts', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'main.styio',
      text: 'value := 1 / 0\n',
      revision: 1,
    );

    final analysis = provider.analysisFactsFor(document);
    final codes = analysis.diagnostics.map((diagnostic) => diagnostic.code);

    expect(codes, contains('division-by-zero'));
    expect(analysis.documentSymbols.map((symbol) => symbol.name), contains('value'));
  });

  test('project rule provider gets current numeric quick fixes without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'main.styio',
      text: 'value := 1 + 0\n',
      revision: 1,
    );
    final diagnostic = provider
        .analysisFactsFor(document)
        .diagnostics
        .singleWhere(
          (diagnostic) => diagnostic.code == 'simplifiable-numeric-expression',
        );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Simplify numeric expression');
    expect(fixes.single.edits.single.newText, '1');
  });

  test('project rule provider gets current expression diagnostics without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'expression-diagnostics.styio',
      text:
          'ready = true\n'
          'blocked = false\n'
          'price = 12.5\n'
          'count: i64 = 3\n'
          'limit = 10.0\n'
          'total = (price)\n'
          'when true && false -> state never\n'
          'when !!ready -> state ready\n'
          'when ready == false -> state stopped\n'
          'when ready || (ready && blocked) -> state absorbed\n'
          'when !(price > limit) -> state affordable\n'
          'when !(ready && blocked) -> state active\n',
      revision: 1,
    );

    final codes = provider
        .analysisFactsFor(document)
        .diagnostics
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    expect(codes, contains('redundant-parentheses'));
    expect(codes, contains('redundant-type-annotation'));
    expect(codes, contains('constant-condition'));
    expect(codes, contains('simplifiable-boolean-negation'));
    expect(codes, contains('simplifiable-boolean-comparison'));
    expect(codes, contains('simplifiable-boolean-expression'));
    expect(codes, contains('simplifiable-negated-comparison'));
    expect(codes, contains('simplifiable-demorgan-expression'));
  });

  test('project rule provider gets current symbol diagnostics without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'symbol-diagnostics.styio',
      text:
          'fn normalize(value: f64): f64 {\n'
          '  value = 1.0\n'
          '  emit value\n'
          '}\n'
          'used = 1\n'
          'unused = 2\n'
          'used -> @stdout\n'
          'duplicate = 1\n'
          'duplicate = 2\n'
          '@prices : i64|..1| := {}\n'
          '@prices : i64|..1| := {}\n'
          'load = ||> { <| 1 }\n'
          'load = ||> { <| 2 }\n',
      revision: 1,
    );

    final codes = provider
        .analysisFactsFor(document)
        .diagnostics
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    expect(codes, contains('duplicate-declaration'));
    expect(codes, contains('duplicate-resource-declaration'));
    expect(codes, contains('duplicate-task-declaration'));
    expect(codes, contains('parameter-shadowing'));
    expect(codes, contains('unused-local-symbol'));
  });

  test('project rule provider gets current document flow diagnostics without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'document-flow-diagnostics.styio',
      text:
          '@import { styio/io }\n'
          '@import { styio/core }\n'
          '@import { styio/io }\n'
          'fn blend(left: f64, right: f64) {\n'
          '  emit left\n'
          '}\n'
          'main = ||> {\n'
          '  <| 1\n'
          '  value = 2\n'
          '}\n'
          'resource = 1\n'
          'resource <- 2\n',
      revision: 1,
    );

    final codes = provider
        .analysisFactsFor(document)
        .diagnostics
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    expect(codes, contains('duplicate-import'));
    expect(codes, contains('import-block-not-optimized'));
    expect(codes, contains('unused-parameter'));
    expect(codes, contains('unreachable-code'));
    expect(codes, contains('read-only-resource-write'));
  });

  test('project rule provider gets current call diagnostics without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'call-diagnostics.styio',
      text:
          'fn blend(left: f64, right: f64, scale: f64) {\n'
          '  emit left\n'
          '}\n'
          'price = 1\n'
          'tax = 2\n'
          'blend(price) -> @stdout\n'
          'blend(price, tax, price, tax) -> @stdout\n'
          'blend(left: price, rigth: tax, scale: price) -> @stdout\n'
          'blend(left: price, left: tax, scale: price) -> @stdout\n'
          'blend(price, tax, 3) -> @stdout\n',
      revision: 1,
    );

    final codes = provider
        .analysisFactsFor(document)
        .diagnostics
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    expect(codes, contains('missing-call-argument'));
    expect(codes, contains('too-many-call-arguments'));
    expect(codes, contains('unknown-named-argument'));
    expect(codes, contains('duplicate-named-argument'));
    expect(codes, contains('argument-type-mismatch'));
  });

  test('project rule provider gets current type diagnostics without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'type-diagnostics.styio',
      text:
          'fn expectFloat(value: f64): f64 {\n'
          '  <| 1\n'
          '}\n'
          'wide: f64 = 3\n'
          'wide = true\n'
          'mixed = 1 + true\n'
          'negative = -true\n'
          'when 1 -> state invalid\n',
      revision: 1,
    );

    final codes = provider
        .analysisFactsFor(document)
        .diagnostics
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    expect(codes, contains('initializer-type-mismatch'));
    expect(codes, contains('assignment-type-mismatch'));
    expect(codes, contains('binary-operator-type-mismatch'));
    expect(codes, contains('unary-operator-type-mismatch'));
    expect(codes, contains('condition-type-mismatch'));
    expect(codes, contains('return-type-mismatch'));
  });

  test('project rule provider gets current missing assignment fix without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'main.styio',
      text: 'let stream\n',
      revision: 1,
    );
    final diagnostic = provider
        .analysisFactsFor(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'missing-assignment');

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Insert assignment');
    expect(fixes.single.edits.single.newText, ' = value');
  });

  test('project rule provider gets current syntax fixes without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'main.styio',
      text: '{\n',
      revision: 1,
    );
    final diagnostic = provider
        .analysisFactsFor(document)
        .diagnostics
        .singleWhere((diagnostic) => diagnostic.code == 'unclosed-block');

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Append closing brace');
    expect(fixes.single.edits.single.newText, '}');
  });

  test('project rule provider gets current unreachable code fix without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'main.styio',
      text: 'first\nsecond\nthird\n',
      revision: 1,
    );
    const diagnostic = Diagnostic(
      severity: DiagnosticSeverity.hint,
      code: 'unreachable-code',
      message: 'Code is unreachable.',
      range: SourceRange(start: 6, end: 12),
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Remove unreachable code');
    expect(fixes.single.edits.single.newText, '');
    expect(fixes.single.edits.single.range.start, 6);
    expect(fixes.single.edits.single.range.end, 13);
  });

  test('project rule provider removes stray tokens and closes strings', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'value = 1 )\n'
        '"unterminated\n';
    const document = DocumentState(
      documentId: 'syntax-quick-fixes.styio',
      text: text,
      revision: 1,
    );
    final strayStart = text.indexOf(')');
    final quoteStart = text.indexOf('"unterminated');

    final removeFix = provider
        .quickFixesForDiagnostic(
          document,
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'unexpected-closing-parenthesis',
            message: 'Unexpected closing parenthesis.',
            range: SourceRange(start: strayStart, end: strayStart + 1),
          ),
        )
        .single;
    final stringFix = provider
        .quickFixesForDiagnostic(
          document,
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'unterminated-string',
            message: 'String literal is not closed.',
            range: SourceRange(start: quoteStart, end: text.length),
          ),
        )
        .single;

    expect(removeFix.label, 'Remove stray delimiter');
    expect(removeFix.edits.single.newText, '');
    expect(stringFix.label, 'Insert closing quote');
    expect(stringFix.edits.single.newText, '"');
  });

  test('project rule provider gets current unused local fix without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'main.styio',
      text: 'used = 1\nunused = 2\nnext = 3\n',
      revision: 1,
    );
    const diagnostic = Diagnostic(
      severity: DiagnosticSeverity.hint,
      code: 'unused-local-symbol',
      message: 'Local symbol is never used.',
      range: SourceRange(start: 9, end: 15),
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Remove unused declaration');
    expect(fixes.single.edits.single.newText, '');
    expect(fixes.single.edits.single.range.start, 9);
    expect(fixes.single.edits.single.range.end, 20);
  });

  test('project rule provider removes unused task block without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'main.styio',
      text: 'main ||> {\n  value = 1\n}\nnext = 2\n',
      revision: 1,
    );
    const diagnostic = Diagnostic(
      severity: DiagnosticSeverity.hint,
      code: 'unused-local-symbol',
      message: 'Task is never awaited.',
      range: SourceRange(start: 0, end: 4),
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Remove unused task declaration');
    expect(fixes.single.edits.single.newText, '');
    expect(fixes.single.edits.single.range.start, 0);
    expect(fixes.single.edits.single.range.end, 25);
  });

  test('project rule provider gets current read-only write fix without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'main.styio',
      text: 'resource = 1\nresource <- 2\nnext = 3\n',
      revision: 1,
    );
    const diagnostic = Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: 'read-only-resource-write',
      message: 'Cannot write to read-only resource.',
      range: SourceRange(start: 13, end: 26),
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Remove read-only resource write');
    expect(fixes.single.edits.single.newText, '');
    expect(fixes.single.edits.single.range.start, 13);
    expect(fixes.single.edits.single.range.end, 27);
  });

  test('project rule provider removes duplicate resource without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'main.styio',
      text: 'res @file\nres @file\nnext = 1\n',
      revision: 1,
    );
    const diagnostic = Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'duplicate-resource-declaration',
      message: 'Resource is already declared.',
      range: SourceRange(start: 10, end: 13),
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Remove duplicate resource declaration');
    expect(fixes.single.edits.single.newText, '');
    expect(fixes.single.edits.single.range.start, 10);
    expect(fixes.single.edits.single.range.end, 20);
  });

  test('project rule provider removes duplicate task block without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const document = DocumentState(
      documentId: 'main.styio',
      text: 'main ||> {\n  value = 1\n}\nnext = 2\n',
      revision: 1,
    );
    const diagnostic = Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'duplicate-task-declaration',
      message: 'Task is already declared.',
      range: SourceRange(start: 0, end: 4),
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Remove duplicate task declaration');
    expect(fixes.single.edits.single.newText, '');
    expect(fixes.single.edits.single.range.start, 0);
    expect(fixes.single.edits.single.range.end, 25);
  });

  test('project rule provider renames duplicate declaration without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'value = 1\n'
        'value = 2\n'
        'value -> @stdout\n';
    const document = DocumentState(
      documentId: 'duplicate-declaration.styio',
      text: text,
      revision: 1,
    );
    final duplicateStart = text.indexOf('value = 2');
    final diagnostic = Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'duplicate-declaration',
      message: 'Declaration `value` is already defined in this scope.',
      range: SourceRange(
        start: duplicateStart,
        end: duplicateStart + 'value'.length,
      ),
    );

    final fix = provider.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Rename duplicate declaration to `value2`');
    expect(_applyFormattingEdits(text, fix.edits), '''
value = 1
value2 = 2
value2 -> @stdout
''');
  });

  test('project rule provider increments duplicate rename suffixes', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'value = 1\n'
        'value2 = 2\n'
        'value = 3\n'
        'value -> @stdout\n';
    const document = DocumentState(
      documentId: 'duplicate-declaration-suffix.styio',
      text: text,
      revision: 1,
    );
    final duplicateStart = text.indexOf('value = 3');
    final diagnostic = Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'duplicate-declaration',
      message: 'Declaration `value` is already defined in this scope.',
      range: SourceRange(
        start: duplicateStart,
        end: duplicateStart + 'value'.length,
      ),
    );

    final fix = provider.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Rename duplicate declaration to `value3`');
    expect(_applyFormattingEdits(text, fix.edits), '''
value = 1
value2 = 2
value3 = 3
value3 -> @stdout
''');
  });

  test('project rule provider renames parameter shadowing without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'fn normalize(value: f64): f64 {\n'
        '  value = 1.0\n'
        '  emit value\n'
        '}\n';
    final shadowedStart = text.indexOf('value = 1.0');
    final document = const DocumentState(
      documentId: 'parameter-shadowing.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: 'parameter-shadowing',
      message: 'Local declaration `value` shadows a function parameter.',
      range: SourceRange(start: shadowedStart, end: shadowedStart + 5),
    );

    final fix = provider.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Rename shadowing declaration to `value2`');
    expect(_applyFormattingEdits(text, fix.edits), '''
fn normalize(value: f64): f64 {
  value2 = 1.0
  emit value2
}
''');
  });

  test('project rule provider removes unused parameter without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'fn blend(left: f64, right: f64) {\n'
        '  emit left\n'
        '}\n'
        'value = blend(price, tax)\n'
        'again = blend(total, fee)\n';
    const document = DocumentState(
      documentId: 'unused-parameter.styio',
      text: text,
      revision: 1,
    );
    final rightStart = text.indexOf('right');
    final diagnostic = Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: 'unused-parameter',
      message: 'Parameter `right` is never used in `blend`.',
      range: SourceRange(start: rightStart, end: rightStart + 'right'.length),
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Remove unused parameter');
    expect(_applyFormattingEdits(text, fixes.single.edits), '''
fn blend(left: f64) {
  emit left
}
value = blend(price)
again = blend(total)
''');
  });

  test('project rule provider optimizes duplicate imports without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        '@import { styio/io }\n'
        '@import { styio/core }\n'
        '@import { styio/io }\n'
        'value = 1\n';
    const document = DocumentState(
      documentId: 'imports.styio',
      text: text,
      revision: 1,
    );
    const diagnostic = Diagnostic(
      severity: DiagnosticSeverity.warning,
      code: 'duplicate-import',
      message: 'Import `styio/io` is already declared.',
      range: SourceRange(start: 44, end: 64),
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Optimize imports');
    expect(_applyFormattingEdits(text, fixes.single.edits), '''
@import { styio/core }
@import { styio/io }
value = 1
''');
  });

  test('project rule provider optimizes unsorted imports without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        '@import { styio/io }\n'
        '@import { styio/core }\n'
        'value = 1\n';
    const document = DocumentState(
      documentId: 'unsorted-imports.styio',
      text: text,
      revision: 1,
    );
    const diagnostic = Diagnostic(
      severity: DiagnosticSeverity.hint,
      code: 'import-block-not-optimized',
      message: 'Top-level Styio imports can be optimized.',
      range: SourceRange(start: 0, end: 43),
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Optimize imports');
    expect(_applyFormattingEdits(text, fixes.single.edits), '''
@import { styio/core }
@import { styio/io }
value = 1
''');
  });

  test('project rule provider removes redundant type without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'price: f64 = 12.5\n'
        'count: i64 = 3\n'
        'price -> @stdout\n'
        'count -> @stdout\n';
    const document = DocumentState(
      documentId: 'redundant-type-annotation.styio',
      text: text,
      revision: 1,
    );
    final typeStart = text.indexOf(': f64');
    final diagnostic = Diagnostic(
      severity: DiagnosticSeverity.hint,
      code: 'redundant-type-annotation',
      message: 'Explicit type `f64` on `price` is redundant.',
      range: SourceRange(start: typeStart, end: typeStart + ': f64'.length),
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Remove redundant type annotation');
    expect(_applyFormattingEdits(text, fixes.single.edits), '''
price = 12.5
count: i64 = 3
price -> @stdout
count -> @stdout
''');
  });

  test('project rule provider removes redundant parentheses without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'price = 12\n'
        'total = (price)\n'
        'total -> @stdout\n';
    final expressionStart = text.indexOf('(price)');
    const document = DocumentState(
      documentId: 'redundant-parentheses.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = Diagnostic(
      severity: DiagnosticSeverity.hint,
      code: 'redundant-parentheses',
      message: 'Parentheses do not change this expression.',
      range: SourceRange(start: expressionStart, end: expressionStart + 7),
    );

    final fix = provider.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Remove redundant parentheses');
    expect(_applyFormattingEdits(text, fix.edits), '''
price = 12
total = price
total -> @stdout
''');
  });

  test('project rule provider simplifies constant condition without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const condition = 'true && false';
    const text =
        'value = 1\n'
        'when true && false -> value -> @stdout\n'
        'next = 2\n';
    final conditionStart = text.indexOf(condition);
    const document = DocumentState(
      documentId: 'constant-condition.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = Diagnostic(
      severity: DiagnosticSeverity.hint,
      code: 'constant-condition',
      message: 'Condition is always false.',
      range: SourceRange(
        start: conditionStart,
        end: conditionStart + condition.length,
      ),
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);
    final replaceFix = fixes.singleWhere(
      (fix) => fix.label == 'Replace condition with false',
    );
    final removeFix = fixes.singleWhere(
      (fix) => fix.label == 'Remove unreachable `when` branch',
    );

    expect(_applyFormattingEdits(text, replaceFix.edits), '''
value = 1
when false -> value -> @stdout
next = 2
''');
    expect(_applyFormattingEdits(text, removeFix.edits), '''
value = 1
next = 2
''');
  });

  test('project rule provider fixes boolean simplifications without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'ready = true\n'
        'blocked = false\n'
        'price = 12.5\n'
        'limit = 10.0\n'
        'when !!ready -> state ready\n'
        'when ready == false -> state stopped\n'
        'when ready || (ready && blocked) -> state absorbed\n'
        'when !(price > limit) -> state affordable\n'
        'when !(ready && blocked) -> state active\n';
    const document = DocumentState(
      documentId: 'boolean-simplifications.styio',
      text: text,
      revision: 1,
    );
    Diagnostic diagnosticFor(String code, String expression) {
      final start = text.indexOf(expression);
      return Diagnostic(
        severity: DiagnosticSeverity.hint,
        code: code,
        message: 'Boolean expression can be simplified.',
        range: SourceRange(start: start, end: start + expression.length),
      );
    }

    final negationFix = provider
        .quickFixesForDiagnostic(
          document,
          diagnosticFor('simplifiable-boolean-negation', '!!ready'),
        )
        .single;
    final comparisonFix = provider
        .quickFixesForDiagnostic(
          document,
          diagnosticFor('simplifiable-boolean-comparison', 'ready == false'),
        )
        .single;
    final expressionFix = provider
        .quickFixesForDiagnostic(
          document,
          diagnosticFor(
            'simplifiable-boolean-expression',
            'ready || (ready && blocked)',
          ),
        )
        .single;
    final negatedComparisonFix = provider
        .quickFixesForDiagnostic(
          document,
          diagnosticFor('simplifiable-negated-comparison', '!(price > limit)'),
        )
        .single;
    final deMorganFix = provider
        .quickFixesForDiagnostic(
          document,
          diagnosticFor(
            'simplifiable-demorgan-expression',
            '!(ready && blocked)',
          ),
        )
        .single;

    expect(negationFix.label, 'Simplify double negation');
    expect(comparisonFix.label, 'Simplify boolean comparison');
    expect(expressionFix.label, 'Simplify boolean expression');
    expect(negatedComparisonFix.label, 'Simplify negated comparison');
    expect(deMorganFix.label, 'Apply De Morgan\'s law');

    expect(_applyFormattingEdits(text, negationFix.edits), '''
ready = true
blocked = false
price = 12.5
limit = 10.0
when ready -> state ready
when ready == false -> state stopped
when ready || (ready && blocked) -> state absorbed
when !(price > limit) -> state affordable
when !(ready && blocked) -> state active
''');
    expect(_applyFormattingEdits(text, comparisonFix.edits), '''
ready = true
blocked = false
price = 12.5
limit = 10.0
when !!ready -> state ready
when !ready -> state stopped
when ready || (ready && blocked) -> state absorbed
when !(price > limit) -> state affordable
when !(ready && blocked) -> state active
''');
    expect(_applyFormattingEdits(text, expressionFix.edits), '''
ready = true
blocked = false
price = 12.5
limit = 10.0
when !!ready -> state ready
when ready == false -> state stopped
when ready -> state absorbed
when !(price > limit) -> state affordable
when !(ready && blocked) -> state active
''');
    expect(_applyFormattingEdits(text, negatedComparisonFix.edits), '''
ready = true
blocked = false
price = 12.5
limit = 10.0
when !!ready -> state ready
when ready == false -> state stopped
when ready || (ready && blocked) -> state absorbed
when price <= limit -> state affordable
when !(ready && blocked) -> state active
''');
    expect(_applyFormattingEdits(text, deMorganFix.edits), '''
ready = true
blocked = false
price = 12.5
limit = 10.0
when !!ready -> state ready
when ready == false -> state stopped
when ready || (ready && blocked) -> state absorbed
when !(price > limit) -> state affordable
when !ready || !blocked -> state active
''');
  });

  test('project rule provider fixes boolean simplification edge forms', () {
    const provider = CurrentProjectDocumentRuleProvider();

    DiagnosticQuickFix fixFor(String code, String expression) {
      final document = DocumentState(
        documentId: 'boolean-edge.styio',
        text: expression,
        revision: 1,
      );
      return provider
          .quickFixesForDiagnostic(
            document,
            Diagnostic(
              severity: DiagnosticSeverity.hint,
              code: code,
              message: 'Boolean expression can be simplified.',
              range: SourceRange(start: 0, end: expression.length),
            ),
          )
          .single;
    }

    expect(
      fixFor('simplifiable-boolean-negation', '!false').edits.single.newText,
      'true',
    );
    expect(
      fixFor('simplifiable-boolean-comparison', 'ready == ready')
          .edits
          .single
          .newText,
      'true',
    );
    expect(
      fixFor('simplifiable-boolean-comparison', 'true == ready')
          .edits
          .single
          .newText,
      'ready',
    );
    expect(
      fixFor('simplifiable-boolean-comparison', 'true != ready')
          .edits
          .single
          .newText,
      '!ready',
    );
    expect(
      fixFor('simplifiable-boolean-comparison', 'ready != true')
          .edits
          .single
          .newText,
      '!ready',
    );
    expect(
      fixFor('simplifiable-boolean-expression', 'ready && blocked || ready')
          .edits
          .single
          .newText,
      'ready',
    );
    expect(
      fixFor('simplifiable-boolean-expression', '(ready || blocked) && ready')
          .edits
          .single
          .newText,
      'ready',
    );
    expect(
      fixFor(
        'simplifiable-demorgan-expression',
        '!(price > limit || !ready)',
      ).edits.single.newText,
      'price <= limit && ready',
    );
  });

  test('project rule provider creates unresolved resource without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text = 'price = 1.0\nprice -> @prices\n';
    const document = DocumentState(
      documentId: 'unresolved-resource.styio',
      text: text,
      revision: 1,
    );
    final resourceStart = text.indexOf('@prices');
    final diagnostic = Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'unresolved-resource',
      message: 'Resource `@prices` is not declared.',
      range: SourceRange(
        start: resourceStart,
        end: resourceStart + '@prices'.length,
      ),
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Create resource `@prices`');
    expect(_applyFormattingEdits(text, fixes.single.edits), '''
@prices : f64|..1| := {}
price = 1.0
price -> @prices
''');
  });

  test('project rule provider creates unresolved task without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text = '?| load -> result: string\n';
    const document = DocumentState(
      documentId: 'unresolved-task.styio',
      text: text,
      revision: 1,
    );
    final taskStart = text.indexOf('load');
    final diagnostic = Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'unresolved-task-await',
      message: 'Task `load` is not declared.',
      range: SourceRange(start: taskStart, end: taskStart + 'load'.length),
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);

    expect(fixes, hasLength(1));
    expect(fixes.single.label, 'Create task `load`');
    expect(_applyFormattingEdits(text, fixes.single.edits), '''
load = ||> {
  <| ""
}

?| load -> result: string
''');
  });

  test('project rule provider fixes unresolved references without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const typoText =
        'movingAverage = 1\n'
        'movingAverge -> @stdout\n';
    final typoStart = typoText.indexOf('movingAverge');
    const typoDocument = DocumentState(
      documentId: 'unresolved-reference-typo.styio',
      text: typoText,
      revision: 1,
    );
    final typoDiagnostic = Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'unresolved-reference',
      message: 'Unresolved reference `movingAverge`.',
      range: SourceRange(
        start: typoStart,
        end: typoStart + 'movingAverge'.length,
      ),
    );

    final typoFixes = provider.quickFixesForDiagnostic(
      typoDocument,
      typoDiagnostic,
    );

    expect(typoFixes.first.label, 'Change to `movingAverage`');
    expect(
      typoFixes.map((fix) => fix.label),
      contains('Create local binding `movingAverge`'),
    );
    expect(_applyFormattingEdits(typoText, typoFixes.first.edits), '''
movingAverage = 1
movingAverage -> @stdout
''');

    const callText =
        '@import { styio/math }\n'
        'price = 1\n'
        'tax = 2\n'
        'total = calculate(price, tax)\n';
    final callStart = callText.indexOf('calculate');
    const callDocument = DocumentState(
      documentId: 'unresolved-reference-call.styio',
      text: callText,
      revision: 1,
    );
    final callDiagnostic = Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'unresolved-reference',
      message: 'Unresolved reference `calculate`.',
      range: SourceRange(
        start: callStart,
        end: callStart + 'calculate'.length,
      ),
    );

    final callFixes = provider.quickFixesForDiagnostic(
      callDocument,
      callDiagnostic,
    );

    expect(callFixes.map((fix) => fix.label), [
      'Create function `calculate`',
      'Create local binding `calculate`',
    ]);
    expect(callFixes.first.edits.single.newText, '''#calculate := (price, tax) => {
  <| value
}

''');
    expect(callFixes.first.edits.single.range.start, callText.indexOf('price'));
  });

  test('project rule provider fixes call arity without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'fn blend(left: f64, right: f64) {\n'
        '  emit left\n'
        '}\n'
        'price = 1\n'
        'tax = 2\n'
        'blend(price) -> @stdout\n'
        'blend(price, tax, price) -> @stdout\n';
    const document = DocumentState(
      documentId: 'call-arity.styio',
      text: text,
      revision: 1,
    );
    final diagnostics = provider.diagnosticsFor(document);
    final missing = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'missing-call-argument',
    );
    final extra = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'too-many-call-arguments',
    );

    final missingFix = provider.quickFixesForDiagnostic(
      document,
      missing,
    ).single;
    final extraFix = provider.quickFixesForDiagnostic(document, extra).single;

    expect(missingFix.label, 'Insert missing argument');
    expect(missingFix.edits.single.newText, 'price, value');
    expect(extraFix.label, 'Remove extra argument');
    expect(extraFix.edits.single.newText, 'price, tax');
  });

  test('project rule provider fixes named call arguments without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'fn blend(left: f64, right: f64, scale: f64) {\n'
        '  emit left\n'
        '}\n'
        'price = 1\n'
        'tax = 2\n'
        'factor = 3\n'
        'typo = blend(left: price, rigth: tax, scale: factor)\n'
        'duplicate = blend(left: price, left: tax, scale: factor)\n';
    const document = DocumentState(
      documentId: 'named-arguments.styio',
      text: text,
      revision: 1,
    );
    final diagnostics = provider.diagnosticsFor(document);
    final unknown = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'unknown-named-argument',
    );
    final duplicate = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'duplicate-named-argument',
    );

    final unknownFix = provider.quickFixesForDiagnostic(
      document,
      unknown,
    ).single;
    final duplicateFix = provider.quickFixesForDiagnostic(
      document,
      duplicate,
    ).single;

    expect(unknownFix.label, 'Change argument name to `right`');
    expect(_applyFormattingEdits(text, unknownFix.edits), '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left
}
price = 1
tax = 2
factor = 3
typo = blend(left: price, right: tax, scale: factor)
duplicate = blend(left: price, left: tax, scale: factor)
''');
    expect(duplicateFix.label, 'Remove duplicate `left` argument');
    expect(_applyFormattingEdits(text, duplicateFix.edits), '''
fn blend(left: f64, right: f64, scale: f64) {
  emit left
}
price = 1
tax = 2
factor = 3
typo = blend(left: price, rigth: tax, scale: factor)
duplicate = blend(left: price, scale: factor)
''');
  });

  test('project rule provider fixes call argument types without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'fn emitPrice(value: f64) {\n'
        '  emit value\n'
        '}\n'
        'emitPrice(3) -> @stdout\n';
    const document = DocumentState(
      documentId: 'argument-type.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = provider.diagnosticsFor(document).singleWhere(
      (diagnostic) => diagnostic.code == 'argument-type-mismatch',
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);
    final literalFix = fixes.singleWhere(
      (fix) => fix.label == 'Change argument to f64 literal',
    );
    final parameterTypeFix = fixes.singleWhere(
      (fix) => fix.label == 'Change parameter `value` type to i64',
    );

    expect(_applyFormattingEdits(text, literalFix.edits), '''
fn emitPrice(value: f64) {
  emit value
}
emitPrice(3.0) -> @stdout
''');
    expect(_applyFormattingEdits(text, parameterTypeFix.edits), '''
fn emitPrice(value: i64) {
  emit value
}
emitPrice(3) -> @stdout
''');
  });

  test('project rule provider fixes initializer type mismatch without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text = 'wide: f64 = 3\nwide -> @stdout\n';
    const document = DocumentState(
      documentId: 'initializer-type.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = provider.diagnosticsFor(document).singleWhere(
      (diagnostic) => diagnostic.code == 'initializer-type-mismatch',
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);
    final literalFix = fixes.singleWhere(
      (fix) => fix.label == 'Change initializer to f64 literal',
    );
    final localTypeFix = fixes.singleWhere(
      (fix) => fix.label == 'Change local `wide` type to i64',
    );

    expect(_applyFormattingEdits(text, literalFix.edits), '''
wide: f64 = 3.0
wide -> @stdout
''');
    expect(_applyFormattingEdits(text, localTypeFix.edits), '''
wide: i64 = 3
wide -> @stdout
''');
  });

  test('project rule provider fixes assignment type mismatch without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'rate: f64 = 0.0\n'
        'rate = 1\n'
        'count: i64 = 0\n'
        'count = 1.5\n';
    const document = DocumentState(
      documentId: 'assignment-type.styio',
      text: text,
      revision: 1,
    );
    final diagnostics = provider
        .diagnosticsFor(document)
        .where((diagnostic) => diagnostic.code == 'assignment-type-mismatch');
    final rateMismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.message.contains('`rate`'),
    );
    final countMismatch = diagnostics.singleWhere(
      (diagnostic) => diagnostic.message.contains('`count`'),
    );

    final rateFixes = provider.quickFixesForDiagnostic(
      document,
      rateMismatch,
    );
    final literalFix = rateFixes.singleWhere(
      (fix) => fix.label == 'Change assignment to f64 literal',
    );
    final countTypeFix = provider
        .quickFixesForDiagnostic(document, countMismatch)
        .singleWhere((fix) => fix.label == 'Change local `count` type to f64');

    expect(_applyFormattingEdits(text, literalFix.edits), '''
rate: f64 = 0.0
rate = 1.0
count: i64 = 0
count = 1.5
''');
    expect(countTypeFix.edits.map((edit) => edit.newText), containsAll([
      'f64',
      '0.0',
    ]));
  });

  test('project rule provider fixes binary operator type mismatch without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'price = 12.5\n'
        'ready = true\n'
        'bad = price && ready\n';
    const document = DocumentState(
      documentId: 'binary-operator-type.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = provider.diagnosticsFor(document).singleWhere(
      (diagnostic) => diagnostic.code == 'binary-operator-type-mismatch',
    );

    final fix = provider
        .quickFixesForDiagnostic(document, diagnostic)
        .singleWhere((fix) => fix.label == 'Compare left operand with zero');

    expect(_applyFormattingEdits(text, fix.edits), '''
price = 12.5
ready = true
bad = price != 0.0 && ready
''');
  });

  test('project rule provider fixes unary operator type mismatch without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text = 'price = 12.5\nbad = !price\n';
    const document = DocumentState(
      documentId: 'unary-operator-type.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = provider.diagnosticsFor(document).singleWhere(
      (diagnostic) => diagnostic.code == 'unary-operator-type-mismatch',
    );

    final fix = provider
        .quickFixesForDiagnostic(document, diagnostic)
        .singleWhere((fix) => fix.label == 'Compare operand with zero');

    expect(_applyFormattingEdits(text, fix.edits), '''
price = 12.5
bad = price == 0.0
''');
  });

  test('project rule provider fixes condition type mismatch without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'price = 12.5\n'
        'ready = price > 0\n'
        'when price -> state priced\n'
        'when ready -> state ready\n';
    const document = DocumentState(
      documentId: 'condition-type.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = provider.diagnosticsFor(document).singleWhere(
      (diagnostic) => diagnostic.code == 'condition-type-mismatch',
    );

    final fix = provider
        .quickFixesForDiagnostic(document, diagnostic)
        .singleWhere((fix) => fix.label == 'Compare condition with zero');

    expect(_applyFormattingEdits(text, fix.edits), '''
price = 12.5
ready = price > 0
when price != 0.0 -> state priced
when ready -> state ready
''');
  });

  test('project rule provider fixes function return type mismatch without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'fn price(): f64 {\n'
        '  emit 3\n'
        '}\n';
    const document = DocumentState(
      documentId: 'return-type.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = provider.diagnosticsFor(document).singleWhere(
      (diagnostic) => diagnostic.code == 'return-type-mismatch',
    );

    final fixes = provider.quickFixesForDiagnostic(document, diagnostic);
    final literalFix = fixes.singleWhere(
      (fix) => fix.label == 'Change return expression to f64 literal',
    );
    final returnTypeFix = fixes.singleWhere(
      (fix) => fix.label == 'Change function `price` return type to i64',
    );

    expect(_applyFormattingEdits(text, literalFix.edits), '''
fn price(): f64 {
  emit 3.0
}
''');
    expect(_applyFormattingEdits(text, returnTypeFix.edits), '''
fn price(): i64 {
  emit 3
}
''');
  });

  test('project rule provider inserts missing function return without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'fn price(): f64 {\n'
        '  total = 1.0\n'
        '}\n';
    const document = DocumentState(
      documentId: 'missing-function-return.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = provider.diagnosticsFor(document).singleWhere(
      (diagnostic) => diagnostic.code == 'missing-function-return',
    );

    final fix = provider.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Insert return value');
    expect(_applyFormattingEdits(text, fix.edits), '''
fn price(): f64 {
  total = 1.0
  emit 0.0
}
''');
  });

  test('project rule provider fixes resource and await result types without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        '@prices : f64|..1| := {}\n'
        'load = ||> { <| "ready" }\n'
        'label = "bad"\n'
        'label -> @prices\n'
        '?| load -> result: i64\n';
    const document = DocumentState(
      documentId: 'runtime-type-mismatches.styio',
      text: text,
      revision: 1,
    );
    final diagnostics = provider.diagnosticsFor(document);
    final resource = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'resource-write-type-mismatch',
    );
    final awaitResult = diagnostics.singleWhere(
      (diagnostic) => diagnostic.code == 'await-result-type-mismatch',
    );

    final resourceFix = provider
        .quickFixesForDiagnostic(document, resource)
        .single;
    final awaitFix = provider
        .quickFixesForDiagnostic(document, awaitResult)
        .single;

    expect(resourceFix.label, 'Change resource write value to f64 literal');
    expect(_applyFormattingEdits(text, resourceFix.edits), '''
@prices : f64|..1| := {}
load = ||> { <| "ready" }
label = "bad"
0.0 -> @prices
?| load -> result: i64
''');
    expect(awaitFix.label, 'Change await binding type to string');
    expect(_applyFormattingEdits(text, awaitFix.edits), '''
@prices : f64|..1| := {}
load = ||> { <| "ready" }
label = "bad"
label -> @prices
?| load -> result: string
''');
  });

  test('project rule provider fixes await fallback type without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'load = ||> { <| 42 }\n'
        '?| load -> result: i64 | "missing"\n'
        'result -> @stdout\n';
    const document = DocumentState(
      documentId: 'await-fallback-type.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = provider.diagnosticsFor(document).singleWhere(
      (diagnostic) => diagnostic.code == 'await-fallback-type-mismatch',
    );

    final fix = provider.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Change await fallback to i64 literal');
    expect(_applyFormattingEdits(text, fix.edits), '''
load = ||> { <| 42 }
?| load -> result: i64 | 0
result -> @stdout
''');
  });

  test('project rule provider fixes task return type without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'load = ||> {\n'
        '  <| 42\n'
        '  <| "bad"\n'
        '}\n'
        '?| load -> result: i64 | 0\n'
        'result -> @stdout\n';
    const document = DocumentState(
      documentId: 'task-return-type.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = provider.diagnosticsFor(document).singleWhere(
      (diagnostic) => diagnostic.code == 'task-return-type-mismatch',
    );

    final fix = provider.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Change task return expression to i64 literal');
    expect(_applyFormattingEdits(text, fix.edits), '''
load = ||> {
  <| 42
  <| 0
}
?| load -> result: i64 | 0
result -> @stdout
''');
  });

  test('project rule provider fixes invalid task return expression without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'load = ||> {\n'
        '  count = 1\n'
        '  <| count && true\n'
        '}\n'
        '?| load -> ok: bool\n';
    const invalidExpression = 'count && true';
    final expressionStart = text.indexOf(invalidExpression);
    final document = const DocumentState(
      documentId: 'invalid-task-return-expression.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'invalid-task-return-expression',
      message:
          'Task `load` has a return expression whose type cannot be inferred '
          'for `ok: bool`.',
      range: SourceRange(
        start: expressionStart,
        end: expressionStart + invalidExpression.length,
      ),
    );

    final fix = provider.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Change task return expression to bool literal');
    expect(_applyFormattingEdits(text, fix.edits), '''
load = ||> {
  count = 1
  <| false
}
?| load -> ok: bool
''');
  });

  test('project rule provider inserts missing task return without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'load = ||> {\n'
        '  step = 1\n'
        '}\n'
        '?| load -> result: i64\n';
    final taskStart = text.lastIndexOf('load');
    final document = const DocumentState(
      documentId: 'missing-task-return.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'missing-task-return',
      message: 'Await target `load` does not return a value for `result: i64`.',
      range: SourceRange(start: taskStart, end: taskStart + 'load'.length),
    );

    final fix = provider.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Insert task return value');
    expect(_applyFormattingEdits(text, fix.edits), '''
load = ||> {
  step = 1
  <| 0
}
?| load -> result: i64
''');
  });

  test('project rule provider inserts missing task return expression without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'load = ||> {\n'
        '  <|\n'
        '}\n'
        '?| load -> result: i64\n';
    final markerStart = text.indexOf('<|');
    final document = const DocumentState(
      documentId: 'missing-task-return-value.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'missing-task-return-value',
      message: 'Task `load` returns no value.',
      range: SourceRange(start: markerStart, end: markerStart + '<|'.length),
    );

    final fix = provider.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Insert task return expression');
    expect(_applyFormattingEdits(text, fix.edits), '''
load = ||> {
  <| 0
}
?| load -> result: i64
''');
  });

  test('project rule provider creates unresolved task return value without legacy', () {
    const provider = CurrentProjectDocumentRuleProvider();
    const text =
        'load = ||> {\n'
        '  <| value\n'
        '}\n'
        '?| load -> result: i64\n';
    final valueStart = text.indexOf('value');
    final document = const DocumentState(
      documentId: 'unresolved-task-return-value.styio',
      text: text,
      revision: 1,
    );
    final diagnostic = Diagnostic(
      severity: DiagnosticSeverity.error,
      code: 'unresolved-task-return-value',
      message: 'Task `load` returns unresolved value `value`.',
      range: SourceRange(start: valueStart, end: valueStart + 'value'.length),
    );

    final fix = provider.quickFixesForDiagnostic(document, diagnostic).single;

    expect(fix.label, 'Create task local binding `value`');
    expect(_applyFormattingEdits(text, fix.edits), '''
load = ||> {
  value = 0
  <| value
}
?| load -> result: i64
''');
  });
}

String _applyFormattingEdits(String source, List<FormattingEdit> edits) {
  final sorted = edits.toList()
    ..sort((left, right) => right.range.start.compareTo(left.range.start));
  var result = source;
  for (final edit in sorted) {
    result =
        result.substring(0, edit.range.start) +
        edit.newText +
        result.substring(edit.range.end);
  }
  return result;
}
