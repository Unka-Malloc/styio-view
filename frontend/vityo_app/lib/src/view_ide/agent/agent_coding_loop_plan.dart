import 'agent_coding_dispatch_plan.dart';
import 'agent_coding_loop_guard.dart';
import 'agent_session_context.dart';

enum AgentCodingLoopPlanStatus { ready, waiting, blocked, complete }

extension AgentCodingLoopPlanStatusX on AgentCodingLoopPlanStatus {
  String get wireValue => switch (this) {
    AgentCodingLoopPlanStatus.ready => 'ready',
    AgentCodingLoopPlanStatus.waiting => 'waiting',
    AgentCodingLoopPlanStatus.blocked => 'blocked',
    AgentCodingLoopPlanStatus.complete => 'complete',
  };
}

enum AgentCodingLoopPhase {
  snapshot,
  tooling,
  permission,
  dispatch,
  review,
  validate,
  guard,
  recover,
}

extension AgentCodingLoopPhaseX on AgentCodingLoopPhase {
  String get wireValue => switch (this) {
    AgentCodingLoopPhase.snapshot => 'snapshot',
    AgentCodingLoopPhase.tooling => 'tooling',
    AgentCodingLoopPhase.permission => 'permission',
    AgentCodingLoopPhase.dispatch => 'dispatch',
    AgentCodingLoopPhase.review => 'review',
    AgentCodingLoopPhase.validate => 'validate',
    AgentCodingLoopPhase.guard => 'guard',
    AgentCodingLoopPhase.recover => 'recover',
  };
}

enum AgentCodingLoopStepStatus { ready, waiting, blocked, complete }

extension AgentCodingLoopStepStatusX on AgentCodingLoopStepStatus {
  String get wireValue => switch (this) {
    AgentCodingLoopStepStatus.ready => 'ready',
    AgentCodingLoopStepStatus.waiting => 'waiting',
    AgentCodingLoopStepStatus.blocked => 'blocked',
    AgentCodingLoopStepStatus.complete => 'complete',
  };
}

class AgentCodingLoopStep {
  const AgentCodingLoopStep({
    required this.stepId,
    required this.phase,
    required this.status,
    required this.label,
    this.required = true,
    this.commandIds = const <String>[],
    this.blockingReasons = const <String>[],
    this.todoItems = const <String>[],
  });

  final String stepId;
  final AgentCodingLoopPhase phase;
  final AgentCodingLoopStepStatus status;
  final String label;
  final bool required;
  final List<String> commandIds;
  final List<String> blockingReasons;
  final List<String> todoItems;

  bool get ready => status == AgentCodingLoopStepStatus.ready;

  bool get blocked => status == AgentCodingLoopStepStatus.blocked;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'stepId': stepId,
      'phase': phase.wireValue,
      'status': status.wireValue,
      'label': label,
      'required': required,
      if (commandIds.isNotEmpty) 'commandIds': commandIds,
      if (blockingReasons.isNotEmpty) 'blockingReasons': blockingReasons,
      if (todoItems.isNotEmpty) 'todoItems': todoItems,
    };
  }
}

class AgentCodingLoopPlan {
  const AgentCodingLoopPlan({
    required this.status,
    required this.steps,
    this.activeStepId,
    this.todoItems = const <String>[],
  });

  factory AgentCodingLoopPlan.fromState({
    required AgentCodingDispatchPlan dispatchPlan,
    required AgentCodingChangeReviewGate changeReviewGate,
    required AgentCodingValidationPlan validationPlan,
    required AgentCodingValidationPipeline validationPipeline,
    required bool hasProviderFailure,
    AgentCodingLoopGuard loopGuard = const AgentCodingLoopGuard.clear(),
  }) {
    final recoveryNeeded =
        hasProviderFailure ||
        dispatchPlan.blockingIssueCodes.isNotEmpty ||
        validationPipeline.status ==
            AgentCodingValidationPipelineStatus.failed ||
        validationPipeline.status ==
            AgentCodingValidationPipelineStatus.blocked;
    final steps = <AgentCodingLoopStep>[
      AgentCodingLoopStep(
        stepId: 'capture-workspace-snapshot',
        phase: AgentCodingLoopPhase.snapshot,
        status: dispatchPlan.ready
            ? AgentCodingLoopStepStatus.ready
            : AgentCodingLoopStepStatus.waiting,
        label: 'Capture workspace snapshot',
        commandIds: const <String>['collectAgentCodingCheckpoint'],
        todoItems: const <String>[
          'Keep restored workspace snapshot recovery visible until the user applies or discards the revert plan.',
        ],
      ),
      AgentCodingLoopStep(
        stepId: 'resolve-agent-tool-contracts',
        phase: AgentCodingLoopPhase.tooling,
        status: dispatchPlan.ready
            ? AgentCodingLoopStepStatus.ready
            : AgentCodingLoopStepStatus.waiting,
        label: 'Resolve agent tool contracts',
        commandIds: const <String>['collectAgentCodingCheckpoint'],
        todoItems: const <String>[
          'Register production local-process/web-worker/remote-service bindings in ExtensionAgentToolHostRpcTransportRegistry for extension-discovered agent tools.',
        ],
      ),
      AgentCodingLoopStep(
        stepId: 'evaluate-agent-tool-permissions',
        phase: AgentCodingLoopPhase.permission,
        status: dispatchPlan.toolPermissionPlan.blocksDispatch
            ? AgentCodingLoopStepStatus.blocked
            : dispatchPlan.ready
            ? AgentCodingLoopStepStatus.ready
            : AgentCodingLoopStepStatus.waiting,
        label: 'Evaluate agent tool permissions',
        commandIds: const <String>['collectAgentCodingCheckpoint'],
        blockingReasons: dispatchPlan.toolPermissionPlan.blockingIssueCodes,
        todoItems: dispatchPlan.toolPermissionPlan.todoItems.isEmpty
            ? const <String>[
                'Add project-level permission policy import/export and bulk-edit controls to Agent settings.',
              ]
            : dispatchPlan.toolPermissionPlan.todoItems,
      ),
      AgentCodingLoopStep(
        stepId: 'dispatch-provider-request',
        phase: AgentCodingLoopPhase.dispatch,
        status: dispatchPlan.ready
            ? AgentCodingLoopStepStatus.ready
            : AgentCodingLoopStepStatus.blocked,
        label: 'Dispatch provider request',
        blockingReasons: dispatchPlan.issueCodes,
        todoItems: dispatchPlan.todoItems,
      ),
      AgentCodingLoopStep(
        stepId: 'review-generated-change',
        phase: AgentCodingLoopPhase.review,
        status: _reviewStepStatus(changeReviewGate),
        label: 'Review generated change',
        commandIds: changeReviewGate.reviewSurfaceActionIds,
        blockingReasons: changeReviewGate.issueCodes,
        todoItems: changeReviewGate.todoItems,
      ),
      AgentCodingLoopStep(
        stepId: 'validate-applied-change',
        phase: AgentCodingLoopPhase.validate,
        status: _validationStepStatus(validationPipeline),
        label: 'Validate applied change',
        commandIds: <String>{
          if (validationPipeline.nextCommandId != null)
            validationPipeline.nextCommandId!,
          ...validationPipeline.runnableCommandIds,
        }.toList(growable: false),
        blockingReasons:
            validationPlan.status == AgentCodingValidationPlanStatus.blocked
            ? <String>[validationPlan.reason]
            : const <String>[],
        todoItems: validationPlan.todoItems,
      ),
      AgentCodingLoopStep(
        stepId: 'guard-agent-loop',
        phase: AgentCodingLoopPhase.guard,
        status: _guardStepStatus(loopGuard),
        label: 'Guard agent loop',
        blockingReasons: loopGuard.blockingReasons,
        todoItems: loopGuard.todoItems,
      ),
      AgentCodingLoopStep(
        stepId: 'recover-agent-loop',
        phase: AgentCodingLoopPhase.recover,
        status: recoveryNeeded
            ? AgentCodingLoopStepStatus.ready
            : AgentCodingLoopStepStatus.waiting,
        label: 'Recover agent loop',
        required: false,
        commandIds: const <String>['collectAgentCodingCheckpoint'],
        todoItems: const <String>[
          'Bind provider failover and persisted checkpoint recovery controls to Agent Surface.',
        ],
      ),
    ];
    return AgentCodingLoopPlan(
      status: _planStatus(steps),
      steps: List<AgentCodingLoopStep>.unmodifiable(steps),
      activeStepId: _activeStepId(steps),
      todoItems: _collectTodos(steps),
    );
  }

  final AgentCodingLoopPlanStatus status;
  final List<AgentCodingLoopStep> steps;
  final String? activeStepId;
  final List<String> todoItems;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      if (activeStepId != null) 'activeStepId': activeStepId,
      'steps': steps.map((step) => step.toJson()).toList(growable: false),
      'todoItems': todoItems,
    };
  }
}

AgentCodingLoopStepStatus _reviewStepStatus(AgentCodingChangeReviewGate gate) {
  return switch (gate.status) {
    AgentCodingChangeReviewGateStatus.idle => AgentCodingLoopStepStatus.waiting,
    AgentCodingChangeReviewGateStatus.needsReview =>
      AgentCodingLoopStepStatus.ready,
    AgentCodingChangeReviewGateStatus.applying =>
      AgentCodingLoopStepStatus.waiting,
    AgentCodingChangeReviewGateStatus.blocked =>
      AgentCodingLoopStepStatus.blocked,
  };
}

AgentCodingLoopStepStatus _guardStepStatus(AgentCodingLoopGuard guard) {
  return switch (guard.status) {
    AgentCodingLoopGuardStatus.clear => AgentCodingLoopStepStatus.complete,
    AgentCodingLoopGuardStatus.attention => AgentCodingLoopStepStatus.ready,
    AgentCodingLoopGuardStatus.blocked => AgentCodingLoopStepStatus.blocked,
  };
}

AgentCodingLoopStepStatus _validationStepStatus(
  AgentCodingValidationPipeline pipeline,
) {
  return switch (pipeline.status) {
    AgentCodingValidationPipelineStatus.idle =>
      AgentCodingLoopStepStatus.waiting,
    AgentCodingValidationPipelineStatus.waiting =>
      AgentCodingLoopStepStatus.waiting,
    AgentCodingValidationPipelineStatus.ready =>
      AgentCodingLoopStepStatus.ready,
    AgentCodingValidationPipelineStatus.running =>
      AgentCodingLoopStepStatus.ready,
    AgentCodingValidationPipelineStatus.complete =>
      AgentCodingLoopStepStatus.complete,
    AgentCodingValidationPipelineStatus.failed ||
    AgentCodingValidationPipelineStatus.blocked =>
      AgentCodingLoopStepStatus.blocked,
  };
}

AgentCodingLoopPlanStatus _planStatus(List<AgentCodingLoopStep> steps) {
  if (steps.any((step) => step.required && step.blocked)) {
    return AgentCodingLoopPlanStatus.blocked;
  }
  if (steps.any((step) => step.ready)) {
    return AgentCodingLoopPlanStatus.ready;
  }
  if (steps
      .where((step) => step.required)
      .every((step) => step.status == AgentCodingLoopStepStatus.complete)) {
    return AgentCodingLoopPlanStatus.complete;
  }
  return AgentCodingLoopPlanStatus.waiting;
}

String? _activeStepId(List<AgentCodingLoopStep> steps) {
  for (final step in steps) {
    if (step.required && step.blocked) {
      return step.stepId;
    }
  }
  for (final step in steps) {
    if (step.ready) {
      return step.stepId;
    }
  }
  for (final step in steps) {
    if (step.status == AgentCodingLoopStepStatus.waiting) {
      return step.stepId;
    }
  }
  return null;
}

List<String> _collectTodos(List<AgentCodingLoopStep> steps) {
  return steps.expand((step) => step.todoItems).toSet().toList(growable: false);
}
