import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/ide/agent_client/agent_client.dart';
import 'package:vityo_app/src/ide/workbench/agent_collaboration/agent_collaboration_service.dart';
import 'package:vityo_app/src/ide/workspace/workspace_revision_service.dart';
import 'package:vityo_app/src/ide/workspace/workspace_transaction_service.dart';
import 'package:vityo_app/src/presentation/agent_workbench/agent_workbench_surface.dart';

void main() {
  testWidgets(
    'surface cancels stale projection subscriptions on rebind and dispose',
    (tester) async {
      final first = _service('first-agent');
      final second = _service('second-agent');

      await first.store.apply(_snapshot('first-session', 'First session'));
      await second.store.apply(_snapshot('second-session', 'Second session'));
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AgentWorkbenchSurface(collaboration: first)),
        ),
      );
      expect(find.text('First session'), findsWidgets);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: AgentWorkbenchSurface(collaboration: second)),
        ),
      );
      await tester.pump();
      expect(find.text('Second session'), findsWidgets);
      expect(find.text('First session'), findsNothing);

      await first.store.apply(_snapshot('stale-session', 'Stale session'));
      await tester.pump();
      expect(find.text('Stale session'), findsNothing);
      expect(find.text('Second session'), findsWidgets);

      await tester.pumpWidget(const SizedBox.shrink());
      await second.store.apply(_snapshot('post-dispose', 'Disposed session'));
      await tester.pump();
      expect(tester.takeException(), isNull);
      await tester.runAsync(() async {
        await first.close();
        await second.close();
      });
    },
  );
}

AgentCollaborationService _service(String agentId) {
  final revisions = InMemoryWorkspaceRevisionService(
    initialDocuments: const <String, String>{'file': 'text'},
  );
  return AgentCollaborationService(
    registry: AgentClientRegistry(
      descriptors: <String, AgentLaunchDescriptor>{
        agentId: AgentLaunchDescriptor(
          id: agentId,
          executable: 'unused',
          arguments: const <String>[],
          workingDirectory: '.',
        ),
      },
    ),
    transactions: RevisionedWorkspaceTransactionService(revisions),
    workspaceRoot: Uri.directory('/workspace'),
  );
}

AgentSessionSnapshot _snapshot(String sessionId, String title) =>
    AgentSessionSnapshot(
      sessionId: sessionId,
      revision: 1,
      updates: <AgentSessionUpdate>[
        AgentSessionUpdate(
          sessionId: sessionId,
          kind: 'session_state',
          payload: <String, Object?>{
            'id': 'state',
            'title': title,
            'status': 'running',
          },
        ),
      ],
    );
