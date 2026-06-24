import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';

void main() {
  test('agent registry exposes OpenCode-style primary and subagent roles', () {
    final snapshot = AgentRegistry().snapshot();
    final json = snapshot.toJson();

    expect(snapshot.defaultAgentId, defaultAgentRuntimeAgentId);
    expect(snapshot.activeAgentId, defaultAgentRuntimeAgentId);
    expect(snapshot.activeAgent?.agentId, defaultAgentRuntimeAgentId);
    expect(snapshot.primaryAgentIds, <String>['vityo-coding-agent']);
    expect(snapshot.subagentIds, <String>['vityo-review-agent']);
    expect(snapshot.agentById('vityo-recovery-agent')?.hidden, isTrue);
    expect(json['agentCount'], 3);
    expect(json['defaultAgentId'], defaultAgentRuntimeAgentId);
    expect(json['activeAgentId'], defaultAgentRuntimeAgentId);
    expect(json['activeAgent'], isA<Map<String, Object?>>());
    expect(json['primaryAgentIds'], <String>['vityo-coding-agent']);
    expect(json['subagentIds'], <String>['vityo-review-agent']);
  });

  test(
    'agent registry falls back to visible primary when default is invalid',
    () {
      final registry = AgentRegistry(
        defaultAgentId: 'missing-agent',
        agents: const <AgentRuntimeDefinition>[
          AgentRuntimeDefinition(
            agentId: 'hidden-primary',
            displayName: 'Hidden Primary',
            mode: AgentRuntimeMode.primary,
            hidden: true,
            priority: 100,
          ),
          AgentRuntimeDefinition(
            agentId: 'visible-primary',
            displayName: 'Visible Primary',
            mode: AgentRuntimeMode.primary,
            priority: 10,
          ),
        ],
      );

      expect(registry.defaultAgent()?.agentId, 'visible-primary');
      expect(registry.snapshot().defaultAgentId, 'visible-primary');
      expect(
        registry.snapshot(activeAgentId: 'hidden-primary').activeAgentId,
        'visible-primary',
      );
    },
  );

  test(
    'agent runtime definition serializes permission rules and step limits',
    () {
      const agent = AgentRuntimeDefinition(
        agentId: 'reviewer',
        displayName: 'Reviewer',
        mode: AgentRuntimeMode.subagent,
        maxSteps: 4,
        permissionRules: <AgentToolPermissionRule>[
          AgentToolPermissionRule(
            ruleId: 'deny-apply',
            toolIdPattern: 'applyWorkspacePatch',
            action: AgentToolPermissionAction.deny,
            reason: 'Review-only agent.',
          ),
        ],
      );

      final json = agent.toJson();
      final permissionRules = json['permissionRules']! as List<Object?>;
      final rule = permissionRules.single! as Map<String, Object?>;

      expect(json['mode'], 'subagent');
      expect(json['maxSteps'], 4);
      expect(rule['ruleId'], 'deny-apply');
      expect(rule['action'], 'deny');
    },
  );
}
