class ContextKey<T extends Object> {
  const ContextKey({required this.id, required this.defaultValue});

  final String id;
  final T defaultValue;
}

class WorkbenchContextKeys {
  const WorkbenchContextKeys._();

  static const hasActiveEditor = ContextKey<bool>(
    id: 'workbench.hasActiveEditor',
    defaultValue: false,
  );
  static const activeEditorId = ContextKey<String>(
    id: 'workbench.activeEditorId',
    defaultValue: '',
  );
  static const activeLanguageId = ContextKey<String>(
    id: 'editor.activeLanguageId',
    defaultValue: '',
  );
  static const workspaceTrusted = ContextKey<bool>(
    id: 'workspace.isTrusted',
    defaultValue: false,
  );
  static const editorHasSelection = ContextKey<bool>(
    id: 'editor.hasSelection',
    defaultValue: false,
  );
  static const workspaceIndexReady = ContextKey<bool>(
    id: 'workspace.indexReady',
    defaultValue: false,
  );
}

class ContextKeyExpressionDiagnostic {
  const ContextKeyExpressionDiagnostic({
    required this.offset,
    required this.message,
  });

  final int offset;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{'offset': offset, 'message': message};
  }
}

class ContextKeyExpressionParseResult {
  const ContextKeyExpressionParseResult({
    required this.source,
    required this.diagnostics,
    this.expression,
  });

  final String source;
  final ContextKeyExpression? expression;
  final List<ContextKeyExpressionDiagnostic> diagnostics;

  bool get isValid => expression != null && diagnostics.isEmpty;
}

class ContextKeyExpression {
  const ContextKeyExpression._({
    required this.operator,
    this.key,
    this.value,
    this.values = const <Object?>[],
    this.operands = const <ContextKeyExpression>[],
  });

  const ContextKeyExpression.equals({
    required String key,
    required Object value,
  }) : this._(operator: 'equals', key: key, value: value);

  const ContextKeyExpression.notEquals({
    required String key,
    required Object value,
  }) : this._(operator: 'notEquals', key: key, value: value);

  const ContextKeyExpression.greaterThan({
    required String key,
    required Object value,
  }) : this._(operator: 'greaterThan', key: key, value: value);

  const ContextKeyExpression.greaterThanOrEquals({
    required String key,
    required Object value,
  }) : this._(operator: 'greaterThanOrEquals', key: key, value: value);

  const ContextKeyExpression.lessThan({
    required String key,
    required Object value,
  }) : this._(operator: 'lessThan', key: key, value: value);

  const ContextKeyExpression.lessThanOrEquals({
    required String key,
    required Object value,
  }) : this._(operator: 'lessThanOrEquals', key: key, value: value);

  const ContextKeyExpression.truthy(String key)
    : this._(operator: 'truthy', key: key);

  const ContextKeyExpression.defined(String key)
    : this._(operator: 'defined', key: key);

  const ContextKeyExpression.inValues({
    required String key,
    required List<Object?> values,
  }) : this._(operator: 'in', key: key, values: values);

  const ContextKeyExpression.contains({
    required String key,
    required Object value,
  }) : this._(operator: 'contains', key: key, value: value);

  ContextKeyExpression.not(ContextKeyExpression operand)
    : this._(operator: 'not', operands: <ContextKeyExpression>[operand]);

  ContextKeyExpression.all(List<ContextKeyExpression> operands)
    : this._(operator: 'and', operands: operands);

  ContextKeyExpression.any(List<ContextKeyExpression> operands)
    : this._(operator: 'or', operands: operands);

  final String operator;
  final String? key;
  final Object? value;
  final List<Object?> values;
  final List<ContextKeyExpression> operands;

  static ContextKeyExpression parse(String source) {
    final result = tryParse(source);
    if (!result.isValid) {
      final diagnostic = result.diagnostics.isEmpty
          ? const ContextKeyExpressionDiagnostic(
              offset: 0,
              message: 'Context expression did not produce an expression.',
            )
          : result.diagnostics.first;
      throw FormatException(diagnostic.message, source, diagnostic.offset);
    }
    return result.expression!;
  }

  static ContextKeyExpressionParseResult tryParse(String source) {
    return _ContextKeyExpressionParser(source).parse();
  }

  factory ContextKeyExpression.fromJson(Map<String, Object?> json) {
    final operator = json['operator'] as String? ?? 'equals';
    final key = json['key'] as String?;
    final operandsJson = json['operands'];
    final operands = operandsJson is Iterable
        ? operandsJson
              .whereType<Map>()
              .map(
                (operand) => ContextKeyExpression.fromJson(
                  operand.map(
                    (key, value) =>
                        MapEntry<String, Object?>(key.toString(), value),
                  ),
                ),
              )
              .toList(growable: false)
        : const <ContextKeyExpression>[];
    final valuesJson = json['values'];
    final values = valuesJson is Iterable
        ? List<Object?>.unmodifiable(valuesJson)
        : const <Object?>[];

    return ContextKeyExpression._(
      operator: operator,
      key: key,
      value: json['value'],
      values: values,
      operands: operands,
    );
  }

  bool evaluate(ContextKeyService service) {
    return switch (operator) {
      'equals' => service.rawValue(key ?? '') == value,
      'notEquals' => service.rawValue(key ?? '') != value,
      'greaterThan' => _compare(service.rawValue(key ?? ''), value) > 0,
      'greaterThanOrEquals' =>
        _compare(service.rawValue(key ?? ''), value) >= 0,
      'lessThan' => _compare(service.rawValue(key ?? ''), value) < 0,
      'lessThanOrEquals' => _compare(service.rawValue(key ?? ''), value) <= 0,
      'truthy' => _isTruthy(service.rawValue(key ?? '')),
      'defined' => service.containsKey(key ?? ''),
      'in' => values.contains(service.rawValue(key ?? '')),
      'contains' => _contains(service.rawValue(key ?? ''), value),
      'not' => operands.isNotEmpty && !operands.first.evaluate(service),
      'and' => operands.every((operand) => operand.evaluate(service)),
      'or' => operands.any((operand) => operand.evaluate(service)),
      _ => false,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'operator': operator,
      if (key != null) 'key': key,
      if (_operatorCarriesValue(operator)) 'value': value,
      if (values.isNotEmpty) 'values': List<Object?>.unmodifiable(values),
      if (operands.isNotEmpty)
        'operands': operands
            .map((operand) => operand.toJson())
            .toList(growable: false),
    };
  }
}

class ContextKeyService {
  ContextKeyService({Map<String, Object?> initialValues = const {}})
    : _values = Map<String, Object?>.from(initialValues);

  final Map<String, Object?> _values;

  bool containsKey(String key) {
    return _values.containsKey(key);
  }

  Object? rawValue(String key) {
    return _values[key];
  }

  T value<T extends Object>(String key, {T? defaultValue}) {
    final value = _values[key];
    if (value is T) {
      return value;
    }
    if (defaultValue != null) {
      return defaultValue;
    }
    throw StateError('Context key `$key` is not set as `$T`.');
  }

  T valueFor<T extends Object>(ContextKey<T> key) {
    return value<T>(key.id, defaultValue: key.defaultValue);
  }

  void setValue<T extends Object>(ContextKey<T> key, T value) {
    _values[key.id] = value;
  }

  void setRawValue(String key, Object value) {
    _values[key] = value;
  }

  void setActiveEditor({
    required String editorId,
    required String languageId,
    bool hasSelection = false,
  }) {
    final normalizedEditorId = editorId.trim();
    _values[WorkbenchContextKeys.hasActiveEditor.id] =
        normalizedEditorId.isNotEmpty;
    _values[WorkbenchContextKeys.activeEditorId.id] = normalizedEditorId;
    _values[WorkbenchContextKeys.activeLanguageId.id] = languageId.trim();
    _values[WorkbenchContextKeys.editorHasSelection.id] = hasSelection;
  }

  void clearActiveEditor() {
    _values[WorkbenchContextKeys.hasActiveEditor.id] = false;
    _values[WorkbenchContextKeys.activeEditorId.id] = '';
    _values[WorkbenchContextKeys.activeLanguageId.id] = '';
    _values[WorkbenchContextKeys.editorHasSelection.id] = false;
  }

  void setWorkspaceTrust(bool trusted) {
    _values[WorkbenchContextKeys.workspaceTrusted.id] = trusted;
  }

  void setWorkspaceIndexReady(bool ready) {
    _values[WorkbenchContextKeys.workspaceIndexReady.id] = ready;
  }

  bool matches(ContextKeyExpression expression) {
    return expression.evaluate(this);
  }

  bool matchesAll(Iterable<ContextKeyExpression> expressions) {
    for (final expression in expressions) {
      if (!expression.evaluate(this)) {
        return false;
      }
    }
    return true;
  }

  Map<String, Object?> snapshot() {
    return Map<String, Object?>.unmodifiable(_values);
  }
}

bool _operatorCarriesValue(String operator) {
  return switch (operator) {
    'equals' ||
    'notEquals' ||
    'greaterThan' ||
    'greaterThanOrEquals' ||
    'lessThan' ||
    'lessThanOrEquals' ||
    'contains' => true,
    _ => false,
  };
}

bool _isTruthy(Object? value) {
  return switch (value) {
    null => false,
    bool() => value,
    num() => value != 0,
    String() => value.isNotEmpty,
    Iterable() => value.isNotEmpty,
    _ => true,
  };
}

bool _contains(Object? target, Object? needle) {
  return switch (target) {
    String() when needle is String => target.contains(needle),
    Iterable() => target.contains(needle),
    Map() => target.containsKey(needle),
    _ => false,
  };
}

int _compare(Object? left, Object? right) {
  if (left is num && right is num) {
    return left.compareTo(right);
  }
  if (left is String && right is String) {
    return left.compareTo(right);
  }
  return -1;
}

enum _ContextTokenKind {
  identifier,
  string,
  number,
  boolean,
  operator,
  leftParen,
  rightParen,
  leftBracket,
  rightBracket,
  comma,
  eof,
}

class _ContextToken {
  const _ContextToken({
    required this.kind,
    required this.lexeme,
    required this.offset,
    this.value,
  });

  final _ContextTokenKind kind;
  final String lexeme;
  final int offset;
  final Object? value;
}

class _ContextKeyExpressionParser {
  _ContextKeyExpressionParser(this.source) : _tokens = _tokenize(source);

  final String source;
  final List<_ContextToken> _tokens;
  final List<ContextKeyExpressionDiagnostic> _diagnostics =
      <ContextKeyExpressionDiagnostic>[];
  int _current = 0;

  ContextKeyExpressionParseResult parse() {
    if (_peek.kind == _ContextTokenKind.eof) {
      _error(_peek, 'Context expression is empty.');
      return _result(null);
    }

    final expression = _parseOr();
    if (!_isAtEnd) {
      _error(_peek, 'Unexpected token `${_peek.lexeme}`.');
    }
    return _result(_diagnostics.isEmpty ? expression : null);
  }

  ContextKeyExpressionParseResult _result(ContextKeyExpression? expression) {
    return ContextKeyExpressionParseResult(
      source: source,
      expression: expression,
      diagnostics: List<ContextKeyExpressionDiagnostic>.unmodifiable(
        _diagnostics,
      ),
    );
  }

  ContextKeyExpression _parseOr() {
    var expression = _parseAnd();
    final operands = <ContextKeyExpression>[expression];
    while (_matchOperator('||') || _matchOperator('or')) {
      operands.add(_parseAnd());
    }
    if (operands.length > 1) {
      expression = ContextKeyExpression.any(
        List<ContextKeyExpression>.unmodifiable(operands),
      );
    }
    return expression;
  }

  ContextKeyExpression _parseAnd() {
    var expression = _parseUnary();
    final operands = <ContextKeyExpression>[expression];
    while (_matchOperator('&&') || _matchOperator('and')) {
      operands.add(_parseUnary());
    }
    if (operands.length > 1) {
      expression = ContextKeyExpression.all(
        List<ContextKeyExpression>.unmodifiable(operands),
      );
    }
    return expression;
  }

  ContextKeyExpression _parseUnary() {
    if (_matchOperator('!') || _matchOperator('not')) {
      return ContextKeyExpression.not(_parseUnary());
    }
    return _parsePrimary();
  }

  ContextKeyExpression _parsePrimary() {
    if (_match(_ContextTokenKind.leftParen)) {
      final expression = _parseOr();
      _consume(_ContextTokenKind.rightParen, 'Expected `)`.');
      return expression;
    }

    final key = _consume(
      _ContextTokenKind.identifier,
      'Expected a context key.',
    );
    if (key.kind != _ContextTokenKind.identifier) {
      return const ContextKeyExpression._(operator: 'invalid');
    }

    if (_matchOperator('==')) {
      return ContextKeyExpression.equals(
        key: key.lexeme,
        value: _parseLiteral(),
      );
    }
    if (_matchOperator('!=')) {
      return ContextKeyExpression.notEquals(
        key: key.lexeme,
        value: _parseLiteral(),
      );
    }
    if (_matchOperator('>')) {
      return ContextKeyExpression.greaterThan(
        key: key.lexeme,
        value: _parseLiteral(),
      );
    }
    if (_matchOperator('>=')) {
      return ContextKeyExpression.greaterThanOrEquals(
        key: key.lexeme,
        value: _parseLiteral(),
      );
    }
    if (_matchOperator('<')) {
      return ContextKeyExpression.lessThan(
        key: key.lexeme,
        value: _parseLiteral(),
      );
    }
    if (_matchOperator('<=')) {
      return ContextKeyExpression.lessThanOrEquals(
        key: key.lexeme,
        value: _parseLiteral(),
      );
    }
    if (_matchOperator('in')) {
      return ContextKeyExpression.inValues(
        key: key.lexeme,
        values: _parseLiteralList(),
      );
    }
    if (_matchOperator('contains')) {
      return ContextKeyExpression.contains(
        key: key.lexeme,
        value: _parseLiteral(),
      );
    }

    return ContextKeyExpression.truthy(key.lexeme);
  }

  Object _parseLiteral() {
    if (_match(_ContextTokenKind.string) ||
        _match(_ContextTokenKind.number) ||
        _match(_ContextTokenKind.boolean)) {
      return _previous.value!;
    }
    if (_match(_ContextTokenKind.identifier)) {
      return _previous.lexeme;
    }
    _error(_peek, 'Expected a string, number, boolean, or identifier value.');
    return '';
  }

  List<Object?> _parseLiteralList() {
    if (!_match(_ContextTokenKind.leftBracket)) {
      return <Object?>[_parseLiteral()];
    }

    final values = <Object?>[];
    if (!_check(_ContextTokenKind.rightBracket)) {
      do {
        values.add(_parseLiteral());
      } while (_match(_ContextTokenKind.comma));
    }
    _consume(_ContextTokenKind.rightBracket, 'Expected `]`.');
    return List<Object?>.unmodifiable(values);
  }

  bool _match(_ContextTokenKind kind) {
    if (!_check(kind)) {
      return false;
    }
    _advance();
    return true;
  }

  bool _matchOperator(String lexeme) {
    if (_peek.kind != _ContextTokenKind.operator || _peek.lexeme != lexeme) {
      return false;
    }
    _advance();
    return true;
  }

  _ContextToken _consume(_ContextTokenKind kind, String message) {
    if (_check(kind)) {
      return _advance();
    }
    _error(_peek, message);
    return const _ContextToken(
      kind: _ContextTokenKind.eof,
      lexeme: '',
      offset: 0,
    );
  }

  bool _check(_ContextTokenKind kind) {
    return !_isAtEnd && _peek.kind == kind;
  }

  bool get _isAtEnd => _peek.kind == _ContextTokenKind.eof;

  _ContextToken _advance() {
    if (!_isAtEnd) {
      _current += 1;
    }
    return _previous;
  }

  _ContextToken get _peek => _tokens[_current];

  _ContextToken get _previous => _tokens[_current - 1];

  void _error(_ContextToken token, String message) {
    _diagnostics.add(
      ContextKeyExpressionDiagnostic(offset: token.offset, message: message),
    );
  }
}

List<_ContextToken> _tokenize(String source) {
  final tokens = <_ContextToken>[];
  var index = 0;

  while (index < source.length) {
    final start = index;
    final char = source[index];
    if (char.trim().isEmpty) {
      index += 1;
      continue;
    }
    if (char == '(') {
      tokens.add(
        _ContextToken(
          kind: _ContextTokenKind.leftParen,
          lexeme: char,
          offset: start,
        ),
      );
      index += 1;
      continue;
    }
    if (char == ')') {
      tokens.add(
        _ContextToken(
          kind: _ContextTokenKind.rightParen,
          lexeme: char,
          offset: start,
        ),
      );
      index += 1;
      continue;
    }
    if (char == '[') {
      tokens.add(
        _ContextToken(
          kind: _ContextTokenKind.leftBracket,
          lexeme: char,
          offset: start,
        ),
      );
      index += 1;
      continue;
    }
    if (char == ']') {
      tokens.add(
        _ContextToken(
          kind: _ContextTokenKind.rightBracket,
          lexeme: char,
          offset: start,
        ),
      );
      index += 1;
      continue;
    }
    if (char == ',') {
      tokens.add(
        _ContextToken(
          kind: _ContextTokenKind.comma,
          lexeme: char,
          offset: start,
        ),
      );
      index += 1;
      continue;
    }
    if (char == '"' || char == "'") {
      final parsed = _readQuoted(source, start, char);
      tokens.add(parsed.token);
      index = parsed.nextOffset;
      continue;
    }
    final twoCharacterOperator = index + 1 < source.length
        ? source.substring(index, index + 2)
        : '';
    if (const <String>{
      '&&',
      '||',
      '==',
      '!=',
      '>=',
      '<=',
    }.contains(twoCharacterOperator)) {
      tokens.add(
        _ContextToken(
          kind: _ContextTokenKind.operator,
          lexeme: twoCharacterOperator,
          offset: start,
        ),
      );
      index += 2;
      continue;
    }
    if (const <String>{'!', '>', '<'}.contains(char)) {
      tokens.add(
        _ContextToken(
          kind: _ContextTokenKind.operator,
          lexeme: char,
          offset: start,
        ),
      );
      index += 1;
      continue;
    }
    if (_isNumberStart(source, index)) {
      final parsed = _readNumber(source, start);
      tokens.add(parsed.token);
      index = parsed.nextOffset;
      continue;
    }
    if (_isIdentifierStart(char)) {
      final parsed = _readIdentifier(source, start);
      tokens.add(parsed.token);
      index = parsed.nextOffset;
      continue;
    }

    tokens.add(
      _ContextToken(
        kind: _ContextTokenKind.operator,
        lexeme: char,
        offset: start,
      ),
    );
    index += 1;
  }

  tokens.add(
    _ContextToken(
      kind: _ContextTokenKind.eof,
      lexeme: '',
      offset: source.length,
    ),
  );
  return tokens;
}

_ParsedToken _readQuoted(String source, int start, String quote) {
  final buffer = StringBuffer();
  var index = start + 1;
  while (index < source.length) {
    final char = source[index];
    if (char == quote) {
      return _ParsedToken(
        token: _ContextToken(
          kind: _ContextTokenKind.string,
          lexeme: source.substring(start, index + 1),
          offset: start,
          value: buffer.toString(),
        ),
        nextOffset: index + 1,
      );
    }
    if (char == '\\' && index + 1 < source.length) {
      final escaped = source[index + 1];
      buffer.write(switch (escaped) {
        'n' => '\n',
        'r' => '\r',
        't' => '\t',
        _ => escaped,
      });
      index += 2;
      continue;
    }
    buffer.write(char);
    index += 1;
  }
  return _ParsedToken(
    token: _ContextToken(
      kind: _ContextTokenKind.string,
      lexeme: source.substring(start),
      offset: start,
      value: buffer.toString(),
    ),
    nextOffset: source.length,
  );
}

_ParsedToken _readNumber(String source, int start) {
  var index = start;
  if (source[index] == '-') {
    index += 1;
  }
  while (index < source.length && _isDigit(source[index])) {
    index += 1;
  }
  if (index < source.length && source[index] == '.') {
    index += 1;
    while (index < source.length && _isDigit(source[index])) {
      index += 1;
    }
  }
  final lexeme = source.substring(start, index);
  final parsed = lexeme.contains('.')
      ? double.parse(lexeme)
      : int.parse(lexeme);
  return _ParsedToken(
    token: _ContextToken(
      kind: _ContextTokenKind.number,
      lexeme: lexeme,
      offset: start,
      value: parsed,
    ),
    nextOffset: index,
  );
}

_ParsedToken _readIdentifier(String source, int start) {
  var index = start;
  while (index < source.length && _isIdentifierPart(source[index])) {
    index += 1;
  }
  final lexeme = source.substring(start, index);
  final lower = lexeme.toLowerCase();
  if (lower == 'true' || lower == 'false') {
    return _ParsedToken(
      token: _ContextToken(
        kind: _ContextTokenKind.boolean,
        lexeme: lexeme,
        offset: start,
        value: lower == 'true',
      ),
      nextOffset: index,
    );
  }
  if (const <String>{'and', 'or', 'not', 'in', 'contains'}.contains(lower)) {
    return _ParsedToken(
      token: _ContextToken(
        kind: _ContextTokenKind.operator,
        lexeme: lower,
        offset: start,
      ),
      nextOffset: index,
    );
  }
  return _ParsedToken(
    token: _ContextToken(
      kind: _ContextTokenKind.identifier,
      lexeme: lexeme,
      offset: start,
    ),
    nextOffset: index,
  );
}

bool _isNumberStart(String source, int index) {
  final char = source[index];
  if (_isDigit(char)) {
    return true;
  }
  return char == '-' &&
      index + 1 < source.length &&
      _isDigit(source[index + 1]);
}

bool _isDigit(String char) {
  final code = char.codeUnitAt(0);
  return code >= 48 && code <= 57;
}

bool _isIdentifierStart(String char) {
  final code = char.codeUnitAt(0);
  return (code >= 65 && code <= 90) ||
      (code >= 97 && code <= 122) ||
      char == '_' ||
      char == r'$';
}

bool _isIdentifierPart(String char) {
  return _isIdentifierStart(char) ||
      _isDigit(char) ||
      char == '.' ||
      char == '-' ||
      char == ':' ||
      char == '/';
}

class _ParsedToken {
  const _ParsedToken({required this.token, required this.nextOffset});

  final _ContextToken token;
  final int nextOffset;
}
