import '../editor/document_state.dart';
import 'language_contract.dart';
import 'styio_language_service.dart';
import 'styio_syntax_highlighter.dart';
import 'styio_symbol_index.dart';

class SimpleStyioLanguageService implements StyioLanguageService {
  const SimpleStyioLanguageService({
    StyioSyntaxHighlighter syntaxHighlighter = const StyioSyntaxHighlighter(),
    StyioSymbolIndex symbolIndex = const StyioSymbolIndex(),
  }) : _syntaxHighlighter = syntaxHighlighter,
       _symbolIndex = symbolIndex;

  static const Set<String> _implicitIdentifierAllowlist = {
    'condition',
    'normalize',
    'sink',
    'source',
    'value',
  };

  final StyioSyntaxHighlighter _syntaxHighlighter;
  final StyioSymbolIndex _symbolIndex;

  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    final tokenSpans = _syntaxHighlighter.tokenize(document.text);
    final semanticSpans = _syntaxHighlighter.resolveSemanticSpans(tokenSpans);
    final symbolSnapshot = _symbolIndex.build(tokenSpans);
    final diagnostics = _lintDocument(tokenSpans, symbolSnapshot);
    final formattingEdits = formatDocument(document);
    final semanticBlocks = _syntaxHighlighter.resolveSemanticBlocks(tokenSpans);

    return StyioDocumentAnalysis(
      tokenSpans: tokenSpans,
      semanticSpans: semanticSpans,
      diagnostics: diagnostics,
      formattingEdits: formattingEdits,
      semanticBlocks: semanticBlocks,
      documentSymbols: symbolSnapshot.symbols,
      referenceSpans: symbolSnapshot.references,
    );
  }

  @override
  List<FormattingEdit> formatDocument(DocumentState document) {
    final original = document.text;
    final normalizedLines = original
        .split('\n')
        .map((line) => line.replaceFirst(RegExp(r'\s+$'), ''))
        .toList(growable: false);
    final normalized = normalizedLines.join('\n');

    if (normalized == original) {
      return const <FormattingEdit>[];
    }

    return [
      FormattingEdit(
        range: SourceRange(start: 0, end: original.length),
        newText: normalized,
      ),
    ];
  }

  @override
  List<CompletionItem> completeAt(DocumentState document, int offset) {
    final tokenSpans = _syntaxHighlighter.tokenize(document.text);
    final token = _tokenAroundOffset(tokenSpans, offset);
    final seed = token?.lexeme ?? '';
    final symbolSnapshot = _symbolIndex.build(tokenSpans);

    final staticItems = <CompletionItem>[
      const CompletionItem(
        label: '@import',
        kind: CompletionItemKind.snippet,
        insertText: '@import { styio/core }',
        detail: 'Declare a top-level Styio import.',
      ),
      const CompletionItem(
        label: '#function',
        kind: CompletionItemKind.snippet,
        insertText: '#main := () => {\n  <| 0\n}',
        detail: 'Declare a Styio function using the current hash form.',
      ),
      const CompletionItem(
        label: '@resource',
        kind: CompletionItemKind.snippet,
        insertText:
            '@prices : f64|..10| := {\n  @file("prices.txt") >> #(p) => {\n    p -> @prices\n  }\n}',
        detail: 'Declare a target resource topology surface.',
      ),
      const CompletionItem(
        label: '@stdout',
        kind: CompletionItemKind.variable,
        insertText: '@stdout',
        detail: 'Standard output resource sink.',
      ),
      const CompletionItem(
        label: '@stdin',
        kind: CompletionItemKind.variable,
        insertText: '@stdin',
        detail: 'Standard input resource source.',
      ),
      const CompletionItem(
        label: 'task',
        kind: CompletionItemKind.snippet,
        insertText: '||> {\n  <| value\n}',
        detail: 'Launch a Styio task block.',
      ),
      const CompletionItem(
        label: 'await',
        kind: CompletionItemKind.snippet,
        insertText: '?| task -> value: i64',
        detail: 'Await a task result into a typed binding.',
      ),
      const CompletionItem(
        label: 'fn',
        kind: CompletionItemKind.keyword,
        insertText: 'fn ',
        detail: 'Declare a function.',
      ),
      const CompletionItem(
        label: 'pipeline',
        kind: CompletionItemKind.keyword,
        insertText: 'pipeline ',
        detail: 'Declare a pipeline.',
      ),
      const CompletionItem(
        label: 'state',
        kind: CompletionItemKind.keyword,
        insertText: 'state ',
        detail: 'Declare a state.',
      ),
      const CompletionItem(
        label: 'emit',
        kind: CompletionItemKind.keyword,
        insertText: 'emit ',
        detail: 'Emit a value.',
      ),
      const CompletionItem(
        label: 'when',
        kind: CompletionItemKind.snippet,
        insertText: 'when condition -> state next_state',
        detail: 'State transition snippet.',
      ),
    ];
    final items = _dedupeCompletionItems([
      ...staticItems,
      ...symbolSnapshot.symbols.map(_completionItemForSymbol),
    ]);

    if (seed.isEmpty || token == null || token.kind == TokenKind.keyword) {
      return items;
    }

    return items
        .where((item) => _matchesCompletionSeed(item, seed))
        .toList(growable: false);
  }

  @override
  List<SurroundTemplate> surroundTemplatesAt(
    DocumentState document,
    SourceRange range,
  ) {
    final normalizedStart = range.start.clamp(0, document.length);
    final normalizedEnd = range.end.clamp(normalizedStart, document.length);
    final selectedText = document.text.substring(
      normalizedStart,
      normalizedEnd,
    );
    if (selectedText.trim().isEmpty) {
      return const <SurroundTemplate>[];
    }

    return const <SurroundTemplate>[
      SurroundTemplate(
        id: 'styio.task-block',
        label: 'task block',
        openingLine: '||> {',
        closingLine: '}',
        detail: 'Surround selected Styio statements with a task block.',
      ),
      SurroundTemplate(
        id: 'styio.function-literal',
        label: 'function literal',
        openingLine: '#() => {',
        closingLine: '}',
        detail: 'Wrap selected statements in a Styio function literal.',
      ),
    ];
  }

  @override
  HoverPayload? hoverAt(DocumentState document, int offset) {
    final token = _syntaxHighlighter.tokenAt(document.text, offset);
    if (token == null) {
      return null;
    }

    if (token.kind == TokenKind.keyword) {
      return HoverPayload(
        range: token.range,
        markdown: 'Keyword `${token.lexeme}` in Styio source.',
      );
    }

    final operatorHover = _syntaxHighlighter.hoverForOperator(token.lexeme);
    if (operatorHover != null) {
      return HoverPayload(range: token.range, markdown: operatorHover);
    }
    if (_syntaxHighlighter.isOperatorLexeme(token.lexeme)) {
      return HoverPayload(
        range: token.range,
        markdown: 'Operator `${token.lexeme}` in Styio source.',
      );
    }

    if (token.kind == TokenKind.identifier) {
      if (_syntaxHighlighter.isTypeName(token.lexeme)) {
        return HoverPayload(
          range: token.range,
          markdown:
              'Type `${token.lexeme}` from the current Styio target syntax.',
        );
      }
      if (_syntaxHighlighter.isStandardResource(token.lexeme)) {
        return HoverPayload(
          range: token.range,
          markdown:
              'Resource identifier `${token.lexeme}`. Prefix it with `@` when using it as a Styio resource.',
        );
      }
      return HoverPayload(
        range: token.range,
        markdown: 'Identifier `${token.lexeme}`.',
      );
    }

    return null;
  }

  @override
  DefinitionTarget? definitionAt(DocumentState document, int offset) {
    return _symbolIndex.definitionAt(document.text, offset);
  }

  @override
  List<ReferenceSpan> referencesAt(DocumentState document, int offset) {
    return _symbolIndex.referencesAt(document.text, offset);
  }

  @override
  RenamePlan? renameAt(DocumentState document, int offset, String newName) {
    return _symbolIndex.renameAt(document.text, offset, newName);
  }

  @override
  SafeDeletePlan? safeDeleteAt(DocumentState document, int offset) {
    return _symbolIndex.safeDeleteAt(document.text, offset);
  }

  @override
  InlineVariablePlan? inlineVariableAt(DocumentState document, int offset) {
    return _symbolIndex.inlineVariableAt(document.text, offset);
  }

  @override
  IntroduceVariablePlan? introduceVariable(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    return _symbolIndex.introduceVariable(document.text, range, name);
  }

  @override
  ExtractFunctionPlan? extractFunction(
    DocumentState document,
    SourceRange range,
    String name,
  ) {
    return _symbolIndex.extractFunction(document.text, range, name);
  }

  @override
  ChangeSignaturePlan? changeSignatureAt(
    DocumentState document,
    int offset, {
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  }) {
    return _symbolIndex.changeSignature(
      document.text,
      offset,
      newName: newName,
      parameters: parameters,
    );
  }

  @override
  ParameterInfoPayload? parameterInfoAt(DocumentState document, int offset) {
    return _symbolIndex.parameterInfoAt(document.text, offset);
  }

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    switch (diagnostic.code) {
      case 'missing-assignment':
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
                range: SourceRange(
                  start: insertionOffset,
                  end: insertionOffset,
                ),
                newText: ' = value',
              ),
            ],
          ),
        ];
      case 'unexpected-closing-brace':
        return [
          DiagnosticQuickFix(
            label: 'Remove stray brace',
            detail: 'Delete the unmatched closing brace.',
            edits: [FormattingEdit(range: diagnostic.range, newText: '')],
          ),
        ];
      case 'unclosed-block':
        final suffix = document.text.endsWith('\n') ? '}' : '\n}';
        return [
          DiagnosticQuickFix(
            label: 'Append closing brace',
            detail: 'Insert a matching `}` at the end of the document.',
            edits: [
              FormattingEdit(
                range: SourceRange(
                  start: document.length,
                  end: document.length,
                ),
                newText: suffix,
              ),
            ],
          ),
        ];
      case 'unused-local-symbol':
        return [
          DiagnosticQuickFix(
            label: 'Remove unused declaration',
            detail: 'Delete the unused local binding line.',
            edits: [
              FormattingEdit(
                range: _lineRemovalRange(document.text, diagnostic.range),
                newText: '',
              ),
            ],
          ),
        ];
    }

    return const <DiagnosticQuickFix>[];
  }

  List<Diagnostic> _lintDocument(
    List<TokenSpan> tokens,
    StyioSymbolSnapshot symbolSnapshot,
  ) {
    final diagnostics = <Diagnostic>[];
    final blockStack = <TokenSpan>[];

    for (final token in tokens) {
      if (token.kind != TokenKind.punctuation) {
        continue;
      }

      if (token.lexeme == '{') {
        blockStack.add(token);
      } else if (token.lexeme == '}') {
        if (blockStack.isEmpty) {
          diagnostics.add(
            Diagnostic(
              severity: DiagnosticSeverity.error,
              code: 'unexpected-closing-brace',
              message: 'Closing brace has no matching opening brace.',
              range: token.range,
            ),
          );
        } else {
          blockStack.removeLast();
        }
      }
    }

    for (final unclosed in blockStack) {
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'unclosed-block',
          message: 'Opening brace is missing a closing brace.',
          range: unclosed.range,
        ),
      );
    }

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.keyword && token.lexeme == 'let') {
        final lineRange = _lineRangeForToken(tokens, index);
        if (!_lineHasLexeme(tokens, lineRange, '=')) {
          diagnostics.add(
            Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'missing-assignment',
              message: 'Variable declaration is missing `=`.',
              range: SourceRange(start: lineRange.start, end: lineRange.end),
            ),
          );
        }
      }
    }

    for (final symbol in symbolSnapshot.symbols) {
      if (!_shouldReportUnusedLocalSymbol(tokens, symbol) ||
          _diagnosticsIntersectRange(diagnostics, symbol.declarationRange)) {
        continue;
      }
      final references = symbolSnapshot.referencesForTarget(symbol.nameRange);
      if (references.any((reference) => !reference.isDeclaration)) {
        continue;
      }
      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'unused-local-symbol',
          message: 'Local symbol `${symbol.name}` is never used.',
          range: symbol.declarationRange,
        ),
      );
    }

    final resolvedRanges = {
      for (final reference in symbolSnapshot.references)
        '${reference.range.start}:${reference.range.end}',
    };
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind != TokenKind.identifier ||
          resolvedRanges.contains('${token.range.start}:${token.range.end}') ||
          _shouldIgnoreUnresolvedCandidate(tokens, index)) {
        continue;
      }

      diagnostics.add(
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'unresolved-reference',
          message: 'Identifier is not resolved by the current symbol index.',
          range: token.range,
        ),
      );
    }

    return diagnostics;
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

  bool _shouldReportUnusedLocalSymbol(
    List<TokenSpan> tokens,
    DocumentSymbol symbol,
  ) {
    if (symbol.kind != SymbolKind.variable || symbol.name.startsWith('_')) {
      return false;
    }

    final nameIndex = tokens.indexWhere(
      (token) =>
          token.range.start == symbol.nameRange.start &&
          token.range.end == symbol.nameRange.end,
    );
    if (nameIndex < 0) {
      return false;
    }
    final previous = _previousSignificant(tokens, nameIndex - 1);
    return previous?.lexeme != 'let';
  }

  bool _diagnosticsIntersectRange(
    List<Diagnostic> diagnostics,
    SourceRange range,
  ) {
    return diagnostics.any((diagnostic) => diagnostic.range.intersects(range));
  }

  SourceRange _lineRangeForToken(List<TokenSpan> tokens, int tokenIndex) {
    var start = tokens[tokenIndex].range.start;
    var end = tokens[tokenIndex].range.end;

    for (var index = tokenIndex - 1; index >= 0; index -= 1) {
      final token = tokens[index];
      if (token.lexeme.contains('\n')) {
        start = token.range.end;
        break;
      }
      start = token.range.start;
    }

    for (var index = tokenIndex + 1; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.lexeme.contains('\n')) {
        end = token.range.start;
        break;
      }
      end = token.range.end;
    }

    return SourceRange(start: start, end: end);
  }

  bool _lineHasLexeme(
    List<TokenSpan> tokens,
    SourceRange lineRange,
    String lexeme,
  ) {
    return tokens.any(
      (token) => token.range.intersects(lineRange) && token.lexeme == lexeme,
    );
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
    if (previous?.lexeme == '.' || next?.lexeme == ':') {
      return true;
    }
    return false;
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

  List<CompletionItem> _dedupeCompletionItems(Iterable<CompletionItem> items) {
    final deduped = <CompletionItem>[];
    final seen = <String>{};
    for (final item in items) {
      final signature = '${item.label}:${item.insertText}';
      if (seen.add(signature)) {
        deduped.add(item);
      }
    }
    return deduped;
  }

  bool _matchesCompletionSeed(CompletionItem item, String rawSeed) {
    final seed = rawSeed.toLowerCase();
    if (seed.isEmpty) {
      return true;
    }
    return _matchesCompletionText(item.label, seed) ||
        _matchesCompletionText(item.insertText, seed);
  }

  bool _matchesCompletionText(String text, String seed) {
    final searchable = text.toLowerCase();
    if (searchable.startsWith(seed) || searchable.contains(seed)) {
      return true;
    }
    return _completionInitials(text).startsWith(seed);
  }

  String _completionInitials(String text) {
    final buffer = StringBuffer();
    var wordBoundary = true;
    var previousLowerOrDigit = false;
    for (var index = 0; index < text.length; index += 1) {
      final code = text.codeUnitAt(index);
      final isUpper = code >= 0x41 && code <= 0x5A;
      final isLower = code >= 0x61 && code <= 0x7A;
      final isDigit = code >= 0x30 && code <= 0x39;
      final isAsciiWord = isUpper || isLower || isDigit || code == 0x5F;
      if (!isAsciiWord || code == 0x5F) {
        wordBoundary = true;
        previousLowerOrDigit = false;
        continue;
      }
      if (wordBoundary || (isUpper && previousLowerOrDigit)) {
        buffer.writeCharCode(isUpper ? code + 0x20 : code);
      }
      wordBoundary = false;
      previousLowerOrDigit = isLower || isDigit;
    }
    return buffer.toString();
  }

  CompletionItem _completionItemForSymbol(DocumentSymbol symbol) {
    return CompletionItem(
      label: symbol.name,
      kind: switch (symbol.kind) {
        SymbolKind.function => CompletionItemKind.function,
        SymbolKind.pipeline ||
        SymbolKind.state ||
        SymbolKind.resource ||
        SymbolKind.variable ||
        SymbolKind.parameter ||
        SymbolKind.task => CompletionItemKind.variable,
      },
      insertText: symbol.name,
      detail: 'Current file ${symbol.kind.name} symbol.',
    );
  }
}
