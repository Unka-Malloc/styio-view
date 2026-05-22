import 'agent_tool_call_dispatcher.dart';
import 'agent_tool_call_execution_journal.dart';
import 'agent_tool_call_execution_plan.dart';
import 'agent_tool_call_lifecycle.dart';
import 'agent_tool_call_result_context.dart';
import 'agent_tool_session_transcript.dart';

class AgentToolSessionProcessor {
  const AgentToolSessionProcessor({
    this.lifecycleTracker = const AgentToolCallLifecycleTracker(),
  });

  final AgentToolCallLifecycleTracker lifecycleTracker;

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

  AgentToolCallExecutionJournal buildJournal({
    required AgentToolCallTimeline timeline,
    AgentToolCallDispatchReport? dispatchReport,
  }) {
    return AgentToolCallExecutionJournal.fromTimeline(
      timeline: timeline,
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
        result = _toolReplayResultWithMetadata(rawResult, request);
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
