import 'agent_tool_registry.dart';

enum AgentToolPermissionAction { allow, ask, deny }

extension AgentToolPermissionActionX on AgentToolPermissionAction {
  String get wireValue => switch (this) {
    AgentToolPermissionAction.allow => 'allow',
    AgentToolPermissionAction.ask => 'ask',
    AgentToolPermissionAction.deny => 'deny',
  };
}

enum AgentToolPermissionDecisionStatus { allowed, reviewRequired, denied }

extension AgentToolPermissionDecisionStatusX
    on AgentToolPermissionDecisionStatus {
  String get wireValue => switch (this) {
    AgentToolPermissionDecisionStatus.allowed => 'allowed',
    AgentToolPermissionDecisionStatus.reviewRequired => 'review_required',
    AgentToolPermissionDecisionStatus.denied => 'denied',
  };
}

enum AgentToolPermissionPlanStatus { ready, reviewRequired, blocked }

extension AgentToolPermissionPlanStatusX on AgentToolPermissionPlanStatus {
  String get wireValue => switch (this) {
    AgentToolPermissionPlanStatus.ready => 'ready',
    AgentToolPermissionPlanStatus.reviewRequired => 'review_required',
    AgentToolPermissionPlanStatus.blocked => 'blocked',
  };
}

class AgentToolPermissionRule {
  const AgentToolPermissionRule({
    required this.ruleId,
    required this.toolIdPattern,
    required this.action,
    this.priority = 0,
    this.reason = '',
  });

  factory AgentToolPermissionRule.fromJson(Map<String, Object?> json) {
    return AgentToolPermissionRule(
      ruleId: json['ruleId'] as String? ?? '',
      toolIdPattern: json['toolIdPattern'] as String? ?? '',
      action: _agentToolPermissionActionFromWire(json['action'] as String?),
      priority: json['priority'] as int? ?? 0,
      reason: json['reason'] as String? ?? '',
    );
  }

  final String ruleId;
  final String toolIdPattern;
  final AgentToolPermissionAction action;
  final int priority;
  final String reason;

  bool matches(AgentToolDefinition tool) {
    return _matchesToolIdPattern(toolIdPattern, tool.toolId);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ruleId': ruleId,
      'toolIdPattern': toolIdPattern,
      'action': action.wireValue,
      'priority': priority,
      if (reason.isNotEmpty) 'reason': reason,
    };
  }
}

class AgentToolPermissionDecision {
  const AgentToolPermissionDecision({
    required this.toolId,
    required this.displayName,
    required this.permissionMode,
    required this.action,
    required this.status,
    required this.source,
    required this.reason,
    this.ruleId,
  });

  factory AgentToolPermissionDecision.fromTool(
    AgentToolDefinition tool, {
    AgentToolPermissionRule? rule,
  }) {
    final action = rule?.action ?? _actionForPermissionMode(tool);
    return AgentToolPermissionDecision(
      toolId: tool.toolId,
      displayName: tool.displayName,
      permissionMode: tool.permissionMode,
      action: action,
      status: _statusForAction(action),
      source: rule == null ? 'tool-default' : 'permission-rule',
      reason: _reasonForDecision(tool, action, rule),
      ruleId: rule?.ruleId,
    );
  }

  final String toolId;
  final String displayName;
  final AgentToolPermissionMode permissionMode;
  final AgentToolPermissionAction action;
  final AgentToolPermissionDecisionStatus status;
  final String source;
  final String reason;
  final String? ruleId;

  bool get requiresReview =>
      status == AgentToolPermissionDecisionStatus.reviewRequired;

  bool get blocksDispatch => status == AgentToolPermissionDecisionStatus.denied;

  String get issueCode => 'agent.tool.permission.denied.$toolId';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'toolId': toolId,
      'displayName': displayName,
      'permissionMode': permissionMode.wireValue,
      'action': action.wireValue,
      'status': status.wireValue,
      'source': source,
      'reason': reason,
      if (ruleId != null) 'ruleId': ruleId,
    };
  }
}

class AgentToolPermissionPlan {
  const AgentToolPermissionPlan({
    required this.status,
    required this.decisions,
    this.rules = const <AgentToolPermissionRule>[],
    this.todoItems = const <String>[],
    this.auditRecords = const <AgentToolPermissionAuditRecord>[],
  });

  factory AgentToolPermissionPlan.fromSelection(
    AgentToolSelection selection, {
    Iterable<AgentToolPermissionRule> rules = const <AgentToolPermissionRule>[],
  }) {
    final orderedRules = rules.toList(growable: false)
      ..sort((left, right) => right.priority.compareTo(left.priority));
    final decisions = <AgentToolPermissionDecision>[
      for (final tool in selection.tools)
        AgentToolPermissionDecision.fromTool(
          tool,
          rule: _firstMatchingRule(tool, orderedRules),
        ),
    ];
    final auditRecords = decisions
        .map((d) => AgentToolPermissionAuditRecord.fromDecision(d))
        .toList(growable: false);
    return AgentToolPermissionPlan(
      status: _planStatus(decisions),
      decisions: List<AgentToolPermissionDecision>.unmodifiable(decisions),
      rules: List<AgentToolPermissionRule>.unmodifiable(orderedRules),
      todoItems: _todoItems(decisions),
      auditRecords: List<AgentToolPermissionAuditRecord>.unmodifiable(
        auditRecords,
      ),
    );
  }

  final AgentToolPermissionPlanStatus status;
  final List<AgentToolPermissionDecision> decisions;
  final List<AgentToolPermissionRule> rules;
  final List<String> todoItems;
  final List<AgentToolPermissionAuditRecord> auditRecords;

  bool get ready => status != AgentToolPermissionPlanStatus.blocked;

  bool get requiresReview =>
      status == AgentToolPermissionPlanStatus.reviewRequired;

  bool get blocksDispatch => status == AgentToolPermissionPlanStatus.blocked;

  List<String> get allowedToolIds {
    return decisions
        .where(
          (decision) =>
              decision.status == AgentToolPermissionDecisionStatus.allowed,
        )
        .map((decision) => decision.toolId)
        .toList(growable: false);
  }

  List<String> get reviewToolIds {
    return decisions
        .where((decision) => decision.requiresReview)
        .map((decision) => decision.toolId)
        .toList(growable: false);
  }

  List<String> get deniedToolIds {
    return decisions
        .where((decision) => decision.blocksDispatch)
        .map((decision) => decision.toolId)
        .toList(growable: false);
  }

  List<String> get issueCodes => blockingIssueCodes;

  List<String> get blockingIssueCodes {
    return decisions
        .where((decision) => decision.blocksDispatch)
        .map((decision) => decision.issueCode)
        .toList(growable: false);
  }

  List<String> get recoveryActions {
    if (!blocksDispatch) {
      return const <String>[];
    }
    return const <String>['reviseToolRequest'];
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'ready': ready,
      'requiresReview': requiresReview,
      'blocksDispatch': blocksDispatch,
      'allowedToolIds': allowedToolIds,
      'reviewToolIds': reviewToolIds,
      'deniedToolIds': deniedToolIds,
      'issueCodes': issueCodes,
      'blockingIssueCodes': blockingIssueCodes,
      if (recoveryActions.isNotEmpty) 'recoveryActions': recoveryActions,
      'decisions': decisions
          .map((decision) => decision.toJson())
          .toList(growable: false),
      'rules': rules.map((rule) => rule.toJson()).toList(growable: false),
      'todoItems': todoItems,
      'auditRecords': auditRecords
          .map((r) => r.toJson())
          .toList(growable: false),
    };
  }
}

class AgentToolPermissionAuditRecord {
  const AgentToolPermissionAuditRecord({
    required this.toolId,
    required this.action,
    required this.decisionStatus,
    required this.reason,
    required this.ruleId,
    required this.createdAtIso8601,
  });

  factory AgentToolPermissionAuditRecord.fromDecision(
    AgentToolPermissionDecision decision,
  ) {
    return AgentToolPermissionAuditRecord(
      toolId: decision.toolId,
      action: decision.action,
      decisionStatus: decision.status,
      reason: decision.reason,
      ruleId: decision.ruleId,
      createdAtIso8601: DateTime.now().toUtc().toIso8601String(),
    );
  }

  final String toolId;
  final AgentToolPermissionAction action;
  final AgentToolPermissionDecisionStatus decisionStatus;
  final String reason;
  final String? ruleId;
  final String createdAtIso8601;

  bool get isDenied =>
      decisionStatus == AgentToolPermissionDecisionStatus.denied;
  bool get requiresReview =>
      decisionStatus == AgentToolPermissionDecisionStatus.reviewRequired;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'toolId': toolId,
      'action': action.wireValue,
      'decisionStatus': decisionStatus.wireValue,
      'reason': reason,
      'ruleId': ruleId,
      'createdAtIso8601': createdAtIso8601,
    };
  }
}

AgentToolPermissionRule? _firstMatchingRule(
  AgentToolDefinition tool,
  List<AgentToolPermissionRule> rules,
) {
  for (final rule in rules) {
    if (rule.matches(tool)) {
      return rule;
    }
  }
  return null;
}

AgentToolPermissionAction _actionForPermissionMode(AgentToolDefinition tool) {
  final modeAction = switch (tool.permissionMode) {
    AgentToolPermissionMode.never => AgentToolPermissionAction.allow,
    AgentToolPermissionMode.review => AgentToolPermissionAction.ask,
    AgentToolPermissionMode.always => AgentToolPermissionAction.allow,
  };

  // Destructive and open-world capabilities default to deny
  // unless the tool's permission mode explicitly allows them.
  final capabilities = tool.capabilities.toSet();
  final hasDestructive = capabilities.contains('destructive');
  final hasOpenWorld = capabilities.contains('openWorld');
  final hasNetwork = capabilities.contains('network');

  if ((hasDestructive || hasOpenWorld) &&
      tool.permissionMode == AgentToolPermissionMode.never) {
    // Even "never" (auto-allow) tools that are destructive or open-world
    // must require review.
    return AgentToolPermissionAction.ask;
  }
  if (hasNetwork && tool.permissionMode == AgentToolPermissionMode.never) {
    // Network-accessing tools default to review even if marked never.
    return AgentToolPermissionAction.ask;
  }

  return modeAction;
}

AgentToolPermissionDecisionStatus _statusForAction(
  AgentToolPermissionAction action,
) {
  return switch (action) {
    AgentToolPermissionAction.allow =>
      AgentToolPermissionDecisionStatus.allowed,
    AgentToolPermissionAction.ask =>
      AgentToolPermissionDecisionStatus.reviewRequired,
    AgentToolPermissionAction.deny => AgentToolPermissionDecisionStatus.denied,
  };
}

AgentToolPermissionPlanStatus _planStatus(
  List<AgentToolPermissionDecision> decisions,
) {
  if (decisions.any((decision) => decision.blocksDispatch)) {
    return AgentToolPermissionPlanStatus.blocked;
  }
  if (decisions.any((decision) => decision.requiresReview)) {
    return AgentToolPermissionPlanStatus.reviewRequired;
  }
  return AgentToolPermissionPlanStatus.ready;
}

List<String> _todoItems(List<AgentToolPermissionDecision> decisions) {
  final todos = <String>[];
  if (decisions.any((decision) => decision.requiresReview)) {
    todos.add(
      'Add project-level permission policy import/export and bulk-edit controls to Agent settings.',
    );
  }
  return List<String>.unmodifiable(todos);
}

String _reasonForDecision(
  AgentToolDefinition tool,
  AgentToolPermissionAction action,
  AgentToolPermissionRule? rule,
) {
  if (rule != null && rule.reason.isNotEmpty) {
    return rule.reason;
  }
  if (rule != null) {
    return 'Matched agent tool permission rule ${rule.ruleId}.';
  }
  return switch (action) {
    AgentToolPermissionAction.allow =>
      'Tool ${tool.toolId} is allowed by its default permission mode.',
    AgentToolPermissionAction.ask =>
      'Tool ${tool.toolId} requires review before execution.',
    AgentToolPermissionAction.deny =>
      'Tool ${tool.toolId} is denied by its default permission mode.',
  };
}

bool _matchesToolIdPattern(String pattern, String toolId) {
  final normalizedPattern = pattern.trim();
  if (normalizedPattern.isEmpty) {
    return false;
  }
  if (normalizedPattern == '*') {
    return true;
  }
  if (!normalizedPattern.contains('*')) {
    return normalizedPattern == toolId;
  }
  final expression = normalizedPattern.split('*').map(RegExp.escape).join('.*');
  return RegExp('^$expression\$').hasMatch(toolId);
}

AgentToolPermissionAction _agentToolPermissionActionFromWire(String? value) {
  return switch (value) {
    'ask' => AgentToolPermissionAction.ask,
    'deny' => AgentToolPermissionAction.deny,
    _ => AgentToolPermissionAction.allow,
  };
}
