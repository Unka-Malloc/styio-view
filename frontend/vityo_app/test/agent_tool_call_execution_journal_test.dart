import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('agent tool call execution journal captures replay candidates', () async {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final selection = AgentToolRegistry().selectForProfile(
      profile: profile,
      providerKind: AgentProviderKind.localOnlyFallback,
    );
    final permissions = AgentToolPermissionPlan.fromSelection(selection);
    const tracker = AgentToolCallLifecycleTracker();
    const events = <AgentToolCallEvent>[
      AgentToolCallEvent.callStarted(
        callId: 'call-read',
        toolId: 'readWorkspaceFile',
        input: '{"path":"main.styio"}',
      ),
    ];
    final timeline = tracker.track(events);
    final executionPlan = AgentToolCallExecutionPlan.fromTimeline(
      toolSelection: selection,
      permissionPlan: permissions,
      timeline: timeline,
    );
    final report = await const AgentToolCallDispatcher().dispatchReady(
      executionPlan: executionPlan,
      timeline: timeline,
      executor: (request) => AgentToolCallDispatchResult.failure(
        callId: request.callId,
        toolId: request.toolId,
        message: 'workspace store unavailable',
      ),
    );
    final failedTimeline = tracker.track(<AgentToolCallEvent>[
      ...events,
      ...report.events,
    ]);

    final journal = AgentToolCallExecutionJournal.fromTimeline(
      timeline: failedTimeline,
      dispatchReport: report,
      sourceEventCount: events.length + report.events.length,
    );
    final replayRequest = journal.replayRequests().single;
    final payload = journal.toJson();

    expect(journal.status, AgentToolCallExecutionJournalStatus.failed);
    expect(journal.replayCandidates.single.callId, 'call-read');
    expect(replayRequest.toolId, 'readWorkspaceFile');
    expect(replayRequest.inputText, '{"path":"main.styio"}');
    expect(replayRequest.metadata['replayedFromJournal'], isTrue);
    expect(payload['replayCandidateCount'], 1);
    expect(payload['sourceEventCount'], 2);
    expect(
      (payload['entries'] as List<Object?>).single,
      isA<Map<Object?, Object?>>(),
    );
  });

  test('agent tool call execution journal can replay completed calls on demand',
      () async {
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final selection = AgentToolRegistry().selectForProfile(
      profile: profile,
      providerKind: AgentProviderKind.localOnlyFallback,
    );
    final permissions = AgentToolPermissionPlan.fromSelection(selection);
    const tracker = AgentToolCallLifecycleTracker();
    const events = <AgentToolCallEvent>[
      AgentToolCallEvent.callStarted(
        callId: 'call-read',
        toolId: 'readWorkspaceFile',
        input: '{"path":"main.styio"}',
      ),
    ];
    final timeline = tracker.track(events);
    final executionPlan = AgentToolCallExecutionPlan.fromTimeline(
      toolSelection: selection,
      permissionPlan: permissions,
      timeline: timeline,
    );
    final report = await const AgentToolCallDispatcher().dispatchReady(
      executionPlan: executionPlan,
      timeline: timeline,
      executor: (request) => AgentToolCallDispatchResult.success(
        callId: request.callId,
        toolId: request.toolId,
        output: '{"document":"ok"}',
      ),
    );
    final completedTimeline = tracker.track(<AgentToolCallEvent>[
      ...events,
      ...report.events,
    ]);

    final journal = AgentToolCallExecutionJournal.fromTimeline(
      timeline: completedTimeline,
      dispatchReport: report,
    );

    expect(journal.status, AgentToolCallExecutionJournalStatus.complete);
    expect(journal.replayCandidates, isEmpty);
    expect(journal.replayRequests(), isEmpty);
    expect(journal.replayRequests(includeCompleted: true).single.callId, 'call-read');
  });
}
