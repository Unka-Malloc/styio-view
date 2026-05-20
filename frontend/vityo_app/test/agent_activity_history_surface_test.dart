import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
  });
}
