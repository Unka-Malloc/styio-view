import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_coding_session_controller.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_configurator.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/environment/configuration/configuration.dart';

void main() {
  test('agent provider configurator saves and mounts configured adapter', () async {
    final savedProfiles = <AgentPromptProfile>[];
    final savedTokens = <String>[];
    final adapter = _FakeAgentProviderAdapter(
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
      saveProfile: ({required workspaceId, required key, required profile}) async {
        expect(workspaceId, 'workspace-1');
        expect(key, 'default');
        savedProfiles.add(profile);
      },
      createAdapter: (_) async => adapter,
      saveBearerToken: ({
        required workspaceId,
        required profileId,
        required secretValue,
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
    expect(savedProfiles.single.endpoint.credentialReference?.key.name, 'cloud');
    expect(savedTokens.single, 'test-token');
    expect(controller.profile.profileId, 'cloud');
    expect(controller.profile.endpoint.credentialReference?.kind, CredentialKind.token);
    expect(controller.adapter, same(adapter));
    expect(controller.providerMountMessage, 'Agent provider profile saved and mounted.');
  });

  test('agent provider configurator saves profile and falls back on mount failure', () async {
    final savedProfiles = <AgentPromptProfile>[];
    final controller = AgentCodingSessionController(
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      adapter: const LocalOnlyAgentProviderAdapter(),
      contextProvider: _context,
    );
    addTearDown(controller.dispose);
    final configurator = AgentProviderConfigurator(
      workspaceId: 'workspace-1',
      saveProfile: ({required workspaceId, required key, required profile}) async {
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
  });

  test('agent provider configurator mirrors profile after local save', () async {
    final events = <String>[];
    final syncedProfiles = <AgentPromptProfile>[];
    final adapter = _FakeAgentProviderAdapter(
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
      saveProfile: ({required workspaceId, required key, required profile}) async {
        events.add('local-save:${profile.profileId}');
      },
      syncProfile: ({required workspaceId, required key, required profile}) async {
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
  });

  test('agent provider configurator keeps local profile when sync fails', () async {
    final events = <String>[];
    final adapter = _FakeAgentProviderAdapter(
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
      saveProfile: ({required workspaceId, required key, required profile}) async {
        events.add('local-save:${profile.profileId}');
      },
      syncProfile: ({required workspaceId, required key, required profile}) async {
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
    expect(controller.providerMountMessage, 'Agent provider profile saved and mounted.');
  });

  test('agent provider configurator ignores blank bearer token', () async {
    final savedProfiles = <AgentPromptProfile>[];
    final savedTokens = <String>[];
    final adapter = _FakeAgentProviderAdapter(
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
      saveProfile: ({required workspaceId, required key, required profile}) async {
        savedProfiles.add(profile);
      },
      createAdapter: (_) async => adapter,
      saveBearerToken: ({
        required workspaceId,
        required profileId,
        required secretValue,
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
