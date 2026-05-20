import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';

void main() {
  test('extension host isolation blocks untrusted extensions by default', () {
    const manifest = ExtensionManifest(
      extensionId: 'external.debug',
      displayName: 'External Debug',
      version: '1.0.0',
      publisher: 'external',
      entrypoint: 'debug.dart',
      metadata: <String, Object?>{'isolationMode': 'local-process'},
    );

    final plan = const ExtensionHostIsolationPolicy().planFor(manifest);

    expect(plan.executable, isFalse);
    expect(plan.mode, ExtensionHostIsolationMode.blocked);
    expect(plan.reason, contains('trust'));
  });

  test('extension host isolation allows trusted local process extensions', () {
    const manifest = ExtensionManifest(
      extensionId: 'styio.language',
      displayName: 'Styio Language',
      version: '1.0.0',
      publisher: 'vityo',
      entrypoint: 'language.dart',
      trustedByDefault: true,
      metadata: <String, Object?>{'isolationMode': 'local-process'},
    );

    final plan = const ExtensionHostIsolationPolicy().planFor(manifest);

    expect(plan.executable, isTrue);
    expect(plan.mode, ExtensionHostIsolationMode.localProcess);
    expect(plan.toJson()['mode'], 'local-process');
  });

  test('extension host isolation planner evaluates full registry', () {
    final registry = ExtensionManifestRegistry()
      ..register(
        const ExtensionManifest(
          extensionId: 'core.theme',
          displayName: 'Core Theme',
          version: '1.0.0',
          publisher: 'vityo',
          entrypoint: 'theme.dart',
          trustedByDefault: true,
          metadata: <String, Object?>{'isolationMode': 'in-process'},
        ),
      )
      ..register(
        const ExtensionManifest(
          extensionId: 'remote.agent',
          displayName: 'Remote Agent',
          version: '1.0.0',
          publisher: 'external',
          entrypoint: 'agent.dart',
          metadata: <String, Object?>{'isolationMode': 'remote-service'},
        ),
      );
    const planner = ExtensionHostIsolationPlanner(
      policy: ExtensionHostIsolationPolicy(allowUntrusted: true),
    );

    final plans = planner.planRegistry(registry);

    expect(plans.map((plan) => plan.mode), <ExtensionHostIsolationMode>[
      ExtensionHostIsolationMode.inProcess,
      ExtensionHostIsolationMode.remoteService,
    ]);
  });
}
