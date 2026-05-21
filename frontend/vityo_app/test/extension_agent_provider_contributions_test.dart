import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';

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
                'description': 'Collect context from an extension.',
                'permissionMode': 'never',
                'supportedProviderKinds': <String>[
                  'cloud_openai_compatible',
                ],
                'supportedProtocols': <String>['openai-responses'],
                'capabilities': <String>['extension.context'],
                'schema': <Object?>[
                  <String, Object?>{
                    'name': 'extensionId',
                    'type': 'string',
                    'required': true,
                    'description': 'Extension id.',
                  },
                ],
              },
            ),
          ],
        ),
      );
    final routes = const ExtensionContributionRouter().routeRegistry(registry);

    final catalog = ExtensionAgentToolContributionCatalog.fromRoutes(routes);
    final tool = catalog.readyTools.single;
    final selection = catalog
        .toRegistry()
        .selectForProfile(
          profile: AgentPromptProfile.openAICodexSparkForPlatform(
            PlatformTarget.linux,
          ),
          providerKind: AgentProviderKind.cloudOpenAICompatible,
        );

    expect(tool.toolId, 'collectExtensionContext');
    expect(tool.builtin, isFalse);
    expect(tool.permissionMode, AgentToolPermissionMode.never);
    expect(tool.schema.single.name, 'extensionId');
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

  test('extension agent tool execution registry reports missing handlers', () async {
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
  });
}
