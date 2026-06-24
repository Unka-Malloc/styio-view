import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_render/platform/viewport_profile.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_render/agent/agent.dart';

void main() {
  testWidgets('agent activity history surface renders empty state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentActivityHistorySurface(
            history: AgentCodingSessionHistory(workspaceId: 'demo'),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('agent-activity-history-surface')),
      findsOneWidget,
    );
    expect(find.text('No persisted agent coding sessions yet.'), findsOne);
  });

  testWidgets('agent activity history surface renders recent records', (
    tester,
  ) async {
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[
        AgentCodingSessionHistoryRecord(
          requestId: 'agent-1',
          profileId: 'default-agent',
          providerKind: 'cloud_openai_compatible',
          prompt: 'Implement language diagnostics.',
          outcome: AgentCodingSessionOutcome.succeeded,
          createdAt: DateTime.utc(2026, 5, 20),
          completedAt: DateTime.utc(2026, 5, 20, 0, 1),
          responseTextSample: 'Diagnostics are wired.',
          contentPartCount: 2,
          patchCount: 1,
          ideCommandCount: 1,
          planCount: 1,
          diagnosticSummaryCount: 1,
          metadata: const <String, Object?>{
            'validationResult': <String, Object?>{
              'status': 'failed',
              'completedCommandIds': <String>['saveAll'],
              'failedCommandIds': <String>['runTests'],
            },
            'validationPipeline': <String, Object?>{
              'status': 'failed',
              'progressNumerator': 1,
              'progressDenominator': 5,
            },
            'validationFailedCommandResults': <Object?>[
              <String, Object?>{
                'commandId': 'runTests',
                'applied': false,
                'message': 'runTests failed.',
              },
            ],
          },
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AgentActivityHistorySurface(history: history)),
      ),
    );

    expect(find.text('Agent Activity'), findsOneWidget);
    expect(find.text('Implement language diagnostics.'), findsOneWidget);
    expect(find.text('succeeded'), findsOneWidget);
    expect(find.text('patches 1'), findsOneWidget);
    expect(find.text('commands 1'), findsOneWidget);
    expect(find.text('diagnostics 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-activity-validation-summary')),
      findsOneWidget,
    );
    expect(
      find.text('Validation: failed · pipeline failed 1/5'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-activity-validation-failure-evidence')),
      findsOneWidget,
    );
    expect(
      find.text('Failure evidence: runTests · runTests failed.'),
      findsOneWidget,
    );
  });

  testWidgets('agent activity history surface renders failed record reason', (
    tester,
  ) async {
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[
        AgentCodingSessionHistoryRecord.failure(
          requestId: 'agent-failed',
          profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
          providerKind: AgentProviderKind.cloudOpenAICompatible,
          prompt: 'Fix parser diagnostics.',
          errorMessage: 'provider timed out',
          createdAt: DateTime.utc(2026, 5, 20),
          completedAt: DateTime.utc(2026, 5, 20, 0, 1),
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AgentActivityHistorySurface(history: history)),
      ),
    );

    expect(find.text('Fix parser diagnostics.'), findsOneWidget);
    expect(find.text('failed'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-activity-record-error')),
      findsOneWidget,
    );
    expect(find.text('Error: provider timed out'), findsOneWidget);
  });

  testWidgets('agent activity history surface renders tool call journal', (
    tester,
  ) async {
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[
        AgentCodingSessionHistoryRecord(
          requestId: 'agent-tools',
          profileId: 'default-agent',
          providerKind: 'cloud_openai_compatible',
          prompt: 'Use workspace tools.',
          outcome: AgentCodingSessionOutcome.succeeded,
          createdAt: DateTime.utc(2026, 5, 20),
          completedAt: DateTime.utc(2026, 5, 20, 0, 1),
          metadata: const <String, Object?>{
            'toolCallExecutionJournal': <String, Object?>{
              'status': 'failed',
              'entryCount': 2,
              'sourceEventCount': 4,
              'replayCandidateCount': 1,
              'entries': <Object?>[
                <String, Object?>{
                  'callId': 'tool-1',
                  'toolId': 'workspace.patch',
                  'status': 'completed',
                },
                <String, Object?>{
                  'callId': 'tool-2',
                  'toolId': 'workspace.test',
                  'status': 'failed',
                  'errorMessage': 'tests failed',
                },
              ],
            },
          },
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AgentActivityHistorySurface(history: history)),
      ),
    );

    expect(
      find.byKey(const ValueKey('agent-activity-tool-call-summary')),
      findsOneWidget,
    );
    expect(
      find.text('Tool calls: failed · 2 entries · 1 replayable · 4 event(s)'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-activity-tool-call-failure-evidence')),
      findsOneWidget,
    );
    expect(
      find.text('Tool call evidence: workspace.test · failed · tests failed'),
      findsOneWidget,
    );
  });

  testWidgets('agent activity history surface renders tool session transcript', (
    tester,
  ) async {
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[
        AgentCodingSessionHistoryRecord(
          requestId: 'agent-tool-transcript',
          profileId: 'default-agent',
          providerKind: 'cloud_openai_compatible',
          prompt: 'Review tool transcript.',
          outcome: AgentCodingSessionOutcome.succeeded,
          createdAt: DateTime.utc(2026, 5, 20),
          completedAt: DateTime.utc(2026, 5, 20, 0, 1),
          metadata: const <String, Object?>{
            'toolSessionTranscript': <String, Object?>{
              'status': 'complete',
              'partCount': 2,
              'parts': <Object?>[
                <String, Object?>{
                  'callId': 'call-read',
                  'toolId': 'readWorkspaceFile',
                  'status': 'completed',
                },
                <String, Object?>{
                  'callId': 'call-write',
                  'toolId': 'writeWorkspaceFile',
                  'status': 'failed',
                },
              ],
            },
          },
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AgentActivityHistorySurface(history: history)),
      ),
    );

    expect(
      find.byKey(
        const ValueKey('agent-activity-tool-session-transcript-summary'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Tool transcript: complete · 2 parts · failed 1 · tools readWorkspaceFile, writeWorkspaceFile',
      ),
      findsOneWidget,
    );
  });

  testWidgets('agent activity history surface renders tool continuation', (
    tester,
  ) async {
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[
        AgentCodingSessionHistoryRecord(
          requestId: 'agent-tool-continuation',
          profileId: 'default-agent',
          providerKind: 'cloud_openai_compatible',
          prompt: 'Continue after tool results.',
          outcome: AgentCodingSessionOutcome.succeeded,
          createdAt: DateTime.utc(2026, 5, 20),
          completedAt: DateTime.utc(2026, 5, 20, 0, 1),
          metadata: const <String, Object?>{
            'toolResultContinuation': true,
            'toolResultContinuationCount': 2,
            'toolResultContinuationFailedCount': 1,
            'toolResultContinuationCallIds': <String>['call-read', 'call-test'],
          },
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AgentActivityHistorySurface(history: history)),
      ),
    );

    expect(
      find.byKey(const ValueKey('agent-activity-tool-continuation-summary')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Tool continuation: 2 result(s) · failed 1 · calls call-read, call-test',
      ),
      findsOneWidget,
    );
  });

  testWidgets('agent activity history surface restores prompt from record', (
    tester,
  ) async {
    AgentCodingSessionHistoryRecord? restoredRecord;
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[
        AgentCodingSessionHistoryRecord(
          requestId: 'agent-restore',
          profileId: 'default-agent',
          providerKind: 'local_only_fallback',
          prompt: 'Replay this prompt.',
          outcome: AgentCodingSessionOutcome.failed,
          createdAt: DateTime.utc(2026, 5, 20),
          completedAt: DateTime.utc(2026, 5, 20, 0, 1),
          errorMessage: 'provider failed',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentActivityHistorySurface(
            history: history,
            onRestorePrompt: (record) {
              restoredRecord = record;
            },
          ),
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('agent-activity-restore-prompt-agent-restore')),
    );
    await tester.pump();

    expect(restoredRecord?.requestId, 'agent-restore');
    expect(restoredRecord?.prompt, 'Replay this prompt.');
  });

  testWidgets('agent activity history surface renders blocked validation plan', (
    tester,
  ) async {
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[
        AgentCodingSessionHistoryRecord(
          requestId: 'agent-validation-blocked',
          profileId: 'default-agent',
          providerKind: 'cloud_openai_compatible',
          prompt: 'Apply generated edits.',
          outcome: AgentCodingSessionOutcome.failed,
          createdAt: DateTime.utc(2026, 5, 20),
          completedAt: DateTime.utc(2026, 5, 20, 0, 1),
          errorMessage: 'Agent coding validation is blocked.',
          metadata: const <String, Object?>{
            'validationPlan': <String, Object?>{
              'status': 'blocked',
              'reason':
                  'Agent coding validation is blocked by autonomy policy.',
            },
          },
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: AgentActivityHistorySurface(history: history)),
      ),
    );

    expect(
      find.byKey(const ValueKey('agent-activity-validation-summary')),
      findsOneWidget,
    );
    expect(
      find.text(
        'Validation: plan blocked · Agent coding validation is blocked by autonomy policy.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('agent surface embeds activity history when provided', (
    tester,
  ) async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[
        AgentCodingSessionHistoryRecord(
          requestId: 'agent-embedded',
          profileId: 'default-agent',
          providerKind: 'local_only_fallback',
          prompt: 'Review the workspace.',
          outcome: AgentCodingSessionOutcome.succeeded,
          createdAt: DateTime.utc(2026, 5, 20),
          completedAt: DateTime.utc(2026, 5, 20, 0, 1),
          responseTextSample: 'Workspace reviewed.',
          contentPartCount: 1,
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentSurface(
            platformTarget: PlatformTarget.web,
            viewportProfile: const ViewportProfile(
              family: ViewportFamily.desktop,
              width: 1200,
              height: 900,
            ),
            visibleModules: const [],
            adapterCapabilities: const [],
            sessionContext: _context(),
            codingController: controller,
            activityHistory: history,
            onApplyPendingPatch: () async {},
            onSaveProviderProfile: (profile, {bearerToken}) async {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('agent-activity-history-surface')),
      findsOneWidget,
    );
    expect(find.text('Review the workspace.'), findsOneWidget);
  });

  testWidgets('agent surface binds activity history from controller snapshot', (
    tester,
  ) async {
    final history = AgentCodingSessionHistory(
      workspaceId: 'demo',
      records: <AgentCodingSessionHistoryRecord>[
        AgentCodingSessionHistoryRecord(
          requestId: 'agent-controller-history',
          profileId: 'default-agent',
          providerKind: 'local_only_fallback',
          prompt: 'Use controller history.',
          outcome: AgentCodingSessionOutcome.succeeded,
          createdAt: DateTime.utc(2026, 5, 20),
          completedAt: DateTime.utc(2026, 5, 20, 0, 1),
          responseTextSample: 'Controller history loaded.',
          contentPartCount: 1,
        ),
      ],
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
      sessionHistoryStore: _MemoryAgentCodingSessionHistoryStore(history),
      sessionHistoryWorkspaceId: 'demo',
    );
    addTearDown(controller.dispose);
    await controller.loadSessionHistory();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentSurface(
            platformTarget: PlatformTarget.web,
            viewportProfile: const ViewportProfile(
              family: ViewportFamily.desktop,
              width: 1200,
              height: 900,
            ),
            visibleModules: const [],
            adapterCapabilities: const [],
            sessionContext: _context(),
            codingController: controller,
            onApplyPendingPatch: () async {},
            onSaveProviderProfile: (profile, {bearerToken}) async {},
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('agent-activity-history-surface')),
      findsOneWidget,
    );
    expect(find.text('Use controller history.'), findsOneWidget);

    final restorePromptButton = find.byKey(
      const ValueKey('agent-activity-restore-prompt-agent-controller-history'),
    );
    await tester.ensureVisible(restorePromptButton);
    await tester.pumpAndSettle();
    await tester.tap(restorePromptButton);
    await tester.pump();

    expect(controller.draftPrompt, 'Use controller history.');
  });
}

class _MemoryAgentCodingSessionHistoryStore
    implements AgentCodingSessionHistoryStore {
  _MemoryAgentCodingSessionHistoryStore(this.history);

  AgentCodingSessionHistory history;

  @override
  Future<AgentCodingSessionHistory> readHistory({
    required String workspaceId,
  }) async {
    return history.workspaceId == workspaceId
        ? history
        : AgentCodingSessionHistory(workspaceId: workspaceId);
  }

  @override
  Future<AgentCodingSessionHistory> appendRecord({
    required String workspaceId,
    required AgentCodingSessionHistoryRecord record,
    int maxEntries = 50,
  }) async {
    final current = await readHistory(workspaceId: workspaceId);
    history = current.append(record, maxEntries: maxEntries);
    return history;
  }

  @override
  Future<AgentCodingSessionCheckpoint> readCheckpoint({
    required String workspaceId,
  }) async {
    return (await readHistory(workspaceId: workspaceId)).toCheckpoint();
  }

  @override
  Future<AgentCodingSessionRecoveryPlan> readRecoveryPlan({
    required String workspaceId,
  }) async {
    return (await readHistory(workspaceId: workspaceId)).toRecoveryPlan();
  }

  @override
  Future<AgentCodingSessionRecoveryContext> readRecoveryContext({
    required String workspaceId,
    String? targetProviderProfileKey,
    String? targetProviderProfileId,
  }) async {
    return (await readHistory(workspaceId: workspaceId)).toRecoveryContext(
      targetProviderProfileKey:
          targetProviderProfileKey ?? targetProviderProfileId,
    );
  }

  @override
  Future<void> saveHistory(AgentCodingSessionHistory history) async {
    this.history = history;
  }
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
