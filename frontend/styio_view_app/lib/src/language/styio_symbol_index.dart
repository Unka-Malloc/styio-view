import 'language_contract.dart';
import 'styio_syntax_highlighter.dart';

class StyioSymbolIndex {
  const StyioSymbolIndex({
    StyioSyntaxHighlighter syntaxHighlighter = const StyioSyntaxHighlighter(),
  }) : _syntaxHighlighter = syntaxHighlighter;

  final StyioSyntaxHighlighter _syntaxHighlighter;

  StyioSymbolSnapshot build(List<TokenSpan> tokens) {
    final symbols = <DocumentSymbol>[];
    final symbolsByName = <String, List<DocumentSymbol>>{};

    void addSymbol({
      required TokenSpan nameToken,
      required SymbolKind kind,
      required SourceRange declarationRange,
      required String detail,
    }) {
      if (_syntaxHighlighter.isTypeName(nameToken.lexeme)) {
        return;
      }
      final duplicate = symbols.any(
        (symbol) =>
            symbol.nameRange.start == nameToken.range.start &&
            symbol.nameRange.end == nameToken.range.end,
      );
      if (duplicate) {
        return;
      }

      final symbol = DocumentSymbol(
        name: nameToken.lexeme,
        kind: kind,
        nameRange: nameToken.range,
        declarationRange: declarationRange,
        detail: detail,
        documentation: _leadingDocumentationForDeclaration(
          tokens,
          declarationRange,
        ),
      );
      symbols.add(symbol);
      symbolsByName
          .putIfAbsent(symbol.name, () => <DocumentSymbol>[])
          .add(symbol);
    }

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];

      if (token.lexeme == '#') {
        final next = _nextSignificant(tokens, index + 1);
        if (next?.kind == TokenKind.identifier) {
          addSymbol(
            nameToken: next!,
            kind: SymbolKind.function,
            declarationRange: _declarationRange(tokens, index),
            detail: 'Styio hash function',
          );
          _addParametersAfter(
            tokens: tokens,
            startIndex: tokens.indexOf(next) + 1,
            addSymbol: addSymbol,
          );
        } else if (next?.lexeme == '(') {
          _addParametersInDelimitedList(
            tokens: tokens,
            openingIndex: tokens.indexOf(next!),
            addSymbol: addSymbol,
          );
        }
        continue;
      }

      if (token.lexeme == '@') {
        final resource = _nextSignificant(tokens, index + 1);
        if (resource == null || resource.lexeme == 'import') {
          continue;
        }
        final afterResource = _nextSignificant(
          tokens,
          tokens.indexOf(resource) + 1,
        );
        if ((resource.kind == TokenKind.identifier ||
                resource.kind == TokenKind.keyword) &&
            (afterResource?.lexeme == ':' || afterResource?.lexeme == ':=')) {
          addSymbol(
            nameToken: resource,
            kind: SymbolKind.resource,
            declarationRange: _declarationRange(tokens, index),
            detail: 'Styio resource declaration',
          );
        }
        continue;
      }

      if (token.lexeme == '=' || token.lexeme == ':=') {
        final previous = _previousSignificant(tokens, index - 1);
        if (previous?.kind == TokenKind.identifier) {
          addSymbol(
            nameToken: previous!,
            kind: SymbolKind.variable,
            declarationRange: _declarationRange(
              tokens,
              tokens.indexOf(previous),
            ),
            detail: 'Styio value binding',
          );
        }
        continue;
      }

      if (token.lexeme == '->') {
        final binding = _nextIdentifier(tokens, index + 1);
        if (binding == null) {
          continue;
        }
        final afterBinding = _nextSignificant(
          tokens,
          tokens.indexOf(binding) + 1,
        );
        if (afterBinding?.lexeme == ':') {
          addSymbol(
            nameToken: binding,
            kind: SymbolKind.variable,
            declarationRange: _declarationRange(
              tokens,
              tokens.indexOf(binding),
            ),
            detail: 'Styio typed result binding',
          );
        }
        continue;
      }

      if (token.kind != TokenKind.keyword) {
        continue;
      }

      switch (token.lexeme) {
        case 'fn':
          final nameToken = _nextIdentifier(tokens, index + 1);
          if (nameToken != null) {
            addSymbol(
              nameToken: nameToken,
              kind: SymbolKind.function,
              declarationRange: _declarationRange(tokens, index),
              detail: 'Styio legacy function',
            );
            _addParametersAfter(
              tokens: tokens,
              startIndex: tokens.indexOf(nameToken) + 1,
              addSymbol: addSymbol,
            );
          }
          break;
        case 'pipeline':
          final nameToken = _nextIdentifier(tokens, index + 1);
          if (nameToken != null) {
            addSymbol(
              nameToken: nameToken,
              kind: SymbolKind.pipeline,
              declarationRange: _declarationRange(tokens, index),
              detail: 'Styio pipeline declaration',
            );
          }
          break;
        case 'state':
          final nameToken = _nextIdentifier(tokens, index + 1);
          if (nameToken != null) {
            addSymbol(
              nameToken: nameToken,
              kind: SymbolKind.state,
              declarationRange: _declarationRange(tokens, index),
              detail: 'Styio state declaration',
            );
          }
          break;
        case 'let':
          final nameToken = _nextIdentifier(tokens, index + 1);
          if (nameToken != null) {
            addSymbol(
              nameToken: nameToken,
              kind: SymbolKind.variable,
              declarationRange: _declarationRange(tokens, index),
              detail: 'Styio local binding',
            );
          }
          break;
      }
    }

    final references = _resolveReferences(tokens, symbolsByName);
    return StyioSymbolSnapshot(
      symbols: List<DocumentSymbol>.unmodifiable(symbols),
      references: List<ReferenceSpan>.unmodifiable(references),
    );
  }

  DefinitionTarget? definitionAt(String source, int offset) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final snapshot = build(tokens);
    final token = _tokenAroundOffset(tokens, offset);
    if (token == null) {
      return null;
    }

    final reference = snapshot.referenceAt(token.range);
    if (reference == null) {
      return null;
    }
    final symbol = snapshot.symbolForTarget(reference.targetRange);
    if (symbol == null) {
      return null;
    }
    return DefinitionTarget(symbol: symbol, originRange: reference.range);
  }

  List<ReferenceSpan> referencesAt(String source, int offset) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final snapshot = build(tokens);
    final token = _tokenAroundOffset(tokens, offset);
    if (token == null) {
      return const <ReferenceSpan>[];
    }

    final reference = snapshot.referenceAt(token.range);
    if (reference == null) {
      return const <ReferenceSpan>[];
    }
    return snapshot.referencesForTarget(reference.targetRange);
  }

  RenamePlan? renameAt(String source, int offset, String newName) {
    if (!_isValidIdentifier(newName)) {
      return null;
    }

    final tokens = _syntaxHighlighter.tokenize(source);
    final snapshot = build(tokens);
    final token = _tokenAroundOffset(tokens, offset);
    if (token == null) {
      return null;
    }

    final reference = snapshot.referenceAt(token.range);
    if (reference == null) {
      return null;
    }

    final target = snapshot.symbolForTarget(reference.targetRange);
    if (target == null) {
      return null;
    }

    final references = snapshot.referencesForTarget(reference.targetRange);
    if (references.isEmpty) {
      return null;
    }

    return RenamePlan(
      target: target,
      newName: newName,
      references: references,
      edits: references
          .map(
            (reference) =>
                FormattingEdit(range: reference.range, newText: newName),
          )
          .toList(growable: false),
      conflicts: _renameConflicts(
        snapshot: snapshot,
        target: target,
        newName: newName,
      ),
    );
  }

  SafeDeletePlan? safeDeleteAt(String source, int offset) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final snapshot = build(tokens);
    final token = _tokenAroundOffset(tokens, offset);
    if (token == null) {
      return null;
    }

    final reference = snapshot.referenceAt(token.range);
    if (reference == null) {
      return null;
    }

    final target = snapshot.symbolForTarget(reference.targetRange);
    if (target == null) {
      return null;
    }

    final references = snapshot.referencesForTarget(reference.targetRange);
    if (references.isEmpty) {
      return null;
    }

    final conflicts = _safeDeleteConflicts(
      target: target,
      references: references,
    );
    return SafeDeletePlan(
      target: target,
      references: references,
      edits: conflicts.isEmpty
          ? [
              FormattingEdit(
                range: _lineRemovalRange(source, target.declarationRange),
                newText: '',
              ),
            ]
          : const <FormattingEdit>[],
      conflicts: conflicts,
    );
  }

  InlineVariablePlan? inlineVariableAt(String source, int offset) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final snapshot = build(tokens);
    final token = _tokenAroundOffset(tokens, offset);
    if (token == null) {
      return null;
    }

    final reference = snapshot.referenceAt(token.range);
    if (reference == null) {
      return null;
    }

    final target = snapshot.symbolForTarget(reference.targetRange);
    if (target == null) {
      return null;
    }

    final references = snapshot.referencesForTarget(reference.targetRange);
    if (references.isEmpty) {
      return null;
    }

    final initializer = _variableInitializer(source, tokens, target);
    final conflicts = _inlineVariableConflicts(
      target: target,
      initializer: initializer,
      references: references,
    );
    final referencesToInline = conflicts.isEmpty
        ? references
              .where((reference) => !reference.isDeclaration)
              .toList(growable: false)
        : const <ReferenceSpan>[];
    final initializerText = initializer?.text ?? '';
    return InlineVariablePlan(
      target: target,
      initializerRange: initializer?.range ?? target.nameRange,
      initializerText: initializerText,
      references: referencesToInline,
      edits: conflicts.isEmpty
          ? [
              for (final reference in referencesToInline)
                FormattingEdit(
                  range: reference.range,
                  newText: initializerText,
                ),
              FormattingEdit(
                range: _lineRemovalRange(source, target.declarationRange),
                newText: '',
              ),
            ]
          : const <FormattingEdit>[],
      conflicts: conflicts,
    );
  }

  IntroduceVariablePlan? introduceVariable(
    String source,
    SourceRange range,
    String name,
  ) {
    final expressionRange = _trimmedRange(source, range);
    if (expressionRange.isCollapsed) {
      return null;
    }

    final expressionText = source.substring(
      expressionRange.start,
      expressionRange.end,
    );
    final tokens = _syntaxHighlighter.tokenize(source);
    final snapshot = build(tokens);
    final conflicts = _introduceVariableConflicts(
      source: source,
      tokens: tokens,
      snapshot: snapshot,
      expressionRange: expressionRange,
      expressionText: expressionText,
      name: name,
    );
    return IntroduceVariablePlan(
      variableName: name,
      expressionRange: expressionRange,
      expressionText: expressionText,
      edits: conflicts.isEmpty
          ? [
              FormattingEdit(
                range: _lineInsertionRange(source, expressionRange.start),
                newText:
                    '${_lineIndentAt(source, expressionRange.start)}$name = '
                    '$expressionText\n',
              ),
              FormattingEdit(range: expressionRange, newText: name),
            ]
          : const <FormattingEdit>[],
      conflicts: conflicts,
    );
  }

  ExtractFunctionPlan? extractFunction(
    String source,
    SourceRange range,
    String name,
  ) {
    final selectionRange = _trimmedRange(source, range);
    if (selectionRange.isCollapsed) {
      return null;
    }

    final selectedText = source.substring(
      selectionRange.start,
      selectionRange.end,
    );
    final tokens = _syntaxHighlighter.tokenize(source);
    final snapshot = build(tokens);
    final selectionKind = _extractFunctionSelectionKind(source, selectionRange);
    final parameters = _extractFunctionParameters(
      snapshot: snapshot,
      selectionRange: selectionRange,
    );
    final callText = _extractFunctionCallText(
      name: name,
      parameters: parameters,
    );
    final functionText = _extractFunctionDeclarationText(
      name: name,
      parameters: parameters,
      selectionKind: selectionKind,
      selectedText: selectedText,
    );
    final conflicts = _extractFunctionConflicts(
      source: source,
      tokens: tokens,
      snapshot: snapshot,
      selectionRange: selectionRange,
      selectedText: selectedText,
      name: name,
      selectionKind: selectionKind,
    );
    final duplicateOccurrences = conflicts.isEmpty
        ? _extractFunctionDuplicateOccurrences(
            source: source,
            tokens: tokens,
            selectionRange: selectionRange,
            selectedText: selectedText,
          )
        : const <SourceRange>[];
    return ExtractFunctionPlan(
      functionName: name,
      selectionRange: selectionRange,
      selectedText: selectedText,
      parameters: parameters,
      callText: callText,
      functionText: functionText,
      edits: conflicts.isEmpty
          ? [
              FormattingEdit(
                range: _extractFunctionInsertionRange(source),
                newText: functionText,
              ),
              FormattingEdit(range: selectionRange, newText: callText),
              for (final occurrence in duplicateOccurrences)
                FormattingEdit(range: occurrence, newText: callText),
            ]
          : const <FormattingEdit>[],
      duplicateOccurrences: duplicateOccurrences,
      conflicts: conflicts,
    );
  }

  ChangeSignaturePlan? changeSignature(
    String source,
    int offset, {
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  }) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final snapshot = build(tokens);
    final token = _tokenAroundOffset(tokens, offset);
    if (token == null) {
      return null;
    }

    final reference = snapshot.referenceAt(token.range);
    if (reference == null) {
      return null;
    }

    final target = snapshot.symbolForTarget(reference.targetRange);
    if (target == null || target.kind != SymbolKind.function) {
      return null;
    }

    final signature = _functionSignatureForTarget(tokens, target);
    if (signature == null) {
      return null;
    }

    final references = snapshot.referencesForTarget(reference.targetRange);
    if (references.isEmpty) {
      return null;
    }

    final conflicts = _changeSignatureConflicts(
      source: source,
      tokens: tokens,
      snapshot: snapshot,
      target: target,
      signature: signature,
      newName: newName,
      parameters: parameters,
      references: references,
    );

    return ChangeSignaturePlan(
      target: target,
      originalName: target.name,
      newName: newName,
      originalParameters: signature.parameters,
      newParameters: parameters,
      references: references,
      edits: conflicts.isEmpty
          ? _changeSignatureEdits(
              source: source,
              tokens: tokens,
              snapshot: snapshot,
              target: target,
              signature: signature,
              newName: newName,
              parameters: parameters,
              references: references,
            )
          : const <FormattingEdit>[],
      conflicts: conflicts,
    );
  }

  ParameterInfoPayload? parameterInfoAt(String source, int offset) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    if (signaturesByName.isEmpty) {
      return null;
    }

    final call = _callArgumentListAt(tokens, offset);
    if (call == null) {
      return null;
    }

    final candidates = signaturesByName[call.callable.lexeme];
    if (candidates == null || candidates.isEmpty) {
      return null;
    }

    final signature = candidates.lastWhere(
      (candidate) => candidate.nameRange.start <= call.callable.range.start,
      orElse: () => candidates.first,
    );
    var activeParameterIndex = _activeParameterIndex(
      tokens: tokens,
      openingIndex: call.openingIndex,
      closingIndex: call.closingIndex,
      offset: offset,
    );
    if (signature.parameters.isEmpty) {
      activeParameterIndex = -1;
    } else {
      activeParameterIndex = activeParameterIndex.clamp(
        0,
        signature.parameters.length - 1,
      );
    }

    return ParameterInfoPayload(
      callableName: signature.name,
      signature: signature.displayText,
      parameters: signature.parameters,
      activeParameterIndex: activeParameterIndex,
      invocationRange: SourceRange(
        start: call.callable.range.start,
        end: tokens[call.closingIndex].range.end,
      ),
      callableRange: call.callable.range,
      documentation: signature.documentation,
    );
  }

  List<InlayHint> inlayHints(String source) {
    return <InlayHint>[...parameterNameHints(source), ...typeNameHints(source)]
      ..sort((left, right) {
        final positionOrder = left.position.compareTo(right.position);
        if (positionOrder != 0) {
          return positionOrder;
        }
        return left.kind.index.compareTo(right.kind.index);
      });
  }

  List<InlayHint> parameterNameHints(String source) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    if (signaturesByName.isEmpty) {
      return const <InlayHint>[];
    }

    final hints = <InlayHint>[];
    for (final call in _callArgumentLists(tokens)) {
      final candidates = signaturesByName[call.callable.lexeme];
      if (candidates == null || candidates.isEmpty) {
        continue;
      }
      final signature = candidates.lastWhere(
        (candidate) => candidate.nameRange.start <= call.callable.range.start,
        orElse: () => candidates.first,
      );
      final arguments = _parseCallArguments(
        source: source,
        tokens: tokens,
        openingIndex: call.openingIndex,
        closingIndex: call.closingIndex,
      );
      final limit = arguments.length < signature.parameters.length
          ? arguments.length
          : signature.parameters.length;
      for (var index = 0; index < limit; index += 1) {
        final argument = arguments[index];
        final parameter = signature.parameters[index];
        if (_shouldSuppressParameterNameHint(parameter, argument)) {
          continue;
        }
        hints.add(
          InlayHint(
            label: '${parameter.name}:',
            kind: InlayHintKind.parameter,
            position: argument.range.start,
            range: argument.range,
          ),
        );
      }
    }
    return hints;
  }

  List<InlayHint> typeNameHints(String source) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    final hints = <InlayHint>[];
    final inferredTypesByName = <String, String>{};

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind != TokenKind.identifier ||
          _syntaxHighlighter.isTypeName(token.lexeme)) {
        continue;
      }

      final assignmentIndex = _bindingAssignmentIndex(tokens, index);
      if (assignmentIndex == null) {
        continue;
      }

      final expressionStartIndex = _nextSignificantIndex(
        tokens,
        assignmentIndex + 1,
      );
      if (expressionStartIndex == null) {
        continue;
      }

      final typeName = _inferExpressionType(
        tokens: tokens,
        expressionStartIndex: expressionStartIndex,
        signaturesByName: signaturesByName,
        inferredTypesByName: inferredTypesByName,
      );
      if (typeName == null || typeName.isEmpty) {
        continue;
      }

      inferredTypesByName[token.lexeme] = typeName;
      hints.add(
        InlayHint(
          label: ': $typeName',
          kind: InlayHintKind.type,
          position: token.range.end,
          range: token.range,
        ),
      );
    }

    return hints;
  }

  int? _bindingAssignmentIndex(List<TokenSpan> tokens, int nameIndex) {
    final nextIndex = _nextSignificantIndex(tokens, nameIndex + 1);
    if (nextIndex == null ||
        (tokens[nextIndex].lexeme != '=' && tokens[nextIndex].lexeme != ':=')) {
      return null;
    }
    if (_hasLineBreakBetween(tokens, nameIndex + 1, nextIndex)) {
      return null;
    }

    final previous = _previousSignificant(tokens, nameIndex - 1);
    final disallowedPrevious = <String>{'fn', '#', '(', ',', ':', '@'};
    if (previous != null && disallowedPrevious.contains(previous.lexeme)) {
      return null;
    }
    return nextIndex;
  }

  String? _inferExpressionType({
    required List<TokenSpan> tokens,
    required int expressionStartIndex,
    required Map<String, List<_FunctionSignature>> signaturesByName,
    required Map<String, String> inferredTypesByName,
  }) {
    final token = tokens[expressionStartIndex];
    if (token.kind == TokenKind.number) {
      return token.lexeme.contains('.') ? 'f64' : 'i64';
    }
    if (token.kind == TokenKind.string) {
      return 'string';
    }
    if (token.kind == TokenKind.keyword) {
      if (token.lexeme == 'true' || token.lexeme == 'false') {
        return 'bool';
      }
      return null;
    }
    if (token.kind != TokenKind.identifier ||
        _syntaxHighlighter.isTypeName(token.lexeme)) {
      return null;
    }

    final call = _callArgumentListAfter(tokens, expressionStartIndex);
    if (call != null) {
      final signature = _signatureForCall(signaturesByName, call.callable);
      if (signature == null || signature.returnType.isEmpty) {
        return null;
      }
      return signature.returnType;
    }

    return inferredTypesByName[token.lexeme];
  }

  _FunctionSignature? _signatureForCall(
    Map<String, List<_FunctionSignature>> signaturesByName,
    TokenSpan callable,
  ) {
    final candidates = signaturesByName[callable.lexeme];
    if (candidates == null || candidates.isEmpty) {
      return null;
    }
    return candidates.lastWhere(
      (candidate) => candidate.nameRange.start <= callable.range.start,
      orElse: () => candidates.first,
    );
  }

  List<StyioCallArgumentIssue> callArgumentIssues(String source) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    if (signaturesByName.isEmpty) {
      return const <StyioCallArgumentIssue>[];
    }

    final issues = <StyioCallArgumentIssue>[];
    for (final call in _callArgumentLists(tokens)) {
      final candidates = signaturesByName[call.callable.lexeme];
      if (candidates == null || candidates.isEmpty) {
        continue;
      }
      final signature = candidates.lastWhere(
        (candidate) => candidate.nameRange.start <= call.callable.range.start,
        orElse: () => candidates.first,
      );
      final arguments = _parseCallArguments(
        source: source,
        tokens: tokens,
        openingIndex: call.openingIndex,
        closingIndex: call.closingIndex,
      );
      final requiredParameters = signature.parameters
          .where(
            (parameter) =>
                !_parameterHasDefaultValue(tokens, signature, parameter.name),
          )
          .toList(growable: false);
      final argumentListRange = SourceRange(
        start: tokens[call.openingIndex].range.end,
        end: tokens[call.closingIndex].range.start,
      );
      final invocationRange = SourceRange(
        start: call.callable.range.start,
        end: tokens[call.closingIndex].range.end,
      );

      if (arguments.length < requiredParameters.length) {
        final missingParameters = requiredParameters
            .skip(arguments.length)
            .toList(growable: false);
        issues.add(
          StyioCallArgumentIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'missing-call-argument',
              message:
                  'Call to `${signature.name}` is missing '
                  '${missingParameters.length} argument'
                  '${missingParameters.length == 1 ? '' : 's'}: '
                  '${missingParameters.map((item) => item.name).join(', ')}.',
              range: invocationRange,
            ),
            callableName: signature.name,
            expectedArgumentCount: requiredParameters.length,
            actualArgumentCount: arguments.length,
            argumentListRange: argumentListRange,
            replacementArgumentText: [
              ...arguments.map((argument) => argument.text),
              for (
                var index = arguments.length;
                index < requiredParameters.length;
                index += 1
              )
                'value',
            ].join(', '),
            missingParameterNames: missingParameters
                .map((parameter) => parameter.name)
                .toList(growable: false),
          ),
        );
        continue;
      }

      if (arguments.length > signature.parameters.length) {
        final extraCount = arguments.length - signature.parameters.length;
        issues.add(
          StyioCallArgumentIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'too-many-call-arguments',
              message:
                  'Call to `${signature.name}` has ${arguments.length} '
                  'argument${arguments.length == 1 ? '' : 's'}, expected '
                  '${signature.parameters.length}.',
              range: invocationRange,
            ),
            callableName: signature.name,
            expectedArgumentCount: signature.parameters.length,
            actualArgumentCount: arguments.length,
            argumentListRange: argumentListRange,
            replacementArgumentText: arguments
                .take(signature.parameters.length)
                .map((argument) => argument.text)
                .join(', '),
            extraArgumentCount: extraCount,
          ),
        );
      }
    }

    return issues;
  }

  List<StyioUnusedParameterIssue> unusedParameterIssues(String source) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final snapshot = build(tokens);
    final signatures = _collectFunctionSignatures(
      tokens,
    ).values.expand((items) => items);
    final issues = <StyioUnusedParameterIssue>[];

    for (final signature in signatures) {
      final bodyRange = _functionBodyRange(tokens, signature);
      if (bodyRange == null) {
        continue;
      }

      for (final parameter in signature.parameters) {
        if (parameter.name.startsWith('_')) {
          continue;
        }

        final bodyReferences = snapshot
            .referencesForTarget(parameter.range)
            .where(
              (reference) =>
                  !reference.isDeclaration &&
                  bodyRange.intersects(reference.range),
            )
            .toList(growable: false);
        if (bodyReferences.isNotEmpty) {
          continue;
        }

        final remainingParameters = [
          for (final item in signature.parameters)
            if (item.name != parameter.name)
              ChangeSignatureParameterUpdate(
                originalName: item.name,
                name: item.name,
              ),
        ];
        final plan = changeSignature(
          source,
          signature.nameRange.start,
          newName: signature.name,
          parameters: remainingParameters,
        );
        if (plan == null || plan.hasConflicts || plan.edits.isEmpty) {
          continue;
        }

        issues.add(
          StyioUnusedParameterIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'unused-parameter',
              message:
                  'Parameter `${parameter.name}` is never used in '
                  '`${signature.name}`.',
              range: parameter.range,
            ),
            functionName: signature.name,
            parameterName: parameter.name,
            edits: plan.edits,
          ),
        );
      }
    }

    return issues;
  }

  Map<String, List<_FunctionSignature>> _collectFunctionSignatures(
    List<TokenSpan> tokens,
  ) {
    final signaturesByName = <String, List<_FunctionSignature>>{};

    void addSignature({
      required TokenSpan nameToken,
      required int openingIndex,
      required String prefix,
      required SourceRange declarationRange,
    }) {
      final closingIndex = _matchingParenthesisIndex(tokens, openingIndex);
      if (closingIndex == null) {
        return;
      }
      final parameters = _parseParameters(
        tokens: tokens,
        openingIndex: openingIndex,
        closingIndex: closingIndex,
      );
      final returnType = _functionReturnTypeText(
        tokens: tokens,
        closingIndex: closingIndex,
      );
      final signature = _FunctionSignature(
        name: nameToken.lexeme,
        nameRange: nameToken.range,
        prefix: prefix,
        openingIndex: openingIndex,
        closingIndex: closingIndex,
        parameters: parameters,
        returnType: returnType,
        displayText:
            '${prefix == '#' ? '#' : '$prefix '}${nameToken.lexeme}'
            '(${parameters.map((parameter) => parameter.displayText).join(', ')})',
        documentation: _leadingDocumentationForDeclaration(
          tokens,
          declarationRange,
        ),
      );
      signaturesByName
          .putIfAbsent(signature.name, () => <_FunctionSignature>[])
          .add(signature);
    }

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.keyword && token.lexeme == 'fn') {
        final nameIndex = _nextIdentifierIndex(tokens, index + 1);
        if (nameIndex == null) {
          continue;
        }
        final openingIndex = _functionParameterOpeningIndex(
          tokens,
          nameIndex + 1,
        );
        if (openingIndex == null || tokens[openingIndex].lexeme != '(') {
          continue;
        }
        addSignature(
          nameToken: tokens[nameIndex],
          openingIndex: openingIndex,
          prefix: 'fn',
          declarationRange: SourceRange(
            start: token.range.start,
            end: tokens[openingIndex].range.end,
          ),
        );
        continue;
      }

      if (token.lexeme == '#') {
        final nameIndex = _nextIdentifierIndex(tokens, index + 1);
        if (nameIndex == null) {
          continue;
        }
        final openingIndex = _functionParameterOpeningIndex(
          tokens,
          nameIndex + 1,
        );
        if (openingIndex == null || tokens[openingIndex].lexeme != '(') {
          continue;
        }
        addSignature(
          nameToken: tokens[nameIndex],
          openingIndex: openingIndex,
          prefix: '#',
          declarationRange: SourceRange(
            start: token.range.start,
            end: tokens[openingIndex].range.end,
          ),
        );
      }
    }

    return signaturesByName;
  }

  String _functionReturnTypeText({
    required List<TokenSpan> tokens,
    required int closingIndex,
  }) {
    final colonIndex = _nextSignificantIndex(tokens, closingIndex + 1);
    if (colonIndex == null || tokens[colonIndex].lexeme != ':') {
      return '';
    }

    final parts = <String>[];
    for (var index = colonIndex + 1; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.lexeme.contains('\n')) {
        break;
      }
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      if (token.lexeme == '{' || token.lexeme == '=>') {
        break;
      }
      parts.add(token.lexeme);
    }
    return parts.join();
  }

  _FunctionSignature? _functionSignatureForTarget(
    List<TokenSpan> tokens,
    DocumentSymbol target,
  ) {
    for (final signatures in _collectFunctionSignatures(tokens).values) {
      for (final signature in signatures) {
        if (_sameRange(signature.nameRange, target.nameRange)) {
          return signature;
        }
      }
    }
    return null;
  }

  List<ParameterInfoParameter> _parseParameters({
    required List<TokenSpan> tokens,
    required int openingIndex,
    required int closingIndex,
  }) {
    final parameters = <ParameterInfoParameter>[];
    var segmentStartIndex = openingIndex + 1;
    var nestedDepth = 0;

    void parseSegment(int endExclusive) {
      final parameter = _parseParameterSegment(
        tokens,
        segmentStartIndex,
        endExclusive,
      );
      if (parameter != null) {
        parameters.add(parameter);
      }
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
        parseSegment(index);
        segmentStartIndex = index + 1;
      }
    }

    parseSegment(closingIndex);
    return parameters;
  }

  ParameterInfoParameter? _parseParameterSegment(
    List<TokenSpan> tokens,
    int startIndex,
    int endExclusive,
  ) {
    TokenSpan? nameToken;
    var nameIndex = -1;
    for (var index = startIndex; index < endExclusive; index += 1) {
      final token = tokens[index];
      if (token.kind != TokenKind.identifier ||
          _syntaxHighlighter.isTypeName(token.lexeme)) {
        continue;
      }
      nameToken = token;
      nameIndex = index;
      break;
    }
    if (nameToken == null) {
      return null;
    }

    final typeText = _parameterTypeText(
      tokens: tokens,
      startIndex: nameIndex + 1,
      endExclusive: endExclusive,
    );
    return ParameterInfoParameter(
      name: nameToken.lexeme,
      type: typeText,
      range: nameToken.range,
    );
  }

  String _parameterTypeText({
    required List<TokenSpan> tokens,
    required int startIndex,
    required int endExclusive,
  }) {
    final colonIndex = _firstLexemeIndex(
      tokens: tokens,
      lexeme: ':',
      startIndex: startIndex,
      endExclusive: endExclusive,
    );
    if (colonIndex == null) {
      return '';
    }

    final parts = <String>[];
    for (var index = colonIndex + 1; index < endExclusive; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      if (token.lexeme == '=') {
        break;
      }
      parts.add(token.lexeme);
    }
    return parts.join();
  }

  int? _firstLexemeIndex({
    required List<TokenSpan> tokens,
    required String lexeme,
    required int startIndex,
    required int endExclusive,
  }) {
    for (var index = startIndex; index < endExclusive; index += 1) {
      if (tokens[index].lexeme == lexeme) {
        return index;
      }
    }
    return null;
  }

  _CallArgumentList? _callArgumentListAt(List<TokenSpan> tokens, int offset) {
    _CallArgumentList? best;
    for (final call in _callArgumentLists(tokens)) {
      final openingToken = tokens[call.openingIndex];
      final closingToken = tokens[call.closingIndex];
      if (offset < openingToken.range.start ||
          offset > closingToken.range.end) {
        continue;
      }

      if (best == null ||
          tokens[call.openingIndex].range.start >
              tokens[best.openingIndex].range.start) {
        best = call;
      }
    }
    return best;
  }

  List<_CallArgumentList> _callArgumentLists(List<TokenSpan> tokens) {
    final calls = <_CallArgumentList>[];
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.lexeme != '(') {
        continue;
      }
      final closingIndex = _matchingParenthesisIndex(tokens, index);
      if (closingIndex == null) {
        continue;
      }

      final callableIndex = _previousSignificantIndex(tokens, index - 1);
      if (callableIndex == null ||
          tokens[callableIndex].kind != TokenKind.identifier) {
        continue;
      }
      final declarationPrefixIndex = _previousSignificantIndex(
        tokens,
        callableIndex - 1,
      );
      final declarationPrefix = declarationPrefixIndex == null
          ? null
          : tokens[declarationPrefixIndex].lexeme;
      if (declarationPrefix == 'fn' || declarationPrefix == '#') {
        continue;
      }

      calls.add(
        _CallArgumentList(
          callable: tokens[callableIndex],
          openingIndex: index,
          closingIndex: closingIndex,
        ),
      );
    }
    return calls;
  }

  _CallArgumentList? _callArgumentListAfter(
    List<TokenSpan> tokens,
    int callableIndex,
  ) {
    final openingIndex = _nextSignificantIndex(tokens, callableIndex + 1);
    if (openingIndex == null || tokens[openingIndex].lexeme != '(') {
      return null;
    }
    final closingIndex = _matchingParenthesisIndex(tokens, openingIndex);
    if (closingIndex == null) {
      return null;
    }
    return _CallArgumentList(
      callable: tokens[callableIndex],
      openingIndex: openingIndex,
      closingIndex: closingIndex,
    );
  }

  List<_ArgumentSegment> _parseCallArguments({
    required String source,
    required List<TokenSpan> tokens,
    required int openingIndex,
    required int closingIndex,
  }) {
    final arguments = <_ArgumentSegment>[];
    var segmentStart = tokens[openingIndex].range.end;
    var nestedDepth = 0;

    void parseSegment(int segmentEnd) {
      final range = _trimmedRange(
        source,
        SourceRange(start: segmentStart, end: segmentEnd),
      );
      if (range.isCollapsed) {
        return;
      }
      arguments.add(
        _ArgumentSegment(
          range: range,
          text: source.substring(range.start, range.end),
        ),
      );
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
        parseSegment(token.range.start);
        segmentStart = token.range.end;
      }
    }

    parseSegment(tokens[closingIndex].range.start);
    return arguments;
  }

  bool _shouldSuppressParameterNameHint(
    ParameterInfoParameter parameter,
    _ArgumentSegment argument,
  ) {
    return argument.text == parameter.name;
  }

  int _activeParameterIndex({
    required List<TokenSpan> tokens,
    required int openingIndex,
    required int closingIndex,
    required int offset,
  }) {
    var activeParameterIndex = 0;
    var nestedDepth = 0;
    for (var index = openingIndex + 1; index < closingIndex; index += 1) {
      final token = tokens[index];
      if (token.range.start >= offset) {
        break;
      }
      if (token.kind == TokenKind.punctuation && token.lexeme == '(') {
        nestedDepth += 1;
        continue;
      }
      if (token.kind == TokenKind.punctuation && token.lexeme == ')') {
        nestedDepth -= 1;
        continue;
      }
      if (nestedDepth == 0 &&
          token.lexeme == ',' &&
          token.range.end <= offset) {
        activeParameterIndex += 1;
      }
    }
    return activeParameterIndex;
  }

  int? _tokenIndexForRange(List<TokenSpan> tokens, SourceRange range) {
    for (var index = 0; index < tokens.length; index += 1) {
      if (_sameRange(tokens[index].range, range)) {
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

  int? _matchingBraceIndex(List<TokenSpan> tokens, int openingIndex) {
    var depth = 0;
    for (var index = openingIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.punctuation && token.lexeme == '{') {
        depth += 1;
        continue;
      }
      if (token.kind == TokenKind.punctuation && token.lexeme == '}') {
        depth -= 1;
        if (depth == 0) {
          return index;
        }
      }
    }
    return null;
  }

  void _addParametersAfter({
    required List<TokenSpan> tokens,
    required int startIndex,
    required void Function({
      required TokenSpan nameToken,
      required SymbolKind kind,
      required SourceRange declarationRange,
      required String detail,
    })
    addSymbol,
  }) {
    final openingIndex = _functionParameterOpeningIndex(tokens, startIndex);
    if (openingIndex != null) {
      _addParametersInDelimitedList(
        tokens: tokens,
        openingIndex: openingIndex,
        addSymbol: addSymbol,
      );
    }
  }

  int? _functionParameterOpeningIndex(List<TokenSpan> tokens, int startIndex) {
    var index = _nextSignificantIndex(tokens, startIndex);
    if (index == null) {
      return null;
    }
    if (tokens[index].lexeme == ':=' || tokens[index].lexeme == '=') {
      index = _nextSignificantIndex(tokens, index + 1);
      if (index == null) {
        return null;
      }
    }
    return tokens[index].lexeme == '(' ? index : null;
  }

  void _addParametersInDelimitedList({
    required List<TokenSpan> tokens,
    required int openingIndex,
    required void Function({
      required TokenSpan nameToken,
      required SymbolKind kind,
      required SourceRange declarationRange,
      required String detail,
    })
    addSymbol,
  }) {
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
          return;
        }
        continue;
      }
      if (depth != 1 || token.kind != TokenKind.identifier) {
        continue;
      }

      final previous = _previousSignificant(tokens, index - 1);
      final next = _nextSignificant(tokens, index + 1);
      final candidateBoundary =
          next?.lexeme == ':' ||
          next?.lexeme == ',' ||
          next?.lexeme == ')' ||
          previous?.lexeme == '(' ||
          previous?.lexeme == ',';
      if (!candidateBoundary || _syntaxHighlighter.isTypeName(token.lexeme)) {
        continue;
      }

      addSymbol(
        nameToken: token,
        kind: SymbolKind.parameter,
        declarationRange: token.range,
        detail: 'Styio parameter',
      );
    }
  }

  List<ReferenceSpan> _resolveReferences(
    List<TokenSpan> tokens,
    Map<String, List<DocumentSymbol>> symbolsByName,
  ) {
    final references = <ReferenceSpan>[];
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind != TokenKind.identifier) {
        continue;
      }
      final candidates = symbolsByName[token.lexeme];
      if (candidates == null || candidates.isEmpty) {
        continue;
      }

      final exactDeclaration = candidates.cast<DocumentSymbol?>().firstWhere(
        (symbol) =>
            symbol != null &&
            symbol.nameRange.start == token.range.start &&
            symbol.nameRange.end == token.range.end,
        orElse: () => null,
      );
      final target = exactDeclaration ?? _nearestDeclaration(candidates, token);
      if (target == null) {
        continue;
      }

      references.add(
        ReferenceSpan(
          name: token.lexeme,
          kind: target.kind,
          range: token.range,
          targetRange: target.nameRange,
          isDeclaration: exactDeclaration != null,
          access: exactDeclaration != null
              ? ReferenceAccess.declaration
              : _referenceAccess(tokens, index, target.kind),
        ),
      );
    }
    return references;
  }

  ReferenceAccess _referenceAccess(
    List<TokenSpan> tokens,
    int tokenIndex,
    SymbolKind targetKind,
  ) {
    if (targetKind == SymbolKind.resource) {
      final previousIndex = _previousSignificantIndex(tokens, tokenIndex - 1);
      if (previousIndex != null && tokens[previousIndex].lexeme == '@') {
        final beforeAtIndex = _previousSignificantIndex(
          tokens,
          previousIndex - 1,
        );
        final beforeAt = beforeAtIndex == null ? null : tokens[beforeAtIndex];
        if (beforeAt?.lexeme == '->' || beforeAt?.lexeme == '>>') {
          return ReferenceAccess.write;
        }
      }
    }

    return ReferenceAccess.read;
  }

  DocumentSymbol? _nearestDeclaration(
    List<DocumentSymbol> candidates,
    TokenSpan token,
  ) {
    DocumentSymbol? best;
    for (final candidate in candidates) {
      if (candidate.nameRange.start > token.range.start) {
        continue;
      }
      if (best == null || candidate.nameRange.start > best.nameRange.start) {
        best = candidate;
      }
    }
    return best ?? candidates.first;
  }

  SourceRange _declarationRange(List<TokenSpan> tokens, int tokenIndex) {
    final start = tokens[tokenIndex].range.start;
    var end = tokens[tokenIndex].range.end;

    for (var index = tokenIndex + 1; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.lexeme.contains('\n')) {
        break;
      }
      end = token.range.end;
    }

    return SourceRange(start: start, end: end);
  }

  String _leadingDocumentationForDeclaration(
    List<TokenSpan> tokens,
    SourceRange declarationRange,
  ) {
    final declarationIndex = tokens.indexWhere(
      (token) => token.range.start >= declarationRange.start,
    );
    if (declarationIndex <= 0) {
      return '';
    }

    final lines = <String>[];
    var index = declarationIndex - 1;
    while (index >= 0) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace) {
        if (_blankLineCount(token.lexeme) > 0) {
          break;
        }
        index -= 1;
        continue;
      }
      if (token.kind != TokenKind.comment || !token.lexeme.startsWith('///')) {
        break;
      }
      lines.add(_documentationTextForComment(token.lexeme));
      index -= 1;
    }

    return lines.reversed.map((line) => line.trimRight()).join('\n').trim();
  }

  int _blankLineCount(String whitespace) {
    var newlineCount = 0;
    for (var index = 0; index < whitespace.length; index += 1) {
      if (whitespace[index] == '\n') {
        newlineCount += 1;
      }
    }
    return newlineCount > 1 ? newlineCount - 1 : 0;
  }

  String _documentationTextForComment(String lexeme) {
    final text = lexeme.substring(3);
    return text.startsWith(' ') ? text.substring(1) : text;
  }

  TokenSpan? _nextIdentifier(List<TokenSpan> tokens, int startIndex) {
    final index = _nextIdentifierIndex(tokens, startIndex);
    return index == null ? null : tokens[index];
  }

  int? _nextIdentifierIndex(List<TokenSpan> tokens, int startIndex) {
    for (var index = startIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      if (token.kind == TokenKind.identifier) {
        return index;
      }
      return null;
    }
    return null;
  }

  TokenSpan? _nextSignificant(List<TokenSpan> tokens, int startIndex) {
    final index = _nextSignificantIndex(tokens, startIndex);
    return index == null ? null : tokens[index];
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

  TokenSpan? _previousSignificant(List<TokenSpan> tokens, int startIndex) {
    final index = _previousSignificantIndex(tokens, startIndex);
    return index == null ? null : tokens[index];
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

  bool _hasLineBreakBetween(
    List<TokenSpan> tokens,
    int startIndex,
    int endExclusive,
  ) {
    for (var index = startIndex; index < endExclusive; index += 1) {
      if (tokens[index].lexeme.contains('\n')) {
        return true;
      }
    }
    return false;
  }

  TokenSpan? _tokenAroundOffset(List<TokenSpan> tokens, int offset) {
    TokenSpan? trailingToken;
    TokenSpan? leadingToken;

    for (final token in tokens) {
      if (token.kind == TokenKind.whitespace) {
        continue;
      }

      if (token.range.contains(offset)) {
        return token;
      }
      if (token.range.end == offset) {
        trailingToken = token;
      }
      if (leadingToken == null && token.range.start == offset) {
        leadingToken = token;
      }
    }

    return trailingToken ?? leadingToken;
  }

  List<RenameConflict> _renameConflicts({
    required StyioSymbolSnapshot snapshot,
    required DocumentSymbol target,
    required String newName,
  }) {
    if (newName == target.name) {
      return const <RenameConflict>[];
    }

    return snapshot.symbols
        .where(
          (symbol) =>
              symbol.name == newName &&
              !_sameRange(symbol.nameRange, target.nameRange),
        )
        .map(
          (symbol) => RenameConflict(
            message:
                'Name `$newName` already declares a current-file '
                '${symbol.kind.name}.',
            range: symbol.nameRange,
          ),
        )
        .toList(growable: false);
  }

  bool _sameRange(SourceRange left, SourceRange right) {
    return left.start == right.start && left.end == right.end;
  }

  bool _sameParameterOrder(
    List<String> originalNames,
    List<ChangeSignatureParameterUpdate> parameters,
  ) {
    if (originalNames.length != parameters.length) {
      return false;
    }
    for (var index = 0; index < originalNames.length; index += 1) {
      if (originalNames[index] != parameters[index].originalName) {
        return false;
      }
    }
    return true;
  }

  SourceRange? _parameterRange(
    _FunctionSignature signature,
    String parameterName,
  ) {
    for (final parameter in signature.parameters) {
      if (parameter.name == parameterName) {
        return parameter.range;
      }
    }
    return null;
  }

  String _changeSignatureParameterText(
    _FunctionSignature signature,
    ChangeSignatureParameterUpdate parameter,
  ) {
    final original = signature.parameters.firstWhere(
      (item) => item.name == parameter.originalName,
    );
    return original.type.isEmpty
        ? parameter.name
        : '${parameter.name}: ${original.type}';
  }

  bool _parameterHasDefaultValue(
    List<TokenSpan> tokens,
    _FunctionSignature signature,
    String parameterName,
  ) {
    final parameterRange = _parameterRange(signature, parameterName);
    if (parameterRange == null) {
      return false;
    }
    final parameterIndex = _tokenIndexForRange(tokens, parameterRange);
    if (parameterIndex == null) {
      return false;
    }
    var nestedDepth = 0;
    for (
      var index = parameterIndex + 1;
      index < signature.closingIndex;
      index += 1
    ) {
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
        return false;
      }
      if (nestedDepth == 0 && token.lexeme == '=') {
        return true;
      }
    }
    return false;
  }

  SourceRange? _functionBodyRange(
    List<TokenSpan> tokens,
    _FunctionSignature signature,
  ) {
    var index = _nextSignificantIndex(tokens, signature.closingIndex + 1);
    while (index != null && index < tokens.length) {
      final token = tokens[index];
      if (token.lexeme == '{') {
        final closingIndex = _matchingBraceIndex(tokens, index);
        if (closingIndex == null) {
          return null;
        }
        return SourceRange(
          start: token.range.end,
          end: tokens[closingIndex].range.start,
        );
      }
      if (token.lexeme != '=>' && token.lexeme != ':=' && token.lexeme != '=') {
        return null;
      }
      index = _nextSignificantIndex(tokens, index + 1);
    }
    return null;
  }

  List<SafeDeleteConflict> _safeDeleteConflicts({
    required DocumentSymbol target,
    required List<ReferenceSpan> references,
  }) {
    if (target.kind != SymbolKind.variable) {
      return [
        SafeDeleteConflict(
          message:
              'Safe delete currently supports current-file variable '
              'declarations.',
          range: target.nameRange,
        ),
      ];
    }

    return references
        .where((reference) => !reference.isDeclaration)
        .map(
          (reference) => SafeDeleteConflict(
            message: 'Symbol `${target.name}` is still used in this file.',
            range: reference.range,
          ),
        )
        .toList(growable: false);
  }

  List<InlineVariableConflict> _inlineVariableConflicts({
    required DocumentSymbol target,
    required _InlineVariableInitializer? initializer,
    required List<ReferenceSpan> references,
  }) {
    if (target.kind != SymbolKind.variable) {
      return [
        InlineVariableConflict(
          message:
              'Inline variable currently supports current-file variable '
              'declarations.',
          range: target.nameRange,
        ),
      ];
    }
    if (initializer == null) {
      return [
        InlineVariableConflict(
          message: 'Inline variable requires a declaration initializer.',
          range: target.nameRange,
        ),
      ];
    }

    final usageReferences = references
        .where((reference) => !reference.isDeclaration)
        .toList(growable: false);
    if (usageReferences.isEmpty) {
      return [
        InlineVariableConflict(
          message: 'Symbol `${target.name}` is never used in this file.',
          range: target.nameRange,
        ),
      ];
    }

    final conflicts = <InlineVariableConflict>[];
    for (final reference in usageReferences) {
      if (reference.range.intersects(target.declarationRange)) {
        conflicts.add(
          InlineVariableConflict(
            message:
                'Symbol `${target.name}` is referenced inside its '
                'initializer.',
            range: reference.range,
          ),
        );
        continue;
      }
      if (reference.access != ReferenceAccess.read) {
        conflicts.add(
          InlineVariableConflict(
            message:
                'Symbol `${target.name}` has a non-read usage in this file.',
            range: reference.range,
          ),
        );
      }
    }
    return conflicts;
  }

  List<IntroduceVariableConflict> _introduceVariableConflicts({
    required String source,
    required List<TokenSpan> tokens,
    required StyioSymbolSnapshot snapshot,
    required SourceRange expressionRange,
    required String expressionText,
    required String name,
  }) {
    final conflicts = <IntroduceVariableConflict>[];
    if (!_isValidIdentifier(name)) {
      conflicts.add(
        IntroduceVariableConflict(
          message: 'Enter a valid Styio identifier.',
          range: expressionRange,
        ),
      );
    }

    for (final symbol in snapshot.symbols) {
      if (symbol.name == name) {
        conflicts.add(
          IntroduceVariableConflict(
            message: 'Name `$name` already declares a current-file symbol.',
            range: symbol.nameRange,
          ),
        );
      }
    }

    if (expressionText.contains('\n')) {
      conflicts.add(
        IntroduceVariableConflict(
          message: 'Introduce Variable currently requires one expression line.',
          range: expressionRange,
        ),
      );
    }

    final selectedTokens = tokens
        .where((token) => token.range.intersects(expressionRange))
        .toList(growable: false);
    final significantTokens = selectedTokens
        .where(
          (token) =>
              token.kind != TokenKind.whitespace &&
              token.kind != TokenKind.comment,
        )
        .toList(growable: false);
    if (significantTokens.isEmpty) {
      conflicts.add(
        IntroduceVariableConflict(
          message: 'Select a Styio expression before introducing a variable.',
          range: expressionRange,
        ),
      );
    }
    if (selectedTokens.any((token) => token.kind == TokenKind.comment)) {
      conflicts.add(
        IntroduceVariableConflict(
          message: 'Cannot introduce a variable from a comment range.',
          range: expressionRange,
        ),
      );
    }
    if (_looksLikeAssignmentTarget(tokens, expressionRange)) {
      conflicts.add(
        IntroduceVariableConflict(
          message: 'Cannot introduce a variable from an assignment target.',
          range: expressionRange,
        ),
      );
    }
    if (expressionText.contains('=') ||
        expressionText.contains('->') ||
        expressionText.contains('>>')) {
      conflicts.add(
        IntroduceVariableConflict(
          message: 'Select an expression, not a binding or pipeline statement.',
          range: expressionRange,
        ),
      );
    }
    if (_lineInsertionRange(source, expressionRange.start).start >
        expressionRange.start) {
      conflicts.add(
        IntroduceVariableConflict(
          message: 'Cannot find a declaration anchor before the expression.',
          range: expressionRange,
        ),
      );
    }
    return conflicts;
  }

  List<ExtractFunctionConflict> _extractFunctionConflicts({
    required String source,
    required List<TokenSpan> tokens,
    required StyioSymbolSnapshot snapshot,
    required SourceRange selectionRange,
    required String selectedText,
    required String name,
    required _ExtractFunctionSelectionKind selectionKind,
  }) {
    final conflicts = <ExtractFunctionConflict>[];
    if (!_isValidIdentifier(name)) {
      conflicts.add(
        ExtractFunctionConflict(
          message: 'Enter a valid Styio function identifier.',
          range: selectionRange,
        ),
      );
    }

    for (final symbol in snapshot.symbols) {
      if (symbol.name == name) {
        conflicts.add(
          ExtractFunctionConflict(
            message: 'Name `$name` already declares a current-file symbol.',
            range: symbol.nameRange,
          ),
        );
      }
    }

    final selectedTokens = tokens
        .where((token) => token.range.intersects(selectionRange))
        .toList(growable: false);
    final significantTokens = selectedTokens
        .where(
          (token) =>
              token.kind != TokenKind.whitespace &&
              token.kind != TokenKind.comment,
        )
        .toList(growable: false);
    if (significantTokens.isEmpty) {
      conflicts.add(
        ExtractFunctionConflict(
          message: 'Select Styio code before extracting a function.',
          range: selectionRange,
        ),
      );
    }

    for (final token in significantTokens) {
      if (token.range.start < selectionRange.start ||
          token.range.end > selectionRange.end) {
        conflicts.add(
          ExtractFunctionConflict(
            message: 'Extract Function requires complete selected tokens.',
            range: token.range,
          ),
        );
        break;
      }
    }

    if (selectionKind == _ExtractFunctionSelectionKind.expression &&
        selectedText.contains('\n')) {
      conflicts.add(
        ExtractFunctionConflict(
          message:
              'Extract Function currently requires full-line selections for '
              'multi-line code.',
          range: selectionRange,
        ),
      );
    }

    if (selectionKind == _ExtractFunctionSelectionKind.expression &&
        _looksLikeAssignmentTarget(tokens, selectionRange)) {
      conflicts.add(
        ExtractFunctionConflict(
          message: 'Cannot extract a function from an assignment target.',
          range: selectionRange,
        ),
      );
    }

    final declarationToken = significantTokens.cast<TokenSpan?>().firstWhere(
      (token) =>
          token != null &&
          (token.lexeme == 'fn' ||
              token.lexeme == 'pipeline' ||
              token.lexeme == 'state' ||
              token.lexeme == '#'),
      orElse: () => null,
    );
    if (declarationToken != null) {
      conflicts.add(
        ExtractFunctionConflict(
          message:
              'Extract Function currently supports expressions and statement '
              'blocks, not declarations.',
          range: declarationToken.range,
        ),
      );
    }

    final braceConflict = _braceConflictForSelection(significantTokens);
    if (braceConflict != null) {
      conflicts.add(braceConflict);
    }

    return conflicts;
  }

  List<ChangeSignatureConflict> _changeSignatureConflicts({
    required String source,
    required List<TokenSpan> tokens,
    required StyioSymbolSnapshot snapshot,
    required DocumentSymbol target,
    required _FunctionSignature signature,
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
    required List<ReferenceSpan> references,
  }) {
    final conflicts = <ChangeSignatureConflict>[];
    if (!_isValidIdentifier(newName)) {
      conflicts.add(
        ChangeSignatureConflict(
          message: 'Enter a valid Styio function identifier.',
          range: target.nameRange,
        ),
      );
    }

    if (newName != target.name) {
      for (final symbol in snapshot.symbols) {
        if (symbol.name == newName &&
            !_sameRange(symbol.nameRange, target.nameRange)) {
          conflicts.add(
            ChangeSignatureConflict(
              message:
                  'Name `$newName` already declares a current-file '
                  '${symbol.kind.name}.',
              range: symbol.nameRange,
            ),
          );
        }
      }
    }

    final originalNames = signature.parameters
        .map((parameter) => parameter.name)
        .toList(growable: false);
    final originalNameSet = originalNames.toSet();
    final requestedOriginals = <String>{};
    final requestedNames = <String>{};
    for (final parameter in parameters) {
      if (!originalNameSet.contains(parameter.originalName)) {
        conflicts.add(
          ChangeSignatureConflict(
            message:
                'Parameter `${parameter.originalName}` is not in the current '
                'function signature.',
            range: target.nameRange,
          ),
        );
        continue;
      }
      if (!requestedOriginals.add(parameter.originalName)) {
        conflicts.add(
          ChangeSignatureConflict(
            message:
                'Parameter `${parameter.originalName}` appears more than once '
                'in the requested signature.',
            range:
                _parameterRange(signature, parameter.originalName) ??
                target.nameRange,
          ),
        );
      }
      if (!_isValidIdentifier(parameter.name)) {
        conflicts.add(
          ChangeSignatureConflict(
            message: 'Enter valid Styio parameter identifiers.',
            range:
                _parameterRange(signature, parameter.originalName) ??
                target.nameRange,
          ),
        );
      } else if (!requestedNames.add(parameter.name)) {
        conflicts.add(
          ChangeSignatureConflict(
            message:
                'Parameter `${parameter.name}` appears more than once in the '
                'requested signature.',
            range:
                _parameterRange(signature, parameter.originalName) ??
                target.nameRange,
          ),
        );
      }
      if (_parameterHasDefaultValue(
        tokens,
        signature,
        parameter.originalName,
      )) {
        conflicts.add(
          ChangeSignatureConflict(
            message:
                'Change Signature currently does not rewrite default '
                'parameter values.',
            range:
                _parameterRange(signature, parameter.originalName) ??
                target.nameRange,
          ),
        );
      }
    }

    if (requestedOriginals.length != parameters.length) {
      conflicts.add(
        ChangeSignatureConflict(
          message:
              'Change Signature currently only reuses existing parameters.',
          range: target.nameRange,
        ),
      );
    }

    final removedOriginalNames = originalNames
        .where((name) => !requestedOriginals.contains(name))
        .toList(growable: false);
    final bodyRange = _functionBodyRange(tokens, signature);
    for (final removedName in removedOriginalNames) {
      final removedRange = _parameterRange(signature, removedName);
      if (removedRange == null) {
        continue;
      }
      final bodyReferences = snapshot
          .referencesForTarget(removedRange)
          .where(
            (reference) =>
                !reference.isDeclaration &&
                bodyRange != null &&
                bodyRange.intersects(reference.range),
          )
          .toList(growable: false);
      if (bodyReferences.isNotEmpty) {
        conflicts.add(
          ChangeSignatureConflict(
            message:
                'Cannot remove parameter `$removedName` while it is used in '
                'the function body.',
            range: bodyReferences.first.range,
          ),
        );
      }
    }

    final hasParameterRenames = parameters.any(
      (parameter) => parameter.name != parameter.originalName,
    );
    final hasParameterReorder = !_sameParameterOrder(originalNames, parameters);
    final hasParameterRemoval = removedOriginalNames.isNotEmpty;
    if (hasParameterRenames && (hasParameterReorder || hasParameterRemoval)) {
      conflicts.add(
        ChangeSignatureConflict(
          message:
              'Change Signature currently applies parameter rename and '
              'parameter reorder/removal as separate safe steps.',
          range: target.nameRange,
        ),
      );
    }

    if (hasParameterReorder || hasParameterRemoval) {
      for (final reference in references.where((item) => !item.isDeclaration)) {
        final referenceIndex = _tokenIndexForRange(tokens, reference.range);
        final call = referenceIndex == null
            ? null
            : _callArgumentListAfter(tokens, referenceIndex);
        if (call == null) {
          conflicts.add(
            ChangeSignatureConflict(
              message:
                  'Cannot update non-call usage of `${target.name}` for '
                  'parameter reordering.',
              range: reference.range,
            ),
          );
          continue;
        }

        final arguments = _parseCallArguments(
          source: source,
          tokens: tokens,
          openingIndex: call.openingIndex,
          closingIndex: call.closingIndex,
        );
        if (arguments.length != originalNames.length) {
          conflicts.add(
            ChangeSignatureConflict(
              message:
                  'Call to `${target.name}` has ${arguments.length} '
                  'argument${arguments.length == 1 ? '' : 's'}, expected '
                  '${originalNames.length}.',
              range: SourceRange(
                start: call.callable.range.start,
                end: tokens[call.closingIndex].range.end,
              ),
            ),
          );
        }
      }
    }

    return conflicts;
  }

  List<FormattingEdit> _changeSignatureEdits({
    required String source,
    required List<TokenSpan> tokens,
    required StyioSymbolSnapshot snapshot,
    required DocumentSymbol target,
    required _FunctionSignature signature,
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
    required List<ReferenceSpan> references,
  }) {
    final edits = <FormattingEdit>[];
    final originalNames = signature.parameters
        .map((parameter) => parameter.name)
        .toList(growable: false);
    final hasParameterReorder = !_sameParameterOrder(originalNames, parameters);
    final hasParameterRemoval = parameters.length != originalNames.length;
    final shouldRewriteArguments = hasParameterReorder || hasParameterRemoval;

    if (newName != target.name) {
      for (final reference in references) {
        edits.add(FormattingEdit(range: reference.range, newText: newName));
      }
    }

    final parameterListRange = SourceRange(
      start: tokens[signature.openingIndex].range.end,
      end: tokens[signature.closingIndex].range.start,
    );
    final nextParameterText = parameters
        .map((parameter) => _changeSignatureParameterText(signature, parameter))
        .join(', ');
    if (source.substring(parameterListRange.start, parameterListRange.end) !=
        nextParameterText) {
      edits.add(
        FormattingEdit(range: parameterListRange, newText: nextParameterText),
      );
    }

    final bodyRange = _functionBodyRange(tokens, signature);
    for (final parameter in parameters) {
      if (parameter.name == parameter.originalName) {
        continue;
      }
      final originalRange = _parameterRange(signature, parameter.originalName);
      if (originalRange == null) {
        continue;
      }
      for (final reference in snapshot.referencesForTarget(originalRange)) {
        if (reference.isDeclaration ||
            bodyRange == null ||
            !bodyRange.intersects(reference.range)) {
          continue;
        }
        edits.add(
          FormattingEdit(range: reference.range, newText: parameter.name),
        );
      }
    }

    if (shouldRewriteArguments) {
      for (final reference in references.where((item) => !item.isDeclaration)) {
        final referenceIndex = _tokenIndexForRange(tokens, reference.range);
        final call = referenceIndex == null
            ? null
            : _callArgumentListAfter(tokens, referenceIndex);
        if (call == null) {
          continue;
        }
        final arguments = _parseCallArguments(
          source: source,
          tokens: tokens,
          openingIndex: call.openingIndex,
          closingIndex: call.closingIndex,
        );
        if (arguments.length != originalNames.length) {
          continue;
        }
        final nextArgumentText = parameters
            .map(
              (parameter) =>
                  arguments[originalNames.indexOf(parameter.originalName)].text,
            )
            .join(', ');
        final argumentListRange = SourceRange(
          start: tokens[call.openingIndex].range.end,
          end: tokens[call.closingIndex].range.start,
        );
        if (source.substring(argumentListRange.start, argumentListRange.end) !=
            nextArgumentText) {
          edits.add(
            FormattingEdit(range: argumentListRange, newText: nextArgumentText),
          );
        }
      }
    }

    return edits;
  }

  ExtractFunctionConflict? _braceConflictForSelection(List<TokenSpan> tokens) {
    var depth = 0;
    for (final token in tokens) {
      if (token.lexeme == '{') {
        depth += 1;
        continue;
      }
      if (token.lexeme == '}') {
        depth -= 1;
        if (depth < 0) {
          return ExtractFunctionConflict(
            message: 'Extract Function selection has unmatched closing brace.',
            range: token.range,
          );
        }
      }
    }
    if (depth != 0 && tokens.isNotEmpty) {
      return ExtractFunctionConflict(
        message: 'Extract Function selection has unmatched opening brace.',
        range: tokens.last.range,
      );
    }
    return null;
  }

  List<String> _extractFunctionParameters({
    required StyioSymbolSnapshot snapshot,
    required SourceRange selectionRange,
  }) {
    final parameters = <String>[];
    final seen = <String>{};
    for (final reference in snapshot.references) {
      if (reference.isDeclaration ||
          !reference.range.intersects(selectionRange) ||
          reference.targetRange.intersects(selectionRange) ||
          reference.access != ReferenceAccess.read ||
          (reference.kind != SymbolKind.variable &&
              reference.kind != SymbolKind.parameter)) {
        continue;
      }
      if (seen.add(reference.name)) {
        parameters.add(reference.name);
      }
    }
    return parameters;
  }

  List<SourceRange> _extractFunctionDuplicateOccurrences({
    required String source,
    required List<TokenSpan> tokens,
    required SourceRange selectionRange,
    required String selectedText,
  }) {
    if (selectedText.isEmpty) {
      return const <SourceRange>[];
    }

    final occurrences = <SourceRange>[];
    var cursor = 0;
    while (cursor < source.length) {
      final index = source.indexOf(selectedText, cursor);
      if (index < 0) {
        break;
      }
      final range = SourceRange(start: index, end: index + selectedText.length);
      cursor = range.end;
      if (_sameRange(range, selectionRange) ||
          range.intersects(selectionRange) ||
          !_rangeCoversCompleteSignificantTokens(tokens, range) ||
          _rangeIntersectsTokenKind(tokens, range, TokenKind.comment)) {
        continue;
      }
      occurrences.add(range);
    }
    return occurrences;
  }

  bool _rangeCoversCompleteSignificantTokens(
    List<TokenSpan> tokens,
    SourceRange range,
  ) {
    var hasSignificantToken = false;
    for (final token in tokens) {
      if (!token.range.intersects(range) ||
          token.kind == TokenKind.whitespace) {
        continue;
      }
      hasSignificantToken = true;
      if (token.range.start < range.start || token.range.end > range.end) {
        return false;
      }
    }
    return hasSignificantToken;
  }

  bool _rangeIntersectsTokenKind(
    List<TokenSpan> tokens,
    SourceRange range,
    TokenKind kind,
  ) {
    return tokens.any(
      (token) => token.kind == kind && token.range.intersects(range),
    );
  }

  String _extractFunctionCallText({
    required String name,
    required List<String> parameters,
  }) {
    return '$name(${parameters.join(', ')})';
  }

  String _extractFunctionDeclarationText({
    required String name,
    required List<String> parameters,
    required _ExtractFunctionSelectionKind selectionKind,
    required String selectedText,
  }) {
    final buffer = StringBuffer()
      ..write('#')
      ..write(name)
      ..write(' := (')
      ..write(parameters.join(', '))
      ..writeln(') => {');

    if (selectionKind == _ExtractFunctionSelectionKind.expression) {
      buffer
        ..write('  <| ')
        ..writeln(selectedText.trim());
    } else {
      for (final line in selectedText.split('\n')) {
        if (line.isEmpty) {
          buffer.writeln();
        } else {
          buffer
            ..write('  ')
            ..writeln(line);
        }
      }
    }

    buffer
      ..writeln('}')
      ..writeln();
    return buffer.toString();
  }

  SourceRange _extractFunctionInsertionRange(String source) {
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

  _ExtractFunctionSelectionKind _extractFunctionSelectionKind(
    String source,
    SourceRange selectionRange,
  ) {
    if (_selectionStartsAtLineContent(source, selectionRange) &&
        _selectionEndsAtLineContent(source, selectionRange)) {
      return _ExtractFunctionSelectionKind.statements;
    }
    return _ExtractFunctionSelectionKind.expression;
  }

  bool _selectionStartsAtLineContent(String source, SourceRange range) {
    final lineStart = _lineInsertionRange(source, range.start).start;
    for (var index = lineStart; index < range.start; index += 1) {
      final codeUnit = source.codeUnitAt(index);
      if (codeUnit != 0x20 && codeUnit != 0x09) {
        return false;
      }
    }
    return true;
  }

  bool _selectionEndsAtLineContent(String source, SourceRange range) {
    var lineEnd = source.indexOf('\n', range.end);
    if (lineEnd < 0) {
      lineEnd = source.length;
    }
    for (var index = range.end; index < lineEnd; index += 1) {
      final codeUnit = source.codeUnitAt(index);
      if (codeUnit != 0x20 && codeUnit != 0x09) {
        return false;
      }
    }
    return true;
  }

  _InlineVariableInitializer? _variableInitializer(
    String source,
    List<TokenSpan> tokens,
    DocumentSymbol target,
  ) {
    final nameIndex = tokens.indexWhere(
      (token) =>
          token.range.start == target.nameRange.start &&
          token.range.end == target.nameRange.end,
    );
    if (nameIndex < 0) {
      return null;
    }

    for (var index = nameIndex + 1; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.range.start >= target.declarationRange.end ||
          token.lexeme.contains('\n')) {
        break;
      }
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      if (token.lexeme != '=' && token.lexeme != ':=') {
        continue;
      }

      var initializerStart = token.range.end;
      var initializerEnd = target.declarationRange.end;
      while (initializerStart < initializerEnd &&
          source.codeUnitAt(initializerStart) <= 0x20) {
        initializerStart += 1;
      }
      while (initializerEnd > initializerStart &&
          source.codeUnitAt(initializerEnd - 1) <= 0x20) {
        initializerEnd -= 1;
      }
      if (initializerStart >= initializerEnd) {
        return null;
      }
      return _InlineVariableInitializer(
        range: SourceRange(start: initializerStart, end: initializerEnd),
        text: source.substring(initializerStart, initializerEnd),
      );
    }
    return null;
  }

  SourceRange _lineRemovalRange(String source, SourceRange range) {
    final normalizedStart = range.start.clamp(0, source.length);
    final normalizedEnd = range.end.clamp(normalizedStart, source.length);
    final previousNewline = normalizedStart <= 0
        ? -1
        : source.lastIndexOf('\n', normalizedStart - 1);
    final lineStart = previousNewline + 1;
    final nextNewline = source.indexOf('\n', normalizedEnd);
    if (nextNewline >= 0) {
      return SourceRange(start: lineStart, end: nextNewline + 1);
    }
    if (lineStart > 0) {
      return SourceRange(start: lineStart - 1, end: source.length);
    }
    return SourceRange(start: 0, end: source.length);
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

  bool _looksLikeAssignmentTarget(
    List<TokenSpan> tokens,
    SourceRange expressionRange,
  ) {
    final selectedIndexes = <int>[];
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      if (token.range.intersects(expressionRange)) {
        selectedIndexes.add(index);
      }
    }
    if (selectedIndexes.isEmpty) {
      return false;
    }

    final firstIndex = selectedIndexes.first;
    final lastIndex = selectedIndexes.last;
    final next = _nextSignificant(tokens, lastIndex + 1);
    final previous = _previousSignificant(tokens, firstIndex - 1);
    return next?.lexeme == '=' ||
        next?.lexeme == ':=' ||
        previous?.lexeme == '->';
  }

  bool _isValidIdentifier(String value) {
    if (value.isEmpty ||
        _syntaxHighlighter.isKeyword(value) ||
        _syntaxHighlighter.isTypeName(value)) {
      return false;
    }
    final identifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    return identifierPattern.hasMatch(value);
  }
}

class _FunctionSignature {
  const _FunctionSignature({
    required this.name,
    required this.nameRange,
    required this.prefix,
    required this.openingIndex,
    required this.closingIndex,
    required this.parameters,
    required this.returnType,
    required this.displayText,
    this.documentation = '',
  });

  final String name;
  final SourceRange nameRange;
  final String prefix;
  final int openingIndex;
  final int closingIndex;
  final List<ParameterInfoParameter> parameters;
  final String returnType;
  final String displayText;
  final String documentation;
}

class _CallArgumentList {
  const _CallArgumentList({
    required this.callable,
    required this.openingIndex,
    required this.closingIndex,
  });

  final TokenSpan callable;
  final int openingIndex;
  final int closingIndex;
}

class _ArgumentSegment {
  const _ArgumentSegment({required this.range, required this.text});

  final SourceRange range;
  final String text;
}

class _InlineVariableInitializer {
  const _InlineVariableInitializer({required this.range, required this.text});

  final SourceRange range;
  final String text;
}

enum _ExtractFunctionSelectionKind { expression, statements }

class StyioCallArgumentIssue {
  const StyioCallArgumentIssue({
    required this.diagnostic,
    required this.callableName,
    required this.expectedArgumentCount,
    required this.actualArgumentCount,
    required this.argumentListRange,
    required this.replacementArgumentText,
    this.missingParameterNames = const <String>[],
    this.extraArgumentCount = 0,
  });

  final Diagnostic diagnostic;
  final String callableName;
  final int expectedArgumentCount;
  final int actualArgumentCount;
  final SourceRange argumentListRange;
  final String replacementArgumentText;
  final List<String> missingParameterNames;
  final int extraArgumentCount;

  bool get hasMissingArguments => missingParameterNames.isNotEmpty;
  bool get hasExtraArguments => extraArgumentCount > 0;
}

class StyioUnusedParameterIssue {
  const StyioUnusedParameterIssue({
    required this.diagnostic,
    required this.functionName,
    required this.parameterName,
    required this.edits,
  });

  final Diagnostic diagnostic;
  final String functionName;
  final String parameterName;
  final List<FormattingEdit> edits;
}

class StyioSymbolSnapshot {
  const StyioSymbolSnapshot({required this.symbols, required this.references});

  final List<DocumentSymbol> symbols;
  final List<ReferenceSpan> references;

  ReferenceSpan? referenceAt(SourceRange range) {
    for (final reference in references) {
      if (reference.range.intersects(range)) {
        return reference;
      }
    }
    return null;
  }

  DocumentSymbol? symbolForTarget(SourceRange targetRange) {
    for (final symbol in symbols) {
      if (symbol.nameRange.start == targetRange.start &&
          symbol.nameRange.end == targetRange.end) {
        return symbol;
      }
    }
    return null;
  }

  List<ReferenceSpan> referencesForTarget(SourceRange targetRange) {
    return references
        .where(
          (reference) =>
              reference.targetRange.start == targetRange.start &&
              reference.targetRange.end == targetRange.end,
        )
        .toList(growable: false);
  }
}
