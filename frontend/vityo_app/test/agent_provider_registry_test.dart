import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_registry.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test(
    'agent provider registry resolves highest-priority matching provider',
    () async {
      final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
      final lowPriorityAdapter = const _RegistryTestAgentProviderAdapter(
        adapterId: 'low',
        kind: AgentProviderKind.localBridge,
      );
      final highPriorityAdapter = const _RegistryTestAgentProviderAdapter(
        adapterId: 'high',
        kind: AgentProviderKind.cloudOpenAICompatible,
      );
      final registry = AgentProviderRegistry(
        registrations: <AgentProviderRegistration>[
          AgentProviderRegistration(
            providerId: 'low',
            displayName: 'Low Priority Provider',
            kind: lowPriorityAdapter.kind,
            priority: 1,
            supportedRoutes: <String>[profile.endpoint.route.wireValue],
            supportedProtocols: <String>[profile.endpoint.protocol],
            createAdapter: (_) async => lowPriorityAdapter,
          ),
          AgentProviderRegistration(
            providerId: 'high',
            displayName: 'High Priority Provider',
            kind: highPriorityAdapter.kind,
            priority: 10,
            supportsCodePatch: true,
            supportedRoutes: <String>[profile.endpoint.route.wireValue],
            supportedProtocols: <String>[profile.endpoint.protocol],
            capabilities: <String>['code_patch', 'ide_command'],
            createAdapter: (_) async => highPriorityAdapter,
          ),
        ],
      );

      final resolved = registry.resolve(profile);
      final plan = registry.selectionPlan(profile);
      final adapter = await registry.createAdapter(profile);

      expect(resolved?.providerId, 'high');
      expect(plan.ready, isTrue);
      expect(plan.selectedProvider?.providerId, 'high');
      expect(plan.candidates.map((candidate) => candidate.providerId), <String>[
        'high',
        'low',
      ]);
      expect(plan.toJson()['selectedProvider'], isA<Map<String, Object?>>());
      expect(adapter, same(highPriorityAdapter));
    },
  );

  test('agent provider registry manifest is metadata-only', () {
    final registry = AgentProviderRegistry()
      ..register(
        AgentProviderRegistration(
          providerId: 'cloud',
          displayName: 'Cloud Provider',
          kind: AgentProviderKind.cloudOpenAICompatible,
          priority: 5,
          supportsCodePatch: true,
          supportedRoutes: const <String>['web-hosted'],
          supportedProtocols: const <String>['openai-compatible'],
          capabilities: const <String>['plan', 'code_patch'],
          createAdapter: (_) async => const LocalOnlyAgentProviderAdapter(),
        ),
      );

    final json = registry.manifest().toJson();
    final providers = json['providers']! as List<Object?>;
    final provider = providers.single! as Map<String, Object?>;

    expect(provider['providerId'], 'cloud');
    expect(provider['displayName'], 'Cloud Provider');
    expect(provider['kind'], 'cloud_openai_compatible');
    expect(provider['priority'], 5);
    expect(provider['supportsCodePatch'], isTrue);
    expect(provider['supportedRoutes'], <String>['web-hosted']);
    expect(provider['supportedProtocols'], <String>['openai-compatible']);
    expect(provider['capabilities'], <String>['plan', 'code_patch']);
    expect(provider.containsKey('createAdapter'), isFalse);
  });

  test('agent provider registry reports unsupported profile routes', () async {
    final registry = AgentProviderRegistry();
    final profile = AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
    final plan = registry.selectionPlan(profile);

    expect(registry.resolve(profile), isNull);
    expect(plan.ready, isFalse);
    expect(plan.status, AgentProviderSelectionStatus.unsupportedProfile);
    expect(plan.toJson()['candidateCount'], 0);
    expect(plan.toJson()['todo'], startsWith('Install or enable'));
    expect(jsonEncode(plan.toJson()), isNot(contains('TODO:')));
    await expectLater(
      registry.createAdapter(profile),
      throwsA(isA<StateError>()),
    );
  });
}

class _RegistryTestAgentProviderAdapter implements AgentProviderAdapter {
  const _RegistryTestAgentProviderAdapter({
    required this.adapterId,
    required this.kind,
  });

  @override
  final String adapterId;

  @override
  final AgentProviderKind kind;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      contentParts: const <AgentContentPart>[
        AgentContentPart(kind: AgentContentPartKind.text, text: 'ok'),
      ],
      finishReason: 'stop',
    );
  }
}
