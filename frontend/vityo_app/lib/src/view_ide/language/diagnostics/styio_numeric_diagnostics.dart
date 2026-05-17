import '../contract/language_contract.dart';

class StyioNumericDiagnostics {
  const StyioNumericDiagnostics();

  List<Diagnostic> analyze({
    required String source,
    required List<TokenSpan> tokens,
  }) {
    return [
      ..._divisionByZeroDiagnostics(source, tokens),
      ..._simplifiableNumericExpressionDiagnostics(source, tokens),
    ];
  }

  List<DiagnosticQuickFix> quickFixesForDiagnostic({
    required String source,
    required List<TokenSpan> tokens,
    required Diagnostic diagnostic,
  }) {
    if (diagnostic.code != 'simplifiable-numeric-expression') {
      return const <DiagnosticQuickFix>[];
    }
    for (final issue in _simplifiableNumericExpressionIssues(source, tokens)) {
      if (issue.expressionRange.start != diagnostic.range.start ||
          issue.expressionRange.end != diagnostic.range.end) {
        continue;
      }
      return [
        DiagnosticQuickFix(
          label: 'Simplify numeric expression',
          detail: 'Remove a neutral numeric operation.',
          edits: [
            FormattingEdit(
              range: issue.expressionRange,
              newText: issue.replacementText,
            ),
          ],
        ),
      ];
    }
    return const <DiagnosticQuickFix>[];
  }

  List<Diagnostic> _divisionByZeroDiagnostics(
    String source,
    List<TokenSpan> tokens,
  ) {
    final diagnostics = <Diagnostic>[];
    for (var index = 0; index < tokens.length; index += 1) {
      final operatorLexeme = tokens[index].lexeme;
      if (operatorLexeme != '/' && operatorLexeme != '%') {
        continue;
      }
      final denominatorIndex = _nextSignificantIndex(tokens, index + 1);
      if (denominatorIndex == null) {
        continue;
      }
      final denominatorRange = _zeroDenominatorRange(
        source,
        tokens,
        denominatorIndex,
      );
      if (denominatorRange == null) {
        continue;
      }
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'division-by-zero',
          message: operatorLexeme == '/'
              ? 'Styio numeric expression divides by zero.'
              : 'Styio numeric expression takes remainder by zero.',
          range: denominatorRange,
        ),
      );
    }
    return diagnostics;
  }

  List<Diagnostic> _simplifiableNumericExpressionDiagnostics(
    String source,
    List<TokenSpan> tokens,
  ) {
    return [
      for (final issue in _simplifiableNumericExpressionIssues(source, tokens))
        Diagnostic(
          severity: DiagnosticSeverity.hint,
          code: 'simplifiable-numeric-expression',
          message: 'Numeric expression can be simplified.',
          range: issue.expressionRange,
        ),
    ];
  }

  List<_StyioNumericSimplificationIssue> _simplifiableNumericExpressionIssues(
    String source,
    List<TokenSpan> tokens,
  ) {
    final issues = <_StyioNumericSimplificationIssue>[];
    for (var index = 0; index < tokens.length; index += 1) {
      final operatorToken = tokens[index];
      if (!const {'+', '-', '*', '/'}.contains(operatorToken.lexeme)) {
        continue;
      }
      final leftIndex = _previousSignificantIndex(tokens, index - 1);
      final rightIndex = _nextSignificantIndex(tokens, index + 1);
      if (leftIndex == null || rightIndex == null) {
        continue;
      }
      final left = tokens[leftIndex];
      final right = tokens[rightIndex];
      if (!_isStableNumericOperand(left) || !_isStableNumericOperand(right)) {
        continue;
      }
      final expressionRange = SourceRange(
        start: left.range.start,
        end: right.range.end,
      );
      if (source
          .substring(expressionRange.start, expressionRange.end)
          .contains('\n')) {
        continue;
      }
      final replacement = _simplifiedNumericExpressionText(
        left.lexeme,
        operatorToken.lexeme,
        right.lexeme,
      );
      if (replacement == null) {
        continue;
      }
      issues.add(
        _StyioNumericSimplificationIssue(
          expressionRange: expressionRange,
          replacementText: replacement,
        ),
      );
    }
    return issues;
  }

  String? _simplifiedNumericExpressionText(
    String left,
    String operatorLexeme,
    String right,
  ) {
    final leftValue = _numericLiteralValue(left);
    final rightValue = _numericLiteralValue(right);
    return switch (operatorLexeme) {
      '+' when rightValue == 0.0 => left,
      '+' when leftValue == 0.0 => right,
      '-' when rightValue == 0.0 => left,
      '*' when rightValue == 1.0 => left,
      '*' when leftValue == 1.0 => right,
      '/' when rightValue == 1.0 => left,
      _ => null,
    };
  }

  SourceRange? _zeroDenominatorRange(
    String source,
    List<TokenSpan> tokens,
    int denominatorIndex,
  ) {
    final denominator = tokens[denominatorIndex];
    if (_isZeroNumericLiteral(denominator.lexeme)) {
      return denominator.range;
    }
    if (denominator.lexeme != '(') {
      return null;
    }

    final closingIndex = _matchingParenthesisIndex(tokens, denominatorIndex);
    if (closingIndex == null) {
      return null;
    }
    final expressionRange = SourceRange(
      start: denominator.range.start,
      end: tokens[closingIndex].range.end,
    );
    if (source
        .substring(expressionRange.start, expressionRange.end)
        .contains('\n')) {
      return null;
    }
    final value = _constantNumericValue(
      tokens
          .sublist(denominatorIndex + 1, closingIndex)
          .where(_isSignificant)
          .toList(growable: false),
    );
    return value == 0.0 ? expressionRange : null;
  }

  int? _matchingParenthesisIndex(List<TokenSpan> tokens, int openingIndex) {
    var depth = 0;
    for (var index = openingIndex; index < tokens.length; index += 1) {
      final lexeme = tokens[index].lexeme;
      if (lexeme == '(') {
        depth += 1;
      } else if (lexeme == ')') {
        depth -= 1;
        if (depth == 0) {
          return index;
        }
      }
    }
    return null;
  }

  int? _nextSignificantIndex(List<TokenSpan> tokens, int startIndex) {
    for (var index = startIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      return index;
    }
    return null;
  }

  int? _previousSignificantIndex(List<TokenSpan> tokens, int startIndex) {
    for (var index = startIndex; index >= 0; index -= 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      return index;
    }
    return null;
  }

  bool _isSignificant(TokenSpan token) {
    return token.kind != TokenKind.whitespace &&
        token.kind != TokenKind.comment;
  }

  bool _isStableNumericOperand(TokenSpan token) {
    if (token.kind == TokenKind.number) {
      return true;
    }
    return token.kind == TokenKind.identifier &&
        RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(token.lexeme);
  }

  double? _constantNumericValue(List<TokenSpan> tokens) {
    if (tokens.isEmpty) {
      return null;
    }
    return _StyioNumericConstantParser(tokens).parse();
  }

  double? _numericLiteralValue(String lexeme) {
    return double.tryParse(lexeme.replaceAll('_', '').toLowerCase());
  }

  bool _isZeroNumericLiteral(String lexeme) {
    return _numericLiteralValue(lexeme) == 0.0;
  }
}

class _StyioNumericSimplificationIssue {
  const _StyioNumericSimplificationIssue({
    required this.expressionRange,
    required this.replacementText,
  });

  final SourceRange expressionRange;
  final String replacementText;
}

class _StyioNumericConstantParser {
  _StyioNumericConstantParser(this.tokens);

  final List<TokenSpan> tokens;
  int _position = 0;

  double? parse() {
    final value = _parseAdditive();
    if (value == null || _position != tokens.length) {
      return null;
    }
    return value.isFinite ? value : null;
  }

  double? _parseAdditive() {
    final first = _parseMultiplicative();
    if (first == null) {
      return null;
    }
    var value = first;
    while (_matchAny(const {'+', '-'})) {
      final operatorLexeme = _previous.lexeme;
      final right = _parseMultiplicative();
      if (right == null) {
        return null;
      }
      value = operatorLexeme == '+' ? value + right : value - right;
    }
    return value;
  }

  double? _parseMultiplicative() {
    final first = _parseUnary();
    if (first == null) {
      return null;
    }
    var value = first;
    while (_matchAny(const {'*', '/', '%'})) {
      final operatorLexeme = _previous.lexeme;
      final right = _parseUnary();
      if (right == null) {
        return null;
      }
      if ((operatorLexeme == '/' || operatorLexeme == '%') && right == 0.0) {
        return null;
      }
      value = switch (operatorLexeme) {
        '*' => value * right,
        '/' => value / right,
        '%' => value % right,
        _ => value,
      };
    }
    return value;
  }

  double? _parseUnary() {
    if (_matchAny(const {'+', '-'})) {
      final operatorLexeme = _previous.lexeme;
      final value = _parseUnary();
      if (value == null) {
        return null;
      }
      return operatorLexeme == '-' ? -value : value;
    }
    return _parsePrimary();
  }

  double? _parsePrimary() {
    if (_match('(')) {
      final value = _parseAdditive();
      if (value == null || !_match(')')) {
        return null;
      }
      return value;
    }
    if (_isAtEnd) {
      return null;
    }
    final token = _advance();
    if (token.kind != TokenKind.number) {
      return null;
    }
    return double.tryParse(token.lexeme.replaceAll('_', '').toLowerCase());
  }

  bool _match(String lexeme) {
    if (_isAtEnd || tokens[_position].lexeme != lexeme) {
      return false;
    }
    _position += 1;
    return true;
  }

  bool _matchAny(Set<String> lexemes) {
    if (_isAtEnd || !lexemes.contains(tokens[_position].lexeme)) {
      return false;
    }
    _position += 1;
    return true;
  }

  TokenSpan _advance() {
    final token = tokens[_position];
    _position += 1;
    return token;
  }

  TokenSpan get _previous => tokens[_position - 1];
  bool get _isAtEnd => _position >= tokens.length;
}
