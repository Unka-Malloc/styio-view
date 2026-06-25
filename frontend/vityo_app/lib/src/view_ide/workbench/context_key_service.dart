class ContextKey<T extends Object> {
  const ContextKey({
    required this.id,
    required this.defaultValue,
  });

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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'operator': 'equals',
      'key': key,
      'value': value,
    };
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
