/// Provider allowlist/denylist and access control.
///
/// Controls which AI providers are allowed or blocked for agent requests.
/// An allowlist takes precedence: if set, only matching providers are allowed.
/// A denylist blocks specific providers regardless of allowlist.
///
/// Key invariants:
/// - Provider IDs are lowercased for matching.
/// - Wildcard "*" in allowlist allows all providers.
/// - Denylist always overrides allowlist.
/// - Matching against provider kind, adapter ID, and profile endpoint model.
/// - Access control is checked before provider selection and execution.
library;

enum AgentProviderAccessControlAction { allow, deny }

extension AgentProviderAccessControlActionX on AgentProviderAccessControlAction {
  String get wireValue {
    return switch (this) {
      AgentProviderAccessControlAction.allow => 'allow',
      AgentProviderAccessControlAction.deny => 'deny',
    };
  }
}

class AgentProviderAccessRule {
  const AgentProviderAccessRule({
    required this.pattern,
    required this.action,
    this.reason = '',
    this.targetField = 'providerId',
    this.schemaVersion = 1,
    this.extraFields = const <String, Object?>{},
  });

  /// Pattern to match. Supports exact match or suffix "*" wildcard.
  /// Examples: "openai.compatible", "openai.*", "local-*", "*".
  final String pattern;

  /// Allow or deny action when this rule matches.
  final AgentProviderAccessControlAction action;

  /// Human-readable reason for the rule.
  final String reason;

  /// Which field to match against: 'providerId', 'adapterId', 'kind', 'model', or 'endpoint'.
  final String targetField;

  /// Schema version for forward compatibility.
  final int schemaVersion;

  /// Extra fields for forward compatibility.
  final Map<String, Object?> extraFields;

  bool matchesProviderField(String fieldValue) {
    final normalizedValue = fieldValue.trim().toLowerCase();
    final normalizedPattern = pattern.trim().toLowerCase();
    if (normalizedPattern.isEmpty) {
      return false;
    }
    if (normalizedPattern == '*') {
      return true;
    }
    if (!normalizedPattern.contains('*')) {
      return normalizedValue == normalizedPattern;
    }
    final parts = normalizedPattern.split('*');
    if (parts.length == 2 && parts[0].isEmpty) {
      return normalizedValue.endsWith(parts[1]);
    }
    if (parts.length == 2 && parts[1].isEmpty) {
      return normalizedValue.startsWith(parts[0]);
    }
    final expression = parts.map(RegExp.escape).join('.*');
    return RegExp('^$expression\$').hasMatch(normalizedValue);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'pattern': pattern,
      'action': action.wireValue,
      'targetField': targetField,
      if (reason.isNotEmpty) 'reason': reason,
      ...extraFields,
    };
  }

  factory AgentProviderAccessRule.fromJson(Map<String, Object?> json) {
    const knownKeys = {
      'schemaVersion', 'pattern', 'action', 'targetField', 'reason',
    };
    final extraFields = <String, Object?>{};
    for (final entry in json.entries) {
      if (!knownKeys.contains(entry.key)) {
        extraFields[entry.key] = entry.value;
      }
    }
    return AgentProviderAccessRule(
      pattern: json['pattern'] as String? ?? '',
      action: _accessActionFromString(json['action'] as String?),
      reason: json['reason'] as String? ?? '',
      targetField: json['targetField'] as String? ?? 'providerId',
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      extraFields: extraFields,
    );
  }
}

AgentProviderAccessControlAction _accessActionFromString(String? value) {
  return switch (value?.trim().toLowerCase()) {
    'deny' || 'block' => AgentProviderAccessControlAction.deny,
    _ => AgentProviderAccessControlAction.allow,
  };
}

enum AgentProviderAccessDecisionStatus {
  /// Provider is explicitly allowed by an allowlist rule.
  allowed,

  /// Provider is blocked by a denylist or not in allowlist when list is active.
  blocked,

  /// No access rules apply; provider can be used freely.
  unrestricted,
}

extension AgentProviderAccessDecisionStatusX
    on AgentProviderAccessDecisionStatus {
  String get wireValue {
    return switch (this) {
      AgentProviderAccessDecisionStatus.allowed => 'allowed',
      AgentProviderAccessDecisionStatus.blocked => 'blocked',
      AgentProviderAccessDecisionStatus.unrestricted => 'unrestricted',
    };
  }
}

class AgentProviderAccessDecision {
  const AgentProviderAccessDecision({
    required this.status,
    required this.matchingRule,
    this.reason = '',
  });

  factory AgentProviderAccessDecision.allowed({
    String reason = 'Provider is allowed by access rule.',
    AgentProviderAccessRule? matchingRule,
  }) {
    return AgentProviderAccessDecision(
      status: AgentProviderAccessDecisionStatus.allowed,
      matchingRule: matchingRule,
      reason: reason,
    );
  }

  factory AgentProviderAccessDecision.blocked({
    required String reason,
    AgentProviderAccessRule? matchingRule,
  }) {
    return AgentProviderAccessDecision(
      status: AgentProviderAccessDecisionStatus.blocked,
      matchingRule: matchingRule,
      reason: reason,
    );
  }

  const AgentProviderAccessDecision.unrestricted({
    this.reason = 'No provider access control rules are configured.',
  }) : status = AgentProviderAccessDecisionStatus.unrestricted,
       matchingRule = null;

  final AgentProviderAccessDecisionStatus status;
  final AgentProviderAccessRule? matchingRule;
  final String reason;

  bool get allowed =>
      status == AgentProviderAccessDecisionStatus.allowed ||
      status == AgentProviderAccessDecisionStatus.unrestricted;

  bool get blocked => status == AgentProviderAccessDecisionStatus.blocked;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'allowed': allowed,
      'blocked': blocked,
      if (matchingRule != null) 'matchingRule': matchingRule!.toJson(),
      if (reason.isNotEmpty) 'reason': reason,
    };
  }
}

class AgentProviderAccessControl {
  const AgentProviderAccessControl({
    this.allowlist = const <AgentProviderAccessRule>[],
    this.denylist = const <AgentProviderAccessRule>[],
    this.schemaVersion = 1,
    this.extraFields = const <String, Object?>{},
  });

  /// If non-empty, ONLY providers matching at least one allowlist rule are usable.
  final List<AgentProviderAccessRule> allowlist;

  /// Providers matching any denylist rule are blocked (always takes precedence).
  final List<AgentProviderAccessRule> denylist;

  /// Schema version for forward compatibility.
  final int schemaVersion;

  /// Extra fields for forward compatibility.
  final Map<String, Object?> extraFields;

  bool get hasAllowlist => allowlist.isNotEmpty;

  bool get hasDenylist => denylist.isNotEmpty;

  bool get hasRules => hasAllowlist || hasDenylist;

  AgentProviderAccessDecision evaluate({
    String? providerId,
    String? adapterId,
    String? kind,
    String? model,
    String? endpoint,
  }) {
    // Denylist check first (always takes precedence).
    for (final rule in denylist) {
      if (_fieldMatches(rule, providerId, adapterId, kind, model, endpoint)) {
        return AgentProviderAccessDecision.blocked(
          reason: rule.reason.isNotEmpty
              ? rule.reason
              : 'Provider blocked by denylist rule: ${rule.pattern}.',
          matchingRule: rule,
        );
      }
    }

    // Allowlist check: if allowlist is active, require at least one match.
    for (final rule in allowlist) {
      if (_fieldMatches(rule, providerId, adapterId, kind, model, endpoint)) {
        return AgentProviderAccessDecision.allowed(
          reason: rule.reason.isNotEmpty
              ? rule.reason
              : 'Provider allowed by allowlist rule: ${rule.pattern}.',
          matchingRule: rule,
        );
      }
    }

    if (hasAllowlist) {
      return AgentProviderAccessDecision.blocked(
        reason:
            'No allowlist rule matched this provider. Allowlist requires explicit '
            'opt-in for the provider to be used.',
      );
    }

    return const AgentProviderAccessDecision.unrestricted();
  }

  bool _fieldMatches(
    AgentProviderAccessRule rule,
    String? providerId,
    String? adapterId,
    String? kind,
    String? model,
    String? endpoint,
  ) {
    final value = switch (rule.targetField.trim().toLowerCase()) {
      'providerid' => providerId,
      'adapterid' => adapterId,
      'kind' => kind,
      'model' => model,
      'endpoint' => endpoint,
      _ => providerId,
    };
    if (value == null || value.isEmpty) {
      return false;
    }
    return rule.matchesProviderField(value);
  }

  AgentProviderAccessControl copyWith({
    List<AgentProviderAccessRule>? allowlist,
    List<AgentProviderAccessRule>? denylist,
    int? schemaVersion,
    Map<String, Object?>? extraFields,
  }) {
    return AgentProviderAccessControl(
      allowlist: allowlist ?? this.allowlist,
      denylist: denylist ?? this.denylist,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      extraFields: extraFields ?? this.extraFields,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'hasAllowlist': hasAllowlist,
      'hasDenylist': hasDenylist,
      'hasRules': hasRules,
      if (allowlist.isNotEmpty)
        'allowlist': allowlist
            .map((rule) => rule.toJson())
            .toList(growable: false),
      if (denylist.isNotEmpty)
        'denylist': denylist
            .map((rule) => rule.toJson())
            .toList(growable: false),
      ...extraFields,
    };
  }

  factory AgentProviderAccessControl.fromJson(Map<String, Object?> json) {
    const knownKeys = {
      'schemaVersion', 'hasAllowlist', 'hasDenylist', 'hasRules',
      'allowlist', 'denylist',
    };
    final extraFields = <String, Object?>{};
    for (final entry in json.entries) {
      if (!knownKeys.contains(entry.key)) {
        extraFields[entry.key] = entry.value;
      }
    }
    final allowlistRaw = json['allowlist'];
    final denylistRaw = json['denylist'];
    return AgentProviderAccessControl(
      allowlist: allowlistRaw is List
          ? allowlistRaw
              .map(_agentProviderAccessRuleFromJson)
              .toList(growable: false)
          : const <AgentProviderAccessRule>[],
      denylist: denylistRaw is List
          ? denylistRaw
              .map(_agentProviderAccessRuleFromJson)
              .toList(growable: false)
          : const <AgentProviderAccessRule>[],
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      extraFields: extraFields,
    );
  }

  static const AgentProviderAccessControl unrestricted =
      AgentProviderAccessControl();
}

AgentProviderAccessRule _agentProviderAccessRuleFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return AgentProviderAccessRule.fromJson(value);
  }
  return AgentProviderAccessRule(
    pattern: value?.toString() ?? '',
    action: AgentProviderAccessControlAction.allow,
  );
}
