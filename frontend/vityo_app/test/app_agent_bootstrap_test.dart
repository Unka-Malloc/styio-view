import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_registry.dart';
import 'package:vityo_app/src/agent/agent_provider_route_executor.dart';
import 'package:vityo_app/src/agent/agent_tool_call_dispatcher.dart';
import 'package:vityo_app/src/agent/agent_tool_registry.dart';
import 'package:vityo_app/src/app/app_bootstrap.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/agent/agent_coding_session_history_store.dart';
import 'package:vityo_app/src/view_ide/agent/extension_agent_tool_contributions.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime_output_channels.dart';

void main() {
  test(
    'agent bootstrap keeps local-only mode without persisted profile',
    () async {
      final registry = AgentProviderRegistry(
        registrations: <AgentProviderRegistration>[
          AgentProviderRegistration(
            providerId: 'hosted',
            displayName: 'Hosted Agent Provider',
            kind: AgentProviderKind.cloudOpenAICompatible,
            supportedRoutes: const <String>['web-hosted'],
            supportedProtocols: const <String>['openai-compatible'],
            createAdapter: (_) async => const LocalOnlyAgentProviderAdapter(),
          ),
        ],
      );
      final controller = await AppBootstrap.createAgentCodingSessionController(
        platformTarget: PlatformTarget.web,
        loadPersistedProfile: () async => null,
        createConfiguredAdapter: (_) {
          fail('default bootstrap must not create a network provider');
        },
        selectConfiguredProvider: registry.selectionPlan,
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

      expect(controller.profile.profileId, 'default-web');
      expect(controller.adapter, isA<LocalOnlyAgentProviderAdapter>());
      expect(controller.providerSelectionPlan?.ready, isTrue);
      expect(
        controller.providerSelectionPlan?.selectedProvider?.providerId,
        'hosted',
      );
      expect(controller.providerExecutionResolution, isNull);
    },
  );

  test(
    'agent bootstrap projects mounted modules into extension startup plan',
    () {
      const module = ModuleDefinition(
        manifest: ModuleManifest(
          moduleId: 'agent.surface.basic',
          displayName: 'Agent Surface',
          version: '1.0.0',
          kind: ModuleKind.core,
          slot: ModuleSlot.agentSurface,
          description: 'Agent UI',
          enabledByDefault: true,
          entrypoint: 'agent_surface.dart',
          distributionPolicyRef: 'core-policy',
          capabilityFlags: <String, bool>{'agentSurface': true},
          extensionActivationEvents: <String>['onStartup'],
          extensionContributions: <Map<String, Object?>>[
            <String, Object?>{
              'kind': 'agent',
              'id': 'collect-agent-surface-context',
              'target': 'agent.tools',
              'metadata': <String, Object?>{
                'toolId': 'collectAgentSurfaceContext',
                'handlerId': 'collect-agent-surface-context',
              },
            },
          ],
          extensionMetadata: <String, Object?>{
            'isolationMode': 'local-process',
          },
        ),
        matrix: ModuleCapabilityMatrix(
          moduleId: 'agent.surface.basic',
          platforms: <PlatformTarget, ModuleCapabilityRule>{
            PlatformTarget.linux: ModuleCapabilityRule(
              supported: true,
              visible: true,
              installable: true,
              mountedByDefault: true,
              iosSafe: true,
              distributionChannel: 'self-hosted',
              note: 'Mounted in tests.',
            ),
          },
        ),
      );
      final moduleRegistry = ModuleRegistry(
        platformTarget: PlatformTarget.linux,
        definitions: const <ModuleDefinition>[module],
      );

      final plan = AppBootstrap.createExtensionStartupPlan(
        moduleRegistry: moduleRegistry,
        clock: () => DateTime.utc(2026, 5, 22),
      );

      expect(
        plan.manifestRegistry.list().single.extensionId,
        'agent.surface.basic',
      );
      expect(plan.activationSession.activatedExtensionIds, <String>[
        'agent.surface.basic',
      ]);
      expect(plan.supervisorSnapshot.startingExtensionIds, <String>[
        'agent.surface.basic',
      ]);
      expect(
        plan.supervisorSnapshot.lookup('agent.surface.basic')?.action,
        ExtensionHostSupervisorAction.spawnLocalProcess,
      );
      expect(
        plan.contributionRoutes.routes.single.contribution.id,
        'collect-agent-surface-context',
      );
      expect(plan.toJson()['manifestCount'], 1);
    },
  );

  test(
    'agent bootstrap installs extension agent tools from activated routes',
    () async {
      final routes = ExtensionContributionRouteManifest(
        routes: <ExtensionContributionRoute>[
          const ExtensionContributionRouter().routeContribution(
            extensionId: 'agent.tools',
            contribution: const ExtensionContributionPoint(
              kind: ExtensionContributionKind.agent,
              id: 'collect-extension-context',
              target: 'agent.tools',
              metadata: <String, Object?>{
                'toolId': 'collectExtensionContext',
                'description': 'Collect context from an extension.',
                'permissionMode': 'never',
              },
            ),
          ),
        ],
      );

      final controller = await AppBootstrap.createAgentCodingSessionController(
        platformTarget: PlatformTarget.web,
        loadPersistedProfile: () async => null,
        createConfiguredAdapter: (_) {
          fail('default bootstrap must not create a network provider');
        },
        extensionContributionRoutes: routes,
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

      final dispatchPlan = controller.previewDispatchPlan();
      expect(
        dispatchPlan.toolSelection.toolIds,
        contains('collectExtensionContext'),
      );
      expect(
        dispatchPlan.toolPermissionPlan.allowedToolIds,
        contains('collectExtensionContext'),
      );

      final executionRegistry =
          AppBootstrap.createAgentExtensionToolExecutionRegistry(
            extensionContributionRoutes: routes,
          );
      final dispatchResult = await executionRegistry!.dispatch(
        const AgentToolCallDispatchRequest(
          callId: 'call-extension-context',
          toolId: 'collectExtensionContext',
          inputText: '{}',
        ),
      );
      expect(executionRegistry.toolIds, contains('collectExtensionContext'));
      expect(
        executionRegistry.handlerToolIds,
        isNot(contains('collectExtensionContext')),
      );
      expect(dispatchResult.success, isFalse);
      expect(dispatchResult.metadata['missingHandler'], isTrue);

      final bridgedRegistry =
          AppBootstrap.createAgentExtensionToolExecutionRegistry(
            extensionContributionRoutes: routes,
            hostBridge: (request) async {
              return AgentToolCallDispatchResult.success(
                callId: request.toolCall.callId,
                toolId: request.toolCall.toolId,
                output: '{"extension":"bootstrap"}',
                metadata: <String, Object?>{'handlerId': request.handlerId},
              );
            },
          );
      final bridgedResult = await bridgedRegistry!.dispatch(
        const AgentToolCallDispatchRequest(
          callId: 'call-extension-context',
          toolId: 'collectExtensionContext',
          inputText: '{}',
        ),
      );
      expect(bridgedResult.success, isTrue);
      expect(bridgedResult.metadata['handlerId'], 'collect-extension-context');

      final activatedHostBridge =
          AppBootstrap.createExtensionAgentToolHostBridge(
            snapshot: const ExtensionHostSupervisorSnapshot(
              records: <ExtensionHostSupervisorRecord>[],
            ),
            buffer: RuntimeOutputLiveBuffer(),
          );
      final missingHostResult = await activatedHostBridge(
        const ExtensionAgentToolHostRequest(
          extensionId: 'agent.tools',
          contributionId: 'collect-extension-context',
          handlerId: 'collect-extension-context',
          toolCall: AgentToolCallDispatchRequest(
            callId: 'call-extension-context',
            toolId: 'collectExtensionContext',
            inputText: '{}',
          ),
        ),
      );
      expect(missingHostResult.success, isFalse);
      expect(missingHostResult.metadata['missingSupervisorRecord'], isTrue);
    },
  );

  test(
    'agent bootstrap wires extension tools through rpc transport catalog',
    () async {
      final manifestRegistry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'agent.tools',
            displayName: 'Agent Tools',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'agent_tools.dart',
            activationEvents: <String>['onCommand:collectContext'],
            trustedByDefault: true,
            metadata: <String, Object?>{'isolationMode': 'local-process'},
            contributions: <ExtensionContributionPoint>[
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.agent,
                id: 'collect-extension-context',
                target: 'agent.tools',
                metadata: <String, Object?>{
                  'toolId': 'collectExtensionContext',
                  'handlerId': 'collect-context',
                  'permissionMode': 'never',
                },
              ),
            ],
          ),
        );
      final routes = const ExtensionContributionRouter().routeRegistry(
        manifestRegistry,
      );
      final session = ExtensionActivator(
        clock: () => DateTime.utc(2026, 5, 22),
      ).activate(registry: manifestRegistry, event: 'onCommand:collectContext');
      final snapshot = ExtensionHostSupervisor(
        clock: () => DateTime.utc(2026, 5, 22, 1),
      ).applyActivation(registry: manifestRegistry, session: session);
      final buffer = RuntimeOutputLiveBuffer();
      ExtensionAgentToolHostRpcRequest? rpcRequest;
      final executionRegistry =
          AppBootstrap.createAgentExtensionToolExecutionRegistry(
            extensionContributionRoutes: routes,
            extensionHostSupervisorSnapshot: snapshot,
            runtimeOutputBuffer: buffer,
            extensionManifestRegistry: manifestRegistry,
            rpcTransports:
                <
                  ExtensionHostSupervisorAction,
                  ExtensionAgentToolHostRpcTransport
                >{
                  ExtensionHostSupervisorAction.spawnLocalProcess:
                      (request) async {
                        rpcRequest = request;
                        return AgentToolCallDispatchResult.success(
                          callId: request.toolCall.callId,
                          toolId: request.toolCall.toolId,
                          output: '{"extension":"bootstrap-rpc"}',
                          metadata: <String, Object?>{
                            'requestAction': request.action.wireValue,
                          },
                        );
                      },
                },
            rpcTransportEndpoints:
                const <ExtensionHostSupervisorAction, String>{
                  ExtensionHostSupervisorAction.spawnLocalProcess:
                      'proc://agent.tools',
                },
            rpcTransportMetadataByAction:
                const <ExtensionHostSupervisorAction, Map<String, Object?>>{
                  ExtensionHostSupervisorAction.spawnLocalProcess:
                      <String, Object?>{'sandbox': 'local-process'},
                },
          );
      final transportCatalog =
          AppBootstrap.createExtensionAgentToolRpcTransportCatalog(
            extensionContributionRoutes: routes,
            snapshot: snapshot,
            rpcTransports:
                <
                  ExtensionHostSupervisorAction,
                  ExtensionAgentToolHostRpcTransport
                >{
                  ExtensionHostSupervisorAction.spawnLocalProcess: (_) async {
                    return const AgentToolCallDispatchResult.success(
                      callId: 'catalog-only',
                      toolId: 'collectExtensionContext',
                      output: '{}',
                    );
                  },
                },
          );

      final result = await executionRegistry!.dispatch(
        const AgentToolCallDispatchRequest(
          callId: 'call-extension-context',
          toolId: 'collectExtensionContext',
          inputText: '{}',
        ),
      );

      expect(transportCatalog.ready, isTrue);
      expect(transportCatalog.toJson()['registrationCount'], 1);
      expect(result.success, isTrue);
      expect(result.output, '{"extension":"bootstrap-rpc"}');
      expect(result.metadata['transportId'], 'local-process-rpc');
      expect(result.metadata['endpoint'], 'proc://agent.tools');
      expect(result.metadata['sandbox'], 'local-process');
      expect(result.metadata['requestAction'], 'spawn-local-process');
      expect(rpcRequest?.handlerId, 'collect-context');
      expect(buffer.snapshot.visibleEvents, isNotEmpty);
    },
  );

  test(
    'agent bootstrap dispatches built-in agent surface extension rpc',
    () async {
      final manifestRegistry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'agent.surface.basic',
            displayName: 'Agent Surface',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'agent_surface.dart',
            activationEvents: <String>['onStartup'],
            trustedByDefault: true,
            metadata: <String, Object?>{'isolationMode': 'in-process'},
            contributions: <ExtensionContributionPoint>[
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.agent,
                id: 'collect-agent-surface-context',
                target: 'agent.tools',
                metadata: <String, Object?>{
                  'toolId': 'collectAgentSurfaceContext',
                  'handlerId': 'collect-agent-surface-context',
                  'permissionMode': 'never',
                },
              ),
            ],
          ),
        );
      final routes = const ExtensionContributionRouter().routeRegistry(
        manifestRegistry,
      );
      final session = ExtensionActivator(
        clock: () => DateTime.utc(2026, 5, 22),
      ).activate(registry: manifestRegistry, event: 'onStartup');
      final snapshot = ExtensionHostSupervisor(
        clock: () => DateTime.utc(2026, 5, 22, 1),
      ).applyActivation(registry: manifestRegistry, session: session);
      final providerRegistry = AgentProviderRegistry(
        registrations: <AgentProviderRegistration>[
          AgentProviderRegistration(
            providerId: 'hosted',
            displayName: 'Hosted Agent Provider',
            kind: AgentProviderKind.cloudOpenAICompatible,
            supportedRoutes: const <String>['web-hosted'],
            supportedProtocols: const <String>['openai-compatible'],
            createAdapter: (_) async => const LocalOnlyAgentProviderAdapter(),
          ),
        ],
      );
      final executionRegistry =
          AppBootstrap.createAgentExtensionToolExecutionRegistry(
            extensionContributionRoutes: routes,
            extensionHostSupervisorSnapshot: snapshot,
            runtimeOutputBuffer: RuntimeOutputLiveBuffer(),
            extensionManifestRegistry: manifestRegistry,
            rpcTransports:
                AppBootstrap.createBuiltInExtensionAgentToolRpcTransports(
                  platformTarget: PlatformTarget.linux,
                  agentProviderRegistry: providerRegistry,
                ),
          );

      final result = await executionRegistry!.dispatch(
        const AgentToolCallDispatchRequest(
          callId: 'call-agent-surface-context',
          toolId: 'collectAgentSurfaceContext',
          inputText: '{"includeProviderStatus":true}',
        ),
      );
      final output = Map<String, Object?>.from(
        jsonDecode(result.output) as Map,
      );

      expect(result.success, isTrue);
      expect(
        result.metadata['source'],
        'app-bootstrap-in-process-extension-rpc',
      );
      expect(result.metadata['includeProviderStatus'], isTrue);
      expect(output['schema'], 'vityo.agent-surface-context.v1');
      expect(output['platformTarget'], 'linux');
      expect(output['transportAction'], 'run-in-process');
      expect(output['providerRegistry'], isA<Map<String, Object?>>());
    },
  );

  test(
    'agent bootstrap prefers explicit tool registry over extension routes',
    () async {
      final controller = await AppBootstrap.createAgentCodingSessionController(
        platformTarget: PlatformTarget.web,
        loadPersistedProfile: () async => null,
        createConfiguredAdapter: (_) {
          fail('default bootstrap must not create a network provider');
        },
        toolRegistry: AgentToolRegistry(
          tools: const <AgentToolDefinition>[
            AgentToolDefinition(
              toolId: 'explicitTool',
              displayName: 'Explicit Tool',
              description: 'Explicitly injected test tool.',
              permissionMode: AgentToolPermissionMode.never,
            ),
          ],
        ),
        extensionContributionRoutes: const ExtensionContributionRouteManifest(
          routes: <ExtensionContributionRoute>[],
        ),
        contextProvider: _context,
      );
      addTearDown(controller.dispose);

      expect(controller.previewDispatchPlan().toolSelection.toolIds, <String>[
        'explicitTool',
      ]);
    },
  );

  test(
    'agent bootstrap provider factory resolves host environment API key',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_agent_bootstrap_provider_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = _createConfigurationStore(tempRoot);
      final factory = AppBootstrap.createAgentProviderFactory(
        configurationStore: configurationStore,
        transport: const _NoopAgentProviderTransport(),
        environment: const <String, String>{'OPENAI_API_KEY': 'host-token'},
      );
      final profile = AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      );

      final execution = await factory.resolveExecution(profile);

      expect(execution.status, AgentProviderExecutionResolutionStatus.ready);
      expect(execution.selectedEndpointIndex, 0);
      expect(
        execution.endpoints.single.credentialReadiness,
        AgentProviderCredentialReadiness.available,
      );
    },
  );

  test('host environment reader is exposed through configuration layer', () {
    expect(readHostEnvironment(), isA<Map<String, String>>());
  });

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

ConfigurationStore _createConfigurationStore(Directory root) {
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: root.path,
      homePath: root.path,
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
