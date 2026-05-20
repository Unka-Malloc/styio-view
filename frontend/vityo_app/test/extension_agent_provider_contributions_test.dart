import 'package:flutter_test/flutter_test.dart';
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
}
