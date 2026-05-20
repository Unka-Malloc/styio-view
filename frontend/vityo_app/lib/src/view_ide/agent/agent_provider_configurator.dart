import 'agent_coding_session_controller.dart';
import 'agent_profile.dart';
import 'agent_prompt_profile_store.dart';
import 'agent_provider_adapter.dart';
import 'agent_provider_credential_resolver.dart';
import 'agent_provider_registry.dart';
import 'agent_provider_retry_policy.dart';
import 'agent_provider_route_executor.dart';
import '../environment/configuration/configuration.dart';

typedef AgentPromptProfileSaver =
    Future<void> Function({
      required String workspaceId,
      required String key,
      required AgentPromptProfile profile,
    });

typedef AgentProviderAdapterCreator =
    Future<AgentProviderAdapter> Function(AgentPromptProfile profile);

typedef AgentProviderExecutionResolver =
    Future<AgentProviderExecutionResolution> Function(
      AgentPromptProfile profile,
    );

typedef AgentProviderSelectionPlanner =
    AgentProviderSelectionPlan Function(AgentPromptProfile profile);

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
      CredentialReference? preferredReference,
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
    this.selectionPlan,
    this.executionResolution,
    this.retryEnabled = false,
  });

  final bool saved;
  final bool mounted;
  final AgentPromptProfile profile;
  final AgentProviderKind adapterKind;
  final String adapterId;
  final String message;
  final bool synced;
  final AgentProviderSelectionPlan? selectionPlan;
  final AgentProviderExecutionResolution? executionResolution;
  final bool retryEnabled;
}

class AgentProviderConfigurator {
  const AgentProviderConfigurator({
    required this.workspaceId,
    required AgentPromptProfileSaver saveProfile,
    required AgentProviderAdapterCreator createAdapter,
    AgentProviderSelectionPlanner? selectProvider,
    AgentProviderExecutionResolver? resolveExecution,
    AgentPromptProfileSync? syncProfile,
    AgentBearerTokenSaver? saveBearerToken,
    AgentProviderRetryExecutor? retryExecutor,
  }) : _saveProfile = saveProfile,
       _createAdapter = createAdapter,
       _selectProvider = selectProvider,
       _resolveExecution = resolveExecution,
       _syncProfile = syncProfile,
       _saveBearerToken = saveBearerToken,
       _retryExecutor = retryExecutor;

  factory AgentProviderConfigurator.fromStores({
    required String workspaceId,
    required AgentPromptProfileStore profileStore,
    required ConfiguredAgentProviderAdapterFactory providerFactory,
    required CredentialDataStore credentialDataStore,
    AgentProviderRegistry? providerRegistry,
    AgentProviderRetryExecutor? retryExecutor,
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
      selectProvider: registry.selectionPlan,
      resolveExecution: providerFactory.resolveExecution,
      retryExecutor: retryExecutor,
      saveBearerToken:
          ({
            required workspaceId,
            required profileId,
            required secretValue,
            CredentialReference? preferredReference,
          }) async {
            final key =
                preferredReference?.key ??
                CredentialDataStoreKey(
                  namespace: 'agent.provider',
                  name: profileId,
                  scope: CredentialScope.workspace,
                  targetId: workspaceId,
                );
            final kind = preferredReference?.kind ?? CredentialKind.token;
            final displayName =
                preferredReference?.displayName ?? 'Agent provider token';
            await credentialDataStore.write(
              CredentialSecretRecord(
                key: key,
                kind: kind,
                secretValue: secretValue,
                displayName: displayName,
              ),
            );
            return preferredReference ??
                CredentialReference(
                  key: key,
                  kind: kind,
                  displayName: displayName,
                );
          },
    );
  }

  final String workspaceId;
  final AgentPromptProfileSaver _saveProfile;
  final AgentProviderAdapterCreator _createAdapter;
  final AgentProviderSelectionPlanner? _selectProvider;
  final AgentProviderExecutionResolver? _resolveExecution;
  final AgentPromptProfileSync? _syncProfile;
  final AgentBearerTokenSaver? _saveBearerToken;
  final AgentProviderRetryExecutor? _retryExecutor;

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
    final selectionPlan = _selectionPlanFor(profileToSave);
    final executionResolution = await _resolveExecutionFor(profileToSave);
    try {
      final createdAdapter = await _createAdapter(profileToSave);
      final adapter = _adapterWithRetry(createdAdapter);
      final message = synced
          ? 'Agent provider profile saved, synced, and mounted.'
          : 'Agent provider profile saved and mounted.';
      controller.mountProvider(
        profile: profileToSave,
        adapter: adapter,
        message: message,
        selectionPlan: selectionPlan,
        executionResolution: executionResolution,
      );
      return AgentProviderConfigurationResult(
        saved: true,
        mounted: true,
        profile: profileToSave,
        adapterKind: adapter.kind,
        adapterId: adapter.adapterId,
        message: message,
        synced: synced,
        selectionPlan: selectionPlan,
        executionResolution: executionResolution,
        retryEnabled: _retryExecutor != null,
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
        selectionPlan: selectionPlan,
        executionResolution: executionResolution,
      );
      return AgentProviderConfigurationResult(
        saved: true,
        mounted: false,
        profile: profileToSave,
        adapterKind: adapter.kind,
        adapterId: adapter.adapterId,
        message: message,
        synced: synced,
        selectionPlan: selectionPlan,
        executionResolution: executionResolution,
        retryEnabled: false,
      );
    }
  }

  AgentProviderAdapter _adapterWithRetry(AgentProviderAdapter adapter) {
    final retryExecutor = _retryExecutor;
    if (retryExecutor == null) {
      return adapter;
    }
    if (adapter is RetryingAgentProviderAdapter) {
      return adapter;
    }
    return RetryingAgentProviderAdapter(
      inner: adapter,
      retryExecutor: retryExecutor,
    );
  }

  AgentProviderSelectionPlan? _selectionPlanFor(AgentPromptProfile profile) {
    final selectProvider = _selectProvider;
    if (selectProvider == null) {
      return null;
    }
    try {
      return selectProvider(profile);
    } on Object {
      return null;
    }
  }

  Future<AgentProviderExecutionResolution?> _resolveExecutionFor(
    AgentPromptProfile profile,
  ) async {
    final resolver = _resolveExecution;
    if (resolver == null) {
      return null;
    }
    try {
      return await resolver(profile);
    } on Object {
      return null;
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
      preferredReference: profile.endpoint.credentialReference,
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
        reasoningEffort: profile.endpoint.reasoningEffort,
        credentialReference: reference,
        requiresCredential: profile.endpoint.requiresCredential,
      ),
      fallbackEndpoints: profile.fallbackEndpoints,
      contextChannels: profile.contextChannels,
    );
  }
}
