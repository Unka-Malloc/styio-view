import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/language/styio_syntax_highlighter.dart';

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

  test('tokenizes block documentation comments as comments', () {
    const highlighter = StyioSyntaxHighlighter();
    const source = '''
/**
 * Blends price and tax inputs.
 */
fn blend(left: f64, right: f64) {
  emit left
}
''';

    final tokens = highlighter.tokenize(source);
    final comment = tokens.singleWhere(
      (token) => token.kind == TokenKind.comment,
    );
    final tokenLexemes = tokens.map((token) => token.lexeme).toList();

    expect(comment.lexeme, startsWith('/**'));
    expect(comment.lexeme, contains('Blends price and tax inputs.'));
    expect(tokenLexemes, containsAll(['fn', 'blend', 'emit']));
  });

  test('tokenizes nested block comments as one comment span', () {
    const highlighter = StyioSyntaxHighlighter();
    const source = '''
/*
 * Outer comment.
 * /* Nested note that should not terminate the outer comment. */
 */
value = 42
''';

    final tokens = highlighter.tokenize(source);
    final comments = tokens
        .where((token) => token.kind == TokenKind.comment)
        .map((token) => token.lexeme)
        .toList();
    final lexemes = tokens.map((token) => token.lexeme).toList();

    expect(comments, hasLength(1));
    expect(comments.single, contains('Nested note'));
    expect(comments.single.trimRight(), endsWith('*/'));
    expect(lexemes, containsAll(['value', '=', '42']));
  });

  test('tokenizes char and extended numeric literals', () {
    const highlighter = StyioSyntaxHighlighter();
    const source = r'''
letter: char = '\n'
price = 1_000.25e-2
mask = 0xFF_A0
bits = 0b1010_1100
octal = 0o755
''';

    final tokens = highlighter.tokenize(source);
    final strings = tokens
        .where((token) => token.kind == TokenKind.string)
        .map((token) => token.lexeme);
    final numbers = tokens
        .where((token) => token.kind == TokenKind.number)
        .map((token) => token.lexeme);

    expect(strings, contains(r"'\n'"));
    expect(
      numbers,
      containsAll(['1_000.25e-2', '0xFF_A0', '0b1010_1100', '0o755']),
    );
  });

  test('keeps unterminated quoted literals on their source line', () {
    const highlighter = StyioSyntaxHighlighter();
    const source = '''
first = 'unterminated
next = 42
text = "also unterminated
value -> @stdout
''';

    final tokens = highlighter.tokenize(source);
    final strings = tokens
        .where((token) => token.kind == TokenKind.string)
        .map((token) => token.lexeme);
    final lexemes = tokens.map((token) => token.lexeme).toList();

    expect(strings, contains("'unterminated"));
    expect(strings, contains('"also unterminated'));
    expect(lexemes, containsAll(['next', '42', 'value', '@', 'stdout']));
  });

  test('resolves resource and type semantic spans independently', () {
    const highlighter = StyioSyntaxHighlighter();
    const source = '@ma5 : f64|..2| := { value: i64 = source }';
    final tokens = highlighter.tokenize(source);
    final spans = highlighter.resolveSemanticSpans(tokens);

    String semanticText(SemanticSpan span) =>
        source.substring(span.range.start, span.range.end);

    expect(
      spans
          .where((span) => span.kind == SemanticKind.resource)
          .map(semanticText),
      contains('ma5'),
    );
    expect(
      spans
          .where((span) => span.kind == SemanticKind.typeName)
          .map(semanticText),
      containsAll(['f64', 'i64']),
    );
    expect(
      spans
          .where((span) => span.kind == SemanticKind.variable)
          .map(semanticText),
      contains('value'),
    );
    expect(
      spans
          .where((span) => span.kind == SemanticKind.variable)
          .map(semanticText),
      isNot(contains('f64')),
    );
    expect(
      spans
          .where((span) => span.kind == SemanticKind.variable)
          .map(semanticText),
      isNot(contains('i64')),
    );
  });

  test('resolves declaration and parameter semantic spans for hash syntax', () {
    const highlighter = StyioSyntaxHighlighter();
    const source = '''
@prices : f64|..10| := {
  @file("prices.txt") >> #(price: f64) => {
    average: f64 = price
    price -> @prices
  }
}
#blend := (left: f64, right: f64) => {
  <| left
}
''';

    final tokens = highlighter.tokenize(source);
    final spans = highlighter.resolveSemanticSpans(tokens);

    Iterable<String> textsFor(SemanticKind kind) => spans
        .where((span) => span.kind == kind)
        .map((span) => source.substring(span.range.start, span.range.end));

    expect(textsFor(SemanticKind.resource), containsAll(['prices', 'file']));
    expect(textsFor(SemanticKind.function), contains('blend'));
    expect(
      textsFor(SemanticKind.parameter),
      containsAll(['price', 'left', 'right']),
    );
    expect(textsFor(SemanticKind.variable), contains('average'));
    expect(textsFor(SemanticKind.variable), isNot(contains('f64')));
    expect(textsFor(SemanticKind.variable), isNot(contains('prices')));
    expect(textsFor(SemanticKind.variable), isNot(contains('blend')));
  });

  test('resolves legacy function parameters without reclassifying types', () {
    const highlighter = StyioSyntaxHighlighter();
    const source = '''
fn normalize(source: f64, scale: f64) {
  let result
  emit source
}
''';

    final tokens = highlighter.tokenize(source);
    final spans = highlighter.resolveSemanticSpans(tokens);

    Iterable<String> textsFor(SemanticKind kind) => spans
        .where((span) => span.kind == kind)
        .map((span) => source.substring(span.range.start, span.range.end));

    expect(textsFor(SemanticKind.function), contains('normalize'));
    expect(textsFor(SemanticKind.parameter), containsAll(['source', 'scale']));
    expect(textsFor(SemanticKind.variable), contains('result'));
    expect(textsFor(SemanticKind.variable), isNot(contains('f64')));
  });

  test('resolves resource topology blocks for folding surfaces', () {
    const highlighter = StyioSyntaxHighlighter();
    const source = '''
@prices : f64|..10| := {
  @file("prices.txt") >> #(price: f64) => {
    price -> @prices
  }
}
job = ||> { <| 42 }
''';

    final tokens = highlighter.tokenize(source);
    final blocks = highlighter.resolveSemanticBlocks(tokens);

    final resourceBlock = blocks.singleWhere(
      (block) => block.label == 'prices',
    );
    final taskBlock = blocks.singleWhere(
      (block) => block.label == 'task_block',
    );

    expect(source.substring(resourceBlock.range.start), startsWith('{\n  @'));
    expect(
      source.substring(resourceBlock.range.start, resourceBlock.range.end),
      contains('price -> @prices'),
    );
    expect(blocks.map((block) => block.label), isNot(contains('file')));
    expect(
      source.substring(taskBlock.range.start, taskBlock.range.end),
      '{ <| 42 }',
    );
  });

  test('exposes operator hover copy for language service reuse', () {
    const highlighter = StyioSyntaxHighlighter();

    for (final lexeme in StyioSyntaxHighlighter.operatorLexemes) {
      expect(
        highlighter.hoverForOperator(lexeme),
        isNot(isNull),
        reason: 'Operator $lexeme should have hover copy.',
      );
    }
    expect(highlighter.hoverForOperator('||>'), contains('task'));
    expect(highlighter.hoverForOperator('=>'), contains('function'));
    expect(highlighter.hoverForOperator('|;'), contains('pipeline'));
    expect(highlighter.hoverForOperator('=='), contains('comparison'));
    expect(highlighter.hoverForOperator('+='), contains('assignment'));
    expect(highlighter.hoverForOperator('...'), contains('dot-run'));
    expect(highlighter.hoverForOperator('>>>'), contains('>>'));
    expect(highlighter.hoverForOperator('^^'), contains('caret-run'));
    expect(highlighter.isOperatorLexeme('?|'), isTrue);
    expect(highlighter.isOperatorLexeme('>>>'), isTrue);
    expect(highlighter.isOperatorLexeme('^^'), isTrue);
    expect(highlighter.isTypeName('i64'), isTrue);
    expect(highlighter.isStandardResource('stdout'), isTrue);
  });
}
