class LogRedactionRule {
  const LogRedactionRule({required this.pattern, required this.replacement});

  final RegExp pattern;
  final String replacement;
}

class LogRedactor {
  LogRedactor({
    List<LogRedactionRule>? rules,
    this.redactedValue = '<redacted>',
  }) : rules = rules ?? defaultRules;

  final List<LogRedactionRule> rules;
  final String redactedValue;

  static final List<LogRedactionRule> defaultRules =
      List<LogRedactionRule>.unmodifiable(<LogRedactionRule>[
    LogRedactionRule(
      pattern: RegExp(
        r'\b(Authorization\s*[:=]\s*)(Bearer|Basic)\s+[A-Za-z0-9._~+/=-]+',
        caseSensitive: false,
      ),
      replacement: r'$1$2 <redacted>',
    ),
    LogRedactionRule(
      pattern: RegExp(
        r'\b(Authorization\s*[:=]\s*)(?!(?:Bearer|Basic)\b)[^\s,;}]+',
        caseSensitive: false,
      ),
      replacement: r'$1<redacted>',
    ),
    LogRedactionRule(
      pattern: RegExp(
        r'([?&][a-z0-9_.-]*(?:api[_-]?key|apikey|'
        r'access[_-]?token|refresh[_-]?token|token|secret|password|'
        r'session[_-]?id)=)([^&\s]+)',
        caseSensitive: false,
      ),
      replacement: r'$1<redacted>',
    ),
    LogRedactionRule(
      pattern: RegExp(
        r'''(["']?)([a-z0-9_.-]*(?:api[_-]?key|apikey|'''
        r'''access[_-]?key|secret[_-]?key|private[_-]?key|'''
        r'''access[_-]?token|refresh[_-]?token|id[_-]?token|'''
        r'''bearer[_-]?token|github[_-]?token|registry[_-]?token|'''
        r'''auth[_-]?token|session[_-]?token|token|secret|password|'''
        r'''passwd|pwd|cloud[_-]?session[_-]?id|hosted[_-]?session[_-]?id))'''
        r'''(["']?\s*[:=]\s*["']?)([^"'\s,;}&]+)''',
        caseSensitive: false,
      ),
      replacement: r'$1$2$3<redacted>',
    ),
    LogRedactionRule(
      pattern: RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]{8,}\b',
          caseSensitive: false),
      replacement: 'Bearer <redacted>',
    ),
    LogRedactionRule(
      pattern: RegExp(r'\bsk-(?:proj-)?[A-Za-z0-9_-]{8,}\b'),
      replacement: '<redacted-api-key>',
    ),
    LogRedactionRule(
      pattern: RegExp(r'\bgithub_pat_[A-Za-z0-9_]{20,}\b'),
      replacement: '<redacted-token>',
    ),
    LogRedactionRule(
      pattern: RegExp(r'\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}\b'),
      replacement: '<redacted-token>',
    ),
    LogRedactionRule(
      pattern: RegExp(
        r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
      ),
      replacement: '<redacted-email>',
    ),
    LogRedactionRule(
      pattern: RegExp(
        r'(^|[^\w./-])((?:/Users|/home)/[^/\s,;:)]+(?:/[^\s,;)]*)?)',
      ),
      replacement: r'$1<redacted-path>',
    ),
    LogRedactionRule(
      pattern: RegExp(
        r'\b[A-Z]:\\Users\\[^\\\s,;:)]+(?:\\[^\s,;)]*)?',
        caseSensitive: false,
      ),
      replacement: '<redacted-path>',
    ),
    LogRedactionRule(
      pattern: RegExp(
        r'\b(?:cloud|hosted|agent|codex)[_-]?session(?:[_-]?id)?[_:=/-]?[A-Za-z0-9_-]{8,}\b',
        caseSensitive: false,
      ),
      replacement: '<redacted-session-id>',
    ),
  ]);

  String redact(String message) {
    var result = message;
    for (final rule in rules) {
      result = result.replaceAllMapped(rule.pattern, (match) {
        var replacement = rule.replacement;
        for (var index = 1; index <= match.groupCount; index += 1) {
          replacement = replacement.replaceAll(
            '\$$index',
            match.group(index) ?? '',
          );
        }
        return replacement;
      });
    }
    return result;
  }

  Map<String, Object?> redactJson(Map<String, Object?> json) {
    return <String, Object?>{
      for (final entry in json.entries)
        redact(entry.key): _redactValue(entry.value, fieldName: entry.key),
    };
  }

  Object? redactValue(Object? value, {String? fieldName}) {
    return _redactValue(value, fieldName: fieldName);
  }

  Object? _redactValue(Object? value, {String? fieldName}) {
    if (_shouldRedactScalarField(fieldName) &&
        value != null &&
        value is! Map &&
        value is! Iterable) {
      return redactedValue;
    }
    if (value is String) {
      return redact(value);
    }
    if (value is Map) {
      return redactJson(
        value.map((key, value) => MapEntry(key.toString(), value)),
      );
    }
    if (value is Iterable) {
      return value.map(_redactValue).toList(growable: false);
    }
    return value;
  }

  bool _shouldRedactScalarField(String? fieldName) {
    if (fieldName == null || fieldName.isEmpty) {
      return false;
    }
    final normalized = fieldName.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
    if (normalized.isEmpty ||
        normalized.endsWith('environmentname') ||
        normalized == 'focustoken' ||
        normalized == 'semantictoken' ||
        normalized == 'tokenkind') {
      return false;
    }
    return normalized == 'authorization' ||
        normalized == 'authheader' ||
        normalized == 'apikey' ||
        normalized.endsWith('apikey') ||
        normalized == 'token' ||
        normalized.endsWith('bearertoken') ||
        normalized.endsWith('accesstoken') ||
        normalized.endsWith('refreshtoken') ||
        normalized.endsWith('idtoken') ||
        normalized.endsWith('authtoken') ||
        normalized.endsWith('githubtoken') ||
        normalized.endsWith('registrytoken') ||
        normalized.endsWith('secret') ||
        normalized.endsWith('password') ||
        normalized.endsWith('privatekey') ||
        normalized.endsWith('cloudsessionid') ||
        normalized.endsWith('hostedsessionid');
  }
}
