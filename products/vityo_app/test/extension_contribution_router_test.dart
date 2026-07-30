import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';

void main() {
  test(
    'extension contribution router maps contributions to target registries',
    () {
      final registry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'styio.core',
            displayName: 'Styio Core',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'styio_core.dart',
            contributions: <ExtensionContributionPoint>[
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.command,
                id: 'styio.refresh',
                target: 'interaction.commands',
              ),
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.language,
                id: 'styio.language',
                target: 'service.styio-language',
              ),
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.debugger,
                id: 'styio.debug',
                target: 'debugger.dap',
              ),
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.toolchain,
                id: 'styio.toolchain',
                target: 'toolchain.manager',
              ),
            ],
          ),
        );

      final routes = const ExtensionContributionRouter().routeRegistry(
        registry,
      );

      expect(routes.routes, hasLength(4));
      expect(routes.readyRoutes, hasLength(4));
      expect(
        routes
            .routesFor(ExtensionContributionRegistryKind.commandRegistry)
            .single
            .registryTargetId,
        'interaction.commands',
      );
      expect(
        routes
            .routesFor(
              ExtensionContributionRegistryKind.languageProviderRegistry,
            )
            .single
            .registryTargetId,
        'service.styio-language',
      );
      expect(
        routes
            .routesFor(ExtensionContributionRegistryKind.debugAdapterRegistry)
            .single
            .registryTargetId,
        'debugger.dap',
      );
      expect(
        routes
            .routesFor(ExtensionContributionRegistryKind.toolchainCatalog)
            .single
            .registryTargetId,
        'toolchain.manager',
      );
      expect(routes.toJson()['readyRouteCount'], 4);
    },
  );

  test('extension contribution router marks invalid contribution routes', () {
    final route = const ExtensionContributionRouter().routeContribution(
      extensionId: 'broken',
      contribution: const ExtensionContributionPoint(
        kind: ExtensionContributionKind.command,
        id: 'missing-target',
        target: '',
      ),
    );

    expect(route.status, ExtensionContributionRouteStatus.invalid);
    expect(route.ready, isFalse);
    expect(
      route.registryKind,
      ExtensionContributionRegistryKind.commandRegistry,
    );
    expect(route.message, contains('invalid'));
  });
}
