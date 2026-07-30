import 'agent_tool_call_lifecycle.dart';
import 'agent_tool_input_validator.dart';
import 'agent_tool_permission.dart';
import 'agent_tool_registry.dart';

enum AgentToolCallExecutionStatus {
  waitingInput,
  ready,
  reviewRequired,
  blocked,
  completed,
  failed,
}

extension AgentToolCallExecutionStatusX on AgentToolCallExecutionStatus {
  String get wireValue => switch (this) {
    AgentToolCallExecutionStatus.waitingInput => 'waiting_input',
    AgentToolCallExecutionStatus.ready => 'ready',
    AgentToolCallExecutionStatus.reviewRequired => 'review_required',
    AgentToolCallExecutionStatus.blocked => 'blocked',
    AgentToolCallExecutionStatus.completed => 'completed',
    AgentToolCallExecutionStatus.failed => 'failed',
  };
}

enum AgentToolCallExecutionPlanStatus {
  idle,
  waiting,
  ready,
  reviewRequired,
  blocked,
  failed,
  complete,
}

extension AgentToolCallExecutionPlanStatusX
    on AgentToolCallExecutionPlanStatus {
  String get wireValue => switch (this) {
    AgentToolCallExecutionPlanStatus.idle => 'idle',
    AgentToolCallExecutionPlanStatus.waiting => 'waiting',
    AgentToolCallExecutionPlanStatus.ready => 'ready',
    AgentToolCallExecutionPlanStatus.reviewRequired => 'review_required',
    AgentToolCallExecutionPlanStatus.blocked => 'blocked',
    AgentToolCallExecutionPlanStatus.failed => 'failed',
    AgentToolCallExecutionPlanStatus.complete => 'complete',
  };
}

enum AgentToolCallReviewDecisionStatus { approved, denied }

extension AgentToolCallReviewDecisionStatusX
    on AgentToolCallReviewDecisionStatus {
  String get wireValue => switch (this) {
    AgentToolCallReviewDecisionStatus.approved => 'approved',
    AgentToolCallReviewDecisionStatus.denied => 'denied',
  };
}

class AgentToolCallReviewDecision {
  const AgentToolCallReviewDecision({
    required this.callId,
    required this.toolId,
    required this.status,
    required this.reason,
    this.decidedAt,
  });

  const AgentToolCallReviewDecision.approved({
    required String callId,
    required String toolId,
    String reason = 'User approved this agent tool call.',
    DateTime? decidedAt,
  }) : this(
         callId: callId,
         toolId: toolId,
         status: AgentToolCallReviewDecisionStatus.approved,
         reason: reason,
         decidedAt: decidedAt,
       );

  const AgentToolCallReviewDecision.denied({
    required String callId,
    required String toolId,
    String reason = 'User denied this agent tool call.',
    DateTime? decidedAt,
  }) : this(
         callId: callId,
         toolId: toolId,
         status: AgentToolCallReviewDecisionStatus.denied,
         reason: reason,
         decidedAt: decidedAt,
       );

  final String callId;
  final String toolId;
  final AgentToolCallReviewDecisionStatus status;
  final String reason;
  final DateTime? decidedAt;

  bool get approved => status == AgentToolCallReviewDecisionStatus.approved;
  bool get denied => status == AgentToolCallReviewDecisionStatus.denied;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'callId': callId,
      'toolId': toolId,
      'status': status.wireValue,
      'reason': reason,
      if (decidedAt != null) 'decidedAt': decidedAt!.toIso8601String(),
    };
  }
}

class AgentToolCallExecutionIssue {
  const AgentToolCallExecutionIssue({
    required this.code,
    required this.message,
    this.blocking = true,
  });

  final String code;
  final String message;
  final bool blocking;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'code': code,
      'message': message,
      'blocking': blocking,
    };
  }
}

class AgentToolCallExecution {
  const AgentToolCallExecution({
    required this.callId,
    required this.toolId,
    required this.status,
    this.lifecycleStatus,
    this.permissionStatus,
    this.reviewDecisionStatus,
    this.issues = const <AgentToolCallExecutionIssue>[],
  });

  final String callId;
  final String toolId;
  final AgentToolCallExecutionStatus status;
  final AgentToolCallStatus? lifecycleStatus;
  final AgentToolPermissionDecisionStatus? permissionStatus;
  final AgentToolCallReviewDecisionStatus? reviewDecisionStatus;
  final List<AgentToolCallExecutionIssue> issues;

  bool get blocked =>
      status == AgentToolCallExecutionStatus.blocked ||
      status == AgentToolCallExecutionStatus.failed;

  List<String> get issueCodes {
    return issues.map((issue) => issue.code).toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'callId': callId,
      'toolId': toolId,
      'status': status.wireValue,
      if (lifecycleStatus != null)
        'lifecycleStatus': lifecycleStatus!.wireValue,
      if (permissionStatus != null)
        'permissionStatus': permissionStatus!.wireValue,
      if (reviewDecisionStatus != null)
        'reviewDecisionStatus': reviewDecisionStatus!.wireValue,
      'issueCodes': issueCodes,
      'issues': issues.map((issue) => issue.toJson()).toList(growable: false),
    };
  }
}

class AgentToolCallExecutionPlan {
  const AgentToolCallExecutionPlan({
    required this.status,
    required this.executions,
    this.todoItems = const <String>[],
  });

  factory AgentToolCallExecutionPlan.fromTimeline({
    required AgentToolSelection toolSelection,
    required AgentToolPermissionPlan permissionPlan,
    required AgentToolCallTimeline timeline,
    Iterable<AgentToolCallReviewDecision> reviewDecisions =
        const <AgentToolCallReviewDecision>[],
  }) {
    final reviewDecisionByCallId = <String, AgentToolCallReviewDecision>{
      for (final decision in reviewDecisions) decision.callId: decision,
    };
    final executions = <AgentToolCallExecution>[
      for (final call in timeline.calls)
        _executionFor(
          call: call,
          toolSelection: toolSelection,
          permissionPlan: permissionPlan,
          reviewDecision: reviewDecisionByCallId[call.callId],
        ),
    ];
    return AgentToolCallExecutionPlan(
      status: _planStatus(executions),
      executions: List<AgentToolCallExecution>.unmodifiable(executions),
    );
  }

  final AgentToolCallExecutionPlanStatus status;
  final List<AgentToolCallExecution> executions;
  final List<String> todoItems;

  bool get ready =>
      status == AgentToolCallExecutionPlanStatus.ready ||
      status == AgentToolCallExecutionPlanStatus.reviewRequired;

  List<String> get callIds {
    return executions
        .map((execution) => execution.callId)
        .toList(growable: false);
  }

  List<String> get blockingIssueCodes {
    return executions
        .expand(
          (execution) => execution.issues
              .where((issue) => issue.blocking)
              .map((issue) => issue.code),
        )
        .toList(growable: false);
  }

  AgentToolCallExecution? executionFor(String callId) {
    for (final execution in executions) {
      if (execution.callId == callId) {
        return execution;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'ready': ready,
      'callIds': callIds,
      'blockingIssueCodes': blockingIssueCodes,
      'executions': executions
          .map((execution) => execution.toJson())
          .toList(growable: false),
      'todoItems': todoItems,
    };
  }
}

AgentToolCallExecution _executionFor({
  required AgentToolCallState call,
  required AgentToolSelection toolSelection,
  required AgentToolPermissionPlan permissionPlan,
  required AgentToolCallReviewDecision? reviewDecision,
}) {
  final issues = <AgentToolCallExecutionIssue>[];
  final tool = _toolFor(toolSelection, call.toolId);
  final permission = _permissionFor(permissionPlan, call.toolId);

  if (tool == null) {
    issues.add(
      AgentToolCallExecutionIssue(
        code: 'agent.tool.unregistered.${call.toolId}',
        message: 'Tool ${call.toolId} is not registered for this provider.',
      ),
    );
  }
  if (permission == null) {
    issues.add(
      AgentToolCallExecutionIssue(
        code: 'agent.tool.permission.missing.${call.toolId}',
        message: 'Tool ${call.toolId} has no permission decision.',
      ),
    );
  } else if (permission.blocksDispatch) {
    issues.add(
      AgentToolCallExecutionIssue(
        code: permission.issueCode,
        message: permission.reason,
      ),
    );
  }
  if (reviewDecision?.denied ?? false) {
    issues.add(
      AgentToolCallExecutionIssue(
        code: 'agent.tool.review.denied.${call.callId}',
        message: reviewDecision!.reason.isEmpty
            ? 'Tool call ${call.callId} was denied by user review.'
            : reviewDecision.reason,
      ),
    );
  }

  if (call.status == AgentToolCallStatus.permissionBlocked) {
    issues.add(
      AgentToolCallExecutionIssue(
        code: 'agent.tool.call.permissionBlocked.${call.callId}',
        message: call.permissionReason.isEmpty
            ? 'Tool call ${call.callId} is blocked by permission.'
            : call.permissionReason,
      ),
    );
  }
  if (call.status == AgentToolCallStatus.failed) {
    issues.add(
      AgentToolCallExecutionIssue(
        code: 'agent.tool.call.failed.${call.callId}',
        message: call.errorMessage.isEmpty
            ? 'Tool call ${call.callId} failed.'
            : call.errorMessage,
      ),
    );
  }

  if (tool != null && call.inputComplete) {
    issues.addAll(_validateInput(tool, call));
  }

  return AgentToolCallExecution(
    callId: call.callId,
    toolId: call.toolId,
    status: _executionStatus(
      call: call,
      permission: permission,
      reviewDecision: reviewDecision,
      issues: issues,
    ),
    lifecycleStatus: call.status,
    permissionStatus: permission?.status,
    reviewDecisionStatus: reviewDecision?.status,
    issues: List<AgentToolCallExecutionIssue>.unmodifiable(issues),
  );
}

AgentToolDefinition? _toolFor(AgentToolSelection selection, String toolId) {
  for (final tool in selection.tools) {
    if (tool.toolId == toolId) {
      return tool;
    }
  }
  return null;
}

AgentToolPermissionDecision? _permissionFor(
  AgentToolPermissionPlan plan,
  String toolId,
) {
  for (final decision in plan.decisions) {
    if (decision.toolId == toolId) {
      return decision;
    }
  }
  return null;
}

List<AgentToolCallExecutionIssue> _validateInput(
  AgentToolDefinition tool,
  AgentToolCallState call,
) {
  final validation = const AgentToolInputValidator().validate(
    tool: tool,
    inputText: call.inputText,
  );
  return validation.issues
      .map(
        (issue) => AgentToolCallExecutionIssue(
          code: issue.code,
          message: issue.message,
        ),
      )
      .toList(growable: false);
}

AgentToolCallExecutionStatus _executionStatus({
  required AgentToolCallState call,
  required AgentToolPermissionDecision? permission,
  required AgentToolCallReviewDecision? reviewDecision,
  required List<AgentToolCallExecutionIssue> issues,
}) {
  if (call.status == AgentToolCallStatus.failed) {
    return AgentToolCallExecutionStatus.failed;
  }
  if (issues.any((issue) => issue.blocking)) {
    return AgentToolCallExecutionStatus.blocked;
  }
  if (call.status == AgentToolCallStatus.completed) {
    return AgentToolCallExecutionStatus.completed;
  }
  if (!call.inputComplete &&
      call.status == AgentToolCallStatus.inputStreaming) {
    return AgentToolCallExecutionStatus.waitingInput;
  }
  if ((permission?.requiresReview ?? false) &&
      !(reviewDecision?.approved ?? false)) {
    return AgentToolCallExecutionStatus.reviewRequired;
  }
  return AgentToolCallExecutionStatus.ready;
}

AgentToolCallExecutionPlanStatus _planStatus(
  List<AgentToolCallExecution> executions,
) {
  if (executions.isEmpty) {
    return AgentToolCallExecutionPlanStatus.idle;
  }
  if (executions.any(
    (execution) => execution.status == AgentToolCallExecutionStatus.blocked,
  )) {
    return AgentToolCallExecutionPlanStatus.blocked;
  }
  if (executions.any(
    (execution) => execution.status == AgentToolCallExecutionStatus.failed,
  )) {
    return AgentToolCallExecutionPlanStatus.failed;
  }
  if (executions.any(
    (execution) =>
        execution.status == AgentToolCallExecutionStatus.waitingInput,
  )) {
    return AgentToolCallExecutionPlanStatus.waiting;
  }
  if (executions.any(
    (execution) =>
        execution.status == AgentToolCallExecutionStatus.reviewRequired,
  )) {
    return AgentToolCallExecutionPlanStatus.reviewRequired;
  }
  if (executions.every(
    (execution) => execution.status == AgentToolCallExecutionStatus.completed,
  )) {
    return AgentToolCallExecutionPlanStatus.complete;
  }
  return AgentToolCallExecutionPlanStatus.ready;
}
