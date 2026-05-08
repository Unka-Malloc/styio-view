import 'package:flutter_test/flutter_test.dart';
import 'package:styio_view_app/src/language/language_contract.dart';
import 'package:styio_view_app/src/language/styio_syntax_highlighter.dart';

void main() {
  test('tokenizes target syntax operators and resource forms', () {
    const highlighter = StyioSyntaxHighlighter();
    const source = '''
@prices : f64|..10| := {
  @file("prices.txt") >> #(p) => {
    p -> @prices
  }
}
job = ||> { <| 42 }
?| job -> answer: i64 | 0
''';

    final tokens = highlighter.tokenize(source);
    final lexemes = tokens.map((token) => token.lexeme).toSet();

    expect(
      lexemes,
      containsAll(['@', ':=', '..', '>>', '#', '=>', '||>', '<|', '?|']),
    );
  });

  test('resolves resource and type semantic spans independently', () {
    const highlighter = StyioSyntaxHighlighter();
    const source = '@ma5 : f64|..2| := { value -> @stdout }';
    final tokens = highlighter.tokenize(source);
    final spans = highlighter.resolveSemanticSpans(tokens);

    String semanticText(SemanticSpan span) =>
        source.substring(span.range.start, span.range.end);

    expect(
      spans
          .where((span) => span.kind == SemanticKind.resource)
          .map(semanticText),
      containsAll(['ma5', 'stdout']),
    );
    expect(
      spans
          .where((span) => span.kind == SemanticKind.typeName)
          .map(semanticText),
      contains('f64'),
    );
  });

  test('exposes operator hover copy for language service reuse', () {
    const highlighter = StyioSyntaxHighlighter();

    expect(highlighter.hoverForOperator('||>'), contains('task'));
    expect(highlighter.isOperatorLexeme('?|'), isTrue);
    expect(highlighter.isTypeName('i64'), isTrue);
    expect(highlighter.isStandardResource('stdout'), isTrue);
  });
}
