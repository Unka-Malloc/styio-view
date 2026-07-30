import '../foundation/foundation.dart';
import 'agent_tool_permission.dart';

class AgentToolPermissionPolicy {
  AgentToolPermissionPolicy({
    required this.workspaceId,
    Iterable<AgentToolPermissionRule> rules = const <AgentToolPermissionRule>[],
    DateTime? updatedAt,
  }) : rules = List<AgentToolPermissionRule>.unmodifiable(rules),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  factory AgentToolPermissionPolicy.fromJson(Map<String, Object?> json) {
    return AgentToolPermissionPolicy(
      workspaceId: json['workspaceId'] as String? ?? '',
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      rules: _rulesFromJson(json['rules']),
    );
  }

  /// Default-policy deny rules for tools with specific capabilities.
  /// Each rule matches a tool id glob; capability-based defaults
  /// (destructive, openWorld) are enforced in _actionForPermissionMode().
  static List<AgentToolPermissionRule> get defaultPolicyRules {
    return const <AgentToolPermissionRule>[];
  }

  final String workspaceId;
  final List<AgentToolPermissionRule> rules;
  final DateTime updatedAt;

  AgentToolPermissionPolicy upsertRule(
    AgentToolPermissionRule rule, {
    DateTime? updatedAt,
  }) {
    return AgentToolPermissionPolicy(
      workspaceId: workspaceId,
      rules: <AgentToolPermissionRule>[
        ...rules.where((candidate) => candidate.ruleId != rule.ruleId),
        rule,
      ],
      updatedAt: updatedAt,
    );
  }

  AgentToolPermissionPolicy removeRule(String ruleId, {DateTime? updatedAt}) {
    return AgentToolPermissionPolicy(
      workspaceId: workspaceId,
      rules: rules
          .where((candidate) => candidate.ruleId != ruleId)
          .toList(growable: false),
      updatedAt: updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'updatedAt': updatedAt.toIso8601String(),
      'ruleCount': rules.length,
      'rules': rules.map((rule) => rule.toJson()).toList(growable: false),
    };
  }
}

class AgentToolPermissionPolicyStore {
  AgentToolPermissionPolicyStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'agent.tool-permission-policy',
             layer: 'service',
             stateFamily: 'agent-tool-permission-policy',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const AgentToolPermissionPolicyStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'agent.tool-permission-policy';
  static const String _key = 'rules';

  final FoundationDataStoreOwner _owner;

  Future<void> savePolicy(AgentToolPermissionPolicy policy) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: policy.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: policy.workspaceId,
    );
  }

  Future<AgentToolPermissionPolicy> readPolicy({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return AgentToolPermissionPolicy(workspaceId: workspaceId);
    }
    final policy = AgentToolPermissionPolicy.fromJson(value);
    return policy.workspaceId.isEmpty
        ? AgentToolPermissionPolicy(
            workspaceId: workspaceId,
            rules: policy.rules,
            updatedAt: policy.updatedAt,
          )
        : policy;
  }

  Future<AgentToolPermissionPolicy> upsertRule({
    required String workspaceId,
    required AgentToolPermissionRule rule,
  }) async {
    final current = await readPolicy(workspaceId: workspaceId);
    final next = current.upsertRule(rule);
    await savePolicy(next);
    return next;
  }

  Future<AgentToolPermissionPolicy> removeRule({
    required String workspaceId,
    required String ruleId,
  }) async {
    final current = await readPolicy(workspaceId: workspaceId);
    final next = current.removeRule(ruleId);
    await savePolicy(next);
    return next;
  }
}

List<AgentToolPermissionRule> _rulesFromJson(Object? value) {
  if (value is! List) {
    return const <AgentToolPermissionRule>[];
  }
  return value
      .whereType<Map>()
      .map(
        (entry) => AgentToolPermissionRule.fromJson(
          entry.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          ),
        ),
      )
      .where(
        (rule) =>
            rule.ruleId.trim().isNotEmpty && rule.toolIdPattern.isNotEmpty,
      )
      .toList(growable: false);
}
