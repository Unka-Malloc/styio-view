import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_coding_session_controller.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_prompt_profile_store.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_configurator.dart';
import 'package:vityo_app/src/agent/agent_provider_credential_resolver.dart';
import 'package:vityo_app/src/agent/agent_provider_registry.dart';
import 'package:vityo_app/src/agent/agent_provider_route_executor.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/agent/agent_provider_retry_policy.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

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
    final telemetry =
        <AgentProviderRetryExecution<AgentProviderResponseEnvelope>>[];
    final telemetryRequestIds = <String>[];
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
        response: AgentProviderResponseEnvelope(
          requestId: 'retry-mounted',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[],
        ),
      ),
      retryExecutor: const AgentProviderRetryExecutor(
        policy: AgentProviderRetryPolicy(maxAttempts: 2),
      ),
      retryTelemetrySink: (request, execution) {
        telemetryRequestIds.add(request.requestId);
        telemetry.add(execution);
      },
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
    await controller.adapter.send(
      AgentProviderRequest(
        requestId: 'retry-mounted',
        profile: controller.profile,
        context: _context(),
        userPrompt: 'Check retry telemetry.',
      ),
    );
    expect(telemetryRequestIds.single, 'retry-mounted');
    expect(telemetry.single.succeeded, isTrue);
    expect(telemetry.single.attemptCount, 1);
  });

  test(
    'agent provider configurator mounts saved profile by profile id',
    () async {
      final loadedKeys = <String>[];
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
        loadProfile: ({required workspaceId, required key}) async {
          loadedKeys.add(key);
          if (key != 'default') {
            return null;
          }
          return _profile('cloud');
        },
        createAdapter: (_) async => const _FakeAgentProviderAdapter(
          kind: AgentProviderKind.cloudOpenAICompatible,
        ),
      );

      final result = await configurator.mountSavedProfile(
        key: 'cloud',
        controller: controller,
      );

      expect(result.saved, isFalse);
      expect(result.mounted, isTrue);
      expect(loadedKeys, <String>['cloud', 'default']);
      expect(controller.profile.profileId, 'cloud');
      expect(
        controller.providerMountMessage,
        'Agent provider failover mounted cloud.',
      );
    },
  );

  test(
    'agent provider configurator from stores mounts saved profile by manifest id',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_agent_provider_configurator_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final dataStore = _createFoundationDataStore(tempRoot);
      final credentialDataStore = InMemoryCredentialDataStore();
      final profileStore = AgentPromptProfileStore.fromDataStore(
        dataStore: dataStore,
      );
      final configurationStore = ConfigurationStore(
        dataStore: dataStore,
        credentialDataStore: credentialDataStore,
      );
      await profileStore.saveProfile(
        workspaceId: 'workspace-1',
        key: 'cloud-key',
        profile: _profile('cloud-profile'),
      );
      final controller = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
        adapter: const LocalOnlyAgentProviderAdapter(),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);
      final configurator = AgentProviderConfigurator.fromStores(
        workspaceId: 'workspace-1',
        profileStore: profileStore,
        providerFactory: ConfiguredAgentProviderAdapterFactory(
          configurationStore: configurationStore,
          transport: const _NoopAgentProviderTransport(),
        ),
        credentialDataStore: credentialDataStore,
      );

      final result = await configurator.mountSavedProfile(
        key: 'cloud-profile',
        controller: controller,
      );

      expect(result.mounted, isTrue);
      expect(controller.profile.profileId, 'cloud-profile');
      expect(
        controller.providerMountMessage,
        'Agent provider failover mounted cloud-profile.',
      );
    },
  );

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

FoundationDataStore _createFoundationDataStore(Directory root) {
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: root.path,
      homePath: root.path,
    ),
  );
  return FoundationDataStore(
    resourceCoordinator: FoundationResourceCoordinator(
      resourceManager: resourceManager,
      fileSystemManager: fileSystemManager,
    ),
    fileSystemManager: fileSystemManager,
  );
}

class _NoopAgentProviderTransport implements AgentProviderTransport {
  const _NoopAgentProviderTransport();

  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) {
    throw UnimplementedError('No network call expected.');
  }
}

class _FakeAgentProviderAdapter implements AgentProviderAdapter {
  const _FakeAgentProviderAdapter({required this.kind, this.response});

  @override
  final AgentProviderKind kind;
  final AgentProviderResponseEnvelope? response;

  @override
  String get adapterId => 'fake';

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    final response = this.response;
    if (response != null) {
      return Future<AgentProviderResponseEnvelope>.value(response);
    }
    throw UnimplementedError();
  }
}
