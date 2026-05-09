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
    );
  }

  Map<String, List<_FunctionSignature>> _collectFunctionSignatures(
    List<TokenSpan> tokens,
  ) {
    final signaturesByName = <String, List<_FunctionSignature>>{};

    void addSignature({
      required TokenSpan nameToken,
      required int openingIndex,
      required String prefix,
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
      final signature = _FunctionSignature(
        name: nameToken.lexeme,
        nameRange: nameToken.range,
        parameters: parameters,
        displayText:
            '${prefix == '#' ? '#' : '$prefix '}${nameToken.lexeme}'
            '(${parameters.map((parameter) => parameter.displayText).join(', ')})',
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
        final openingIndex = _nextSignificantIndex(tokens, nameIndex + 1);
        if (openingIndex == null || tokens[openingIndex].lexeme != '(') {
          continue;
        }
        addSignature(
          nameToken: tokens[nameIndex],
          openingIndex: openingIndex,
          prefix: 'fn',
        );
        continue;
      }

      if (token.lexeme == '#') {
        final nameIndex = _nextIdentifierIndex(tokens, index + 1);
        if (nameIndex == null) {
          continue;
        }
        final openingIndex = _nextSignificantIndex(tokens, nameIndex + 1);
        if (openingIndex == null || tokens[openingIndex].lexeme != '(') {
          continue;
        }
        addSignature(
          nameToken: tokens[nameIndex],
          openingIndex: openingIndex,
          prefix: '#',
        );
      }
    }

    return signaturesByName;
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
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.lexeme != '(') {
        continue;
      }
      final closingIndex = _matchingParenthesisIndex(tokens, index);
      if (closingIndex == null) {
        continue;
      }
      final closingToken = tokens[closingIndex];
      if (offset < token.range.start || offset > closingToken.range.end) {
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

      final candidate = _CallArgumentList(
        callable: tokens[callableIndex],
        openingIndex: index,
        closingIndex: closingIndex,
      );
      if (best == null ||
          tokens[candidate.openingIndex].range.start >
              tokens[best.openingIndex].range.start) {
        best = candidate;
      }
    }
    return best;
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
    for (var index = startIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      if (token.lexeme == '(') {
        _addParametersInDelimitedList(
          tokens: tokens,
          openingIndex: index,
          addSymbol: addSymbol,
        );
      }
      return;
    }
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
    required this.parameters,
    required this.displayText,
  });

  final String name;
  final SourceRange nameRange;
  final List<ParameterInfoParameter> parameters;
  final String displayText;
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

class _InlineVariableInitializer {
  const _InlineVariableInitializer({required this.range, required this.text});

  final SourceRange range;
  final String text;
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
