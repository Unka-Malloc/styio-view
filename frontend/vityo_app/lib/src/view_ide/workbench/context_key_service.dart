class ContextKey<T extends Object> {
  const ContextKey({
    required this.id,
    required this.defaultValue,
  });

  final String id;
  final T defaultValue;
}

class ContextKeyExpression {
  const ContextKeyExpression.equals({
    required this.key,
    required this.value,
  });

  final String key;
  final Object value;

  bool evaluate(ContextKeyService service) {
    try {
      return service.value<Object>(key) == value;
    } on StateError {
      return false;
    }
  }
}

class ContextKeyService {
  ContextKeyService({Map<String, Object?> initialValues = const {}})
    : _values = Map<String, Object?>.from(initialValues);

  final Map<String, Object?> _values;

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
