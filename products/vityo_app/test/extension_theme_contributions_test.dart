import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';
import 'package:vityo_app/src/view_render/theme/theme.dart';

void main() {
  test('extension theme catalog converts theme routes to overrides', () {
    final registry = ExtensionManifestRegistry()
      ..register(
        const ExtensionManifest(
          extensionId: 'vityo.theme',
          displayName: 'Vityo Theme',
          version: '1.0.0',
          publisher: 'vityo',
          entrypoint: 'theme.dart',
          trustedByDefault: true,
          contributions: <ExtensionContributionPoint>[
            ExtensionContributionPoint(
              kind: ExtensionContributionKind.theme,
              id: 'sunlit',
              target: 'theme.registry',
              title: 'Sunlit',
              metadata: <String, Object?>{
                'canvas': '#FFF7E8',
                'panel': '#FFFFFF',
                'ink': '#201A14',
                'accent': '#C46A2B',
                'muted': '#7F6D5B',
              },
            ),
          ],
        ),
      );
    final routes = const ExtensionContributionRouter().routeRegistry(registry);

    final catalog = ExtensionThemeContributionCatalog.fromRoutes(routes);
    final theme = catalog.lookup('sunlit')!;

    expect(theme.ready, isTrue);
    expect(theme.title, 'Sunlit');
    expect(theme.override?.accent, const Color(0xFFC46A2B).toARGB32());
    expect(catalog.toJson()['readyThemeCount'], 1);
  });

  test('extension theme catalog reports missing palette colors', () {
    final route = const ExtensionContributionRouter().routeContribution(
      extensionId: 'broken.theme',
      contribution: const ExtensionContributionPoint(
        kind: ExtensionContributionKind.theme,
        id: 'empty',
        target: 'theme.registry',
      ),
    );

    final catalog = ExtensionThemeContributionCatalog.fromRoutes(
      ExtensionContributionRouteManifest(
        routes: <ExtensionContributionRoute>[route],
      ),
    );

    expect(catalog.readyThemes, isEmpty);
    expect(
      catalog.contributions.single.status,
      ExtensionThemeContributionStatus.missingPalette,
    );
  });
}
