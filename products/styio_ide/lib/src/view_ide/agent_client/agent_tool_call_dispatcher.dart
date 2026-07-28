import 'dart:async';

import 'agent_tool_call_execution_plan.dart';
import 'agent_tool_call_lifecycle.dart';
import 'agent_tool_input_validator.dart';
import 'agent_tool_registry.dart';

typedef AgentToolCallExecutor =
    FutureOr<AgentToolCallDispatchResult> Function(
      AgentToolCallDispatchRequest request,
    );

enum AgentToolCallDispatchPlanStatus {
  idle,
  waitingInput,
  waitingReview,
  ready,
  blocked,
  failed,
  complete,
}

extension AgentToolCallDispatchPlanStatusX on AgentToolCallDispatchPlanStatus {
  String get wireValue => switch (this) {
    AgentToolCallDispatchPlanStatus.idle => 'idle',
    AgentToolCallDispatchPlanStatus.waitingInput => 'waiting_input',
    AgentToolCallDispatchPlanStatus.waitingReview => 'waiting_review',
    AgentToolCallDispatchPlanStatus.ready => 'ready',
    AgentToolCallDispatchPlanStatus.blocked => 'blocked',
    AgentToolCallDispatchPlanStatus.failed => 'failed',
    AgentToolCallDispatchPlanStatus.complete => 'complete',
  };
}

enum AgentToolCallDispatchReportStatus {
  idle,
  waiting,
  blocked,
  failed,
  dispatched,
  complete,
}

extension AgentToolCallDispatchReportStatusX
    on AgentToolCallDispatchReportStatus {
  String get wireValue => switch (this) {
    AgentToolCallDispatchReportStatus.idle => 'idle',
    AgentToolCallDispatchReportStatus.waiting => 'waiting',
    AgentToolCallDispatchReportStatus.blocked => 'blocked',
    AgentToolCallDispatchReportStatus.failed => 'failed',
    AgentToolCallDispatchReportStatus.dispatched => 'dispatched',
    AgentToolCallDispatchReportStatus.complete => 'complete',
  };
}

class AgentToolCallDispatchRequest {
  const AgentToolCallDispatchRequest({
    required this.callId,
    required this.toolId,
    required this.inputText,
    this.metadata = const <String, Object?>{},
  });

  final String callId;
  final String toolId;
  final String inputText;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'callId': callId,
      'toolId': toolId,
      'inputLength': inputText.length,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class AgentToolCallDispatchResult {
  const AgentToolCallDispatchResult({
    required this.callId,
    required this.toolId,
    required this.success,
    required this.message,
    this.output = '',
    this.metadata = const <String, Object?>{},
  });

  const AgentToolCallDispatchResult.success({
    required String callId,
    required String toolId,
    required String output,
    String message = 'Agent tool call completed.',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         callId: callId,
         toolId: toolId,
         success: true,
         message: message,
         output: output,
         metadata: metadata,
       );

  const AgentToolCallDispatchResult.failure({
    required String callId,
    required String toolId,
    required String message,
    String output = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : this(
         callId: callId,
         toolId: toolId,
         success: false,
         message: message,
         output: output,
         metadata: metadata,
       );

  final String callId;
  final String toolId;
  final bool success;
  final String message;
  final String output;
  final Map<String, Object?> metadata;

  AgentToolCallEvent toLifecycleEvent() {
    if (success) {
      return AgentToolCallEvent.result(
        callId: callId,
        toolId: toolId,
        result: output.isEmpty ? message : output,
        metadata: metadata,
      );
    }
    return AgentToolCallEvent.error(
      callId: callId,
      toolId: toolId,
      errorMessage: message,
      metadata: metadata,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'callId': callId,
      'toolId': toolId,
      'success': success,
      'message': message,
      if (output.isNotEmpty) 'outputLength': output.length,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class AgentToolCallDispatchPlan {
  const AgentToolCallDispatchPlan({
    required this.status,
    required this.readyExecutions,
    required this.blockingIssueCodes,
  });

  factory AgentToolCallDispatchPlan.fromExecutionPlan(
    AgentToolCallExecutionPlan executionPlan,
  ) {
    final readyExecutions = executionPlan.executions
        .where(
          (execution) => execution.status == AgentToolCallExecutionStatus.ready,
        )
        .toList(growable: false);
    return AgentToolCallDispatchPlan(
      status: _dispatchPlanStatus(executionPlan, readyExecutions),
      readyExecutions: List<AgentToolCallExecution>.unmodifiable(
        readyExecutions,
      ),
      blockingIssueCodes: executionPlan.blockingIssueCodes,
    );
  }

  final AgentToolCallDispatchPlanStatus status;
  final List<AgentToolCallExecution> readyExecutions;
  final List<String> blockingIssueCodes;

  bool get ready =>
      status == AgentToolCallDispatchPlanStatus.ready &&
      readyExecutions.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'ready': ready,
      'readyCallIds': readyExecutions
          .map((execution) => execution.callId)
          .toList(growable: false),
      'blockingIssueCodes': blockingIssueCodes,
    };
  }
}

class AgentToolCallDispatchReport {
  const AgentToolCallDispatchReport({
    required this.status,
    required this.plan,
    this.results = const <AgentToolCallDispatchResult>[],
    this.events = const <AgentToolCallEvent>[],
  });

  final AgentToolCallDispatchReportStatus status;
  final AgentToolCallDispatchPlan plan;
  final List<AgentToolCallDispatchResult> results;
  final List<AgentToolCallEvent> events;

  bool get dispatched => status == AgentToolCallDispatchReportStatus.dispatched;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'dispatched': dispatched,
      'plan': plan.toJson(),
      'results': results.map((result) => result.toJson()).toList(),
      'eventCount': events.length,
    };
  }
}

class AgentToolCallDispatcher {
  const AgentToolCallDispatcher();

  Future<AgentToolCallDispatchReport> dispatchReady({
    required AgentToolCallExecutionPlan executionPlan,
    required AgentToolCallTimeline timeline,
    required AgentToolCallExecutor executor,
    AgentToolSelection? toolSelection,
  }) async {
    final dispatchPlan = AgentToolCallDispatchPlan.fromExecutionPlan(
      executionPlan,
    );
    if (!dispatchPlan.ready) {
      return AgentToolCallDispatchReport(
        status: _blockedReportStatus(dispatchPlan.status),
        plan: dispatchPlan,
      );
    }

    final results = <AgentToolCallDispatchResult>[];
    final events = <AgentToolCallEvent>[];
    for (final execution in dispatchPlan.readyExecutions) {
      final call = timeline.callFor(execution.callId);
      late final AgentToolCallDispatchResult result;
      if (call == null) {
        result = AgentToolCallDispatchResult.failure(
          callId: execution.callId,
          toolId: execution.toolId,
          message:
              'Agent tool call ${execution.callId} cannot dispatch because lifecycle state is missing.',
        );
      } else {
        final request = AgentToolCallDispatchRequest(
          callId: call.callId,
          toolId: call.toolId,
          inputText: call.inputText,
          metadata: call.metadata,
        );
        try {
          result = await Future<AgentToolCallDispatchResult>.value(
            executor(request),
          );
        } on Object catch (error) {
          result = AgentToolCallDispatchResult.failure(
            callId: call.callId,
            toolId: call.toolId,
            message: 'Agent tool call ${call.callId} failed: $error',
          );
        }
      }
      final validatedResult = _validatedDispatchResult(
        result: result,
        toolSelection: toolSelection,
      );
      results.add(validatedResult);
      events.add(validatedResult.toLifecycleEvent());
    }

    return AgentToolCallDispatchReport(
      status: results.every((result) => result.success)
          ? AgentToolCallDispatchReportStatus.dispatched
          : AgentToolCallDispatchReportStatus.failed,
      plan: dispatchPlan,
      results: List<AgentToolCallDispatchResult>.unmodifiable(results),
      events: List<AgentToolCallEvent>.unmodifiable(events),
    );
  }
}

AgentToolCallDispatchResult _validatedDispatchResult({
  required AgentToolCallDispatchResult result,
  required AgentToolSelection? toolSelection,
}) {
  if (!result.success || toolSelection == null) {
    return result;
  }
  final tool = _toolForResult(toolSelection, result.toolId);
  if (tool == null || tool.resultSchema.isEmpty) {
    return result;
  }
  final validation = const AgentToolResultValidator().validate(
    tool: tool,
    outputText: result.output,
  );
  final metadata = <String, Object?>{
    ...result.metadata,
    'resultValidation': validation.toJson(),
  };
  if (validation.valid) {
    return AgentToolCallDispatchResult.success(
      callId: result.callId,
      toolId: result.toolId,
      output: result.output,
      message: result.message,
      metadata: metadata,
    );
  }
  return AgentToolCallDispatchResult.failure(
    callId: result.callId,
    toolId: result.toolId,
    message: validation.modelFacingMessage,
    output: result.output,
    metadata: <String, Object?>{
      ...metadata,
      'source': 'agent-tool-result-validation',
    },
  );
}

AgentToolDefinition? _toolForResult(
  AgentToolSelection selection,
  String toolId,
) {
  for (final tool in selection.tools) {
    if (tool.toolId == toolId) {
      return tool;
    }
  }
  return null;
}

AgentToolCallDispatchPlanStatus _dispatchPlanStatus(
  AgentToolCallExecutionPlan executionPlan,
  List<AgentToolCallExecution> readyExecutions,
) {
  return switch (executionPlan.status) {
    AgentToolCallExecutionPlanStatus.idle =>
      AgentToolCallDispatchPlanStatus.idle,
    AgentToolCallExecutionPlanStatus.waiting =>
      AgentToolCallDispatchPlanStatus.waitingInput,
    AgentToolCallExecutionPlanStatus.reviewRequired =>
      AgentToolCallDispatchPlanStatus.waitingReview,
    AgentToolCallExecutionPlanStatus.blocked =>
      AgentToolCallDispatchPlanStatus.blocked,
    AgentToolCallExecutionPlanStatus.failed =>
      AgentToolCallDispatchPlanStatus.failed,
    AgentToolCallExecutionPlanStatus.complete =>
      AgentToolCallDispatchPlanStatus.complete,
    AgentToolCallExecutionPlanStatus.ready =>
      readyExecutions.isEmpty
          ? AgentToolCallDispatchPlanStatus.waitingReview
          : AgentToolCallDispatchPlanStatus.ready,
  };
}

AgentToolCallDispatchReportStatus _blockedReportStatus(
  AgentToolCallDispatchPlanStatus status,
) {
  return switch (status) {
    AgentToolCallDispatchPlanStatus.idle =>
      AgentToolCallDispatchReportStatus.idle,
    AgentToolCallDispatchPlanStatus.blocked =>
      AgentToolCallDispatchReportStatus.blocked,
    AgentToolCallDispatchPlanStatus.failed =>
      AgentToolCallDispatchReportStatus.failed,
    AgentToolCallDispatchPlanStatus.complete =>
      AgentToolCallDispatchReportStatus.complete,
    _ => AgentToolCallDispatchReportStatus.waiting,
  };
}
