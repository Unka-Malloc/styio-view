import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('agent tool permission plan maps default tools to allow or ask', () {
    final selection = AgentToolRegistry().selectForProfile(
      profile: AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      ),
      providerKind: AgentProviderKind.cloudOpenAICompatible,
    );

    final plan = AgentToolPermissionPlan.fromSelection(selection);
    final readDecision = plan.decisions.singleWhere(
      (decision) => decision.toolId == 'readWorkspaceFile',
    );
    final patchDecision = plan.decisions.singleWhere(
      (decision) => decision.toolId == 'applyWorkspacePatch',
    );
    final json = plan.toJson();

    expect(plan.status, AgentToolPermissionPlanStatus.reviewRequired);
    expect(plan.ready, isTrue);
    expect(plan.requiresReview, isTrue);
    expect(plan.blocksDispatch, isFalse);
    expect(plan.allowedToolIds, contains('readWorkspaceFile'));
    expect(plan.reviewToolIds, contains('applyWorkspacePatch'));
    expect(readDecision.action, AgentToolPermissionAction.allow);
    expect(readDecision.status, AgentToolPermissionDecisionStatus.allowed);
    expect(patchDecision.action, AgentToolPermissionAction.ask);
    expect(
      patchDecision.status,
      AgentToolPermissionDecisionStatus.reviewRequired,
    );
    expect(json['status'], 'review_required');
    expect(json['requiresReview'], isTrue);
    expect(json['blocksDispatch'], isFalse);
    expect(
      plan.todoItems.join('\n'),
      contains('permission policy import/export and bulk-edit controls'),
    );
    expect(plan.todoItems.join('\n'), isNot(contains('TODO:')));
  });

  test('agent tool permission rules can deny matching tools', () {
    final selection = AgentToolRegistry().selectForProfile(
      profile: AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      ),
      providerKind: AgentProviderKind.cloudOpenAICompatible,
    );

    final plan = AgentToolPermissionPlan.fromSelection(
      selection,
      rules: const <AgentToolPermissionRule>[
        AgentToolPermissionRule(
          ruleId: 'deny-patches',
          toolIdPattern: 'applyWorkspacePatch',
          action: AgentToolPermissionAction.deny,
          reason: 'Patch application requires a user-approved review gate.',
        ),
      ],
    );
    final deniedDecision = plan.decisions.singleWhere(
      (decision) => decision.toolId == 'applyWorkspacePatch',
    );
    final json = plan.toJson();

    expect(plan.status, AgentToolPermissionPlanStatus.blocked);
    expect(plan.ready, isFalse);
    expect(plan.blocksDispatch, isTrue);
    expect(plan.deniedToolIds, contains('applyWorkspacePatch'));
    expect(plan.recoveryActions, <String>['reviseToolRequest']);
    expect(
      plan.blockingIssueCodes,
      contains('agent.tool.permission.denied.applyWorkspacePatch'),
    );
    expect(deniedDecision.action, AgentToolPermissionAction.deny);
    expect(deniedDecision.status, AgentToolPermissionDecisionStatus.denied);
    expect(deniedDecision.source, 'permission-rule');
    expect(deniedDecision.ruleId, 'deny-patches');
    expect(json['status'], 'blocked');
    expect(json['blockingIssueCodes'], contains(deniedDecision.issueCode));
    expect(json['recoveryActions'], <String>['reviseToolRequest']);
    expect(plan.todoItems.join('\n'), isNot(contains('denied agent tools')));
  });

  test('agent tool permission rules support wildcard tool ids', () {
    final registry = AgentToolRegistry(
      tools: const <AgentToolDefinition>[
        AgentToolDefinition(
          toolId: 'readWorkspaceFile',
          displayName: 'Read Workspace File',
          description: 'Read file.',
          permissionMode: AgentToolPermissionMode.never,
        ),
        AgentToolDefinition(
          toolId: 'runIdeCommand',
          displayName: 'Run IDE Command',
          description: 'Run command.',
          permissionMode: AgentToolPermissionMode.review,
        ),
      ],
    );
    final selection = registry.selectForProfile(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      providerKind: AgentProviderKind.localOnlyFallback,
    );

    final plan = AgentToolPermissionPlan.fromSelection(
      selection,
      rules: const <AgentToolPermissionRule>[
        AgentToolPermissionRule(
          ruleId: 'ask-workspace',
          toolIdPattern: '*Workspace*',
          action: AgentToolPermissionAction.ask,
        ),
      ],
    );

    expect(plan.reviewToolIds, contains('readWorkspaceFile'));
    expect(plan.reviewToolIds, contains('runIdeCommand'));
    expect(plan.status, AgentToolPermissionPlanStatus.reviewRequired);
  });
}
