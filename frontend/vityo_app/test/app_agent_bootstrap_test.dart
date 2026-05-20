import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_route_executor.dart';
import 'package:vityo_app/src/app/app_bootstrap.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/agent/agent_coding_session_history_store.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test(
    'agent bootstrap keeps local-only mode without persisted profile',
    () async {
      final controller = await AppBootstrap.createAgentCodingSessionController(
        platformTarget: PlatformTarget.web,
        loadPersistedProfile: () async => null,
        createConfiguredAdapter: (_) {
          fail('default bootstrap must not create a network provider');
        },
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

      expect(controller.profile.profileId, 'default-web');
      expect(controller.adapter, isA<LocalOnlyAgentProviderAdapter>());
    },
  );

  test('agent bootstrap restores persisted session history', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_app_agent_history_bootstrap_test_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final historyStore = AgentCodingSessionHistoryStore.fromDataStore(
      dataStore: FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      ),
    );
    await historyStore.saveHistory(
      AgentCodingSessionHistory(
        workspaceId: 'demo',
        records: <AgentCodingSessionHistoryRecord>[
          AgentCodingSessionHistoryRecord(
            requestId: 'agent-restored',
            profileId: 'default-agent',
            providerKind: 'local_only_fallback',
            prompt: 'Restore history.',
            outcome: AgentCodingSessionOutcome.succeeded,
            createdAt: DateTime.utc(2026, 5, 20),
            completedAt: DateTime.utc(2026, 5, 20, 0, 1),
          ),
        ],
      ),
    );

    final controller = await AppBootstrap.createAgentCodingSessionController(
      platformTarget: PlatformTarget.web,
      loadPersistedProfile: () async => null,
      createConfiguredAdapter: (_) {
        fail('default bootstrap must not create a network provider');
      },
      sessionHistoryStore: historyStore,
      sessionHistoryWorkspaceId: 'demo',
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    expect(
      controller.sessionHistorySnapshot.records.single.requestId,
      'agent-restored',
    );
  });

  test(
    'agent bootstrap mounts configured provider for persisted profile',
    () async {
      const profile = AgentPromptProfile(
        profileId: 'cloud',
        displayName: 'Cloud Agent',
        systemPrompt: 'Use IDE context.',
        endpoint: AgentProviderEndpoint(
          route: AgentProviderRoute.webHosted,
          baseUrl: 'https://agent.example.test/v1',
          model: 'gpt-test',
        ),
      );
      final adapter = _FakeAgentProviderAdapter();
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
              baseUrl: 'https://agent.example.test/v1',
              model: 'gpt-test',
            ),
            plan: AgentProviderExecutionPlan(
              routeKind: AgentProviderExecutionRouteKind.cloud,
              providerKind: AgentProviderKind.cloudOpenAICompatible,
              route: AgentProviderRoute.webHosted,
              endpointBaseUrl: 'https://agent.example.test/v1',
            ),
            credentialReadiness: AgentProviderCredentialReadiness.notReferenced,
          ),
        ],
      );

      final controller = await AppBootstrap.createAgentCodingSessionController(
        platformTarget: PlatformTarget.web,
        loadPersistedProfile: () async => profile,
        createConfiguredAdapter: (profile) async {
          expect(profile.profileId, 'cloud');
          return adapter;
        },
        resolveConfiguredExecution: (profile) async {
          expect(profile.profileId, 'cloud');
          return executionResolution;
        },
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

      expect(controller.profile.profileId, 'cloud');
      expect(controller.adapter, same(adapter));
      expect(controller.providerExecutionResolution, same(executionResolution));
    },
  );

  test(
    'agent bootstrap falls back to local-only when provider mount fails',
    () async {
      const profile = AgentPromptProfile(
        profileId: 'broken',
        displayName: 'Broken Agent',
        systemPrompt: 'Use IDE context.',
        endpoint: AgentProviderEndpoint(
          route: AgentProviderRoute.webHosted,
          baseUrl: 'https://agent.example.test/v1',
          model: 'gpt-test',
        ),
      );

      final controller = await AppBootstrap.createAgentCodingSessionController(
        platformTarget: PlatformTarget.web,
        loadPersistedProfile: () async => profile,
        createConfiguredAdapter: (_) async {
          throw StateError('provider mount failed');
        },
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

      expect(controller.profile.profileId, 'broken');
      expect(controller.adapter, isA<LocalOnlyAgentProviderAdapter>());
    },
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
  @override
  String get adapterId => 'fake';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    throw UnimplementedError();
  }
}
