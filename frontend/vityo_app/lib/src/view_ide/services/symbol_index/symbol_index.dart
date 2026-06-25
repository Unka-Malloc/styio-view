import '../../language/contract/language_contract.dart';
import '../../language/semantic/styio_symbol_index.dart' as semantic;
import '../../language/syntax/styio_syntax_highlighter.dart';

class SymbolIndexDocument {
  const SymbolIndexDocument({required this.path, required this.source});

  final String path;
  final String source;
}

class IndexedSymbol {
  const IndexedSymbol({
    required this.id,
    required this.filePath,
    required this.symbol,
  });

  final String id;
  final String filePath;
  final DocumentSymbol symbol;

  String get name => symbol.name;

  SymbolKind get kind => symbol.kind;
}

class IndexedReference {
  const IndexedReference({
    required this.symbolId,
    required this.filePath,
    required this.reference,
  });

  final String symbolId;
  final String filePath;
  final ReferenceSpan reference;

  String get name => reference.name;

  SourceRange get range => reference.range;

  bool get isDeclaration => reference.isDeclaration;

  ReferenceAccess get access => reference.access;
}

class SymbolIndexSnapshot {
  const SymbolIndexSnapshot({
    required this.symbols,
    required this.references,
  });

  final List<IndexedSymbol> symbols;
  final List<IndexedReference> references;

  List<IndexedSymbol> queryPrefix(
    String prefix, {
    bool caseSensitive = false,
    int? limit,
  }) {
    final normalizedPrefix = caseSensitive ? prefix : prefix.toLowerCase();
    final matches = symbols.where((symbol) {
      final name = caseSensitive ? symbol.name : symbol.name.toLowerCase();
      return name.startsWith(normalizedPrefix);
    }).toList()
      ..sort(_compareSymbols);
    if (limit == null || matches.length <= limit) {
      return matches;
    }
    return matches.take(limit).toList(growable: false);
  }

  List<IndexedReference> referencesForSymbol(String symbolId) {
    return references
        .where((reference) => reference.symbolId == symbolId)
        .toList(growable: false)
      ..sort(_compareReferences);
  }

  List<IndexedReference> referencesForName(String name) {
    return references
        .where((reference) => reference.name == name)
        .toList(growable: false)
      ..sort(_compareReferences);
  }

  IndexedSymbol? symbolById(String symbolId) {
    for (final symbol in symbols) {
      if (symbol.id == symbolId) {
        return symbol;
      }
    }
    return null;
  }

  IndexedSymbol? symbolAt({
    required String filePath,
    required int offset,
  }) {
    for (final symbol in symbols) {
      if (symbol.filePath == filePath && symbol.symbol.nameRange.contains(offset)) {
        return symbol;
      }
    }
    return null;
  }
}

class SymbolIndex {
  const SymbolIndex({
    StyioSyntaxHighlighter syntaxHighlighter = const StyioSyntaxHighlighter(),
    semantic.StyioSymbolIndex documentIndex =
        const semantic.StyioSymbolIndex(),
  })  : _syntaxHighlighter = syntaxHighlighter,
        _documentIndex = documentIndex;

  final StyioSyntaxHighlighter _syntaxHighlighter;
  final semantic.StyioSymbolIndex _documentIndex;

  SymbolIndexSnapshot build(Iterable<SymbolIndexDocument> documents) {
    final sortedDocuments = documents.toList()
      ..sort((left, right) => left.path.compareTo(right.path));
    final symbols = <IndexedSymbol>[];
    final references = <IndexedReference>[];
    final symbolsByName = <String, List<IndexedSymbol>>{};
    final localReferenceKeysByFile = <String, Set<String>>{};
    final tokensByFile = <String, List<TokenSpan>>{};

    for (final document in sortedDocuments) {
      final tokens = _syntaxHighlighter.tokenize(document.source);
      tokensByFile[document.path] = tokens;
      final snapshot = _documentIndex.build(tokens);
      final symbolByTarget = <String, IndexedSymbol>{};

      for (final symbol in snapshot.symbols) {
        final indexedSymbol = IndexedSymbol(
          id: _symbolId(document.path, symbol),
          filePath: document.path,
          symbol: symbol,
        );
        symbols.add(indexedSymbol);
        symbolsByName
            .putIfAbsent(symbol.name, () => <IndexedSymbol>[])
            .add(indexedSymbol);
        symbolByTarget[_rangeKey(symbol.nameRange)] = indexedSymbol;
      }

      final localKeys = <String>{};
      for (final reference in snapshot.references) {
        final targetSymbol = symbolByTarget[_rangeKey(reference.targetRange)];
        if (targetSymbol == null) {
          continue;
        }
        references.add(
          IndexedReference(
            symbolId: targetSymbol.id,
            filePath: document.path,
            reference: reference,
          ),
        );
        localKeys.add(_referenceKey(reference.range));
      }
      localReferenceKeysByFile[document.path] = localKeys;
    }

    final uniqueSymbolByName = <String, IndexedSymbol>{};
    for (final entry in symbolsByName.entries) {
      if (entry.value.length == 1) {
        uniqueSymbolByName[entry.key] = entry.value.single;
      }
    }

    for (final document in sortedDocuments) {
      final tokens = tokensByFile[document.path] ?? const <TokenSpan>[];
      final localKeys = localReferenceKeysByFile[document.path] ?? const <String>{};
      for (final token in tokens) {
        if (token.kind != TokenKind.identifier) {
          continue;
        }
        if (localKeys.contains(_referenceKey(token.range)) ||
            _syntaxHighlighter.isKeyword(token.lexeme) ||
            _syntaxHighlighter.isTypeName(token.lexeme) ||
            _syntaxHighlighter.isStandardResource(token.lexeme)) {
          continue;
        }
        final target = uniqueSymbolByName[token.lexeme];
        if (target == null) {
          continue;
        }
        references.add(
          IndexedReference(
            symbolId: target.id,
            filePath: document.path,
            reference: ReferenceSpan(
              name: target.name,
              kind: target.kind,
              range: token.range,
              targetRange: target.symbol.nameRange,
              isDeclaration: false,
              access: ReferenceAccess.read,
            ),
          ),
        );
      }
    }

    symbols.sort(_compareSymbols);
    references.sort(_compareReferences);
    return SymbolIndexSnapshot(
      symbols: List<IndexedSymbol>.unmodifiable(symbols),
      references: List<IndexedReference>.unmodifiable(references),
    );
  }

  static String _symbolId(String filePath, DocumentSymbol symbol) {
    return [
      filePath,
      symbol.name,
      symbol.kind.name,
      symbol.nameRange.start,
      symbol.nameRange.end,
    ].join(':');
  }

  static String _rangeKey(SourceRange range) => '${range.start}:${range.end}';

  static String _referenceKey(SourceRange range) => _rangeKey(range);
}

int _compareSymbols(IndexedSymbol left, IndexedSymbol right) {
  final nameCompare = left.name.toLowerCase().compareTo(right.name.toLowerCase());
  if (nameCompare != 0) {
    return nameCompare;
  }
  final pathCompare = left.filePath.compareTo(right.filePath);
  if (pathCompare != 0) {
    return pathCompare;
  }
  return left.symbol.nameRange.start.compareTo(right.symbol.nameRange.start);
}

int _compareReferences(IndexedReference left, IndexedReference right) {
  final symbolCompare = left.symbolId.compareTo(right.symbolId);
  if (symbolCompare != 0) {
    return symbolCompare;
  }
  final pathCompare = left.filePath.compareTo(right.filePath);
  if (pathCompare != 0) {
    return pathCompare;
  }
  return left.range.start.compareTo(right.range.start);
}

