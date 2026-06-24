import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';

void main() {
  test('extension command catalog consumes command contribution routes', () {
    final registry = ExtensionManifestRegistry()
      ..register(
        const ExtensionManifest(
          extensionId: 'styio.commands',
          displayName: 'Styio Commands',
          version: '1.0.0',
          publisher: 'vityo',
          entrypoint: 'commands.dart',
          contributions: <ExtensionContributionPoint>[
            ExtensionContributionPoint(
              kind: ExtensionContributionKind.command,
              id: 'styio.refreshExternal',
              target: 'interaction.commands',
              title: 'Refresh external Styio state',
              metadata: <String, Object?>{'group': 'styio'},
            ),
            ExtensionContributionPoint(
              kind: ExtensionContributionKind.language,
              id: 'styio.language',
              target: 'service.styio-language',
            ),
          ],
        ),
      );
    final routes = const ExtensionContributionRouter().routeRegistry(registry);

    final catalog = ExtensionCommandContributionCatalog.fromRoutes(routes);
    final manifest = catalog.mergeWithStaticManifest();

    expect(catalog.hasCommands, isTrue);
    expect(catalog.commands, hasLength(1));
    expect(
      catalog.lookup('styio.refreshExternal')!.extensionId,
      'styio.commands',
    );
    expect(
      catalog.lookup('styio.refreshExternal')!.label,
      'Refresh external Styio state',
    );
    expect(
      catalog.toJson()['schema'],
      'vityo.extension-command-contributions.v1',
    );
    expect(manifest['schema'], 'vityo.command-contributions.v1');
    expect(manifest['extensionCommandCount'], 1);
    expect(
      (manifest['extensionCommands']! as List<Object?>).single,
      containsPair('target', 'interaction.commands'),
    );
  });
}
