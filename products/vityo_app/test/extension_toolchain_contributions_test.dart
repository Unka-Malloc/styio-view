import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';

void main() {
  test(
    'extension toolchain catalog converts toolchain routes to descriptors',
    () {
      final registry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'styio.toolchain',
            displayName: 'Styio Toolchain',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'toolchain.dart',
            contributions: <ExtensionContributionPoint>[
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.toolchain,
                id: 'styio-language-service',
                target: 'toolchain.manager',
                title: 'Styio Language Service',
                metadata: <String, Object?>{
                  'kind': 'language-service',
                  'executablePath': '/usr/bin/styio',
                  'version': 'nightly',
                  'language': 'styio',
                },
              ),
            ],
          ),
        );
      final routes = const ExtensionContributionRouter().routeRegistry(
        registry,
      );

      final catalog = ExtensionToolchainContributionCatalog.fromRoutes(routes);
      final descriptor = catalog.readyDescriptors.single;

      expect(catalog.contributions.single.ready, isTrue);
      expect(descriptor.id, 'styio-language-service');
      expect(descriptor.kind, ToolchainKind.languageService);
      expect(descriptor.executablePath, '/usr/bin/styio');
      expect(descriptor.metadata['extensionId'], 'styio.toolchain');
      expect(catalog.toJson()['readyDescriptorCount'], 1);
    },
  );

  test('extension toolchain catalog reports missing executable metadata', () {
    final route = const ExtensionContributionRouter().routeContribution(
      extensionId: 'broken.toolchain',
      contribution: const ExtensionContributionPoint(
        kind: ExtensionContributionKind.toolchain,
        id: 'missing-executable',
        target: 'toolchain.manager',
        metadata: <String, Object?>{'kind': 'compiler'},
      ),
    );

    final catalog = ExtensionToolchainContributionCatalog.fromRoutes(
      ExtensionContributionRouteManifest(
        routes: <ExtensionContributionRoute>[route],
      ),
    );

    expect(catalog.readyDescriptors, isEmpty);
    expect(
      catalog.contributions.single.status,
      ExtensionToolchainContributionStatus.missingExecutable,
    );
  });
}
