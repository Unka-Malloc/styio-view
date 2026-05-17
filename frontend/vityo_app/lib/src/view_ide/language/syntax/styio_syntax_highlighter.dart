import '../contract/language_contract.dart';

class StyioSyntaxHighlighter {
  const StyioSyntaxHighlighter();

  static const Set<String> keywords = {
    'import',
    'schema',
    'true',
    'false',
    'avg',
    'max',
    'min',
    'std',
    'rsi',
    // Legacy editor fixtures stay highlighted until the frontend is fully
    // switched to the compiler-owned syntax service.
    'fn',
    'let',
    'pipeline',
    'state',
    'when',
    'emit',
    'spawn',
    'sync',
  };

  static const Set<String> typeNames = {
    'i8',
    'i16',
    'i32',
    'i64',
    'i128',
    'f32',
    'f64',
    'bool',
    'char',
    'string',
    'byte',
    'matrix',
    'list',
    'dict',
    'ftype',
    'cont',
  };

  static const Set<String> standardResources = {
    'stdin',
    'stdout',
    'stderr',
    'file',
  };

  static const Set<String> operatorLexemes = {
    '@',
    '#',
    r'$',
    ':=',
    '?=',
    '?|',
    '||>',
    '<|',
    '|<|',
    '|;',
    '>>',
    '<<',
    '->',
    '<-',
    '=>',
    '|>',
    '??',
    '..',
    '...',
    '[>_]',
    '>_',
    '<~',
    '~>',
    '>=',
    '<=',
    '==',
    '!=',
    '&&',
    '||',
    '**',
    '+=',
    '-=',
    '*=',
    '/=',
    '%=',
    '!',
    '^',
    '+',
    '-',
    '*',
    '/',
    '%',
    '<',
    '>',
    '|',
    '=',
  };

  static const Map<String, String> operatorHover = {
    '@':
        '`@` starts import declarations, resources, standard streams, and '
        'resource topology declarations.',
    '#': '`#` starts Styio function declarations and closure signatures.',
    r'$': r'`$` is a reserved Styio marker operator for syntax surfaces.',
    ':=': '`:=` binds declarations in current Styio syntax.',
    '?=': '`?=` starts match-cases over the left expression.',
    '?|': '`?|` awaits a task result or marks a reserved continuation freeze.',
    '||>': '`||>` launches a task block or task group.',
    '<|': '`<|` returns from a block or applies a one-shot continuation.',
    '|<|': '`|<|` is the inline return form for compact blocks.',
    '|;': '`|;` separates compact pipeline stages by context.',
    '->': '`->` writes to a resource sink or redirects a produced value.',
    '<-': '`<-` receives from a resource entry or awaits a task binding.',
    '>>': '`>>` iterates, pipes, or writes iterable values to a sink.',
    '<<': '`<<` copies resources and remains a compatibility pull spelling.',
    '=>': '`=>` separates a Styio function or closure signature from its body.',
    '|>': '`|>` pipes an expression result into the next stage by context.',
    '..': '`..` is a range, selector, or type-repetition separator by context.',
    '...': '`...` is a dot-run separator equivalent to `..` by context.',
    '[>_]': '`[>_]` is the canonical terminal-handle spelling.',
    '>_': '`>_` is the terminal device primitive.',
    '<~': '`<~` is reserved and should fail closed until implemented.',
    '~>': '`~>` is reserved and should fail closed until implemented.',
    '??': '`??` is reserved for diagnostic/fallback surfaces.',
    '>=': '`>=` is a comparison operator in Styio expressions.',
    '<=': '`<=` is a comparison operator in Styio expressions.',
    '==': '`==` is an equality comparison operator in Styio expressions.',
    '!=': '`!=` is an inequality comparison operator in Styio expressions.',
    '&&': '`&&` is a logical-and operator in Styio expressions.',
    '||': '`||` is a logical-or operator in Styio expressions.',
    '**': '`**` is the exponent-style arithmetic operator.',
    '+=': '`+=` is a compound assignment operator.',
    '-=': '`-=` is a compound assignment operator.',
    '*=': '`*=` is a compound assignment operator.',
    '/=': '`/=` is a compound assignment operator.',
    '%=': '`%=` is a compound assignment operator.',
    '!': '`!` negates a boolean expression by context.',
    '^': '`^` is a caret operator in Styio expressions.',
    '+': '`+` is an arithmetic addition or unary-plus operator.',
    '-': '`-` is an arithmetic subtraction or unary-minus operator.',
    '*': '`*` is an arithmetic multiplication operator.',
    '/': '`/` is an arithmetic division operator.',
    '%': '`%` is an arithmetic remainder operator.',
    '<': '`<` is a comparison operator in Styio expressions.',
    '>': '`>` is a comparison operator in Styio expressions.',
    '|': '`|` separates type dimensions and pipeline fragments by context.',
    '=': '`=` binds or assigns values in compatibility editor syntax.',
  };

  List<TokenSpan> tokenize(String source) {
    final tokens = <TokenSpan>[];
    var index = 0;

    while (index < source.length) {
      final char = source[index];

      if (_isWhitespace(char)) {
        final start = index;
        while (index < source.length && _isWhitespace(source[index])) {
          index += 1;
        }
        tokens.add(
          TokenSpan(
            range: SourceRange(start: start, end: index),
            kind: TokenKind.whitespace,
            lexeme: source.substring(start, index),
          ),
        );
        continue;
      }

      if (_startsWith(source, index, '/*')) {
        final start = index;
        var depth = 1;
        index += 2;
        while (index + 1 < source.length && depth > 0) {
          if (_startsWith(source, index, '/*')) {
            depth += 1;
            index += 2;
            continue;
          }
          if (_startsWith(source, index, '*/')) {
            depth -= 1;
            index += 2;
            continue;
          }
          index += 1;
        }
        if (depth > 0) {
          index = source.length;
        }
        tokens.add(
          TokenSpan(
            range: SourceRange(start: start, end: index),
            kind: TokenKind.comment,
            lexeme: source.substring(start, index),
          ),
        );
        continue;
      }

      if (_startsWith(source, index, '//')) {
        final start = index;
        while (index < source.length && source[index] != '\n') {
          index += 1;
        }
        tokens.add(
          TokenSpan(
            range: SourceRange(start: start, end: index),
            kind: TokenKind.comment,
            lexeme: source.substring(start, index),
          ),
        );
        continue;
      }

      if (_isQuote(char)) {
        final start = index;
        final quote = char;
        index += 1;
        while (index < source.length && source[index] != quote) {
          if (_isLineBreak(source[index])) {
            break;
          }
          if (source[index] == '\\' && index + 1 < source.length) {
            index += 2;
          } else {
            index += 1;
          }
        }
        if (index < source.length && source[index] == quote) {
          index += 1;
        }
        tokens.add(
          TokenSpan(
            range: SourceRange(start: start, end: index),
            kind: TokenKind.string,
            lexeme: source.substring(start, index),
          ),
        );
        continue;
      }

      final operator = _matchOperator(source, index);
      if (operator != null) {
        tokens.add(
          TokenSpan(
            range: SourceRange(start: index, end: index + operator.length),
            kind: TokenKind.operator,
            lexeme: operator,
          ),
        );
        index += operator.length;
        continue;
      }

      if (_isPunctuation(char)) {
        tokens.add(
          TokenSpan(
            range: SourceRange(start: index, end: index + 1),
            kind: TokenKind.punctuation,
            lexeme: char,
          ),
        );
        index += 1;
        continue;
      }

      if (_isDigit(char)) {
        final start = index;
        if (index + 1 < source.length &&
            source[index] == '0' &&
            _isRadixPrefix(source[index + 1])) {
          final prefix = source[index + 1];
          index += 2;
          while (index < source.length &&
              _isRadixDigit(source[index], prefix)) {
            index += 1;
          }
        } else {
          while (index < source.length && _isDecimalDigitPart(source[index])) {
            index += 1;
          }
          if (index + 1 < source.length &&
              source[index] == '.' &&
              source[index + 1] != '.' &&
              _isDigit(source[index + 1])) {
            index += 1;
            while (index < source.length &&
                _isDecimalDigitPart(source[index])) {
              index += 1;
            }
          }
          if (index < source.length &&
              (source[index] == 'e' || source[index] == 'E')) {
            final exponentStart = index;
            index += 1;
            if (index < source.length &&
                (source[index] == '+' || source[index] == '-')) {
              index += 1;
            }
            final digitsStart = index;
            while (index < source.length &&
                _isDecimalDigitPart(source[index])) {
              index += 1;
            }
            if (digitsStart == index) {
              index = exponentStart;
            }
          }
        }
        tokens.add(
          TokenSpan(
            range: SourceRange(start: start, end: index),
            kind: TokenKind.number,
            lexeme: source.substring(start, index),
          ),
        );
        continue;
      }

      if (_isIdentifierStart(char)) {
        final start = index;
        while (index < source.length && _isIdentifierPart(source[index])) {
          index += 1;
        }
        final lexeme = source.substring(start, index);
        tokens.add(
          TokenSpan(
            range: SourceRange(start: start, end: index),
            kind: keywords.contains(lexeme)
                ? TokenKind.keyword
                : TokenKind.identifier,
            lexeme: lexeme,
          ),
        );
        continue;
      }

      tokens.add(
        TokenSpan(
          range: SourceRange(start: index, end: index + 1),
          kind: TokenKind.unknown,
          lexeme: char,
        ),
      );
      index += 1;
    }

    return tokens;
  }

  List<SemanticSpan> resolveSemanticSpans(List<TokenSpan> tokens) {
    final spans = <SemanticSpan>[];

    void addSpan(TokenSpan token, SemanticKind kind) {
      final duplicate = spans.any(
        (span) =>
            span.kind == kind &&
            span.range.start == token.range.start &&
            span.range.end == token.range.end,
      );
      if (duplicate) {
        return;
      }
      spans.add(SemanticSpan(range: token.range, kind: kind));
    }

    int? nextSignificantIndex(int startIndex) {
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

    int? previousSignificantIndex(int startIndex) {
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

    int? parameterListOpeningIndex(int startIndex) {
      for (var index = startIndex; index < tokens.length; index += 1) {
        final token = tokens[index];
        if (token.kind == TokenKind.whitespace ||
            token.kind == TokenKind.comment) {
          continue;
        }
        if (token.lexeme == '(') {
          return index;
        }
        if (token.lexeme == '{' ||
            token.lexeme == '=>' ||
            token.lexeme == ';') {
          return null;
        }
      }
      return null;
    }

    void addParameterSpansInList(int openingIndex) {
      var depth = 0;
      for (var index = openingIndex + 1; index < tokens.length; index += 1) {
        final token = tokens[index];
        if (token.kind == TokenKind.whitespace ||
            token.kind == TokenKind.comment) {
          continue;
        }
        if (token.lexeme == '(') {
          depth += 1;
          continue;
        }
        if (token.lexeme == ')') {
          if (depth == 0) {
            return;
          }
          depth -= 1;
          continue;
        }
        if (depth > 0 ||
            token.kind != TokenKind.identifier ||
            isTypeName(token.lexeme)) {
          continue;
        }

        final previousIndex = previousSignificantIndex(index - 1);
        final nextIndex = nextSignificantIndex(index + 1);
        final previousLexeme = previousIndex == null
            ? '('
            : tokens[previousIndex].lexeme;
        final nextLexeme = nextIndex == null ? ')' : tokens[nextIndex].lexeme;
        final startsParameter = previousLexeme == '(' || previousLexeme == ',';
        final endsParameter =
            nextLexeme == ':' ||
            nextLexeme == ',' ||
            nextLexeme == ')' ||
            nextLexeme == '=';

        if (startsParameter && endsParameter) {
          addSpan(token, SemanticKind.parameter);
        }
      }
    }

    TokenSpan? typedBindingNameBeforeAssignment(int assignmentIndex) {
      final typeIndex = previousSignificantIndex(assignmentIndex - 1);
      if (typeIndex == null || !isTypeName(tokens[typeIndex].lexeme)) {
        return null;
      }
      final colonIndex = previousSignificantIndex(typeIndex - 1);
      if (colonIndex == null || tokens[colonIndex].lexeme != ':') {
        return null;
      }
      final nameIndex = previousSignificantIndex(colonIndex - 1);
      if (nameIndex == null) {
        return null;
      }
      final nameToken = tokens[nameIndex];
      if (nameToken.kind != TokenKind.identifier ||
          isTypeName(nameToken.lexeme)) {
        return null;
      }
      final ownerIndex = previousSignificantIndex(nameIndex - 1);
      if (ownerIndex != null &&
          (tokens[ownerIndex].lexeme == '@' ||
              tokens[ownerIndex].lexeme == '#')) {
        return null;
      }
      return nameToken;
    }

    TokenSpan? untypedBindingNameBeforeAssignment(int assignmentIndex) {
      final nameIndex = previousSignificantIndex(assignmentIndex - 1);
      if (nameIndex == null) {
        return null;
      }
      final nameToken = tokens[nameIndex];
      if (nameToken.kind != TokenKind.identifier ||
          isTypeName(nameToken.lexeme)) {
        return null;
      }
      final ownerIndex = previousSignificantIndex(nameIndex - 1);
      if (ownerIndex != null &&
          (tokens[ownerIndex].lexeme == '@' ||
              tokens[ownerIndex].lexeme == '#')) {
        return null;
      }
      return nameToken;
    }

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];

      if (token.kind == TokenKind.identifier && isTypeName(token.lexeme)) {
        addSpan(token, SemanticKind.typeName);
      }

      if (token.lexeme == '#') {
        final nextIndex = nextSignificantIndex(index + 1);
        if (nextIndex != null &&
            tokens[nextIndex].kind == TokenKind.identifier) {
          addSpan(tokens[nextIndex], SemanticKind.function);
          final openingIndex = parameterListOpeningIndex(nextIndex + 1);
          if (openingIndex != null) {
            addParameterSpansInList(openingIndex);
          }
        } else if (nextIndex != null && tokens[nextIndex].lexeme == '(') {
          addParameterSpansInList(nextIndex);
        }
        continue;
      }

      if (token.lexeme == '@') {
        final resourceIdentifier = nextSignificantToken(
          tokens,
          startIndex: index + 1,
        );
        if (resourceIdentifier != null &&
            resourceIdentifier.lexeme != 'import' &&
            (resourceIdentifier.kind == TokenKind.identifier ||
                resourceIdentifier.kind == TokenKind.keyword)) {
          addSpan(resourceIdentifier, SemanticKind.resource);
        }
        continue;
      }

      if (token.lexeme == '->') {
        final nextIdentifier = nextTokenOfKind(
          tokens,
          startIndex: index + 1,
          kind: TokenKind.identifier,
        );
        final afterIdentifier = nextIdentifier == null
            ? null
            : nextSignificantToken(
                tokens,
                startIndex: tokens.indexOf(nextIdentifier) + 1,
              );
        if (nextIdentifier != null && afterIdentifier?.lexeme == ':') {
          addSpan(nextIdentifier, SemanticKind.variable);
        }
      }

      if (token.lexeme == '=' || token.lexeme == ':=') {
        final bindingName =
            typedBindingNameBeforeAssignment(index) ??
            untypedBindingNameBeforeAssignment(index);
        if (bindingName != null) {
          addSpan(bindingName, SemanticKind.variable);
        }
      }

      if (token.kind != TokenKind.keyword) {
        continue;
      }

      switch (token.lexeme) {
        case 'fn':
          final nextIdentifier = nextTokenOfKind(
            tokens,
            startIndex: index + 1,
            kind: TokenKind.identifier,
          );
          if (nextIdentifier != null) {
            addSpan(nextIdentifier, SemanticKind.function);
            final openingIndex = parameterListOpeningIndex(
              tokens.indexOf(nextIdentifier) + 1,
            );
            if (openingIndex != null) {
              addParameterSpansInList(openingIndex);
            }
          }
          break;
        case 'pipeline':
          final nextIdentifier = nextTokenOfKind(
            tokens,
            startIndex: index + 1,
            kind: TokenKind.identifier,
          );
          if (nextIdentifier != null) {
            addSpan(nextIdentifier, SemanticKind.pipeline);
          }
          break;
        case 'state':
          final nextIdentifier = nextTokenOfKind(
            tokens,
            startIndex: index + 1,
            kind: TokenKind.identifier,
          );
          if (nextIdentifier != null) {
            addSpan(nextIdentifier, SemanticKind.state);
          }
          break;
        case 'let':
          final nextIdentifier = nextTokenOfKind(
            tokens,
            startIndex: index + 1,
            kind: TokenKind.identifier,
          );
          if (nextIdentifier != null) {
            addSpan(nextIdentifier, SemanticKind.variable);
          }
          break;
        default:
          break;
      }
    }

    return spans;
  }

  List<SemanticBlockRange> resolveSemanticBlocks(List<TokenSpan> tokens) {
    final blocks = <SemanticBlockRange>[];

    for (var index = 0; index < tokens.length; index += 1) {
      final token = tokens[index];
      final isLegacyFunction =
          token.kind == TokenKind.keyword && token.lexeme == 'fn';
      final isHashFunction = token.lexeme == '#';
      final isTaskLaunch = token.lexeme == '||>';
      final isResourceDeclaration = _isResourceDeclarationBlockAnchor(
        tokens,
        index,
      );
      if (!isLegacyFunction &&
          !isHashFunction &&
          !isTaskLaunch &&
          !isResourceDeclaration) {
        continue;
      }

      final blockName = isTaskLaunch
          ? null
          : nextTokenOfKind(
              tokens,
              startIndex: index + 1,
              kind: TokenKind.identifier,
            );
      final openingBrace = nextTokenByLexeme(
        tokens,
        startIndex: index + 1,
        lexeme: '{',
      );

      if (openingBrace == null) {
        continue;
      }

      final closingBrace = matchingClosingBrace(tokens, openingBrace);
      if (closingBrace == null) {
        continue;
      }

      blocks.add(
        SemanticBlockRange(
          range: SourceRange(
            start: openingBrace.range.start,
            end: closingBrace.range.end,
          ),
          label:
              blockName?.lexeme ??
              (isTaskLaunch ? 'task_block' : 'function_block'),
        ),
      );
    }

    return blocks;
  }

  TokenSpan? tokenAt(String source, int offset) {
    final safeOffset = offset.clamp(0, source.length);
    for (final token in tokenize(source)) {
      if (token.range.contains(safeOffset)) {
        return token;
      }
    }
    return null;
  }

  bool isOperatorLexeme(String lexeme) =>
      operatorLexemes.contains(lexeme) || _isRepeatedOperatorLexeme(lexeme);

  String? hoverForOperator(String lexeme) {
    final exactHover = operatorHover[lexeme];
    if (exactHover != null) {
      return exactHover;
    }
    if (_isRepeatedLexeme(lexeme, '.')) {
      return '`$lexeme` is tokenized as a dot-run separator; `..` is the '
          'canonical range, selector, or type-repetition spelling.';
    }
    if (_isRepeatedLexeme(lexeme, '>')) {
      return '`$lexeme` is tokenized as a write/pipe run; `>>` is the '
          'canonical iterable write or sink spelling.';
    }
    if (_isRepeatedLexeme(lexeme, '^')) {
      return '`$lexeme` is tokenized as a caret-run operator for tolerant '
          'Styio expression preview.';
    }
    return null;
  }

  bool isKeyword(String lexeme) => keywords.contains(lexeme);

  bool isTypeName(String lexeme) => typeNames.contains(lexeme);

  bool isStandardResource(String lexeme) => standardResources.contains(lexeme);

  TokenSpan? nextTokenOfKind(
    List<TokenSpan> tokens, {
    required int startIndex,
    required TokenKind kind,
  }) {
    for (var index = startIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      if (token.kind == kind) {
        return token;
      }
      return null;
    }
    return null;
  }

  TokenSpan? previousTokenOfKind(
    List<TokenSpan> tokens, {
    required int startIndex,
    required TokenKind kind,
  }) {
    for (var index = startIndex; index >= 0; index -= 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      if (token.kind == kind) {
        return token;
      }
      return null;
    }
    return null;
  }

  TokenSpan? nextSignificantToken(
    List<TokenSpan> tokens, {
    required int startIndex,
  }) {
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

  TokenSpan? nextTokenByLexeme(
    List<TokenSpan> tokens, {
    required int startIndex,
    required String lexeme,
  }) {
    for (var index = startIndex; index < tokens.length; index += 1) {
      final token = tokens[index];
      if (token.kind == TokenKind.whitespace ||
          token.kind == TokenKind.comment) {
        continue;
      }
      if (token.lexeme == lexeme) {
        return token;
      }
    }
    return null;
  }

  TokenSpan? matchingClosingBrace(
    List<TokenSpan> tokens,
    TokenSpan openingBrace,
  ) {
    var depth = 0;
    var seenOpening = false;

    for (final token in tokens) {
      if (token.range.start < openingBrace.range.start) {
        continue;
      }

      if (token.kind != TokenKind.punctuation) {
        continue;
      }

      if (token.lexeme == '{') {
        depth += 1;
        seenOpening = true;
      } else if (token.lexeme == '}') {
        depth -= 1;
        if (seenOpening && depth == 0) {
          return token;
        }
      }
    }

    return null;
  }

  bool _isResourceDeclarationBlockAnchor(List<TokenSpan> tokens, int index) {
    final token = tokens[index];
    if (token.lexeme != '@') {
      return false;
    }
    final resourceToken = nextSignificantToken(tokens, startIndex: index + 1);
    if (resourceToken == null ||
        resourceToken.lexeme == 'import' ||
        (resourceToken.kind != TokenKind.identifier &&
            resourceToken.kind != TokenKind.keyword)) {
      return false;
    }
    var cursor = tokens.indexOf(resourceToken) + 1;
    while (true) {
      final next = nextSignificantToken(tokens, startIndex: cursor);
      if (next == null) {
        return false;
      }
      if (next.lexeme == '{' || next.lexeme == ';') {
        return false;
      }
      if (next.lexeme == ':=') {
        final opening = nextSignificantToken(
          tokens,
          startIndex: tokens.indexOf(next) + 1,
        );
        return opening?.lexeme == '{';
      }
      cursor = tokens.indexOf(next) + 1;
    }
  }

  bool _isRepeatedOperatorLexeme(String lexeme) =>
      _isRepeatedLexeme(lexeme, '.') ||
      _isRepeatedLexeme(lexeme, '>') ||
      _isRepeatedLexeme(lexeme, '^');

  static bool _isRepeatedLexeme(String lexeme, String char) =>
      lexeme.length > 1 && lexeme.split('').every((part) => part == char);

  String? _matchOperator(String source, int index) {
    if (source[index] == '.') {
      var end = index;
      while (end < source.length && source[end] == '.') {
        end += 1;
      }
      if (end - index >= 2) {
        return source.substring(index, end);
      }
    }

    if (source[index] == '>') {
      var end = index;
      while (end < source.length && source[end] == '>') {
        end += 1;
      }
      if (end - index >= 2) {
        return source.substring(index, end);
      }
    }

    if (source[index] == '^') {
      var end = index;
      while (end < source.length && source[end] == '^') {
        end += 1;
      }
      return source.substring(index, end);
    }

    const orderedOperators = [
      '[>_]',
      '|<|',
      '||>',
      '?|',
      ':=',
      '?=',
      '=>',
      '<|',
      '->',
      '<-',
      '<<',
      '>=',
      '<=',
      '==',
      '!=',
      '&&',
      '||',
      '**',
      '+=',
      '-=',
      '*=',
      '/=',
      '%=',
      '<~',
      '~>',
      '??',
      '|>',
      '|;',
      '>_',
    ];
    for (final operator in orderedOperators) {
      if (_startsWith(source, index, operator)) {
        return operator;
      }
    }
    if ('@#\$+-*/%=!?<>|&~'.contains(source[index])) {
      return source[index];
    }
    return null;
  }

  bool _startsWith(String source, int start, String value) {
    if (start + value.length > source.length) {
      return false;
    }
    return source.substring(start, start + value.length) == value;
  }

  bool _isWhitespace(String char) {
    return char == ' ' || char == '\n' || char == '\t' || char == '\r';
  }

  bool _isLineBreak(String char) {
    return char == '\n' || char == '\r';
  }

  bool _isIdentifierStart(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        char == '_';
  }

  bool _isIdentifierPart(String char) {
    return _isIdentifierStart(char) || _isDigit(char);
  }

  bool _isDigit(String char) {
    final code = char.codeUnitAt(0);
    return code >= 48 && code <= 57;
  }

  bool _isDecimalDigitPart(String char) {
    return _isDigit(char) || char == '_';
  }

  bool _isRadixPrefix(String char) {
    return char == 'x' ||
        char == 'X' ||
        char == 'b' ||
        char == 'B' ||
        char == 'o' ||
        char == 'O';
  }

  bool _isRadixDigit(String char, String prefix) {
    if (char == '_') {
      return true;
    }
    switch (prefix) {
      case 'x':
      case 'X':
        return _isHexDigit(char);
      case 'b':
      case 'B':
        return char == '0' || char == '1';
      case 'o':
      case 'O':
        return char.codeUnitAt(0) >= 48 && char.codeUnitAt(0) <= 55;
      default:
        return false;
    }
  }

  bool _isHexDigit(String char) {
    final code = char.codeUnitAt(0);
    return (code >= 48 && code <= 57) ||
        (code >= 65 && code <= 70) ||
        (code >= 97 && code <= 102);
  }

  bool _isQuote(String char) {
    return char == '"' || char == "'";
  }

  bool _isPunctuation(String char) {
    return '{}()[],:;.'.contains(char);
  }
}
