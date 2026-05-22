import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test('extension agent provider catalog converts agent routes', () {
    final registry = ExtensionManifestRegistry()
      ..register(
        const ExtensionManifest(
          extensionId: 'codex.provider',
          displayName: 'Codex Provider',
          version: '1.0.0',
          publisher: 'vityo',
          entrypoint: 'codex_provider.dart',
          trustedByDefault: true,
          contributions: <ExtensionContributionPoint>[
            ExtensionContributionPoint(
              kind: ExtensionContributionKind.agent,
              id: 'codex-5.3-spark',
              target: 'agent.providers',
              title: 'Codex 5.3 Spark',
              metadata: <String, Object?>{
                'providerId': 'codex.spark',
                'kind': 'cloud_openai_compatible',
                'priority': 100,
                'supportsCodePatch': true,
                'supportedRoutes': <String>['desktop_local_bridge'],
                'supportedProtocols': <String>['openai-compatible'],
                'capabilities': <String>['code_patch', 'ide_command'],
              },
            ),
          ],
        ),
      );
    final routes = const ExtensionContributionRouter().routeRegistry(registry);

    final catalog = ExtensionAgentProviderContributionCatalog.fromRoutes(
      routes,
    );
    final manifest = catalog.readyManifests.single;

    expect(manifest.providerId, 'codex.spark');
    expect(manifest.displayName, 'Codex 5.3 Spark');
    expect(manifest.kind, AgentProviderKind.cloudOpenAICompatible);
    expect(manifest.priority, 100);
    expect(manifest.supportsCodePatch, isTrue);
    expect(manifest.supportedProtocols, <String>['openai-compatible']);
    expect(catalog.toJson()['readyProviderCount'], 1);
  });

  test('extension agent provider catalog reports missing provider kind', () {
    final route = const ExtensionContributionRouter().routeContribution(
      extensionId: 'broken.agent',
      contribution: const ExtensionContributionPoint(
        kind: ExtensionContributionKind.agent,
        id: 'broken',
        target: 'agent.providers',
      ),
    );

    final catalog = ExtensionAgentProviderContributionCatalog.fromRoutes(
      ExtensionContributionRouteManifest(
        routes: <ExtensionContributionRoute>[route],
      ),
    );

    expect(catalog.readyManifests, isEmpty);
    expect(
      catalog.contributions.single.status,
      ExtensionAgentProviderContributionStatus.missingKind,
    );
  });

  test('extension agent tool catalog converts agent tool routes', () {
    final registry = ExtensionManifestRegistry()
      ..register(
        const ExtensionManifest(
          extensionId: 'agent.tools',
          displayName: 'Agent Tools',
          version: '1.0.0',
          publisher: 'vityo',
          entrypoint: 'agent_tools.dart',
          trustedByDefault: true,
          contributions: <ExtensionContributionPoint>[
            ExtensionContributionPoint(
              kind: ExtensionContributionKind.agent,
              id: 'collect-extension-context',
              target: 'agent.tools',
              title: 'Collect Extension Context',
              metadata: <String, Object?>{
                'toolId': 'collectExtensionContext',
                'handlerId': 'collect-context',
                'description': 'Collect context from an extension.',
                'permissionMode': 'never',
                'supportedProviderKinds': <String>['cloud_openai_compatible'],
                'supportedProtocols': <String>['openai-responses'],
                'outputLimit': 4096,
                'providerOutputLimits': <String, Object?>{
                  'cloud_openai_compatible': 2048,
                },
                'capabilities': <String>['extension.context'],
                'schema': <Object?>[
                  <String, Object?>{
                    'name': 'extensionId',
                    'type': 'string',
                    'required': true,
                    'description': 'Extension id.',
                  },
                ],
                'resultSchema': <Object?>[
                  <String, Object?>{
                    'name': 'source',
                    'type': 'string',
                    'required': true,
                  },
                  <String, Object?>{
                    'name': 'extension',
                    'type': 'object',
                    'required': true,
                  },
                ],
              },
            ),
          ],
        ),
      );
    final routes = const ExtensionContributionRouter().routeRegistry(registry);

    final catalog = ExtensionAgentToolContributionCatalog.fromRoutes(routes);
    final contribution = catalog.readyContributions.single;
    final tool = catalog.readyTools.single;
    final selection = catalog.toRegistry().selectForProfile(
      profile: AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.linux,
      ),
      providerKind: AgentProviderKind.cloudOpenAICompatible,
    );

    expect(contribution.handlerId, 'collect-context');
    expect(tool.toolId, 'collectExtensionContext');
    expect(tool.builtin, isFalse);
    expect(tool.permissionMode, AgentToolPermissionMode.never);
    expect(tool.todo, isEmpty);
    expect(tool.outputLimit, 4096);
    expect(tool.providerOutputLimits, <AgentProviderKind, int>{
      AgentProviderKind.cloudOpenAICompatible: 2048,
    });
    expect(tool.schema.single.name, 'extensionId');
    expect(tool.resultSchema.map((property) => property.name), <String>[
      'source',
      'extension',
    ]);
    expect(tool.resultJsonSchema()['required'], <String>[
      'source',
      'extension',
    ]);
    expect(selection.toolIds, contains('collectExtensionContext'));
    expect(catalog.toJson()['readyToolCount'], 1);
  });

  test('extension agent provider catalog ignores agent tool routes', () {
    final route = const ExtensionContributionRouter().routeContribution(
      extensionId: 'agent.tools',
      contribution: const ExtensionContributionPoint(
        kind: ExtensionContributionKind.agent,
        id: 'collect-extension-context',
        target: 'agent.tools',
      ),
    );

    final catalog = ExtensionAgentProviderContributionCatalog.fromRoutes(
      ExtensionContributionRouteManifest(
        routes: <ExtensionContributionRoute>[route],
      ),
    );

    expect(catalog.contributions, isEmpty);
    expect(catalog.readyManifests, isEmpty);
  });

  test('extension agent tool execution registry dispatches handlers', () async {
    final catalog = ExtensionAgentToolContributionCatalog.fromRoutes(
      ExtensionContributionRouteManifest(
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
              },
            ),
          ),
        ],
      ),
    );
    final registry = ExtensionAgentToolExecutionRegistry(
      catalog: catalog,
      handlers: <String, ExtensionAgentToolHandler>{
        'collectExtensionContext': (request) async {
          return AgentToolCallDispatchResult.success(
            callId: request.callId,
            toolId: request.toolId,
            output: '{"extension":"ok"}',
            metadata: const <String, Object?>{'source': 'extension-host'},
          );
        },
      },
    );

    final result = await registry.dispatch(
      const AgentToolCallDispatchRequest(
        callId: 'call-extension',
        toolId: 'collectExtensionContext',
        inputText: '{"extensionId":"demo"}',
      ),
    );

    expect(registry.canHandle('collectExtensionContext'), isTrue);
    expect(result.success, isTrue);
    expect(result.output, '{"extension":"ok"}');
    expect(registry.toJson()['missingHandlerToolIds'], isEmpty);
  });

  test(
    'extension agent tool execution registry bridges host handlers',
    () async {
      final catalog = ExtensionAgentToolContributionCatalog.fromRoutes(
        ExtensionContributionRouteManifest(
          routes: <ExtensionContributionRoute>[
            const ExtensionContributionRouter().routeContribution(
              extensionId: 'agent.tools',
              contribution: const ExtensionContributionPoint(
                kind: ExtensionContributionKind.agent,
                id: 'collect-extension-context',
                target: 'agent.tools',
                metadata: <String, Object?>{
                  'toolId': 'collectExtensionContext',
                  'handlerId': 'collect-context',
                },
              ),
            ),
          ],
        ),
      );
      ExtensionAgentToolHostRequest? hostRequest;
      final registry = ExtensionAgentToolExecutionRegistry.fromHostBridge(
        catalog: catalog,
        hostBridge: (request) async {
          hostRequest = request;
          return AgentToolCallDispatchResult.success(
            callId: request.toolCall.callId,
            toolId: request.toolCall.toolId,
            output: '{"extension":"host"}',
            metadata: <String, Object?>{
              'source': 'extension-host-bridge',
              'handlerId': request.handlerId,
            },
          );
        },
      );

      final result = await registry.dispatch(
        const AgentToolCallDispatchRequest(
          callId: 'call-extension',
          toolId: 'collectExtensionContext',
          inputText: '{"extensionId":"demo"}',
        ),
      );

      expect(registry.canHandle('collectExtensionContext'), isTrue);
      expect(hostRequest?.extensionId, 'agent.tools');
      expect(hostRequest?.contributionId, 'collect-extension-context');
      expect(hostRequest?.handlerId, 'collect-context');
      expect(hostRequest?.toolCall.inputText, '{"extensionId":"demo"}');
      expect(result.success, isTrue);
      expect(result.metadata['handlerId'], 'collect-context');
    },
  );

  test(
    'extension agent tool execution registry bridges activated extension hosts',
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
      final activeRoutes = const ExtensionContributionRouter().routeRegistry(
        manifestRegistry,
      );
      final activeCatalog = ExtensionAgentToolContributionCatalog.fromRoutes(
        activeRoutes,
      );
      final session = ExtensionActivator(
        clock: () => DateTime.utc(2026, 5, 22),
      ).activate(registry: manifestRegistry, event: 'onCommand:collectContext');
      final snapshot = ExtensionHostSupervisor(
        clock: () => DateTime.utc(2026, 5, 22, 1),
      ).applyActivation(registry: manifestRegistry, session: session);
      final buffer = RuntimeOutputLiveBuffer();
      ExtensionAgentToolHostInvocation? invocation;
      final invokerRegistry = ExtensionAgentToolHostInvokerRegistry(
        registrations: <ExtensionAgentToolHostInvokerRegistration>[
          ExtensionAgentToolHostInvokerRegistration(
            extensionId: 'agent.tools',
            handlerId: 'collect-context',
            label: 'Collect Context Fixture',
            metadata: const <String, Object?>{'transport': 'fixture-rpc'},
            invoker: (request) async {
              invocation = request;
              return AgentToolCallDispatchResult.success(
                callId: request.toolCall.callId,
                toolId: request.toolCall.toolId,
                output: '{"extension":"active-host"}',
                metadata: <String, Object?>{'dispatched': request.dispatched},
              );
            },
          ),
        ],
      );
      final hostBridge = ExtensionAgentToolActivatedHostBridge(
        snapshot: snapshot,
        buffer: buffer,
        manifestRegistry: manifestRegistry,
        clock: () => DateTime.utc(2026, 5, 22, 2),
        invoker: invokerRegistry.invoke,
      );
      final registry = ExtensionAgentToolExecutionRegistry.fromHostBridge(
        catalog: activeCatalog,
        hostBridge: hostBridge.call,
      );

      final result = await registry.dispatch(
        const AgentToolCallDispatchRequest(
          callId: 'call-extension',
          toolId: 'collectExtensionContext',
          inputText: '{"extensionId":"demo"}',
        ),
      );

      expect(result.success, isTrue);
      expect(result.output, '{"extension":"active-host"}');
      expect(result.metadata['handlerId'], 'collect-context');
      expect(result.metadata['dispatched'], isTrue);
      expect(result.metadata['invokerLabel'], 'Collect Context Fixture');
      expect(result.metadata['transport'], 'fixture-rpc');
      expect(invocation?.extensionId, 'agent.tools');
      expect(invocation?.handlerId, 'collect-context');
      expect(invocation?.plan.ready, isTrue);
      expect(invocation?.dispatchResult.dispatched, isTrue);
      expect(buffer.snapshot.visibleEvents, isNotEmpty);
      expect(
        buffer.snapshot.visibleEvents.single.metadata['agentToolHostBridge'],
        isTrue,
      );
      expect(invokerRegistry.toJson()['registrationCount'], 1);
    },
  );

  test(
    'extension agent tool host invoker registry reports missing rpc handlers',
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
                },
              ),
            ],
          ),
        );
      final session = ExtensionActivator(
        clock: () => DateTime.utc(2026, 5, 22),
      ).activate(registry: manifestRegistry, event: 'onCommand:collectContext');
      final snapshot = ExtensionHostSupervisor(
        clock: () => DateTime.utc(2026, 5, 22, 1),
      ).applyActivation(registry: manifestRegistry, session: session);
      final bridge = ExtensionAgentToolActivatedHostBridge(
        snapshot: snapshot,
        buffer: RuntimeOutputLiveBuffer(),
        manifestRegistry: manifestRegistry,
        clock: () => DateTime.utc(2026, 5, 22, 2),
        invoker: ExtensionAgentToolHostInvokerRegistry().invoke,
      );

      final result = await bridge.call(
        const ExtensionAgentToolHostRequest(
          extensionId: 'agent.tools',
          contributionId: 'collect-extension-context',
          handlerId: 'missing-handler',
          toolCall: AgentToolCallDispatchRequest(
            callId: 'call-extension',
            toolId: 'collectExtensionContext',
            inputText: '{}',
          ),
        ),
      );

      expect(result.success, isFalse);
      expect(result.metadata['missingHostInvokerRegistration'], isTrue);
      expect(result.metadata['extensionId'], 'agent.tools');
      expect(result.metadata['handlerId'], 'missing-handler');
    },
  );

  test(
    'extension agent tool host rpc transport registry routes active hosts',
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
                },
              ),
            ],
          ),
        );
      final routes = const ExtensionContributionRouter().routeRegistry(
        manifestRegistry,
      );
      final catalog = ExtensionAgentToolContributionCatalog.fromRoutes(routes);
      final session = ExtensionActivator(
        clock: () => DateTime.utc(2026, 5, 22),
      ).activate(registry: manifestRegistry, event: 'onCommand:collectContext');
      final snapshot = ExtensionHostSupervisor(
        clock: () => DateTime.utc(2026, 5, 22, 1),
      ).applyActivation(registry: manifestRegistry, session: session);
      ExtensionAgentToolHostRpcRequest? rpcRequest;
      final transportCatalog =
          ExtensionAgentToolHostRpcTransportCatalog.fromContributions(
            catalog: catalog,
            snapshot: snapshot,
            transports:
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
                          output: '{"extension":"rpc"}',
                          metadata: <String, Object?>{
                            'requestAction': request.action.wireValue,
                          },
                        );
                      },
                },
            endpoints: const <ExtensionHostSupervisorAction, String>{
              ExtensionHostSupervisorAction.spawnLocalProcess:
                  'proc://agent.tools',
            },
            metadataByAction:
                const <ExtensionHostSupervisorAction, Map<String, Object?>>{
                  ExtensionHostSupervisorAction.spawnLocalProcess:
                      <String, Object?>{'sandbox': 'local-process'},
                },
          );
      final transportRegistry = transportCatalog.toRegistry();
      expect(transportCatalog.ready, isTrue);
      expect(transportCatalog.issues, isEmpty);
      expect(transportCatalog.toJson()['registrationCount'], 1);
      final bridge = ExtensionAgentToolActivatedHostBridge(
        snapshot: snapshot,
        buffer: RuntimeOutputLiveBuffer(),
        manifestRegistry: manifestRegistry,
        clock: () => DateTime.utc(2026, 5, 22, 2),
        invoker: transportRegistry.invoke,
      );

      final result = await bridge.call(
        const ExtensionAgentToolHostRequest(
          extensionId: 'agent.tools',
          contributionId: 'collect-extension-context',
          handlerId: 'collect-context',
          toolCall: AgentToolCallDispatchRequest(
            callId: 'call-extension',
            toolId: 'collectExtensionContext',
            inputText: '{}',
          ),
        ),
      );

      expect(result.success, isTrue);
      expect(result.output, '{"extension":"rpc"}');
      expect(result.metadata['transportId'], 'local-process-rpc');
      expect(result.metadata['transportLabel'], 'Local Process RPC');
      expect(result.metadata['endpoint'], 'proc://agent.tools');
      expect(result.metadata['sandbox'], 'local-process');
      expect(result.metadata['contributionId'], 'collect-extension-context');
      expect(result.metadata['extensionHostAction'], 'spawn-local-process');
      expect(result.metadata['requestAction'], 'spawn-local-process');
      expect(rpcRequest?.handlerId, 'collect-context');
      expect(rpcRequest?.endpoint, 'proc://agent.tools');
      expect(transportRegistry.toJson()['registrationCount'], 1);
    },
  );

  test(
    'extension agent tool host rpc transport registry reports missing bindings',
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
                },
              ),
            ],
          ),
        );
      final routes = const ExtensionContributionRouter().routeRegistry(
        manifestRegistry,
      );
      final catalog = ExtensionAgentToolContributionCatalog.fromRoutes(routes);
      final session = ExtensionActivator(
        clock: () => DateTime.utc(2026, 5, 22),
      ).activate(registry: manifestRegistry, event: 'onCommand:collectContext');
      final snapshot = ExtensionHostSupervisor(
        clock: () => DateTime.utc(2026, 5, 22, 1),
      ).applyActivation(registry: manifestRegistry, session: session);
      final transportCatalog =
          ExtensionAgentToolHostRpcTransportCatalog.fromContributions(
            catalog: catalog,
            snapshot: snapshot,
            transports:
                const <
                  ExtensionHostSupervisorAction,
                  ExtensionAgentToolHostRpcTransport
                >{},
          );
      final bridge = ExtensionAgentToolActivatedHostBridge(
        snapshot: snapshot,
        buffer: RuntimeOutputLiveBuffer(),
        manifestRegistry: manifestRegistry,
        clock: () => DateTime.utc(2026, 5, 22, 2),
        invoker: ExtensionAgentToolHostRpcTransportRegistry().invoke,
      );

      final result = await bridge.call(
        const ExtensionAgentToolHostRequest(
          extensionId: 'agent.tools',
          contributionId: 'collect-extension-context',
          handlerId: 'collect-context',
          toolCall: AgentToolCallDispatchRequest(
            callId: 'call-extension',
            toolId: 'collectExtensionContext',
            inputText: '{}',
          ),
        ),
      );

      expect(transportCatalog.ready, isFalse);
      expect(transportCatalog.issues.single.issueCode, 'missing-rpc-transport');
      expect(result.success, isFalse);
      expect(result.metadata['missingRpcTransportBinding'], isTrue);
      expect(result.metadata['extensionHostAction'], 'spawn-local-process');
    },
  );

  test(
    'extension agent tool activated host bridge blocks inactive hosts',
    () async {
      final manifestRegistry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'agent.tools',
            displayName: 'Agent Tools',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'agent_tools.dart',
            trustedByDefault: true,
            metadata: <String, Object?>{'isolationMode': 'local-process'},
          ),
        );
      final snapshot = ExtensionHostSupervisor(
        clock: () => DateTime.utc(2026, 5, 22),
      ).planRegistry(manifestRegistry);
      final bridge = ExtensionAgentToolActivatedHostBridge(
        snapshot: snapshot,
        buffer: RuntimeOutputLiveBuffer(),
        manifestRegistry: manifestRegistry,
        invoker: (_) async {
          fail('inactive extension hosts must not invoke handlers');
        },
      );

      final result = await bridge.call(
        const ExtensionAgentToolHostRequest(
          extensionId: 'agent.tools',
          contributionId: 'collect-extension-context',
          handlerId: 'collect-context',
          toolCall: AgentToolCallDispatchRequest(
            callId: 'call-extension',
            toolId: 'collectExtensionContext',
            inputText: '{}',
          ),
        ),
      );

      expect(result.success, isFalse);
      expect(result.metadata['inactiveExtensionHost'], isTrue);
      expect(result.metadata['supervisorStatus'], 'planned');
    },
  );

  test(
    'extension agent tool execution registry reports missing handlers',
    () async {
      final catalog = ExtensionAgentToolContributionCatalog.fromRoutes(
        ExtensionContributionRouteManifest(
          routes: <ExtensionContributionRoute>[
            const ExtensionContributionRouter().routeContribution(
              extensionId: 'agent.tools',
              contribution: const ExtensionContributionPoint(
                kind: ExtensionContributionKind.agent,
                id: 'collect-extension-context',
                target: 'agent.tools',
                metadata: <String, Object?>{
                  'toolId': 'collectExtensionContext',
                },
              ),
            ),
          ],
        ),
      );
      final registry = ExtensionAgentToolExecutionRegistry(catalog: catalog);

      final result = await registry.dispatch(
        const AgentToolCallDispatchRequest(
          callId: 'call-extension',
          toolId: 'collectExtensionContext',
          inputText: '{"extensionId":"demo"}',
        ),
      );

      expect(result.success, isFalse);
      expect(result.message, contains('no registered execution handler'));
      expect(result.metadata['missingHandler'], isTrue);
      expect(registry.toJson()['missingHandlerToolIds'], <String>[
        'collectExtensionContext',
      ]);
    },
  );
}
