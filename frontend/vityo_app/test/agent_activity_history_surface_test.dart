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
