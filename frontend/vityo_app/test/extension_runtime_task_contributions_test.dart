import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test(
    'extension runtime task catalog converts task routes to definitions',
    () {
      final registry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'styio.tasks',
            displayName: 'Styio Tasks',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'tasks.dart',
            trustedByDefault: true,
            contributions: <ExtensionContributionPoint>[
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.task,
                id: 'styio.build',
                target: 'runtime.tasks',
                title: 'Build Styio',
                metadata: <String, Object?>{
                  'taskId': 'build.styio',
                  'kind': 'build',
                  'command': 'ninja',
                  'arguments': <String>['-C', 'build'],
                  'workingDirectory': '/workspace/styio',
                  'environment': <String, String>{'CC': 'clang'},
                  'group': 'build',
                },
              ),
            ],
          ),
        );
      final routes = const ExtensionContributionRouter().routeRegistry(
        registry,
      );

      final catalog = ExtensionRuntimeTaskContributionCatalog.fromRoutes(
        routes,
      );
      final definition = catalog.readyDefinitions.single;

      expect(definition.id, 'build.styio');
      expect(definition.kind, RuntimeTaskKind.build);
      expect(definition.command, 'ninja');
      expect(definition.arguments, <String>['-C', 'build']);
      expect(definition.environment['CC'], 'clang');
      expect(definition.metadata['extensionId'], 'styio.tasks');
      expect(catalog.toJson()['readyDefinitionCount'], 1);
    },
  );

  test('extension runtime task catalog reports missing command metadata', () {
    final route = const ExtensionContributionRouter().routeContribution(
      extensionId: 'broken.tasks',
      contribution: const ExtensionContributionPoint(
        kind: ExtensionContributionKind.task,
        id: 'broken',
        target: 'runtime.tasks',
      ),
    );

    final catalog = ExtensionRuntimeTaskContributionCatalog.fromRoutes(
      ExtensionContributionRouteManifest(
        routes: <ExtensionContributionRoute>[route],
      ),
    );

    expect(catalog.readyDefinitions, isEmpty);
    expect(
      catalog.contributions.single.status,
      ExtensionRuntimeTaskContributionStatus.missingCommand,
    );
  });
}
