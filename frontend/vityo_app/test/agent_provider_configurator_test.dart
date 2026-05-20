import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_coding_session_controller.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_configurator.dart';
import 'package:vityo_app/src/agent/agent_provider_registry.dart';
import 'package:vityo_app/src/agent/agent_provider_route_executor.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/agent/agent_provider_retry_policy.dart';
import 'package:vityo_app/src/view_ide/environment/configuration/configuration.dart';

void main() {
  test(
    'agent provider configurator saves and mounts configured adapter',
    () async {
      final savedProfiles = <AgentPromptProfile>[];
      final savedTokens = <String>[];
      final adapter = const _FakeAgentProviderAdapter(
        kind: AgentProviderKind.cloudOpenAICompatible,
      );
      const executionResolution = AgentProviderExecutionResolution(
        profileId: 'cloud',
        status: AgentProviderExecutionResolutionStatus.ready,
        selectedEndpointIndex: 0,
        endpoints: <AgentProviderEndpointReadiness>[
          AgentProviderEndpointReadiness(
            endpointIndex: 0,
            fallback: false,
            endpoint: AgentProviderEndpoint(
              route: AgentProviderRoute.webHosted,
              baseUrl: 'https://agent.test/v1',
              model: 'gpt-test',
            ),
            plan: AgentProviderExecutionPlan(
              routeKind: AgentProviderExecutionRouteKind.cloud,
              providerKind: AgentProviderKind.cloudOpenAICompatible,
              route: AgentProviderRoute.webHosted,
              endpointBaseUrl: 'https://agent.test/v1',
            ),
            credentialReadiness: AgentProviderCredentialReadiness.available,
          ),
        ],
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);
      final configurator = AgentProviderConfigurator(
        workspaceId: 'workspace-1',
        saveProfile:
            ({required workspaceId, required key, required profile}) async {
              expect(workspaceId, 'workspace-1');
              expect(key, 'default');
              savedProfiles.add(profile);
            },
        createAdapter: (_) async => adapter,
        selectProvider: (profile) {
          expect(profile.profileId, 'cloud');
          return AgentProviderSelectionPlan(
            status: AgentProviderSelectionStatus.ready,
            route: profile.endpoint.route,
            protocol: profile.endpoint.protocol,
            requiresCredential: profile.endpoint.requiresCredential,
            selectedProvider: const AgentProviderRegistrationManifest(
              providerId: 'cloud',
              displayName: 'Cloud Provider',
              kind: AgentProviderKind.cloudOpenAICompatible,
              priority: 10,
              supportsCodePatch: true,
              supportedRoutes: <String>['web-hosted'],
              supportedProtocols: <String>['openai-compatible'],
              capabilities: <String>['plan', 'code_patch'],
            ),
            candidates: const <AgentProviderRegistrationManifest>[],
          );
        },
        resolveExecution: (profile) async {
          expect(profile.profileId, 'cloud');
          return executionResolution;
        },
        saveBearerToken:
            ({
              required workspaceId,
              required profileId,
              required secretValue,
              CredentialReference? preferredReference,
            }) async {
              savedTokens.add(secretValue);
              return CredentialReference(
                key: CredentialDataStoreKey(
                  namespace: 'agent.provider',
                  name: profileId,
                  scope: CredentialScope.workspace,
                  targetId: workspaceId,
                ),
                kind: CredentialKind.token,
              );
            },
      );

      final result = await configurator.saveAndMount(
        profile: _profile('cloud'),
        controller: controller,
        bearerToken: 'test-token',
      );

      expect(result.saved, isTrue);
      expect(result.mounted, isTrue);
      expect(savedProfiles.single.profileId, 'cloud');
      expect(
        savedProfiles.single.endpoint.credentialReference?.key.name,
        'cloud',
      );
      expect(savedTokens.single, 'test-token');
      expect(controller.profile.profileId, 'cloud');
      expect(
        controller.profile.endpoint.credentialReference?.kind,
        CredentialKind.token,
      );
      expect(controller.adapter, same(adapter));
      expect(
        controller.providerMountMessage,
        'Agent provider profile saved and mounted.',
      );
      expect(controller.providerExecutionResolution, same(executionResolution));
      expect(controller.providerSelectionPlan?.ready, isTrue);
      expect(
        controller.providerSelectionPlan?.selectedProvider?.providerId,
        'cloud',
      );
      expect(result.selectionPlan?.ready, isTrue);
      expect(result.selectionPlan?.selectedProvider?.providerId, 'cloud');
      expect(result.executionResolution, same(executionResolution));
    },
  );

  test('agent provider configurator can mount retrying adapter', () async {
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    final configurator = AgentProviderConfigurator(
      workspaceId: 'workspace-1',
      saveProfile:
          ({required workspaceId, required key, required profile}) async {},
      createAdapter: (_) async => const _FakeAgentProviderAdapter(
        kind: AgentProviderKind.cloudOpenAICompatible,
      ),
      retryExecutor: const AgentProviderRetryExecutor(
        policy: AgentProviderRetryPolicy(maxAttempts: 2),
      ),
    );

    final result = await configurator.saveAndMount(
      profile: _profile('cloud'),
      controller: controller,
    );

    expect(result.mounted, isTrue);
    expect(result.retryEnabled, isTrue);
    expect(result.adapterId, 'fake:retrying');
    expect(controller.adapter, isA<RetryingAgentProviderAdapter>());
    expect(controller.adapter.kind, AgentProviderKind.cloudOpenAICompatible);
  });

  test(
    'agent provider configurator writes token to preferred OpenAI credential',
    () async {
      final savedProfiles = <AgentPromptProfile>[];
      final savedTokens = <String>[];
      final preferredReferences = <CredentialReference?>[];
      final adapter = const _FakeAgentProviderAdapter(
        kind: AgentProviderKind.cloudOpenAICompatible,
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);
      final configurator = AgentProviderConfigurator(
        workspaceId: 'workspace-1',
        saveProfile:
            ({required workspaceId, required key, required profile}) async {
              savedProfiles.add(profile);
            },
        createAdapter: (_) async => adapter,
        saveBearerToken:
            ({
              required workspaceId,
              required profileId,
              required secretValue,
              CredentialReference? preferredReference,
            }) async {
              savedTokens.add(secretValue);
              preferredReferences.add(preferredReference);
              return preferredReference!;
            },
      );
      final profile = AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      );

      final result = await configurator.saveAndMount(
        profile: profile,
        controller: controller,
        bearerToken: 'user-openai-key',
      );
      final credentialReference =
          savedProfiles.single.endpoint.credentialReference!;

      expect(result.saved, isTrue);
      expect(savedTokens.single, 'user-openai-key');
      expect(
        preferredReferences.single,
        same(profile.endpoint.credentialReference),
      );
      expect(credentialReference.key.namespace, 'agent.provider');
      expect(credentialReference.key.name, 'openai-api-key');
      expect(credentialReference.key.scope, CredentialScope.user);
      expect(credentialReference.kind, CredentialKind.remoteServiceCredential);
      expect(savedProfiles.single.endpoint.model, 'gpt-5.3-codex-spark');
      expect(
        savedProfiles.single.endpoint.toJson().toString(),
        isNot(contains('user-openai-key')),
      );
      expect(
        controller.profile.endpoint.credentialReference,
        credentialReference,
      );
    },
  );

  test(
    'agent provider configurator saves profile and falls back on mount failure',
    () async {
      final savedProfiles = <AgentPromptProfile>[];
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);
      final configurator = AgentProviderConfigurator(
        workspaceId: 'workspace-1',
        saveProfile:
            ({required workspaceId, required key, required profile}) async {
              savedProfiles.add(profile);
            },
        createAdapter: (_) async {
          throw StateError('mount failed');
        },
      );

      final result = await configurator.saveAndMount(
        profile: _profile('broken'),
        controller: controller,
      );

      expect(result.saved, isTrue);
      expect(result.mounted, isFalse);
      expect(savedProfiles.single.profileId, 'broken');
      expect(controller.profile.profileId, 'broken');
      expect(controller.adapter, isA<LocalOnlyAgentProviderAdapter>());
      expect(controller.providerMountMessage, contains('mount failed'));
    },
  );

  test(
    'agent provider configurator mirrors profile after local save',
    () async {
      final events = <String>[];
      final syncedProfiles = <AgentPromptProfile>[];
      final adapter = const _FakeAgentProviderAdapter(
        kind: AgentProviderKind.cloudOpenAICompatible,
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);
      final configurator = AgentProviderConfigurator(
        workspaceId: 'workspace-1',
        saveProfile:
            ({required workspaceId, required key, required profile}) async {
              events.add('local-save:${profile.profileId}');
            },
        syncProfile:
            ({required workspaceId, required key, required profile}) async {
              events.add('sync:${profile.profileId}');
              syncedProfiles.add(profile);
            },
        createAdapter: (profile) async {
          events.add('create-adapter:${profile.profileId}');
          return adapter;
        },
      );

      final result = await configurator.saveAndMount(
        profile: _profile('synced'),
        controller: controller,
      );

      expect(result.saved, isTrue);
      expect(result.synced, isTrue);
      expect(result.mounted, isTrue);
      expect(events, <String>[
        'local-save:synced',
        'sync:synced',
        'create-adapter:synced',
      ]);
      expect(syncedProfiles.single.profileId, 'synced');
      expect(controller.providerMountMessage, contains('saved, synced'));
    },
  );

  test(
    'agent provider configurator keeps local profile when sync fails',
    () async {
      final events = <String>[];
      final adapter = const _FakeAgentProviderAdapter(
        kind: AgentProviderKind.cloudOpenAICompatible,
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);
      final configurator = AgentProviderConfigurator(
        workspaceId: 'workspace-1',
        saveProfile:
            ({required workspaceId, required key, required profile}) async {
              events.add('local-save:${profile.profileId}');
            },
        syncProfile:
            ({required workspaceId, required key, required profile}) async {
              events.add('sync-failed:${profile.profileId}');
              throw StateError('sync failed');
            },
        createAdapter: (profile) async {
          events.add('create-adapter:${profile.profileId}');
          return adapter;
        },
      );

      final result = await configurator.saveAndMount(
        profile: _profile('local-only-after-sync-failure'),
        controller: controller,
      );

      expect(result.saved, isTrue);
      expect(result.synced, isFalse);
      expect(result.mounted, isTrue);
      expect(events, <String>[
        'local-save:local-only-after-sync-failure',
        'sync-failed:local-only-after-sync-failure',
        'create-adapter:local-only-after-sync-failure',
      ]);
      expect(controller.profile.profileId, 'local-only-after-sync-failure');
      expect(
        controller.providerMountMessage,
        'Agent provider profile saved and mounted.',
      );
    },
  );

  test('agent provider configurator ignores blank bearer token', () async {
    final savedProfiles = <AgentPromptProfile>[];
    final savedTokens = <String>[];
    final adapter = const _FakeAgentProviderAdapter(
      kind: AgentProviderKind.cloudOpenAICompatible,
    );
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    final configurator = AgentProviderConfigurator(
      workspaceId: 'workspace-1',
      saveProfile:
          ({required workspaceId, required key, required profile}) async {
            savedProfiles.add(profile);
          },
      createAdapter: (_) async => adapter,
      saveBearerToken:
          ({
            required workspaceId,
            required profileId,
            required secretValue,
            CredentialReference? preferredReference,
          }) async {
            savedTokens.add(secretValue);
            return CredentialReference(
              key: CredentialDataStoreKey(
                namespace: 'agent.provider',
                name: profileId,
                scope: CredentialScope.workspace,
                targetId: workspaceId,
              ),
              kind: CredentialKind.token,
            );
          },
    );

    final result = await configurator.saveAndMount(
      profile: _profile('blank-token'),
      controller: controller,
      bearerToken: '   ',
    );

    expect(result.saved, isTrue);
    expect(result.mounted, isTrue);
    expect(savedTokens, isEmpty);
    expect(savedProfiles.single.endpoint.credentialReference, isNull);
    expect(controller.profile.endpoint.credentialReference, isNull);
  });

  test(
    'agent provider configurator preserves fallback endpoints when saving token',
    () async {
      final savedProfiles = <AgentPromptProfile>[];
      final adapter = const _FakeAgentProviderAdapter(
        kind: AgentProviderKind.cloudOpenAICompatible,
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);
      final configurator = AgentProviderConfigurator(
        workspaceId: 'workspace-1',
        saveProfile:
            ({required workspaceId, required key, required profile}) async {
              savedProfiles.add(profile);
            },
        createAdapter: (_) async => adapter,
        saveBearerToken:
            ({
              required workspaceId,
              required profileId,
              required secretValue,
              CredentialReference? preferredReference,
            }) async {
              return CredentialReference(
                key: CredentialDataStoreKey(
                  namespace: 'agent.provider',
                  name: profileId,
                  scope: CredentialScope.workspace,
                  targetId: workspaceId,
                ),
                kind: CredentialKind.token,
              );
            },
      );
      const profile = AgentPromptProfile(
        profileId: 'fallback-token',
        displayName: 'Fallback Token Agent',
        systemPrompt: 'Use IDE context.',
        endpoint: AgentProviderEndpoint(
          route: AgentProviderRoute.webHosted,
          baseUrl: 'https://api.openai.com/v1',
          model: 'gpt-test',
          requiresCredential: true,
        ),
        fallbackEndpoints: <AgentProviderEndpoint>[
          AgentProviderEndpoint(
            route: AgentProviderRoute.webHosted,
            baseUrl: 'https://fallback.example.test/v1',
            model: 'gpt-fallback-test',
          ),
        ],
      );

      final result = await configurator.saveAndMount(
        profile: profile,
        controller: controller,
        bearerToken: 'test-token',
      );

      expect(result.saved, isTrue);
      expect(savedProfiles.single.endpoint.requiresCredential, isTrue);
      expect(savedProfiles.single.fallbackEndpoints, hasLength(1));
      expect(
        savedProfiles.single.fallbackEndpoints.single.model,
        'gpt-fallback-test',
      );
      expect(
        controller.profile.fallbackEndpoints.single.baseUrl,
        contains('fallback'),
      );
    },
  );
}

AgentPromptProfile _profile(String profileId) {
  return AgentPromptProfile(
    profileId: profileId,
    displayName: 'Agent $profileId',
    systemPrompt: 'Use IDE context.',
    endpoint: const AgentProviderEndpoint(
      route: AgentProviderRoute.webHosted,
      baseUrl: 'https://agent.example.test/v1',
      model: 'gpt-test',
    ),
  );
}

AgentSessionContext _context() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: 'main.styio',
      text: '',
      revision: 0,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
  );
}

class _FakeAgentProviderAdapter implements AgentProviderAdapter {
  const _FakeAgentProviderAdapter({required this.kind});

  @override
  final AgentProviderKind kind;

  @override
  String get adapterId => 'fake';

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    throw UnimplementedError();
  }
}
