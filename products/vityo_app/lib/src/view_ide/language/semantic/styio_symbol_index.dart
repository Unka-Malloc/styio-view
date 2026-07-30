import '../contract/language_contract.dart';
import '../syntax/styio_syntax_highlighter.dart';

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

      if (token.lexeme == ':') {
        final previous = _previousSignificant(tokens, index - 1);
        final typeIndex = _nextSignificantIndex(tokens, index + 1);
        final assignmentIndex = typeIndex == null
            ? null
            : _nextSignificantIndex(tokens, typeIndex + 1);
        if (previous?.kind == TokenKind.identifier &&
            typeIndex != null &&
            _syntaxHighlighter.isTypeName(tokens[typeIndex].lexeme) &&
            assignmentIndex != null &&
            (tokens[assignmentIndex].lexeme == '=' ||
                tokens[assignmentIndex].lexeme == ':=')) {
          addSymbol(
            nameToken: previous!,
            kind: SymbolKind.variable,
            declarationRange: _declarationRange(
              tokens,
              tokens.indexOf(previous),
            ),
            detail: 'Styio typed value binding',
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

  List<DocumentSymbol> visibleSymbolsAt({
    required List<TokenSpan> tokens,
    required List<DocumentSymbol> symbols,
    required int offset,
  }) {
    final signatures = _collectFunctionSignatures(
      tokens,
    ).values.expand((items) => items).toList(growable: false);
    return [
      for (final symbol in symbols)
        if (_isSymbolVisibleFromOffset(
          tokens: tokens,
          signatures: signatures,
          symbol: symbol,
          offset: offset,
        ))
          symbol,
    ];
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
    final arguments = _parseCallArguments(
      source: source,
      tokens: tokens,
      openingIndex: call.openingIndex,
      closingIndex: call.closingIndex,
    );
    var activeParameterIndex = _activeParameterIndex(
      tokens: tokens,
      openingIndex: call.openingIndex,
      closingIndex: call.closingIndex,
      offset: offset,
    );
    final activeArgument = _argumentAtOffset(arguments, offset);
    if (activeArgument?.name != null) {
      final namedIndex = signature.parameters.indexWhere(
        (parameter) => parameter.name == activeArgument!.name,
      );
      if (namedIndex >= 0) {
        activeParameterIndex = namedIndex;
      }
    }
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

  List<CompletionItem> namedArgumentCompletionsAt(String source, int offset) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    if (signaturesByName.isEmpty) {
      return const <CompletionItem>[];
    }

    final call = _callArgumentListAt(tokens, offset);
    if (call == null) {
      return const <CompletionItem>[];
    }
    final openingToken = tokens[call.openingIndex];
    final closingToken = tokens[call.closingIndex];
    if (offset < openingToken.range.end || offset > closingToken.range.start) {
      return const <CompletionItem>[];
    }

    final signature = _signatureForCall(signaturesByName, call.callable);
    if (signature == null || signature.parameters.isEmpty) {
      return const <CompletionItem>[];
    }

    final context = _namedArgumentCompletionContext(
      source: source,
      tokens: tokens,
      call: call,
      offset: offset,
    );
    if (context == null) {
      return const <CompletionItem>[];
    }

    final currentArguments = _parseCallArguments(
      source: source,
      tokens: tokens,
      openingIndex: call.openingIndex,
      closingIndex: call.closingIndex,
    );
    final providedNames = _providedCallParameterNames(
      signature,
      currentArguments
          .where((argument) => !argument.range.intersects(context.segmentRange))
          .toList(growable: false),
    );

    return [
      for (final parameter in signature.parameters)
        if (!providedNames.contains(parameter.name))
          CompletionItem(
            label: '${parameter.name}:',
            kind: CompletionItemKind.snippet,
            insertText: '${parameter.name}: ',
            detail:
                'Named argument for `${signature.name}`'
                '${parameter.type.isEmpty ? '' : ' · ${parameter.type}'}',
            documentation: parameter.documentation,
            replacementRange: context.replacementRange,
          ),
    ];
  }

  AddArgumentNamesPlan? addArgumentNamesAt(String source, int offset) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    if (signaturesByName.isEmpty) {
      return null;
    }

    final call = _callArgumentListAt(tokens, offset);
    if (call == null) {
      return null;
    }
    if (offset < call.callable.range.start ||
        offset > tokens[call.closingIndex].range.end) {
      return null;
    }

    final signature = _signatureForCall(signaturesByName, call.callable);
    if (signature == null || signature.parameters.isEmpty) {
      return null;
    }

    final arguments = _parseCallArguments(
      source: source,
      tokens: tokens,
      openingIndex: call.openingIndex,
      closingIndex: call.closingIndex,
    );
    if (arguments.isEmpty ||
        arguments.every((argument) => argument.name != null)) {
      return null;
    }

    final parameterNames = signature.parameters
        .map((parameter) => parameter.name)
        .toSet();
    final providedNames = <String>{};
    final edits = <FormattingEdit>[];
    var positionalIndex = 0;

    for (final argument in arguments) {
      final name = argument.name;
      if (name != null) {
        if (!parameterNames.contains(name)) {
          return null;
        }
        providedNames.add(name);
        continue;
      }

      while (positionalIndex < signature.parameters.length &&
          providedNames.contains(signature.parameters[positionalIndex].name)) {
        positionalIndex += 1;
      }
      if (positionalIndex >= signature.parameters.length) {
        return null;
      }

      final parameter = signature.parameters[positionalIndex];
      providedNames.add(parameter.name);
      positionalIndex += 1;
      edits.add(
        FormattingEdit(
          range: argument.range,
          newText: '${parameter.name}: ${argument.text}',
        ),
      );
    }

    if (edits.isEmpty) {
      return null;
    }
    return AddArgumentNamesPlan(
      callableName: signature.name,
      invocationRange: SourceRange(
        start: call.callable.range.start,
        end: tokens[call.closingIndex].range.end,
      ),
      edits: edits,
    );
  }

  AddArgumentNamePlan? addArgumentNameAt(String source, int offset) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    if (signaturesByName.isEmpty) {
      return null;
    }

    final call = _callArgumentListAt(tokens, offset);
    if (call == null) {
      return null;
    }
    if (offset < call.callable.range.start ||
        offset > tokens[call.closingIndex].range.end) {
      return null;
    }

    final signature = _signatureForCall(signaturesByName, call.callable);
    if (signature == null || signature.parameters.isEmpty) {
      return null;
    }

    final arguments = _parseCallArguments(
      source: source,
      tokens: tokens,
      openingIndex: call.openingIndex,
      closingIndex: call.closingIndex,
    );
    final activeArgument = _argumentAtOffset(arguments, offset);
    if (activeArgument == null || activeArgument.name != null) {
      return null;
    }

    final parameter = _parameterForPositionalArgument(
      signature: signature,
      arguments: arguments,
      targetArgument: activeArgument,
    );
    if (parameter == null) {
      return null;
    }

    return AddArgumentNamePlan(
      callableName: signature.name,
      parameterName: parameter.name,
      argumentRange: activeArgument.range,
      invocationRange: SourceRange(
        start: call.callable.range.start,
        end: tokens[call.closingIndex].range.end,
      ),
      edit: FormattingEdit(
        range: activeArgument.range,
        newText: '${parameter.name}: ${activeArgument.text}',
      ),
    );
  }

  RemoveArgumentNamesPlan? removeArgumentNamesAt(String source, int offset) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    if (signaturesByName.isEmpty) {
      return null;
    }

    final call = _callArgumentListAt(tokens, offset);
    if (call == null) {
      return null;
    }
    if (offset < call.callable.range.start ||
        offset > tokens[call.closingIndex].range.end) {
      return null;
    }

    final signature = _signatureForCall(signaturesByName, call.callable);
    if (signature == null || signature.parameters.isEmpty) {
      return null;
    }

    final arguments = _parseCallArguments(
      source: source,
      tokens: tokens,
      openingIndex: call.openingIndex,
      closingIndex: call.closingIndex,
    );
    final namedArguments = arguments
        .where((argument) => argument.name != null)
        .toList(growable: false);
    if (namedArguments.length < 2) {
      return null;
    }

    final parameterNames = signature.parameters
        .map((parameter) => parameter.name)
        .toSet();
    final originalNames = <_ArgumentSegment, String>{};
    final valueRanges = <_ArgumentSegment, SourceRange>{};
    final seenNames = <String>{};
    for (final argument in namedArguments) {
      final name = argument.name!;
      if (!parameterNames.contains(name) || !seenNames.add(name)) {
        return null;
      }
      final valueRange = _argumentValueRange(
        source: source,
        tokens: tokens,
        argument: argument,
      );
      if (valueRange == null || valueRange.isCollapsed) {
        return null;
      }
      originalNames[argument] = name;
      valueRanges[argument] = valueRange;
    }

    final simulatedArguments = <_ArgumentSegment>[];
    final simulatedByOriginal = <_ArgumentSegment, _ArgumentSegment>{};
    for (final argument in arguments) {
      final valueRange = valueRanges[argument];
      if (valueRange == null) {
        simulatedArguments.add(argument);
        continue;
      }
      final simulated = _ArgumentSegment(
        range: argument.range,
        text: source.substring(valueRange.start, valueRange.end),
      );
      simulatedArguments.add(simulated);
      simulatedByOriginal[argument] = simulated;
    }

    final edits = <FormattingEdit>[];
    for (final argument in namedArguments) {
      final simulatedArgument = simulatedByOriginal[argument];
      if (simulatedArgument == null) {
        return null;
      }
      final simulatedParameter = _parameterForPositionalArgument(
        signature: signature,
        arguments: simulatedArguments,
        targetArgument: simulatedArgument,
      );
      if (simulatedParameter == null ||
          simulatedParameter.name != originalNames[argument]) {
        return null;
      }
      final valueRange = valueRanges[argument]!;
      edits.add(
        FormattingEdit(
          range: argument.range,
          newText: source.substring(valueRange.start, valueRange.end),
        ),
      );
    }

    return RemoveArgumentNamesPlan(
      callableName: signature.name,
      invocationRange: SourceRange(
        start: call.callable.range.start,
        end: tokens[call.closingIndex].range.end,
      ),
      edits: edits,
    );
  }

  RemoveArgumentNamePlan? removeArgumentNameAt(String source, int offset) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    if (signaturesByName.isEmpty) {
      return null;
    }

    final call = _callArgumentListAt(tokens, offset);
    if (call == null) {
      return null;
    }
    if (offset < call.callable.range.start ||
        offset > tokens[call.closingIndex].range.end) {
      return null;
    }

    final signature = _signatureForCall(signaturesByName, call.callable);
    if (signature == null || signature.parameters.isEmpty) {
      return null;
    }

    final arguments = _parseCallArguments(
      source: source,
      tokens: tokens,
      openingIndex: call.openingIndex,
      closingIndex: call.closingIndex,
    );
    final activeArgument = _argumentAtOffset(arguments, offset);
    final activeName = activeArgument?.name;
    if (activeArgument == null || activeName == null) {
      return null;
    }

    final valueRange = _argumentValueRange(
      source: source,
      tokens: tokens,
      argument: activeArgument,
    );
    if (valueRange == null || valueRange.isCollapsed) {
      return null;
    }

    _ArgumentSegment? simulatedActiveArgument;
    final simulatedArguments = [
      for (final argument in arguments)
        if (identical(argument, activeArgument))
          simulatedActiveArgument = _ArgumentSegment(
            range: argument.range,
            text: source.substring(valueRange.start, valueRange.end),
          )
        else
          argument,
    ];

    final simulatedParameter = _parameterForPositionalArgument(
      signature: signature,
      arguments: simulatedArguments,
      targetArgument: simulatedActiveArgument!,
    );
    if (simulatedParameter == null || simulatedParameter.name != activeName) {
      return null;
    }

    return RemoveArgumentNamePlan(
      callableName: signature.name,
      parameterName: activeName,
      argumentRange: activeArgument.range,
      invocationRange: SourceRange(
        start: call.callable.range.start,
        end: tokens[call.closingIndex].range.end,
      ),
      edit: FormattingEdit(
        range: activeArgument.range,
        newText: source.substring(valueRange.start, valueRange.end),
      ),
    );
  }

  SpecifyTypeExplicitlyPlan? specifyTypeExplicitlyAt(
    String source,
    int offset,
  ) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final token = _tokenAroundOffset(tokens, offset);
    if (token == null || token.kind != TokenKind.identifier) {
      return null;
    }

    for (final hint in typeNameHints(source)) {
      if (!_sameRange(hint.range, token.range)) {
        continue;
      }
      final typeName = hint.label.replaceFirst(':', '').trim();
      if (typeName.isEmpty) {
        return null;
      }
      return SpecifyTypeExplicitlyPlan(
        variableName: token.lexeme,
        typeName: typeName,
        nameRange: token.range,
        edit: FormattingEdit(
          range: SourceRange(start: token.range.end, end: token.range.end),
          newText: ': $typeName',
        ),
      );
    }
    return null;
  }

  RemoveExplicitTypePlan? removeExplicitTypeAt(String source, int offset) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final token = _tokenAroundOffset(tokens, offset);
    if (token == null) {
      return null;
    }
    final tokenIndex = tokens.indexOf(token);
    if (tokenIndex < 0) {
      return null;
    }

    final binding = _typedLocalBindingContaining(tokens, tokenIndex);
    if (binding == null) {
      return null;
    }

    final inferredType = _inferTypedLocalInitializerTypes(
      tokens,
    )[tokens[binding.nameIndex].lexeme];
    if (inferredType == null || inferredType != binding.typeName) {
      return null;
    }

    return _removeExplicitTypePlanForBinding(tokens, binding);
  }

  List<RemoveExplicitTypePlan> redundantExplicitTypePlans(String source) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final inferredTypes = _inferTypedLocalInitializerTypes(tokens);
    final plans = <RemoveExplicitTypePlan>[];
    final seenTypeRanges = <String>{};

    for (var index = 0; index < tokens.length; index += 1) {
      final binding = _typedLocalBindingAtName(tokens, index);
      if (binding == null) {
        continue;
      }
      final inferredType = inferredTypes[tokens[binding.nameIndex].lexeme];
      if (inferredType == null || inferredType != binding.typeName) {
        continue;
      }
      final plan = _removeExplicitTypePlanForBinding(tokens, binding);
      final key = '${plan.typeRange.start}:${plan.typeRange.end}';
      if (seenTypeRanges.add(key)) {
        plans.add(plan);
      }
    }
    return plans;
  }

  RemoveExplicitTypePlan _removeExplicitTypePlanForBinding(
    List<TokenSpan> tokens,
    _TypedLocalBinding binding,
  ) {
    return RemoveExplicitTypePlan(
      variableName: tokens[binding.nameIndex].lexeme,
      typeName: binding.typeName,
      typeRange: SourceRange(
        start: tokens[binding.colonIndex].range.start,
        end: tokens[binding.typeIndex].range.end,
      ),
      edit: FormattingEdit(
        range: SourceRange(
          start: tokens[binding.nameIndex].range.end,
          end: tokens[binding.typeIndex].range.end,
        ),
        newText: '',
      ),
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

      final typedBinding = _typedLocalBindingAtName(tokens, index);
      if (typedBinding != null) {
        inferredTypesByName[token.lexeme] = typedBinding.typeName;
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

  _TypedLocalBinding? _typedLocalBindingContaining(
    List<TokenSpan> tokens,
    int tokenIndex,
  ) {
    for (var index = 0; index < tokens.length; index += 1) {
      final binding = _typedLocalBindingAtName(tokens, index);
      if (binding == null) {
        continue;
      }
      if (tokenIndex >= binding.nameIndex &&
          tokenIndex < binding.assignmentIndex) {
        return binding;
      }
    }
    return null;
  }

  _TypedLocalBinding? _typedLocalBindingAtName(
    List<TokenSpan> tokens,
    int nameIndex,
  ) {
    final nameToken = tokens[nameIndex];
    if (nameToken.kind != TokenKind.identifier ||
        _syntaxHighlighter.isTypeName(nameToken.lexeme)) {
      return null;
    }
    final colonIndex = _nextSignificantIndex(tokens, nameIndex + 1);
    if (colonIndex == null || tokens[colonIndex].lexeme != ':') {
      return null;
    }
    final typeIndex = _nextSignificantIndex(tokens, colonIndex + 1);
    if (typeIndex == null ||
        !_syntaxHighlighter.isTypeName(tokens[typeIndex].lexeme)) {
      return null;
    }
    final assignmentIndex = _nextSignificantIndex(tokens, typeIndex + 1);
    if (assignmentIndex == null ||
        (tokens[assignmentIndex].lexeme != '=' &&
            tokens[assignmentIndex].lexeme != ':=')) {
      return null;
    }
    if (_hasLineBreakBetween(tokens, nameIndex + 1, assignmentIndex)) {
      return null;
    }

    final previous = _previousSignificant(tokens, nameIndex - 1);
    final disallowedPrevious = <String>{'fn', '#', '(', ',', ':', '@'};
    if (previous != null && disallowedPrevious.contains(previous.lexeme)) {
      return null;
    }

    return _TypedLocalBinding(
      nameIndex: nameIndex,
      colonIndex: colonIndex,
      typeIndex: typeIndex,
      assignmentIndex: assignmentIndex,
      typeName: tokens[typeIndex].lexeme,
    );
  }

  String? _inferExpressionType({
    required List<TokenSpan> tokens,
    required int expressionStartIndex,
    required Map<String, List<_FunctionSignature>> signaturesByName,
    required Map<String, String> inferredTypesByName,
    List<StyioBinaryOperatorTypeIssue>? binaryOperatorIssues,
    List<StyioUnaryOperatorTypeIssue>? unaryOperatorIssues,
  }) {
    final expression = _inferExpressionTypeSpan(
      tokens: tokens,
      expressionStartIndex: expressionStartIndex,
      signaturesByName: signaturesByName,
      inferredTypesByName: inferredTypesByName,
      binaryOperatorIssues: binaryOperatorIssues,
      unaryOperatorIssues: unaryOperatorIssues,
    );
    return expression?.typeName;
  }

  _ExpressionTypeSpan? _inferExpressionTypeSpan({
    required List<TokenSpan> tokens,
    required int expressionStartIndex,
    required Map<String, List<_FunctionSignature>> signaturesByName,
    required Map<String, String> inferredTypesByName,
    List<StyioBinaryOperatorTypeIssue>? binaryOperatorIssues,
    List<StyioUnaryOperatorTypeIssue>? unaryOperatorIssues,
    int minPrecedence = 0,
  }) {
    final primary = _inferPrimaryExpressionType(
      tokens: tokens,
      expressionStartIndex: expressionStartIndex,
      signaturesByName: signaturesByName,
      inferredTypesByName: inferredTypesByName,
      binaryOperatorIssues: binaryOperatorIssues,
      unaryOperatorIssues: unaryOperatorIssues,
    );
    if (primary == null) {
      return null;
    }
    var left = primary;

    while (true) {
      final operatorIndex = _nextSignificantIndex(tokens, left.endIndex + 1);
      if (operatorIndex == null ||
          _hasLineBreakBetween(tokens, left.endIndex + 1, operatorIndex) ||
          !_isBinaryExpressionOperator(tokens[operatorIndex].lexeme)) {
        return left;
      }
      final operatorLexeme = tokens[operatorIndex].lexeme;
      final precedence = _binaryExpressionPrecedence(operatorLexeme);
      if (precedence == null || precedence < minPrecedence) {
        return left;
      }
      final rightIndex = _nextSignificantIndex(tokens, operatorIndex + 1);
      if (rightIndex == null ||
          _hasLineBreakBetween(tokens, operatorIndex + 1, rightIndex)) {
        return left;
      }
      final right = _inferExpressionTypeSpan(
        tokens: tokens,
        expressionStartIndex: rightIndex,
        signaturesByName: signaturesByName,
        inferredTypesByName: inferredTypesByName,
        binaryOperatorIssues: binaryOperatorIssues,
        unaryOperatorIssues: unaryOperatorIssues,
        minPrecedence:
            _isRightAssociativeBinaryExpressionOperator(operatorLexeme)
            ? precedence
            : precedence + 1,
      );
      if (right == null) {
        return null;
      }
      final combinedType = _inferBinaryExpressionType(
        operatorLexeme: operatorLexeme,
        leftType: left.typeName,
        rightType: right.typeName,
      );
      if (combinedType == null || combinedType.isEmpty) {
        binaryOperatorIssues?.add(
          StyioBinaryOperatorTypeIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'binary-operator-type-mismatch',
              message:
                  'Operator `$operatorLexeme` cannot be applied to '
                  '`${left.typeName}` and `${right.typeName}`.',
              range: tokens[operatorIndex].range,
            ),
            operatorLexeme: operatorLexeme,
            leftTypeName: left.typeName,
            rightTypeName: right.typeName,
            operatorRange: tokens[operatorIndex].range,
            leftOperandRange: SourceRange(
              start: tokens[left.startIndex].range.start,
              end: tokens[left.endIndex].range.end,
            ),
            rightOperandRange: SourceRange(
              start: tokens[right.startIndex].range.start,
              end: tokens[right.endIndex].range.end,
            ),
          ),
        );
        return null;
      }
      left = _ExpressionTypeSpan(
        startIndex: left.startIndex,
        typeName: combinedType,
        endIndex: right.endIndex,
      );
    }
  }

  _ExpressionTypeSpan? _inferPrimaryExpressionType({
    required List<TokenSpan> tokens,
    required int expressionStartIndex,
    required Map<String, List<_FunctionSignature>> signaturesByName,
    required Map<String, String> inferredTypesByName,
    List<StyioBinaryOperatorTypeIssue>? binaryOperatorIssues,
    List<StyioUnaryOperatorTypeIssue>? unaryOperatorIssues,
  }) {
    final token = tokens[expressionStartIndex];
    if (token.lexeme == '(') {
      final innerIndex = _nextSignificantIndex(
        tokens,
        expressionStartIndex + 1,
      );
      final closingIndex = _matchingParenthesisIndex(
        tokens,
        expressionStartIndex,
      );
      if (innerIndex == null ||
          closingIndex == null ||
          innerIndex >= closingIndex) {
        return null;
      }
      final innerType = _inferExpressionType(
        tokens: tokens,
        expressionStartIndex: innerIndex,
        signaturesByName: signaturesByName,
        inferredTypesByName: inferredTypesByName,
        binaryOperatorIssues: binaryOperatorIssues,
        unaryOperatorIssues: unaryOperatorIssues,
      );
      if (innerType == null || innerType.isEmpty) {
        return null;
      }
      return _ExpressionTypeSpan(
        startIndex: expressionStartIndex,
        typeName: innerType,
        endIndex: closingIndex,
      );
    }
    if (_isUnaryPrefixExpressionOperator(token.lexeme)) {
      final operandIndex = _nextSignificantIndex(
        tokens,
        expressionStartIndex + 1,
      );
      if (operandIndex == null ||
          _hasLineBreakBetween(
            tokens,
            expressionStartIndex + 1,
            operandIndex,
          )) {
        return null;
      }
      final operand = _inferPrimaryExpressionType(
        tokens: tokens,
        expressionStartIndex: operandIndex,
        signaturesByName: signaturesByName,
        inferredTypesByName: inferredTypesByName,
        binaryOperatorIssues: binaryOperatorIssues,
        unaryOperatorIssues: unaryOperatorIssues,
      );
      if (operand == null) {
        return null;
      }
      final typeName = _inferUnaryExpressionType(
        operatorLexeme: token.lexeme,
        operandType: operand.typeName,
      );
      if (typeName == null || typeName.isEmpty) {
        unaryOperatorIssues?.add(
          StyioUnaryOperatorTypeIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'unary-operator-type-mismatch',
              message:
                  'Operator `${token.lexeme}` cannot be applied to '
                  '`${operand.typeName}`.',
              range: token.range,
            ),
            operatorLexeme: token.lexeme,
            operandTypeName: operand.typeName,
            operatorRange: token.range,
            operandRange: SourceRange(
              start: tokens[operand.startIndex].range.start,
              end: tokens[operand.endIndex].range.end,
            ),
          ),
        );
        return null;
      }
      return _ExpressionTypeSpan(
        startIndex: expressionStartIndex,
        typeName: typeName,
        endIndex: operand.endIndex,
      );
    }
    if (token.kind == TokenKind.number) {
      return _ExpressionTypeSpan(
        startIndex: expressionStartIndex,
        typeName: token.lexeme.contains('.') ? 'f64' : 'i64',
        endIndex: expressionStartIndex,
      );
    }
    if (token.kind == TokenKind.string) {
      return _ExpressionTypeSpan(
        startIndex: expressionStartIndex,
        typeName: 'string',
        endIndex: expressionStartIndex,
      );
    }
    if (token.kind == TokenKind.keyword) {
      if (token.lexeme == 'true' || token.lexeme == 'false') {
        return _ExpressionTypeSpan(
          startIndex: expressionStartIndex,
          typeName: 'bool',
          endIndex: expressionStartIndex,
        );
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
      return _ExpressionTypeSpan(
        startIndex: expressionStartIndex,
        typeName: signature.returnType,
        endIndex: call.closingIndex,
      );
    }

    final inferredType = inferredTypesByName[token.lexeme];
    if (inferredType == null || inferredType.isEmpty) {
      return null;
    }
    return _ExpressionTypeSpan(
      startIndex: expressionStartIndex,
      typeName: inferredType,
      endIndex: expressionStartIndex,
    );
  }

  bool _isUnaryPrefixExpressionOperator(String lexeme) {
    return lexeme == '!' || lexeme == '-' || lexeme == '+';
  }

  String? _inferUnaryExpressionType({
    required String operatorLexeme,
    required String operandType,
  }) {
    if (operatorLexeme == '!') {
      return operandType == 'bool' ? 'bool' : null;
    }
    if (operatorLexeme == '-' || operatorLexeme == '+') {
      return _isNumericType(operandType) ? operandType : null;
    }
    return null;
  }

  bool _isBinaryExpressionOperator(String lexeme) {
    return const {
      '+',
      '-',
      '*',
      '/',
      '%',
      '**',
      '<',
      '<=',
      '>',
      '>=',
      '==',
      '!=',
      '&&',
      '||',
    }.contains(lexeme);
  }

  int? _binaryExpressionPrecedence(String lexeme) {
    if (lexeme == '||') {
      return 1;
    }
    if (lexeme == '&&') {
      return 2;
    }
    if (lexeme == '==' || lexeme == '!=') {
      return 3;
    }
    if (const {'<', '<=', '>', '>='}.contains(lexeme)) {
      return 4;
    }
    if (lexeme == '+' || lexeme == '-') {
      return 5;
    }
    if (lexeme == '*' || lexeme == '/' || lexeme == '%') {
      return 6;
    }
    if (lexeme == '**') {
      return 7;
    }
    return null;
  }

  bool _isRightAssociativeBinaryExpressionOperator(String lexeme) {
    return lexeme == '**';
  }

  String? _inferBinaryExpressionType({
    required String operatorLexeme,
    required String leftType,
    required String rightType,
  }) {
    final isNumeric = _isNumericType(leftType) && _isNumericType(rightType);
    if (const {'+', '-', '*', '/', '%', '**'}.contains(operatorLexeme)) {
      if (!isNumeric) {
        return null;
      }
      return leftType == 'f64' || rightType == 'f64' ? 'f64' : 'i64';
    }
    if (const {'<', '<=', '>', '>='}.contains(operatorLexeme)) {
      return isNumeric ? 'bool' : null;
    }
    if (operatorLexeme == '==' || operatorLexeme == '!=') {
      return leftType == rightType || isNumeric ? 'bool' : null;
    }
    if (operatorLexeme == '&&' || operatorLexeme == '||') {
      return leftType == 'bool' && rightType == 'bool' ? 'bool' : null;
    }
    return null;
  }

  bool _isNumericType(String typeName) {
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

  Map<String, String> _inferTypedLocalInitializerTypes(List<TokenSpan> tokens) {
    final signaturesByName = _collectFunctionSignatures(tokens);
    final inferredTypesByName = <String, String>{};
    final inferredTypedLocalTypes = <String, String>{};

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind != TokenKind.identifier ||
          _syntaxHighlighter.isTypeName(token.lexeme)) {
        continue;
      }

      final typedBinding = _typedLocalBindingAtName(tokens, index);
      if (typedBinding != null) {
        final expressionStartIndex = _nextSignificantIndex(
          tokens,
          typedBinding.assignmentIndex + 1,
        );
        if (expressionStartIndex != null) {
          final inferredType = _inferExpressionType(
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
            signaturesByName: signaturesByName,
            inferredTypesByName: inferredTypesByName,
          );
          if (inferredType != null && inferredType.isNotEmpty) {
            inferredTypedLocalTypes[token.lexeme] = inferredType;
          }
        }
        inferredTypesByName[token.lexeme] = typedBinding.typeName;
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
      final inferredType = _inferExpressionType(
        tokens: tokens,
        expressionStartIndex: expressionStartIndex,
        signaturesByName: signaturesByName,
        inferredTypesByName: inferredTypesByName,
      );
      if (inferredType != null && inferredType.isNotEmpty) {
        inferredTypesByName[token.lexeme] = inferredType;
      }
    }

    return inferredTypedLocalTypes;
  }

  List<StyioTypeMismatchIssue> typedLocalInitializerIssues(String source) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    final signatures = signaturesByName.values.expand((items) => items);
    final inferredTypesByName = <String, String>{};
    final issues = <StyioTypeMismatchIssue>[];

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind != TokenKind.identifier ||
          _syntaxHighlighter.isTypeName(token.lexeme)) {
        continue;
      }

      final typedBinding = _typedLocalBindingAtName(tokens, index);
      if (typedBinding != null) {
        final expressionStartIndex = _nextSignificantIndex(
          tokens,
          typedBinding.assignmentIndex + 1,
        );
        final initializerRange = expressionStartIndex == null
            ? null
            : _initializerRangeForBinding(
                source: source,
                tokens: tokens,
                expressionStartIndex: expressionStartIndex,
              );
        if (expressionStartIndex != null && initializerRange != null) {
          final actualType = _inferExpressionType(
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
            signaturesByName: signaturesByName,
            inferredTypesByName: inferredTypesByName,
          );
          if (actualType != null &&
              actualType.isNotEmpty &&
              actualType != typedBinding.typeName) {
            issues.add(
              StyioTypeMismatchIssue(
                diagnostic: Diagnostic(
                  severity: DiagnosticSeverity.warning,
                  code: 'initializer-type-mismatch',
                  message:
                      'Initializer for `${token.lexeme}` expects '
                      '`${typedBinding.typeName}`, got `$actualType`.',
                  range: initializerRange,
                ),
                variableName: token.lexeme,
                expectedTypeName: typedBinding.typeName,
                actualTypeName: actualType,
                initializerRange: initializerRange,
                typeRange: tokens[typedBinding.typeIndex].range,
                replacementInitializerText: _argumentTypeReplacementText(
                  tokens: tokens,
                  expressionStartIndex: expressionStartIndex,
                  argumentRange: initializerRange,
                  expectedType: typedBinding.typeName,
                  actualType: actualType,
                ),
              ),
            );
          }
        }
        inferredTypesByName[token.lexeme] = typedBinding.typeName;
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
      final inferredType = _inferExpressionType(
        tokens: tokens,
        expressionStartIndex: expressionStartIndex,
        signaturesByName: signaturesByName,
        inferredTypesByName: inferredTypesByName,
      );
      if (inferredType != null && inferredType.isNotEmpty) {
        inferredTypesByName[token.lexeme] = inferredType;
      }
    }

    for (final signature in signatures) {
      final bodySpan = _functionBodySpan(tokens, signature);
      if (bodySpan == null) {
        continue;
      }
      final localTypesByName = <String, String>{
        for (final parameter in signature.parameters)
          if (parameter.type.isNotEmpty) parameter.name: parameter.type,
      };
      for (
        var index = bodySpan.openingIndex + 1;
        index < bodySpan.closingIndex;
        index += 1
      ) {
        final token = tokens[index];
        if (token.kind != TokenKind.identifier ||
            _syntaxHighlighter.isTypeName(token.lexeme)) {
          continue;
        }

        final typedBinding = _typedLocalBindingAtName(tokens, index);
        if (typedBinding != null &&
            typedBinding.assignmentIndex < bodySpan.closingIndex) {
          final expressionStartIndex = _nextSignificantIndex(
            tokens,
            typedBinding.assignmentIndex + 1,
          );
          final initializerRange = expressionStartIndex == null
              ? null
              : _initializerRangeForBinding(
                  source: source,
                  tokens: tokens,
                  expressionStartIndex: expressionStartIndex,
                );
          if (expressionStartIndex != null &&
              expressionStartIndex < bodySpan.closingIndex &&
              initializerRange != null) {
            final actualType = _inferExpressionType(
              tokens: tokens,
              expressionStartIndex: expressionStartIndex,
              signaturesByName: signaturesByName,
              inferredTypesByName: localTypesByName,
            );
            if (actualType != null &&
                actualType.isNotEmpty &&
                actualType != typedBinding.typeName) {
              issues.add(
                StyioTypeMismatchIssue(
                  diagnostic: Diagnostic(
                    severity: DiagnosticSeverity.warning,
                    code: 'initializer-type-mismatch',
                    message:
                        'Initializer for `${token.lexeme}` expects '
                        '`${typedBinding.typeName}`, got `$actualType`.',
                    range: initializerRange,
                  ),
                  variableName: token.lexeme,
                  expectedTypeName: typedBinding.typeName,
                  actualTypeName: actualType,
                  initializerRange: initializerRange,
                  typeRange: tokens[typedBinding.typeIndex].range,
                  replacementInitializerText: _argumentTypeReplacementText(
                    tokens: tokens,
                    expressionStartIndex: expressionStartIndex,
                    argumentRange: initializerRange,
                    expectedType: typedBinding.typeName,
                    actualType: actualType,
                  ),
                ),
              );
            }
          }
          localTypesByName[token.lexeme] = typedBinding.typeName;
          continue;
        }

        final assignmentIndex = _bindingAssignmentIndex(tokens, index);
        if (assignmentIndex == null ||
            assignmentIndex >= bodySpan.closingIndex) {
          continue;
        }
        final expressionStartIndex = _nextSignificantIndex(
          tokens,
          assignmentIndex + 1,
        );
        if (expressionStartIndex == null ||
            expressionStartIndex >= bodySpan.closingIndex) {
          continue;
        }
        final inferredType = _inferExpressionType(
          tokens: tokens,
          expressionStartIndex: expressionStartIndex,
          signaturesByName: signaturesByName,
          inferredTypesByName: localTypesByName,
        );
        if (inferredType != null && inferredType.isNotEmpty) {
          localTypesByName[token.lexeme] = inferredType;
        }
      }
    }

    final dedupedIssues = <String, StyioTypeMismatchIssue>{};
    for (final issue in issues) {
      final key =
          '${issue.initializerRange.start}:${issue.initializerRange.end}:'
          '${issue.expectedTypeName}:${issue.actualTypeName}';
      dedupedIssues.putIfAbsent(key, () => issue);
    }
    return dedupedIssues.values.toList(growable: false)..sort(
      (left, right) =>
          left.initializerRange.start.compareTo(right.initializerRange.start),
    );
  }

  List<StyioAssignmentTypeMismatchIssue> assignmentTypeMismatchIssues(
    String source,
  ) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    final signatures = signaturesByName.values.expand((items) => items);
    final inferredTypesByName = <String, String>{};
    final explicitTypesByName = <String, _ExplicitTypedLocal>{};
    final issues = <StyioAssignmentTypeMismatchIssue>[];

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind != TokenKind.identifier ||
          _syntaxHighlighter.isTypeName(token.lexeme)) {
        continue;
      }

      final typedBinding = _typedLocalBindingAtName(tokens, index);
      if (typedBinding != null) {
        final expressionStartIndex = _nextSignificantIndex(
          tokens,
          typedBinding.assignmentIndex + 1,
        );
        SourceRange? initializerRange;
        String initializerActualType = '';
        if (expressionStartIndex != null) {
          initializerRange = _initializerRangeForBinding(
            source: source,
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
          );
          final inferredType = _inferExpressionType(
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
            signaturesByName: signaturesByName,
            inferredTypesByName: inferredTypesByName,
          );
          if (inferredType != null && inferredType.isNotEmpty) {
            initializerActualType = inferredType;
          }
        }
        explicitTypesByName[token.lexeme] = _ExplicitTypedLocal(
          typeName: typedBinding.typeName,
          typeRange: tokens[typedBinding.typeIndex].range,
          initializerRange: initializerRange,
          initializerExpressionStartIndex: expressionStartIndex,
          initializerActualTypeName: initializerActualType,
        );
        inferredTypesByName[token.lexeme] = typedBinding.typeName;
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

      final actualType = _inferExpressionType(
        tokens: tokens,
        expressionStartIndex: expressionStartIndex,
        signaturesByName: signaturesByName,
        inferredTypesByName: inferredTypesByName,
      );
      if (actualType == null || actualType.isEmpty) {
        continue;
      }

      final explicitType = explicitTypesByName[token.lexeme];
      if (explicitType == null) {
        inferredTypesByName[token.lexeme] = actualType;
        continue;
      }
      inferredTypesByName[token.lexeme] = explicitType.typeName;

      if (actualType == explicitType.typeName) {
        continue;
      }

      final assignmentRange = _initializerRangeForBinding(
        source: source,
        tokens: tokens,
        expressionStartIndex: expressionStartIndex,
      );
      if (assignmentRange == null || assignmentRange.isCollapsed) {
        continue;
      }

      var replacementInitializerTextForActualType = '';
      final initializerRange = explicitType.initializerRange;
      final initializerExpressionStartIndex =
          explicitType.initializerExpressionStartIndex;
      if (initializerRange != null &&
          initializerExpressionStartIndex != null &&
          explicitType.initializerActualTypeName.isNotEmpty &&
          explicitType.initializerActualTypeName != actualType) {
        replacementInitializerTextForActualType = _argumentTypeReplacementText(
          tokens: tokens,
          expressionStartIndex: initializerExpressionStartIndex,
          argumentRange: initializerRange,
          expectedType: actualType,
          actualType: explicitType.initializerActualTypeName,
        );
      }

      issues.add(
        StyioAssignmentTypeMismatchIssue(
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'assignment-type-mismatch',
            message:
                'Assignment to `${token.lexeme}` expects '
                '`${explicitType.typeName}`, got `$actualType`.',
            range: assignmentRange,
          ),
          variableName: token.lexeme,
          expectedTypeName: explicitType.typeName,
          actualTypeName: actualType,
          assignmentRange: assignmentRange,
          typeRange: explicitType.typeRange,
          replacementAssignmentText: _argumentTypeReplacementText(
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
            argumentRange: assignmentRange,
            expectedType: explicitType.typeName,
            actualType: actualType,
          ),
          initializerRange: initializerRange,
          initializerActualTypeName: explicitType.initializerActualTypeName,
          replacementInitializerTextForActualType:
              replacementInitializerTextForActualType,
        ),
      );
    }

    for (final signature in signatures) {
      final bodySpan = _functionBodySpan(tokens, signature);
      if (bodySpan == null) {
        continue;
      }
      final localTypesByName = <String, String>{
        for (final parameter in signature.parameters)
          if (parameter.type.isNotEmpty) parameter.name: parameter.type,
      };
      final localExplicitTypesByName = <String, _ExplicitTypedLocal>{};
      for (
        var index = bodySpan.openingIndex + 1;
        index < bodySpan.closingIndex;
        index += 1
      ) {
        final token = tokens[index];
        if (token.kind != TokenKind.identifier ||
            _syntaxHighlighter.isTypeName(token.lexeme)) {
          continue;
        }

        final typedBinding = _typedLocalBindingAtName(tokens, index);
        if (typedBinding != null &&
            typedBinding.assignmentIndex < bodySpan.closingIndex) {
          final expressionStartIndex = _nextSignificantIndex(
            tokens,
            typedBinding.assignmentIndex + 1,
          );
          SourceRange? initializerRange;
          String initializerActualType = '';
          if (expressionStartIndex != null &&
              expressionStartIndex < bodySpan.closingIndex) {
            initializerRange = _initializerRangeForBinding(
              source: source,
              tokens: tokens,
              expressionStartIndex: expressionStartIndex,
            );
            final inferredType = _inferExpressionType(
              tokens: tokens,
              expressionStartIndex: expressionStartIndex,
              signaturesByName: signaturesByName,
              inferredTypesByName: localTypesByName,
            );
            if (inferredType != null && inferredType.isNotEmpty) {
              initializerActualType = inferredType;
            }
          }
          localExplicitTypesByName[token.lexeme] = _ExplicitTypedLocal(
            typeName: typedBinding.typeName,
            typeRange: tokens[typedBinding.typeIndex].range,
            initializerRange: initializerRange,
            initializerExpressionStartIndex: expressionStartIndex,
            initializerActualTypeName: initializerActualType,
          );
          localTypesByName[token.lexeme] = typedBinding.typeName;
          continue;
        }

        final assignmentIndex = _bindingAssignmentIndex(tokens, index);
        if (assignmentIndex == null ||
            assignmentIndex >= bodySpan.closingIndex) {
          continue;
        }

        final expressionStartIndex = _nextSignificantIndex(
          tokens,
          assignmentIndex + 1,
        );
        if (expressionStartIndex == null ||
            expressionStartIndex >= bodySpan.closingIndex) {
          continue;
        }

        final actualType = _inferExpressionType(
          tokens: tokens,
          expressionStartIndex: expressionStartIndex,
          signaturesByName: signaturesByName,
          inferredTypesByName: localTypesByName,
        );
        if (actualType == null || actualType.isEmpty) {
          continue;
        }

        final explicitType = localExplicitTypesByName[token.lexeme];
        if (explicitType == null) {
          localTypesByName[token.lexeme] = actualType;
          continue;
        }
        localTypesByName[token.lexeme] = explicitType.typeName;

        if (actualType == explicitType.typeName) {
          continue;
        }

        final assignmentRange = _initializerRangeForBinding(
          source: source,
          tokens: tokens,
          expressionStartIndex: expressionStartIndex,
        );
        if (assignmentRange == null || assignmentRange.isCollapsed) {
          continue;
        }

        var replacementInitializerTextForActualType = '';
        final initializerRange = explicitType.initializerRange;
        final initializerExpressionStartIndex =
            explicitType.initializerExpressionStartIndex;
        if (initializerRange != null &&
            initializerExpressionStartIndex != null &&
            explicitType.initializerActualTypeName.isNotEmpty &&
            explicitType.initializerActualTypeName != actualType) {
          replacementInitializerTextForActualType =
              _argumentTypeReplacementText(
                tokens: tokens,
                expressionStartIndex: initializerExpressionStartIndex,
                argumentRange: initializerRange,
                expectedType: actualType,
                actualType: explicitType.initializerActualTypeName,
              );
        }

        issues.add(
          StyioAssignmentTypeMismatchIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'assignment-type-mismatch',
              message:
                  'Assignment to `${token.lexeme}` expects '
                  '`${explicitType.typeName}`, got `$actualType`.',
              range: assignmentRange,
            ),
            variableName: token.lexeme,
            expectedTypeName: explicitType.typeName,
            actualTypeName: actualType,
            assignmentRange: assignmentRange,
            typeRange: explicitType.typeRange,
            replacementAssignmentText: _argumentTypeReplacementText(
              tokens: tokens,
              expressionStartIndex: expressionStartIndex,
              argumentRange: assignmentRange,
              expectedType: explicitType.typeName,
              actualType: actualType,
            ),
            initializerRange: initializerRange,
            initializerActualTypeName: explicitType.initializerActualTypeName,
            replacementInitializerTextForActualType:
                replacementInitializerTextForActualType,
          ),
        );
      }
    }

    final dedupedIssues = <String, StyioAssignmentTypeMismatchIssue>{};
    for (final issue in issues) {
      final key =
          '${issue.assignmentRange.start}:${issue.assignmentRange.end}:'
          '${issue.expectedTypeName}:${issue.actualTypeName}';
      dedupedIssues.putIfAbsent(key, () => issue);
    }
    return dedupedIssues.values.toList(growable: false)..sort(
      (left, right) =>
          left.assignmentRange.start.compareTo(right.assignmentRange.start),
    );
  }

  List<StyioBinaryOperatorTypeIssue> binaryOperatorTypeIssues(String source) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    final signatures = signaturesByName.values.expand((items) => items);
    final functionBodyClosingByOpening = _functionBodyClosingByOpening(
      tokens: tokens,
      signatures: signatures,
    );
    final issues = <StyioBinaryOperatorTypeIssue>[];
    final inferredTypesByName = <String, String>{};

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      final functionBodyClosingIndex = functionBodyClosingByOpening[index];
      if (functionBodyClosingIndex != null) {
        index = functionBodyClosingIndex;
        continue;
      }
      final taskBodyClosingIndex = _taskBodyClosingIndexAfterAsyncOperator(
        tokens,
        index,
      );
      if (taskBodyClosingIndex != null) {
        index = taskBodyClosingIndex;
        continue;
      }
      if (token.kind == TokenKind.keyword && token.lexeme == 'when') {
        final expressionStartIndex = _nextSignificantIndex(tokens, index + 1);
        if (expressionStartIndex != null &&
            !_hasLineBreakBetween(tokens, index + 1, expressionStartIndex)) {
          _inferExpressionType(
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
            signaturesByName: signaturesByName,
            inferredTypesByName: inferredTypesByName,
            binaryOperatorIssues: issues,
          );
        }
        continue;
      }

      if (token.kind != TokenKind.identifier ||
          _syntaxHighlighter.isTypeName(token.lexeme)) {
        continue;
      }

      final typedBinding = _typedLocalBindingAtName(tokens, index);
      if (typedBinding != null) {
        final expressionStartIndex = _nextSignificantIndex(
          tokens,
          typedBinding.assignmentIndex + 1,
        );
        if (expressionStartIndex != null) {
          _inferExpressionType(
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
            signaturesByName: signaturesByName,
            inferredTypesByName: inferredTypesByName,
            binaryOperatorIssues: issues,
          );
        }
        inferredTypesByName[token.lexeme] = typedBinding.typeName;
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
      final inferredType = _inferExpressionType(
        tokens: tokens,
        expressionStartIndex: expressionStartIndex,
        signaturesByName: signaturesByName,
        inferredTypesByName: inferredTypesByName,
        binaryOperatorIssues: issues,
      );
      if (inferredType != null && inferredType.isNotEmpty) {
        inferredTypesByName[token.lexeme] = inferredType;
      }
    }

    for (final signature in signatures) {
      final bodySpan = _functionBodySpan(tokens, signature);
      if (bodySpan == null) {
        continue;
      }
      final localTypesByName = <String, String>{
        for (final parameter in signature.parameters)
          if (parameter.type.isNotEmpty) parameter.name: parameter.type,
      };
      for (
        var index = bodySpan.openingIndex + 1;
        index < bodySpan.closingIndex;
        index += 1
      ) {
        final token = tokens[index];

        if (token.kind == TokenKind.identifier &&
            !_syntaxHighlighter.isTypeName(token.lexeme)) {
          final typedBinding = _typedLocalBindingAtName(tokens, index);
          if (typedBinding != null &&
              typedBinding.assignmentIndex < bodySpan.closingIndex) {
            final expressionStartIndex = _nextSignificantIndex(
              tokens,
              typedBinding.assignmentIndex + 1,
            );
            if (expressionStartIndex != null &&
                expressionStartIndex < bodySpan.closingIndex) {
              _inferExpressionType(
                tokens: tokens,
                expressionStartIndex: expressionStartIndex,
                signaturesByName: signaturesByName,
                inferredTypesByName: localTypesByName,
                binaryOperatorIssues: issues,
              );
            }
            localTypesByName[token.lexeme] = typedBinding.typeName;
            continue;
          }

          final assignmentIndex = _bindingAssignmentIndex(tokens, index);
          if (assignmentIndex != null &&
              assignmentIndex < bodySpan.closingIndex) {
            final expressionStartIndex = _nextSignificantIndex(
              tokens,
              assignmentIndex + 1,
            );
            if (expressionStartIndex != null &&
                expressionStartIndex < bodySpan.closingIndex) {
              final inferredType = _inferExpressionType(
                tokens: tokens,
                expressionStartIndex: expressionStartIndex,
                signaturesByName: signaturesByName,
                inferredTypesByName: localTypesByName,
                binaryOperatorIssues: issues,
              );
              if (inferredType != null && inferredType.isNotEmpty) {
                localTypesByName[token.lexeme] = inferredType;
              }
            }
          }
        }

        if (!_isReturnExpressionMarker(token)) {
          continue;
        }
        final expressionStartIndex = _nextSignificantIndex(tokens, index + 1);
        if (expressionStartIndex == null ||
            expressionStartIndex >= bodySpan.closingIndex) {
          continue;
        }
        _inferExpressionType(
          tokens: tokens,
          expressionStartIndex: expressionStartIndex,
          signaturesByName: signaturesByName,
          inferredTypesByName: localTypesByName,
          binaryOperatorIssues: issues,
        );
      }
    }

    _collectTaskBodyExpressionTypeIssues(
      tokens: tokens,
      signaturesByName: signaturesByName,
      binaryOperatorIssues: issues,
    );

    final dedupedIssues = <String, StyioBinaryOperatorTypeIssue>{};
    for (final issue in issues) {
      final key =
          '${issue.operatorRange.start}:${issue.operatorRange.end}:'
          '${issue.leftTypeName}:${issue.rightTypeName}';
      dedupedIssues.putIfAbsent(key, () => issue);
    }
    return dedupedIssues.values.toList(growable: false)..sort(
      (left, right) =>
          left.operatorRange.start.compareTo(right.operatorRange.start),
    );
  }

  List<StyioUnaryOperatorTypeIssue> unaryOperatorTypeIssues(String source) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    final signatures = signaturesByName.values.expand((items) => items);
    final functionBodyClosingByOpening = _functionBodyClosingByOpening(
      tokens: tokens,
      signatures: signatures,
    );
    final issues = <StyioUnaryOperatorTypeIssue>[];
    final inferredTypesByName = <String, String>{};

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      final functionBodyClosingIndex = functionBodyClosingByOpening[index];
      if (functionBodyClosingIndex != null) {
        index = functionBodyClosingIndex;
        continue;
      }
      final taskBodyClosingIndex = _taskBodyClosingIndexAfterAsyncOperator(
        tokens,
        index,
      );
      if (taskBodyClosingIndex != null) {
        index = taskBodyClosingIndex;
        continue;
      }
      if (token.kind == TokenKind.keyword && token.lexeme == 'when') {
        final expressionStartIndex = _nextSignificantIndex(tokens, index + 1);
        if (expressionStartIndex != null &&
            !_hasLineBreakBetween(tokens, index + 1, expressionStartIndex)) {
          _inferExpressionType(
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
            signaturesByName: signaturesByName,
            inferredTypesByName: inferredTypesByName,
            unaryOperatorIssues: issues,
          );
        }
        continue;
      }

      if (token.kind != TokenKind.identifier ||
          _syntaxHighlighter.isTypeName(token.lexeme)) {
        continue;
      }

      final typedBinding = _typedLocalBindingAtName(tokens, index);
      if (typedBinding != null) {
        final expressionStartIndex = _nextSignificantIndex(
          tokens,
          typedBinding.assignmentIndex + 1,
        );
        if (expressionStartIndex != null) {
          _inferExpressionType(
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
            signaturesByName: signaturesByName,
            inferredTypesByName: inferredTypesByName,
            unaryOperatorIssues: issues,
          );
        }
        inferredTypesByName[token.lexeme] = typedBinding.typeName;
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
      final inferredType = _inferExpressionType(
        tokens: tokens,
        expressionStartIndex: expressionStartIndex,
        signaturesByName: signaturesByName,
        inferredTypesByName: inferredTypesByName,
        unaryOperatorIssues: issues,
      );
      if (inferredType != null && inferredType.isNotEmpty) {
        inferredTypesByName[token.lexeme] = inferredType;
      }
    }

    for (final signature in signatures) {
      final bodySpan = _functionBodySpan(tokens, signature);
      if (bodySpan == null) {
        continue;
      }
      final localTypesByName = <String, String>{
        for (final parameter in signature.parameters)
          if (parameter.type.isNotEmpty) parameter.name: parameter.type,
      };
      for (
        var index = bodySpan.openingIndex + 1;
        index < bodySpan.closingIndex;
        index += 1
      ) {
        final token = tokens[index];

        if (token.kind == TokenKind.identifier &&
            !_syntaxHighlighter.isTypeName(token.lexeme)) {
          final typedBinding = _typedLocalBindingAtName(tokens, index);
          if (typedBinding != null &&
              typedBinding.assignmentIndex < bodySpan.closingIndex) {
            final expressionStartIndex = _nextSignificantIndex(
              tokens,
              typedBinding.assignmentIndex + 1,
            );
            if (expressionStartIndex != null &&
                expressionStartIndex < bodySpan.closingIndex) {
              _inferExpressionType(
                tokens: tokens,
                expressionStartIndex: expressionStartIndex,
                signaturesByName: signaturesByName,
                inferredTypesByName: localTypesByName,
                unaryOperatorIssues: issues,
              );
            }
            localTypesByName[token.lexeme] = typedBinding.typeName;
            continue;
          }

          final assignmentIndex = _bindingAssignmentIndex(tokens, index);
          if (assignmentIndex != null &&
              assignmentIndex < bodySpan.closingIndex) {
            final expressionStartIndex = _nextSignificantIndex(
              tokens,
              assignmentIndex + 1,
            );
            if (expressionStartIndex != null &&
                expressionStartIndex < bodySpan.closingIndex) {
              final inferredType = _inferExpressionType(
                tokens: tokens,
                expressionStartIndex: expressionStartIndex,
                signaturesByName: signaturesByName,
                inferredTypesByName: localTypesByName,
                unaryOperatorIssues: issues,
              );
              if (inferredType != null && inferredType.isNotEmpty) {
                localTypesByName[token.lexeme] = inferredType;
              }
            }
          }
        }

        if (!_isReturnExpressionMarker(token)) {
          continue;
        }
        final expressionStartIndex = _nextSignificantIndex(tokens, index + 1);
        if (expressionStartIndex == null ||
            expressionStartIndex >= bodySpan.closingIndex) {
          continue;
        }
        _inferExpressionType(
          tokens: tokens,
          expressionStartIndex: expressionStartIndex,
          signaturesByName: signaturesByName,
          inferredTypesByName: localTypesByName,
          unaryOperatorIssues: issues,
        );
      }
    }

    _collectTaskBodyExpressionTypeIssues(
      tokens: tokens,
      signaturesByName: signaturesByName,
      unaryOperatorIssues: issues,
    );

    final dedupedIssues = <String, StyioUnaryOperatorTypeIssue>{};
    for (final issue in issues) {
      final key =
          '${issue.operatorRange.start}:${issue.operatorRange.end}:'
          '${issue.operandTypeName}';
      dedupedIssues.putIfAbsent(key, () => issue);
    }
    return dedupedIssues.values.toList(growable: false)..sort(
      (left, right) =>
          left.operatorRange.start.compareTo(right.operatorRange.start),
    );
  }

  void _collectTaskBodyExpressionTypeIssues({
    required List<TokenSpan> tokens,
    required Map<String, List<_FunctionSignature>> signaturesByName,
    String? source,
    List<StyioBinaryOperatorTypeIssue>? binaryOperatorIssues,
    List<StyioUnaryOperatorTypeIssue>? unaryOperatorIssues,
    List<StyioConditionTypeMismatchIssue>? conditionTypeIssues,
  }) {
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.lexeme != '||>') {
        continue;
      }
      final bodyOpeningIndex = _nextSignificantIndex(tokens, index + 1);
      if (bodyOpeningIndex == null || tokens[bodyOpeningIndex].lexeme != '{') {
        continue;
      }
      final bodyClosingIndex = _matchingBraceIndex(tokens, bodyOpeningIndex);
      if (bodyClosingIndex == null) {
        continue;
      }
      final localTypesByName = <String, String>{};
      for (
        var bodyIndex = bodyOpeningIndex + 1;
        bodyIndex < bodyClosingIndex;
        bodyIndex += 1
      ) {
        final bodyToken = tokens[bodyIndex];
        if (conditionTypeIssues != null &&
            source != null &&
            bodyToken.kind == TokenKind.keyword &&
            bodyToken.lexeme == 'when') {
          final expressionStartIndex = _nextSignificantIndex(
            tokens,
            bodyIndex + 1,
          );
          if (expressionStartIndex == null ||
              expressionStartIndex >= bodyClosingIndex ||
              _hasLineBreakBetween(
                tokens,
                bodyIndex + 1,
                expressionStartIndex,
              )) {
            continue;
          }
          final conditionRange = _conditionExpressionRange(
            source: source,
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
          );
          if (conditionRange == null || conditionRange.isCollapsed) {
            continue;
          }
          final actualType = _inferExpressionType(
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
            signaturesByName: signaturesByName,
            inferredTypesByName: localTypesByName,
          );
          if (actualType == null ||
              actualType.isEmpty ||
              actualType == 'bool') {
            continue;
          }
          conditionTypeIssues.add(
            StyioConditionTypeMismatchIssue(
              diagnostic: Diagnostic(
                severity: DiagnosticSeverity.warning,
                code: 'condition-type-mismatch',
                message: '`when` condition expects `bool`, got `$actualType`.',
                range: conditionRange,
              ),
              expectedTypeName: 'bool',
              actualTypeName: actualType,
              conditionRange: conditionRange,
              replacementConditionText: _conditionTypeReplacementText(
                source: source,
                conditionRange: conditionRange,
                actualType: actualType,
              ),
            ),
          );
          continue;
        }

        if (bodyToken.kind == TokenKind.identifier &&
            !_syntaxHighlighter.isTypeName(bodyToken.lexeme)) {
          final typedBinding = _typedLocalBindingAtName(tokens, bodyIndex);
          if (typedBinding != null &&
              typedBinding.assignmentIndex < bodyClosingIndex) {
            final expressionStartIndex = _nextSignificantIndex(
              tokens,
              typedBinding.assignmentIndex + 1,
            );
            if (expressionStartIndex != null &&
                expressionStartIndex < bodyClosingIndex) {
              _inferExpressionType(
                tokens: tokens,
                expressionStartIndex: expressionStartIndex,
                signaturesByName: signaturesByName,
                inferredTypesByName: localTypesByName,
                binaryOperatorIssues: binaryOperatorIssues,
                unaryOperatorIssues: unaryOperatorIssues,
              );
            }
            localTypesByName[bodyToken.lexeme] = typedBinding.typeName;
            continue;
          }

          final assignmentIndex = _bindingAssignmentIndex(tokens, bodyIndex);
          if (assignmentIndex != null && assignmentIndex < bodyClosingIndex) {
            final expressionStartIndex = _nextSignificantIndex(
              tokens,
              assignmentIndex + 1,
            );
            if (expressionStartIndex != null &&
                expressionStartIndex < bodyClosingIndex) {
              final inferredType = _inferExpressionType(
                tokens: tokens,
                expressionStartIndex: expressionStartIndex,
                signaturesByName: signaturesByName,
                inferredTypesByName: localTypesByName,
                binaryOperatorIssues: binaryOperatorIssues,
                unaryOperatorIssues: unaryOperatorIssues,
              );
              if (inferredType != null && inferredType.isNotEmpty) {
                localTypesByName[bodyToken.lexeme] = inferredType;
              }
            }
          }
        }

        if (!_isReturnExpressionMarker(bodyToken)) {
          continue;
        }
        final expressionStartIndex = _nextSignificantIndex(
          tokens,
          bodyIndex + 1,
        );
        if (expressionStartIndex == null ||
            expressionStartIndex >= bodyClosingIndex) {
          continue;
        }
        _inferExpressionType(
          tokens: tokens,
          expressionStartIndex: expressionStartIndex,
          signaturesByName: signaturesByName,
          inferredTypesByName: localTypesByName,
          binaryOperatorIssues: binaryOperatorIssues,
          unaryOperatorIssues: unaryOperatorIssues,
        );
      }
      index = bodyClosingIndex;
    }
  }

  int? _taskBodyClosingIndexAfterAsyncOperator(
    List<TokenSpan> tokens,
    int operatorIndex,
  ) {
    if (tokens[operatorIndex].lexeme != '||>') {
      return null;
    }
    final bodyOpeningIndex = _nextSignificantIndex(tokens, operatorIndex + 1);
    if (bodyOpeningIndex == null || tokens[bodyOpeningIndex].lexeme != '{') {
      return null;
    }
    return _matchingBraceIndex(tokens, bodyOpeningIndex);
  }

  Map<int, int> _functionBodyClosingByOpening({
    required List<TokenSpan> tokens,
    required Iterable<_FunctionSignature> signatures,
  }) {
    final bodyClosingByOpening = <int, int>{};
    for (final signature in signatures) {
      final bodySpan = _functionBodySpan(tokens, signature);
      if (bodySpan == null) {
        continue;
      }
      bodyClosingByOpening[bodySpan.openingIndex] = bodySpan.closingIndex;
    }
    return bodyClosingByOpening;
  }

  List<StyioConditionTypeMismatchIssue> conditionTypeMismatchIssues(
    String source,
  ) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    final signatures = signaturesByName.values.expand((items) => items);
    final functionBodyClosingByOpening = _functionBodyClosingByOpening(
      tokens: tokens,
      signatures: signatures,
    );
    final inferredTypesByName = <String, String>{};
    final issues = <StyioConditionTypeMismatchIssue>[];

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      final functionBodyClosingIndex = functionBodyClosingByOpening[index];
      if (functionBodyClosingIndex != null) {
        index = functionBodyClosingIndex;
        continue;
      }
      final taskBodyClosingIndex = _taskBodyClosingIndexAfterAsyncOperator(
        tokens,
        index,
      );
      if (taskBodyClosingIndex != null) {
        index = taskBodyClosingIndex;
        continue;
      }
      if (token.kind == TokenKind.keyword && token.lexeme == 'when') {
        final expressionStartIndex = _nextSignificantIndex(tokens, index + 1);
        if (expressionStartIndex == null ||
            _hasLineBreakBetween(tokens, index + 1, expressionStartIndex)) {
          continue;
        }
        final conditionRange = _conditionExpressionRange(
          source: source,
          tokens: tokens,
          expressionStartIndex: expressionStartIndex,
        );
        if (conditionRange == null || conditionRange.isCollapsed) {
          continue;
        }
        final actualType = _inferExpressionType(
          tokens: tokens,
          expressionStartIndex: expressionStartIndex,
          signaturesByName: signaturesByName,
          inferredTypesByName: inferredTypesByName,
        );
        if (actualType == null || actualType.isEmpty || actualType == 'bool') {
          continue;
        }
        issues.add(
          StyioConditionTypeMismatchIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'condition-type-mismatch',
              message: '`when` condition expects `bool`, got `$actualType`.',
              range: conditionRange,
            ),
            expectedTypeName: 'bool',
            actualTypeName: actualType,
            conditionRange: conditionRange,
            replacementConditionText: _conditionTypeReplacementText(
              source: source,
              conditionRange: conditionRange,
              actualType: actualType,
            ),
          ),
        );
        continue;
      }

      if (token.kind != TokenKind.identifier ||
          _syntaxHighlighter.isTypeName(token.lexeme)) {
        continue;
      }

      final typedBinding = _typedLocalBindingAtName(tokens, index);
      if (typedBinding != null) {
        inferredTypesByName[token.lexeme] = typedBinding.typeName;
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
      final inferredType = _inferExpressionType(
        tokens: tokens,
        expressionStartIndex: expressionStartIndex,
        signaturesByName: signaturesByName,
        inferredTypesByName: inferredTypesByName,
      );
      if (inferredType != null && inferredType.isNotEmpty) {
        inferredTypesByName[token.lexeme] = inferredType;
      }
    }

    for (final signature in signatures) {
      final bodySpan = _functionBodySpan(tokens, signature);
      if (bodySpan == null) {
        continue;
      }
      final localTypesByName = <String, String>{
        for (final parameter in signature.parameters)
          if (parameter.type.isNotEmpty) parameter.name: parameter.type,
      };
      for (
        var index = bodySpan.openingIndex + 1;
        index < bodySpan.closingIndex;
        index += 1
      ) {
        final token = tokens[index];
        if (token.kind == TokenKind.keyword && token.lexeme == 'when') {
          final expressionStartIndex = _nextSignificantIndex(tokens, index + 1);
          if (expressionStartIndex == null ||
              _hasLineBreakBetween(tokens, index + 1, expressionStartIndex)) {
            continue;
          }
          final conditionRange = _conditionExpressionRange(
            source: source,
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
          );
          if (conditionRange == null || conditionRange.isCollapsed) {
            continue;
          }
          final actualType = _inferExpressionType(
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
            signaturesByName: signaturesByName,
            inferredTypesByName: localTypesByName,
          );
          if (actualType == null ||
              actualType.isEmpty ||
              actualType == 'bool') {
            continue;
          }
          issues.add(
            StyioConditionTypeMismatchIssue(
              diagnostic: Diagnostic(
                severity: DiagnosticSeverity.warning,
                code: 'condition-type-mismatch',
                message: '`when` condition expects `bool`, got `$actualType`.',
                range: conditionRange,
              ),
              expectedTypeName: 'bool',
              actualTypeName: actualType,
              conditionRange: conditionRange,
              replacementConditionText: _conditionTypeReplacementText(
                source: source,
                conditionRange: conditionRange,
                actualType: actualType,
              ),
            ),
          );
          continue;
        }

        if (token.kind != TokenKind.identifier ||
            _syntaxHighlighter.isTypeName(token.lexeme)) {
          continue;
        }

        final typedBinding = _typedLocalBindingAtName(tokens, index);
        if (typedBinding != null &&
            typedBinding.assignmentIndex < bodySpan.closingIndex) {
          localTypesByName[token.lexeme] = typedBinding.typeName;
          continue;
        }

        final assignmentIndex = _bindingAssignmentIndex(tokens, index);
        if (assignmentIndex == null ||
            assignmentIndex >= bodySpan.closingIndex) {
          continue;
        }
        final expressionStartIndex = _nextSignificantIndex(
          tokens,
          assignmentIndex + 1,
        );
        if (expressionStartIndex == null ||
            expressionStartIndex >= bodySpan.closingIndex) {
          continue;
        }
        final inferredType = _inferExpressionType(
          tokens: tokens,
          expressionStartIndex: expressionStartIndex,
          signaturesByName: signaturesByName,
          inferredTypesByName: localTypesByName,
        );
        if (inferredType != null && inferredType.isNotEmpty) {
          localTypesByName[token.lexeme] = inferredType;
        }
      }
    }

    _collectTaskBodyExpressionTypeIssues(
      tokens: tokens,
      signaturesByName: signaturesByName,
      source: source,
      conditionTypeIssues: issues,
    );

    final dedupedIssues = <String, StyioConditionTypeMismatchIssue>{};
    for (final issue in issues) {
      final key =
          '${issue.conditionRange.start}:${issue.conditionRange.end}:'
          '${issue.actualTypeName}';
      dedupedIssues.putIfAbsent(key, () => issue);
    }
    return dedupedIssues.values.toList(growable: false)..sort(
      (left, right) =>
          left.conditionRange.start.compareTo(right.conditionRange.start),
    );
  }

  List<StyioFunctionReturnTypeIssue> functionReturnTypeIssues(String source) {
    final tokens = _syntaxHighlighter.tokenize(source);
    final signaturesByName = _collectFunctionSignatures(tokens);
    final signatures = signaturesByName.values.expand((items) => items);
    final issues = <StyioFunctionReturnTypeIssue>[];

    for (final signature in signatures) {
      final returnTypeRange = signature.returnTypeRange;
      if (signature.returnType.isEmpty || returnTypeRange == null) {
        continue;
      }
      final bodySpan = _functionBodySpan(tokens, signature);
      if (bodySpan == null) {
        continue;
      }

      final inferredTypesByName = <String, String>{
        for (final parameter in signature.parameters)
          if (parameter.type.isNotEmpty) parameter.name: parameter.type,
      };
      for (
        var index = bodySpan.openingIndex + 1;
        index < bodySpan.closingIndex;
        index += 1
      ) {
        final token = tokens[index];
        if (token.lexeme == '||>') {
          final taskBodyOpeningIndex = _nextSignificantIndex(tokens, index + 1);
          if (taskBodyOpeningIndex != null &&
              taskBodyOpeningIndex < bodySpan.closingIndex &&
              tokens[taskBodyOpeningIndex].lexeme == '{') {
            final taskBodyClosingIndex = _matchingBraceIndex(
              tokens,
              taskBodyOpeningIndex,
            );
            if (taskBodyClosingIndex != null &&
                taskBodyClosingIndex < bodySpan.closingIndex) {
              index = taskBodyClosingIndex;
              continue;
            }
          }
        }

        if (token.kind == TokenKind.identifier &&
            !_syntaxHighlighter.isTypeName(token.lexeme)) {
          final typedBinding = _typedLocalBindingAtName(tokens, index);
          if (typedBinding != null &&
              typedBinding.assignmentIndex < bodySpan.closingIndex) {
            final expressionStartIndex = _nextSignificantIndex(
              tokens,
              typedBinding.assignmentIndex + 1,
            );
            if (expressionStartIndex != null &&
                expressionStartIndex < bodySpan.closingIndex) {
              final inferredType = _inferExpressionType(
                tokens: tokens,
                expressionStartIndex: expressionStartIndex,
                signaturesByName: signaturesByName,
                inferredTypesByName: inferredTypesByName,
              );
              if (inferredType != null && inferredType.isNotEmpty) {
                inferredTypesByName[token.lexeme] = inferredType;
              }
            }
            inferredTypesByName[token.lexeme] = typedBinding.typeName;
            continue;
          }

          final assignmentIndex = _bindingAssignmentIndex(tokens, index);
          if (assignmentIndex != null &&
              assignmentIndex < bodySpan.closingIndex) {
            final expressionStartIndex = _nextSignificantIndex(
              tokens,
              assignmentIndex + 1,
            );
            if (expressionStartIndex != null &&
                expressionStartIndex < bodySpan.closingIndex) {
              final inferredType = _inferExpressionType(
                tokens: tokens,
                expressionStartIndex: expressionStartIndex,
                signaturesByName: signaturesByName,
                inferredTypesByName: inferredTypesByName,
              );
              if (inferredType != null && inferredType.isNotEmpty) {
                inferredTypesByName[token.lexeme] = inferredType;
              }
            }
          }
        }

        if (!_isReturnExpressionMarker(token)) {
          continue;
        }
        final expressionStartIndex = _nextSignificantIndex(tokens, index + 1);
        if (expressionStartIndex == null ||
            expressionStartIndex >= bodySpan.closingIndex) {
          continue;
        }
        final expressionRange = _lineExpressionRange(
          source: source,
          tokens: tokens,
          expressionStartIndex: expressionStartIndex,
          endExclusive: bodySpan.closingIndex,
        );
        if (expressionRange == null || expressionRange.isCollapsed) {
          continue;
        }
        final actualType = _inferExpressionType(
          tokens: tokens,
          expressionStartIndex: expressionStartIndex,
          signaturesByName: signaturesByName,
          inferredTypesByName: inferredTypesByName,
        );
        if (actualType == null ||
            actualType.isEmpty ||
            actualType == signature.returnType) {
          continue;
        }

        issues.add(
          StyioFunctionReturnTypeIssue(
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'return-type-mismatch',
              message:
                  'Return expression for `${signature.name}` expects '
                  '`${signature.returnType}`, got `$actualType`.',
              range: expressionRange,
            ),
            functionName: signature.name,
            expectedTypeName: signature.returnType,
            actualTypeName: actualType,
            returnExpressionRange: expressionRange,
            returnTypeRange: returnTypeRange,
            replacementReturnExpressionText: _argumentTypeReplacementText(
              tokens: tokens,
              expressionStartIndex: expressionStartIndex,
              argumentRange: expressionRange,
              expectedType: signature.returnType,
              actualType: actualType,
            ),
          ),
        );
      }
    }

    return issues;
  }

  Map<String, String> _inferLocalBindingTypes(
    List<TokenSpan> tokens,
    Map<String, List<_FunctionSignature>> signaturesByName,
  ) {
    final inferredTypesByName = <String, String>{};
    final functionBodySpans = signaturesByName.values
        .expand((items) => items)
        .map((signature) => _functionBodySpan(tokens, signature))
        .nonNulls
        .toList(growable: false);

    for (var index = 0; index < tokens.length; index += 1) {
      _FunctionBodySpan? containingFunctionBody;
      for (final span in functionBodySpans) {
        if (index > span.openingIndex && index < span.closingIndex) {
          containingFunctionBody = span;
          break;
        }
      }
      if (containingFunctionBody != null) {
        index = containingFunctionBody.closingIndex;
        continue;
      }
      final token = tokens[index];
      if (token.kind != TokenKind.identifier ||
          _syntaxHighlighter.isTypeName(token.lexeme)) {
        continue;
      }

      final typedBinding = _typedLocalBindingAtName(tokens, index);
      if (typedBinding != null) {
        inferredTypesByName[token.lexeme] = typedBinding.typeName;
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
      final inferredType = _inferExpressionType(
        tokens: tokens,
        expressionStartIndex: expressionStartIndex,
        signaturesByName: signaturesByName,
        inferredTypesByName: inferredTypesByName,
      );
      if (inferredType != null && inferredType.isNotEmpty) {
        inferredTypesByName[token.lexeme] = inferredType;
      }
    }

    return inferredTypesByName;
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
    final inferredTypesByName = _inferLocalBindingTypes(
      tokens,
      signaturesByName,
    );
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
      final providedParameterNames = _providedCallParameterNames(
        signature,
        arguments,
      );
      final argumentListRange = SourceRange(
        start: tokens[call.openingIndex].range.end,
        end: tokens[call.closingIndex].range.start,
      );
      final invocationRange = SourceRange(
        start: call.callable.range.start,
        end: tokens[call.closingIndex].range.end,
      );
      final parameterNames = signature.parameters
          .map((parameter) => parameter.name)
          .toSet();
      final argumentNameCounts = <String, int>{};
      var hasNamedArgumentIssue = false;

      for (final argument in arguments) {
        final argumentName = argument.name;
        if (argumentName == null) {
          continue;
        }

        if (!parameterNames.contains(argumentName)) {
          issues.add(
            StyioCallArgumentIssue(
              diagnostic: Diagnostic(
                severity: DiagnosticSeverity.warning,
                code: 'unknown-named-argument',
                message:
                    'Call to `${signature.name}` has no parameter named '
                    '`$argumentName`.',
                range: argument.nameRange ?? argument.range,
              ),
              callableName: signature.name,
              expectedArgumentCount: signature.parameters.length,
              actualArgumentCount: arguments.length,
              argumentListRange: argumentListRange,
              replacementArgumentText: '',
              namedArgumentName: argumentName,
              suggestedParameterName: _closestParameterName(
                argumentName,
                signature.parameters,
              ),
              argumentNameRange: argument.nameRange,
            ),
          );
          hasNamedArgumentIssue = true;
          continue;
        }

        final count = (argumentNameCounts[argumentName] ?? 0) + 1;
        argumentNameCounts[argumentName] = count;
        if (count > 1) {
          issues.add(
            StyioCallArgumentIssue(
              diagnostic: Diagnostic(
                severity: DiagnosticSeverity.warning,
                code: 'duplicate-named-argument',
                message:
                    'Argument `$argumentName` is already supplied in call to '
                    '`${signature.name}`.',
                range: argument.nameRange ?? argument.range,
              ),
              callableName: signature.name,
              expectedArgumentCount: signature.parameters.length,
              actualArgumentCount: arguments.length,
              argumentListRange: argumentListRange,
              replacementArgumentText: arguments
                  .where((candidate) => !identical(candidate, argument))
                  .map((argument) => argument.text)
                  .join(', '),
              namedArgumentName: argumentName,
              argumentNameRange: argument.nameRange,
            ),
          );
          hasNamedArgumentIssue = true;
          continue;
        }
      }

      final missingParameters = requiredParameters
          .where(
            (parameter) => !providedParameterNames.contains(parameter.name),
          )
          .toList(growable: false);

      if (missingParameters.isNotEmpty) {
        final usesNamedArguments = arguments.any(
          (argument) => argument.name != null,
        );
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
              for (final parameter in missingParameters)
                usesNamedArguments ? '${parameter.name}: value' : 'value',
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
        continue;
      }

      if (!hasNamedArgumentIssue) {
        final scopedInferredTypesByName = <String, String>{
          ...inferredTypesByName,
          ..._functionLocalTypesBeforeOffset(
            tokens: tokens,
            signaturesByName: signaturesByName,
            offset: call.callable.range.start,
          ),
        };
        issues.addAll(
          _callArgumentTypeIssues(
            source: source,
            tokens: tokens,
            signature: signature,
            arguments: arguments,
            signaturesByName: signaturesByName,
            inferredTypesByName: scopedInferredTypesByName,
            argumentListRange: argumentListRange,
          ),
        );
      }
    }

    return issues;
  }

  Map<String, String> _functionLocalTypesBeforeOffset({
    required List<TokenSpan> tokens,
    required Map<String, List<_FunctionSignature>> signaturesByName,
    required int offset,
  }) {
    final signatures = signaturesByName.values.expand((items) => items);
    for (final signature in signatures) {
      final bodySpan = _functionBodySpan(tokens, signature);
      if (bodySpan == null ||
          offset <= bodySpan.range.start ||
          offset >= bodySpan.range.end) {
        continue;
      }
      final localTypesByName = <String, String>{
        for (final parameter in signature.parameters)
          if (parameter.type.isNotEmpty) parameter.name: parameter.type,
      };
      for (
        var index = bodySpan.openingIndex + 1;
        index < bodySpan.closingIndex;
        index += 1
      ) {
        final token = tokens[index];
        if (token.range.start >= offset) {
          break;
        }
        if (token.kind != TokenKind.identifier ||
            _syntaxHighlighter.isTypeName(token.lexeme)) {
          continue;
        }

        final typedBinding = _typedLocalBindingAtName(tokens, index);
        if (typedBinding != null &&
            typedBinding.assignmentIndex < bodySpan.closingIndex) {
          localTypesByName[token.lexeme] = typedBinding.typeName;
          continue;
        }

        final assignmentIndex = _bindingAssignmentIndex(tokens, index);
        if (assignmentIndex == null ||
            assignmentIndex >= bodySpan.closingIndex ||
            assignmentIndex >= offset) {
          continue;
        }
        final expressionStartIndex = _nextSignificantIndex(
          tokens,
          assignmentIndex + 1,
        );
        if (expressionStartIndex == null ||
            expressionStartIndex >= bodySpan.closingIndex ||
            expressionStartIndex >= offset) {
          continue;
        }
        final inferredType = _inferExpressionType(
          tokens: tokens,
          expressionStartIndex: expressionStartIndex,
          signaturesByName: signaturesByName,
          inferredTypesByName: localTypesByName,
        );
        if (inferredType != null && inferredType.isNotEmpty) {
          localTypesByName[token.lexeme] = inferredType;
        }
      }
      return localTypesByName;
    }
    return const <String, String>{};
  }

  List<StyioCallArgumentIssue> _callArgumentTypeIssues({
    required String source,
    required List<TokenSpan> tokens,
    required _FunctionSignature signature,
    required List<_ArgumentSegment> arguments,
    required Map<String, List<_FunctionSignature>> signaturesByName,
    required Map<String, String> inferredTypesByName,
    required SourceRange argumentListRange,
  }) {
    final issues = <StyioCallArgumentIssue>[];
    for (final argument in arguments) {
      final parameter = _parameterForCallArgument(
        signature: signature,
        arguments: arguments,
        argument: argument,
      );
      if (parameter == null || parameter.type.isEmpty) {
        continue;
      }

      final argumentRange = argument.name == null
          ? argument.range
          : _argumentValueRange(
              source: source,
              tokens: tokens,
              argument: argument,
            );
      if (argumentRange == null || argumentRange.isCollapsed) {
        continue;
      }

      final expressionStartIndex = _firstSignificantIndexInRange(
        tokens,
        argumentRange,
      );
      if (expressionStartIndex == null) {
        continue;
      }

      final actualType = _inferExpressionType(
        tokens: tokens,
        expressionStartIndex: expressionStartIndex,
        signaturesByName: signaturesByName,
        inferredTypesByName: inferredTypesByName,
      );
      if (actualType == null ||
          actualType.isEmpty ||
          actualType == parameter.type) {
        continue;
      }

      issues.add(
        StyioCallArgumentIssue(
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'argument-type-mismatch',
            message:
                'Argument `${parameter.name}` for `${signature.name}` expects '
                '`${parameter.type}`, got `$actualType`.',
            range: argumentRange,
          ),
          callableName: signature.name,
          expectedArgumentCount: signature.parameters.length,
          actualArgumentCount: arguments.length,
          argumentListRange: argumentListRange,
          replacementArgumentText: _argumentTypeReplacementText(
            tokens: tokens,
            expressionStartIndex: expressionStartIndex,
            argumentRange: argumentRange,
            expectedType: parameter.type,
            actualType: actualType,
          ),
          parameterName: parameter.name,
          expectedTypeName: parameter.type,
          actualTypeName: actualType,
          argumentRange: argumentRange,
          parameterTypeRange: _parameterTypeRange(
            tokens: tokens,
            signature: signature,
            parameter: parameter,
          ),
        ),
      );
    }
    return issues;
  }

  String _argumentTypeReplacementText({
    required List<TokenSpan> tokens,
    required int expressionStartIndex,
    required SourceRange argumentRange,
    required String expectedType,
    required String actualType,
  }) {
    final token = tokens[expressionStartIndex];
    if ((expectedType == 'i64' || expectedType == 'f64') &&
        actualType == 'bool' &&
        token.range.start == argumentRange.start &&
        token.range.end == argumentRange.end) {
      if (token.lexeme == 'true') {
        return expectedType == 'f64' ? '1.0' : '1';
      }
      if (token.lexeme == 'false') {
        return expectedType == 'f64' ? '0.0' : '0';
      }
    }
    if (expectedType != 'f64' || actualType != 'i64') {
      return '';
    }
    if (token.kind != TokenKind.number ||
        token.lexeme.contains('.') ||
        token.range.start != argumentRange.start ||
        token.range.end != argumentRange.end) {
      return '';
    }
    return '${token.lexeme}.0';
  }

  SourceRange? _initializerRangeForBinding({
    required String source,
    required List<TokenSpan> tokens,
    required int expressionStartIndex,
  }) {
    var end = tokens[expressionStartIndex].range.end;
    for (
      var index = expressionStartIndex + 1;
      index < tokens.length;
      index += 1
    ) {
      final token = tokens[index];
      if (token.lexeme.contains('\n') || token.kind == TokenKind.comment) {
        break;
      }
      end = token.range.end;
    }
    return _trimmedRange(
      source,
      SourceRange(start: tokens[expressionStartIndex].range.start, end: end),
    );
  }

  SourceRange? _lineExpressionRange({
    required String source,
    required List<TokenSpan> tokens,
    required int expressionStartIndex,
    required int endExclusive,
  }) {
    var end = tokens[expressionStartIndex].range.end;
    var nestedDepth =
        tokens[expressionStartIndex].lexeme == '(' ||
            tokens[expressionStartIndex].lexeme == '[' ||
            tokens[expressionStartIndex].lexeme == '{'
        ? 1
        : 0;
    for (
      var index = expressionStartIndex + 1;
      index < endExclusive;
      index += 1
    ) {
      final token = tokens[index];
      if (token.lexeme.contains('\n') || token.kind == TokenKind.comment) {
        break;
      }
      if (token.lexeme == '(' || token.lexeme == '[' || token.lexeme == '{') {
        nestedDepth += 1;
      } else if (token.lexeme == ')' ||
          token.lexeme == ']' ||
          token.lexeme == '}') {
        if (nestedDepth == 0) {
          break;
        }
        nestedDepth -= 1;
      }
      end = token.range.end;
    }
    return _trimmedRange(
      source,
      SourceRange(start: tokens[expressionStartIndex].range.start, end: end),
    );
  }

  SourceRange? _conditionExpressionRange({
    required String source,
    required List<TokenSpan> tokens,
    required int expressionStartIndex,
  }) {
    var end = tokens[expressionStartIndex].range.end;
    var nestedDepth = 0;
    for (
      var index = expressionStartIndex + 1;
      index < tokens.length;
      index += 1
    ) {
      final token = tokens[index];
      if (token.lexeme.contains('\n') || token.kind == TokenKind.comment) {
        break;
      }
      if (nestedDepth == 0 && token.lexeme == '->') {
        break;
      }
      if (token.lexeme == '(' || token.lexeme == '[' || token.lexeme == '{') {
        nestedDepth += 1;
      } else if (token.lexeme == ')' ||
          token.lexeme == ']' ||
          token.lexeme == '}') {
        nestedDepth -= 1;
      }
      end = token.range.end;
    }
    return _trimmedRange(
      source,
      SourceRange(start: tokens[expressionStartIndex].range.start, end: end),
    );
  }

  String _conditionTypeReplacementText({
    required String source,
    required SourceRange conditionRange,
    required String actualType,
  }) {
    if (!_isNumericType(actualType)) {
      return '';
    }
    final conditionText = source
        .substring(conditionRange.start, conditionRange.end)
        .trim();
    if (conditionText.isEmpty) {
      return '';
    }
    final zero = actualType.startsWith('f') ? '0.0' : '0';
    return '$conditionText != $zero';
  }

  bool _isReturnExpressionMarker(TokenSpan token) {
    return token.lexeme == 'emit' ||
        token.lexeme == '<|' ||
        token.lexeme == '|<|';
  }

  String? _closestParameterName(
    String argumentName,
    List<ParameterInfoParameter> parameters,
  ) {
    _ParameterNameCandidate? best;
    for (final parameter in parameters) {
      final score = _parameterNameSimilarityScore(argumentName, parameter.name);
      if (score == null) {
        continue;
      }
      final candidate = _ParameterNameCandidate(
        name: parameter.name,
        score: score,
      );
      if (best == null ||
          candidate.score < best.score ||
          (candidate.score == best.score &&
              candidate.name.compareTo(best.name) < 0)) {
        best = candidate;
      }
    }
    return best?.name;
  }

  int? _parameterNameSimilarityScore(
    String argumentName,
    String parameterName,
  ) {
    final left = argumentName.toLowerCase();
    final right = parameterName.toLowerCase();
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
    final limit = left.length < 5 && right.length < 5 ? 1 : 2;
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
      final rawDocumentation = _leadingDocumentationForDeclaration(
        tokens,
        declarationRange,
      );
      final parameterDocumentation = _parameterDocumentationByName(
        rawDocumentation,
      );
      final documentedParameters = parameters
          .map(
            (parameter) => ParameterInfoParameter(
              name: parameter.name,
              range: parameter.range,
              type: parameter.type,
              defaultValue: parameter.defaultValue,
              documentation: parameterDocumentation[parameter.name] ?? '',
            ),
          )
          .toList(growable: false);
      var returnType = _functionReturnTypeText(
        tokens: tokens,
        closingIndex: closingIndex,
      );
      final returnTypeRange = _functionReturnTypeRange(
        tokens: tokens,
        closingIndex: closingIndex,
      );
      if (returnType.isEmpty && prefix == '#') {
        returnType =
            _hashFunctionInferredReturnType(
              tokens: tokens,
              closingIndex: closingIndex,
              signaturesByName: signaturesByName,
            ) ??
            '';
      }
      final signature = _FunctionSignature(
        name: nameToken.lexeme,
        nameRange: nameToken.range,
        prefix: prefix,
        openingIndex: openingIndex,
        closingIndex: closingIndex,
        parameters: documentedParameters,
        returnType: returnType,
        returnTypeRange: returnTypeRange,
        displayText:
            '${prefix == '#' ? '#' : '$prefix '}${nameToken.lexeme}'
            '(${documentedParameters.map((parameter) => parameter.displayText).join(', ')})',
        documentation: _documentationSummaryText(rawDocumentation),
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

  String? _hashFunctionInferredReturnType({
    required List<TokenSpan> tokens,
    required int closingIndex,
    required Map<String, List<_FunctionSignature>> signaturesByName,
  }) {
    final bodyOpeningIndex = _functionBodyOpeningIndexAfterSignature(
      tokens,
      closingIndex,
    );
    if (bodyOpeningIndex == null) {
      return null;
    }
    final bodyClosingIndex = _matchingBraceIndex(tokens, bodyOpeningIndex);
    if (bodyClosingIndex == null) {
      return null;
    }
    final inferredTypesByName = <String, String>{};
    for (
      var index = bodyOpeningIndex + 1;
      index < bodyClosingIndex;
      index += 1
    ) {
      final token = tokens[index];
      if (!_isReturnExpressionMarker(token)) {
        if (token.kind == TokenKind.identifier &&
            !_syntaxHighlighter.isTypeName(token.lexeme)) {
          final typedBinding = _typedLocalBindingAtName(tokens, index);
          if (typedBinding != null &&
              typedBinding.assignmentIndex < bodyClosingIndex) {
            inferredTypesByName[token.lexeme] = typedBinding.typeName;
            continue;
          }
          final assignmentIndex = _bindingAssignmentIndex(tokens, index);
          final expressionStartIndex = assignmentIndex == null
              ? null
              : _nextSignificantIndex(tokens, assignmentIndex + 1);
          if (expressionStartIndex != null &&
              expressionStartIndex < bodyClosingIndex) {
            final inferredType = _inferExpressionType(
              tokens: tokens,
              expressionStartIndex: expressionStartIndex,
              signaturesByName: signaturesByName,
              inferredTypesByName: inferredTypesByName,
            );
            if (inferredType != null && inferredType.isNotEmpty) {
              inferredTypesByName[token.lexeme] = inferredType;
            }
          }
        }
        continue;
      }
      final expressionStartIndex = _nextSignificantIndex(tokens, index + 1);
      if (expressionStartIndex == null ||
          expressionStartIndex >= bodyClosingIndex) {
        return null;
      }
      return _inferExpressionType(
        tokens: tokens,
        expressionStartIndex: expressionStartIndex,
        signaturesByName: signaturesByName,
        inferredTypesByName: inferredTypesByName,
      );
    }
    return null;
  }

  int? _functionBodyOpeningIndexAfterSignature(
    List<TokenSpan> tokens,
    int closingIndex,
  ) {
    var index = _nextSignificantIndex(tokens, closingIndex + 1);
    while (index != null && index < tokens.length) {
      final token = tokens[index];
      if (token.lexeme == '{') {
        return index;
      }
      if (token.lexeme != '=>' && token.lexeme != ':=' && token.lexeme != '=') {
        return null;
      }
      index = _nextSignificantIndex(tokens, index + 1);
    }
    return null;
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

  SourceRange? _functionReturnTypeRange({
    required List<TokenSpan> tokens,
    required int closingIndex,
  }) {
    final colonIndex = _nextSignificantIndex(tokens, closingIndex + 1);
    if (colonIndex == null || tokens[colonIndex].lexeme != ':') {
      return null;
    }

    int? start;
    int? end;
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
      start ??= token.range.start;
      end = token.range.end;
    }
    if (start == null || end == null) {
      return null;
    }
    return SourceRange(start: start, end: end);
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
    final defaultValueText = _parameterDefaultValueText(
      tokens: tokens,
      startIndex: nameIndex + 1,
      endExclusive: endExclusive,
    );
    return ParameterInfoParameter(
      name: nameToken.lexeme,
      type: typeText,
      defaultValue: defaultValueText,
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

  String _parameterDefaultValueText({
    required List<TokenSpan> tokens,
    required int startIndex,
    required int endExclusive,
  }) {
    final assignmentIndex = _firstLexemeIndex(
      tokens: tokens,
      lexeme: '=',
      startIndex: startIndex,
      endExclusive: endExclusive,
    );
    if (assignmentIndex == null) {
      return '';
    }

    final parts = <String>[];
    for (var index = assignmentIndex + 1; index < endExclusive; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
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
          nameToken: _namedArgumentTokenForRange(tokens, range),
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
    return argument.name != null || argument.text == parameter.name;
  }

  Set<String> _providedCallParameterNames(
    _FunctionSignature signature,
    List<_ArgumentSegment> arguments,
  ) {
    final providedNames = <String>{};
    final parameterNames = signature.parameters
        .map((parameter) => parameter.name)
        .toSet();
    var positionalIndex = 0;

    for (final argument in arguments) {
      final name = argument.name;
      if (name != null && parameterNames.contains(name)) {
        providedNames.add(name);
        continue;
      }
      while (positionalIndex < signature.parameters.length &&
          providedNames.contains(signature.parameters[positionalIndex].name)) {
        positionalIndex += 1;
      }
      if (positionalIndex < signature.parameters.length) {
        providedNames.add(signature.parameters[positionalIndex].name);
        positionalIndex += 1;
      }
    }
    return providedNames;
  }

  ParameterInfoParameter? _parameterForPositionalArgument({
    required _FunctionSignature signature,
    required List<_ArgumentSegment> arguments,
    required _ArgumentSegment targetArgument,
  }) {
    final parameterNames = signature.parameters
        .map((parameter) => parameter.name)
        .toSet();
    final namedArgumentCounts = <String, int>{};
    for (final argument in arguments) {
      final name = argument.name;
      if (name == null) {
        continue;
      }
      if (!parameterNames.contains(name)) {
        return null;
      }
      namedArgumentCounts[name] = (namedArgumentCounts[name] ?? 0) + 1;
      if (namedArgumentCounts[name]! > 1) {
        return null;
      }
    }

    final providedNames = <String>{};
    var positionalIndex = 0;
    for (final argument in arguments) {
      final name = argument.name;
      if (name != null) {
        providedNames.add(name);
        continue;
      }

      while (positionalIndex < signature.parameters.length &&
          providedNames.contains(signature.parameters[positionalIndex].name)) {
        positionalIndex += 1;
      }
      if (positionalIndex >= signature.parameters.length) {
        return null;
      }

      final parameter = signature.parameters[positionalIndex];
      positionalIndex += 1;
      if (!identical(argument, targetArgument)) {
        continue;
      }
      if ((namedArgumentCounts[parameter.name] ?? 0) > 0) {
        return null;
      }
      return parameter;
    }
    return null;
  }

  ParameterInfoParameter? _parameterForCallArgument({
    required _FunctionSignature signature,
    required List<_ArgumentSegment> arguments,
    required _ArgumentSegment argument,
  }) {
    final argumentName = argument.name;
    if (argumentName != null) {
      for (final parameter in signature.parameters) {
        if (parameter.name == argumentName) {
          return parameter;
        }
      }
      return null;
    }

    return _parameterForPositionalArgument(
      signature: signature,
      arguments: arguments,
      targetArgument: argument,
    );
  }

  SourceRange? _parameterTypeRange({
    required List<TokenSpan> tokens,
    required _FunctionSignature signature,
    required ParameterInfoParameter parameter,
  }) {
    final nameIndex = tokens.indexWhere(
      (token) => _sameRange(token.range, parameter.range),
    );
    if (nameIndex < 0 || nameIndex >= signature.closingIndex) {
      return null;
    }

    final colonIndex = _nextSignificantIndex(tokens, nameIndex + 1);
    if (colonIndex == null ||
        colonIndex >= signature.closingIndex ||
        tokens[colonIndex].lexeme != ':') {
      return null;
    }

    int? start;
    int? end;
    var parenDepth = 0;
    var bracketDepth = 0;
    for (
      var index = colonIndex + 1;
      index < signature.closingIndex;
      index += 1
    ) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      if (parenDepth == 0 &&
          bracketDepth == 0 &&
          (token.lexeme == ',' || token.lexeme == '=')) {
        break;
      }

      start ??= token.range.start;
      end = token.range.end;
      if (token.kind == TokenKind.punctuation && token.lexeme == '(') {
        parenDepth += 1;
      } else if (token.kind == TokenKind.punctuation && token.lexeme == ')') {
        parenDepth -= 1;
      } else if (token.kind == TokenKind.punctuation && token.lexeme == '[') {
        bracketDepth += 1;
      } else if (token.kind == TokenKind.punctuation && token.lexeme == ']') {
        bracketDepth -= 1;
      }
    }

    if (start == null || end == null) {
      return null;
    }
    return SourceRange(start: start, end: end);
  }

  _ArgumentSegment? _argumentAtOffset(
    List<_ArgumentSegment> arguments,
    int offset,
  ) {
    for (final argument in arguments) {
      if (argument.range.contains(offset) || offset == argument.range.end) {
        return argument;
      }
    }
    return null;
  }

  SourceRange? _argumentValueRange({
    required String source,
    required List<TokenSpan> tokens,
    required _ArgumentSegment argument,
  }) {
    final nameToken = argument.nameToken;
    if (nameToken == null) {
      return null;
    }
    final nameIndex = tokens.indexWhere(
      (token) => _sameRange(token.range, nameToken.range),
    );
    if (nameIndex < 0) {
      return null;
    }
    final separatorIndex = _nextSignificantIndex(tokens, nameIndex + 1);
    if (separatorIndex == null || tokens[separatorIndex].lexeme != ':') {
      return null;
    }

    var valueStart = tokens[separatorIndex].range.end;
    while (valueStart < argument.range.end &&
        source.codeUnitAt(valueStart) <= 0x20) {
      valueStart += 1;
    }
    return SourceRange(start: valueStart, end: argument.range.end);
  }

  _NamedArgumentCompletionContext? _namedArgumentCompletionContext({
    required String source,
    required List<TokenSpan> tokens,
    required _CallArgumentList call,
    required int offset,
  }) {
    final openingToken = tokens[call.openingIndex];
    final closingToken = tokens[call.closingIndex];
    final normalizedOffset = offset
        .clamp(openingToken.range.end, closingToken.range.start)
        .toInt();
    var segmentStart = openingToken.range.end;
    var segmentEnd = closingToken.range.start;
    var nestedDepth = 0;

    for (
      var index = call.openingIndex + 1;
      index < call.closingIndex;
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
        if (normalizedOffset <= token.range.start) {
          segmentEnd = token.range.start;
          break;
        }
        segmentStart = token.range.end;
      }
    }

    if (_hasTopLevelLexemeInRange(
      tokens: tokens,
      lexeme: ':',
      start: segmentStart,
      end: segmentEnd,
    )) {
      return null;
    }

    final candidateToken = _completionSeedTokenInSegment(
      tokens: tokens,
      offset: normalizedOffset,
      start: segmentStart,
      end: segmentEnd,
    );

    if (candidateToken == null) {
      final prefixRange = _trimmedRange(
        source,
        SourceRange(start: segmentStart, end: normalizedOffset),
      );
      if (!prefixRange.isCollapsed) {
        return null;
      }
      return _NamedArgumentCompletionContext(
        segmentRange: SourceRange(start: segmentStart, end: segmentEnd),
        replacementRange: SourceRange(
          start: normalizedOffset,
          end: normalizedOffset,
        ),
      );
    }

    final beforeCandidate = source
        .substring(segmentStart, candidateToken.range.start)
        .trim();
    if (beforeCandidate.isNotEmpty) {
      return null;
    }

    return _NamedArgumentCompletionContext(
      segmentRange: SourceRange(start: segmentStart, end: segmentEnd),
      replacementRange: candidateToken.range,
    );
  }

  TokenSpan? _completionSeedTokenInSegment({
    required List<TokenSpan> tokens,
    required int offset,
    required int start,
    required int end,
  }) {
    for (final token in tokens) {
      if (token.range.end < start) {
        continue;
      }
      if (token.range.start > end) {
        break;
      }
      if (token.kind != TokenKind.identifier &&
          token.kind != TokenKind.keyword) {
        continue;
      }
      if (token.range.start < start || token.range.end > end) {
        continue;
      }
      if (token.range.contains(offset) || token.range.end == offset) {
        return token;
      }
    }
    return null;
  }

  bool _hasTopLevelLexemeInRange({
    required List<TokenSpan> tokens,
    required String lexeme,
    required int start,
    required int end,
  }) {
    var parenDepth = 0;
    var bracketDepth = 0;
    for (final token in tokens) {
      if (token.range.end <= start) {
        continue;
      }
      if (token.range.start >= end) {
        break;
      }
      if (token.kind == TokenKind.punctuation && token.lexeme == '(') {
        parenDepth += 1;
        continue;
      }
      if (token.kind == TokenKind.punctuation && token.lexeme == ')') {
        parenDepth -= 1;
        continue;
      }
      if (token.kind == TokenKind.punctuation && token.lexeme == '[') {
        bracketDepth += 1;
        continue;
      }
      if (token.kind == TokenKind.punctuation && token.lexeme == ']') {
        bracketDepth -= 1;
        continue;
      }
      if (parenDepth == 0 && bracketDepth == 0 && token.lexeme == lexeme) {
        return true;
      }
    }
    return false;
  }

  TokenSpan? _namedArgumentTokenForRange(
    List<TokenSpan> tokens,
    SourceRange range,
  ) {
    int? firstIndex;
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.range.start < range.start || token.range.end > range.end) {
        continue;
      }
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      firstIndex = index;
      break;
    }
    if (firstIndex == null || tokens[firstIndex].kind != TokenKind.identifier) {
      return null;
    }
    final separatorIndex = _nextSignificantIndex(tokens, firstIndex + 1);
    if (separatorIndex == null ||
        tokens[separatorIndex].range.end > range.end ||
        tokens[separatorIndex].lexeme != ':') {
      return null;
    }
    return tokens[firstIndex];
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
    final signatures = _collectFunctionSignatures(
      tokens,
    ).values.expand((items) => items).toList(growable: false);
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
      final target =
          exactDeclaration ??
          _nearestDeclaration(
            tokens: tokens,
            signatures: signatures,
            candidates: candidates,
            token: token,
          );
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

  DocumentSymbol? _nearestDeclaration({
    required List<TokenSpan> tokens,
    required List<_FunctionSignature> signatures,
    required List<DocumentSymbol> candidates,
    required TokenSpan token,
  }) {
    DocumentSymbol? best;
    for (final candidate in candidates) {
      if (candidate.nameRange.start > token.range.start) {
        continue;
      }
      if (!_isSymbolVisibleFromToken(
        tokens: tokens,
        signatures: signatures,
        symbol: candidate,
        token: token,
      )) {
        continue;
      }
      if (best == null || candidate.nameRange.start > best.nameRange.start) {
        best = candidate;
      }
    }
    return best;
  }

  bool _isSymbolVisibleFromToken({
    required List<TokenSpan> tokens,
    required List<_FunctionSignature> signatures,
    required DocumentSymbol symbol,
    required TokenSpan token,
  }) {
    return _isSymbolVisibleFromOffset(
      tokens: tokens,
      signatures: signatures,
      symbol: symbol,
      offset: token.range.start,
    );
  }

  bool _isSymbolVisibleFromOffset({
    required List<TokenSpan> tokens,
    required List<_FunctionSignature> signatures,
    required DocumentSymbol symbol,
    required int offset,
  }) {
    if (symbol.kind != SymbolKind.variable &&
        symbol.kind != SymbolKind.parameter) {
      return true;
    }
    for (final signature in signatures) {
      final bodySpan = _functionBodySpan(tokens, signature);
      if (bodySpan == null) {
        continue;
      }
      final parameterListRange = SourceRange(
        start: tokens[signature.openingIndex].range.start,
        end: tokens[signature.closingIndex].range.end,
      );
      final symbolIsFunctionLocal =
          bodySpan.range.contains(symbol.nameRange.start) ||
          (symbol.kind == SymbolKind.parameter &&
              parameterListRange.contains(symbol.nameRange.start));
      if (!symbolIsFunctionLocal) {
        continue;
      }
      return bodySpan.range.contains(offset);
    }
    return true;
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
      if (token.kind != TokenKind.comment || !_isDocumentationComment(token)) {
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
    if (lexeme.startsWith('/**')) {
      return _documentationTextForBlockComment(lexeme);
    }
    final text = lexeme.substring(3);
    return text.startsWith(' ') ? text.substring(1) : text;
  }

  bool _isDocumentationComment(TokenSpan token) {
    return token.lexeme.startsWith('///') || token.lexeme.startsWith('/**');
  }

  String _documentationTextForBlockComment(String lexeme) {
    var text = lexeme.substring(3);
    if (text.endsWith('*/')) {
      text = text.substring(0, text.length - 2);
    }
    final lines = text
        .split('\n')
        .map((line) {
          var trimmed = line.trimLeft();
          if (trimmed.startsWith('*')) {
            trimmed = trimmed.substring(1);
            if (trimmed.startsWith(' ')) {
              trimmed = trimmed.substring(1);
            }
          }
          return trimmed.trimRight();
        })
        .toList(growable: false);
    return lines.join('\n').trim();
  }

  String _documentationSummaryText(String documentation) {
    return documentation
        .split('\n')
        .where((line) => !_isParameterDocumentationLine(line))
        .join('\n')
        .trim();
  }

  Map<String, String> _parameterDocumentationByName(String documentation) {
    final docsByName = <String, String>{};
    final tagPattern = RegExp(
      r'^@param(?:\s+|\[)([A-Za-z_][A-Za-z0-9_]*)(?:\])?\s*(.*)$',
    );
    for (final line in documentation.split('\n')) {
      final match = tagPattern.firstMatch(line.trim());
      if (match == null) {
        continue;
      }
      final name = match.group(1)!;
      final text = match.group(2)!.trim();
      if (text.isNotEmpty) {
        docsByName[name] = text;
      }
    }
    return docsByName;
  }

  bool _isParameterDocumentationLine(String line) {
    return line.trimLeft().startsWith('@param ') ||
        line.trimLeft().startsWith('@param[');
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

  int? _firstSignificantIndexInRange(
    List<TokenSpan> tokens,
    SourceRange range,
  ) {
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.range.end <= range.start) {
        continue;
      }
      if (token.range.start >= range.end) {
        break;
      }
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      return index;
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
    return _functionBodySpan(tokens, signature)?.range;
  }

  _FunctionBodySpan? _functionBodySpan(
    List<TokenSpan> tokens,
    _FunctionSignature signature,
  ) {
    var index = _nextSignificantIndex(tokens, signature.closingIndex + 1);
    while (index != null && index < tokens.length) {
      final token = tokens[index];
      if (token.lexeme == ':') {
        index = _nextSignificantIndex(tokens, index + 1);
        while (index != null && index < tokens.length) {
          final typeToken = tokens[index];
          if (typeToken.lexeme.contains('\n') ||
              typeToken.lexeme == '{' ||
              typeToken.lexeme == '=>' ||
              typeToken.lexeme == ':=' ||
              typeToken.lexeme == '=') {
            break;
          }
          index = _nextSignificantIndex(tokens, index + 1);
        }
        continue;
      }
      if (token.lexeme == '{') {
        final closingIndex = _matchingBraceIndex(tokens, index);
        if (closingIndex == null) {
          return null;
        }
        return _FunctionBodySpan(
          openingIndex: index,
          closingIndex: closingIndex,
          range: SourceRange(
            start: token.range.end,
            end: tokens[closingIndex].range.start,
          ),
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

    for (final parameter in parameters) {
      if (parameter.name == parameter.originalName) {
        continue;
      }
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
        for (final argument in arguments) {
          if (argument.name != parameter.originalName ||
              argument.nameRange == null) {
            continue;
          }
          edits.add(
            FormattingEdit(range: argument.nameRange!, newText: parameter.name),
          );
        }
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
        final nextArgumentText = _changeSignatureCallArgumentText(
          originalNames: originalNames,
          parameters: parameters,
          arguments: arguments,
        );
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

  String _changeSignatureCallArgumentText({
    required List<String> originalNames,
    required List<ChangeSignatureParameterUpdate> parameters,
    required List<_ArgumentSegment> arguments,
  }) {
    if (!arguments.any((argument) => argument.name != null)) {
      return parameters
          .map(
            (parameter) =>
                arguments[originalNames.indexOf(parameter.originalName)].text,
          )
          .join(', ');
    }

    final argumentsByParameterName = <String, String>{};
    final originalNameSet = originalNames.toSet();
    var positionalIndex = 0;
    for (final argument in arguments) {
      final name = argument.name;
      if (name != null && originalNameSet.contains(name)) {
        argumentsByParameterName[name] = argument.text;
        continue;
      }
      while (positionalIndex < originalNames.length &&
          argumentsByParameterName.containsKey(
            originalNames[positionalIndex],
          )) {
        positionalIndex += 1;
      }
      if (positionalIndex < originalNames.length) {
        argumentsByParameterName[originalNames[positionalIndex]] =
            argument.text;
        positionalIndex += 1;
      }
    }
    return [
      for (final parameter in parameters)
        if (argumentsByParameterName.containsKey(parameter.originalName))
          argumentsByParameterName[parameter.originalName]!,
    ].join(', ');
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
    required this.returnTypeRange,
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
  final SourceRange? returnTypeRange;
  final String displayText;
  final String documentation;
}

class _FunctionBodySpan {
  const _FunctionBodySpan({
    required this.openingIndex,
    required this.closingIndex,
    required this.range,
  });

  final int openingIndex;
  final int closingIndex;
  final SourceRange range;
}

class _ExpressionTypeSpan {
  const _ExpressionTypeSpan({
    required this.startIndex,
    required this.typeName,
    required this.endIndex,
  });

  final int startIndex;
  final String typeName;
  final int endIndex;
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

class _TypedLocalBinding {
  const _TypedLocalBinding({
    required this.nameIndex,
    required this.colonIndex,
    required this.typeIndex,
    required this.assignmentIndex,
    required this.typeName,
  });

  final int nameIndex;
  final int colonIndex;
  final int typeIndex;
  final int assignmentIndex;
  final String typeName;
}

class _ExplicitTypedLocal {
  const _ExplicitTypedLocal({
    required this.typeName,
    required this.typeRange,
    required this.initializerRange,
    required this.initializerExpressionStartIndex,
    required this.initializerActualTypeName,
  });

  final String typeName;
  final SourceRange typeRange;
  final SourceRange? initializerRange;
  final int? initializerExpressionStartIndex;
  final String initializerActualTypeName;
}

class _ArgumentSegment {
  const _ArgumentSegment({
    required this.range,
    required this.text,
    this.nameToken,
  });

  final SourceRange range;
  final String text;
  final TokenSpan? nameToken;

  String? get name => nameToken?.lexeme;

  SourceRange? get nameRange => nameToken?.range;
}

class _NamedArgumentCompletionContext {
  const _NamedArgumentCompletionContext({
    required this.segmentRange,
    required this.replacementRange,
  });

  final SourceRange segmentRange;
  final SourceRange replacementRange;
}

class _ParameterNameCandidate {
  const _ParameterNameCandidate({required this.name, required this.score});

  final String name;
  final int score;
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
    this.namedArgumentName = '',
    this.suggestedParameterName,
    this.argumentNameRange,
    this.parameterName = '',
    this.expectedTypeName = '',
    this.actualTypeName = '',
    this.argumentRange,
    this.parameterTypeRange,
  });

  final Diagnostic diagnostic;
  final String callableName;
  final int expectedArgumentCount;
  final int actualArgumentCount;
  final SourceRange argumentListRange;
  final String replacementArgumentText;
  final List<String> missingParameterNames;
  final int extraArgumentCount;
  final String namedArgumentName;
  final String? suggestedParameterName;
  final SourceRange? argumentNameRange;
  final String parameterName;
  final String expectedTypeName;
  final String actualTypeName;
  final SourceRange? argumentRange;
  final SourceRange? parameterTypeRange;

  bool get hasMissingArguments => missingParameterNames.isNotEmpty;
  bool get hasExtraArguments => extraArgumentCount > 0;
  bool get hasUnknownNamedArgument =>
      diagnostic.code == 'unknown-named-argument' &&
      namedArgumentName.isNotEmpty;
  bool get hasDuplicateNamedArgument =>
      diagnostic.code == 'duplicate-named-argument' &&
      namedArgumentName.isNotEmpty;
  bool get hasArgumentTypeMismatch =>
      diagnostic.code == 'argument-type-mismatch' &&
      parameterName.isNotEmpty &&
      expectedTypeName.isNotEmpty &&
      actualTypeName.isNotEmpty;
}

class StyioTypeMismatchIssue {
  const StyioTypeMismatchIssue({
    required this.diagnostic,
    required this.variableName,
    required this.expectedTypeName,
    required this.actualTypeName,
    required this.initializerRange,
    required this.typeRange,
    required this.replacementInitializerText,
  });

  final Diagnostic diagnostic;
  final String variableName;
  final String expectedTypeName;
  final String actualTypeName;
  final SourceRange initializerRange;
  final SourceRange typeRange;
  final String replacementInitializerText;
}

class StyioAssignmentTypeMismatchIssue {
  const StyioAssignmentTypeMismatchIssue({
    required this.diagnostic,
    required this.variableName,
    required this.expectedTypeName,
    required this.actualTypeName,
    required this.assignmentRange,
    required this.typeRange,
    required this.replacementAssignmentText,
    required this.initializerRange,
    required this.initializerActualTypeName,
    required this.replacementInitializerTextForActualType,
  });

  final Diagnostic diagnostic;
  final String variableName;
  final String expectedTypeName;
  final String actualTypeName;
  final SourceRange assignmentRange;
  final SourceRange typeRange;
  final String replacementAssignmentText;
  final SourceRange? initializerRange;
  final String initializerActualTypeName;
  final String replacementInitializerTextForActualType;

  bool get canChangeDeclaredType =>
      initializerActualTypeName.isEmpty ||
      initializerActualTypeName == actualTypeName ||
      replacementInitializerTextForActualType.isNotEmpty;
}

class StyioConditionTypeMismatchIssue {
  const StyioConditionTypeMismatchIssue({
    required this.diagnostic,
    required this.expectedTypeName,
    required this.actualTypeName,
    required this.conditionRange,
    required this.replacementConditionText,
  });

  final Diagnostic diagnostic;
  final String expectedTypeName;
  final String actualTypeName;
  final SourceRange conditionRange;
  final String replacementConditionText;
}

class StyioBinaryOperatorTypeIssue {
  const StyioBinaryOperatorTypeIssue({
    required this.diagnostic,
    required this.operatorLexeme,
    required this.leftTypeName,
    required this.rightTypeName,
    required this.operatorRange,
    required this.leftOperandRange,
    required this.rightOperandRange,
  });

  final Diagnostic diagnostic;
  final String operatorLexeme;
  final String leftTypeName;
  final String rightTypeName;
  final SourceRange operatorRange;
  final SourceRange leftOperandRange;
  final SourceRange rightOperandRange;
}

class StyioUnaryOperatorTypeIssue {
  const StyioUnaryOperatorTypeIssue({
    required this.diagnostic,
    required this.operatorLexeme,
    required this.operandTypeName,
    required this.operatorRange,
    required this.operandRange,
  });

  final Diagnostic diagnostic;
  final String operatorLexeme;
  final String operandTypeName;
  final SourceRange operatorRange;
  final SourceRange operandRange;
}

class StyioFunctionReturnTypeIssue {
  const StyioFunctionReturnTypeIssue({
    required this.diagnostic,
    required this.functionName,
    required this.expectedTypeName,
    required this.actualTypeName,
    required this.returnExpressionRange,
    required this.returnTypeRange,
    required this.replacementReturnExpressionText,
  });

  final Diagnostic diagnostic;
  final String functionName;
  final String expectedTypeName;
  final String actualTypeName;
  final SourceRange returnExpressionRange;
  final SourceRange returnTypeRange;
  final String replacementReturnExpressionText;
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

class AddArgumentNamesPlan {
  const AddArgumentNamesPlan({
    required this.callableName,
    required this.invocationRange,
    required this.edits,
  });

  final String callableName;
  final SourceRange invocationRange;
  final List<FormattingEdit> edits;
}

class AddArgumentNamePlan {
  const AddArgumentNamePlan({
    required this.callableName,
    required this.parameterName,
    required this.argumentRange,
    required this.invocationRange,
    required this.edit,
  });

  final String callableName;
  final String parameterName;
  final SourceRange argumentRange;
  final SourceRange invocationRange;
  final FormattingEdit edit;
}

class RemoveArgumentNamesPlan {
  const RemoveArgumentNamesPlan({
    required this.callableName,
    required this.invocationRange,
    required this.edits,
  });

  final String callableName;
  final SourceRange invocationRange;
  final List<FormattingEdit> edits;
}

class RemoveArgumentNamePlan {
  const RemoveArgumentNamePlan({
    required this.callableName,
    required this.parameterName,
    required this.argumentRange,
    required this.invocationRange,
    required this.edit,
  });

  final String callableName;
  final String parameterName;
  final SourceRange argumentRange;
  final SourceRange invocationRange;
  final FormattingEdit edit;
}

class SpecifyTypeExplicitlyPlan {
  const SpecifyTypeExplicitlyPlan({
    required this.variableName,
    required this.typeName,
    required this.nameRange,
    required this.edit,
  });

  final String variableName;
  final String typeName;
  final SourceRange nameRange;
  final FormattingEdit edit;
}

class RemoveExplicitTypePlan {
  const RemoveExplicitTypePlan({
    required this.variableName,
    required this.typeName,
    required this.typeRange,
    required this.edit,
  });

  final String variableName;
  final String typeName;
  final SourceRange typeRange;
  final FormattingEdit edit;
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
