import 'agent_tool_permission.dart';

enum AgentRuntimeMode { primary, subagent, all }

extension AgentRuntimeModeX on AgentRuntimeMode {
  String get wireValue => switch (this) {
    AgentRuntimeMode.primary => 'primary',
    AgentRuntimeMode.subagent => 'subagent',
    AgentRuntimeMode.all => 'all',
  };
}

class AgentRuntimeDefinition {
  const AgentRuntimeDefinition({
    required this.agentId,
    required this.displayName,
    required this.mode,
    this.description = '',
    this.hidden = false,
    this.providerProfileId = '',
    this.systemPrompt = '',
    this.permissionRules = const <AgentToolPermissionRule>[],
    this.capabilities = const <String>[],
    this.maxSteps,
    this.priority = 0,
  });

  final String agentId;
  final String displayName;
  final AgentRuntimeMode mode;
  final String description;
  final bool hidden;
  final String providerProfileId;
  final String systemPrompt;
  final List<AgentToolPermissionRule> permissionRules;
  final List<String> capabilities;
  final int? maxSteps;
  final int priority;

  bool supportsMode(AgentRuntimeMode requestedMode) {
    return mode == AgentRuntimeMode.all || mode == requestedMode;
  }

  bool get visibleAsPrimary {
    return !hidden && supportsMode(AgentRuntimeMode.primary);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'agentId': agentId,
      'displayName': displayName,
      'mode': mode.wireValue,
      'hidden': hidden,
      'priority': priority,
      if (description.isNotEmpty) 'description': description,
      if (providerProfileId.isNotEmpty) 'providerProfileId': providerProfileId,
      if (systemPrompt.isNotEmpty) 'systemPrompt': systemPrompt,
      if (capabilities.isNotEmpty) 'capabilities': capabilities,
      if (maxSteps != null) 'maxSteps': maxSteps,
      if (permissionRules.isNotEmpty)
        'permissionRules': permissionRules
            .map((rule) => rule.toJson())
            .toList(growable: false),
    };
  }
}

class AgentRegistrySnapshot {
  const AgentRegistrySnapshot({
    required this.defaultAgentId,
    this.activeAgentId = '',
    required this.agents,
  });

  final String defaultAgentId;
  final String activeAgentId;
  final List<AgentRuntimeDefinition> agents;

  int get agentCount => agents.length;

  List<String> get primaryAgentIds {
    return agents
        .where((agent) => agent.visibleAsPrimary)
        .map((agent) => agent.agentId)
        .toList(growable: false);
  }

  List<String> get subagentIds {
    return agents
        .where(
          (agent) =>
              !agent.hidden && agent.supportsMode(AgentRuntimeMode.subagent),
        )
        .map((agent) => agent.agentId)
        .toList(growable: false);
  }

  AgentRuntimeDefinition? agentById(String agentId) {
    final normalized = agentId.trim();
    for (final agent in agents) {
      if (agent.agentId == normalized) {
        return agent;
      }
    }
    return null;
  }

  AgentRuntimeDefinition? get activeAgent {
    return agentById(activeAgentId.isEmpty ? defaultAgentId : activeAgentId);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'defaultAgentId': defaultAgentId,
      'activeAgentId': activeAgentId.isEmpty ? defaultAgentId : activeAgentId,
      'agentCount': agentCount,
      'primaryAgentIds': primaryAgentIds,
      'subagentIds': subagentIds,
      if (activeAgent != null) 'activeAgent': activeAgent!.toJson(),
      'agents': agents.map((agent) => agent.toJson()).toList(growable: false),
    };
  }
}

class AgentRegistry {
  AgentRegistry({
    Iterable<AgentRuntimeDefinition> agents = defaultAgentRuntimeDefinitions,
    String defaultAgentId = defaultAgentRuntimeAgentId,
  }) : _defaultAgentId = defaultAgentId {
    for (final agent in agents) {
      register(agent);
    }
  }

  final String _defaultAgentId;
  final Map<String, AgentRuntimeDefinition> _agents =
      <String, AgentRuntimeDefinition>{};

  List<AgentRuntimeDefinition> get agents {
    final values = _agents.values.toList(growable: false);
    values.sort(_compareAgentPriority);
    return List<AgentRuntimeDefinition>.unmodifiable(values);
  }

  AgentRegistry register(AgentRuntimeDefinition agent) {
    final agentId = agent.agentId.trim();
    if (agentId.isEmpty) {
      throw ArgumentError.value(
        agent.agentId,
        'agentId',
        'Agent id must not be empty.',
      );
    }
    _agents[agentId] = agent;
    return this;
  }

  AgentRuntimeDefinition? resolve(String agentId) {
    return _agents[agentId.trim()];
  }

  AgentRuntimeDefinition? defaultAgent() {
    final configured = resolve(_defaultAgentId);
    if (configured != null && configured.visibleAsPrimary) {
      return configured;
    }
    for (final agent in agents) {
      if (agent.visibleAsPrimary) {
        return agent;
      }
    }
    return null;
  }

  AgentRegistrySnapshot snapshot({String? activeAgentId}) {
    final defaultAgentId = defaultAgent()?.agentId ?? '';
    final activeAgent = _activeAgent(activeAgentId) ?? defaultAgent();
    return AgentRegistrySnapshot(
      defaultAgentId: defaultAgentId,
      activeAgentId: activeAgent?.agentId ?? defaultAgentId,
      agents: agents,
    );
  }

  AgentRuntimeDefinition? _activeAgent(String? activeAgentId) {
    final requested = activeAgentId?.trim();
    if (requested == null || requested.isEmpty) {
      return null;
    }
    final agent = resolve(requested);
    if (agent == null || agent.hidden) {
      return null;
    }
    return agent;
  }
}

const String defaultAgentRuntimeAgentId = 'vityo-coding-agent';

const List<AgentRuntimeDefinition>
defaultAgentRuntimeDefinitions = <AgentRuntimeDefinition>[
  AgentRuntimeDefinition(
    agentId: defaultAgentRuntimeAgentId,
    displayName: 'Vityo Coding Agent',
    mode: AgentRuntimeMode.primary,
    description:
        'Primary coding agent for planning, patch generation, IDE command routing, and validation handoff.',
    capabilities: <String>[
      'plan',
      'code_patch',
      'ide_command',
      'styio_language',
      'validation',
    ],
    maxSteps: 24,
    priority: 100,
  ),
  AgentRuntimeDefinition(
    agentId: 'vityo-review-agent',
    displayName: 'Vityo Review Agent',
    mode: AgentRuntimeMode.subagent,
    description:
        'Review-focused subagent for risks, diagnostics, regressions, and validation coverage.',
    permissionRules: <AgentToolPermissionRule>[
      AgentToolPermissionRule(
        ruleId: 'review-agent-deny-patch-apply',
        toolIdPattern: 'applyWorkspacePatch',
        action: AgentToolPermissionAction.deny,
        priority: 2000,
        reason:
            'Review agents should report findings without applying patches.',
      ),
    ],
    capabilities: <String>[
      'code_review',
      'diagnostic_summary',
      'risk_assessment',
      'validation_review',
    ],
    maxSteps: 12,
    priority: 80,
  ),
  AgentRuntimeDefinition(
    agentId: 'vityo-recovery-agent',
    displayName: 'Vityo Recovery Agent',
    mode: AgentRuntimeMode.all,
    hidden: true,
    description:
        'Internal recovery persona for provider retry, replay, and checkpoint-aware continuation.',
    capabilities: <String>[
      'provider_recovery',
      'tool_replay',
      'checkpoint_recovery',
    ],
    maxSteps: 8,
    priority: 10,
  ),
];

const AgentRegistrySnapshot defaultAgentRegistrySnapshot =
    AgentRegistrySnapshot(
      defaultAgentId: defaultAgentRuntimeAgentId,
      activeAgentId: defaultAgentRuntimeAgentId,
      agents: defaultAgentRuntimeDefinitions,
    );

int _compareAgentPriority(
  AgentRuntimeDefinition left,
  AgentRuntimeDefinition right,
) {
  final priority = right.priority.compareTo(left.priority);
  if (priority != 0) {
    return priority;
  }
  return left.agentId.compareTo(right.agentId);
}
