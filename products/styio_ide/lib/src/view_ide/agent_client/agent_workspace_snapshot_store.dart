import '../foundation/foundation.dart';
import 'agent_workspace_snapshot.dart';

class AgentWorkspaceSnapshotStore {
  AgentWorkspaceSnapshotStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'agent.workspace-snapshot',
             layer: 'service',
             stateFamily: 'agent-workspace-snapshot',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const AgentWorkspaceSnapshotStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'agent.workspace-snapshot';
  static const String _key = 'latest';

  final FoundationDataStoreOwner _owner;

  Future<void> saveSnapshot({
    required String workspaceId,
    required AgentWorkspaceChangeSnapshot snapshot,
  }) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: <String, Object?>{
        'workspaceId': workspaceId,
        'updatedAt': DateTime.now().toUtc().toIso8601String(),
        'snapshot': snapshot.toPersistedJson(),
      },
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Future<AgentWorkspaceChangeSnapshot?> readSnapshot({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return null;
    }
    final snapshot = value['snapshot'];
    if (snapshot is Map<String, Object?>) {
      return AgentWorkspaceChangeSnapshot.fromPersistedJson(snapshot);
    }
    if (snapshot is Map) {
      return AgentWorkspaceChangeSnapshot.fromPersistedJson(
        snapshot.map<String, Object?>(
          (key, value) => MapEntry(key.toString(), value),
        ),
      );
    }
    return null;
  }

  Future<bool> deleteSnapshot({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}
