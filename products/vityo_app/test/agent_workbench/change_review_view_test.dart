import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/workbench/agent_collaboration/collaboration_store.dart';
import 'package:vityo_app/src/ide/workspace/workspace_change_set.dart';
import 'package:vityo_app/src/ide/workspace/workspace_transaction_service.dart';
import 'package:vityo_app/src/presentation/agent_workbench/change_review_view.dart';

void main() {
  testWidgets('replacement previews remain bounded', (tester) async {
    final replacement = List<String>.filled(600, 'x').join();
    final review = AgentChangeReviewProjection(
      sessionId: 'session',
      changeSet: WorkspaceChangeSet(
        id: 'change',
        baseWorkspaceRevision: 0,
        resources: <WorkspaceResourceChange>[
          WorkspaceResourceChange(
            resourceId: 'lib/example.dart',
            baseDocumentRevision: 0,
            edits: <WorkspaceTextChange>[
              WorkspaceTextChange(start: 0, end: 0, replacement: replacement),
            ],
          ),
        ],
      ),
      previewId: 'preview',
      outcome: WorkspaceTransactionOutcome.ready,
      conflicts: const <WorkspaceConflict>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentChangeReviewView(
            review: review,
            onDecision: (_) async => review,
          ),
        ),
      ),
    );

    expect(find.textContaining('88 code units omitted'), findsOneWidget);
    expect(find.textContaining(replacement), findsNothing);
  });

  testWidgets('replacement preview does not split a surrogate pair', (
    tester,
  ) async {
    final replacement = '${List<String>.filled(511, 'x').join()}😀tail';
    final review = AgentChangeReviewProjection(
      sessionId: 'session',
      changeSet: WorkspaceChangeSet(
        id: 'change',
        baseWorkspaceRevision: 0,
        resources: <WorkspaceResourceChange>[
          WorkspaceResourceChange(
            resourceId: 'lib/example.dart',
            baseDocumentRevision: 0,
            edits: <WorkspaceTextChange>[
              WorkspaceTextChange(start: 0, end: 0, replacement: replacement),
            ],
          ),
        ],
      ),
      previewId: 'preview',
      outcome: WorkspaceTransactionOutcome.ready,
      conflicts: const <WorkspaceConflict>[],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AgentChangeReviewView(
            review: review,
            onDecision: (_) async => review,
          ),
        ),
      ),
    );

    final preview = tester
        .widgetList<Text>(find.byType(Text))
        .map((text) => text.data ?? '')
        .singleWhere((text) => text.contains('code units omitted'));
    expect(preview.codeUnits, isNot(contains(0xD83D)));
    expect(preview, contains('6 code units omitted'));
  });
}
