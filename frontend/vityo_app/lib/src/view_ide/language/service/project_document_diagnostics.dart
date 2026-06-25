import '../../editor/document_state.dart';
import '../diagnostics/diagnostic_range_index.dart';
import '../contract/language_contract.dart';
import '../diagnostics/styio_compiler_diagnostics.dart';
import '../diagnostics/styio_numeric_diagnostics.dart';
import '../semantic/styio_symbol_index.dart';
import '../syntax/styio_syntax_highlighter.dart';

class ProjectDocumentDiagnostics {
  const ProjectDocumentDiagnostics({
    StyioSyntaxHighlighter syntaxHighlighter = const StyioSyntaxHighlighter(),
    StyioCompilerDiagnostics compilerDiagnostics =
        const StyioCompilerDiagnostics(),
    StyioNumericDiagnostics numericDiagnostics =
        const StyioNumericDiagnostics(),
    StyioSymbolIndex symbolIndex = const StyioSymbolIndex(),
  }) : _syntaxHighlighter = syntaxHighlighter,
       _compilerDiagnostics = compilerDiagnostics,
       _numericDiagnostics = numericDiagnostics,
       _symbolIndex = symbolIndex;

  final StyioSyntaxHighlighter _syntaxHighlighter;
  final StyioCompilerDiagnostics _compilerDiagnostics;
  final StyioNumericDiagnostics _numericDiagnostics;
  final StyioSymbolIndex _symbolIndex;

  static const Set<String> _implicitIdentifierAllowlist = {
    'condition',
    'normalize',
    'sink',
    'source',
    'value',
  };

  List<Diagnostic> analyze(DocumentState document) {
    final tokens = _syntaxHighlighter.tokenize(document.text);
    final diagnostics = <Diagnostic>[
      ..._compilerDiagnostics.analyze(source: document.text, tokens: tokens),
      ..._missingAssignmentDiagnostics(document.text, tokens),
      ..._importDiagnostics(document.text),
      ..._unreachableCodeDiagnostics(document.text),
      ..._redundantTypeAnnotationDiagnostics(document.text),
      ..._expressionDiagnostics(document.text),
      ..._numericDiagnostics.analyze(
        source: document.text,
        tokens: tokens,
      ),
    ];
    final diagnosticGate = DiagnosticRangeGate(
      diagnostics,
      revision: document.revision,
    );
    for (final diagnostic in _symbolDiagnostics(document.text, tokens)) {
      if (diagnostic.code == 'unresolved-reference') {
        diagnosticGate.add(diagnostic);
        continue;
      }
      diagnosticGate.addIfNoOverlap(diagnostic);
    }
    diagnosticGate.flush();
    return _dedupeDiagnostics(diagnostics);
  }

  List<Diagnostic> _missingAssignmentDiagnostics(
    String source,
    List<TokenSpan> tokens,
  ) {
    final diagnostics = <Diagnostic>[];
    for (final token in tokens) {
      if (token.kind != TokenKind.keyword || token.lexeme != 'let') {
        continue;
      }
      final lineRange = _lineRange(source, token.range.start);
      final lineText = source.substring(lineRange.start, lineRange.end);
      if (lineText.contains('=')) {
        continue;
      }
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'missing-assignment',
          message: 'Variable declaration is missing `=`.',
          range: lineRange,
        ),
      );
    }
    return diagnostics;
  }

  List<Diagnostic> _importDiagnostics(String source) {
    final imports = _importDeclarations(source);
    if (imports.isEmpty) {
      return const <Diagnostic>[];
    }

    final diagnostics = <Diagnostic>[];
    final seen = <String>{};
    for (final import in imports) {
      if (seen.add(import.path)) {
        continue;
      }
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'duplicate-import',
          message: 'Import `${import.path}` is already declared.',
          range: import.range,
        ),
      );
    }

    final optimizedPaths = imports
        .map((import) => import.path)
        .toSet()
        .toList(growable: false)
      ..sort();
    final currentPaths = imports
        .map((import) => import.path)
        .toList(growable: false);
    if (!_sameStringList(currentPaths, optimizedPaths)) {
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.hint,
          code: 'import-block-not-optimized',
          message: 'Top-level Styio imports can be optimized.',
          range: SourceRange(
            start: imports.first.range.start,
            end: imports.last.range.end,
          ),
        ),
      );
    }

    return diagnostics;
  }

  List<_ImportDeclaration> _importDeclarations(String source) {
    final imports = <_ImportDeclaration>[];
    var lineStart = 0;
    while (lineStart < source.length) {
      final newline = source.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? source.length : newline;
      final line = source.substring(lineStart, lineEnd);
      final path = _importPathForLine(line);
      if (path != null) {
        imports.add(
          _ImportDeclaration(
            path: path,
            range: SourceRange(start: lineStart, end: lineEnd),
          ),
        );
      }
      if (newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }
    return imports;
  }

  String? _importPathForLine(String line) {
    final trimmed = line.trim();
    if (!trimmed.startsWith('@import')) {
      return null;
    }
    final open = trimmed.indexOf('{');
    final close = trimmed.lastIndexOf('}');
    if (open < 0 || close <= open) {
      return null;
    }
    final path = trimmed.substring(open + 1, close).trim();
    return path.isEmpty ? null : path;
  }

  bool _sameStringList(List<String> left, List<String> right) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (left[index] != right[index]) {
        return false;
      }
    }
    return true;
  }

  List<Diagnostic> _unreachableCodeDiagnostics(String source) {
    final diagnostics = <Diagnostic>[];
    var lineStart = 0;
    var blockDepth = 0;
    int? unreachableDepth;

    while (lineStart < source.length) {
      final newline = source.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? source.length : newline;
      final line = source.substring(lineStart, lineEnd);
      final trimmed = line.trim();
      final lineDepth = blockDepth;

      if (unreachableDepth != null &&
          blockDepth >= unreachableDepth &&
          trimmed.isNotEmpty &&
          !trimmed.startsWith('}') &&
          !trimmed.startsWith('//')) {
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.hint,
            code: 'unreachable-code',
            message: 'Code is unreachable.',
            range: SourceRange(start: lineStart, end: lineEnd),
          ),
        );
      }

      blockDepth += _countChar(line, '{');
      blockDepth -= _countChar(line, '}');
      if (blockDepth < 0) {
        blockDepth = 0;
      }
      if ((trimmed.contains('<|') || trimmed.contains('|<|')) &&
          blockDepth > 0 &&
          blockDepth >= lineDepth) {
        unreachableDepth = blockDepth;
      }
      if (unreachableDepth != null && blockDepth < unreachableDepth) {
        unreachableDepth = null;
      }

      if (newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }

    return diagnostics;
  }

  int _countChar(String value, String char) {
    var count = 0;
    for (var index = 0; index < value.length; index += 1) {
      if (value[index] == char) {
        count += 1;
      }
    }
    return count;
  }

  List<Diagnostic> _symbolDiagnostics(String source, List<TokenSpan> tokens) {
    final snapshot = _symbolIndex.build(tokens);
    final diagnostics = <Diagnostic>[];
    final duplicateKeys = <String>{};
    final firstByKindAndName = <String, DocumentSymbol>{};

    for (final symbol in snapshot.symbols) {
      final key = '${symbol.kind.name}:${symbol.name}';
      final original = firstByKindAndName[key];
      if (original == null) {
        firstByKindAndName[key] = symbol;
        continue;
      }
      duplicateKeys.add(key);
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: switch (symbol.kind) {
            SymbolKind.resource => 'duplicate-resource-declaration',
            SymbolKind.task => 'duplicate-task-declaration',
            SymbolKind.function => 'duplicate-function-declaration',
            SymbolKind.parameter => 'duplicate-parameter-declaration',
            _ => 'duplicate-declaration',
          },
          message:
              'Name `${symbol.name}` already has a current-file '
              '${original.kind.name} declaration.',
          range: symbol.nameRange,
        ),
      );
    }

    diagnostics.addAll(_parameterShadowingDiagnostics(snapshot));
    diagnostics.addAll(
      _unusedParameterDiagnostics(
        snapshot,
        duplicateKeys: duplicateKeys,
      ),
    );
    diagnostics.addAll(
      _unusedLocalSymbolDiagnostics(
        snapshot,
        duplicateKeys: duplicateKeys,
      ),
    );
    diagnostics.addAll(
      _readOnlyResourceWriteDiagnostics(source, snapshot, tokens),
    );
    diagnostics.addAll(_unresolvedReferenceDiagnostics(snapshot, tokens));
    return diagnostics;
  }

  List<Diagnostic> _parameterShadowingDiagnostics(
    StyioSymbolSnapshot snapshot,
  ) {
    final parameterNames = {
      for (final symbol in snapshot.symbols)
        if (symbol.kind == SymbolKind.parameter) symbol.name,
    };
    return [
      for (final symbol in snapshot.symbols)
        if (symbol.kind == SymbolKind.variable &&
            parameterNames.contains(symbol.name))
          Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'parameter-shadowing',
            message:
                'Local declaration `${symbol.name}` shadows a function parameter.',
            range: symbol.nameRange,
          ),
    ];
  }

  List<Diagnostic> _unusedParameterDiagnostics(
    StyioSymbolSnapshot snapshot, {
    required Set<String> duplicateKeys,
  }) {
    return [
      for (final symbol in snapshot.symbols)
        if (symbol.kind == SymbolKind.parameter &&
            !duplicateKeys.contains('${symbol.kind.name}:${symbol.name}') &&
            !snapshot
                .referencesForTarget(symbol.nameRange)
                .any((reference) => !reference.isDeclaration))
          Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'unused-parameter',
            message: _unusedParameterMessage(snapshot, symbol),
            range: symbol.nameRange,
          ),
    ];
  }

  String _unusedParameterMessage(
    StyioSymbolSnapshot snapshot,
    DocumentSymbol parameter,
  ) {
    final function = snapshot.symbols.where((symbol) {
      return symbol.kind == SymbolKind.function &&
          symbol.declarationRange.start <= parameter.nameRange.start &&
          symbol.declarationRange.end >= parameter.nameRange.end;
    }).lastOrNull;
    if (function == null) {
      return 'Parameter `${parameter.name}` is never used.';
    }
    return 'Parameter `${parameter.name}` is never used in `${function.name}`.';
  }

  List<Diagnostic> _readOnlyResourceWriteDiagnostics(
    String source,
    StyioSymbolSnapshot snapshot,
    List<TokenSpan> tokens,
  ) {
    final diagnostics = <Diagnostic>[];
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.lexeme != '<-') {
        continue;
      }
      final target = _previousSignificant(tokens, index - 1);
      if (target == null || target.kind != TokenKind.identifier) {
        continue;
      }
      final symbol = snapshot.symbols.where((symbol) {
        return symbol.name == target.lexeme &&
            symbol.nameRange.start < target.range.start;
      }).lastOrNull;
      if (symbol == null || symbol.kind == SymbolKind.resource) {
        continue;
      }
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'read-only-resource-write',
          message: 'Cannot write to read-only resource `${target.lexeme}`.',
          range: _lineRange(source, token.range.start),
        ),
      );
    }
    return diagnostics;
  }

  TokenSpan? _previousSignificant(List<TokenSpan> tokens, int index) {
    for (var current = index; current >= 0; current -= 1) {
      final token = tokens[current];
      if (token.kind == TokenKind.whitespace || token.kind == TokenKind.comment) {
        continue;
      }
      return token;
    }
    return null;
  }

  TokenSpan? _nextSignificant(List<TokenSpan> tokens, int index) {
    for (var current = index; current < tokens.length; current += 1) {
      final token = tokens[current];
      if (token.kind == TokenKind.whitespace || token.kind == TokenKind.comment) {
        continue;
      }
      return token;
    }
    return null;
  }

  List<Diagnostic> _unresolvedReferenceDiagnostics(
    StyioSymbolSnapshot snapshot,
    List<TokenSpan> tokens,
  ) {
    final resolvedRanges = {
      for (final reference in snapshot.references)
        '${reference.range.start}:${reference.range.end}',
    };
    return [
      for (var index = 0; index < tokens.length; index += 1)
        if (tokens[index].kind == TokenKind.identifier &&
            !resolvedRanges.contains(
              '${tokens[index].range.start}:${tokens[index].range.end}',
            ) &&
            !_shouldIgnoreUnresolvedCandidate(tokens, index))
          Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'unresolved-reference',
            message: 'Identifier is not resolved by the current symbol index.',
            range: tokens[index].range,
          ),
    ];
  }

  bool _shouldIgnoreUnresolvedCandidate(
    List<TokenSpan> tokens,
    int tokenIndex,
  ) {
    final token = tokens[tokenIndex];
    if (_syntaxHighlighter.isTypeName(token.lexeme) ||
        _syntaxHighlighter.isStandardResource(token.lexeme) ||
        _implicitIdentifierAllowlist.contains(token.lexeme) ||
        _isInsideImportDeclaration(tokens, tokenIndex) ||
        _isInsideBracketSelector(tokens, tokenIndex)) {
      return true;
    }

    final previous = _previousSignificant(tokens, tokenIndex - 1);
    final next = _nextSignificant(tokens, tokenIndex + 1);
    return previous?.lexeme == '.' || next?.lexeme == ':';
  }

  bool _isInsideImportDeclaration(List<TokenSpan> tokens, int tokenIndex) {
    var sawImport = false;
    for (var index = tokenIndex - 1; index >= 0; index -= 1) {
      final token = tokens[index];
      if (token.lexeme.contains('\n')) {
        return false;
      }
      if (token.kind == TokenKind.keyword && token.lexeme == 'import') {
        sawImport = true;
      } else if (sawImport && token.lexeme == '@') {
        return true;
      }
    }
    return false;
  }

  bool _isInsideBracketSelector(List<TokenSpan> tokens, int tokenIndex) {
    for (var index = tokenIndex - 1; index >= 0; index -= 1) {
      final token = tokens[index];
      if (token.lexeme.contains('\n')) {
        return false;
      }
      if (token.lexeme == ']') {
        return false;
      }
      if (token.lexeme == '[') {
        return true;
      }
    }
    return false;
  }

  List<Diagnostic> _redundantTypeAnnotationDiagnostics(String source) {
    return [
      for (final plan in _symbolIndex.redundantExplicitTypePlans(source))
        Diagnostic(
          severity: DiagnosticSeverity.hint,
          code: 'redundant-type-annotation',
          message:
              'Explicit type `${plan.typeName}` on `${plan.variableName}` is redundant.',
          range: plan.typeRange,
        ),
    ];
  }

  List<Diagnostic> _unusedLocalSymbolDiagnostics(
    StyioSymbolSnapshot snapshot, {
    required Set<String> duplicateKeys,
  }) {
    return [
      for (final symbol in snapshot.symbols)
        if ((symbol.kind == SymbolKind.variable ||
                symbol.kind == SymbolKind.task) &&
            !duplicateKeys.contains('${symbol.kind.name}:${symbol.name}') &&
            !snapshot
                .referencesForTarget(symbol.nameRange)
                .any((reference) => !reference.isDeclaration))
          Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'unused-local-symbol',
            message: 'Local symbol `${symbol.name}` is never used.',
            range: symbol.declarationRange,
          ),
    ];
  }

  List<Diagnostic> _expressionDiagnostics(String source) {
    final diagnostics = <Diagnostic>[];
    diagnostics.addAll(_redundantParenthesesDiagnostics(source));

    var lineStart = 0;
    while (lineStart < source.length) {
      final newline = source.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? source.length : newline;
      final line = source.substring(lineStart, lineEnd);
      final whenIndex = line.indexOf('when ');
      final arrowIndex = line.indexOf('->', whenIndex < 0 ? 0 : whenIndex + 5);
      if (whenIndex >= 0 && arrowIndex > whenIndex) {
        final conditionRange = _trimmedRange(
          source,
          SourceRange(
            start: lineStart + whenIndex + 5,
            end: lineStart + arrowIndex,
          ),
        );
        if (!conditionRange.isCollapsed) {
          diagnostics.addAll(
            _conditionExpressionDiagnostics(source, conditionRange),
          );
        }
      }
      if (newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }

    return diagnostics;
  }

  List<Diagnostic> _conditionExpressionDiagnostics(
    String source,
    SourceRange range,
  ) {
    final expression = source.substring(range.start, range.end);
    final diagnostics = <Diagnostic>[];
    if (_simplifyBooleanNegationExpression(expression) != null) {
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.hint,
          code: 'simplifiable-boolean-negation',
          message: _booleanSimplificationMessage(
            'simplifiable-boolean-negation',
          ),
          range: range,
        ),
      );
      return diagnostics;
    }

    final constantValue = _constantBooleanConditionValue(expression);
    if (constantValue != null && expression.trim() != '$constantValue') {
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.hint,
          code: 'constant-condition',
          message: 'Condition is always $constantValue.',
          range: range,
        ),
      );
      return diagnostics;
    }

    final code = _booleanSimplificationCode(expression);
    if (code != null) {
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.hint,
          code: code,
          message: _booleanSimplificationMessage(code),
          range: range,
        ),
      );
    }
    return diagnostics;
  }

  List<Diagnostic> _redundantParenthesesDiagnostics(String source) {
    final diagnostics = <Diagnostic>[];
    final pattern = RegExp(r'\(([A-Za-z_][A-Za-z0-9_]*)\)');
    for (final match in pattern.allMatches(source)) {
      if (match.start > 0 &&
          _isIdentifierCodeUnit(source.codeUnitAt(match.start - 1))) {
        continue;
      }
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.hint,
          code: 'redundant-parentheses',
          message: 'Parentheses do not change this expression.',
          range: SourceRange(start: match.start, end: match.end),
        ),
      );
    }
    return diagnostics;
  }

  String? _booleanSimplificationCode(String expression) {
    if (_simplifyBooleanNegationExpression(expression) != null) {
      return 'simplifiable-boolean-negation';
    }
    if (_simplifyNegatedComparisonExpression(expression) != null) {
      return 'simplifiable-negated-comparison';
    }
    if (_simplifyDeMorganExpression(expression) != null) {
      return 'simplifiable-demorgan-expression';
    }
    if (_simplifyBooleanComparisonExpression(expression) != null) {
      return 'simplifiable-boolean-comparison';
    }
    if (_simplifyBooleanExpression(expression) != null) {
      return 'simplifiable-boolean-expression';
    }
    return null;
  }

  String _booleanSimplificationMessage(String code) {
    return switch (code) {
      'simplifiable-boolean-negation' =>
        'Boolean negation can be simplified.',
      'simplifiable-boolean-comparison' =>
        'Boolean comparison can be simplified.',
      'simplifiable-boolean-expression' =>
        'Boolean expression can be simplified.',
      'simplifiable-negated-comparison' =>
        'Negated comparison can be simplified.',
      'simplifiable-demorgan-expression' =>
        'Negated boolean expression can use De Morgan\'s law.',
      _ => 'Boolean expression can be simplified.',
    };
  }

  String? _simplifyBooleanNegationExpression(String expression) {
    final trimmed = expression.trim();
    if (trimmed.startsWith('!!')) {
      return trimmed.substring(2).trim();
    }
    if (trimmed == '!true') {
      return 'false';
    }
    if (trimmed == '!false') {
      return 'true';
    }
    return null;
  }

  String? _simplifyBooleanComparisonExpression(String expression) {
    final comparison = _splitTopLevelComparison(expression);
    if (comparison == null) {
      return null;
    }
    final left = comparison.left;
    final right = comparison.right;
    final operator = comparison.operatorLexeme;

    if (left == right) {
      return switch (operator) {
        '==' || '<=' || '>=' => 'true',
        '!=' || '<' || '>' => 'false',
        _ => null,
      };
    }

    final leftBool = _boolLiteralValue(left);
    if (leftBool != null) {
      if (operator == '==') {
        return leftBool ? right : '!$right';
      }
      if (operator == '!=') {
        return leftBool ? '!$right' : right;
      }
    }

    final rightBool = _boolLiteralValue(right);
    if (rightBool != null) {
      if (operator == '==') {
        return rightBool ? left : '!$left';
      }
      if (operator == '!=') {
        return rightBool ? '!$left' : left;
      }
    }
    return null;
  }

  String? _simplifyBooleanExpression(String expression) {
    final orSplit = _splitTopLevelBinary(expression, '||');
    if (orSplit != null) {
      final left = orSplit.left;
      final right = orSplit.right;
      if (left == right) {
        return left;
      }
      if (left == 'true' || right == 'true') {
        return 'true';
      }
      if (left == 'false') {
        return right;
      }
      if (right == 'false') {
        return left;
      }
      if (_absorbsBooleanExpression(absorber: left, absorbed: right, op: '&&')) {
        return left;
      }
      if (_absorbsBooleanExpression(absorber: right, absorbed: left, op: '&&')) {
        return right;
      }
      return null;
    }

    final andSplit = _splitTopLevelBinary(expression, '&&');
    if (andSplit != null) {
      final left = andSplit.left;
      final right = andSplit.right;
      if (left == right) {
        return left;
      }
      if (left == 'false' || right == 'false') {
        return 'false';
      }
      if (left == 'true') {
        return right;
      }
      if (right == 'true') {
        return left;
      }
      if (_absorbsBooleanExpression(absorber: left, absorbed: right, op: '||')) {
        return left;
      }
      if (_absorbsBooleanExpression(absorber: right, absorbed: left, op: '||')) {
        return right;
      }
    }
    return null;
  }

  String? _simplifyNegatedComparisonExpression(String expression) {
    final inner = _negatedParenthesizedInner(expression);
    if (inner == null) {
      return null;
    }
    final comparison = _splitTopLevelComparison(inner);
    if (comparison == null) {
      return null;
    }
    final opposite = _oppositeComparisonOperator(comparison.operatorLexeme);
    if (opposite == null) {
      return null;
    }
    return '${comparison.left} $opposite ${comparison.right}';
  }

  String? _simplifyDeMorganExpression(String expression) {
    final inner = _negatedParenthesizedInner(expression);
    if (inner == null) {
      return null;
    }
    final orSplit = _splitTopLevelBinary(inner, '||');
    if (orSplit != null) {
      return '!${orSplit.left} && !${orSplit.right}';
    }
    final andSplit = _splitTopLevelBinary(inner, '&&');
    if (andSplit != null) {
      return '!${andSplit.left} || !${andSplit.right}';
    }
    return null;
  }

  String? _negatedParenthesizedInner(String expression) {
    final trimmed = expression.trim();
    if (!trimmed.startsWith('!')) {
      return null;
    }
    final operand = trimmed.substring(1).trim();
    if (!_isWrappedInSingleParenthesisPair(operand)) {
      return null;
    }
    return operand.substring(1, operand.length - 1).trim();
  }

  bool _absorbsBooleanExpression({
    required String absorber,
    required String absorbed,
    required String op,
  }) {
    final unwrapped = _stripWrappingParentheses(absorbed);
    final split = _splitTopLevelBinary(unwrapped, op);
    if (split == null) {
      return false;
    }
    return split.left == absorber || split.right == absorber;
  }

  _BooleanExpressionSplit? _splitTopLevelBinary(
    String expression,
    String operator,
  ) {
    final trimmed = expression.trim();
    final index = _topLevelOperatorIndex(trimmed, operator);
    if (index < 0) {
      return null;
    }
    return _BooleanExpressionSplit(
      left: _stripWrappingParentheses(trimmed.substring(0, index).trim()),
      operatorLexeme: operator,
      right: _stripWrappingParentheses(
        trimmed.substring(index + operator.length).trim(),
      ),
    );
  }

  _BooleanExpressionSplit? _splitTopLevelComparison(String expression) {
    final trimmed = expression.trim();
    for (final operator in const ['==', '!=', '<=', '>=', '<', '>']) {
      final index = _topLevelOperatorIndex(trimmed, operator);
      if (index < 0) {
        continue;
      }
      return _BooleanExpressionSplit(
        left: _stripWrappingParentheses(trimmed.substring(0, index).trim()),
        operatorLexeme: operator,
        right: _stripWrappingParentheses(
          trimmed.substring(index + operator.length).trim(),
        ),
      );
    }
    return null;
  }

  String? _oppositeComparisonOperator(String operator) {
    return switch (operator) {
      '==' => '!=',
      '!=' => '==',
      '<' => '>=',
      '<=' => '>',
      '>' => '<=',
      '>=' => '<',
      _ => null,
    };
  }

  bool? _boolLiteralValue(String value) {
    return switch (value.trim()) {
      'true' => true,
      'false' => false,
      _ => null,
    };
  }

  String _stripWrappingParentheses(String expression) {
    var current = expression.trim();
    while (_isWrappedInSingleParenthesisPair(current)) {
      current = current.substring(1, current.length - 1).trim();
    }
    return current;
  }

  bool? _constantBooleanConditionValue(String expression) {
    var trimmed = expression.trim();
    if (trimmed == 'true') {
      return true;
    }
    if (trimmed == 'false') {
      return false;
    }
    if (trimmed.startsWith('!')) {
      final value = _constantBooleanConditionValue(trimmed.substring(1));
      return value == null ? null : !value;
    }
    if (_isWrappedInSingleParenthesisPair(trimmed)) {
      return _constantBooleanConditionValue(
        trimmed.substring(1, trimmed.length - 1),
      );
    }

    for (final operator in const ['||', '&&', '==', '!=']) {
      final index = _topLevelOperatorIndex(trimmed, operator);
      if (index < 0) {
        continue;
      }
      final left = _constantBooleanConditionValue(trimmed.substring(0, index));
      final right = _constantBooleanConditionValue(
        trimmed.substring(index + operator.length),
      );
      if (left == null || right == null) {
        return null;
      }
      return switch (operator) {
        '||' => left || right,
        '&&' => left && right,
        '==' => left == right,
        '!=' => left != right,
        _ => null,
      };
    }
    return null;
  }

  bool _isWrappedInSingleParenthesisPair(String expression) {
    if (expression.length < 2 ||
        expression[0] != '(' ||
        expression[expression.length - 1] != ')') {
      return false;
    }
    var depth = 0;
    for (var index = 0; index < expression.length; index += 1) {
      final char = expression[index];
      if (char == '(') {
        depth += 1;
      } else if (char == ')') {
        depth -= 1;
        if (depth == 0 && index < expression.length - 1) {
          return false;
        }
      }
    }
    return depth == 0;
  }

  int _topLevelOperatorIndex(String expression, String operator) {
    var depth = 0;
    for (var index = 0; index <= expression.length - operator.length; index++) {
      final char = expression[index];
      if (char == '(') {
        depth += 1;
        continue;
      }
      if (char == ')') {
        depth -= 1;
        continue;
      }
      if (depth == 0 && expression.startsWith(operator, index)) {
        return index;
      }
    }
    return -1;
  }

  SourceRange _trimmedRange(String source, SourceRange range) {
    var start = range.start.clamp(0, source.length).toInt();
    var end = range.end.clamp(start, source.length).toInt();
    while (start < end && source.codeUnitAt(start) <= 0x20) {
      start += 1;
    }
    while (end > start && source.codeUnitAt(end - 1) <= 0x20) {
      end -= 1;
    }
    return SourceRange(start: start, end: end);
  }

  bool _isIdentifierCodeUnit(int codeUnit) {
    return (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
        (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        codeUnit == 0x5f;
  }

  List<Diagnostic> _dedupeDiagnostics(Iterable<Diagnostic> diagnostics) {
    final deduped = <Diagnostic>[];
    final seen = <String>{};
    for (final diagnostic in diagnostics) {
      final key =
          '${diagnostic.code}:'
          '${diagnostic.range.start}:${diagnostic.range.end}:'
          '${diagnostic.message}';
      if (seen.add(key)) {
        deduped.add(diagnostic);
      }
    }
    return deduped;
  }

  SourceRange _lineRange(String source, int offset) {
    var start = offset.clamp(0, source.length);
    while (start > 0 && source[start - 1] != '\n') {
      start -= 1;
    }

    var end = offset.clamp(0, source.length);
    while (end < source.length && source[end] != '\n') {
      end += 1;
    }

    return SourceRange(start: start, end: end);
  }
}

class _ImportDeclaration {
  const _ImportDeclaration({required this.path, required this.range});

  final String path;
  final SourceRange range;
}

class _BooleanExpressionSplit {
  const _BooleanExpressionSplit({
    required this.left,
    required this.operatorLexeme,
    required this.right,
  });

  final String left;
  final String operatorLexeme;
  final String right;
}
