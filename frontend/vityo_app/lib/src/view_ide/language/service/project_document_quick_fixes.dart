import '../../editor/document_state.dart';
import '../contract/language_contract.dart';
import '../diagnostics/styio_numeric_diagnostics.dart';
import '../semantic/styio_symbol_index.dart';
import '../syntax/styio_syntax_highlighter.dart';

class ProjectDocumentQuickFixProvider {
  const ProjectDocumentQuickFixProvider({
    StyioSyntaxHighlighter syntaxHighlighter = const StyioSyntaxHighlighter(),
    StyioNumericDiagnostics numericDiagnostics =
        const StyioNumericDiagnostics(),
    StyioSymbolIndex symbolIndex = const StyioSymbolIndex(),
  }) : _syntaxHighlighter = syntaxHighlighter,
       _numericDiagnostics = numericDiagnostics,
       _symbolIndex = symbolIndex;

  final StyioSyntaxHighlighter _syntaxHighlighter;
  final StyioNumericDiagnostics _numericDiagnostics;
  final StyioSymbolIndex _symbolIndex;

  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return switch (diagnostic.code) {
      'missing-assignment' => _missingAssignmentFix(document, diagnostic),
      'unexpected-closing-brace' ||
      'unexpected-closing-parenthesis' ||
      'unexpected-closing-bracket' => _removeDiagnosticRangeFix(
        label: 'Remove stray delimiter',
        detail: 'Delete the unmatched closing delimiter.',
        diagnostic: diagnostic,
      ),
      'unclosed-block' => _appendTextFix(
        document: document,
        label: 'Append closing brace',
        detail: 'Insert a matching `}` at the end of the document.',
        text: document.text.endsWith('\n') ? '}' : '\n}',
      ),
      'unclosed-parenthesis' => _appendTextFix(
        document: document,
        label: 'Append closing parenthesis',
        detail: 'Insert a matching `)` at the end of the document.',
        text: ')',
      ),
      'unclosed-bracket' => _appendTextFix(
        document: document,
        label: 'Append closing bracket',
        detail: 'Insert a matching `]` at the end of the document.',
        text: ']',
      ),
      'unknown-token' => _removeDiagnosticRangeFix(
        label: 'Remove unknown token',
        detail: 'Delete the token that is not valid Styio syntax.',
        diagnostic: diagnostic,
      ),
      'unterminated-string' => _unterminatedStringFix(document, diagnostic),
      'unterminated-block-comment' => _appendTextFix(
        document: document,
        label: 'Insert block comment terminator',
        detail: 'Close the block comment with `*/`.',
        text: '*/',
      ),
      'unused-local-symbol' => _unusedLocalSymbolFix(document, diagnostic),
      'unreachable-code' => [
        DiagnosticQuickFix(
          label: 'Remove unreachable code',
          detail: 'Delete code that cannot be executed.',
          edits: [
            FormattingEdit(
              range: _lineRemovalRange(document.text, diagnostic.range),
              newText: '',
            ),
          ],
        ),
      ],
      'read-only-resource-write' => [
        DiagnosticQuickFix(
          label: 'Remove read-only resource write',
          detail: 'Delete the write because the target resource is read-only.',
          edits: [
            FormattingEdit(
              range: _lineRemovalRange(document.text, diagnostic.range),
              newText: '',
            ),
          ],
        ),
      ],
      'duplicate-resource-declaration' => _duplicateResourceOrTaskFix(
        document,
        diagnostic,
        kind: 'resource',
      ),
      'duplicate-task-declaration' => _duplicateResourceOrTaskFix(
        document,
        diagnostic,
        kind: 'task',
      ),
      'duplicate-declaration' ||
      'duplicate-function-declaration' ||
      'duplicate-parameter-declaration' => _duplicateDeclarationFixes(
        document,
        diagnostic,
      ),
      'parameter-shadowing' => _shadowingDeclarationFixes(document, diagnostic),
      'unused-parameter' => _unusedParameterFix(document, diagnostic),
      'redundant-type-annotation' => _redundantTypeAnnotationFix(
        document,
        diagnostic,
      ),
      'redundant-parentheses' => _redundantParenthesesFixes(
        document,
        diagnostic,
      ),
      'constant-condition' => _constantConditionFixes(document, diagnostic),
      'unresolved-resource' => _unresolvedResourceFix(document, diagnostic),
      'unresolved-task-await' => _unresolvedTaskAwaitFix(document, diagnostic),
      'unresolved-reference' => _unresolvedReferenceFixes(document, diagnostic),
      'simplifiable-boolean-negation' ||
      'simplifiable-boolean-comparison' ||
      'simplifiable-boolean-expression' ||
      'simplifiable-negated-comparison' ||
      'simplifiable-demorgan-expression' => _booleanSimplificationFixes(
        document,
        diagnostic,
      ),
      'conditional-task-return' ||
      'missing-task-return' => _missingTaskReturnFixes(document, diagnostic),
      'missing-task-return-value' => _missingTaskReturnValueFixes(
        document,
        diagnostic,
      ),
      'unresolved-task-return-value' => _unresolvedTaskReturnValueFixes(
        document,
        diagnostic,
      ),
      'unknown-named-argument' ||
      'duplicate-named-argument' ||
      'missing-call-argument' ||
      'too-many-call-arguments' ||
      'argument-type-mismatch' => _callArgumentFixes(document, diagnostic),
      'initializer-type-mismatch' => _initializerTypeMismatchFixes(
        document,
        diagnostic,
      ),
      'assignment-type-mismatch' => _assignmentTypeMismatchFixes(
        document,
        diagnostic,
      ),
      'binary-operator-type-mismatch' => _binaryOperatorTypeMismatchFixes(
        document,
        diagnostic,
      ),
      'unary-operator-type-mismatch' => _unaryOperatorTypeMismatchFixes(
        document,
        diagnostic,
      ),
      'condition-type-mismatch' => _conditionTypeMismatchFixes(
        document,
        diagnostic,
      ),
      'return-type-mismatch' => _functionReturnTypeMismatchFixes(
        document,
        diagnostic,
      ),
      'missing-function-return' => _missingFunctionReturnFixes(
        document,
        diagnostic,
      ),
      'resource-write-type-mismatch' => _resourceWriteTypeMismatchFixes(
        document,
        diagnostic,
      ),
      'await-result-type-mismatch' => _awaitResultTypeMismatchFixes(
        document,
        diagnostic,
      ),
      'await-fallback-type-mismatch' => _awaitFallbackTypeMismatchFixes(
        document,
        diagnostic,
      ),
      'task-return-type-mismatch' => _taskReturnTypeMismatchFixes(
        document,
        diagnostic,
      ),
      'invalid-task-return-expression' => _invalidTaskReturnExpressionFixes(
        document,
        diagnostic,
      ),
      'duplicate-import' ||
      'import-block-not-optimized' => _importOptimizationFix(document),
      'simplifiable-numeric-expression' =>
        _numericDiagnostics.quickFixesForDiagnostic(
          source: document.text,
          tokens: _syntaxHighlighter.tokenize(document.text),
          diagnostic: diagnostic,
        ),
      _ => const <DiagnosticQuickFix>[],
    };
  }

  List<DiagnosticQuickFix> _missingAssignmentFix(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final lineText = document.text.substring(
      diagnostic.range.start,
      diagnostic.range.end,
    );
    final trimmedLine = lineText.replaceFirst(RegExp(r'\s+$'), '');
    final insertionOffset = diagnostic.range.start + trimmedLine.length;
    return [
      DiagnosticQuickFix(
        label: 'Insert assignment',
        detail: 'Append ` = value` to the declaration.',
        edits: [
          FormattingEdit(
            range: SourceRange(start: insertionOffset, end: insertionOffset),
            newText: ' = value',
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _removeDiagnosticRangeFix({
    required String label,
    required String detail,
    required Diagnostic diagnostic,
  }) {
    return [
      DiagnosticQuickFix(
        label: label,
        detail: detail,
        edits: [FormattingEdit(range: diagnostic.range, newText: '')],
      ),
    ];
  }

  List<DiagnosticQuickFix> _appendTextFix({
    required DocumentState document,
    required String label,
    required String detail,
    required String text,
  }) {
    return [
      DiagnosticQuickFix(
        label: label,
        detail: detail,
        edits: [
          FormattingEdit(
            range: SourceRange(start: document.length, end: document.length),
            newText: text,
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _unterminatedStringFix(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final quote = document.text.substring(
      diagnostic.range.start,
      diagnostic.range.start + 1,
    );
    return [
      DiagnosticQuickFix(
        label: 'Insert closing quote',
        detail: 'Close the string literal.',
        edits: [
          FormattingEdit(
            range: SourceRange(
              start: diagnostic.range.end,
              end: diagnostic.range.end,
            ),
            newText: quote,
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _resourceWriteTypeMismatchFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final expectedType = _firstBacktickCaptureAfter(
      diagnostic.message,
      'expects',
    );
    if (expectedType == null) {
      return const <DiagnosticQuickFix>[];
    }
    final replacement = _defaultReturnExpressionForType(expectedType);
    if (replacement == 'value') {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: 'Change resource write value to $expectedType literal',
        detail: 'Rewrite the value sent to the resource as `$expectedType`.',
        edits: [
          FormattingEdit(
            range: _trimmedRange(document.text, diagnostic.range),
            newText: replacement,
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _missingFunctionReturnFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final source = document.text;
    final nameEnd = diagnostic.range.end.clamp(0, source.length).toInt();
    final openingBrace = _functionOpeningBraceAfter(source, nameEnd);
    if (openingBrace == null) {
      return const <DiagnosticQuickFix>[];
    }
    final closingBrace = _matchingBraceInSource(source, openingBrace);
    if (closingBrace == null) {
      return const <DiagnosticQuickFix>[];
    }
    final returnType = _functionReturnTypeBeforeBody(
      source: source,
      nameEnd: nameEnd,
      openingBrace: openingBrace,
    );
    if (returnType == null || returnType.isEmpty) {
      return const <DiagnosticQuickFix>[];
    }
    final replacement = _defaultReturnExpressionForType(returnType);
    if (replacement.isEmpty) {
      return const <DiagnosticQuickFix>[];
    }

    final returnKeyword =
        _isHashFunctionDeclarationName(source, diagnostic.range.start)
        ? '<|'
        : 'emit';
    final lineEnding = _lineEndingFor(source);
    final closingIndent = _lineIndentBefore(source, closingBrace);
    final emitIndent = '$closingIndent  ';
    final insertText = closingBrace > 0 && source[closingBrace - 1] == '\n'
        ? '$emitIndent$returnKeyword $replacement$lineEnding'
        : '$lineEnding$emitIndent$returnKeyword $replacement'
              '$lineEnding$closingIndent';

    return [
      DiagnosticQuickFix(
        label: 'Insert return value',
        detail:
            'Insert a default Styio `$returnKeyword` return for `$returnType`.',
        edits: [
          FormattingEdit(
            range: SourceRange(start: closingBrace, end: closingBrace),
            newText: insertText,
          ),
        ],
      ),
    ];
  }

  int? _functionOpeningBraceAfter(String source, int offset) {
    final openingParenthesis = source.indexOf('(', offset);
    if (openingParenthesis < 0) {
      return null;
    }
    final closingParenthesis = _matchingParenthesisInSource(
      source,
      openingParenthesis,
    );
    if (closingParenthesis == null) {
      return null;
    }
    var index = closingParenthesis + 1;
    while (index < source.length) {
      final char = source[index];
      if (char == '{') {
        return index;
      }
      if (char == '\n') {
        return null;
      }
      index += 1;
    }
    return null;
  }

  String? _functionReturnTypeBeforeBody({
    required String source,
    required int nameEnd,
    required int openingBrace,
  }) {
    final openingParenthesis = source.indexOf('(', nameEnd);
    if (openingParenthesis < 0 || openingParenthesis >= openingBrace) {
      return null;
    }
    final closingParenthesis = _matchingParenthesisInSource(
      source,
      openingParenthesis,
    );
    if (closingParenthesis == null || closingParenthesis >= openingBrace) {
      return null;
    }
    final colon = source.indexOf(':', closingParenthesis + 1);
    if (colon < 0 || colon >= openingBrace) {
      return null;
    }
    final arrow = source.lastIndexOf('=>', openingBrace);
    final returnTypeEnd = arrow > colon ? arrow : openingBrace;
    return source.substring(colon + 1, returnTypeEnd).trim();
  }

  bool _isHashFunctionDeclarationName(String source, int nameStart) {
    if (nameStart <= 0 || nameStart >= source.length) {
      return false;
    }
    final lineStart = source.lastIndexOf('\n', nameStart - 1) + 1;
    final hashIndex = source.lastIndexOf('#', nameStart);
    if (hashIndex < lineStart) {
      return false;
    }
    return source.substring(hashIndex + 1, nameStart).trim().isEmpty;
  }

  int? _matchingParenthesisInSource(String source, int openingParenthesis) {
    if (openingParenthesis < 0 ||
        openingParenthesis >= source.length ||
        source[openingParenthesis] != '(') {
      return null;
    }
    var depth = 0;
    for (var index = openingParenthesis; index < source.length; index += 1) {
      final char = source[index];
      if (char == '(') {
        depth += 1;
      } else if (char == ')') {
        depth -= 1;
        if (depth == 0) {
          return index;
        }
      }
    }
    return null;
  }

  List<DiagnosticQuickFix> _awaitResultTypeMismatchFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final actualType = _firstBacktickCaptureAfter(
      diagnostic.message,
      'returns',
    );
    if (actualType == null) {
      return const <DiagnosticQuickFix>[];
    }
    final typeRange = _awaitBindingTypeSourceRange(
      document.text,
      diagnostic.range,
    );
    if (typeRange == null) {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: 'Change await binding type to $actualType',
        detail: 'Update the await binding type to match the task result.',
        edits: [FormattingEdit(range: typeRange, newText: actualType)],
      ),
    ];
  }

  List<DiagnosticQuickFix> _awaitFallbackTypeMismatchFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final expectedType = _firstBacktickCaptureAfter(
      diagnostic.message,
      'expects',
    );
    if (expectedType == null) {
      return const <DiagnosticQuickFix>[];
    }
    final replacement = _defaultReturnExpressionForType(expectedType);
    if (replacement == 'value') {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: 'Change await fallback to $expectedType literal',
        detail: 'Rewrite the await fallback value as `$expectedType`.',
        edits: [
          FormattingEdit(
            range: _trimmedRange(document.text, diagnostic.range),
            newText: replacement,
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _taskReturnTypeMismatchFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final expectedType = _firstBacktickCaptureAfter(
      diagnostic.message,
      'returns both',
    );
    if (expectedType == null) {
      return const <DiagnosticQuickFix>[];
    }
    final replacement = _defaultReturnExpressionForType(expectedType);
    if (replacement == 'value') {
      return const <DiagnosticQuickFix>[];
    }

    return _taskReturnExpressionLiteralFixes(
      document: document,
      diagnostic: diagnostic,
      expectedType: expectedType,
      replacement: replacement,
    );
  }

  List<DiagnosticQuickFix> _invalidTaskReturnExpressionFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final taskName = _firstBacktickCaptureAfter(diagnostic.message, 'Task');
    if (taskName == null) {
      return const <DiagnosticQuickFix>[];
    }
    final expectedType = _awaitBindingTypeForTaskName(document.text, taskName);
    if (expectedType == null) {
      return const <DiagnosticQuickFix>[];
    }
    final replacement = _defaultReturnExpressionForType(expectedType);
    if (replacement == 'value') {
      return const <DiagnosticQuickFix>[];
    }

    return _taskReturnExpressionLiteralFixes(
      document: document,
      diagnostic: diagnostic,
      expectedType: expectedType,
      replacement: replacement,
    );
  }

  List<DiagnosticQuickFix> _missingTaskReturnFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final source = document.text;
    if (diagnostic.range.start < 0 ||
        diagnostic.range.end > source.length ||
        diagnostic.range.start >= diagnostic.range.end) {
      return const <DiagnosticQuickFix>[];
    }

    final taskName = source.substring(
      diagnostic.range.start,
      diagnostic.range.end,
    );
    final bindingText = _firstBacktickCaptureAfter(diagnostic.message, 'for');
    final colon = bindingText?.lastIndexOf(':') ?? -1;
    if (bindingText == null || colon < 0) {
      return const <DiagnosticQuickFix>[];
    }
    final expectedType = bindingText.substring(colon + 1).trim();
    final replacement = _defaultReturnExpressionForType(expectedType);
    if (replacement == 'value') {
      return const <DiagnosticQuickFix>[];
    }

    final taskPattern = RegExp(
      '\\b${RegExp.escape(taskName)}\\s*=\\s*\\|\\|>\\s*\\{',
    );
    final declaration = taskPattern.firstMatch(source);
    if (declaration == null) {
      return const <DiagnosticQuickFix>[];
    }
    final openingBrace = source.indexOf('{', declaration.start);
    final closingBrace = _matchingBraceInSource(source, openingBrace);
    if (closingBrace == null) {
      return const <DiagnosticQuickFix>[];
    }

    final closingIndent = _lineIndentBefore(source, closingBrace);
    final returnIndent = '$closingIndent  ';
    final insertText = closingBrace > 0 && source[closingBrace - 1] == '\n'
        ? '$returnIndent<| $replacement\n'
        : '\n$returnIndent<| $replacement\n$closingIndent';

    return [
      DiagnosticQuickFix(
        label: 'Insert task return value',
        detail: 'Insert a default Styio task return for `$expectedType`.',
        edits: [
          FormattingEdit(
            range: SourceRange(start: closingBrace, end: closingBrace),
            newText: insertText,
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _duplicateDeclarationFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return _renameDeclarationFixes(
      document: document,
      diagnostic: diagnostic,
      labelPrefix: 'Rename duplicate declaration to',
      detail:
          'Rename the duplicate declaration and its current-file references.',
    );
  }

  List<DiagnosticQuickFix> _shadowingDeclarationFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    return _renameDeclarationFixes(
      document: document,
      diagnostic: diagnostic,
      labelPrefix: 'Rename shadowing declaration to',
      detail:
          'Rename the shadowing local declaration and its current-file references.',
    );
  }

  List<DiagnosticQuickFix> _renameDeclarationFixes({
    required DocumentState document,
    required Diagnostic diagnostic,
    required String labelPrefix,
    required String detail,
  }) {
    final tokens = _syntaxHighlighter.tokenize(document.text);
    final symbolSnapshot = _symbolIndex.build(tokens);
    final symbol = _symbolForRange(symbolSnapshot, diagnostic.range);
    if (symbol == null) {
      return const <DiagnosticQuickFix>[];
    }

    final newName = _uniqueSymbolName(symbolSnapshot, symbol.name);
    final renamePlan = _symbolIndex.renameAt(
      document.text,
      diagnostic.range.start,
      newName,
    );
    if (renamePlan == null ||
        renamePlan.hasConflicts ||
        renamePlan.edits.isEmpty) {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: '$labelPrefix `$newName`',
        detail: detail,
        edits: renamePlan.edits,
      ),
    ];
  }

  DocumentSymbol? _symbolForRange(
    StyioSymbolSnapshot symbolSnapshot,
    SourceRange range,
  ) {
    for (final symbol in symbolSnapshot.symbols) {
      if (symbol.nameRange.start == range.start &&
          symbol.nameRange.end == range.end) {
        return symbol;
      }
    }
    return null;
  }

  String _uniqueSymbolName(
    StyioSymbolSnapshot symbolSnapshot,
    String baseName,
  ) {
    final existingNames = symbolSnapshot.symbols
        .map((symbol) => symbol.name)
        .toSet();
    var suffix = 2;
    var candidate = '$baseName$suffix';
    while (existingNames.contains(candidate) ||
        !_isValidIdentifier(candidate)) {
      suffix += 1;
      candidate = '$baseName$suffix';
    }
    return candidate;
  }

  List<DiagnosticQuickFix> _redundantParenthesesFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final range = _trimmedRange(document.text, diagnostic.range);
    if (range.end - range.start < 2 ||
        document.text[range.start] != '(' ||
        document.text[range.end - 1] != ')') {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: 'Remove redundant parentheses',
        detail: 'Unwrap parentheses that do not change the expression shape.',
        edits: [
          FormattingEdit(
            range: range,
            newText: document.text.substring(range.start + 1, range.end - 1),
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _constantConditionFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final conditionText = _textForRange(document.text, diagnostic.range);
    if (conditionText == null) {
      return const <DiagnosticQuickFix>[];
    }
    final value = _constantBooleanConditionValue(conditionText);
    if (value == null) {
      return const <DiagnosticQuickFix>[];
    }

    final replacement = value ? 'true' : 'false';
    final fixes = <DiagnosticQuickFix>[];
    if (conditionText.trim() != replacement) {
      fixes.add(
        DiagnosticQuickFix(
          label: 'Replace condition with $replacement',
          detail: 'Collapse the constant Styio `when` condition.',
          edits: [
            FormattingEdit(range: diagnostic.range, newText: replacement),
          ],
        ),
      );
    }
    if (!value) {
      final lineRange = _lineRemovalRange(document.text, diagnostic.range);
      final lineText = document.text.substring(lineRange.start, lineRange.end);
      if (lineText.contains('when') &&
          lineText.contains('->') &&
          !lineText.contains('{')) {
        fixes.add(
          DiagnosticQuickFix(
            label: 'Remove unreachable `when` branch',
            detail:
                'Delete the Styio branch guarded by a constant false condition.',
            edits: [FormattingEdit(range: lineRange, newText: '')],
          ),
        );
      }
    }
    return fixes;
  }

  List<DiagnosticQuickFix> _booleanSimplificationFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final range = _trimmedRange(document.text, diagnostic.range);
    if (range.start >= range.end) {
      return const <DiagnosticQuickFix>[];
    }
    final expression = document.text.substring(range.start, range.end);
    final replacement = switch (diagnostic.code) {
      'simplifiable-boolean-negation' => _simplifyBooleanNegationExpression(
        expression,
      ),
      'simplifiable-boolean-comparison' => _simplifyBooleanComparisonExpression(
        expression,
      ),
      'simplifiable-boolean-expression' => _simplifyBooleanExpression(
        expression,
      ),
      'simplifiable-negated-comparison' => _simplifyNegatedComparisonExpression(
        expression,
      ),
      'simplifiable-demorgan-expression' => _simplifyDeMorganExpression(
        expression,
      ),
      _ => null,
    };
    if (replacement == null || replacement.trim().isEmpty) {
      return const <DiagnosticQuickFix>[];
    }

    final (label, detail) = switch (diagnostic.code) {
      'simplifiable-boolean-negation' => (
        expression.trim().startsWith('!!')
            ? 'Simplify double negation'
            : 'Simplify negated boolean literal',
        expression.trim().startsWith('!!')
            ? 'Replace the double-negated boolean expression with its value.'
            : 'Replace a negated boolean literal with its opposite value.',
      ),
      'simplifiable-boolean-comparison' => (
        'Simplify boolean comparison',
        'Replace a boolean comparison with its simplified value.',
      ),
      'simplifiable-boolean-expression' => (
        'Simplify boolean expression',
        'Replace a boolean operation with its simplified value.',
      ),
      'simplifiable-negated-comparison' => (
        'Simplify negated comparison',
        'Replace negated comparison with the opposite operator.',
      ),
      'simplifiable-demorgan-expression' => (
        'Apply De Morgan\'s law',
        'Distribute negation over the boolean expression.',
      ),
      _ => ('Simplify boolean expression', 'Simplify the boolean expression.'),
    };

    return [
      DiagnosticQuickFix(
        label: label,
        detail: detail,
        edits: [FormattingEdit(range: range, newText: replacement)],
      ),
    ];
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
      if (_absorbsBooleanExpression(
        absorber: left,
        absorbed: right,
        op: '&&',
      )) {
        return left;
      }
      if (_absorbsBooleanExpression(
        absorber: right,
        absorbed: left,
        op: '&&',
      )) {
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
      if (_absorbsBooleanExpression(
        absorber: left,
        absorbed: right,
        op: '||',
      )) {
        return left;
      }
      if (_absorbsBooleanExpression(
        absorber: right,
        absorbed: left,
        op: '||',
      )) {
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
      return '${_negatedBooleanTerm(orSplit.left)} && '
          '${_negatedBooleanTerm(orSplit.right)}';
    }
    final andSplit = _splitTopLevelBinary(inner, '&&');
    if (andSplit != null) {
      return '${_negatedBooleanTerm(andSplit.left)} || '
          '${_negatedBooleanTerm(andSplit.right)}';
    }
    return null;
  }

  String _negatedBooleanTerm(String term) {
    final trimmed = term.trim();
    final comparison = _splitTopLevelComparison(trimmed);
    if (comparison != null) {
      final opposite = _oppositeComparisonOperator(comparison.operatorLexeme);
      if (opposite != null) {
        return '${comparison.left} $opposite ${comparison.right}';
      }
    }
    if (trimmed.startsWith('!')) {
      return trimmed.substring(1).trim();
    }
    return '!$trimmed';
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

  _BooleanBinarySplit? _splitTopLevelBinary(
    String expression,
    String operator,
  ) {
    final trimmed = expression.trim();
    final index = _topLevelOperatorIndex(trimmed, operator);
    if (index < 0) {
      return null;
    }
    return _BooleanBinarySplit(
      left: _stripWrappingParentheses(trimmed.substring(0, index).trim()),
      operatorLexeme: operator,
      right: _stripWrappingParentheses(
        trimmed.substring(index + operator.length).trim(),
      ),
    );
  }

  _BooleanBinarySplit? _splitTopLevelComparison(String expression) {
    final trimmed = expression.trim();
    for (final operator in const ['==', '!=', '<=', '>=', '<', '>']) {
      final index = _topLevelOperatorIndex(trimmed, operator);
      if (index < 0) {
        continue;
      }
      return _BooleanBinarySplit(
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

  List<DiagnosticQuickFix> _missingTaskReturnValueFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final source = document.text;
    final taskName = _firstBacktickCaptureAfter(diagnostic.message, 'Task');
    if (taskName == null ||
        diagnostic.range.start < 0 ||
        diagnostic.range.end > source.length ||
        diagnostic.range.start >= diagnostic.range.end) {
      return const <DiagnosticQuickFix>[];
    }

    final expectedType = _awaitBindingTypeForTaskName(source, taskName);
    if (expectedType == null) {
      return const <DiagnosticQuickFix>[];
    }
    final replacement = _defaultReturnExpressionForType(expectedType);
    if (replacement == 'value') {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: 'Insert task return expression',
        detail: 'Insert a default `$expectedType` task return expression.',
        edits: [
          FormattingEdit(
            range: SourceRange(
              start: diagnostic.range.end,
              end: diagnostic.range.end,
            ),
            newText: ' $replacement',
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _unresolvedTaskReturnValueFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final source = document.text;
    final taskName = _firstBacktickCaptureAfter(diagnostic.message, 'Task');
    final valueName = _firstBacktickCaptureAfter(diagnostic.message, 'value');
    if (taskName == null ||
        valueName == null ||
        diagnostic.range.start < 0 ||
        diagnostic.range.end > source.length ||
        diagnostic.range.start >= diagnostic.range.end) {
      return const <DiagnosticQuickFix>[];
    }

    final expectedType = _awaitBindingTypeForTaskName(source, taskName);
    if (expectedType == null) {
      return const <DiagnosticQuickFix>[];
    }
    final replacement = _defaultReturnExpressionForType(expectedType);
    if (replacement == 'value') {
      return const <DiagnosticQuickFix>[];
    }

    final indent = _lineIndentAt(source, diagnostic.range.start);
    return [
      DiagnosticQuickFix(
        label: 'Create task local binding `$valueName`',
        detail:
            'Create `$valueName` before the task return using `$expectedType`.',
        edits: [
          FormattingEdit(
            range: _lineInsertionRange(source, diagnostic.range.start),
            newText: '$indent$valueName = $replacement\n',
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _taskReturnExpressionLiteralFixes({
    required DocumentState document,
    required Diagnostic diagnostic,
    required String expectedType,
    required String replacement,
  }) {
    return [
      DiagnosticQuickFix(
        label: 'Change task return expression to $expectedType literal',
        detail: 'Rewrite the task return expression as `$expectedType`.',
        edits: [
          FormattingEdit(
            range: _trimmedRange(document.text, diagnostic.range),
            newText: replacement,
          ),
        ],
      ),
    ];
  }

  String? _firstBacktickCaptureAfter(String message, String marker) {
    final markerIndex = message.indexOf(marker);
    if (markerIndex < 0) {
      return null;
    }
    final match = RegExp(
      r'`([^`]+)`',
    ).firstMatch(message.substring(markerIndex + marker.length));
    return match?.group(1);
  }

  SourceRange? _awaitBindingTypeSourceRange(
    String source,
    SourceRange taskRange,
  ) {
    if (taskRange.start < 0 || taskRange.start > source.length) {
      return null;
    }
    final lineStart = source.lastIndexOf('\n', taskRange.start - 1) + 1;
    final lineEndIndex = source.indexOf('\n', taskRange.end);
    final lineEnd = lineEndIndex < 0 ? source.length : lineEndIndex;
    final arrow = source.lastIndexOf('->', taskRange.start);
    if (arrow < lineStart || arrow >= taskRange.start) {
      return null;
    }
    final colon = source.indexOf(':', taskRange.end);
    if (colon < 0 || colon >= lineEnd) {
      return null;
    }

    var start = colon + 1;
    while (start < lineEnd && source.codeUnitAt(start) <= 0x20) {
      start += 1;
    }
    var end = lineEnd;
    while (end > start && source.codeUnitAt(end - 1) <= 0x20) {
      end -= 1;
    }
    if (start >= end) {
      return null;
    }
    return SourceRange(start: start, end: end);
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

  List<DiagnosticQuickFix> _functionReturnTypeMismatchFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final issue = _symbolIndex
        .functionReturnTypeIssues(document.text)
        .firstWhere(
          (item) =>
              item.diagnostic.code == diagnostic.code &&
              item.diagnostic.range.start == diagnostic.range.start &&
              item.diagnostic.range.end == diagnostic.range.end,
          orElse: () => const StyioFunctionReturnTypeIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.hint,
              code: '',
              message: '',
              range: SourceRange(start: 0, end: 0),
            ),
            functionName: '',
            expectedTypeName: '',
            actualTypeName: '',
            returnExpressionRange: SourceRange(start: 0, end: 0),
            returnTypeRange: SourceRange(start: 0, end: 0),
            replacementReturnExpressionText: '',
          ),
        );
    if (issue.functionName.isEmpty) {
      return const <DiagnosticQuickFix>[];
    }

    final fixes = <DiagnosticQuickFix>[];
    if (issue.replacementReturnExpressionText.isNotEmpty) {
      fixes.add(
        DiagnosticQuickFix(
          label:
              'Change return expression to ${issue.expectedTypeName} literal',
          detail:
              'Rewrite `${issue.functionName}` return expression from '
              '`${issue.actualTypeName}` to `${issue.expectedTypeName}`.',
          edits: [
            FormattingEdit(
              range: issue.returnExpressionRange,
              newText: issue.replacementReturnExpressionText,
            ),
          ],
        ),
      );
    }
    if (_canChangeFunctionReturnTypeForIssue(document.text, issue)) {
      fixes.add(
        DiagnosticQuickFix(
          label:
              'Change function `${issue.functionName}` return type to '
              '${issue.actualTypeName}',
          detail:
              'Update `${issue.functionName}` return type to match the '
              'returned expression.',
          edits: [
            FormattingEdit(
              range: issue.returnTypeRange,
              newText: issue.actualTypeName,
            ),
          ],
        ),
      );
    }
    return fixes;
  }

  bool _canChangeFunctionReturnTypeForIssue(
    String source,
    StyioFunctionReturnTypeIssue issue,
  ) {
    final openingBrace = _functionOpeningBraceAfterReturnTypeRange(
      source,
      issue.returnTypeRange,
    );
    if (openingBrace == null) {
      return false;
    }
    final closingBrace = _matchingBraceInSource(source, openingBrace);
    if (closingBrace == null) {
      return false;
    }

    final tokens = _syntaxHighlighter.tokenize(source);
    final returnMarkerIndexes = <int>[];
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.range.start <= openingBrace || token.range.end > closingBrace) {
        continue;
      }
      if (token.lexeme == 'emit' || token.lexeme == '<|') {
        returnMarkerIndexes.add(index);
      }
    }
    if (returnMarkerIndexes.length != 1) {
      return false;
    }

    final expressionIndex = _nextSignificantIndex(
      tokens,
      returnMarkerIndexes.single + 1,
    );
    return expressionIndex != null &&
        tokens[expressionIndex].range.start ==
            issue.returnExpressionRange.start;
  }

  int? _functionOpeningBraceAfterReturnTypeRange(
    String source,
    SourceRange returnTypeRange,
  ) {
    var index = returnTypeRange.end.clamp(0, source.length);
    while (index < source.length) {
      final char = source[index];
      if (char == '{') {
        return index;
      }
      if (char == '\n') {
        return null;
      }
      index += 1;
    }
    return null;
  }

  int? _matchingBraceInSource(String source, int openingBrace) {
    if (openingBrace < 0 ||
        openingBrace >= source.length ||
        source[openingBrace] != '{') {
      return null;
    }
    var depth = 0;
    for (var index = openingBrace; index < source.length; index += 1) {
      final char = source[index];
      if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        depth -= 1;
        if (depth == 0) {
          return index;
        }
      }
    }
    return null;
  }

  String _lineIndentBefore(String source, int offset) {
    final lineStart = offset <= 0
        ? 0
        : source.lastIndexOf('\n', offset - 1) + 1;
    final buffer = StringBuffer();
    for (var index = lineStart; index < offset; index += 1) {
      final char = source[index];
      if (char != ' ' && char != '\t') {
        return '';
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  SourceRange _lineInsertionRange(String source, int offset) {
    final normalizedOffset = offset.clamp(0, source.length).toInt();
    final previousNewline = normalizedOffset <= 0
        ? -1
        : source.lastIndexOf('\n', normalizedOffset - 1);
    final lineStart = previousNewline + 1;
    return SourceRange(start: lineStart, end: lineStart);
  }

  String _lineIndentAt(String source, int offset) {
    final lineStart = _lineInsertionRange(source, offset).start;
    var cursor = lineStart;
    while (cursor < source.length) {
      final codeUnit = source.codeUnitAt(cursor);
      if (codeUnit != 0x20 && codeUnit != 0x09) {
        break;
      }
      cursor += 1;
    }
    return source.substring(lineStart, cursor);
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

  List<DiagnosticQuickFix> _binaryOperatorTypeMismatchFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final issue = _symbolIndex
        .binaryOperatorTypeIssues(document.text)
        .firstWhere(
          (item) =>
              item.diagnostic.code == diagnostic.code &&
              item.diagnostic.range.start == diagnostic.range.start &&
              item.diagnostic.range.end == diagnostic.range.end,
          orElse: () => const StyioBinaryOperatorTypeIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.hint,
              code: '',
              message: '',
              range: SourceRange(start: 0, end: 0),
            ),
            operatorLexeme: '',
            leftTypeName: '',
            rightTypeName: '',
            operatorRange: SourceRange(start: 0, end: 0),
            leftOperandRange: SourceRange(start: 0, end: 0),
            rightOperandRange: SourceRange(start: 0, end: 0),
          ),
        );
    if (issue.operatorLexeme.isEmpty ||
        (issue.operatorLexeme != '&&' && issue.operatorLexeme != '||')) {
      return const <DiagnosticQuickFix>[];
    }

    final fixes = <DiagnosticQuickFix>[];
    if (_isNumericTypeName(issue.leftTypeName)) {
      fixes.add(
        DiagnosticQuickFix(
          label: 'Compare left operand with zero',
          detail:
              'Rewrite the left `${issue.operatorLexeme}` operand from '
              '`${issue.leftTypeName}` to `bool`.',
          edits: [
            FormattingEdit(
              range: issue.leftOperandRange,
              newText: _compareOperandWithZero(
                source: document.text,
                range: issue.leftOperandRange,
                typeName: issue.leftTypeName,
              ),
            ),
          ],
        ),
      );
    }
    if (_isNumericTypeName(issue.rightTypeName)) {
      fixes.add(
        DiagnosticQuickFix(
          label: 'Compare right operand with zero',
          detail:
              'Rewrite the right `${issue.operatorLexeme}` operand from '
              '`${issue.rightTypeName}` to `bool`.',
          edits: [
            FormattingEdit(
              range: issue.rightOperandRange,
              newText: _compareOperandWithZero(
                source: document.text,
                range: issue.rightOperandRange,
                typeName: issue.rightTypeName,
              ),
            ),
          ],
        ),
      );
    }
    return fixes;
  }

  List<DiagnosticQuickFix> _unaryOperatorTypeMismatchFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final issue = _symbolIndex
        .unaryOperatorTypeIssues(document.text)
        .firstWhere(
          (item) =>
              item.diagnostic.code == diagnostic.code &&
              item.diagnostic.range.start == diagnostic.range.start &&
              item.diagnostic.range.end == diagnostic.range.end,
          orElse: () => const StyioUnaryOperatorTypeIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.hint,
              code: '',
              message: '',
              range: SourceRange(start: 0, end: 0),
            ),
            operatorLexeme: '',
            operandTypeName: '',
            operatorRange: SourceRange(start: 0, end: 0),
            operandRange: SourceRange(start: 0, end: 0),
          ),
        );
    if (issue.operatorLexeme != '!' ||
        !_isNumericTypeName(issue.operandTypeName)) {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: 'Compare operand with zero',
        detail:
            'Rewrite `!` operand from `${issue.operandTypeName}` to `bool`.',
        edits: [
          FormattingEdit(
            range: SourceRange(
              start: issue.operatorRange.start,
              end: issue.operandRange.end,
            ),
            newText: _compareOperandEqualToZero(
              source: document.text,
              range: issue.operandRange,
              typeName: issue.operandTypeName,
            ),
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _conditionTypeMismatchFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final issue = _symbolIndex
        .conditionTypeMismatchIssues(document.text)
        .firstWhere(
          (item) =>
              item.diagnostic.code == diagnostic.code &&
              item.diagnostic.range.start == diagnostic.range.start &&
              item.diagnostic.range.end == diagnostic.range.end,
          orElse: () => const StyioConditionTypeMismatchIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.hint,
              code: '',
              message: '',
              range: SourceRange(start: 0, end: 0),
            ),
            expectedTypeName: '',
            actualTypeName: '',
            conditionRange: SourceRange(start: 0, end: 0),
            replacementConditionText: '',
          ),
        );
    if (issue.expectedTypeName.isEmpty ||
        issue.replacementConditionText.isEmpty) {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: 'Compare condition with zero',
        detail:
            'Rewrite numeric `when` condition from '
            '`${issue.actualTypeName}` to `bool`.',
        edits: [
          FormattingEdit(
            range: issue.conditionRange,
            newText: issue.replacementConditionText,
          ),
        ],
      ),
    ];
  }

  bool _isNumericTypeName(String typeName) {
    return const {
      'i8',
      'i16',
      'i32',
      'i64',
      'i128',
      'f32',
      'f64',
    }.contains(typeName);
  }

  String _compareOperandWithZero({
    required String source,
    required SourceRange range,
    required String typeName,
  }) {
    final operandText = source.substring(range.start, range.end).trim();
    final zeroLiteral = typeName == 'f32' || typeName == 'f64' ? '0.0' : '0';
    return '$operandText != $zeroLiteral';
  }

  String _compareOperandEqualToZero({
    required String source,
    required SourceRange range,
    required String typeName,
  }) {
    final operandText = source.substring(range.start, range.end).trim();
    final zeroLiteral = typeName == 'f32' || typeName == 'f64' ? '0.0' : '0';
    return '$operandText == $zeroLiteral';
  }

  List<DiagnosticQuickFix> _assignmentTypeMismatchFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final issue = _symbolIndex
        .assignmentTypeMismatchIssues(document.text)
        .firstWhere(
          (item) =>
              item.diagnostic.code == diagnostic.code &&
              item.diagnostic.range.start == diagnostic.range.start &&
              item.diagnostic.range.end == diagnostic.range.end,
          orElse: () => const StyioAssignmentTypeMismatchIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.hint,
              code: '',
              message: '',
              range: SourceRange(start: 0, end: 0),
            ),
            variableName: '',
            expectedTypeName: '',
            actualTypeName: '',
            assignmentRange: SourceRange(start: 0, end: 0),
            typeRange: SourceRange(start: 0, end: 0),
            replacementAssignmentText: '',
            initializerRange: null,
            initializerActualTypeName: '',
            replacementInitializerTextForActualType: '',
          ),
        );
    if (issue.variableName.isEmpty) {
      return const <DiagnosticQuickFix>[];
    }

    final fixes = <DiagnosticQuickFix>[];
    if (issue.replacementAssignmentText.isNotEmpty) {
      fixes.add(
        DiagnosticQuickFix(
          label: 'Change assignment to ${issue.expectedTypeName} literal',
          detail:
              'Rewrite `${issue.variableName}` assignment from '
              '`${issue.actualTypeName}` to `${issue.expectedTypeName}`.',
          edits: [
            FormattingEdit(
              range: issue.assignmentRange,
              newText: issue.replacementAssignmentText,
            ),
          ],
        ),
      );
    }

    if (issue.canChangeDeclaredType) {
      final edits = <FormattingEdit>[
        FormattingEdit(range: issue.typeRange, newText: issue.actualTypeName),
      ];
      final initializerRange = issue.initializerRange;
      if (initializerRange != null &&
          issue.replacementInitializerTextForActualType.isNotEmpty) {
        edits.add(
          FormattingEdit(
            range: initializerRange,
            newText: issue.replacementInitializerTextForActualType,
          ),
        );
      }
      fixes.add(
        DiagnosticQuickFix(
          label:
              'Change local `${issue.variableName}` type to '
              '${issue.actualTypeName}',
          detail:
              'Update `${issue.variableName}` explicit type to match the '
              'assigned expression.',
          edits: edits,
        ),
      );
    }
    return fixes;
  }

  List<DiagnosticQuickFix> _initializerTypeMismatchFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final issue = _symbolIndex
        .typedLocalInitializerIssues(document.text)
        .firstWhere(
          (item) =>
              item.diagnostic.code == diagnostic.code &&
              item.diagnostic.range.start == diagnostic.range.start &&
              item.diagnostic.range.end == diagnostic.range.end,
          orElse: () => const StyioTypeMismatchIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.hint,
              code: '',
              message: '',
              range: SourceRange(start: 0, end: 0),
            ),
            variableName: '',
            expectedTypeName: '',
            actualTypeName: '',
            initializerRange: SourceRange(start: 0, end: 0),
            typeRange: SourceRange(start: 0, end: 0),
            replacementInitializerText: '',
          ),
        );
    if (issue.variableName.isEmpty) {
      return const <DiagnosticQuickFix>[];
    }

    final fixes = <DiagnosticQuickFix>[];
    if (issue.replacementInitializerText.isNotEmpty) {
      fixes.add(
        DiagnosticQuickFix(
          label: 'Change initializer to ${issue.expectedTypeName} literal',
          detail:
              'Rewrite `${issue.variableName}` initializer from '
              '`${issue.actualTypeName}` to `${issue.expectedTypeName}`.',
          edits: [
            FormattingEdit(
              range: issue.initializerRange,
              newText: issue.replacementInitializerText,
            ),
          ],
        ),
      );
    }
    fixes.add(
      DiagnosticQuickFix(
        label:
            'Change local `${issue.variableName}` type to '
            '${issue.actualTypeName}',
        detail:
            'Update `${issue.variableName}` explicit type to match the '
            'initializer type.',
        edits: [
          FormattingEdit(range: issue.typeRange, newText: issue.actualTypeName),
        ],
      ),
    );
    return fixes;
  }

  List<DiagnosticQuickFix> _callArgumentFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final issue = _symbolIndex
        .callArgumentIssues(document.text)
        .firstWhere(
          (item) =>
              item.diagnostic.code == diagnostic.code &&
              item.diagnostic.range.start == diagnostic.range.start &&
              item.diagnostic.range.end == diagnostic.range.end,
          orElse: () => const StyioCallArgumentIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.hint,
              code: '',
              message: '',
              range: SourceRange(start: 0, end: 0),
            ),
            callableName: '',
            expectedArgumentCount: 0,
            actualArgumentCount: 0,
            argumentListRange: SourceRange(start: 0, end: 0),
            replacementArgumentText: '',
          ),
        );
    if (issue.callableName.isEmpty) {
      return const <DiagnosticQuickFix>[];
    }

    if (issue.hasUnknownNamedArgument) {
      final argumentNameRange = issue.argumentNameRange;
      final suggestedParameterName = issue.suggestedParameterName;
      if (argumentNameRange == null || suggestedParameterName == null) {
        return const <DiagnosticQuickFix>[];
      }
      return [
        DiagnosticQuickFix(
          label: 'Change argument name to `$suggestedParameterName`',
          detail:
              'Replace unknown `${issue.namedArgumentName}` argument name '
              'with `${issue.callableName}` parameter '
              '`$suggestedParameterName`.',
          edits: [
            FormattingEdit(
              range: argumentNameRange,
              newText: suggestedParameterName,
            ),
          ],
        ),
      ];
    }

    if (issue.hasDuplicateNamedArgument) {
      return [
        DiagnosticQuickFix(
          label: 'Remove duplicate `${issue.namedArgumentName}` argument',
          detail:
              'Rewrite `${issue.callableName}` call arguments without the '
              'duplicate `${issue.namedArgumentName}` entry.',
          edits: [
            FormattingEdit(
              range: issue.argumentListRange,
              newText: issue.replacementArgumentText,
            ),
          ],
        ),
      ];
    }

    if (issue.hasArgumentTypeMismatch) {
      final fixes = <DiagnosticQuickFix>[];
      final argumentRange = issue.argumentRange;
      if (argumentRange != null && issue.replacementArgumentText.isNotEmpty) {
        fixes.add(
          DiagnosticQuickFix(
            label: 'Change argument to ${issue.expectedTypeName} literal',
            detail:
                'Rewrite `${issue.parameterName}` argument for '
                '`${issue.callableName}` from `${issue.actualTypeName}` to '
                '`${issue.expectedTypeName}`.',
            edits: [
              FormattingEdit(
                range: argumentRange,
                newText: issue.replacementArgumentText,
              ),
            ],
          ),
        );
      }

      final parameterTypeRange = issue.parameterTypeRange;
      if (parameterTypeRange != null) {
        fixes.add(
          DiagnosticQuickFix(
            label:
                'Change parameter `${issue.parameterName}` type to '
                '${issue.actualTypeName}',
            detail:
                'Update `${issue.callableName}` parameter '
                '`${issue.parameterName}` to match the argument type.',
            edits: [
              FormattingEdit(
                range: parameterTypeRange,
                newText: issue.actualTypeName,
              ),
            ],
          ),
        );
      }
      return fixes;
    }

    final isMissing = issue.hasMissingArguments;
    final count = isMissing
        ? issue.missingParameterNames.length
        : issue.extraArgumentCount;
    return [
      DiagnosticQuickFix(
        label: isMissing
            ? 'Insert missing argument${count == 1 ? '' : 's'}'
            : 'Remove extra argument${count == 1 ? '' : 's'}',
        detail: isMissing
            ? 'Append placeholder value${count == 1 ? '' : 's'} for '
                  '`${issue.callableName}` parameter'
                  '${count == 1 ? '' : 's'} '
                  '${issue.missingParameterNames.join(', ')}.'
            : 'Rewrite `${issue.callableName}` call arguments to match the '
                  'current signature.',
        edits: [
          FormattingEdit(
            range: issue.argumentListRange,
            newText: issue.replacementArgumentText,
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _unresolvedResourceFix(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final name = _resourceNameForRange(document.text, diagnostic.range);
    if (name == null) {
      return const <DiagnosticQuickFix>[];
    }
    final resourceType =
        _inferredResourceWriteType(document.text, diagnostic.range) ?? 'i64';

    return [
      DiagnosticQuickFix(
        label: 'Create resource `@$name`',
        detail: 'Declare a Styio resource for this write target.',
        edits: [
          FormattingEdit(
            range: const SourceRange(start: 0, end: 0),
            newText: '@$name : $resourceType|..1| := {}\n',
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _unresolvedTaskAwaitFix(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final name = _identifierTextForRange(document.text, diagnostic.range);
    if (name == null) {
      return const <DiagnosticQuickFix>[];
    }
    final returnType =
        _awaitBindingTypeForTaskRange(document.text, diagnostic.range) ?? 'i64';
    final returnExpression = _defaultReturnExpressionForType(returnType);

    return [
      DiagnosticQuickFix(
        label: 'Create task `$name`',
        detail: 'Declare a Styio task stub for this await expression.',
        edits: [
          FormattingEdit(
            range: const SourceRange(start: 0, end: 0),
            newText: '$name = ||> {\n  <| $returnExpression\n}\n\n',
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _unresolvedReferenceFixes(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final name = _identifierTextForRange(document.text, diagnostic.range);
    if (name == null) {
      return const <DiagnosticQuickFix>[];
    }

    final tokens = _syntaxHighlighter.tokenize(document.text);
    final tokenIndex = _tokenIndexForRange(tokens, diagnostic.range);
    final fixes = <DiagnosticQuickFix>[
      ..._changeToSimilarSymbolFixes(
        tokens,
        name: name,
        range: diagnostic.range,
      ),
    ];

    final functionFix = tokenIndex == null
        ? null
        : _createFunctionFromUsageFix(
            source: document.text,
            tokens: tokens,
            callableIndex: tokenIndex,
            name: name,
          );
    if (functionFix != null) {
      fixes.add(functionFix);
    }

    fixes.add(
      DiagnosticQuickFix(
        label: 'Create local binding `$name`',
        detail: 'Insert a local Styio binding before the unresolved usage.',
        edits: [
          FormattingEdit(
            range: _lineInsertionRange(document.text, diagnostic.range.start),
            newText:
                '${_lineIndentAt(document.text, diagnostic.range.start)}'
                '$name = value\n',
          ),
        ],
      ),
    );
    return fixes;
  }

  List<DiagnosticQuickFix> _changeToSimilarSymbolFixes(
    List<TokenSpan> tokens, {
    required String name,
    required SourceRange range,
  }) {
    final symbolSnapshot = _symbolIndex.build(tokens);
    final candidates = _similarSymbolCandidates(symbolSnapshot, name);
    return [
      for (final candidate in candidates)
        DiagnosticQuickFix(
          label: 'Change to `${candidate.name}`',
          detail:
              'Replace unresolved identifier with current-file '
              '${candidate.kind.name} `${candidate.name}`.',
          edits: [FormattingEdit(range: range, newText: candidate.name)],
        ),
    ];
  }

  List<DocumentSymbol> _similarSymbolCandidates(
    StyioSymbolSnapshot symbolSnapshot,
    String name,
  ) {
    final seenNames = <String>{};
    final candidates = <_SimilarSymbolCandidate>[];
    for (final symbol in symbolSnapshot.symbols) {
      if (!seenNames.add(symbol.name) || symbol.name == name) {
        continue;
      }
      final score = _symbolSimilarityScore(name, symbol.name);
      if (score == null) {
        continue;
      }
      candidates.add(_SimilarSymbolCandidate(symbol: symbol, score: score));
    }
    candidates.sort((left, right) {
      final scoreCompare = left.score.compareTo(right.score);
      if (scoreCompare != 0) {
        return scoreCompare;
      }
      final nameCompare = left.symbol.name.compareTo(right.symbol.name);
      if (nameCompare != 0) {
        return nameCompare;
      }
      return left.symbol.nameRange.start.compareTo(
        right.symbol.nameRange.start,
      );
    });
    return candidates
        .take(3)
        .map((candidate) => candidate.symbol)
        .toList(growable: false);
  }

  int? _symbolSimilarityScore(String unresolved, String candidate) {
    final left = unresolved.toLowerCase();
    final right = candidate.toLowerCase();
    if (left == right) {
      return 0;
    }
    if (left.length < 3 || right.length < 3) {
      return null;
    }
    if (right.startsWith(left) || left.startsWith(right)) {
      return 1 + (left.length - right.length).abs();
    }
    if (right.contains(left) || left.contains(right)) {
      return 3 + (left.length - right.length).abs();
    }

    final distance = _editDistance(left, right);
    final limit = left.length < 8 && right.length < 8 ? 1 : 2;
    if (distance > limit) {
      return null;
    }
    return 8 + distance;
  }

  int _editDistance(String left, String right) {
    var previous = List<int>.generate(right.length + 1, (index) => index);
    for (var leftIndex = 0; leftIndex < left.length; leftIndex += 1) {
      final current = List<int>.filled(right.length + 1, leftIndex + 1);
      for (var rightIndex = 0; rightIndex < right.length; rightIndex += 1) {
        final substitutionCost =
            left.codeUnitAt(leftIndex) == right.codeUnitAt(rightIndex) ? 0 : 1;
        current[rightIndex + 1] = [
          current[rightIndex] + 1,
          previous[rightIndex + 1] + 1,
          previous[rightIndex] + substitutionCost,
        ].reduce((value, element) => value < element ? value : element);
      }
      previous = current;
    }
    return previous.last;
  }

  DiagnosticQuickFix? _createFunctionFromUsageFix({
    required String source,
    required List<TokenSpan> tokens,
    required int callableIndex,
    required String name,
  }) {
    final openingIndex = _nextSignificantIndex(tokens, callableIndex + 1);
    if (openingIndex == null || tokens[openingIndex].lexeme != '(') {
      return null;
    }
    final closingIndex = _matchingParenthesisIndex(tokens, openingIndex);
    if (closingIndex == null) {
      return null;
    }

    final parameters = _parameterNamesForCallArguments(
      source: source,
      tokens: tokens,
      openingIndex: openingIndex,
      closingIndex: closingIndex,
    );
    final declaration = StringBuffer()
      ..write('#')
      ..write(name)
      ..write(' := (')
      ..write(parameters.join(', '))
      ..writeln(') => {')
      ..writeln('  <| value')
      ..writeln('}')
      ..writeln();

    return DiagnosticQuickFix(
      label: 'Create function `$name`',
      detail:
          'Insert a current-file Styio function stub from the unresolved call.',
      edits: [
        FormattingEdit(
          range: _topLevelInsertionRangeAfterImports(source),
          newText: declaration.toString(),
        ),
      ],
    );
  }

  List<String> _parameterNamesForCallArguments({
    required String source,
    required List<TokenSpan> tokens,
    required int openingIndex,
    required int closingIndex,
  }) {
    final parameters = <String>[];
    final seen = <String>{};
    var segmentStart = tokens[openingIndex].range.end;
    var nestedDepth = 0;

    String nextFallbackName() {
      var ordinal = parameters.length + 1;
      var candidate = 'arg$ordinal';
      while (seen.contains(candidate) || !_isValidIdentifier(candidate)) {
        ordinal += 1;
        candidate = 'arg$ordinal';
      }
      return candidate;
    }

    void addArgument(int segmentEnd) {
      final range = _trimmedRange(
        source,
        SourceRange(start: segmentStart, end: segmentEnd),
      );
      if (range.isCollapsed) {
        return;
      }
      var candidate = source.substring(range.start, range.end);
      if (!_isValidIdentifier(candidate) || seen.contains(candidate)) {
        candidate = nextFallbackName();
      }
      seen.add(candidate);
      parameters.add(candidate);
    }

    for (var index = openingIndex + 1; index < closingIndex; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.punctuation && token.lexeme == '(') {
        nestedDepth += 1;
        continue;
      }
      if (token.kind == TokenKind.punctuation && token.lexeme == ')') {
        nestedDepth -= 1;
        continue;
      }
      if (nestedDepth == 0 && token.lexeme == ',') {
        addArgument(token.range.start);
        segmentStart = token.range.end;
      }
    }

    addArgument(tokens[closingIndex].range.start);
    return parameters;
  }

  SourceRange _topLevelInsertionRangeAfterImports(String source) {
    var insertionOffset = 0;
    var cursor = 0;
    while (cursor < source.length) {
      final lineEnd = source.indexOf('\n', cursor);
      final end = lineEnd < 0 ? source.length : lineEnd;
      final line = source.substring(cursor, end).trimLeft();
      if (!line.startsWith('@import')) {
        break;
      }
      insertionOffset = lineEnd < 0 ? source.length : lineEnd + 1;
      cursor = insertionOffset;
    }
    return SourceRange(start: insertionOffset, end: insertionOffset);
  }

  int? _tokenIndexForRange(List<TokenSpan> tokens, SourceRange range) {
    for (var index = 0; index < tokens.length; index += 1) {
      if (tokens[index].range.start == range.start &&
          tokens[index].range.end == range.end) {
        return index;
      }
    }
    return null;
  }

  int? _matchingParenthesisIndex(List<TokenSpan> tokens, int openingIndex) {
    var depth = 0;
    for (var index = openingIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.punctuation && token.lexeme == '(') {
        depth += 1;
        continue;
      }
      if (token.kind == TokenKind.punctuation && token.lexeme == ')') {
        depth -= 1;
        if (depth == 0) {
          return index;
        }
      }
    }
    return null;
  }

  String? _resourceNameForRange(String source, SourceRange range) {
    final text = _textForRange(source, range)?.trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    final name = text.startsWith('@') ? text.substring(1).trim() : text;
    return _isValidIdentifier(name) ? name : null;
  }

  String? _identifierTextForRange(String source, SourceRange range) {
    final text = _textForRange(source, range)?.trim();
    if (text == null || !_isValidIdentifier(text)) {
      return null;
    }
    return text;
  }

  String? _textForRange(String source, SourceRange range) {
    if (range.start < 0 ||
        range.end > source.length ||
        range.start >= range.end) {
      return null;
    }
    return source.substring(range.start, range.end);
  }

  String? _inferredResourceWriteType(String source, SourceRange resourceRange) {
    if (resourceRange.start < 0 || resourceRange.start > source.length) {
      return null;
    }
    final lineStart = source.lastIndexOf('\n', resourceRange.start - 1) + 1;
    final lineEndIndex = source.indexOf('\n', resourceRange.end);
    final lineEnd = lineEndIndex < 0 ? source.length : lineEndIndex;
    final arrow = source.lastIndexOf('->', resourceRange.start);
    if (arrow < lineStart || arrow >= lineEnd) {
      return null;
    }
    final expression = source.substring(lineStart, arrow).trim();
    if (expression.isEmpty) {
      return null;
    }
    final localTypes = _localBindingTypesBefore(source, lineStart);
    return _inferSimpleExpressionType(expression, localTypes);
  }

  Map<String, String> _localBindingTypesBefore(String source, int offset) {
    final localTypes = <String, String>{};
    var lineStart = 0;
    while (lineStart < offset && lineStart < source.length) {
      final newline = source.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? source.length : newline;
      if (lineEnd >= offset) {
        break;
      }
      final line = source.substring(lineStart, lineEnd);
      final match = RegExp(
        r'^\s*([A-Za-z_][A-Za-z0-9_]*)\s*(?::\s*([A-Za-z][A-Za-z0-9_]*))?\s*=\s*(.+)$',
      ).firstMatch(line);
      if (match != null && !line.contains('||>')) {
        final name = match.group(1)!;
        final explicitType = match.group(2);
        final initializer = match.group(3)!.trim();
        final inferredType =
            explicitType ?? _inferSimpleExpressionType(initializer, localTypes);
        if (inferredType != null) {
          localTypes[name] = inferredType;
        }
      }
      if (newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }
    return localTypes;
  }

  String? _inferSimpleExpressionType(
    String expression,
    Map<String, String> localTypes,
  ) {
    final trimmed = expression.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      return 'string';
    }
    if (trimmed == 'true' || trimmed == 'false') {
      return 'bool';
    }
    if (RegExp(r'^[+-]?\d+\.\d+$').hasMatch(trimmed)) {
      return 'f64';
    }
    if (RegExp(r'^[+-]?\d+$').hasMatch(trimmed)) {
      return 'i64';
    }
    if (_isValidIdentifier(trimmed)) {
      return localTypes[trimmed];
    }
    final operatorMatch = RegExp(r'\s[+\-*/]\s').firstMatch(trimmed);
    if (operatorMatch != null) {
      final left = trimmed.substring(0, operatorMatch.start).trim();
      final right = trimmed.substring(operatorMatch.end).trim();
      final leftType = _inferSimpleExpressionType(left, localTypes);
      final rightType = _inferSimpleExpressionType(right, localTypes);
      if (leftType == null || rightType == null) {
        return null;
      }
      if ((leftType == 'i64' || leftType == 'f64') &&
          (rightType == 'i64' || rightType == 'f64')) {
        return leftType == 'f64' || rightType == 'f64' ? 'f64' : 'i64';
      }
    }
    return null;
  }

  String? _awaitBindingTypeForTaskRange(String source, SourceRange taskRange) {
    if (taskRange.start < 0 ||
        taskRange.end > source.length ||
        taskRange.start >= taskRange.end) {
      return null;
    }
    final lineEndIndex = source.indexOf('\n', taskRange.end);
    final lineEnd = lineEndIndex < 0 ? source.length : lineEndIndex;
    final colon = source.indexOf(':', taskRange.end);
    if (colon < 0 || colon >= lineEnd) {
      return null;
    }
    var typeStart = colon + 1;
    while (typeStart < lineEnd && source.codeUnitAt(typeStart) <= 0x20) {
      typeStart += 1;
    }
    var typeEnd = typeStart;
    while (typeEnd < lineEnd &&
        _isIdentifierCodeUnit(source.codeUnitAt(typeEnd))) {
      typeEnd += 1;
    }
    if (typeStart >= typeEnd) {
      return null;
    }
    return source.substring(typeStart, typeEnd);
  }

  String? _awaitBindingTypeForTaskName(String source, String taskName) {
    final awaitPattern = RegExp(
      r'\?\|\s*' +
          RegExp.escape(taskName) +
          r'\s*->\s*[A-Za-z_][A-Za-z0-9_]*\s*:\s*([A-Za-z_][A-Za-z0-9_]*)',
    );
    return awaitPattern.firstMatch(source)?.group(1);
  }

  String _defaultReturnExpressionForType(String returnType) {
    final normalized = returnType.trim();
    if (normalized == 'bool') {
      return 'false';
    }
    if (normalized == 'string' || normalized == 'String') {
      return '""';
    }
    if (normalized.startsWith('f')) {
      return '0.0';
    }
    if (normalized.startsWith('i') || normalized.startsWith('u')) {
      return '0';
    }
    return 'value';
  }

  bool _isIdentifierCodeUnit(int codeUnit) {
    return (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
        (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        codeUnit == 0x5f;
  }

  bool _isValidIdentifier(String value) {
    if (value.isEmpty ||
        _syntaxHighlighter.isKeyword(value) ||
        _syntaxHighlighter.isTypeName(value)) {
      return false;
    }
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
  }

  List<DiagnosticQuickFix> _redundantTypeAnnotationFix(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    for (final plan in _symbolIndex.redundantExplicitTypePlans(document.text)) {
      if (plan.typeRange.start != diagnostic.range.start ||
          plan.typeRange.end != diagnostic.range.end) {
        continue;
      }
      return [
        DiagnosticQuickFix(
          label: 'Remove redundant type annotation',
          detail:
              'Remove `${plan.typeName}` from `${plan.variableName}` because Styio inference preserves it.',
          edits: [plan.edit],
        ),
      ];
    }
    return const <DiagnosticQuickFix>[];
  }

  List<DiagnosticQuickFix> _importOptimizationFix(DocumentState document) {
    final plan = _importOptimizationPlan(document.text);
    if (plan == null || !plan.needsOptimization || plan.edits.isEmpty) {
      return const <DiagnosticQuickFix>[];
    }
    return [
      DiagnosticQuickFix(
        label: 'Optimize imports',
        detail: 'Sort Styio imports and remove duplicate declarations.',
        edits: plan.edits,
      ),
    ];
  }

  _StyioImportOptimization? _importOptimizationPlan(String source) {
    final imports = _topLevelImportLines(source);
    if (imports.isEmpty) {
      return null;
    }

    final firstByTarget = <String, _StyioImportLine>{};
    final duplicateImports = <_StyioImportLine>[];
    for (final importLine in imports) {
      final previous = firstByTarget[importLine.target];
      if (previous == null) {
        firstByTarget[importLine.target] = importLine;
      } else {
        duplicateImports.add(importLine);
      }
    }

    final optimizedTargets = firstByTarget.keys.toList(growable: false)
      ..sort(_compareImportTargets);
    final optimizedLines = [
      for (final target in optimizedTargets) '@import { $target }',
    ];
    final optimizedText =
        optimizedLines.join('\n') +
        (_importReplacementNeedsTrailingNewline(source, imports) ? '\n' : '');
    final currentTargets = imports
        .map((importLine) => importLine.target)
        .toList(growable: false);
    final canonicalLines = imports.every(
      (importLine) => importLine.lineText == '@import { ${importLine.target} }',
    );
    final needsOptimization =
        duplicateImports.isNotEmpty ||
        !canonicalLines ||
        currentTargets.length != optimizedTargets.length ||
        !_sameStringList(currentTargets, optimizedTargets);

    return _StyioImportOptimization(
      imports: imports,
      duplicateImports: duplicateImports,
      needsOptimization: needsOptimization,
      edits: needsOptimization
          ? [
              FormattingEdit(
                range: imports.first.lineRemovalRange,
                newText: optimizedText,
              ),
              for (final importLine in imports.skip(1))
                FormattingEdit(range: importLine.lineRemovalRange, newText: ''),
            ]
          : const <FormattingEdit>[],
    );
  }

  List<_StyioImportLine> _topLevelImportLines(String source) {
    final imports = <_StyioImportLine>[];
    var lineStart = 0;
    while (lineStart <= source.length) {
      final newline = source.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? source.length : newline;
      final rawLine = source.substring(lineStart, lineEnd);
      final lineText = rawLine.replaceFirst(RegExp(r'\s+$'), '');
      if (lineText.startsWith('@import')) {
        final target = _importTargetFromLine(lineText);
        if (target != null && target.isNotEmpty) {
          imports.add(
            _StyioImportLine(
              target: target,
              lineText: lineText,
              lineContentRange: SourceRange(start: lineStart, end: lineEnd),
              lineRemovalRange: SourceRange(
                start: lineStart,
                end: newline < 0 ? lineEnd : newline + 1,
              ),
            ),
          );
        }
      }

      if (newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }
    return imports;
  }

  String? _importTargetFromLine(String lineText) {
    final openBrace = lineText.indexOf('{');
    final closeBrace = lineText.lastIndexOf('}');
    if (openBrace >= 0 && closeBrace > openBrace) {
      return lineText.substring(openBrace + 1, closeBrace).trim();
    }
    return lineText.replaceFirst('@import', '').trim();
  }

  int _compareImportTargets(String left, String right) {
    final lowerCompare = left.toLowerCase().compareTo(right.toLowerCase());
    return lowerCompare == 0 ? left.compareTo(right) : lowerCompare;
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

  bool _importReplacementNeedsTrailingNewline(
    String source,
    List<_StyioImportLine> imports,
  ) {
    if (imports.length > 1) {
      return true;
    }
    final first = imports.first;
    return first.lineRemovalRange.end > first.lineContentRange.end ||
        source.length > first.lineRemovalRange.end;
  }

  List<DiagnosticQuickFix> _unusedParameterFix(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final issue = _symbolIndex
        .unusedParameterIssues(document.text)
        .firstWhere(
          (item) =>
              item.diagnostic.range.start == diagnostic.range.start &&
              item.diagnostic.range.end == diagnostic.range.end,
          orElse: () => const StyioUnusedParameterIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.hint,
              code: '',
              message: '',
              range: SourceRange(start: 0, end: 0),
            ),
            functionName: '',
            parameterName: '',
            edits: <FormattingEdit>[],
          ),
        );
    if (issue.parameterName.isEmpty || issue.edits.isEmpty) {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: 'Remove unused parameter',
        detail:
            'Remove `${issue.parameterName}` from `${issue.functionName}` and '
            'rewrite current-file call arguments.',
        edits: issue.edits,
      ),
    ];
  }

  List<DiagnosticQuickFix> _duplicateResourceOrTaskFix(
    DocumentState document,
    Diagnostic diagnostic, {
    required String kind,
  }) {
    if (diagnostic.range.start < 0 ||
        diagnostic.range.end > document.text.length ||
        diagnostic.range.start >= diagnostic.range.end) {
      return const <DiagnosticQuickFix>[];
    }

    return [
      DiagnosticQuickFix(
        label: 'Remove duplicate $kind declaration',
        detail: 'Delete the duplicate Styio $kind declaration.',
        edits: [
          FormattingEdit(
            range: _declarationRemovalRange(document.text, diagnostic.range),
            newText: '',
          ),
        ],
      ),
    ];
  }

  List<DiagnosticQuickFix> _unusedLocalSymbolFix(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    final lineRemovalRange = _lineRemovalRange(document.text, diagnostic.range);
    final lineText = document.text.substring(
      lineRemovalRange.start,
      lineRemovalRange.end,
    );
    final isAwaitResultBinding =
        lineText.contains('?|') &&
        lineText.contains('->') &&
        lineText.contains(':');
    final isTaskDeclaration = lineText.contains('||>');
    final removalRange = isTaskDeclaration
        ? _taskDeclarationRemovalRange(document.text, diagnostic.range)
        : lineRemovalRange;
    final label = isAwaitResultBinding
        ? 'Remove unused await result binding'
        : isTaskDeclaration
        ? 'Remove unused task declaration'
        : 'Remove unused declaration';
    final detail = isAwaitResultBinding
        ? 'Delete the await line whose result binding is never used.'
        : isTaskDeclaration
        ? 'Delete the local task declaration that is never awaited.'
        : 'Delete the unused local binding line.';
    return [
      DiagnosticQuickFix(
        label: label,
        detail: detail,
        edits: [FormattingEdit(range: removalRange, newText: '')],
      ),
    ];
  }

  SourceRange _lineRemovalRange(String source, SourceRange range) {
    var start = range.start.clamp(0, source.length);
    while (start > 0 && source[start - 1] != '\n') {
      start -= 1;
    }

    var end = range.end.clamp(start, source.length);
    while (end < source.length && source[end] != '\n') {
      end += 1;
    }
    if (end < source.length && source[end] == '\n') {
      end += 1;
    } else if (start > 0 && source[start - 1] == '\n') {
      start -= 1;
    }
    return SourceRange(start: start, end: end);
  }

  SourceRange _declarationRemovalRange(String source, SourceRange range) {
    final lineRange = _lineRemovalRange(source, range);
    final lineEnd = source.indexOf('\n', range.end);
    final declarationLineEnd = lineEnd < 0 ? source.length : lineEnd;
    final lineText = source.substring(lineRange.start, declarationLineEnd);
    if (!lineText.contains('||>')) {
      return lineRange;
    }
    return _taskDeclarationRemovalRange(source, range);
  }

  SourceRange _taskDeclarationRemovalRange(
    String source,
    SourceRange declarationRange,
  ) {
    final firstLineRange = _lineRemovalRange(source, declarationRange);
    final tokens = _syntaxHighlighter.tokenize(source);
    final openingBraceIndex = tokens.indexWhere(
      (token) =>
          token.range.start >= firstLineRange.start &&
          token.range.start < firstLineRange.end &&
          token.lexeme == '{',
    );
    if (openingBraceIndex < 0) {
      return firstLineRange;
    }

    var depth = 0;
    for (var index = openingBraceIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.lexeme == '{') {
        depth += 1;
        continue;
      }
      if (token.lexeme == '}') {
        depth -= 1;
        if (depth == 0) {
          final closingLineRange = _lineRemovalRange(source, token.range);
          return SourceRange(
            start: firstLineRange.start,
            end: closingLineRange.end,
          );
        }
      }
    }
    return firstLineRange;
  }
}

String _lineEndingFor(String source) {
  return source.contains('\r\n') ? '\r\n' : '\n';
}

class _StyioImportLine {
  const _StyioImportLine({
    required this.target,
    required this.lineText,
    required this.lineContentRange,
    required this.lineRemovalRange,
  });

  final String target;
  final String lineText;
  final SourceRange lineContentRange;
  final SourceRange lineRemovalRange;
}

class _StyioImportOptimization {
  const _StyioImportOptimization({
    required this.imports,
    required this.duplicateImports,
    required this.needsOptimization,
    required this.edits,
  });

  final List<_StyioImportLine> imports;
  final List<_StyioImportLine> duplicateImports;
  final bool needsOptimization;
  final List<FormattingEdit> edits;
}

class _BooleanBinarySplit {
  const _BooleanBinarySplit({
    required this.left,
    required this.operatorLexeme,
    required this.right,
  });

  final String left;
  final String operatorLexeme;
  final String right;
}

class _SimilarSymbolCandidate {
  const _SimilarSymbolCandidate({required this.symbol, required this.score});

  final DocumentSymbol symbol;
  final int score;
}
