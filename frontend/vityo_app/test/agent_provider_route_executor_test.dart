import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
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
    final plan =
        AgentProviderRouteExecutor(
          localServiceManager:
              LoopbackLocalServiceManager.linuxDebianArmForTest(),
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
    final plan = AgentProviderRouteExecutor(localServiceManager: manager)
        .planFor(
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

  test('agent provider resolution reports credential-based fallback', () async {
    const credentialReference = CredentialReference(
      key: CredentialDataStoreKey(
        namespace: 'agent.provider',
        name: 'primary',
        scope: CredentialScope.user,
      ),
      kind: CredentialKind.token,
    );
    final profile = _profile(
      route: AgentProviderRoute.webHosted,
      baseUrl: 'https://primary.example.test/v1',
      credentialReference: credentialReference,
      fallbackEndpoints: const <AgentProviderEndpoint>[
        AgentProviderEndpoint(
          route: AgentProviderRoute.webHosted,
          baseUrl: 'https://fallback.example.test/v1',
          model: 'gpt-cloud-fallback',
        ),
      ],
    );

    final resolution = await const AgentProviderRouteExecutor().resolve(
      profile,
      credentialAvailable: (endpoint) async {
        return endpoint.credentialReference == null;
      },
    );

    expect(
      resolution.status,
      AgentProviderExecutionResolutionStatus.fallbackReady,
    );
    expect(resolution.selectedEndpointIndex, 1);
    expect(
      resolution.endpoints.first.credentialReadiness,
      AgentProviderCredentialReadiness.unavailable,
    );
    expect(resolution.endpoints.last.executable, isTrue);
    expect(
      resolution.toJson()['status'],
      AgentProviderExecutionResolutionStatus.fallbackReady.wireValue,
    );
  });

  test(
    'agent provider resolution blocks required missing credentials',
    () async {
      final profile = _profile(
        route: AgentProviderRoute.webHosted,
        baseUrl: 'https://api.openai.com/v1',
        requiresCredential: true,
      );

      final resolution = await const AgentProviderRouteExecutor().resolve(
        profile,
      );

      expect(resolution.status, AgentProviderExecutionResolutionStatus.blocked);
      expect(resolution.selectedEndpointIndex, isNull);
      expect(
        resolution.endpoints.single.credentialReadiness,
        AgentProviderCredentialReadiness.unavailable,
      );
      expect(resolution.endpoints.single.executable, isFalse);
    },
  );

  test('agent provider resolution reports probe-based fallback', () async {
    final profile = _profile(
      route: AgentProviderRoute.webHosted,
      baseUrl: 'https://primary.example.test/v1',
      fallbackEndpoints: const <AgentProviderEndpoint>[
        AgentProviderEndpoint(
          route: AgentProviderRoute.webHosted,
          baseUrl: 'https://fallback.example.test/v1',
          model: 'gpt-cloud-fallback',
        ),
      ],
    );

    final resolution = await const AgentProviderRouteExecutor().resolve(
      profile,
      endpointProbe: ({required endpoint, required plan}) async {
        if (endpoint.baseUrl.contains('primary')) {
          return const AgentProviderEndpointProbeResult(
            status: AgentProviderEndpointProbeStatus.unreachable,
            message: 'primary unavailable',
            statusCode: 503,
          );
        }
        return const AgentProviderEndpointProbeResult(
          status: AgentProviderEndpointProbeStatus.reachable,
        );
      },
    );

    expect(
      resolution.status,
      AgentProviderExecutionResolutionStatus.fallbackReady,
    );
    expect(resolution.selectedEndpointIndex, 1);
    expect(
      resolution.endpoints.first.probeResult.status,
      AgentProviderEndpointProbeStatus.unreachable,
    );
    expect(
      resolution.endpoints.last.probeResult.status,
      AgentProviderEndpointProbeStatus.reachable,
    );
    final health = resolution.toHealthReport();

    expect(health.status, AgentProviderServiceHealthStatus.degraded);
    expect(health.fallbackActive, isTrue);
    expect(health.executable, isTrue);
    expect(health.unreachableEndpointCount, 1);
    expect(health.toJson()['status'], 'degraded');
  });

  test('agent provider health report summarizes blocked services', () async {
    final profile = _profile(
      route: AgentProviderRoute.webHosted,
      baseUrl: 'https://api.openai.com/v1',
      requiresCredential: true,
    );

    final resolution = await const AgentProviderRouteExecutor().resolve(
      profile,
    );
    final health = resolution.toHealthReport();

    expect(health.status, AgentProviderServiceHealthStatus.blocked);
    expect(health.ready, isFalse);
    expect(health.executable, isFalse);
    expect(health.missingCredentialCount, 1);
    expect(health.message, contains('missing credential'));
  });

  test(
    'agent provider factory routes loopback requests to local transport',
    () async {
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
        localServiceManager:
            LoopbackLocalServiceManager.linuxDebianArmForTest(),
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
    },
  );

  test(
    'agent provider factory fails over from blocked bridge to cloud',
    () async {
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
    },
  );

  test(
    'agent provider factory skips endpoint with missing credential',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_agent_credential_failover_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      const missingCredential = CredentialReference(
        key: CredentialDataStoreKey(
          namespace: 'agent.provider',
          name: 'missing-primary',
          scope: CredentialScope.user,
        ),
        kind: CredentialKind.token,
      );
      final cloudTransport = _RecordingTransport();
      final factory = ConfiguredAgentProviderAdapterFactory(
        configurationStore: _configurationStore(tempRoot),
        transport: cloudTransport,
      );
      final profile = _profile(
        route: AgentProviderRoute.webHosted,
        baseUrl: 'https://primary.example.test/v1',
        credentialReference: missingCredential,
        fallbackEndpoints: const <AgentProviderEndpoint>[
          AgentProviderEndpoint(
            route: AgentProviderRoute.webHosted,
            baseUrl: 'https://fallback.example.test/v1',
            model: 'gpt-cloud-fallback',
          ),
        ],
      );

      final resolution = await factory.resolveExecution(profile);
      final adapter = await factory.create(profile);
      await adapter.send(
        AgentProviderRequest(
          requestId: 'credential-failover-request',
          profile: profile,
          context: _emptyContext(),
          userPrompt: 'Use credential fallback.',
        ),
      );

      expect(
        resolution.status,
        AgentProviderExecutionResolutionStatus.fallbackReady,
      );
      expect(adapter.kind, AgentProviderKind.cloudOpenAICompatible);
      expect(
        cloudTransport.lastEndpoint.toString(),
        'https://fallback.example.test/v1/chat/completions',
      );
      expect(cloudTransport.lastBody['model'], 'gpt-cloud-fallback');
    },
  );

  test(
    'agent provider factory skips endpoint when probe is unreachable',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_agent_probe_failover_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final cloudTransport = _RecordingTransport();
      final factory = ConfiguredAgentProviderAdapterFactory(
        configurationStore: _configurationStore(tempRoot),
        transport: cloudTransport,
        endpointProbe: ({required endpoint, required plan}) async {
          if (endpoint.baseUrl.contains('primary')) {
            return const AgentProviderEndpointProbeResult(
              status: AgentProviderEndpointProbeStatus.unreachable,
              message: 'primary unavailable',
            );
          }
          return const AgentProviderEndpointProbeResult(
            status: AgentProviderEndpointProbeStatus.reachable,
          );
        },
      );
      final profile = _profile(
        route: AgentProviderRoute.webHosted,
        baseUrl: 'https://primary.example.test/v1',
        fallbackEndpoints: const <AgentProviderEndpoint>[
          AgentProviderEndpoint(
            route: AgentProviderRoute.webHosted,
            baseUrl: 'https://fallback.example.test/v1',
            model: 'gpt-cloud-fallback',
          ),
        ],
      );

      final resolution = await factory.resolveExecution(profile);
      final health = await factory.resolveHealth(profile);
      final adapter = await factory.create(profile);
      await adapter.send(
        AgentProviderRequest(
          requestId: 'probe-failover-request',
          profile: profile,
          context: _emptyContext(),
          userPrompt: 'Use probe fallback.',
        ),
      );

      expect(
        resolution.status,
        AgentProviderExecutionResolutionStatus.fallbackReady,
      );
      expect(
        resolution.endpoints.first.probeResult.status,
        AgentProviderEndpointProbeStatus.unreachable,
      );
      expect(health.status, AgentProviderServiceHealthStatus.degraded);
      expect(health.fallbackActive, isTrue);
      expect(
        cloudTransport.lastEndpoint.toString(),
        'https://fallback.example.test/v1/chat/completions',
      );
      expect(cloudTransport.lastBody['model'], 'gpt-cloud-fallback');
    },
  );

  test(
    'agent provider factory sends OpenAI Responses requests for Codex profile',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_agent_openai_responses_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      const credentialKey = CredentialDataStoreKey(
        namespace: 'agent.provider',
        name: 'openai-codex',
        scope: CredentialScope.user,
      );
      const credentialReference = CredentialReference(
        key: credentialKey,
        kind: CredentialKind.token,
      );
      final credentials = InMemoryCredentialDataStore();
      final configurationStore = _configurationStore(
        tempRoot,
        credentialDataStore: credentials,
      );
      await credentials.write(
        CredentialSecretRecord(
          key: credentialKey,
          kind: CredentialKind.token,
          secretValue: 'codex-test-token',
        ),
      );
      final baseProfile = AgentPromptProfile.openAICodexForPlatform(
        PlatformTarget.linux,
      );
      final profile = baseProfile.copyWith(
        endpoint: AgentProviderEndpoint(
          route: baseProfile.endpoint.route,
          baseUrl: baseProfile.endpoint.baseUrl,
          model: baseProfile.endpoint.model,
          protocol: baseProfile.endpoint.protocol,
          reasoningEffort: baseProfile.endpoint.reasoningEffort,
          credentialReference: credentialReference,
          requiresCredential: baseProfile.endpoint.requiresCredential,
        ),
      );
      final transport = _RecordingTransport(
        response: <String, Object?>{
          'id': 'resp-codex-test',
          'status': 'completed',
          'output_text': 'codex ok',
        },
      );
      final factory = ConfiguredAgentProviderAdapterFactory(
        configurationStore: configurationStore,
        transport: transport,
      );

      final resolution = await factory.resolveExecution(profile);
      final adapter = await factory.create(profile);
      final response = await adapter.send(
        AgentProviderRequest(
          requestId: 'codex-responses-request',
          profile: profile,
          context: _emptyContext(),
          userPrompt: 'Review this Styio file.',
        ),
      );

      expect(baseProfile.endpoint.protocol, 'openai-responses');
      expect(baseProfile.endpoint.model, 'gpt-5.3-codex');
      expect(baseProfile.endpoint.reasoningEffort, 'high');
      expect(resolution.status, AgentProviderExecutionResolutionStatus.ready);
      expect(adapter, isA<OpenAIResponsesAgentProviderAdapter>());
      expect(adapter.kind, AgentProviderKind.cloudOpenAICompatible);
      expect(
        transport.lastEndpoint.toString(),
        'https://api.openai.com/v1/responses',
      );
      expect(transport.lastHeaders['Authorization'], 'Bearer codex-test-token');
      expect(transport.lastBody['model'], 'gpt-5.3-codex');
      expect(
        (transport.lastBody['reasoning']! as Map<String, Object?>)['effort'],
        'high',
      );
      final tools = transport.lastBody['tools']! as List<Object?>;
      final toolNames = tools
          .whereType<Map<String, Object?>>()
          .map((tool) => tool['name'])
          .toList(growable: false);
      expect(toolNames, contains('vityo_code_patch'));
      expect(toolNames, contains('vityo_ide_command'));
      expect(toolNames, contains('vityo_coding_plan'));
      expect(toolNames, contains('vityo_diagnostic_summary'));
      expect(transport.lastBody['tool_choice'], 'auto');
      final firstTool = tools.first! as Map<String, Object?>;
      final parameters = firstTool['parameters']! as Map<String, Object?>;
      expect(parameters['required'], contains('contentParts'));
      expect(transport.lastBody['instructions'], contains('contentParts'));
      expect(transport.lastBody['input'], isA<List<Object?>>());
      expect(
        ((transport.lastBody['metadata']!
            as Map<String, Object?>)['requestId']),
        'codex-responses-request',
      );
      expect(response.providerMessageId, 'resp-codex-test');
      expect(response.contentParts.single.text, 'codex ok');
    },
  );

  test(
    'OpenAI Codex Spark profile requires user-managed API credential',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_agent_codex_spark_credential_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final profile = AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      );
      final factory = ConfiguredAgentProviderAdapterFactory(
        configurationStore: _configurationStore(tempRoot),
        transport: _RecordingTransport(),
      );

      final resolution = await factory.resolveExecution(profile);
      final endpointJson = profile.endpoint.toJson();
      final credentialJson =
          endpointJson['credentialReference']! as Map<String, Object?>;
      final credentialKeyJson = credentialJson['key']! as Map<String, Object?>;

      expect(profile.endpoint.protocol, 'openai-responses');
      expect(profile.endpoint.model, 'gpt-5.3-codex-spark');
      expect(profile.endpoint.requiresCredential, isTrue);
      expect(credentialJson['kind'], 'remote-service-credential');
      expect(credentialJson['displayName'], 'OpenAI API key');
      expect(credentialKeyJson['namespace'], 'agent.provider');
      expect(credentialKeyJson['name'], 'openai-api-key');
      expect(credentialKeyJson['scope'], 'user');
      expect(endpointJson.toString(), isNot(contains('secretValue')));
      expect(resolution.status, AgentProviderExecutionResolutionStatus.blocked);
      expect(
        resolution.endpoints.single.credentialReadiness,
        AgentProviderCredentialReadiness.unavailable,
      );
    },
  );
}

AgentPromptProfile _profile({
  required AgentProviderRoute route,
  required String baseUrl,
  String model = 'gpt-route-test',
  CredentialReference? credentialReference,
  bool requiresCredential = false,
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
      credentialReference: credentialReference,
      requiresCredential: requiresCredential,
    ),
    fallbackEndpoints: fallbackEndpoints,
  );
}

ConfigurationStore _configurationStore(
  Directory tempRoot, {
  CredentialDataStore? credentialDataStore,
}) {
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
    credentialDataStore: credentialDataStore ?? InMemoryCredentialDataStore(),
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
  _RecordingTransport({Map<String, Object?>? response})
    : response =
          response ??
          <String, Object?>{
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

  final Map<String, Object?> response;
  int callCount = 0;
  Uri? lastEndpoint;
  Map<String, String> lastHeaders = const <String, String>{};
  Map<String, Object?> lastBody = const <String, Object?>{};

  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    callCount += 1;
    lastEndpoint = endpoint;
    lastHeaders = headers;
    lastBody = body;
    return response;
  }
}
