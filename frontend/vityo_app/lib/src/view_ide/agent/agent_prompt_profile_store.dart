import '../foundation/foundation.dart';
import 'agent_profile.dart';

class AgentPromptProfileStore {
  AgentPromptProfileStore.fromDataStore({required FoundationDataStore dataStore})
    : this(
        owner: FoundationDataStoreOwner(
          descriptor: const FoundationDataStoreOwnerDescriptor(
            ownerId: 'agent.prompt-profile',
            layer: 'service',
            stateFamily: 'agent-profile',
            allowedNamespaces: <String>{_namespaceName},
          ),
          dataStore: dataStore,
        ),
      );

  const AgentPromptProfileStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'agent.profile';

  final FoundationDataStoreOwner _owner;

  Future<void> saveProfile({
    required String workspaceId,
    String key = 'default',
    required AgentPromptProfile profile,
  }) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: key,
      value: profile.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Future<AgentPromptProfile?> readProfile({
    required String workspaceId,
    String key = 'default',
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    return value == null ? null : AgentPromptProfile.fromJson(value);
  }

  Future<bool> deleteProfile({
    required String workspaceId,
    String key = 'default',
  }) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchProfiles({
    required String workspaceId,
  }) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}
