import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/app/app_bootstrap.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('agent bootstrap keeps local-only mode without persisted profile', () async {
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
  });

  test('agent bootstrap mounts configured provider for persisted profile', () async {
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

    final controller = await AppBootstrap.createAgentCodingSessionController(
      platformTarget: PlatformTarget.web,
      loadPersistedProfile: () async => profile,
      createConfiguredAdapter: (profile) async {
        expect(profile.profileId, 'cloud');
        return adapter;
      },
      contextProvider: _context,
    );
    addTearDown(controller.dispose);

    expect(controller.profile.profileId, 'cloud');
    expect(controller.adapter, same(adapter));
  });

  test('agent bootstrap falls back to local-only when provider mount fails', () async {
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
  });
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
