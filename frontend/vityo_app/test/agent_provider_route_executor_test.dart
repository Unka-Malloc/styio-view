import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test('agent provider route executor selects cloud for remote endpoints', () {
    final plan = const AgentProviderRouteExecutor().planFor(
      _profile(
        route: AgentProviderRoute.webHosted,
        baseUrl: 'https://agent.example.test/v1',
      ),
    );

    expect(plan.routeKind, AgentProviderExecutionRouteKind.cloud);
    expect(plan.providerKind, AgentProviderKind.cloudOpenAICompatible);
    expect(plan.usesCloud, isTrue);
    expect(plan.executable, isTrue);
  });

  test('agent provider route executor selects local bridge for loopback', () {
    final plan = AgentProviderRouteExecutor(
      localServiceManager: LoopbackLocalServiceManager.linuxDebianArmForTest(),
    ).planFor(
      _profile(
        route: AgentProviderRoute.desktopLocalBridge,
        baseUrl: 'http://127.0.0.1:11434/v1',
      ),
    );

    expect(plan.routeKind, AgentProviderExecutionRouteKind.localBridge);
    expect(plan.providerKind, AgentProviderKind.localBridge);
    expect(plan.usesLocalBridge, isTrue);
    expect(plan.adapterId, 'openai-compatible-local-bridge');
  });

  test('agent provider route executor blocks unavailable local bridge', () {
    final manager = UnsupportedLocalServiceManager(
      facts: const LocalServiceFacts(
        targetId: 'unsupported',
        operatingSystem: 'linux',
        distributionId: 'generic',
        architecture: 'x64',
        providerKind: LocalServiceProviderKind.unsupported,
        supportsLoopbackHttpServer: false,
        supportsEphemeralPort: false,
      ),
    );
    final plan = AgentProviderRouteExecutor(localServiceManager: manager).planFor(
      _profile(
        route: AgentProviderRoute.desktopLocalBridge,
        baseUrl: 'http://localhost:11434/v1',
      ),
    );

    expect(plan.executable, isFalse);
    expect(
      plan.blockReason,
      AgentProviderExecutionBlockReason.localBridgeUnavailable,
    );
    expect(plan.providerKind, AgentProviderKind.localOnlyFallback);
  });

  test('agent prompt profile serializes fallback endpoints', () {
    final profile = _profile(
      route: AgentProviderRoute.desktopLocalBridge,
      baseUrl: 'http://localhost:11434/v1',
      fallbackEndpoints: const <AgentProviderEndpoint>[
        AgentProviderEndpoint(
          route: AgentProviderRoute.webHosted,
          baseUrl: 'https://agent.example.test/v1',
          model: 'gpt-cloud-fallback',
        ),
      ],
    );

    final reloaded = AgentPromptProfile.fromJson(profile.toJson());

    expect(reloaded.endpoint.baseUrl, 'http://localhost:11434/v1');
    expect(reloaded.fallbackEndpoints, hasLength(1));
    expect(
      reloaded.fallbackEndpoints.single.baseUrl,
      'https://agent.example.test/v1',
    );
    expect(reloaded.fallbackEndpoints.single.model, 'gpt-cloud-fallback');
  });

  test('agent provider factory routes loopback requests to local transport', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_agent_route_executor_test_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });
    final configurationStore = _configurationStore(tempRoot);
    final cloudTransport = _RecordingTransport();
    final localTransport = _RecordingTransport();
    final factory = ConfiguredAgentProviderAdapterFactory(
      configurationStore: configurationStore,
      transport: cloudTransport,
      localBridgeTransport: localTransport,
      localServiceManager: LoopbackLocalServiceManager.linuxDebianArmForTest(),
    );
    final profile = _profile(
      route: AgentProviderRoute.desktopLocalBridge,
      baseUrl: 'http://127.0.0.1:11434/v1',
    );

    final adapter = await factory.create(profile);
    await adapter.send(
      AgentProviderRequest(
        requestId: 'route-request',
        profile: profile,
        context: _emptyContext(),
        userPrompt: 'Use the local bridge.',
      ),
    );

    expect(adapter.kind, AgentProviderKind.localBridge);
    expect(adapter.adapterId, 'openai-compatible-local-bridge');
    expect(localTransport.callCount, 1);
    expect(cloudTransport.callCount, 0);
    expect(
      localTransport.lastEndpoint.toString(),
      'http://127.0.0.1:11434/v1/chat/completions',
    );
    expect(localTransport.lastBody['model'], 'gpt-route-test');
  });

  test('agent provider factory fails over from blocked bridge to cloud', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_agent_route_failover_test_',
    );
    addTearDown(() async {
      if (await tempRoot.exists()) {
        await tempRoot.delete(recursive: true);
      }
    });
    final unsupportedManager = UnsupportedLocalServiceManager(
      facts: const LocalServiceFacts(
        targetId: 'unsupported',
        operatingSystem: 'linux',
        distributionId: 'generic',
        architecture: 'x64',
        providerKind: LocalServiceProviderKind.unsupported,
        supportsLoopbackHttpServer: false,
        supportsEphemeralPort: false,
      ),
    );
    final cloudTransport = _RecordingTransport();
    final localTransport = _RecordingTransport();
    final factory = ConfiguredAgentProviderAdapterFactory(
      configurationStore: _configurationStore(tempRoot),
      transport: cloudTransport,
      localBridgeTransport: localTransport,
      localServiceManager: unsupportedManager,
    );
    final profile = _profile(
      route: AgentProviderRoute.desktopLocalBridge,
      baseUrl: 'http://127.0.0.1:11434/v1',
      fallbackEndpoints: const <AgentProviderEndpoint>[
        AgentProviderEndpoint(
          route: AgentProviderRoute.webHosted,
          baseUrl: 'https://agent.example.test/v1',
          model: 'gpt-cloud-fallback',
        ),
      ],
    );

    final adapter = await factory.create(profile);
    await adapter.send(
      AgentProviderRequest(
        requestId: 'failover-request',
        profile: profile,
        context: _emptyContext(),
        userPrompt: 'Use fallback.',
      ),
    );

    expect(adapter.kind, AgentProviderKind.cloudOpenAICompatible);
    expect(adapter.adapterId, 'openai-compatible-cloud');
    expect(cloudTransport.callCount, 1);
    expect(localTransport.callCount, 0);
    expect(
      cloudTransport.lastEndpoint.toString(),
      'https://agent.example.test/v1/chat/completions',
    );
    expect(cloudTransport.lastBody['model'], 'gpt-cloud-fallback');
  });
}

AgentPromptProfile _profile({
  required AgentProviderRoute route,
  required String baseUrl,
  String model = 'gpt-route-test',
  List<AgentProviderEndpoint> fallbackEndpoints =
      const <AgentProviderEndpoint>[],
}) {
  return AgentPromptProfile(
    profileId: 'route-test',
    displayName: 'Route Test',
    systemPrompt: 'Use IDE context.',
    endpoint: AgentProviderEndpoint(
      route: route,
      baseUrl: baseUrl,
      model: model,
    ),
    fallbackEndpoints: fallbackEndpoints,
  );
}

ConfigurationStore _configurationStore(Directory tempRoot) {
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: tempRoot.path,
      homePath: tempRoot.path,
    ),
  );
  return ConfigurationStore(
    dataStore: FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
    ),
    credentialDataStore: InMemoryCredentialDataStore(),
  );
}

AgentSessionContext _emptyContext() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: '/workspace/demo/src/main.styio',
      text: '',
      revision: 0,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
  );
}

class _RecordingTransport implements AgentProviderTransport {
  int callCount = 0;
  Uri? lastEndpoint;
  Map<String, Object?> lastBody = const <String, Object?>{};

  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    callCount += 1;
    lastEndpoint = endpoint;
    lastBody = body;
    return <String, Object?>{
      'id': 'chatcmpl-route-test',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': 'route ok',
          },
        },
      ],
    };
  }
}
