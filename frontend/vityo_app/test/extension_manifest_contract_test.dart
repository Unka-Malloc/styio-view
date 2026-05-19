import 'package:flutter_test/flutter_test.dart';
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
}
