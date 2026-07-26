import '../contract/language_contract.dart';

typedef StyioTaskReturnControlArrowPredicate =
    bool Function(String source, int offset);

class StyioTaskReturnInference {
  const StyioTaskReturnInference();

  StyioTaskReturnScan scan({
    required String body,
    int bodyStartOffset = 0,
    Map<String, String> functionReturnTypes = const <String, String>{},
    StyioTaskReturnControlArrowPredicate? hasControlArrowBeforeOnLine,
  }) {
    final values = <StyioTaskReturnValue>[];
    final missingValueRanges = <SourceRange>[];
    final conditionalValueRanges = <SourceRange>[];
    final conditionalValues = <StyioTaskReturnValue>[];
    final unresolvedValues = <StyioTaskReturnExpression>[];
    final invalidExpressions = <StyioTaskReturnExpression>[];
    final isControlArrow =
        hasControlArrowBeforeOnLine ?? _hasControlArrowBeforeOnLine;
    var index = 0;
    while (index < body.length) {
      final ignoredEnd = _ignoredTextEndAt(body, index);
      if (ignoredEnd != null) {
        index = ignoredEnd;
        continue;
      }
      if (!body.startsWith('<|', index)) {
        index += 1;
        continue;
      }
      if (isControlArrow(body, index)) {
        conditionalValueRanges.add(
          SourceRange(
            start: bodyStartOffset + index,
            end: bodyStartOffset + index + 2,
          ),
        );
        final expressionStart = index + 2;
        final lineEnd = _lineEndOffset(body, index);
        final closingBrace = body.indexOf('}', expressionStart);
        final expressionEnd = closingBrace >= 0 && closingBrace < lineEnd
            ? closingBrace
            : lineEnd;
        final rawExpression = body.substring(expressionStart, expressionEnd);
        final leadingWhitespace =
            rawExpression.length - rawExpression.trimLeft().length;
        final expression = _taskReturnExpressionBeforeComment(
          rawExpression.trimLeft(),
        ).trimRight();
        if (expression.isEmpty) {
          missingValueRanges.add(
            SourceRange(
              start: bodyStartOffset + index,
              end: bodyStartOffset + index + 2,
            ),
          );
          index = expressionEnd;
          continue;
        }
        final localTypes = localValueTypes(
          body.substring(0, index),
          functionReturnTypes: functionReturnTypes,
        );
        final type = inferExpressionType(
          expression,
          localTypes,
          functionReturnTypes: functionReturnTypes,
        );
        final start = bodyStartOffset + expressionStart + leadingWhitespace;
        final range = SourceRange(start: start, end: start + expression.length);
        if (type == null) {
          if (_isSimpleIdentifier(expression)) {
            unresolvedValues.add(
              StyioTaskReturnExpression(expression: expression, range: range),
            );
          } else {
            invalidExpressions.add(
              StyioTaskReturnExpression(expression: expression, range: range),
            );
          }
          index = expressionEnd;
          continue;
        }
        conditionalValues.add(StyioTaskReturnValue(type: type, range: range));
        index = expressionEnd;
        continue;
      }

      final expressionStart = index + 2;
      final lineEnd = _lineEndOffset(body, index);
      final closingBrace = body.indexOf('}', expressionStart);
      final expressionEnd = closingBrace >= 0 && closingBrace < lineEnd
          ? closingBrace
          : lineEnd;
      final rawExpression = body.substring(expressionStart, expressionEnd);
      final leadingWhitespace =
          rawExpression.length - rawExpression.trimLeft().length;
      final expression = _taskReturnExpressionBeforeComment(
        rawExpression.trimLeft(),
      ).trimRight();
      if (expression.isEmpty) {
        missingValueRanges.add(
          SourceRange(
            start: bodyStartOffset + index,
            end: bodyStartOffset + index + 2,
          ),
        );
        index = expressionEnd;
        continue;
      }
      final localTypes = localValueTypes(
        body.substring(0, index),
        functionReturnTypes: functionReturnTypes,
      );
      final type = inferExpressionType(
        expression,
        localTypes,
        functionReturnTypes: functionReturnTypes,
      );
      final start = bodyStartOffset + expressionStart + leadingWhitespace;
      final range = SourceRange(start: start, end: start + expression.length);
      if (type == null) {
        if (_isSimpleIdentifier(expression)) {
          unresolvedValues.add(
            StyioTaskReturnExpression(expression: expression, range: range),
          );
        } else {
          invalidExpressions.add(
            StyioTaskReturnExpression(expression: expression, range: range),
          );
        }
        index = expressionEnd;
        continue;
      }
      values.add(StyioTaskReturnValue(type: type, range: range));
      index = expressionEnd;
    }
    return StyioTaskReturnScan(
      values: values,
      missingValueRanges: missingValueRanges,
      conditionalValueRanges: conditionalValueRanges,
      conditionalValues: conditionalValues,
      unresolvedValues: unresolvedValues,
      invalidExpressions: invalidExpressions,
    );
  }

  String? firstReturnType({
    required String body,
    Map<String, String> functionReturnTypes = const <String, String>{},
    StyioTaskReturnControlArrowPredicate? hasControlArrowBeforeOnLine,
  }) {
    final result = scan(
      body: body,
      functionReturnTypes: functionReturnTypes,
      hasControlArrowBeforeOnLine: hasControlArrowBeforeOnLine,
    );
    return result.values.isEmpty ? null : result.values.first.type;
  }

  Map<String, String> localValueTypes(
    String source, {
    Map<String, String> functionReturnTypes = const <String, String>{},
  }) {
    final types = <String, String>{};
    for (final line in source.split('\n')) {
      final match = RegExp(
        r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*([A-Za-z][A-Za-z0-9_]*))?\s*=\s*(.+)$',
      ).firstMatch(line);
      if (match == null) {
        continue;
      }
      final name = match.group(1)!;
      final explicitType = match.group(2);
      final initializer = match.group(3) ?? '';
      final inferred =
          explicitType ??
          inferExpressionType(
            initializer,
            types,
            functionReturnTypes: functionReturnTypes,
          );
      if (inferred != null) {
        types[name] = inferred;
      }
    }
    return types;
  }

  String? inferExpressionType(
    String expression,
    Map<String, String> localTypes, {
    Map<String, String> functionReturnTypes = const <String, String>{},
  }) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    final unparenthesized = _stripBalancedOuterParentheses(trimmed);
    if (unparenthesized != trimmed) {
      return inferExpressionType(
        unparenthesized,
        localTypes,
        functionReturnTypes: functionReturnTypes,
      );
    }
    if (trimmed.startsWith('!')) {
      final operandType = inferExpressionType(
        trimmed.substring(1),
        localTypes,
        functionReturnTypes: functionReturnTypes,
      );
      return operandType == 'bool' ? 'bool' : null;
    }
    if (trimmed.startsWith('-')) {
      final operandType = inferExpressionType(
        trimmed.substring(1),
        localTypes,
        functionReturnTypes: functionReturnTypes,
      );
      return _isNumericType(operandType) ? operandType : null;
    }
    if (trimmed == 'true' || trimmed == 'false') {
      return 'bool';
    }
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      return 'string';
    }
    if (RegExp(r'^[0-9][0-9_]*$').hasMatch(trimmed)) {
      return 'i64';
    }
    if (RegExp(r'^[0-9][0-9_]*\.[0-9][0-9_]*$').hasMatch(trimmed)) {
      return 'f64';
    }
    final binaryExpressionType = _inferBinaryExpressionType(
      trimmed,
      localTypes,
      functionReturnTypes: functionReturnTypes,
    );
    if (binaryExpressionType != null) {
      return binaryExpressionType;
    }
    final functionReturnType = _inferFunctionCallReturnType(
      trimmed,
      functionReturnTypes,
    );
    if (functionReturnType != null) {
      return functionReturnType;
    }
    return localTypes[trimmed];
  }

  String? _inferBinaryExpressionType(
    String expression,
    Map<String, String> localTypes, {
    Map<String, String> functionReturnTypes = const <String, String>{},
  }) {
    for (final operator in const ['||', '&&']) {
      final index = _topLevelExpressionOperatorIndex(expression, operator);
      if (index == null) {
        continue;
      }
      final left = inferExpressionType(
        expression.substring(0, index),
        localTypes,
        functionReturnTypes: functionReturnTypes,
      );
      final right = inferExpressionType(
        expression.substring(index + operator.length),
        localTypes,
        functionReturnTypes: functionReturnTypes,
      );
      return left == 'bool' && right == 'bool' ? 'bool' : null;
    }

    for (final operator in const ['==', '!=', '>=', '<=', '>', '<']) {
      final index = _topLevelExpressionOperatorIndex(expression, operator);
      if (index == null) {
        continue;
      }
      final left = inferExpressionType(
        expression.substring(0, index),
        localTypes,
        functionReturnTypes: functionReturnTypes,
      );
      final right = inferExpressionType(
        expression.substring(index + operator.length),
        localTypes,
        functionReturnTypes: functionReturnTypes,
      );
      return left == null || right == null ? null : 'bool';
    }

    for (final operator in const ['+', '-', '*', '/', '%']) {
      final index = _topLevelExpressionOperatorIndex(expression, operator);
      if (index == null) {
        continue;
      }
      final left = inferExpressionType(
        expression.substring(0, index),
        localTypes,
        functionReturnTypes: functionReturnTypes,
      );
      final right = inferExpressionType(
        expression.substring(index + operator.length),
        localTypes,
        functionReturnTypes: functionReturnTypes,
      );
      if (!_isNumericType(left) || !_isNumericType(right)) {
        return null;
      }
      if (left == 'f64' || right == 'f64') {
        return 'f64';
      }
      return 'i64';
    }
    return null;
  }

  bool _isNumericType(String? type) {
    return type == 'i64' || type == 'f64';
  }

  int? _topLevelExpressionOperatorIndex(String text, String operator) {
    var depth = 0;
    var index = 0;
    while (index <= text.length - operator.length) {
      final char = text[index];
      if (char == '"' || char == "'") {
        index = _quotedTextEnd(text, index);
        continue;
      }
      if (char == '(' || char == '[' || char == '{') {
        depth += 1;
      } else if (char == ')' || char == ']' || char == '}') {
        if (depth > 0) {
          depth -= 1;
        }
      } else if (depth == 0 &&
          text.startsWith(operator, index) &&
          index > 0) {
        return index;
      }
      index += 1;
    }
    return null;
  }

  String _taskReturnExpressionBeforeComment(String expression) {
    var index = 0;
    String? quote;
    while (index < expression.length) {
      final char = expression[index];
      if (quote != null) {
        if (char == r'\' && index + 1 < expression.length) {
          index += 2;
          continue;
        }
        if (char == quote) {
          quote = null;
        }
        index += 1;
        continue;
      }
      if (char == '"' || char == "'") {
        quote = char;
        index += 1;
        continue;
      }
      if (expression.startsWith('//', index) ||
          expression.startsWith('/*', index)) {
        return expression.substring(0, index);
      }
      index += 1;
    }
    return expression;
  }

  String? _inferFunctionCallReturnType(
    String expression,
    Map<String, String> functionReturnTypes,
  ) {
    final match = RegExp(
      r'^([A-Za-z_][A-Za-z0-9_]*)\s*\(',
    ).firstMatch(expression.trim());
    if (match == null) {
      return null;
    }
    return functionReturnTypes[match.group(1)!];
  }

  bool _isSimpleIdentifier(String text) {
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(text);
  }

  bool _hasControlArrowBeforeOnLine(String source, int offset) {
    final lineStart = source.lastIndexOf('\n', offset - 1) + 1;
    var depth = 0;
    var index = lineStart;
    while (index < offset) {
      final ignoredEnd = _ignoredTextEndAt(source, index);
      if (ignoredEnd != null) {
        if (ignoredEnd > offset) {
          return false;
        }
        index = ignoredEnd;
        continue;
      }
      final char = source[index];
      if (char == '(' || char == '[' || char == '{') {
        depth += 1;
      } else if (char == ')' || char == ']' || char == '}') {
        if (depth > 0) {
          depth -= 1;
        }
      } else if (depth == 0 && source.startsWith('->', index)) {
        return !_isAlwaysTrueWhenGuard(source.substring(lineStart, index));
      }
      index += 1;
    }
    return false;
  }

  bool _isAlwaysTrueWhenGuard(String prefix) {
    final condition = _whenGuardCondition(prefix);
    if (condition == null) {
      return false;
    }
    return _constantBooleanConditionValue(condition) == true;
  }

  String? _whenGuardCondition(String prefix) {
    final trimmed = prefix.trim();
    if (!trimmed.startsWith('when ')) {
      return null;
    }
    return trimmed.substring(5).replaceAll(RegExp(r'\s+'), '');
  }

  bool? _constantBooleanConditionValue(String text) {
    if (text.isEmpty) {
      return null;
    }
    final remaining = _stripBalancedOuterParentheses(text);
    final orIndex = _topLevelBooleanOperatorIndex(remaining, '||');
    if (orIndex != null) {
      final left = _constantBooleanConditionValue(
        remaining.substring(0, orIndex),
      );
      final right = _constantBooleanConditionValue(
        remaining.substring(orIndex + 2),
      );
      if (left == true || right == true) {
        return true;
      }
      if (left == false && right == false) {
        return false;
      }
      return null;
    }

    final andIndex = _topLevelBooleanOperatorIndex(remaining, '&&');
    if (andIndex != null) {
      final left = _constantBooleanConditionValue(
        remaining.substring(0, andIndex),
      );
      final right = _constantBooleanConditionValue(
        remaining.substring(andIndex + 2),
      );
      if (left == false || right == false) {
        return false;
      }
      if (left == true && right == true) {
        return true;
      }
      return null;
    }

    final equalsIndex = _topLevelBooleanOperatorIndex(remaining, '==');
    if (equalsIndex != null) {
      final left = _constantBooleanConditionValue(
        remaining.substring(0, equalsIndex),
      );
      final right = _constantBooleanConditionValue(
        remaining.substring(equalsIndex + 2),
      );
      if (left != null && right != null) {
        return left == right;
      }
      final numericLeft = _constantNumericValue(remaining.substring(0, equalsIndex));
      final numericRight = _constantNumericValue(
        remaining.substring(equalsIndex + 2),
      );
      if (numericLeft != null && numericRight != null) {
        return numericLeft == numericRight;
      }
      return null;
    }

    final notEqualsIndex = _topLevelBooleanOperatorIndex(remaining, '!=');
    if (notEqualsIndex != null) {
      final left = _constantBooleanConditionValue(
        remaining.substring(0, notEqualsIndex),
      );
      final right = _constantBooleanConditionValue(
        remaining.substring(notEqualsIndex + 2),
      );
      if (left != null && right != null) {
        return left != right;
      }
      final numericLeft = _constantNumericValue(
        remaining.substring(0, notEqualsIndex),
      );
      final numericRight = _constantNumericValue(
        remaining.substring(notEqualsIndex + 2),
      );
      if (numericLeft != null && numericRight != null) {
        return numericLeft != numericRight;
      }
      return null;
    }

    final greaterThanOrEqualsIndex = _topLevelBooleanOperatorIndex(
      remaining,
      '>=',
    );
    if (greaterThanOrEqualsIndex != null) {
      final left = _constantNumericValue(
        remaining.substring(0, greaterThanOrEqualsIndex),
      );
      final right = _constantNumericValue(
        remaining.substring(greaterThanOrEqualsIndex + 2),
      );
      if (left != null && right != null) {
        return left >= right;
      }
      return null;
    }

    final lessThanOrEqualsIndex = _topLevelBooleanOperatorIndex(
      remaining,
      '<=',
    );
    if (lessThanOrEqualsIndex != null) {
      final left = _constantNumericValue(
        remaining.substring(0, lessThanOrEqualsIndex),
      );
      final right = _constantNumericValue(
        remaining.substring(lessThanOrEqualsIndex + 2),
      );
      if (left != null && right != null) {
        return left <= right;
      }
      return null;
    }

    final greaterThanIndex = _topLevelBooleanOperatorIndex(remaining, '>');
    if (greaterThanIndex != null) {
      final left = _constantNumericValue(remaining.substring(0, greaterThanIndex));
      final right = _constantNumericValue(
        remaining.substring(greaterThanIndex + 1),
      );
      if (left != null && right != null) {
        return left > right;
      }
      return null;
    }

    final lessThanIndex = _topLevelBooleanOperatorIndex(remaining, '<');
    if (lessThanIndex != null) {
      final left = _constantNumericValue(remaining.substring(0, lessThanIndex));
      final right = _constantNumericValue(remaining.substring(lessThanIndex + 1));
      if (left != null && right != null) {
        return left < right;
      }
      return null;
    }

    if (remaining.startsWith('!')) {
      final value = _constantBooleanConditionValue(remaining.substring(1));
      return value == null ? null : !value;
    }

    if (remaining == 'true') {
      return true;
    }
    if (remaining == 'false') {
      return false;
    }
    return null;
  }

  double? _constantNumericValue(String text) {
    final remaining = _stripBalancedOuterParentheses(text);
    if (remaining.isEmpty) {
      return null;
    }
    final normalized = remaining.replaceAll('_', '');
    if (!RegExp(r'^-?[0-9]+(?:\.[0-9]+)?$').hasMatch(normalized)) {
      return null;
    }
    return double.tryParse(normalized);
  }

  String _stripBalancedOuterParentheses(String text) {
    var remaining = text;
    while (_hasBalancedOuterParentheses(remaining)) {
      remaining = remaining.substring(1, remaining.length - 1);
    }
    return remaining;
  }

  int? _topLevelBooleanOperatorIndex(String text, String operator) {
    var depth = 0;
    var index = 0;
    while (index <= text.length - operator.length) {
      final char = text[index];
      if (char == '(') {
        depth += 1;
      } else if (char == ')') {
        if (depth > 0) {
          depth -= 1;
        }
      } else if (depth == 0 && text.startsWith(operator, index)) {
        return index;
      }
      index += 1;
    }
    return null;
  }

  bool _hasBalancedOuterParentheses(String text) {
    if (!text.startsWith('(') || !text.endsWith(')')) {
      return false;
    }
    var depth = 0;
    for (var index = 0; index < text.length; index += 1) {
      final char = text[index];
      if (char == '(') {
        depth += 1;
      } else if (char == ')') {
        depth -= 1;
        if (depth < 0 || (depth == 0 && index < text.length - 1)) {
          return false;
        }
      }
    }
    return depth == 0;
  }

  int _lineEndOffset(String source, int offset) {
    final newline = source.indexOf('\n', offset);
    return newline < 0 ? source.length : newline;
  }

  int? _ignoredTextEndAt(String source, int index) {
    if (index < 0 || index >= source.length) {
      return null;
    }
    final char = source[index];
    if (char == '"' || char == "'") {
      return _quotedTextEnd(source, index);
    }
    if (char == '/' && index + 1 < source.length) {
      final next = source[index + 1];
      if (next == '/') {
        final newline = source.indexOf('\n', index + 2);
        return newline < 0 ? source.length : newline;
      }
      if (next == '*') {
        final closing = source.indexOf('*/', index + 2);
        return closing < 0 ? source.length : closing + 2;
      }
    }
    return null;
  }

  int _quotedTextEnd(String source, int openingQuote) {
    final quote = source[openingQuote];
    var index = openingQuote + 1;
    while (index < source.length) {
      if (source[index] == '\\' && index + 1 < source.length) {
        index += 2;
        continue;
      }
      if (source[index] == quote) {
        return index + 1;
      }
      index += 1;
    }
    return source.length;
  }
}

class StyioTaskReturnScan {
  const StyioTaskReturnScan({
    required this.values,
    required this.missingValueRanges,
    required this.conditionalValueRanges,
    required this.conditionalValues,
    required this.unresolvedValues,
    required this.invalidExpressions,
  });

  final List<StyioTaskReturnValue> values;
  final List<SourceRange> missingValueRanges;
  final List<SourceRange> conditionalValueRanges;
  final List<StyioTaskReturnValue> conditionalValues;
  final List<StyioTaskReturnExpression> unresolvedValues;
  final List<StyioTaskReturnExpression> invalidExpressions;
}

class StyioTaskReturnValue {
  const StyioTaskReturnValue({required this.type, required this.range});

  final String type;
  final SourceRange range;
}

class StyioTaskReturnExpression {
  const StyioTaskReturnExpression({
    required this.expression,
    required this.range,
  });

  final String expression;
  final SourceRange range;
}
