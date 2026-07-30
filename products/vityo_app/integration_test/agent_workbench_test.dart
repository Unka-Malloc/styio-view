import 'package:vityo_app/src/ide/agent_client/agent_client.dart';
import 'package:vityo_app/src/ide/workbench/agent_collaboration/collaboration_store.dart';
import 'package:vityo_app/src/ide/workspace/workspace_change_set.dart';
import 'package:vityo_app/src/ide/workspace/workspace_transaction_service.dart';

Future<void> main() async {
  final commands = _Commands();
  final store = AgentCollaborationStore(
    commands: commands,
    transactions: _Transactions(),
    maxTimelineEntriesPerSession: 8,
  );
  try {
    await Future.wait(<Future<CollaborationProjection>>[
      store.apply(_snapshot('first', 'First task')),
      store.apply(_snapshot('second', 'Second task')),
    ]);
    await store.addPermission(
      const AgentPermissionRequest(
        id: 'permission',
        agentId: 'fixture',
        sessionId: 'second',
        options: <String>{'allow_once'},
      ),
    );
    if (store.projection.sessions.length != 2 ||
        store.projection.attentionCount != 1 ||
        store.projection.session('first').attentionRequired) {
      throw StateError('concurrent task attention was not isolated');
    }
    await store.resolvePermission(
      sessionId: 'second',
      permissionId: 'permission',
      decision: AgentPermissionDecision.allowOnce,
    );
    if (commands.permissionSessions.single != 'second' ||
        store.projection.attentionCount != 0) {
      throw StateError('permission was not routed to its owning session');
    }
  } finally {
    await store.close();
  }
}

AgentSessionSnapshot _snapshot(String sessionId, String title) =>
    AgentSessionSnapshot(
      sessionId: sessionId,
      revision: 1,
      updates: <AgentSessionUpdate>[
        AgentSessionUpdate(
          sessionId: sessionId,
          kind: 'session_state',
          text: title,
          payload: <String, Object?>{
            'id': 'state',
            'title': title,
            'status': 'running',
          },
        ),
      ],
    );

final class _Commands implements AgentWorkbenchCommandPort {
  final List<String> permissionSessions = <String>[];

  @override
  Future<void> cancel(String sessionId) async {}

  @override
  Future<void> reconnect(String sessionId) async {}

  @override
  Future<void> resolvePermission({
    required String sessionId,
    required String permissionId,
    required AgentPermissionDecision decision,
  }) async {
    permissionSessions.add(sessionId);
  }

  @override
  Future<void> retry(String sessionId) async {}

  @override
  Future<void> steer(String sessionId, String prompt) async {}
}

final class _Transactions implements WorkspaceTransactionService {
  @override
  Future<WorkspaceTransactionReceipt> commit(String previewId) async =>
      const WorkspaceTransactionReceipt(
        id: 'commit',
        outcome: WorkspaceTransactionOutcome.committed,
        workspaceRevision: 1,
      );

  @override
  Future<WorkspaceTransactionPreview> preview(
    WorkspaceChangeSet changeSet,
  ) async => WorkspaceTransactionPreview(
    id: 'preview',
    changeSetId: changeSet.id,
    outcome: WorkspaceTransactionOutcome.ready,
    conflicts: const <WorkspaceConflict>[],
  );

  @override
  Future<WorkspaceTransactionReceipt> reject(String previewId) async =>
      const WorkspaceTransactionReceipt(
        id: 'reject',
        outcome: WorkspaceTransactionOutcome.rejected,
        workspaceRevision: 0,
      );

  @override
  Future<WorkspaceTransactionReceipt> rollback(String transactionId) async =>
      const WorkspaceTransactionReceipt(
        id: 'rollback',
        outcome: WorkspaceTransactionOutcome.rolledBack,
        workspaceRevision: 2,
      );
}
