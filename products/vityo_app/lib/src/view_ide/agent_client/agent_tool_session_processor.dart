import 'agent_provider_adapter.dart';
import 'agent_tool_call_dispatcher.dart';
import 'agent_tool_call_execution_journal.dart';
import 'agent_tool_call_execution_plan.dart';
import 'agent_tool_call_lifecycle.dart';
import 'agent_tool_call_result_context.dart';
import 'agent_tool_input_validator.dart';
import 'agent_tool_registry.dart';
import 'agent_tool_call_stream_bridge.dart';
import 'agent_tool_session_transcript.dart';

enum AgentToolResultContinuationPlanStatus { unavailable, ready }

extension AgentToolResultContinuationPlanStatusX
    on AgentToolResultContinuationPlanStatus {
  String get wireValue => switch (this) {
    AgentToolResultContinuationPlanStatus.unavailable => 'unavailable',
    AgentToolResultContinuationPlanStatus.ready => 'ready',
  };
}

class AgentToolResultContinuationPlan {
  const AgentToolResultContinuationPlan({
    required this.status,
    required this.prompt,
    required this.message,
    required this.resultCount,
    required this.failedCount,
    this.metadata = const <String, Object?>{},
  });

  const AgentToolResultContinuationPlan.unavailable({
    String message = 'No tool results are available.',
  }) : this(
         status: AgentToolResultContinuationPlanStatus.unavailable,
         prompt: '',
         message: message,
         resultCount: 0,
         failedCount: 0,
       );

  final AgentToolResultContinuationPlanStatus status;
  final String prompt;
  final String message;
  final int resultCount;
  final int failedCount;
  final Map<String, Object?> metadata;

  bool get ready => status == AgentToolResultContinuationPlanStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'ready': ready,
      'resultCount': resultCount,
      'failedCount': failedCount,
      'message': message,
      if (prompt.isNotEmpty) 'prompt': prompt,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class AgentToolSessionProcessor {
  const AgentToolSessionProcessor({
    this.lifecycleTracker = const AgentToolCallLifecycleTracker(),
    this.streamBridge = const AgentProviderToolCallStreamBridge(),
  });

  final AgentToolCallLifecycleTracker lifecycleTracker;
  final AgentProviderToolCallStreamBridge streamBridge;

  AgentToolCallTimeline applyEvent(
    AgentToolCallTimeline timeline,
    AgentToolCallEvent event,
  ) {
    return lifecycleTracker.apply(timeline, event);
  }

  AgentToolCallTimeline applyEvents(
    AgentToolCallTimeline timeline,
    Iterable<AgentToolCallEvent> events,
  ) {
    var next = timeline;
    for (final event in events) {
      next = lifecycleTracker.apply(next, event);
    }
    return next;
  }

  AgentToolCallEvent? eventForProviderStream(AgentProviderStreamEvent event) {
    return streamBridge.eventFor(event);
  }

  List<AgentToolCallEvent> eventsForProviderStream(
    Iterable<AgentProviderStreamEvent> events,
  ) {
    return streamBridge.eventsFor(events);
  }

  AgentToolCallExecutionJournal buildJournal({
    required AgentToolCallTimeline timeline,
    AgentToolCallExecutionPlan? executionPlan,
    AgentToolCallDispatchReport? dispatchReport,
  }) {
    return AgentToolCallExecutionJournal.fromTimeline(
      timeline: timeline,
      executionPlan: executionPlan,
      dispatchReport: dispatchReport,
    );
  }

  AgentToolSessionTranscript buildTranscript({
    required AgentToolCallTimeline timeline,
    required AgentToolCallExecutionPlan executionPlan,
    Iterable<AgentToolCallResultContext> resultContexts =
        const <AgentToolCallResultContext>[],
  }) {
    return AgentToolSessionTranscript.fromToolState(
      timeline: timeline,
      executionPlan: executionPlan,
      resultContexts: resultContexts,
    );
  }

  Future<AgentToolCallDispatchReport> dispatchReady({
    required AgentToolCallExecutionPlan executionPlan,
    required AgentToolCallTimeline timeline,
    required AgentToolCallExecutor executor,
    AgentToolSelection? toolSelection,
    AgentToolCallDispatcher dispatcher = const AgentToolCallDispatcher(),
  }) async {
    final blockedInputResults = blockedToolInputResults(executionPlan);
    if (blockedInputResults.isNotEmpty) {
      final events = blockedInputResults
          .map((result) => result.toLifecycleEvent())
          .toList(growable: false);
      return AgentToolCallDispatchReport(
        status: AgentToolCallDispatchReportStatus.failed,
        plan: AgentToolCallDispatchPlan.fromExecutionPlan(executionPlan),
        results: List<AgentToolCallDispatchResult>.unmodifiable(
          blockedInputResults,
        ),
        events: List<AgentToolCallEvent>.unmodifiable(events),
      );
    }
    return dispatcher.dispatchReady(
      executionPlan: executionPlan,
      timeline: timeline,
      executor: executor,
      toolSelection: toolSelection,
    );
  }

  List<AgentToolCallDispatchResult> blockedToolInputResults(
    AgentToolCallExecutionPlan executionPlan,
  ) {
    final results = <AgentToolCallDispatchResult>[];
    for (final execution in executionPlan.executions) {
      if (execution.status != AgentToolCallExecutionStatus.blocked) {
        continue;
      }
      final inputIssues = execution.issues
          .where(_isToolInputIssue)
          .toList(growable: false);
      if (inputIssues.isEmpty) {
        continue;
      }
      final message = _blockedToolInputMessage(execution, inputIssues);
      results.add(
        AgentToolCallDispatchResult.failure(
          callId: execution.callId,
          toolId: execution.toolId,
          message: message,
          output: message,
          metadata: <String, Object?>{
            'source': 'agent-tool-input-validation',
            'blocked': true,
            'issueCodes': inputIssues
                .map((issue) => issue.code)
                .toList(growable: false),
          },
        ),
      );
    }
    return List<AgentToolCallDispatchResult>.unmodifiable(results);
  }

  Future<AgentToolCallReplayReport> replayJournal({
    required AgentToolCallExecutionJournal journal,
    required AgentToolCallExecutor executor,
    bool includeCompleted = false,
    AgentToolSelection? toolSelection,
  }) async {
    final plan = AgentToolCallReplayPlan.fromJournal(
      journal,
      includeCompleted: includeCompleted,
    );
    if (!plan.ready) {
      return AgentToolCallReplayReport(
        status: AgentToolCallReplayReportStatus.blocked,
        plan: plan,
      );
    }

    final results = <AgentToolCallDispatchResult>[];
    final events = <AgentToolCallEvent>[];
    for (final request in plan.requests) {
      late final AgentToolCallDispatchResult result;
      try {
        final rawResult = await Future<AgentToolCallDispatchResult>.value(
          executor(request),
        );
        result = _validatedToolReplayResult(
          result: _toolReplayResultWithMetadata(rawResult, request),
          request: request,
          toolSelection: toolSelection,
        );
      } on Object catch (error) {
        result = AgentToolCallDispatchResult.failure(
          callId: request.callId,
          toolId: request.toolId,
          message: 'Agent tool replay ${request.callId} failed: $error',
          metadata: _toolReplayMetadata(request),
        );
      }
      results.add(result);
      events.add(result.toLifecycleEvent());
    }
    return AgentToolCallReplayReport.fromResults(
      plan: plan,
      results: results,
      events: events,
    );
  }

  AgentToolResultContinuationPlan buildContinuationPlan({
    required Iterable<AgentToolCallResultContext> resultContexts,
    String? prompt,
  }) {
    final results = resultContexts.toList(growable: false);
    if (results.isEmpty) {
      return const AgentToolResultContinuationPlan.unavailable();
    }
    final failedCount = results.where((result) => !result.success).length;
    final resultCount = results.length;
    final normalizedPrompt = prompt?.trim();
    return AgentToolResultContinuationPlan(
      status: AgentToolResultContinuationPlanStatus.ready,
      prompt: normalizedPrompt == null || normalizedPrompt.isEmpty
          ? _toolResultContinuationPrompt(
              resultCount: resultCount,
              failedCount: failedCount,
            )
          : normalizedPrompt,
      message: 'Agent tool continuation is ready.',
      resultCount: resultCount,
      failedCount: failedCount,
      metadata: <String, Object?>{
        'toolResultContinuation': true,
        'toolResultContinuationCount': resultCount,
        'toolResultContinuationFailedCount': failedCount,
        'toolResultContinuationCallIds': results
            .map((result) => result.callId)
            .toList(growable: false),
      },
    );
  }

  AgentToolCallDispatchResult reviewDeniedResult({
    required AgentToolCallState call,
    required String reason,
  }) {
    final feedback = reason.trim().isEmpty
        ? 'User denied this agent tool call.'
        : reason.trim();
    final output = <String>[
      'Agent tool call denied by user review.',
      'callId: ${call.callId}',
      'toolId: ${call.toolId}',
      'correctiveFeedback: $feedback',
      'recoveryAction: reviseToolRequest',
    ].join('\n');
    return AgentToolCallDispatchResult.failure(
      callId: call.callId,
      toolId: call.toolId,
      message: feedback,
      output: output,
      metadata: <String, Object?>{
        'source': 'agent-tool-review',
        'blocked': true,
        'reviewDecision': 'denied',
        'correctiveFeedback': feedback,
        'recoveryAction': 'reviseToolRequest',
      },
    );
  }
}

AgentToolCallDispatchResult _validatedToolReplayResult({
  required AgentToolCallDispatchResult result,
  required AgentToolCallDispatchRequest request,
  required AgentToolSelection? toolSelection,
}) {
  if (!result.success || toolSelection == null) {
    return result;
  }
  final tool = _toolForReplay(toolSelection, request.toolId);
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
      ..._toolReplayMetadata(request),
      'source': 'agent-tool-result-validation',
    },
  );
}

AgentToolDefinition? _toolForReplay(
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

bool _isToolInputIssue(AgentToolCallExecutionIssue issue) {
  return issue.code.startsWith('agent.tool.input.');
}

String _blockedToolInputMessage(
  AgentToolCallExecution execution,
  List<AgentToolCallExecutionIssue> inputIssues,
) {
  final detail = inputIssues.map((issue) => issue.message).join(' ');
  return 'The ${execution.toolId} tool was called with invalid arguments: '
      '$detail Please rewrite the input so it satisfies the expected schema.';
}

AgentToolCallDispatchResult _toolReplayResultWithMetadata(
  AgentToolCallDispatchResult result,
  AgentToolCallDispatchRequest request,
) {
  final metadata = <String, Object?>{
    ...result.metadata,
    ..._toolReplayMetadata(request),
  };
  return AgentToolCallDispatchResult(
    callId: result.callId,
    toolId: result.toolId,
    success: result.success,
    message: result.message,
    output: result.output,
    metadata: metadata,
  );
}

Map<String, Object?> _toolReplayMetadata(AgentToolCallDispatchRequest request) {
  return <String, Object?>{
    'replayedFromJournal': true,
    'replayCallId': request.callId,
    'replayToolId': request.toolId,
  };
}

String _toolResultContinuationPrompt({
  required int resultCount,
  required int failedCount,
}) {
  final failed = failedCount == 0
      ? ''
      : ' $failedCount result(s) failed; explain the failure and propose a recovery step.';
  return 'Continue after $resultCount agent tool result(s). '
      'Use the attached tool results as the source of truth, summarize the outcome, and propose the next IDE action.$failed';
}
