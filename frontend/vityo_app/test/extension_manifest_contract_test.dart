import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';

void main() {
  test(
    'extension manifest converts module manifest into contribution contract',
    () {
      const module = ModuleManifest(
        moduleId: 'styio.language',
        displayName: 'Styio Language',
        version: '1.0.0',
        kind: ModuleKind.core,
        slot: ModuleSlot.editor,
        description: 'Styio language features',
        enabledByDefault: true,
        entrypoint: 'styio_language.dart',
        distributionPolicyRef: 'core-policy',
        capabilityFlags: <String, bool>{'languageService': true},
      );
      final manifest = ExtensionManifest.fromModuleManifest(
        module: module,
        publisher: 'vityo',
        activationEvents: const <String>['onLanguage:styio'],
        contributions: const <ExtensionContributionPoint>[
          ExtensionContributionPoint(
            kind: ExtensionContributionKind.language,
            id: 'styio',
            target: 'service.styio-language',
            title: 'Styio Language Service',
          ),
        ],
        metadata: const <String, Object?>{'source': 'module-host'},
      );
      final restored = ExtensionManifest.fromJson(manifest.toJson());

      expect(restored.extensionId, 'styio.language');
      expect(restored.moduleId, 'styio.language');
      expect(restored.trustedByDefault, isTrue);
      expect(restored.valid, isTrue);
      expect(restored.activatesOn('onLanguage:styio'), isTrue);
      expect(
        restored
            .contributionsFor(ExtensionContributionKind.language)
            .single
            .target,
        'service.styio-language',
      );
      expect(restored.capabilities['languageService'], isTrue);
    },
  );

  test(
    'extension manifest registry resolves activation and contribution points',
    () {
      final registry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'debug.tools',
            displayName: 'Debug Tools',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'debug_tools.dart',
            activationEvents: <String>['onDebug'],
            contributions: <ExtensionContributionPoint>[
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.debugger,
                id: 'styio-debug',
                target: 'debugger.dap',
              ),
            ],
          ),
        )
        ..register(
          const ExtensionManifest(
            extensionId: 'command.palette',
            displayName: 'Command Palette',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'commands.dart',
            contributions: <ExtensionContributionPoint>[
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.command,
                id: 'refresh-modules',
                target: 'interaction.commands',
              ),
            ],
          ),
        );

      expect(
        registry.activationCandidates('onDebug').single.extensionId,
        'debug.tools',
      );
      expect(
        registry.contributionsFor(ExtensionContributionKind.command).single.id,
        'refresh-modules',
      );
      expect(registry.toJson()['extensionCount'], 2);
      expect(registry.unregister('command.palette'), isTrue);
      expect(registry.lookup('command.palette'), isNull);
    },
  );

  test('extension manifest activation plan gates enabled and trusted ids', () {
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
        ),
      )
      ..register(
        const ExtensionManifest(
          extensionId: 'external.theme',
          displayName: 'External Theme',
          version: '1.0.0',
          publisher: 'external',
          entrypoint: 'theme.dart',
          activationEvents: <String>['onLanguage:styio'],
        ),
      );

    final plan = ExtensionActivationPlan.fromRegistry(
      registry: registry,
      event: 'onLanguage:styio',
      enabledExtensionIds: const <String>['styio.language', 'external.theme'],
      trustedExtensionIds: const <String>['styio.language'],
    );

    expect(plan.canActivate, isTrue);
    expect(plan.activatableExtensionIds, <String>['styio.language']);
    expect(plan.blockedExtensionIds, <String>['external.theme']);
    expect(plan.toJson()['blockedCount'], 1);
  });

  test(
    'extension manifest registry persists through Foundation DataStore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_extension_manifest_registry_test_',
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
      final dataStore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      final store = ExtensionManifestRegistryStore.fromDataStore(
        dataStore: dataStore,
      );
      final registry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'styio.language',
            displayName: 'Styio Language',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'styio_language.dart',
            activationEvents: <String>['onLanguage:styio'],
            contributions: <ExtensionContributionPoint>[
              ExtensionContributionPoint(
                kind: ExtensionContributionKind.language,
                id: 'styio',
                target: 'service.styio-language',
              ),
            ],
          ),
        );

      await store.saveRegistry(workspaceId: 'demo', registry: registry);
      final restored = await store.readRegistry(workspaceId: 'demo');

      expect(restored.lookup('styio.language'), isNotNull);
      expect(
        restored.activationCandidates('onLanguage:styio').single.extensionId,
        'styio.language',
      );
      expect(
        restored
            .contributionsFor(ExtensionContributionKind.language)
            .single
            .target,
        'service.styio-language',
      );
      expect(await store.deleteRegistry(workspaceId: 'demo'), isTrue);
      expect((await store.readRegistry(workspaceId: 'demo')).list(), isEmpty);
    },
  );
}
