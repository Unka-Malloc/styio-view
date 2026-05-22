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
}
