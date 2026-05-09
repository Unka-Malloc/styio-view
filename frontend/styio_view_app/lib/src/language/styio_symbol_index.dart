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

    final definition = definitionAt(source, offset);
    if (definition == null) {
      return null;
    }

    final references = referencesAt(source, offset);
    if (references.isEmpty) {
      return null;
    }

    return RenamePlan(
      target: definition.symbol,
      newName: newName,
      references: references,
      edits: references
          .map(
            (reference) =>
                FormattingEdit(range: reference.range, newText: newName),
          )
          .toList(growable: false),
    );
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
    for (final token in tokens) {
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
        ),
      );
    }
    return references;
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
    for (var index = startIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      if (token.kind == TokenKind.identifier) {
        return token;
      }
      return null;
    }
    return null;
  }

  TokenSpan? _nextSignificant(List<TokenSpan> tokens, int startIndex) {
    for (var index = startIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      return token;
    }
    return null;
  }

  TokenSpan? _previousSignificant(List<TokenSpan> tokens, int startIndex) {
    for (var index = startIndex; index >= 0; index -= 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      return token;
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

  bool _isValidIdentifier(String value) {
    if (value.isEmpty || _syntaxHighlighter.isTypeName(value)) {
      return false;
    }
    final identifierPattern = RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$');
    return identifierPattern.hasMatch(value);
  }
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
