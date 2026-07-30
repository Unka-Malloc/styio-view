import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';
import 'package:vityo_app/src/view_render/extensions/extensions.dart';

void main() {
  test('extension view catalog converts view routes to surface entries', () {
    final registry = ExtensionManifestRegistry()
      ..register(
        const ExtensionManifest(
          extensionId: 'vityo.views',
          displayName: 'Vityo Views',
          version: '1.0.0',
          publisher: 'vityo',
          entrypoint: 'views.dart',
          trustedByDefault: true,
          contributions: <ExtensionContributionPoint>[
            ExtensionContributionPoint(
              kind: ExtensionContributionKind.view,
              id: 'agent.activity',
              target: 'presentation.views',
              title: 'Agent Activity',
              metadata: <String, Object?>{
                'viewKind': 'panel',
                'location': 'right-sidebar',
                'icon': 'agent',
                'order': 20,
              },
            ),
            ExtensionContributionPoint(
              kind: ExtensionContributionKind.view,
              id: 'diagnostics.timeline',
              target: 'presentation.views',
              title: 'Diagnostics Timeline',
              metadata: <String, Object?>{
                'viewKind': 'panel',
                'location': 'right-sidebar',
                'order': 10,
              },
            ),
          ],
        ),
      );
    final routes = const ExtensionContributionRouter().routeRegistry(registry);

    final catalog = ExtensionViewContributionCatalog.fromRoutes(routes);
    final sidebarViews = catalog.viewsForLocation('right-sidebar');

    expect(catalog.readyViews.map((view) => view.viewId), <String>[
      'diagnostics.timeline',
      'agent.activity',
    ]);
    expect(sidebarViews, hasLength(2));
    expect(sidebarViews.last.icon, 'agent');
    expect(catalog.toJson()['readyViewCount'], 2);
  });

  test('extension view catalog reports missing view kind', () {
    final route = const ExtensionContributionRouter().routeContribution(
      extensionId: 'broken.views',
      contribution: const ExtensionContributionPoint(
        kind: ExtensionContributionKind.view,
        id: 'missing-kind',
        target: 'presentation.views',
      ),
    );

    final catalog = ExtensionViewContributionCatalog.fromRoutes(
      ExtensionContributionRouteManifest(
        routes: <ExtensionContributionRoute>[route],
      ),
    );

    expect(catalog.readyViews, isEmpty);
    expect(
      catalog.contributions.single.status,
      ExtensionViewContributionStatus.missingViewKind,
    );
  });
}
