import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test(
    'agent tool call execution journal captures replay candidates',
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
      final replayPlan = AgentToolCallReplayPlan.fromJournal(journal);
      final replayPlanPayload = replayPlan.toJson();
      expect(replayPlan.requests.single.inputText, '{"path":"main.styio"}');
      expect(replayPlanPayload['requiresUserConfirmation'], isTrue);
      expect(replayPlanPayload.containsKey('todoItems'), isFalse);
    },
  );

  test(
    'agent tool call execution journal can replay completed calls on demand',
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
      expect(
        AgentToolCallReplayPlan.fromJournal(journal).status,
        AgentToolCallReplayPlanStatus.blocked,
      );
      expect(
        AgentToolCallReplayPlan.fromJournal(
          journal,
        ).toJson()['requiresUserConfirmation'],
        isFalse,
      );
      expect(
        AgentToolCallReplayPlan.fromJournal(
          journal,
          includeCompleted: true,
        ).requests.single.callId,
        'call-read',
      );
    },
  );

  test(
    'agent tool call execution journal redacts persisted structured secrets',
    () {
      const entry = AgentToolCallExecutionJournalEntry(
        callId: 'call-secret',
        toolId: 'applyWorkspacePatch',
        status: AgentToolCallStatus.failed,
        inputComplete: true,
        inputText:
            '{"path":"main.styio","apiKey":"sk-secret","nested":{"authorization":"Bearer secret-token"},"items":[{"refreshToken":"refresh-secret"}]}',
        resultSample: 'provider returned token=result-secret',
        errorMessage: 'failed with Bearer error-secret',
        metadata: <String, Object?>{
          'path': 'main.styio',
          'dispatchResult': <String, Object?>{
            'metadata': <String, Object?>{
              'accessToken': 'metadata-secret',
              'normal': 'kept',
            },
          },
        },
      );

      final payload = entry.toJson();
      final encoded = jsonEncode(payload);

      expect(payload['inputLength'], entry.inputText.length);
      expect(entry.toReplayRequest().inputText, contains('sk-secret'));
      expect(encoded, contains('[redacted]'));
      expect(encoded, contains('main.styio'));
      expect(encoded, contains('kept'));
      expect(encoded, isNot(contains('sk-secret')));
      expect(encoded, isNot(contains('secret-token')));
      expect(encoded, isNot(contains('refresh-secret')));
      expect(encoded, isNot(contains('result-secret')));
      expect(encoded, isNot(contains('error-secret')));
      expect(encoded, isNot(contains('metadata-secret')));
      expect(encoded, isNot(contains('TODO')));
    },
  );

  test(
    'agent tool call execution journal redacts persisted free text secrets',
    () {
      const entry = AgentToolCallExecutionJournalEntry(
        callId: 'call-shell',
        toolId: 'runCommand',
        status: AgentToolCallStatus.failed,
        inputComplete: true,
        inputText:
            'Authorization: Bearer header-secret\npassword=hunter2\npath=main.styio',
        metadata: <String, Object?>{'command': 'test'},
      );

      final encoded = jsonEncode(entry.toJson());

      expect(encoded, contains('Bearer [redacted]'));
      expect(encoded, contains('password=[redacted]'));
      expect(encoded, contains('main.styio'));
      expect(encoded, isNot(contains('header-secret')));
      expect(encoded, isNot(contains('hunter2')));
    },
  );
}
