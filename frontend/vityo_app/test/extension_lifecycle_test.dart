import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';

void main() {
  test('extension lifecycle projects activation decisions to records', () {
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
          extensionId: 'external.debug',
          displayName: 'External Debug',
          version: '1.0.0',
          publisher: 'external',
          entrypoint: 'debug.dart',
          activationEvents: <String>['onLanguage:styio'],
        ),
      );
    final activator = ExtensionActivator(
      clock: () => DateTime.utc(2026, 5, 20),
    );
    final controller = ExtensionLifecycleController(
      clock: () => DateTime.utc(2026, 5, 20, 1),
    );

    final session = activator.activate(
      registry: registry,
      event: 'onLanguage:styio',
    );
    final snapshot = controller.applyActivation(
      registry: registry,
      session: session,
    );

    expect(snapshot.activatedExtensionIds, <String>['styio.language']);
    expect(snapshot.blockedExtensionIds, <String>['external.debug']);
    expect(
      snapshot.lookup('styio.language')?.status,
      ExtensionLifecycleStatus.activated,
    );
    expect(snapshot.toJson()['recordCount'], 2);
  });

  test('extension lifecycle can mark active extension deactivated', () {
    final controller = ExtensionLifecycleController(
      clock: () => DateTime.utc(2026, 5, 20, 1),
    );
    final snapshot = ExtensionLifecycleSnapshot(
      records: <ExtensionLifecycleRecord>[
        ExtensionLifecycleRecord(
          extensionId: 'styio.language',
          status: ExtensionLifecycleStatus.activated,
          event: 'onLanguage:styio',
          message: 'activated',
          updatedAt: DateTime.utc(2026, 5, 20),
        ),
      ],
    );

    final next = controller.deactivate(
      snapshot: snapshot,
      extensionId: 'styio.language',
      reason: 'Extension host stopped.',
    );

    expect(next.activatedExtensionIds, isEmpty);
    expect(
      next.lookup('styio.language')?.status,
      ExtensionLifecycleStatus.deactivated,
    );
    expect(next.lookup('styio.language')?.message, 'Extension host stopped.');
  });
}
