import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/diagnostics/styio_compiler_diagnostics.dart';
import 'package:vityo_app/src/view_ide/language/syntax/styio_syntax_highlighter.dart';

void main() {
  test('reports compiler-style lexical and structural diagnostics', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'compiler-diagnostics.styio',
      text: '''
value = "open
cost = €
fn main(
items = [1, 2
/* open
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final codes = diagnostics.map((diagnostic) => diagnostic.code).toSet();

    expect(
      codes,
      containsAll({
        'unterminated-string',
        'unknown-token',
        'unclosed-parenthesis',
        'unclosed-bracket',
        'unterminated-block-comment',
      }),
    );
    expect(
      diagnostics
          .where(
            (diagnostic) => {
              'unterminated-string',
              'unknown-token',
              'unclosed-parenthesis',
              'unclosed-bracket',
              'unterminated-block-comment',
            }.contains(diagnostic.code),
          )
          .every(
            (diagnostic) => diagnostic.severity == DiagnosticSeverity.error,
          ),
      isTrue,
    );
  });

  test('returns quick fixes for compiler diagnostics', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'compiler-diagnostic-fixes.styio',
      text: '''
value = "open
cost = €
fn main(
items = [1, 2
/* open
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    Diagnostic byCode(String code) {
      return diagnostics.singleWhere((diagnostic) => diagnostic.code == code);
    }

    expect(
      service
          .quickFixesForDiagnostic(document, byCode('unknown-token'))
          .single
          .label,
      'Remove unknown token',
    );
    expect(
      service
          .quickFixesForDiagnostic(document, byCode('unterminated-string'))
          .single
          .edits
          .single
          .newText,
      '"',
    );
    expect(
      service
          .quickFixesForDiagnostic(document, byCode('unclosed-parenthesis'))
          .single
          .edits
          .single
          .newText,
      ')',
    );
    expect(
      service
          .quickFixesForDiagnostic(document, byCode('unclosed-bracket'))
          .single
          .edits
          .single
          .newText,
      ']',
    );
    expect(
      service
          .quickFixesForDiagnostic(
            document,
            byCode('unterminated-block-comment'),
          )
          .single
          .edits
          .single
          .newText,
      '*/',
    );
  });

  test('reports unexpected closing delimiters with removal fixes', () {
    const service = SimpleStyioLanguageService();
    const document = DocumentState(
      documentId: 'unexpected-delimiters.styio',
      text: '''
)
]
}
''',
      revision: 0,
    );

    final diagnostics = service.analyzeDocument(document).diagnostics;
    final codes = diagnostics.map((diagnostic) => diagnostic.code).toSet();

    expect(
      codes,
      containsAll({
        'unexpected-closing-parenthesis',
        'unexpected-closing-bracket',
        'unexpected-closing-brace',
      }),
    );
    expect(
      service
          .quickFixesForDiagnostic(
            document,
            diagnostics.singleWhere(
              (diagnostic) =>
                  diagnostic.code == 'unexpected-closing-parenthesis',
            ),
          )
          .single
          .edits
          .single
          .newText,
      isEmpty,
    );
  });

  test(
    'aggregates resolver and type-check diagnostics in compiler pipeline',
    () {
      const source = '''
fn blend(left: f64, right: f64): f64 {
  emit "bad"
}
price = 1.0
count: i64 = 1.5
value = blend(price)
when price -> state ready
''';
      const highlighter = StyioSyntaxHighlighter();
      const diagnostics = StyioCompilerDiagnostics();
      final tokens = highlighter.tokenize(source);
      final codes = diagnostics
          .analyze(source: source, tokens: tokens)
          .map((diagnostic) => diagnostic.code)
          .toSet();

      expect(
        codes,
        containsAll({
          'return-type-mismatch',
          'initializer-type-mismatch',
          'missing-call-argument',
          'condition-type-mismatch',
        }),
      );
    },
  );

  test('reports typed functions with no value return', () {
    const source = '''
fn missingReturn(value: f64): f64 {
  next = value + 1.0
}

fn sideEffect(value: f64) {
  next = value
}

fn ok(value: f64): f64 {
  emit value
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final missingReturns = diagnostics
        .analyze(source: source, tokens: tokens)
        .where((diagnostic) => diagnostic.code == 'missing-function-return')
        .toList(growable: false);

    expect(missingReturns, hasLength(1));
    expect(missingReturns.single.message, contains('missingReturn'));
  });

  test('reports missing returns for Styio topology return types', () {
    const source = '''
fn movingAverage(): f64|..2| {
  window = 1.0
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final missingReturn = diagnostics
        .analyze(source: source, tokens: tokens)
        .singleWhere(
          (diagnostic) => diagnostic.code == 'missing-function-return',
        );

    expect(missingReturn.message, contains('movingAverage'));
    expect(missingReturn.message, contains('f64|..2|'));
  });

  test('does not treat nested value returns as complete function returns', () {
    const source = '''
fn nestedOnly(flag: bool): f64 {
  when flag -> state branch {
    emit 1.0
  }
}

fn hasFallback(flag: bool): f64 {
  when flag -> state branch {
    emit 1.0
  }
  emit 0.0
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final missingReturns = diagnostics
        .analyze(source: source, tokens: tokens)
        .where((diagnostic) => diagnostic.code == 'missing-function-return')
        .toList(growable: false);

    expect(missingReturns, hasLength(1));
    expect(missingReturns.single.message, contains('nestedOnly'));
  });

  test(
    'does not treat guarded inline returns as complete function returns',
    () {
      const source = '''
fn guarded(flag: bool): f64 {
  when flag -> emit 1.0
  next = 0.0
}
''';
      const highlighter = StyioSyntaxHighlighter();
      const diagnostics = StyioCompilerDiagnostics();
      final tokens = highlighter.tokenize(source);
      final reported = diagnostics.analyze(source: source, tokens: tokens);

      expect(
        reported.where(
          (diagnostic) => diagnostic.code == 'missing-function-return',
        ),
        hasLength(1),
      );
      expect(
        reported.where((diagnostic) => diagnostic.code == 'unreachable-code'),
        isEmpty,
      );
    },
  );

  test('treats constant true guarded inline returns as complete returns', () {
    const source = '''
fn guarded(): f64 {
  when true -> emit 1.0
  next = 0.0
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final reported = diagnostics.analyze(source: source, tokens: tokens);

    expect(
      reported.where(
        (diagnostic) => diagnostic.code == 'missing-function-return',
      ),
      isEmpty,
    );
    expect(
      reported.where((diagnostic) => diagnostic.code == 'unreachable-code'),
      hasLength(1),
    );
  });

  test('treats constant true guarded block returns as complete returns', () {
    const source = '''
fn guarded(): f64 {
  when true -> state ready {
    emit 1.0
  }
  next = 0.0
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final reported = diagnostics.analyze(source: source, tokens: tokens);
    final unreachable = reported
        .where((diagnostic) => diagnostic.code == 'unreachable-code')
        .toList(growable: false);

    expect(
      reported.where(
        (diagnostic) => diagnostic.code == 'missing-function-return',
      ),
      isEmpty,
    );
    expect(unreachable, hasLength(1));
    expect(
      source.substring(
        unreachable.single.range.start,
        unreachable.single.range.end,
      ),
      'next = 0.0',
    );
  });

  test('reports constant false guarded inline returns as unreachable', () {
    const source = '''
fn guarded(): f64 {
  when false -> emit 1.0
  emit 0.0
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final reported = diagnostics.analyze(source: source, tokens: tokens);
    final unreachable = reported
        .where((diagnostic) => diagnostic.code == 'unreachable-code')
        .toList(growable: false);

    expect(
      reported.where(
        (diagnostic) => diagnostic.code == 'missing-function-return',
      ),
      isEmpty,
    );
    expect(unreachable, hasLength(1));
    expect(
      source.substring(
        unreachable.single.range.start,
        unreachable.single.range.end,
      ),
      'emit 1.0',
    );
  });

  test('reports constant false guarded block returns as unreachable', () {
    const source = '''
fn guarded(): f64 {
  when false -> state skipped {
    emit 1.0
  }
  emit 0.0
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final reported = diagnostics.analyze(source: source, tokens: tokens);
    final unreachable = reported
        .where((diagnostic) => diagnostic.code == 'unreachable-code')
        .toList(growable: false);

    expect(
      reported.where(
        (diagnostic) => diagnostic.code == 'missing-function-return',
      ),
      isEmpty,
    );
    expect(unreachable, hasLength(1));
    expect(
      source
          .substring(
            unreachable.single.range.start,
            unreachable.single.range.end,
          )
          .trim(),
      'state skipped {\n    emit 1.0\n  }',
    );
  });

  test('folds parenthesized boolean constants in guarded returns', () {
    const source = '''
fn always(): f64 {
  when !(false) -> emit 1.0
  nextAlways = 0.0
}

fn never(): f64 {
  when ((false)) -> emit 2.0
  emit 0.0
}

fn combinedAlways(): f64 {
  when true && !false -> emit 3.0
  nextCombined = 0.0
}

fn combinedNever(): f64 {
  when (true && false) || false -> emit 4.0
  emit 5.0
}

fn shortCircuitAlways(flag: bool): f64 {
  when true || flag -> emit 6.0
  nextShortCircuit = 0.0
}

fn shortCircuitNever(flag: bool): f64 {
  when false && flag -> emit 7.0
  emit 8.0
}

fn equalityAlways(): f64 {
  when true != false -> emit 9.0
  nextEquality = 0.0
}

fn equalityNever(): f64 {
  when true == false -> emit 10.0
  emit 11.0
}

fn numericAlways(): f64 {
  when 1 < 2 -> emit 12.0
  nextNumeric = 0.0
}

fn numericNever(): f64 {
  when 3 >= 4 -> emit 13.0
  emit 14.0
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final reported = diagnostics.analyze(source: source, tokens: tokens);
    final unreachableTexts = reported
        .where((diagnostic) => diagnostic.code == 'unreachable-code')
        .map(
          (diagnostic) => source
              .substring(diagnostic.range.start, diagnostic.range.end)
              .trim(),
        )
        .toList(growable: false);

    expect(
      reported.where(
        (diagnostic) => diagnostic.code == 'missing-function-return',
      ),
      isEmpty,
    );
    expect(unreachableTexts, hasLength(10));
    expect(
      unreachableTexts,
      containsAll({
        'nextAlways = 0.0',
        'emit 2.0',
        'nextCombined = 0.0',
        'emit 4.0',
        'nextShortCircuit = 0.0',
        'emit 7.0',
        'nextEquality = 0.0',
        'emit 10.0',
        'nextNumeric = 0.0',
        'emit 13.0',
      }),
    );
  });

  test('reports unreachable top-level code after value return', () {
    const source = '''
fn stop(value: f64): f64 {
  emit value
  next = value + 1.0
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final unreachable = diagnostics
        .analyze(source: source, tokens: tokens)
        .where((diagnostic) => diagnostic.code == 'unreachable-code')
        .toList(growable: false);

    expect(unreachable, hasLength(1));
    expect(unreachable.single.severity, DiagnosticSeverity.warning);
    expect(
      source.substring(
        unreachable.single.range.start,
        unreachable.single.range.end,
      ),
      contains('next'),
    );
  });

  test('reports unreachable task code after task return', () {
    const source = '''
load = ||> {
  <| 1
  stale = 2
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final unreachable = diagnostics
        .analyze(source: source, tokens: tokens)
        .where((diagnostic) => diagnostic.code == 'unreachable-code')
        .toList(growable: false);

    expect(unreachable, hasLength(1));
    expect(unreachable.single.severity, DiagnosticSeverity.warning);
    expect(
      unreachable.single.message,
      'Code after a task return is unreachable.',
    );
    expect(
      source.substring(
        unreachable.single.range.start,
        unreachable.single.range.end,
      ),
      contains('stale'),
    );
  });

  test('reports task returns with no value', () {
    const source = '''
load = ||> {
  <|
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final missingReturnValue = diagnostics
        .analyze(source: source, tokens: tokens)
        .singleWhere(
          (diagnostic) => diagnostic.code == 'missing-task-return-value',
        );

    expect(missingReturnValue.severity, DiagnosticSeverity.error);
    expect(missingReturnValue.message, contains('load'));
    expect(
      source.substring(
        missingReturnValue.range.start,
        missingReturnValue.range.end,
      ),
      '<|',
    );
  });

  test('ignores task return markers inside strings and comments', () {
    const source = '''
load = ||> {
  message = "<| string"
  // <| "comment"
  /*
   <|
   <| "block"
  */
  <| 1
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final codes = diagnostics
        .analyze(source: source, tokens: tokens)
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    expect(codes, isNot(contains('missing-task-return-value')));
    expect(codes, isNot(contains('task-return-type-mismatch')));
  });

  test('infers task return types before trailing comments', () {
    const source = '''
load = ||> {
  <| 1 // ok
}
label = ||> {
  <| "http://example.test"
}
?| load -> result: i64 | 0
?| label -> text: string | ""
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final codes = diagnostics
        .analyze(source: source, tokens: tokens)
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    expect(codes, isNot(contains('missing-task-return')));
    expect(codes, isNot(contains('task-return-type-mismatch')));
    expect(codes, isNot(contains('await-result-type-mismatch')));
  });

  test('infers task return types from task local bindings', () {
    const source = '''
load = ||> {
  value = 1
  <| value
}
mixed = ||> {
  first = 1
  second = "bad"
  <| first
  <| second
}
?| load -> result: i64 | 0
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final reported = diagnostics
        .analyze(source: source, tokens: tokens)
        .toList(growable: false);
    final codes = reported.map((diagnostic) => diagnostic.code);
    final mismatch = reported.singleWhere(
      (diagnostic) => diagnostic.code == 'task-return-type-mismatch',
    );

    expect(codes, isNot(contains('missing-task-return')));
    expect(codes, isNot(contains('await-result-type-mismatch')));
    expect(mismatch.message, contains('mixed'));
    expect(
      source.substring(mismatch.range.start, mismatch.range.end),
      'second',
    );
  });

  test('reports conditional task returns when awaited as values', () {
    const source = '''
load = ||> {
  ready = false
  when ready -> <| 1
}
?| load -> result: i64 | 0
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final reported = diagnostics
        .analyze(source: source, tokens: tokens)
        .toList(growable: false);
    final codes = reported.map((diagnostic) => diagnostic.code);
    final conditional = reported.singleWhere(
      (diagnostic) => diagnostic.code == 'conditional-task-return',
    );

    expect(codes, contains('conditional-task-return'));
    expect(codes, isNot(contains('missing-task-return')));
    expect(
      conditional.message,
      'Await target `load` only returns from conditional branches for '
      '`result: i64`.',
    );
  });

  test('reports conditional task return type mismatches', () {
    const source = '''
load = ||> {
  ready = false
  when ready -> <| "bad"
  <| 1
}
?| load -> result: i64 | 0
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final reported = diagnostics
        .analyze(source: source, tokens: tokens)
        .toList(growable: false);
    final mismatch = reported.singleWhere(
      (diagnostic) => diagnostic.code == 'task-return-type-mismatch',
    );
    final codes = reported.map((diagnostic) => diagnostic.code);

    expect(codes, isNot(contains('conditional-task-return')));
    expect(mismatch.message, 'Task `load` returns both `i64` and `string`.');
    expect(source.substring(mismatch.range.start, mismatch.range.end), '"bad"');
  });

  test('infers task return types from binary expressions', () {
    const source = '''
load = ||> {
  count = 41
  <| (count + 1)
}
flag = ||> {
  count = 41
  <| count > 0 && true
}
ratio = ||> {
  value = 10.0
  <| value / 2
}
either = ||> {
  count = 41
  <| (count > 0) || false
}
?| load -> result: i64 | 0
?| flag -> ok: bool | false
?| ratio -> scaled: f64 | 0.0
?| either -> selected: bool | false
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final codes = diagnostics
        .analyze(source: source, tokens: tokens)
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    expect(codes, isNot(contains('missing-task-return')));
    expect(codes, isNot(contains('await-result-type-mismatch')));
    expect(codes, isNot(contains('unresolved-task-return-value')));
  });

  test('does not infer task return types from later task bindings', () {
    const source = '''
load = ||> {
  <| value
  value = 1
}
?| load -> result: i64 | 0
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final codes = diagnostics
        .analyze(source: source, tokens: tokens)
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    expect(codes, contains('unresolved-task-return-value'));
    expect(codes, isNot(contains('missing-task-return')));
    expect(codes, isNot(contains('await-result-type-mismatch')));
  });

  test('reports invalid task return expressions without missing-return noise', () {
    const source = '''
load = ||> {
  count = 1
  <| count && true
}
?| load -> ok: bool | false
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final reported = diagnostics
        .analyze(source: source, tokens: tokens)
        .toList(growable: false);
    final codes = reported.map((diagnostic) => diagnostic.code);
    final invalid = reported.singleWhere(
      (diagnostic) => diagnostic.code == 'invalid-task-return-expression',
    );
    final operatorMismatch = reported.singleWhere(
      (diagnostic) => diagnostic.code == 'binary-operator-type-mismatch',
    );

    expect(codes, isNot(contains('missing-task-return')));
    expect(codes, isNot(contains('unresolved-task-return-value')));
    expect(
      source.substring(invalid.range.start, invalid.range.end),
      'count && true',
    );
    expect(
      operatorMismatch.message,
      'Operator `&&` cannot be applied to `i64` and `bool`.',
    );
  });

  test('reports unary operator mismatches inside task returns', () {
    const source = '''
load = ||> {
  count = 1
  <| !count
}
?| load -> ok: bool | false
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final reported = diagnostics
        .analyze(source: source, tokens: tokens)
        .toList(growable: false);
    final codes = reported.map((diagnostic) => diagnostic.code);
    final operatorMismatch = reported.singleWhere(
      (diagnostic) => diagnostic.code == 'unary-operator-type-mismatch',
    );

    expect(codes, contains('invalid-task-return-expression'));
    expect(codes, isNot(contains('missing-task-return')));
    expect(
      operatorMismatch.message,
      'Operator `!` cannot be applied to `i64`.',
    );
  });

  test('checks task conditions with task-local scopes', () {
    const source = '''
first = ||> {
  count = 1
  <| count
}
second = ||> {
  flag = 1
  when flag -> <| 1
}
third = ||> {
  when count -> <| 1
}
?| first -> result: i64 | 0
?| second -> selected: i64 | 0
?| third -> other: i64 | 0
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final conditionMismatches = diagnostics
        .analyze(source: source, tokens: tokens)
        .where((diagnostic) => diagnostic.code == 'condition-type-mismatch')
        .toList(growable: false);

    expect(conditionMismatches, hasLength(1));
    expect(
      source.substring(
        conditionMismatches.single.range.start,
        conditionMismatches.single.range.end,
      ),
      'flag',
    );
  });

  test('does not leak task local types into top-level operators', () {
    const source = '''
load = ||> {
  price = 1.0
  <| price
}
bad = price && true
other = !price
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final codes = diagnostics
        .analyze(source: source, tokens: tokens)
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    expect(codes, isNot(contains('binary-operator-type-mismatch')));
    expect(codes, isNot(contains('unary-operator-type-mismatch')));
  });

  test('does not leak function local types into top-level diagnostics', () {
    const source = '''
fn source(): f64 {
  price = 1.0
  emit price
}
bad = price && true
other = !price
when price -> state leaked
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final codes = diagnostics
        .analyze(source: source, tokens: tokens)
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    expect(codes, isNot(contains('binary-operator-type-mismatch')));
    expect(codes, isNot(contains('unary-operator-type-mismatch')));
    expect(codes, isNot(contains('condition-type-mismatch')));
  });

  test('reports unreachable code inside nested blocks', () {
    const source = '''
fn stopBranch(flag: bool): f64 {
  when flag -> state branch {
    emit 1.0
    branchLog = 2.0
  }
  emit 0.0
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final unreachable = diagnostics
        .analyze(source: source, tokens: tokens)
        .where((diagnostic) => diagnostic.code == 'unreachable-code')
        .toList(growable: false);

    expect(unreachable, hasLength(1));
    expect(
      source.substring(
        unreachable.single.range.start,
        unreachable.single.range.end,
      ),
      contains('branchLog'),
    );
  });

  test('reports unreachable code inside task blocks', () {
    const source = '''
job = ||> {
  <| 1
  next = 2
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final unreachable = diagnostics
        .analyze(source: source, tokens: tokens)
        .where((diagnostic) => diagnostic.code == 'unreachable-code')
        .toList(growable: false);

    expect(unreachable, hasLength(1));
    expect(
      source.substring(
        unreachable.single.range.start,
        unreachable.single.range.end,
      ),
      contains('next'),
    );
  });

  test('does not duplicate task unreachable diagnostics inside functions', () {
    const source = '''
fn wrapper(): i64 {
  job = ||> {
    <| 1
    next = 2
  }
  emit 0
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final unreachable = diagnostics
        .analyze(source: source, tokens: tokens)
        .where((diagnostic) => diagnostic.code == 'unreachable-code')
        .toList(growable: false);

    expect(unreachable, hasLength(1));
    expect(
      source.substring(
        unreachable.single.range.start,
        unreachable.single.range.end,
      ),
      contains('next'),
    );
  });

  test('reports unreachable top-level code in hash functions', () {
    const source = '''
#stop := (value) => {
  <| value
  next = value
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final unreachable = diagnostics
        .analyze(source: source, tokens: tokens)
        .where((diagnostic) => diagnostic.code == 'unreachable-code')
        .toList(growable: false);

    expect(unreachable, hasLength(1));
    expect(
      source.substring(
        unreachable.single.range.start,
        unreachable.single.range.end,
      ),
      contains('next'),
    );
  });

  test('reports duplicate resource and task declarations', () {
    const source = '''
@prices : f64|..2| := {}
@prices : string|..2| := {}
load = ||> { <| 1 }
load = ||> { <| 2 }
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final codes = diagnostics
        .analyze(source: source, tokens: tokens)
        .map((diagnostic) => diagnostic.code);

    expect(codes, contains('duplicate-resource-declaration'));
    expect(codes, contains('duplicate-task-declaration'));
  });

  test('reports duplicate function parameter declarations', () {
    const source = '''
fn blend(left: f64, left: f64, right: f64): f64 {
  emit right
}

// fn ignored(value: f64, value: f64): f64 { emit value }

#sum := (value, value) => {
  <| value
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final duplicateParameters = diagnostics
        .analyze(source: source, tokens: tokens)
        .where(
          (diagnostic) => diagnostic.code == 'duplicate-parameter-declaration',
        )
        .toList(growable: false);

    expect(duplicateParameters, hasLength(2));
    expect(duplicateParameters.first.message, contains('left'));
    expect(duplicateParameters.last.message, contains('value'));
    expect(
      source.substring(
        duplicateParameters.first.range.start,
        duplicateParameters.first.range.end,
      ),
      'left',
    );
  });

  test('reports duplicate function declarations', () {
    const source = '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}

fn blend(value: f64): f64 {
  emit value
}

/* fn blend(ignored: f64): f64 { emit ignored } */
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final duplicateFunctions = diagnostics
        .analyze(source: source, tokens: tokens)
        .where(
          (diagnostic) => diagnostic.code == 'duplicate-function-declaration',
        )
        .toList(growable: false);

    expect(duplicateFunctions, hasLength(1));
    expect(duplicateFunctions.single.message, contains('blend'));
    expect(
      source.substring(
        duplicateFunctions.single.range.start,
        duplicateFunctions.single.range.end,
      ),
      'blend',
    );
  });

  test('reports duplicate hash function declarations', () {
    const source = '''
#blend := (left, right) => {
  <| left
}

#blend := (value) => {
  <| value
}

fn blend(ignored: f64): f64 {
  emit ignored
}
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final duplicateFunctions = diagnostics
        .analyze(source: source, tokens: tokens)
        .where(
          (diagnostic) => diagnostic.code == 'duplicate-function-declaration',
        )
        .toList(growable: false);

    expect(duplicateFunctions, hasLength(2));
    expect(
      duplicateFunctions.every(
        (diagnostic) => diagnostic.message.contains('blend'),
      ),
      isTrue,
    );
  });

  test('reports resource topology sink diagnostics', () {
    const source = '''
@prices : f64|..2| := {
}
price = 1.0
label = "bad"
price -> @prices
label -> @prices
price -> @missing
price -> @stdin
label -> @stdout
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final codes = diagnostics
        .analyze(source: source, tokens: tokens)
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    expect(codes, contains('resource-write-type-mismatch'));
    expect(codes, contains('unresolved-resource'));
    expect(codes, contains('read-only-resource-write'));
  });

  test('reports task await semantic diagnostics', () {
    const source = '''
job = ||> {
  <| 42
}
bad = ||> {
  <| "done"
}
empty = ||> {
}
mixed = ||> {
  <| 1
  <| "bad"
}
?| job -> answer: i64 | 0
?| bad -> badAnswer: i64 | 0
?| job -> fallbackAnswer: i64 | "missing"
?| empty -> emptyAnswer: i64 | 0
?| missing -> missingAnswer: i64 | 0
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final codes = diagnostics
        .analyze(source: source, tokens: tokens)
        .map((diagnostic) => diagnostic.code)
        .toList(growable: false);

    expect(codes, contains('await-result-type-mismatch'));
    expect(codes, contains('await-fallback-type-mismatch'));
    expect(codes, contains('missing-task-return'));
    expect(codes, contains('task-return-type-mismatch'));
    expect(codes, contains('unresolved-task-await'));
    expect(
      diagnostics
          .analyze(source: source, tokens: tokens)
          .where(
            (diagnostic) => diagnostic.message.contains('answer` expects'),
          ),
      isEmpty,
    );
  });

  test('infers task return types from current-file function calls', () {
    const source = '''
fn makeCount(): i64 {
  emit 42
}
load = ||> {
  <| makeCount()
}
?| load -> result: i64 | 0
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final codes = diagnostics
        .analyze(source: source, tokens: tokens)
        .map((diagnostic) => diagnostic.code);

    expect(codes, isNot(contains('missing-task-return')));
    expect(codes, isNot(contains('await-result-type-mismatch')));
    expect(codes, isNot(contains('unresolved-task-return-value')));
  });

  test('ignores semantic patterns inside strings and comments', () {
    const source = '''
@prices : f64|..2| := {}
price = 1.0

// price -> @missing
/*
fn ghost(value: f64): f64 {
  next = value
}
?| missingTask -> result: i64
*/
label = "price -> @missing and ?| missingTask -> result: i64"
price -> @prices
''';
    const highlighter = StyioSyntaxHighlighter();
    const diagnostics = StyioCompilerDiagnostics();
    final tokens = highlighter.tokenize(source);
    final codes = diagnostics
        .analyze(source: source, tokens: tokens)
        .map((diagnostic) => diagnostic.code);

    expect(codes, isNot(contains('missing-function-return')));
    expect(codes, isNot(contains('unresolved-resource')));
    expect(codes, isNot(contains('unresolved-task-await')));
  });
}
