import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('agent coding loop plan blocks empty dispatch prompts', () {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );

    final plan = controller.codingLoopPlan;
    final json = plan.toJson();
    final dispatch = plan.steps.singleWhere(
      (step) => step.stepId == 'dispatch-provider-request',
    );

    expect(plan.status, AgentCodingLoopPlanStatus.blocked);
    expect(plan.activeStepId, 'dispatch-provider-request');
    expect(dispatch.blockingReasons, contains('agent.prompt.empty'));
    expect(json['activeStepId'], 'dispatch-provider-request');
    expect(
      (json['todoItems']! as List<Object?>).join('\n'),
      isNot(contains('Agent Surface provider picker')),
    );
  });

  test('agent coding loop plan opens dispatch after prompt readiness', () {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );

    controller.updatePrompt('Refactor this Styio file.');
    final plan = controller.codingLoopPlan;
    final snapshot = plan.steps[0];
    final tooling = plan.steps[1];
    final permission = plan.steps[2];
    final dispatch = plan.steps[3];
    final review = plan.steps[4];
    final validation = plan.steps[5];

    expect(plan.status, AgentCodingLoopPlanStatus.ready);
    expect(plan.activeStepId, 'capture-workspace-snapshot');
    expect(
      plan.steps.map((step) => step.stepId),
      containsAllInOrder(const <String>[
        'capture-workspace-snapshot',
        'resolve-agent-tool-contracts',
        'evaluate-agent-tool-permissions',
        'dispatch-provider-request',
        'review-generated-change',
        'validate-applied-change',
        'recover-agent-loop',
      ]),
    );
    expect(snapshot.status, AgentCodingLoopStepStatus.ready);
    expect(tooling.status, AgentCodingLoopStepStatus.ready);
    expect(permission.status, AgentCodingLoopStepStatus.ready);
    expect(permission.blockingReasons, isEmpty);
    expect(
      permission.todoItems.join('\n'),
      contains('permission policy import/export and bulk-edit controls'),
    );
    expect(dispatch.status, AgentCodingLoopStepStatus.ready);
    expect(review.status, AgentCodingLoopStepStatus.waiting);
    expect(validation.status, AgentCodingLoopStepStatus.waiting);
    expect(
      plan.todoItems.join('\n'),
      contains('ExtensionAgentToolHostRpcTransportRegistry'),
    );
    expect(
      plan.todoItems.join('\n'),
      contains('restored workspace snapshot recovery'),
    );
    expect(plan.todoItems.join('\n'), isNot(contains('TODO:')));
    expect(plan.todoItems.join('\n'), isNot(contains('result truncation')));
  });

  test('agent coding loop plan exposes recovery for blocked providers', () {
    const resolution = AgentProviderExecutionResolution(
      profileId: 'blocked-provider',
      status: AgentProviderExecutionResolutionStatus.blocked,
      endpoints: <AgentProviderEndpointReadiness>[],
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
      providerExecutionResolution: resolution,
    );

    controller.updatePrompt('Try a provider-backed edit.');
    final plan = controller.codingLoopPlan;
    final recovery = plan.steps.singleWhere(
      (step) => step.stepId == 'recover-agent-loop',
    );
    final dispatch = plan.steps.singleWhere(
      (step) => step.stepId == 'dispatch-provider-request',
    );

    expect(plan.status, AgentCodingLoopPlanStatus.blocked);
    expect(plan.activeStepId, 'dispatch-provider-request');
    expect(dispatch.blockingReasons, contains('agent.provider.route.blocked'));
    expect(recovery.status, AgentCodingLoopStepStatus.ready);
    expect(recovery.required, isFalse);
    expect(recovery.commandIds, contains('collectAgentCodingCheckpoint'));
  });

  test('agent coding loop plan blocks repeated replay loops', () {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    controller.updatePrompt('Continue after repeated replay failures.');

    final plan = AgentCodingLoopPlan.fromState(
      dispatchPlan: controller.previewDispatchPlan(),
      changeReviewGate: controller.codingChangeReviewGate,
      validationPlan: controller.codingValidationPlan,
      validationPipeline: controller.codingValidationPipeline,
      hasProviderFailure: false,
      loopGuard: AgentCodingLoopGuard.fromSignals(
        toolReplayReportCount: 3,
        failedToolResultCount: 0,
        hasProviderFailure: false,
      ),
    );
    final guard = plan.steps.singleWhere(
      (step) => step.stepId == 'guard-agent-loop',
    );

    expect(plan.status, AgentCodingLoopPlanStatus.blocked);
    expect(plan.activeStepId, 'guard-agent-loop');
    expect(guard.status, AgentCodingLoopStepStatus.blocked);
    expect(guard.blockingReasons, contains('agent.loop.replayReportLimit:3'));
  });
}

AgentSessionContext _context() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: 'value = 1\n',
      revision: 1,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
  );
}
