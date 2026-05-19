import 'agent_coding_session_controller.dart';
import 'agent_profile.dart';
import 'agent_prompt_profile_store.dart';
import 'agent_provider_adapter.dart';
import 'agent_provider_credential_resolver.dart';
import 'agent_provider_registry.dart';
import '../environment/configuration/configuration.dart';

typedef AgentPromptProfileSaver =
    Future<void> Function({
      required String workspaceId,
      required String key,
      required AgentPromptProfile profile,
    });

typedef AgentProviderAdapterCreator =
    Future<AgentProviderAdapter> Function(AgentPromptProfile profile);

typedef AgentPromptProfileSync =
    Future<void> Function({
      required String workspaceId,
      required String key,
      required AgentPromptProfile profile,
    });

typedef AgentBearerTokenSaver =
    Future<CredentialReference> Function({
      required String workspaceId,
      required String profileId,
      required String secretValue,
    });

class AgentProviderConfigurationResult {
  const AgentProviderConfigurationResult({
    required this.saved,
    required this.mounted,
    required this.profile,
    required this.adapterKind,
    required this.adapterId,
    required this.message,
    this.synced = false,
  });

  final bool saved;
  final bool mounted;
  final AgentPromptProfile profile;
  final AgentProviderKind adapterKind;
  final String adapterId;
  final String message;
  final bool synced;
}

class AgentProviderConfigurator {
  const AgentProviderConfigurator({
    required this.workspaceId,
    required AgentPromptProfileSaver saveProfile,
    required AgentProviderAdapterCreator createAdapter,
    AgentPromptProfileSync? syncProfile,
    AgentBearerTokenSaver? saveBearerToken,
  }) : _saveProfile = saveProfile,
       _createAdapter = createAdapter,
       _syncProfile = syncProfile,
       _saveBearerToken = saveBearerToken;

  factory AgentProviderConfigurator.fromStores({
    required String workspaceId,
    required AgentPromptProfileStore profileStore,
    required ConfiguredAgentProviderAdapterFactory providerFactory,
    required CredentialDataStore credentialDataStore,
    AgentProviderRegistry? providerRegistry,
  }) {
    final registry = providerRegistry ?? providerFactory.createRegistry();
    return AgentProviderConfigurator(
      workspaceId: workspaceId,
      saveProfile: ({required workspaceId, required key, required profile}) {
        return profileStore.saveProfile(
          workspaceId: workspaceId,
          key: key,
          profile: profile,
        );
      },
      createAdapter: registry.createAdapter,
      saveBearerToken:
          ({
            required workspaceId,
            required profileId,
            required secretValue,
          }) async {
            final key = CredentialDataStoreKey(
              namespace: 'agent.provider',
              name: profileId,
              scope: CredentialScope.workspace,
              targetId: workspaceId,
            );
            await credentialDataStore.write(
              CredentialSecretRecord(
                key: key,
                kind: CredentialKind.token,
                secretValue: secretValue,
                displayName: 'Agent provider token',
              ),
            );
            return CredentialReference(
              key: key,
              kind: CredentialKind.token,
              displayName: 'Agent provider token',
            );
          },
    );
  }

  final String workspaceId;
  final AgentPromptProfileSaver _saveProfile;
  final AgentProviderAdapterCreator _createAdapter;
  final AgentPromptProfileSync? _syncProfile;
  final AgentBearerTokenSaver? _saveBearerToken;

  Future<AgentProviderConfigurationResult> saveAndMount({
    required AgentPromptProfile profile,
    required AgentCodingSessionController controller,
    String key = 'default',
    String? bearerToken,
  }) async {
    final profileToSave = await _profileWithOptionalBearerToken(
      profile: profile,
      bearerToken: bearerToken,
    );
    await _saveProfile(
      workspaceId: workspaceId,
      key: key,
      profile: profileToSave,
    );
    final synced = await _syncProfileAfterLocalSave(
      key: key,
      profile: profileToSave,
    );
    try {
      final adapter = await _createAdapter(profileToSave);
      final message = synced
          ? 'Agent provider profile saved, synced, and mounted.'
          : 'Agent provider profile saved and mounted.';
      controller.mountProvider(
        profile: profileToSave,
        adapter: adapter,
        message: message,
      );
      return AgentProviderConfigurationResult(
        saved: true,
        mounted: true,
        profile: profileToSave,
        adapterKind: adapter.kind,
        adapterId: adapter.adapterId,
        message: message,
        synced: synced,
      );
    } on Object catch (error) {
      const adapter = LocalOnlyAgentProviderAdapter();
      final message = synced
          ? 'Agent provider profile saved and synced, but provider mount failed: $error'
          : 'Agent provider profile saved, but provider mount failed: $error';
      controller.mountProvider(
        profile: profileToSave,
        adapter: adapter,
        message: message,
      );
      return AgentProviderConfigurationResult(
        saved: true,
        mounted: false,
        profile: profileToSave,
        adapterKind: adapter.kind,
        adapterId: adapter.adapterId,
        message: message,
        synced: synced,
      );
    }
  }

  Future<bool> _syncProfileAfterLocalSave({
    required String key,
    required AgentPromptProfile profile,
  }) async {
    final syncProfile = _syncProfile;
    if (syncProfile == null) {
      return false;
    }
    try {
      await syncProfile(workspaceId: workspaceId, key: key, profile: profile);
      return true;
    } on Object {
      return false;
    }
  }

  Future<AgentPromptProfile> _profileWithOptionalBearerToken({
    required AgentPromptProfile profile,
    String? bearerToken,
  }) async {
    final token = bearerToken?.trim();
    if (token == null || token.isEmpty) {
      return profile;
    }
    final saver = _saveBearerToken;
    if (saver == null) {
      return profile;
    }
    final reference = await saver(
      workspaceId: workspaceId,
      profileId: profile.profileId,
      secretValue: token,
    );
    return AgentPromptProfile(
      profileId: profile.profileId,
      displayName: profile.displayName,
      systemPrompt: profile.systemPrompt,
      endpoint: AgentProviderEndpoint(
        route: profile.endpoint.route,
        baseUrl: profile.endpoint.baseUrl,
        model: profile.endpoint.model,
        apiKeyEnvironmentName: profile.endpoint.apiKeyEnvironmentName,
        protocol: profile.endpoint.protocol,
        credentialReference: reference,
      ),
      contextChannels: profile.contextChannels,
    );
  }
}
