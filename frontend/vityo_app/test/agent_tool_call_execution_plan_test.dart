import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('agent tool call execution plan requires review for gated tools', () {
    final profile = AgentPromptProfile.openAICodexSparkForPlatform(
      PlatformTarget.linux,
    );
    final selection = AgentToolRegistry().selectForProfile(
      profile: profile,
      providerKind: AgentProviderKind.cloudOpenAICompatible,
    );
    final permissions = AgentToolPermissionPlan.fromSelection(selection);
    final timeline = const AgentToolCallLifecycleTracker()
        .track(<AgentToolCallEvent>[
          const AgentToolCallEvent.callStarted(
            callId: 'call-patch',
            toolId: 'applyWorkspacePatch',
            input: '{"patch":"diff --git a/main.styio b/main.styio"}',
          ),
        ]);

    final plan = AgentToolCallExecutionPlan.fromTimeline(
      toolSelection: selection,
      permissionPlan: permissions,
      timeline: timeline,
    );
    final execution = plan.executionFor('call-patch')!;

    expect(plan.status, AgentToolCallExecutionPlanStatus.reviewRequired);
    expect(plan.ready, isTrue);
    expect(execution.status, AgentToolCallExecutionStatus.reviewRequired);
    expect(
      execution.permissionStatus,
      AgentToolPermissionDecisionStatus.reviewRequired,
    );
    expect(execution.issueCodes, isEmpty);
    expect(plan.toJson()['status'], 'review_required');
  });

  test('agent tool call execution plan applies review decisions', () {
    final profile = AgentPromptProfile.openAICodexSparkForPlatform(
      PlatformTarget.linux,
    );
    final selection = AgentToolRegistry().selectForProfile(
      profile: profile,
      providerKind: AgentProviderKind.cloudOpenAICompatible,
    );
    final permissions = AgentToolPermissionPlan.fromSelection(selection);
    final timeline = const AgentToolCallLifecycleTracker()
        .track(<AgentToolCallEvent>[
          const AgentToolCallEvent.callStarted(
            callId: 'call-patch',
            toolId: 'applyWorkspacePatch',
            input: '{"patch":"diff --git a/main.styio b/main.styio"}',
          ),
        ]);

    final approvedPlan = AgentToolCallExecutionPlan.fromTimeline(
      toolSelection: selection,
      permissionPlan: permissions,
      timeline: timeline,
      reviewDecisions: const <AgentToolCallReviewDecision>[
        AgentToolCallReviewDecision.approved(
          callId: 'call-patch',
          toolId: 'applyWorkspacePatch',
        ),
      ],
    );
    final deniedPlan = AgentToolCallExecutionPlan.fromTimeline(
      toolSelection: selection,
      permissionPlan: permissions,
      timeline: timeline,
      reviewDecisions: const <AgentToolCallReviewDecision>[
        AgentToolCallReviewDecision.denied(
          callId: 'call-patch',
          toolId: 'applyWorkspacePatch',
          reason: 'Patch is too broad.',
        ),
      ],
    );

    expect(approvedPlan.status, AgentToolCallExecutionPlanStatus.ready);
    expect(
      approvedPlan.executionFor('call-patch')!.reviewDecisionStatus,
      AgentToolCallReviewDecisionStatus.approved,
    );
    expect(deniedPlan.status, AgentToolCallExecutionPlanStatus.blocked);
    expect(
      deniedPlan.blockingIssueCodes,
      contains('agent.tool.review.denied.call-patch'),
    );
    expect(
      deniedPlan.executionFor('call-patch')!.reviewDecisionStatus,
      AgentToolCallReviewDecisionStatus.denied,
    );
  });

  test('agent tool call execution plan blocks unregistered tools', () {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final selection = AgentToolRegistry().selectForProfile(
      profile: profile,
      providerKind: AgentProviderKind.localOnlyFallback,
    );
    final permissions = AgentToolPermissionPlan.fromSelection(selection);
    final timeline = const AgentToolCallLifecycleTracker()
        .track(<AgentToolCallEvent>[
          const AgentToolCallEvent.callStarted(
            callId: 'call-unknown',
            toolId: 'unknownTool',
            input: '{}',
          ),
        ]);

    final plan = AgentToolCallExecutionPlan.fromTimeline(
      toolSelection: selection,
      permissionPlan: permissions,
      timeline: timeline,
    );

    expect(plan.status, AgentToolCallExecutionPlanStatus.blocked);
    expect(
      plan.blockingIssueCodes,
      contains('agent.tool.unregistered.unknownTool'),
    );
    expect(
      plan.blockingIssueCodes,
      contains('agent.tool.permission.missing.unknownTool'),
    );
  });

  test('agent tool call execution plan validates required JSON input', () {
    final profile = AgentPromptProfile.openAICodexSparkForPlatform(
      PlatformTarget.linux,
    );
    final selection = AgentToolRegistry().selectForProfile(
      profile: profile,
      providerKind: AgentProviderKind.cloudOpenAICompatible,
    );
    final permissions = AgentToolPermissionPlan.fromSelection(selection);
    final timeline = const AgentToolCallLifecycleTracker()
        .track(<AgentToolCallEvent>[
          const AgentToolCallEvent.callStarted(
            callId: 'call-read',
            toolId: 'readWorkspaceFile',
            input: '{}',
          ),
        ]);

    final plan = AgentToolCallExecutionPlan.fromTimeline(
      toolSelection: selection,
      permissionPlan: permissions,
      timeline: timeline,
    );

    expect(plan.status, AgentToolCallExecutionPlanStatus.blocked);
    expect(
      plan.blockingIssueCodes,
      contains('agent.tool.input.missing.readWorkspaceFile.path'),
    );
  });

  test('agent tool call execution plan waits for streaming input', () {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final selection = AgentToolRegistry().selectForProfile(
      profile: profile,
      providerKind: AgentProviderKind.localOnlyFallback,
    );
    final permissions = AgentToolPermissionPlan.fromSelection(selection);
    final timeline = const AgentToolCallLifecycleTracker()
        .track(<AgentToolCallEvent>[
          const AgentToolCallEvent.inputStart(
            callId: 'call-input',
            toolId: 'readWorkspaceFile',
          ),
          const AgentToolCallEvent.inputDelta(
            callId: 'call-input',
            inputDelta: '{"path"',
          ),
        ]);

    final plan = AgentToolCallExecutionPlan.fromTimeline(
      toolSelection: selection,
      permissionPlan: permissions,
      timeline: timeline,
    );

    expect(plan.status, AgentToolCallExecutionPlanStatus.waiting);
    expect(
      plan.executionFor('call-input')!.status,
      AgentToolCallExecutionStatus.waitingInput,
    );
  });
}
