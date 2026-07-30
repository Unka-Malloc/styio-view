import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';

void main() {
  test('extension activator activates trusted event candidates', () {
    final registry = ExtensionManifestRegistry()
      ..register(
        const ExtensionManifest(
          extensionId: 'styio.language',
          displayName: 'Styio Language',
          version: '1.0.0',
          publisher: 'vityo',
          entrypoint: 'styio_language.dart',
          activationEvents: <String>['onLanguage:styio'],
          trustedByDefault: true,
          contributions: <ExtensionContributionPoint>[
            ExtensionContributionPoint(
              kind: ExtensionContributionKind.language,
              id: 'styio',
              target: 'service.styio-language',
            ),
          ],
        ),
      )
      ..register(
        const ExtensionManifest(
          extensionId: 'untrusted.debug',
          displayName: 'Untrusted Debug',
          version: '1.0.0',
          publisher: 'external',
          entrypoint: 'debug.dart',
          activationEvents: <String>['onLanguage:styio'],
          contributions: <ExtensionContributionPoint>[
            ExtensionContributionPoint(
              kind: ExtensionContributionKind.debugger,
              id: 'debug',
              target: 'debugger.dap',
            ),
          ],
        ),
      );
    final activator = ExtensionActivator(
      clock: () => DateTime.utc(2026, 5, 20),
    );

    final session = activator.activate(
      registry: registry,
      event: 'onLanguage:styio',
    );
    final routes = activator.routeActivatedContributions(
      registry: registry,
      event: 'onLanguage:styio',
    );

    expect(session.activatedExtensionIds, <String>['styio.language']);
    expect(session.blockedExtensionIds, <String>['untrusted.debug']);
    expect(session.toJson()['activatedAt'], '2026-05-20T00:00:00.000Z');
    expect(routes.readyRoutes, hasLength(1));
    expect(
      routes
          .routesFor(ExtensionContributionRegistryKind.languageProviderRegistry)
          .single
          .extensionId,
      'styio.language',
    );
  });

  test('extension activator can allow untrusted extensions by policy', () {
    final registry = ExtensionManifestRegistry()
      ..register(
        const ExtensionManifest(
          extensionId: 'external.commands',
          displayName: 'External Commands',
          version: '1.0.0',
          publisher: 'external',
          entrypoint: 'commands.dart',
          activationEvents: <String>['*'],
          contributions: <ExtensionContributionPoint>[
            ExtensionContributionPoint(
              kind: ExtensionContributionKind.command,
              id: 'external.run',
              target: 'interaction.commands',
            ),
          ],
        ),
      );
    const activator = ExtensionActivator(
      policy: ExtensionActivationPolicy(allowUntrusted: true),
    );

    final session = activator.activate(
      registry: registry,
      event: 'onStartupFinished',
    );
    final routes = activator.routeActivatedContributions(
      registry: registry,
      event: 'onStartupFinished',
    );

    expect(session.activatedExtensionIds, <String>['external.commands']);
    expect(session.blockedExtensionIds, isEmpty);
    expect(
      routes.routesFor(ExtensionContributionRegistryKind.commandRegistry),
      hasLength(1),
    );
  });

  test(
    'extension activation history persists through Foundation DataStore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_extension_activation_history_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final store = ExtensionActivationHistoryStore.fromDataStore(
        dataStore: FoundationDataStore(
          resourceCoordinator: FoundationResourceCoordinator(
            resourceManager: resourceManager,
            fileSystemManager: fileSystemManager,
          ),
          fileSystemManager: fileSystemManager,
        ),
      );
      final session = ExtensionActivationSession(
        event: 'onStartupFinished',
        activatedAt: DateTime.utc(2026, 5, 20),
        decisions: const <ExtensionActivationDecision>[
          ExtensionActivationDecision(
            extensionId: 'styio.language',
            event: 'onStartupFinished',
            status: ExtensionActivationDecisionStatus.activated,
            message: 'activated',
          ),
        ],
      );

      final history = await store.appendSession(
        workspaceId: 'demo',
        session: session,
      );
      final restored = await store.readHistory(workspaceId: 'demo');

      expect(history.sessions.single.event, 'onStartupFinished');
      expect(restored.sessions.single.activatedExtensionIds, <String>[
        'styio.language',
      ]);
      expect(restored.toJson()['sessionCount'], 1);
      expect(await store.deleteHistory(workspaceId: 'demo'), isTrue);
      expect((await store.readHistory(workspaceId: 'demo')).sessions, isEmpty);
    },
  );
}
