import '../contract/language_contract.dart';
import '../semantic/styio_symbol_index.dart';
import '../semantic/styio_task_return_inference.dart';
import '../syntax_validation/syntax_validation.dart';

class StyioCompilerDiagnostics {
  const StyioCompilerDiagnostics({
    StyioSymbolIndex symbolIndex = const StyioSymbolIndex(),
    StyioSyntaxValidator syntaxValidator = const StyioSyntaxValidator(),
  }) : _symbolIndex = symbolIndex,
       _syntaxValidator = syntaxValidator;

  static const _taskReturnInference = StyioTaskReturnInference();

  final StyioSymbolIndex _symbolIndex;
  final StyioSyntaxValidator _syntaxValidator;

  List<Diagnostic> analyze({
    required String source,
    required List<TokenSpan> tokens,
  }) {
    final declarations = _declarationModel(source);
    return [
      ..._syntaxValidator.validate(source: source, tokens: tokens),
      ..._declarationDiagnostics(declarations),
      ..._resolverDiagnostics(source),
      ..._typeDiagnostics(source),
      ..._controlFlowDiagnostics(source),
      ..._resourceDiagnostics(source, declarations),
      ..._taskDiagnostics(source, declarations),
    ];
  }

  List<Diagnostic> _declarationDiagnostics(
    _StyioDeclarationModel declarations,
  ) {
    return [
      ..._duplicateFunctionDeclarationDiagnostics(declarations),
      ..._duplicateResourceDeclarationDiagnostics(declarations),
      ..._duplicateTaskDeclarationDiagnostics(declarations),
      ..._duplicateParameterDeclarationDiagnostics(declarations),
      ..._missingTaskReturnValueDiagnostics(declarations),
      ..._unresolvedTaskReturnValueDiagnostics(declarations),
      ..._invalidTaskReturnExpressionDiagnostics(declarations),
      ..._taskReturnTypeMismatchDiagnostics(declarations),
    ];
  }

  List<Diagnostic> _duplicateFunctionDeclarationDiagnostics(
    _StyioDeclarationModel declarations,
  ) {
    final diagnostics = <Diagnostic>[];
    for (final declaration in declarations.duplicateFunctions) {
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'duplicate-function-declaration',
          message:
              'Function `${declaration.name}` is already declared in this document.',
          range: declaration.range,
        ),
      );
    }
    return diagnostics;
  }

  List<Diagnostic> _duplicateResourceDeclarationDiagnostics(
    _StyioDeclarationModel declarations,
  ) {
    final diagnostics = <Diagnostic>[];
    for (final declaration in declarations.duplicateResources) {
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'duplicate-resource-declaration',
          message:
              'Resource `@${declaration.name}` is already declared in this document.',
          range: declaration.range,
        ),
      );
    }
    return diagnostics;
  }

  List<Diagnostic> _duplicateTaskDeclarationDiagnostics(
    _StyioDeclarationModel declarations,
  ) {
    final diagnostics = <Diagnostic>[];
    for (final declaration in declarations.duplicateTasks) {
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'duplicate-task-declaration',
          message:
              'Task `${declaration.name}` is already declared in this document.',
          range: declaration.range,
        ),
      );
    }
    return diagnostics;
  }

  List<Diagnostic> _taskReturnTypeMismatchDiagnostics(
    _StyioDeclarationModel declarations,
  ) {
    final diagnostics = <Diagnostic>[];
    for (final task in declarations.tasks.values) {
      final returnValues = [
        ...task.returnValues,
        ...task.conditionalReturnValues,
      ];
      if (returnValues.length < 2) {
        continue;
      }
      final first = returnValues.first;
      for (final value in returnValues.skip(1)) {
        if (_areReturnTypesCompatible(first.type, value.type)) {
          continue;
        }
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'task-return-type-mismatch',
            message:
                'Task `${task.name}` returns both `${first.type}` and '
                '`${value.type}`.',
            range: value.range,
          ),
        );
      }
    }
    return diagnostics;
  }

  List<Diagnostic> _missingTaskReturnValueDiagnostics(
    _StyioDeclarationModel declarations,
  ) {
    final diagnostics = <Diagnostic>[];
    for (final task in [
      ...declarations.tasks.values,
      ...declarations.duplicateTasks,
    ]) {
      for (final range in task.missingReturnValueRanges) {
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'missing-task-return-value',
            message: 'Task `${task.name}` has a return operator with no value.',
            range: range,
          ),
        );
      }
    }
    return diagnostics;
  }

  List<Diagnostic> _unresolvedTaskReturnValueDiagnostics(
    _StyioDeclarationModel declarations,
  ) {
    final diagnostics = <Diagnostic>[];
    for (final task in [
      ...declarations.tasks.values,
      ...declarations.duplicateTasks,
    ]) {
      for (final value in task.unresolvedReturnValues) {
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'unresolved-task-return-value',
            message:
                'Task `${task.name}` returns unresolved value '
                '`${value.expression}`.',
            range: value.range,
          ),
        );
      }
    }
    return diagnostics;
  }

  List<Diagnostic> _invalidTaskReturnExpressionDiagnostics(
    _StyioDeclarationModel declarations,
  ) {
    final diagnostics = <Diagnostic>[];
    for (final task in [
      ...declarations.tasks.values,
      ...declarations.duplicateTasks,
    ]) {
      for (final expression in task.invalidReturnExpressions) {
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'invalid-task-return-expression',
            message:
                'Task `${task.name}` returns an expression whose type cannot '
                'be inferred.',
            range: expression.range,
          ),
        );
      }
    }
    return diagnostics;
  }

  List<Diagnostic> _duplicateParameterDeclarationDiagnostics(
    _StyioDeclarationModel declarations,
  ) {
    final diagnostics = <Diagnostic>[];
    for (final declaration in declarations.duplicateParameters) {
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'duplicate-parameter-declaration',
          message:
              'Parameter `${declaration.name}` is already declared in this function.',
          range: declaration.range,
        ),
      );
    }
    return diagnostics;
  }

  List<Diagnostic> _resolverDiagnostics(String source) {
    return [
      ..._symbolIndex
          .callArgumentIssues(source)
          .map((issue) => issue.diagnostic),
      ..._symbolIndex
          .unusedParameterIssues(source)
          .map((issue) => issue.diagnostic),
    ];
  }

  List<Diagnostic> _typeDiagnostics(String source) {
    return [
      ..._symbolIndex
          .typedLocalInitializerIssues(source)
          .map((issue) => issue.diagnostic),
      ..._symbolIndex
          .assignmentTypeMismatchIssues(source)
          .map((issue) => issue.diagnostic),
      ..._symbolIndex
          .binaryOperatorTypeIssues(source)
          .map((issue) => issue.diagnostic),
      ..._symbolIndex
          .unaryOperatorTypeIssues(source)
          .map((issue) => issue.diagnostic),
      ..._symbolIndex
          .conditionTypeMismatchIssues(source)
          .map((issue) => issue.diagnostic),
      ..._symbolIndex
          .functionReturnTypeIssues(source)
          .map((issue) => issue.diagnostic),
    ];
  }

  List<Diagnostic> _controlFlowDiagnostics(String source) {
    final diagnostics = <Diagnostic>[];
    final pattern = RegExp(
      r'\bfn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*(?::\s*([^{\n]+?))?\s*\{',
    );
    for (final match in pattern.allMatches(source)) {
      if (_isOffsetInIgnoredText(source, match.start)) {
        continue;
      }
      final returnType = match.group(2)?.trim();
      if (returnType == null || returnType.isEmpty || returnType == 'void') {
        continue;
      }
      final openingBrace = source.lastIndexOf('{', match.end - 1);
      final closingBrace = _matchingBrace(source, openingBrace);
      if (openingBrace < 0 || closingBrace == null) {
        continue;
      }
      final body = source.substring(openingBrace + 1, closingBrace);
      if (!_bodyHasTopLevelValueReturn(body)) {
        final nameStart =
            match.start + match.group(0)!.indexOf(match.group(1)!);
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'missing-function-return',
            message:
                'Function `${match.group(1)}` declares return type `$returnType` '
                'but does not return a value.',
            range: SourceRange(
              start: nameStart,
              end: nameStart + match.group(1)!.length,
            ),
          ),
        );
      }
      diagnostics.addAll(
        _unreachableCodeDiagnostics(
          body: body,
          bodyStartOffset: openingBrace + 1,
        ),
      );
    }
    final hashFunctionPattern = RegExp(
      r'#\s*([A-Za-z_][A-Za-z0-9_]*)\s*:=\s*\([^)]*\)\s*(?::\s*([^=\n{]+?))?\s*=>\s*\{',
    );
    for (final match in hashFunctionPattern.allMatches(source)) {
      if (_isOffsetInIgnoredText(source, match.start)) {
        continue;
      }
      final openingBrace = source.lastIndexOf('{', match.end - 1);
      final closingBrace = _matchingBrace(source, openingBrace);
      if (openingBrace < 0 || closingBrace == null) {
        continue;
      }
      final body = source.substring(openingBrace + 1, closingBrace);
      final returnType = match.group(2)?.trim();
      if (returnType != null &&
          returnType.isNotEmpty &&
          returnType != 'void' &&
          !_bodyHasTopLevelValueReturn(body)) {
        final name = match.group(1)!;
        final nameStart = match.start + match.group(0)!.indexOf(name);
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'missing-function-return',
            message:
                'Function `$name` declares return type `$returnType` '
                'but does not return a value.',
            range: SourceRange(start: nameStart, end: nameStart + name.length),
          ),
        );
      }
      diagnostics.addAll(
        _unreachableCodeDiagnostics(
          body: body,
          bodyStartOffset: openingBrace + 1,
        ),
      );
    }
    final taskPattern = RegExp(r'\|\|>\s*\{');
    for (final match in taskPattern.allMatches(source)) {
      if (_isOffsetInIgnoredText(source, match.start)) {
        continue;
      }
      final openingBrace = source.lastIndexOf('{', match.end - 1);
      final closingBrace = _matchingBrace(source, openingBrace);
      if (openingBrace < 0 || closingBrace == null) {
        continue;
      }
      final body = source.substring(openingBrace + 1, closingBrace);
      diagnostics.addAll(
        _unreachableCodeDiagnostics(
          body: body,
          bodyStartOffset: openingBrace + 1,
          returnOwner: 'task',
        ),
      );
    }
    diagnostics.addAll(_constantFalseGuardDiagnostics(source));
    return diagnostics;
  }

  List<Diagnostic> _constantFalseGuardDiagnostics(String source) {
    final diagnostics = <Diagnostic>[];
    var lineStart = 0;
    while (lineStart <= source.length) {
      final newline = source.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? source.length : newline;
      final line = source.substring(lineStart, lineEnd);
      final trimmedLeft = line.trimLeft();
      final leadingWhitespace = line.length - trimmedLeft.length;
      final whenOffset = lineStart + leadingWhitespace;
      if (trimmedLeft.startsWith('when ') &&
          !_isOffsetInIgnoredText(source, whenOffset)) {
        final arrowIndex = _topLevelArrowIndex(line, leadingWhitespace);
        if (arrowIndex != null) {
          final condition = line.substring(
            leadingWhitespace + 'when '.length,
            arrowIndex,
          );
          final actionStart = _firstNonWhitespaceOffset(line, arrowIndex + 2);
          if (_isAlwaysFalseWhenCondition(condition) && actionStart != null) {
            final blockOpeningIndex = _topLevelCharacterIndex(
              line,
              arrowIndex + 2,
              '{',
            );
            final diagnosticEnd = blockOpeningIndex == null
                ? lineEnd
                : (_matchingBrace(source, lineStart + blockOpeningIndex) ??
                          lineEnd - 1) +
                      1;
            diagnostics.add(
              Diagnostic(
                severity: DiagnosticSeverity.warning,
                code: 'unreachable-code',
                message:
                    'Code guarded by an always-false `when` is unreachable.',
                range: SourceRange(
                  start: lineStart + actionStart,
                  end: diagnosticEnd,
                ),
              ),
            );
          }
        }
      }
      if (newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }
    return diagnostics;
  }

  List<Diagnostic> _resourceDiagnostics(
    String source,
    _StyioDeclarationModel declarations,
  ) {
    final localTypes = _localValueTypes(source);
    final diagnostics = <Diagnostic>[];
    var lineStart = 0;
    while (lineStart <= source.length) {
      final newline = source.indexOf('\n', lineStart);
      final lineEnd = newline < 0 ? source.length : newline;
      final line = source.substring(lineStart, lineEnd);
      final arrowIndex = line.indexOf('->');
      if (arrowIndex >= 0) {
        if (_isOffsetInIgnoredText(source, lineStart + arrowIndex)) {
          if (newline < 0) {
            break;
          }
          lineStart = newline + 1;
          continue;
        }
        final targetMatch = RegExp(
          r'@\s*([A-Za-z_][A-Za-z0-9_]*)',
        ).firstMatch(line.substring(arrowIndex + 2));
        if (targetMatch != null) {
          final targetName = targetMatch.group(1)!;
          final targetStart =
              lineStart +
              arrowIndex +
              2 +
              targetMatch.start +
              targetMatch.group(0)!.indexOf(targetName);
          final expression = line.substring(0, arrowIndex).trim();
          if (targetName == 'stdin') {
            diagnostics.add(
              Diagnostic(
                severity: DiagnosticSeverity.error,
                code: 'read-only-resource-write',
                message:
                    'Resource `@stdin` is read-only and cannot be used as a sink.',
                range: SourceRange(
                  start: targetStart,
                  end: targetStart + targetName.length,
                ),
              ),
            );
          } else if (!_isStandardWritableResource(targetName) &&
              !declarations.resources.containsKey(targetName)) {
            diagnostics.add(
              Diagnostic(
                severity: DiagnosticSeverity.error,
                code: 'unresolved-resource',
                message:
                    'Resource `@$targetName` is not declared in this document.',
                range: SourceRange(
                  start: targetStart,
                  end: targetStart + targetName.length,
                ),
              ),
            );
          } else {
            final declaration = declarations.resources[targetName];
            final actualType = _inferExpressionType(expression, localTypes);
            if (declaration != null &&
                actualType != null &&
                !_isAssignable(
                  actualType: actualType,
                  expectedType: declaration.type,
                )) {
              diagnostics.add(
                Diagnostic(
                  severity: DiagnosticSeverity.error,
                  code: 'resource-write-type-mismatch',
                  message:
                      'Resource `@$targetName` expects `${declaration.type}` '
                      'but receives `$actualType`.',
                  range: SourceRange(
                    start: lineStart,
                    end: lineStart + arrowIndex,
                  ),
                ),
              );
            }
          }
        }
      }
      if (newline < 0) {
        break;
      }
      lineStart = newline + 1;
    }
    return diagnostics;
  }

  List<Diagnostic> _taskDiagnostics(
    String source,
    _StyioDeclarationModel declarations,
  ) {
    final tasks = declarations.tasks;
    final localTypes = _localValueTypes(source);
    final diagnostics = <Diagnostic>[];
    final pattern = RegExp(
      r'\?\|\s*([A-Za-z_][A-Za-z0-9_]*)\s*->\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z][A-Za-z0-9_]*)(?:\s*\|\s*([^\n]+))?',
    );
    for (final match in pattern.allMatches(source)) {
      if (_isOffsetInIgnoredText(source, match.start)) {
        continue;
      }
      final taskName = match.group(1)!;
      final bindingName = match.group(2)!;
      final expectedType = match.group(3)!;
      final task = tasks[taskName];
      final taskNameStart = match.start + match.group(0)!.indexOf(taskName);
      if (task == null) {
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'unresolved-task-await',
            message: 'Await target `$taskName` is not a declared Styio task.',
            range: SourceRange(
              start: taskNameStart,
              end: taskNameStart + taskName.length,
            ),
          ),
        );
        continue;
      }
      if (task.returnType == null) {
        if (task.unresolvedReturnValues.isNotEmpty ||
            task.invalidReturnExpressions.isNotEmpty) {
          continue;
        }
        final hasOnlyConditionalReturns =
            task.conditionalReturnRanges.isNotEmpty;
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: hasOnlyConditionalReturns
                ? 'conditional-task-return'
                : 'missing-task-return',
            message: hasOnlyConditionalReturns
                ? 'Await target `$taskName` only returns from conditional '
                      'branches for `$bindingName: $expectedType`.'
                : 'Await target `$taskName` does not return a value for '
                      '`$bindingName: $expectedType`.',
            range: SourceRange(
              start: taskNameStart,
              end: taskNameStart + taskName.length,
            ),
          ),
        );
      } else if (!_isAssignable(
        actualType: task.returnType!,
        expectedType: expectedType,
      )) {
        final bindingStart = match.start + match.group(0)!.indexOf(bindingName);
        diagnostics.add(
          Diagnostic(
            severity: DiagnosticSeverity.error,
            code: 'await-result-type-mismatch',
            message:
                'Await binding `$bindingName` expects `$expectedType` but task '
                '`$taskName` returns `${task.returnType}`.',
            range: SourceRange(
              start: bindingStart,
              end: bindingStart + bindingName.length,
            ),
          ),
        );
      }
      final fallbackExpression = match.group(4);
      if (fallbackExpression != null) {
        final fallbackType = _inferExpressionType(
          fallbackExpression,
          localTypes,
        );
        if (fallbackType != null &&
            !_isAssignable(
              actualType: fallbackType,
              expectedType: expectedType,
            )) {
          final matchedText = match.group(0)!;
          final fallbackPipe = matchedText.lastIndexOf('|');
          final fallbackOffsetInMatch = matchedText.indexOf(
            fallbackExpression,
            fallbackPipe + 1,
          );
          if (fallbackOffsetInMatch < 0) {
            continue;
          }
          final trimmedFallback = fallbackExpression.trimLeft();
          final fallbackStart =
              match.start +
              fallbackOffsetInMatch +
              (fallbackExpression.length - trimmedFallback.length);
          diagnostics.add(
            Diagnostic(
              severity: DiagnosticSeverity.error,
              code: 'await-fallback-type-mismatch',
              message:
                  'Await fallback for `$bindingName` expects `$expectedType` '
                  'but receives `$fallbackType`.',
              range: SourceRange(
                start: fallbackStart,
                end: fallbackStart + trimmedFallback.trimRight().length,
              ),
            ),
          );
        }
      }
    }
    return diagnostics;
  }

  _StyioDeclarationModel _declarationModel(String source) {
    final resources = <String, _ResourceDeclaration>{};
    final duplicateResources = <_ResourceDeclaration>[];
    final resourcePattern = RegExp(
      r'@\s*([A-Za-z_][A-Za-z0-9_]*)\s*:\s*([A-Za-z][A-Za-z0-9_]*)',
    );
    for (final match in resourcePattern.allMatches(source)) {
      final name = match.group(1)!;
      if (name == 'import') {
        continue;
      }
      final nameStart = match.start + match.group(0)!.indexOf(name);
      if (_isOffsetInIgnoredText(source, nameStart)) {
        continue;
      }
      final declaration = _ResourceDeclaration(
        name: name,
        type: match.group(2)!,
        range: SourceRange(start: nameStart, end: nameStart + name.length),
      );
      if (resources.containsKey(name)) {
        duplicateResources.add(declaration);
      } else {
        resources[name] = declaration;
      }
    }

    final tasks = <String, _TaskDeclaration>{};
    final duplicateTasks = <_TaskDeclaration>[];
    final functionReturnTypes = _functionReturnTypes(source);
    final taskPattern = RegExp(r'\b([A-Za-z_][A-Za-z0-9_]*)\s*=\s*\|\|>\s*\{');
    for (final match in taskPattern.allMatches(source)) {
      final name = match.group(1)!;
      final nameStart = match.start + match.group(0)!.indexOf(name);
      if (_isOffsetInIgnoredText(source, nameStart)) {
        continue;
      }
      final openingBrace = source.indexOf('{', match.start);
      final closingBrace = _matchingBrace(source, openingBrace);
      final body = openingBrace >= 0 && closingBrace != null
          ? source.substring(openingBrace + 1, closingBrace)
          : '';
      final returnScan = _taskReturnInference.scan(
        body: body,
        bodyStartOffset: openingBrace + 1,
        functionReturnTypes: functionReturnTypes,
        hasControlArrowBeforeOnLine: _hasControlArrowBeforeOnLine,
      );
      final declaration = _TaskDeclaration(
        name: name,
        returnType: returnScan.values.isEmpty
            ? null
            : returnScan.values.first.type,
        returnValues: returnScan.values,
        missingReturnValueRanges: returnScan.missingValueRanges,
        conditionalReturnRanges: returnScan.conditionalValueRanges,
        conditionalReturnValues: returnScan.conditionalValues,
        unresolvedReturnValues: returnScan.unresolvedValues,
        invalidReturnExpressions: returnScan.invalidExpressions,
        range: SourceRange(start: nameStart, end: nameStart + name.length),
      );
      if (tasks.containsKey(name)) {
        duplicateTasks.add(declaration);
      } else {
        tasks[name] = declaration;
      }
    }

    final functions = <String, _FunctionDeclaration>{};
    final duplicateFunctions = <_FunctionDeclaration>[];
    final duplicateParameters = <_ParameterDeclaration>[];
    final functionPattern = RegExp(
      r'\bfn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)',
    );
    for (final match in functionPattern.allMatches(source)) {
      if (_isOffsetInIgnoredText(source, match.start)) {
        continue;
      }
      final name = match.group(1)!;
      final nameStart = match.start + match.group(0)!.indexOf(name);
      final functionDeclaration = _FunctionDeclaration(
        name: name,
        range: SourceRange(start: nameStart, end: nameStart + name.length),
      );
      if (functions.containsKey(name)) {
        duplicateFunctions.add(functionDeclaration);
      } else {
        functions[name] = functionDeclaration;
      }
      final openParen = source.indexOf('(', match.start);
      if (openParen < 0) {
        continue;
      }
      final seenParameters = <String>{};
      for (final parameter in _parameterDeclarations(
        match.group(2) ?? '',
        openParen + 1,
      )) {
        if (!seenParameters.add(parameter.name)) {
          duplicateParameters.add(parameter);
        }
      }
    }

    final hashFunctionPattern = RegExp(
      r'#\s*([A-Za-z_][A-Za-z0-9_]*)\s*:=\s*\(([^)]*)\)\s*=>\s*\{',
    );
    for (final match in hashFunctionPattern.allMatches(source)) {
      if (_isOffsetInIgnoredText(source, match.start)) {
        continue;
      }
      final name = match.group(1)!;
      final nameStart = match.start + match.group(0)!.indexOf(name);
      final functionDeclaration = _FunctionDeclaration(
        name: name,
        range: SourceRange(start: nameStart, end: nameStart + name.length),
      );
      if (functions.containsKey(name)) {
        duplicateFunctions.add(functionDeclaration);
      } else {
        functions[name] = functionDeclaration;
      }
      final openParen = source.indexOf('(', match.start);
      if (openParen < 0) {
        continue;
      }
      final seenParameters = <String>{};
      for (final parameter in _parameterDeclarations(
        match.group(2) ?? '',
        openParen + 1,
      )) {
        if (!seenParameters.add(parameter.name)) {
          duplicateParameters.add(parameter);
        }
      }
    }

    return _StyioDeclarationModel(
      functions: functions,
      duplicateFunctions: duplicateFunctions,
      resources: resources,
      duplicateResources: duplicateResources,
      tasks: tasks,
      duplicateTasks: duplicateTasks,
      duplicateParameters: duplicateParameters,
    );
  }

  Map<String, String> _functionReturnTypes(String source) {
    final types = <String, String>{};
    final pattern = RegExp(
      r'\bfn\s+([A-Za-z_][A-Za-z0-9_]*)\s*\([^)]*\)\s*:\s*([A-Za-z][A-Za-z0-9_]*)',
    );
    for (final match in pattern.allMatches(source)) {
      final name = match.group(1)!;
      final nameStart = match.start + match.group(0)!.indexOf(name);
      if (_isOffsetInIgnoredText(source, nameStart)) {
        continue;
      }
      types.putIfAbsent(name, () => match.group(2)!);
    }
    return types;
  }

  List<_ParameterDeclaration> _parameterDeclarations(
    String parameterText,
    int baseOffset,
  ) {
    final parameters = <_ParameterDeclaration>[];
    var start = 0;
    var index = 0;
    while (index < parameterText.length) {
      final char = parameterText[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(parameterText, index);
        continue;
      }
      if (char == ',') {
        _addParameterDeclaration(
          parameters,
          parameterText,
          baseOffset,
          start,
          index,
        );
        start = index + 1;
      }
      index += 1;
    }
    _addParameterDeclaration(
      parameters,
      parameterText,
      baseOffset,
      start,
      parameterText.length,
    );
    return parameters;
  }

  void _addParameterDeclaration(
    List<_ParameterDeclaration> parameters,
    String parameterText,
    int baseOffset,
    int start,
    int end,
  ) {
    var trimmedStart = start;
    var trimmedEnd = end;
    while (trimmedStart < trimmedEnd &&
        parameterText.codeUnitAt(trimmedStart) <= 0x20) {
      trimmedStart += 1;
    }
    while (trimmedEnd > trimmedStart &&
        parameterText.codeUnitAt(trimmedEnd - 1) <= 0x20) {
      trimmedEnd -= 1;
    }
    if (trimmedStart >= trimmedEnd) {
      return;
    }
    final text = parameterText.substring(trimmedStart, trimmedEnd);
    final match = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*').firstMatch(text);
    if (match == null) {
      return;
    }
    final name = match.group(0)!;
    parameters.add(
      _ParameterDeclaration(
        name: name,
        range: SourceRange(
          start: baseOffset + trimmedStart,
          end: baseOffset + trimmedStart + name.length,
        ),
      ),
    );
  }

  bool _areReturnTypesCompatible(String left, String right) {
    return _isAssignable(actualType: left, expectedType: right) ||
        _isAssignable(actualType: right, expectedType: left);
  }

  bool _isStandardWritableResource(String name) {
    return name == 'stdout' || name == 'stderr';
  }

  Map<String, String> _localValueTypes(
    String source, {
    Map<String, String> functionReturnTypes = const <String, String>{},
  }) {
    return _taskReturnInference.localValueTypes(
      source,
      functionReturnTypes: functionReturnTypes,
    );
  }

  String? _inferExpressionType(
    String expression,
    Map<String, String> localTypes, {
    Map<String, String> functionReturnTypes = const <String, String>{},
  }) {
    return _taskReturnInference.inferExpressionType(
      expression,
      localTypes,
      functionReturnTypes: functionReturnTypes,
    );
  }

  bool _isAssignable({
    required String actualType,
    required String expectedType,
  }) {
    if (actualType == expectedType) {
      return true;
    }
    return expectedType == 'f64' && actualType == 'i64';
  }

  bool _bodyHasTopLevelValueReturn(String body) {
    return _topLevelValueReturnLineEnd(body) != null;
  }

  List<Diagnostic> _unreachableCodeDiagnostics({
    required String body,
    required int bodyStartOffset,
    String returnOwner = 'function value',
  }) {
    final diagnostics = <Diagnostic>[];
    final returnLineEnd = _topLevelValueReturnLineEnd(body);
    diagnostics.addAll(
      _nestedUnreachableCodeDiagnostics(
        body: body,
        bodyStartOffset: bodyStartOffset,
        endExclusive: returnLineEnd ?? body.length,
        returnOwner: returnOwner,
      ),
    );
    if (returnLineEnd == null) {
      return diagnostics;
    }
    final unreachableStart = _firstTopLevelCodeOffset(body, returnLineEnd);
    if (unreachableStart == null) {
      return diagnostics;
    }
    final unreachableEnd = _lineEndOffset(body, unreachableStart);
    diagnostics.add(
      Diagnostic(
        severity: DiagnosticSeverity.warning,
        code: 'unreachable-code',
        message: 'Code after a $returnOwner return is unreachable.',
        range: SourceRange(
          start: bodyStartOffset + unreachableStart,
          end: bodyStartOffset + unreachableEnd,
        ),
      ),
    );
    return diagnostics;
  }

  List<Diagnostic> _nestedUnreachableCodeDiagnostics({
    required String body,
    required int bodyStartOffset,
    required int endExclusive,
    required String returnOwner,
  }) {
    final diagnostics = <Diagnostic>[];
    var index = 0;
    while (index < endExclusive) {
      final ignoredEnd = _ignoredTextEndAt(body, index);
      if (ignoredEnd != null) {
        index = ignoredEnd;
        continue;
      }
      if (body[index] != '{') {
        index += 1;
        continue;
      }
      final closingBrace = _matchingBrace(body, index);
      if (closingBrace == null) {
        return diagnostics;
      }
      if (_isTaskBodyOpeningBrace(body, index)) {
        index = closingBrace + 1;
        continue;
      }
      diagnostics.addAll(
        _unreachableCodeDiagnostics(
          body: body.substring(index + 1, closingBrace),
          bodyStartOffset: bodyStartOffset + index + 1,
          returnOwner: returnOwner,
        ),
      );
      index = closingBrace + 1;
    }
    return diagnostics;
  }

  bool _isTaskBodyOpeningBrace(String source, int openingBrace) {
    var index = openingBrace - 1;
    while (index >= 0 && source.codeUnitAt(index) <= 0x20) {
      index -= 1;
    }
    if (index < 2) {
      return false;
    }
    return source.substring(index - 2, index + 1) == '||>';
  }

  int? _topLevelValueReturnLineEnd(String body) {
    var depth = 0;
    var index = 0;
    while (index < body.length) {
      final char = body[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(body, index);
        continue;
      }
      if (index + 1 < body.length && body.substring(index, index + 2) == '//') {
        final newline = body.indexOf('\n', index + 2);
        if (newline < 0) {
          return null;
        }
        index = newline + 1;
        continue;
      }
      if (index + 1 < body.length && body.substring(index, index + 2) == '/*') {
        final close = body.indexOf('*/', index + 2);
        if (close < 0) {
          return null;
        }
        index = close + 2;
        continue;
      }
      if (char == '{') {
        depth += 1;
        index += 1;
        continue;
      }
      if (char == '}') {
        if (depth > 0) {
          depth -= 1;
        }
        index += 1;
        continue;
      }
      if (depth == 0) {
        final guardReturnEnd = _constantTrueGuardBlockReturnEnd(body, index);
        if (guardReturnEnd != null) {
          return guardReturnEnd;
        }
      }
      if (depth == 0 && _startsValueReturn(body, index)) {
        return _lineEndOffset(body, index);
      }
      index += 1;
    }
    return null;
  }

  int? _firstTopLevelCodeOffset(String body, int start) {
    var depth = 0;
    var index = start;
    while (index < body.length) {
      final char = body[index];
      if (char.codeUnitAt(0) <= 0x20) {
        index += 1;
        continue;
      }
      if (char == '"' || char == "'") {
        return depth == 0 ? index : _skipQuotedText(body, index);
      }
      if (index + 1 < body.length && body.substring(index, index + 2) == '//') {
        final newline = body.indexOf('\n', index + 2);
        if (newline < 0) {
          return null;
        }
        index = newline + 1;
        continue;
      }
      if (index + 1 < body.length && body.substring(index, index + 2) == '/*') {
        final close = body.indexOf('*/', index + 2);
        if (close < 0) {
          return null;
        }
        index = close + 2;
        continue;
      }
      if (char == '{') {
        if (depth == 0) {
          return index;
        }
        depth += 1;
        index += 1;
        continue;
      }
      if (char == '}') {
        if (depth > 0) {
          depth -= 1;
          index += 1;
          continue;
        }
        return index;
      }
      if (depth == 0) {
        return index;
      }
      index += 1;
    }
    return null;
  }

  int _lineEndOffset(String source, int offset) {
    final newline = source.indexOf('\n', offset);
    return newline < 0 ? source.length : newline;
  }

  bool _startsValueReturn(String source, int index) {
    final startsTaskReturn = source.startsWith('<|', index);
    final startsEmit = source.startsWith('emit', index);
    if (!startsTaskReturn && !startsEmit) {
      return false;
    }
    if (startsEmit) {
      final previous = index == 0 ? null : source.codeUnitAt(index - 1);
      final next = index + 4 >= source.length
          ? null
          : source.codeUnitAt(index + 4);
      if (_isIdentifierCodeUnit(previous) || next == null || next > 0x20) {
        return false;
      }
    }
    return !_hasControlArrowBeforeOnLine(source, index);
  }

  bool _hasControlArrowBeforeOnLine(String source, int offset) {
    final lineStart = source.lastIndexOf('\n', offset - 1) + 1;
    var depth = 0;
    var index = lineStart;
    while (index < offset) {
      final char = source[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(source, index);
        continue;
      }
      if (index + 1 < offset && source.substring(index, index + 2) == '//') {
        return false;
      }
      if (index + 1 < offset && source.substring(index, index + 2) == '/*') {
        final close = source.indexOf('*/', index + 2);
        if (close < 0 || close >= offset) {
          return false;
        }
        index = close + 2;
        continue;
      }
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
    return _isAlwaysTrueWhenCondition(condition);
  }

  bool _isAlwaysTrueWhenCondition(String condition) {
    return _constantBooleanConditionValue(condition) == true;
  }

  bool _isAlwaysFalseWhenCondition(String condition) {
    return _constantBooleanConditionValue(condition) == false;
  }

  bool? _constantBooleanConditionValue(String condition) {
    return _constantBooleanConditionValueNormalized(
      condition.replaceAll(RegExp(r'\s+'), ''),
    );
  }

  bool? _constantBooleanConditionValueNormalized(String text) {
    if (text.isEmpty) {
      return null;
    }
    final remaining = _stripBalancedOuterParentheses(text);
    final orIndex = _topLevelBooleanOperatorIndex(remaining, '||');
    if (orIndex != null) {
      final left = _constantBooleanConditionValueNormalized(
        remaining.substring(0, orIndex),
      );
      final right = _constantBooleanConditionValueNormalized(
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
      final left = _constantBooleanConditionValueNormalized(
        remaining.substring(0, andIndex),
      );
      final right = _constantBooleanConditionValueNormalized(
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
      final left = _constantBooleanConditionValueNormalized(
        remaining.substring(0, equalsIndex),
      );
      final right = _constantBooleanConditionValueNormalized(
        remaining.substring(equalsIndex + 2),
      );
      if (left != null && right != null) {
        return left == right;
      }
      final numericLeft = _constantNumericValueNormalized(
        remaining.substring(0, equalsIndex),
      );
      final numericRight = _constantNumericValueNormalized(
        remaining.substring(equalsIndex + 2),
      );
      if (numericLeft != null && numericRight != null) {
        return numericLeft == numericRight;
      }
      return null;
    }

    final notEqualsIndex = _topLevelBooleanOperatorIndex(remaining, '!=');
    if (notEqualsIndex != null) {
      final left = _constantBooleanConditionValueNormalized(
        remaining.substring(0, notEqualsIndex),
      );
      final right = _constantBooleanConditionValueNormalized(
        remaining.substring(notEqualsIndex + 2),
      );
      if (left != null && right != null) {
        return left != right;
      }
      final numericLeft = _constantNumericValueNormalized(
        remaining.substring(0, notEqualsIndex),
      );
      final numericRight = _constantNumericValueNormalized(
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
      final left = _constantNumericValueNormalized(
        remaining.substring(0, greaterThanOrEqualsIndex),
      );
      final right = _constantNumericValueNormalized(
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
      final left = _constantNumericValueNormalized(
        remaining.substring(0, lessThanOrEqualsIndex),
      );
      final right = _constantNumericValueNormalized(
        remaining.substring(lessThanOrEqualsIndex + 2),
      );
      if (left != null && right != null) {
        return left <= right;
      }
      return null;
    }

    final greaterThanIndex = _topLevelBooleanOperatorIndex(remaining, '>');
    if (greaterThanIndex != null) {
      final left = _constantNumericValueNormalized(
        remaining.substring(0, greaterThanIndex),
      );
      final right = _constantNumericValueNormalized(
        remaining.substring(greaterThanIndex + 1),
      );
      if (left != null && right != null) {
        return left > right;
      }
      return null;
    }

    final lessThanIndex = _topLevelBooleanOperatorIndex(remaining, '<');
    if (lessThanIndex != null) {
      final left = _constantNumericValueNormalized(
        remaining.substring(0, lessThanIndex),
      );
      final right = _constantNumericValueNormalized(
        remaining.substring(lessThanIndex + 1),
      );
      if (left != null && right != null) {
        return left < right;
      }
      return null;
    }

    if (remaining.startsWith('!')) {
      final value = _constantBooleanConditionValueNormalized(
        remaining.substring(1),
      );
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

  double? _constantNumericValueNormalized(String text) {
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

  String? _whenGuardCondition(String prefix) {
    final trimmed = prefix.trim();
    if (!trimmed.startsWith('when ')) {
      return null;
    }
    return trimmed.substring(5).replaceAll(RegExp(r'\s+'), '');
  }

  int? _constantTrueGuardBlockReturnEnd(String source, int index) {
    if (!source.startsWith('when ', index)) {
      return null;
    }
    final previous = index == 0 ? null : source.codeUnitAt(index - 1);
    if (_isIdentifierCodeUnit(previous)) {
      return null;
    }
    final lineEnd = _lineEndOffset(source, index);
    final line = source.substring(index, lineEnd);
    final arrowIndex = _topLevelArrowIndex(line, 0);
    if (arrowIndex == null) {
      return null;
    }
    final condition = line.substring('when '.length, arrowIndex);
    if (!_isAlwaysTrueWhenCondition(condition)) {
      return null;
    }
    final openingBraceIndex = _topLevelCharacterIndex(
      line,
      arrowIndex + 2,
      '{',
    );
    if (openingBraceIndex == null) {
      return null;
    }
    final openingBrace = index + openingBraceIndex;
    final closingBrace = _matchingBrace(source, openingBrace);
    if (closingBrace == null) {
      return null;
    }
    final blockBody = source.substring(openingBrace + 1, closingBrace);
    if (!_bodyHasTopLevelValueReturn(blockBody)) {
      return null;
    }
    return _lineEndOffset(source, closingBrace);
  }

  int? _topLevelArrowIndex(String line, int start) {
    var depth = 0;
    var index = start;
    while (index < line.length) {
      final char = line[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(line, index);
        continue;
      }
      if (index + 1 < line.length && line.substring(index, index + 2) == '//') {
        return null;
      }
      if (index + 1 < line.length && line.substring(index, index + 2) == '/*') {
        final close = line.indexOf('*/', index + 2);
        if (close < 0) {
          return null;
        }
        index = close + 2;
        continue;
      }
      if (char == '(' || char == '[' || char == '{') {
        depth += 1;
      } else if (char == ')' || char == ']' || char == '}') {
        if (depth > 0) {
          depth -= 1;
        }
      } else if (depth == 0 && line.startsWith('->', index)) {
        return index;
      }
      index += 1;
    }
    return null;
  }

  int? _topLevelCharacterIndex(String line, int start, String target) {
    var depth = 0;
    var index = start;
    while (index < line.length) {
      final char = line[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(line, index);
        continue;
      }
      if (index + 1 < line.length && line.substring(index, index + 2) == '//') {
        return null;
      }
      if (index + 1 < line.length && line.substring(index, index + 2) == '/*') {
        final close = line.indexOf('*/', index + 2);
        if (close < 0) {
          return null;
        }
        index = close + 2;
        continue;
      }
      if (depth == 0 && char == target) {
        return index;
      }
      if (char == '(' || char == '[' || char == '{') {
        depth += 1;
      } else if (char == ')' || char == ']' || char == '}') {
        if (depth > 0) {
          depth -= 1;
        }
      }
      index += 1;
    }
    return null;
  }

  int? _firstNonWhitespaceOffset(String line, int start) {
    var index = start;
    while (index < line.length) {
      if (line.codeUnitAt(index) > 0x20) {
        return index;
      }
      index += 1;
    }
    return null;
  }

  bool _isIdentifierCodeUnit(int? codeUnit) {
    if (codeUnit == null) {
      return false;
    }
    return (codeUnit >= 0x41 && codeUnit <= 0x5a) ||
        (codeUnit >= 0x61 && codeUnit <= 0x7a) ||
        (codeUnit >= 0x30 && codeUnit <= 0x39) ||
        codeUnit == 0x5f;
  }

  int? _matchingBrace(String source, int openingBrace) {
    if (openingBrace < 0 ||
        openingBrace >= source.length ||
        source[openingBrace] != '{') {
      return null;
    }
    var depth = 0;
    var index = openingBrace;
    while (index < source.length) {
      final char = source[index];
      if (char == '"' || char == "'") {
        index = _skipQuotedText(source, index);
        continue;
      }
      if (index + 1 < source.length &&
          source.substring(index, index + 2) == '//') {
        final newline = source.indexOf('\n', index + 2);
        if (newline < 0) {
          return null;
        }
        index = newline + 1;
        continue;
      }
      if (index + 1 < source.length &&
          source.substring(index, index + 2) == '/*') {
        final close = source.indexOf('*/', index + 2);
        if (close < 0) {
          return null;
        }
        index = close + 2;
        continue;
      }
      if (char == '{') {
        depth += 1;
      } else if (char == '}') {
        depth -= 1;
        if (depth == 0) {
          return index;
        }
      }
      index += 1;
    }
    return null;
  }

  int _skipQuotedText(String source, int openingQuote) {
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

  bool _isOffsetInIgnoredText(String source, int offset) {
    var index = 0;
    while (index < source.length && index <= offset) {
      final ignoredEnd = _ignoredTextEndAt(source, index);
      if (ignoredEnd != null) {
        if (offset < ignoredEnd) {
          return true;
        }
        index = ignoredEnd;
        continue;
      }
      index += 1;
    }
    return false;
  }

  int? _ignoredTextEndAt(String source, int index) {
    if (index < 0 || index >= source.length) {
      return null;
    }
    final char = source[index];
    if (char == '"' || char == "'") {
      return _skipQuotedText(source, index);
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
}


class _StyioDeclarationModel {
  const _StyioDeclarationModel({
    required this.functions,
    required this.duplicateFunctions,
    required this.resources,
    required this.duplicateResources,
    required this.tasks,
    required this.duplicateTasks,
    required this.duplicateParameters,
  });

  final Map<String, _FunctionDeclaration> functions;
  final List<_FunctionDeclaration> duplicateFunctions;
  final Map<String, _ResourceDeclaration> resources;
  final List<_ResourceDeclaration> duplicateResources;
  final Map<String, _TaskDeclaration> tasks;
  final List<_TaskDeclaration> duplicateTasks;
  final List<_ParameterDeclaration> duplicateParameters;
}

class _FunctionDeclaration {
  const _FunctionDeclaration({required this.name, required this.range});

  final String name;
  final SourceRange range;
}

class _ResourceDeclaration {
  const _ResourceDeclaration({
    required this.name,
    required this.type,
    required this.range,
  });

  final String name;
  final String type;
  final SourceRange range;
}

class _TaskDeclaration {
  const _TaskDeclaration({
    required this.name,
    required this.returnType,
    required this.returnValues,
    required this.missingReturnValueRanges,
    required this.conditionalReturnRanges,
    required this.conditionalReturnValues,
    required this.unresolvedReturnValues,
    required this.invalidReturnExpressions,
    required this.range,
  });

  final String name;
  final String? returnType;
  final List<StyioTaskReturnValue> returnValues;
  final List<SourceRange> missingReturnValueRanges;
  final List<SourceRange> conditionalReturnRanges;
  final List<StyioTaskReturnValue> conditionalReturnValues;
  final List<StyioTaskReturnExpression> unresolvedReturnValues;
  final List<StyioTaskReturnExpression> invalidReturnExpressions;
  final SourceRange range;
}

class _ParameterDeclaration {
  const _ParameterDeclaration({required this.name, required this.range});

  final String name;
  final SourceRange range;
}
