import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';

void main() {
  test('extension lifecycle hook catalog reads manifest hooks', () {
    final registry = ExtensionManifestRegistry()
      ..register(
        const ExtensionManifest(
          extensionId: 'styio.language',
          displayName: 'Styio Language',
          version: '1.0.0',
          publisher: 'vityo',
          entrypoint: 'styio_language.dart',
          trustedByDefault: true,
          metadata: <String, Object?>{
            'lifecycleHooks': <Object?>[
              <String, Object?>{
                'kind': 'activate',
                'command': 'styio-language-host',
                'arguments': <String>['--activate'],
                'environment': <String, String>{'VITYO_EXTENSION': '1'},
              },
              <String, Object?>{
                'kind': 'deactivate',
                'command': 'styio-language-host',
                'arguments': <String>['--deactivate'],
              },
            ],
          },
        ),
      );

    final catalog = ExtensionLifecycleHookCatalog.fromRegistry(registry);

    expect(catalog.hooks, hasLength(2));
    expect(
      catalog
          .hooksFor(
            extensionId: 'styio.language',
            kind: ExtensionLifecycleHookKind.activate,
          )
          .single
          .command,
      'styio-language-host',
    );
    expect(catalog.toJson()['hookCount'], 2);
  });

  test(
    'extension lifecycle hook runner executes activated hooks only',
    () async {
      final registry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'trusted.language',
            displayName: 'Trusted Language',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'trusted.dart',
            activationEvents: <String>['onLanguage:styio'],
            trustedByDefault: true,
            metadata: <String, Object?>{
              'lifecycleHooks': <Object?>[
                <String, Object?>{
                  'kind': 'activate',
                  'command': 'trusted-language-host',
                },
              ],
            },
          ),
        )
        ..register(
          const ExtensionManifest(
            extensionId: 'blocked.debug',
            displayName: 'Blocked Debug',
            version: '1.0.0',
            publisher: 'external',
            entrypoint: 'blocked.dart',
            activationEvents: <String>['onLanguage:styio'],
            metadata: <String, Object?>{
              'lifecycleHooks': <Object?>[
                <String, Object?>{
                  'kind': 'activate',
                  'command': 'blocked-debug-host',
                },
              ],
            },
          ),
        );
      final session = ExtensionActivator(
        clock: () => DateTime.utc(2026, 5, 20),
      ).activate(registry: registry, event: 'onLanguage:styio');
      final executed = <String>[];
      final runner = ExtensionLifecycleHookRunner(
        catalog: ExtensionLifecycleHookCatalog.fromRegistry(registry),
        executor: (hook) async {
          executed.add(hook.command);
          return ExtensionLifecycleHookResult(
            hook: hook,
            succeeded: true,
            message: 'executed',
            completedAt: DateTime.utc(2026, 5, 20, 0, 1),
          );
        },
      );

      final results = await runner.runActivationHooks(session);

      expect(executed, <String>['trusted-language-host']);
      expect(results.single.succeeded, isTrue);
      expect(results.single.toJson()['message'], 'executed');
    },
  );
}
