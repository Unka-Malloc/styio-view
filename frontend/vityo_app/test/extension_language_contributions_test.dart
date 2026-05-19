import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/language/service/service.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';

void main() {
  test(
    'extension language catalog converts language routes to provider entries',
    () {
      final registry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'styio.language',
            displayName: 'Styio Language',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'language.dart',
            contributions: <ExtensionContributionPoint>[
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.language,
                id: 'styio-provider',
                target: 'service.styio-language',
                title: 'Styio Provider',
                metadata: <String, Object?>{
                  'languageId': 'styio',
                  'providerId': 'styio-service',
                  'priority': 20,
                  'capabilities': <String>[
                    'language.syntax-diagnostics',
                    'language.completion',
                  ],
                },
              ),
            ],
          ),
        );
      final routes = const ExtensionContributionRouter().routeRegistry(
        registry,
      );

      final catalog = ExtensionLanguageContributionCatalog.fromRoutes(routes);
      final entry = catalog.readyEntries.single;
      final manifest = catalog.toManifest().toJson();

      expect(catalog.contributions.single.ready, isTrue);
      expect(entry.languageId, 'styio');
      expect(entry.providerId, 'styio-service');
      expect(entry.priority, 20);
      expect(entry.capabilities, <String>[
        'language.completion',
        'language.syntax-diagnostics',
      ]);
      expect((manifest['entries']! as List<Object?>), hasLength(1));
      expect(catalog.toJson()['readyEntryCount'], 1);
    },
  );

  test('extension language catalog rejects non-language route', () {
    final route = const ExtensionContributionRouter().routeContribution(
      extensionId: 'commands',
      contribution: const ExtensionContributionPoint(
        kind: ExtensionContributionKind.command,
        id: 'refresh',
        target: 'interaction.commands',
      ),
    );

    final contribution = ExtensionLanguageContribution.fromRoute(route);

    expect(contribution.ready, isFalse);
    expect(
      contribution.status,
      ExtensionLanguageContributionStatus.invalidRoute,
    );
  });
}
