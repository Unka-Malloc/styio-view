import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/diagnostics/diagnostics.dart';
import 'package:vityo_app/src/view_ide/language/syntax/styio_syntax_highlighter.dart';

void main() {
  test('reports zero divisors for division and remainder operators', () {
    const diagnostics = StyioNumericDiagnostics();
    const highlighter = StyioSyntaxHighlighter();
    const source = '''
total = 42
ratio = total / 0
scaled = total / 0.0
remainder = total % 0
safe = total / 10
safe_remainder = total % 3
label = "total / 0"
// ignored = total % 0
''';

    final results = diagnostics.analyze(
      source: source,
      tokens: highlighter.tokenize(source),
    );

    expect(results, hasLength(3));
    expect(
      results.map((diagnostic) => diagnostic.code),
      everyElement('division-by-zero'),
    );
    expect(
      results.map((diagnostic) => diagnostic.message),
      equals([
        'Styio numeric expression divides by zero.',
        'Styio numeric expression divides by zero.',
        'Styio numeric expression takes remainder by zero.',
      ]),
    );
    expect(
      results.map(
        (diagnostic) =>
            source.substring(diagnostic.range.start, diagnostic.range.end),
      ),
      equals(['0', '0.0', '0']),
    );
  });

  test('reports parenthesized constant zero divisor expressions', () {
    const diagnostics = StyioNumericDiagnostics();
    const highlighter = StyioSyntaxHighlighter();
    const source = '''
total = 42
direct = total / (0)
folded = total / (1 - 1)
nested = total % ((2 * 3) - 6)
safe = total / (2 - 1)
dynamic = total / (scale - scale)
effect = total / (check() - check())
''';

    final results = diagnostics.analyze(
      source: source,
      tokens: highlighter.tokenize(source),
    );

    expect(results, hasLength(3));
    expect(
      results.map(
        (diagnostic) =>
            source.substring(diagnostic.range.start, diagnostic.range.end),
      ),
      equals(['(0)', '(1 - 1)', '((2 * 3) - 6)']),
    );
  });

  test('reports and fixes neutral numeric operations', () {
    const diagnostics = StyioNumericDiagnostics();
    const highlighter = StyioSyntaxHighlighter();
    const source = '''
total = 42
a = total + 0
b = 0 + total
c = total - 0
d = total * 1
e = 1 * total
f = total / 1
g = check() + 0
h = total * 0
''';
    final tokens = highlighter.tokenize(source);
    final results = diagnostics
        .analyze(source: source, tokens: tokens)
        .where(
          (diagnostic) => diagnostic.code == 'simplifiable-numeric-expression',
        )
        .toList();

    expect(results, hasLength(6));
    expect(
      results.map(
        (diagnostic) =>
            source.substring(diagnostic.range.start, diagnostic.range.end),
      ),
      equals([
        'total + 0',
        '0 + total',
        'total - 0',
        'total * 1',
        '1 * total',
        'total / 1',
      ]),
    );
    expect(
      diagnostics
          .quickFixesForDiagnostic(
            source: source,
            tokens: tokens,
            diagnostic: results.first,
          )
          .single
          .edits
          .single
          .newText,
      'total',
    );
  });
}
