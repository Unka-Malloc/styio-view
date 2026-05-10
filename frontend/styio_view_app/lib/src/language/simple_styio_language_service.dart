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
    final diagnostics = _lintDocument(
      document.text,
      tokenSpans,
      symbolSnapshot,
    );
    final formattingEdits = formatDocument(document);
    final semanticBlocks = _syntaxHighlighter.resolveSemanticBlocks(tokenSpans);

    return StyioDocumentAnalysis(
      tokenSpans: tokenSpans,
      semanticSpans: semanticSpans,
      diagnostics: diagnostics,
      formattingEdits: formattingEdits,
      semanticBlocks: semanticBlocks,
      inlayHints: _symbolIndex.inlayHints(document.text),
      documentSymbols: symbolSnapshot.symbols,
      referenceSpans: symbolSnapshot.references,
    );
  }

  @override
  List<InlayHint> inlayHints(DocumentState document) {
    return _symbolIndex.inlayHints(document.text);
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
    final token = _completionSeedToken(tokenSpans, offset);
    final seed = token?.lexeme ?? '';
    final symbolSnapshot = _symbolIndex.build(tokenSpans);
    final postfixItems = _postfixCompletionItems(
      document.text,
      offset,
      tokenSpans,
    );
    final namedArgumentItems = _symbolIndex.namedArgumentCompletionsAt(
      document.text,
      offset,
    );

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
      ...postfixItems,
      ...namedArgumentItems,
      ...staticItems,
      ...symbolSnapshot.symbols.map(_completionItemForSymbol),
    ]);

    if (seed.isEmpty ||
        token == null ||
        (token.kind == TokenKind.keyword && postfixItems.isEmpty)) {
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
      final symbolHover = _symbolHoverPayload(document, offset, token);
      if (symbolHover != null) {
        return symbolHover;
      }
      return HoverPayload(
        range: token.range,
        markdown: 'Identifier `${token.lexeme}`.',
      );
    }

    return null;
  }

  HoverPayload? _symbolHoverPayload(
    DocumentState document,
    int offset,
    TokenSpan token,
  ) {
    final definition = _symbolIndex.definitionAt(document.text, offset);
    if (definition == null) {
      return null;
    }

    final symbol = definition.symbol;
    final references = _symbolIndex.referencesAt(document.text, offset);
    final position = document.positionForOffset(symbol.nameRange.start);
    final usageLabel =
        '${references.length} current-file usage'
        '${references.length == 1 ? '' : 's'}';
    final detail = symbol.detail.isEmpty ? '' : ' ${symbol.detail}.';
    final documentation = symbol.documentation.isEmpty
        ? ''
        : '\n\n${symbol.documentation}';

    return HoverPayload(
      range: token.range,
      markdown:
          'Styio ${symbol.kind.name} `${symbol.name}`.$documentation$detail '
          'Declared at ${position.line + 1}:${position.column + 1}. '
          '$usageLabel.',
    );
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
  List<DiagnosticQuickFix> intentionsAt(DocumentState document, int offset) {
    final intentions = <DiagnosticQuickFix>[];
    final addNamesPlan = _symbolIndex.addArgumentNamesAt(document.text, offset);
    if (addNamesPlan != null && addNamesPlan.edits.isNotEmpty) {
      intentions.add(
        DiagnosticQuickFix(
          label: 'Add argument names',
          detail:
              'Name positional arguments in `${addNamesPlan.callableName}` '
              'using the current signature.',
          edits: addNamesPlan.edits,
        ),
      );
    }

    final addNamePlan = _symbolIndex.addArgumentNameAt(document.text, offset);
    if (addNamePlan != null) {
      intentions.add(
        DiagnosticQuickFix(
          label: 'Add ${addNamePlan.parameterName}: to argument',
          detail:
              'Name the current `${addNamePlan.callableName}` argument without '
              'rewriting the rest of the call.',
          edits: [addNamePlan.edit],
        ),
      );
    }

    final removeNamesPlan = _symbolIndex.removeArgumentNamesAt(
      document.text,
      offset,
    );
    if (removeNamesPlan != null && removeNamesPlan.edits.isNotEmpty) {
      intentions.add(
        DiagnosticQuickFix(
          label: 'Remove all argument names',
          detail:
              'Use all named `${removeNamesPlan.callableName}` arguments '
              'positionally when the signature order is preserved.',
          edits: removeNamesPlan.edits,
        ),
      );
    }

    final removeNamePlan = _symbolIndex.removeArgumentNameAt(
      document.text,
      offset,
    );
    if (removeNamePlan != null) {
      intentions.add(
        DiagnosticQuickFix(
          label: 'Remove ${removeNamePlan.parameterName}: from argument',
          detail:
              'Use the current `${removeNamePlan.callableName}` argument '
              'positionally when it still maps to '
              '`${removeNamePlan.parameterName}`.',
          edits: [removeNamePlan.edit],
        ),
      );
    }

    final specifyTypePlan = _symbolIndex.specifyTypeExplicitlyAt(
      document.text,
      offset,
    );
    if (specifyTypePlan != null) {
      intentions.add(
        DiagnosticQuickFix(
          label: 'Specify type explicitly',
          detail:
              'Insert `${specifyTypePlan.typeName}` for local binding '
              '`${specifyTypePlan.variableName}`.',
          edits: [specifyTypePlan.edit],
        ),
      );
    }

    final removeTypePlan = _symbolIndex.removeExplicitTypeAt(
      document.text,
      offset,
    );
    if (removeTypePlan != null) {
      intentions.add(
        DiagnosticQuickFix(
          label: 'Remove explicit type',
          detail:
              'Remove `${removeTypePlan.typeName}` from local binding '
              '`${removeTypePlan.variableName}` when inference preserves it.',
          edits: [removeTypePlan.edit],
        ),
      );
    }

    final negateConditionFix = _negateWhenConditionAt(document, offset);
    if (negateConditionFix != null) {
      intentions.add(negateConditionFix);
    }

    final deMorganFix = _deMorganAt(document, offset);
    if (deMorganFix != null) {
      intentions.add(deMorganFix);
    }

    final flipComparisonFix = _flipComparisonAt(document, offset);
    if (flipComparisonFix != null) {
      intentions.add(flipComparisonFix);
    }

    return intentions;
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
      case 'unused-parameter':
        return _quickFixesForUnusedParameter(document, diagnostic);
      case 'unresolved-reference':
        return _quickFixesForUnresolvedReference(document, diagnostic);
      case 'duplicate-declaration':
        return _quickFixesForDuplicateDeclaration(document, diagnostic);
      case 'initializer-type-mismatch':
        return _quickFixesForTypeMismatchIssue(document, diagnostic);
      case 'assignment-type-mismatch':
        return _quickFixesForAssignmentTypeMismatchIssue(document, diagnostic);
      case 'binary-operator-type-mismatch':
        return _quickFixesForBinaryOperatorTypeIssue(document, diagnostic);
      case 'unary-operator-type-mismatch':
        return _quickFixesForUnaryOperatorTypeIssue(document, diagnostic);
      case 'condition-type-mismatch':
        return _quickFixesForConditionTypeMismatchIssue(document, diagnostic);
      case 'return-type-mismatch':
        return _quickFixesForFunctionReturnTypeIssue(document, diagnostic);
      case 'unknown-named-argument':
      case 'duplicate-named-argument':
      case 'missing-call-argument':
      case 'too-many-call-arguments':
      case 'argument-type-mismatch':
        return _quickFixesForCallArgumentIssue(document, diagnostic);
      case 'duplicate-import':
      case 'import-block-not-optimized':
        return _quickFixesForImportOptimization(document, diagnostic);
    }

    return const <DiagnosticQuickFix>[];
  }

  List<Diagnostic> _lintDocument(
    String source,
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

    diagnostics.addAll(
      _symbolIndex.callArgumentIssues(source).map((issue) => issue.diagnostic),
    );
    diagnostics.addAll(
      _symbolIndex
          .typedLocalInitializerIssues(source)
          .map((issue) => issue.diagnostic),
    );
    diagnostics.addAll(
      _symbolIndex
          .assignmentTypeMismatchIssues(source)
          .map((issue) => issue.diagnostic),
    );
    diagnostics.addAll(
      _symbolIndex
          .binaryOperatorTypeIssues(source)
          .map((issue) => issue.diagnostic),
    );
    diagnostics.addAll(
      _symbolIndex
          .unaryOperatorTypeIssues(source)
          .map((issue) => issue.diagnostic),
    );
    diagnostics.addAll(
      _symbolIndex
          .conditionTypeMismatchIssues(source)
          .map((issue) => issue.diagnostic),
    );
    diagnostics.addAll(
      _symbolIndex
          .functionReturnTypeIssues(source)
          .map((issue) => issue.diagnostic),
    );
    diagnostics.addAll(
      _symbolIndex
          .unusedParameterIssues(source)
          .map((issue) => issue.diagnostic),
    );
    diagnostics.addAll(
      _duplicateDeclarationDiagnostics(tokens, symbolSnapshot),
    );
    diagnostics.addAll(_importOptimizationDiagnostics(source));

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
          _hasDuplicateDeclaration(tokens, symbolSnapshot, symbol) ||
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

  List<Diagnostic> _duplicateDeclarationDiagnostics(
    List<TokenSpan> tokens,
    StyioSymbolSnapshot symbolSnapshot,
  ) {
    return [
      for (final duplicate in _duplicateDeclarationEntries(
        tokens,
        symbolSnapshot,
      ))
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'duplicate-declaration',
          message:
              'Name `${duplicate.symbol.name}` already has a current-file '
              '${duplicate.original.kind.name} declaration in this scope.',
          range: duplicate.symbol.nameRange,
        ),
    ];
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

  List<Diagnostic> _importOptimizationDiagnostics(String source) {
    final plan = _importOptimizationPlan(source);
    if (plan == null || !plan.needsOptimization) {
      return const <Diagnostic>[];
    }

    if (plan.duplicateImports.isNotEmpty) {
      return [
        for (final importLine in plan.duplicateImports)
          Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'duplicate-import',
            message: 'Import `${importLine.target}` is already declared.',
            range: importLine.lineContentRange,
          ),
      ];
    }

    return [
      Diagnostic(
        severity: DiagnosticSeverity.hint,
        code: 'import-block-not-optimized',
        message: 'Top-level Styio imports can be optimized.',
        range: SourceRange(
          start: plan.imports.first.lineContentRange.start,
          end: plan.imports.last.lineContentRange.end,
        ),
      ),
    ];
  }

  List<DiagnosticQuickFix> _quickFixesForImportOptimization(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
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

  List<DiagnosticQuickFix> _quickFixesForUnresolvedReference(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
    if (diagnostic.range.start < 0 ||
        diagnostic.range.end > document.length ||
        diagnostic.range.start >= diagnostic.range.end) {
      return const <DiagnosticQuickFix>[];
    }

    final name = document.text.substring(
      diagnostic.range.start,
      diagnostic.range.end,
    );
    if (!_isValidIdentifier(name)) {
      return const <DiagnosticQuickFix>[];
    }

    final tokens = _syntaxHighlighter.tokenize(document.text);
    final tokenIndex = _tokenIndexForRange(tokens, diagnostic.range);
    final fixes = <DiagnosticQuickFix>[];
    fixes.addAll(
      _changeToSimilarSymbolFixes(tokens, name: name, range: diagnostic.range),
    );
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

  List<DiagnosticQuickFix> _quickFixesForCallArgumentIssue(
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

  List<DiagnosticQuickFix> _quickFixesForTypeMismatchIssue(
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

  List<DiagnosticQuickFix> _quickFixesForAssignmentTypeMismatchIssue(
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

  List<DiagnosticQuickFix> _quickFixesForBinaryOperatorTypeIssue(
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

  List<DiagnosticQuickFix> _quickFixesForUnaryOperatorTypeIssue(
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

  List<DiagnosticQuickFix> _quickFixesForConditionTypeMismatchIssue(
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

  List<DiagnosticQuickFix> _quickFixesForFunctionReturnTypeIssue(
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
    fixes.add(
      DiagnosticQuickFix(
        label:
            'Change function `${issue.functionName}` return type to '
            '${issue.actualTypeName}',
        detail:
            'Update `${issue.functionName}` return type to match the returned '
            'expression.',
        edits: [
          FormattingEdit(
            range: issue.returnTypeRange,
            newText: issue.actualTypeName,
          ),
        ],
      ),
    );
    return fixes;
  }

  List<DiagnosticQuickFix> _quickFixesForUnusedParameter(
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

  List<DiagnosticQuickFix> _quickFixesForDuplicateDeclaration(
    DocumentState document,
    Diagnostic diagnostic,
  ) {
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
        label: 'Rename duplicate declaration to `$newName`',
        detail:
            'Rename the duplicate declaration and its current-file references.',
        edits: renamePlan.edits,
      ),
    ];
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

  bool _isValidIdentifier(String value) {
    if (value.isEmpty ||
        _syntaxHighlighter.isKeyword(value) ||
        _syntaxHighlighter.isTypeName(value)) {
      return false;
    }
    return RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value);
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

  List<_DuplicateDeclarationEntry> _duplicateDeclarationEntries(
    List<TokenSpan> tokens,
    StyioSymbolSnapshot symbolSnapshot,
  ) {
    final firstByKey = <String, DocumentSymbol>{};
    final duplicates = <_DuplicateDeclarationEntry>[];
    for (final symbol in symbolSnapshot.symbols) {
      final key = _duplicateDeclarationKey(tokens, symbol);
      final previous = firstByKey[key];
      if (previous == null) {
        firstByKey[key] = symbol;
        continue;
      }
      duplicates.add(
        _DuplicateDeclarationEntry(original: previous, symbol: symbol),
      );
    }
    return duplicates;
  }

  bool _hasDuplicateDeclaration(
    List<TokenSpan> tokens,
    StyioSymbolSnapshot symbolSnapshot,
    DocumentSymbol symbol,
  ) {
    final key = _duplicateDeclarationKey(tokens, symbol);
    var count = 0;
    for (final candidate in symbolSnapshot.symbols) {
      if (_duplicateDeclarationKey(tokens, candidate) == key) {
        count += 1;
      }
      if (count > 1) {
        return true;
      }
    }
    return false;
  }

  String _duplicateDeclarationKey(
    List<TokenSpan> tokens,
    DocumentSymbol symbol,
  ) {
    final scope = symbol.kind == SymbolKind.parameter
        ? _enclosingParenthesisStart(tokens, symbol.nameRange.start)
        : _enclosingBlockStart(tokens, symbol.nameRange.start);
    return '${symbol.name}\u0000$scope';
  }

  int _enclosingBlockStart(List<TokenSpan> tokens, int offset) {
    final stack = <int>[];
    for (final token in tokens) {
      if (token.range.start >= offset) {
        break;
      }
      if (token.kind != TokenKind.punctuation) {
        continue;
      }
      if (token.lexeme == '{') {
        stack.add(token.range.start);
      } else if (token.lexeme == '}' && stack.isNotEmpty) {
        stack.removeLast();
      }
    }
    return stack.isEmpty ? -1 : stack.last;
  }

  int _enclosingParenthesisStart(List<TokenSpan> tokens, int offset) {
    final stack = <int>[];
    for (final token in tokens) {
      if (token.range.start >= offset) {
        break;
      }
      if (token.kind != TokenKind.punctuation) {
        continue;
      }
      if (token.lexeme == '(') {
        stack.add(token.range.start);
      } else if (token.lexeme == ')' && stack.isNotEmpty) {
        stack.removeLast();
      }
    }
    return stack.isEmpty ? -1 : stack.last;
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

  bool _hasLineBreakBetween(
    List<TokenSpan> tokens,
    int startIndex,
    int endIndex,
  ) {
    final start = startIndex.clamp(0, tokens.length).toInt();
    final end = endIndex.clamp(start, tokens.length).toInt();
    for (var index = start; index < end; index += 1) {
      if (tokens[index].lexeme.contains('\n')) {
        return true;
      }
    }
    return false;
  }

  DiagnosticQuickFix? _deMorganAt(DocumentState document, int offset) {
    final source = document.text;
    final tokens = _syntaxHighlighter.tokenize(source);
    for (var index = 0; index < tokens.length; index += 1) {
      final notToken = tokens[index];
      if (notToken.lexeme != '!') {
        continue;
      }
      final openingIndex = _nextSignificantIndex(tokens, index + 1);
      if (openingIndex == null ||
          tokens[openingIndex].lexeme != '(' ||
          _hasLineBreakBetween(tokens, index + 1, openingIndex)) {
        continue;
      }
      final closingIndex = _matchingParenthesisIndex(tokens, openingIndex);
      if (closingIndex == null) {
        continue;
      }
      final expressionRange = SourceRange(
        start: notToken.range.start,
        end: tokens[closingIndex].range.end,
      );
      if (offset < expressionRange.start || offset > expressionRange.end) {
        continue;
      }
      if (source
          .substring(expressionRange.start, expressionRange.end)
          .contains('\n')) {
        continue;
      }

      final operatorIndex = _topLevelBooleanOperatorIndex(
        tokens: tokens,
        startIndex: openingIndex + 1,
        endIndex: closingIndex,
      );
      if (operatorIndex == null) {
        continue;
      }
      final operatorToken = tokens[operatorIndex];
      final replacementOperator = switch (operatorToken.lexeme) {
        '&&' => '||',
        '||' => '&&',
        _ => null,
      };
      if (replacementOperator == null) {
        continue;
      }

      final leftRange = _trimmedRange(
        source,
        SourceRange(
          start: tokens[openingIndex].range.end,
          end: operatorToken.range.start,
        ),
      );
      final rightRange = _trimmedRange(
        source,
        SourceRange(
          start: operatorToken.range.end,
          end: tokens[closingIndex].range.start,
        ),
      );
      if (leftRange.isCollapsed || rightRange.isCollapsed) {
        continue;
      }

      final leftText = source.substring(leftRange.start, leftRange.end);
      final rightText = source.substring(rightRange.start, rightRange.end);
      return DiagnosticQuickFix(
        label: "Apply De Morgan's law",
        detail: 'Distribute negation over the boolean expression.',
        edits: [
          FormattingEdit(
            range: expressionRange,
            newText:
                '${_negatedBooleanTerm(leftText)} '
                '$replacementOperator '
                '${_negatedBooleanTerm(rightText)}',
          ),
        ],
      );
    }
    return null;
  }

  int? _topLevelBooleanOperatorIndex({
    required List<TokenSpan> tokens,
    required int startIndex,
    required int endIndex,
  }) {
    int? operatorIndex;
    var nestedDepth = 0;
    for (var index = startIndex; index < endIndex; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      if (nestedDepth == 0 && (token.lexeme == '&&' || token.lexeme == '||')) {
        if (operatorIndex != null) {
          return null;
        }
        operatorIndex = index;
      }
      if (token.lexeme == '(' || token.lexeme == '[' || token.lexeme == '{') {
        nestedDepth += 1;
      } else if (token.lexeme == ')' ||
          token.lexeme == ']' ||
          token.lexeme == '}') {
        nestedDepth -= 1;
      }
    }
    return operatorIndex;
  }

  String _negatedBooleanTerm(String expression) {
    final trimmed = expression.trim();
    if (trimmed.startsWith('!')) {
      return trimmed.substring(1).trimLeft();
    }
    if (_isSimplePostfixOperand(trimmed)) {
      return '!$trimmed';
    }
    return '!($trimmed)';
  }

  DiagnosticQuickFix? _flipComparisonAt(DocumentState document, int offset) {
    final source = document.text;
    final tokens = _syntaxHighlighter.tokenize(source);
    for (var index = 0; index < tokens.length; index += 1) {
      final operatorToken = tokens[index];
      final flippedOperator = _flippedComparisonOperator(operatorToken.lexeme);
      if (flippedOperator == null) {
        continue;
      }
      final leftRange = _comparisonLeftOperandRange(
        source: source,
        tokens: tokens,
        operatorIndex: index,
      );
      final rightRange = _comparisonRightOperandRange(
        source: source,
        tokens: tokens,
        operatorIndex: index,
      );
      if (leftRange == null ||
          rightRange == null ||
          leftRange.isCollapsed ||
          rightRange.isCollapsed) {
        continue;
      }
      final expressionRange = SourceRange(
        start: leftRange.start,
        end: rightRange.end,
      );
      if (offset < expressionRange.start || offset > expressionRange.end) {
        continue;
      }
      final leftText = source.substring(leftRange.start, leftRange.end).trim();
      final rightText = source
          .substring(rightRange.start, rightRange.end)
          .trim();
      return DiagnosticQuickFix(
        label: 'Flip comparison operands',
        detail: 'Swap comparison operands and preserve the expression meaning.',
        edits: [
          FormattingEdit(
            range: expressionRange,
            newText: '$rightText $flippedOperator $leftText',
          ),
        ],
      );
    }
    return null;
  }

  String? _flippedComparisonOperator(String lexeme) {
    return const {
      '<': '>',
      '<=': '>=',
      '>': '<',
      '>=': '<=',
      '==': '==',
      '!=': '!=',
    }[lexeme];
  }

  SourceRange? _comparisonLeftOperandRange({
    required String source,
    required List<TokenSpan> tokens,
    required int operatorIndex,
  }) {
    var start = tokens[operatorIndex].range.start;
    var end = start;
    var nestedDepth = 0;
    var sawOperand = false;
    for (var index = operatorIndex - 1; index >= 0; index -= 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace) {
        if (token.lexeme.contains('\n')) {
          break;
        }
        continue;
      }
      if (token.kind == TokenKind.comment ||
          _isComparisonOperandBoundary(token, nestedDepth) ||
          (token.kind == TokenKind.keyword && token.lexeme == 'when')) {
        break;
      }
      sawOperand = true;
      start = token.range.start;
      if (token.lexeme == ')' || token.lexeme == ']' || token.lexeme == '}') {
        nestedDepth += 1;
      } else if (token.lexeme == '(' ||
          token.lexeme == '[' ||
          token.lexeme == '{') {
        nestedDepth -= 1;
      }
    }
    if (!sawOperand) {
      return null;
    }
    return _trimmedRange(source, SourceRange(start: start, end: end));
  }

  SourceRange? _comparisonRightOperandRange({
    required String source,
    required List<TokenSpan> tokens,
    required int operatorIndex,
  }) {
    final firstIndex = _nextSignificantIndex(tokens, operatorIndex + 1);
    if (firstIndex == null ||
        _hasLineBreakBetween(tokens, operatorIndex + 1, firstIndex)) {
      return null;
    }
    var start = tokens[firstIndex].range.start;
    var end = tokens[firstIndex].range.end;
    var nestedDepth = 0;
    var sawOperand = false;
    for (var index = firstIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace) {
        if (token.lexeme.contains('\n')) {
          break;
        }
        continue;
      }
      if (token.kind == TokenKind.comment ||
          _isComparisonOperandBoundary(token, nestedDepth)) {
        break;
      }
      sawOperand = true;
      end = token.range.end;
      if (token.lexeme == '(' || token.lexeme == '[' || token.lexeme == '{') {
        nestedDepth += 1;
      } else if (token.lexeme == ')' ||
          token.lexeme == ']' ||
          token.lexeme == '}') {
        nestedDepth -= 1;
      }
    }
    if (!sawOperand) {
      return null;
    }
    return _trimmedRange(source, SourceRange(start: start, end: end));
  }

  bool _isComparisonOperandBoundary(TokenSpan token, int nestedDepth) {
    if (nestedDepth != 0) {
      return false;
    }
    return const {
      '->',
      '&&',
      '||',
      ',',
      ';',
      '=',
      '{',
      '}',
    }.contains(token.lexeme);
  }

  DiagnosticQuickFix? _negateWhenConditionAt(
    DocumentState document,
    int offset,
  ) {
    final source = document.text;
    final tokens = _syntaxHighlighter.tokenize(source);
    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind != TokenKind.keyword || token.lexeme != 'when') {
        continue;
      }
      final expressionStartIndex = _nextSignificantIndex(tokens, index + 1);
      if (expressionStartIndex == null ||
          _hasLineBreakBetween(tokens, index + 1, expressionStartIndex)) {
        continue;
      }
      final conditionRange = _whenConditionExpressionRange(
        source: source,
        tokens: tokens,
        expressionStartIndex: expressionStartIndex,
      );
      if (conditionRange == null || conditionRange.isCollapsed) {
        continue;
      }
      if (offset < conditionRange.start || offset > conditionRange.end) {
        continue;
      }
      return DiagnosticQuickFix(
        label: 'Negate when condition',
        detail: 'Invert the current `when` guard expression.',
        edits: [
          FormattingEdit(
            range: conditionRange,
            newText: _negatedWhenConditionText(source, conditionRange),
          ),
        ],
      );
    }
    return null;
  }

  SourceRange? _whenConditionExpressionRange({
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

  String _negatedWhenConditionText(String source, SourceRange range) {
    final conditionText = source.substring(range.start, range.end).trim();
    if (conditionText.startsWith('!')) {
      return conditionText.substring(1).trimLeft();
    }
    if (_isSimplePostfixOperand(conditionText)) {
      return '!$conditionText';
    }
    return '!($conditionText)';
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

  TokenSpan? _completionSeedToken(List<TokenSpan> tokens, int offset) {
    TokenSpan? trailingEditableToken;
    TokenSpan? containingEditableToken;

    for (final token in tokens) {
      if (token.kind == TokenKind.whitespace) {
        continue;
      }
      if (!_isCompletionSeedKind(token)) {
        continue;
      }
      if (token.range.end == offset) {
        trailingEditableToken = token;
      }
      if (containingEditableToken == null && token.range.contains(offset)) {
        containingEditableToken = token;
      }
    }

    return trailingEditableToken ??
        containingEditableToken ??
        _tokenAroundOffset(tokens, offset);
  }

  bool _isCompletionSeedKind(TokenSpan token) {
    return switch (token.kind) {
      TokenKind.identifier ||
      TokenKind.keyword ||
      TokenKind.operator ||
      TokenKind.unknown => true,
      TokenKind.number ||
      TokenKind.string ||
      TokenKind.comment ||
      TokenKind.punctuation ||
      TokenKind.whitespace => false,
    };
  }

  List<CompletionItem> _postfixCompletionItems(
    String source,
    int offset,
    List<TokenSpan> tokens,
  ) {
    final context = _postfixCompletionContext(source, offset, tokens);
    if (context == null) {
      return const <CompletionItem>[];
    }

    final expression = source.substring(
      context.expressionRange.start,
      context.expressionRange.end,
    );
    final baseIndent = _lineIndentBefore(source, context.expressionRange.start);
    final taskText = '||> {\n$baseIndent  <| $expression\n$baseIndent}';

    return [
      CompletionItem(
        label: '.not',
        kind: CompletionItemKind.snippet,
        insertText: _negatedPostfixExpression(expression),
        detail: 'Postfix completion: negate the expression.',
        replacementRange: context.replacementRange,
      ),
      CompletionItem(
        label: '.when',
        kind: CompletionItemKind.snippet,
        insertText: 'when $expression -> state next_state',
        detail: 'Postfix completion: use the expression as a state guard.',
        replacementRange: context.replacementRange,
      ),
      CompletionItem(
        label: '.emit',
        kind: CompletionItemKind.snippet,
        insertText: 'emit $expression',
        detail: 'Postfix completion: emit the expression.',
        replacementRange: context.replacementRange,
      ),
      CompletionItem(
        label: '.task',
        kind: CompletionItemKind.snippet,
        insertText: taskText,
        detail: 'Postfix completion: return the expression from a task block.',
        replacementRange: context.replacementRange,
      ),
      CompletionItem(
        label: '.await',
        kind: CompletionItemKind.snippet,
        insertText: '?| $expression -> value: i64',
        detail: 'Postfix completion: await a task-like expression.',
        replacementRange: context.replacementRange,
      ),
      CompletionItem(
        label: '.stdout',
        kind: CompletionItemKind.snippet,
        insertText: '$expression -> @stdout',
        detail: 'Postfix completion: send the expression to stdout.',
        replacementRange: context.replacementRange,
      ),
    ];
  }

  _PostfixCompletionContext? _postfixCompletionContext(
    String source,
    int offset,
    List<TokenSpan> tokens,
  ) {
    final normalizedOffset = offset.clamp(0, source.length).toInt();
    final token = _tokenAroundOffset(tokens, normalizedOffset);
    int? dotOffset;
    var suffixEnd = normalizedOffset;

    if (token != null &&
        (token.kind == TokenKind.identifier ||
            token.kind == TokenKind.keyword) &&
        token.range.start <= normalizedOffset &&
        normalizedOffset <= token.range.end) {
      final possibleDot = token.range.start - 1;
      if (possibleDot >= 0 && source[possibleDot] == '.') {
        dotOffset = possibleDot;
        suffixEnd = token.range.end;
      }
    }

    if (dotOffset == null &&
        normalizedOffset > 0 &&
        source[normalizedOffset - 1] == '.') {
      dotOffset = normalizedOffset - 1;
      suffixEnd = normalizedOffset;
    }

    if (dotOffset == null) {
      return null;
    }

    final expressionRange = _postfixExpressionRange(source, dotOffset);
    if (expressionRange == null) {
      return null;
    }

    return _PostfixCompletionContext(
      expressionRange: expressionRange,
      replacementRange: SourceRange(
        start: expressionRange.start,
        end: suffixEnd,
      ),
    );
  }

  SourceRange? _postfixExpressionRange(String source, int dotOffset) {
    var targetEnd = dotOffset;
    while (targetEnd > 0 && _isHorizontalWhitespace(source[targetEnd - 1])) {
      targetEnd -= 1;
    }
    if (targetEnd <= 0) {
      return null;
    }

    var index = targetEnd - 1;
    var parenDepth = 0;
    var bracketDepth = 0;
    while (index >= 0) {
      final char = source[index];
      if (char == '\n' || char == '\r') {
        break;
      }
      if (char == '"') {
        index -= 1;
        while (index >= 0) {
          final quoteCandidate =
              source[index] == '"' && (index == 0 || source[index - 1] != '\\');
          index -= 1;
          if (quoteCandidate) {
            break;
          }
        }
        continue;
      }
      if (char == ')') {
        parenDepth += 1;
        index -= 1;
        continue;
      }
      if (char == ']') {
        bracketDepth += 1;
        index -= 1;
        continue;
      }
      if (char == '(') {
        if (parenDepth == 0) {
          break;
        }
        parenDepth -= 1;
        index -= 1;
        continue;
      }
      if (char == '[') {
        if (bracketDepth == 0) {
          break;
        }
        bracketDepth -= 1;
        index -= 1;
        continue;
      }
      if (parenDepth == 0 && bracketDepth == 0) {
        if (_isHorizontalWhitespace(char) || '{};,='.contains(char)) {
          break;
        }
      }
      index -= 1;
    }

    var start = index + 1;
    while (start < targetEnd && _isHorizontalWhitespace(source[start])) {
      start += 1;
    }
    if (start >= targetEnd) {
      return null;
    }
    return SourceRange(start: start, end: targetEnd);
  }

  String _negatedPostfixExpression(String expression) {
    final trimmed = expression.trim();
    if (_isSimplePostfixOperand(trimmed)) {
      return '!$trimmed';
    }
    return '!($trimmed)';
  }

  bool _isSimplePostfixOperand(String expression) {
    if (expression.isEmpty) {
      return false;
    }
    if (RegExp(r'^[A-Za-z_][A-Za-z0-9_]*(\([^()]*\))?$').hasMatch(expression)) {
      return true;
    }
    if (RegExp(r'^-?[0-9]+(\.[0-9]+)?$').hasMatch(expression)) {
      return true;
    }
    return expression.startsWith('(') && expression.endsWith(')');
  }

  String _lineIndentBefore(String source, int offset) {
    final lineStart = offset <= 0
        ? 0
        : source.lastIndexOf('\n', offset - 1) + 1;
    final buffer = StringBuffer();
    for (var index = lineStart; index < offset; index += 1) {
      final char = source[index];
      if (!_isHorizontalWhitespace(char)) {
        return '';
      }
      buffer.write(char);
    }
    return buffer.toString();
  }

  bool _isHorizontalWhitespace(String char) {
    return char == ' ' || char == '\t';
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
      documentation: symbol.documentation,
    );
  }
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

class _PostfixCompletionContext {
  const _PostfixCompletionContext({
    required this.expressionRange,
    required this.replacementRange,
  });

  final SourceRange expressionRange;
  final SourceRange replacementRange;
}

class _DuplicateDeclarationEntry {
  const _DuplicateDeclarationEntry({
    required this.original,
    required this.symbol,
  });

  final DocumentSymbol original;
  final DocumentSymbol symbol;
}

class _SimilarSymbolCandidate {
  const _SimilarSymbolCandidate({required this.symbol, required this.score});

  final DocumentSymbol symbol;
  final int score;
}
