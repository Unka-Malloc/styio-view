import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

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

  test('extension host supervisor maps activation to host start requests', () {
    final registry = ExtensionManifestRegistry()
      ..register(
        const ExtensionManifest(
          extensionId: 'styio.language',
          displayName: 'Styio Language',
          version: '1.0.0',
          publisher: 'vityo',
          entrypoint: 'language.dart',
          activationEvents: <String>['onLanguage:styio'],
          trustedByDefault: true,
          metadata: <String, Object?>{'isolationMode': 'local-process'},
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
          metadata: <String, Object?>{'isolationMode': 'remote-service'},
        ),
      );
    final session = ExtensionActivator(
      clock: () => DateTime.utc(2026, 5, 20),
    ).activate(registry: registry, event: 'onLanguage:styio');
    final supervisor = ExtensionHostSupervisor(
      clock: () => DateTime.utc(2026, 5, 20, 1),
    );

    final snapshot = supervisor.applyActivation(
      registry: registry,
      session: session,
    );
    final running = supervisor.markRunning(
      snapshot: snapshot,
      extensionId: 'styio.language',
    );

    expect(snapshot.startingExtensionIds, <String>['styio.language']);
    expect(snapshot.blockedExtensionIds, <String>['external.debug']);
    expect(
      snapshot.lookup('styio.language')?.action,
      ExtensionHostSupervisorAction.spawnLocalProcess,
    );
    expect(running.runningExtensionIds, <String>['styio.language']);
    expect(
      running.telemetryEvents
          .map((event) => event.toJson()['action'])
          .toList(growable: false),
      <String>['none', 'spawn-local-process'],
    );
  });

  test(
    'extension host supervisor dispatches active hosts to runtime bridge',
    () {
      final registry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'styio.language',
            displayName: 'Styio Language',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'language.dart',
            activationEvents: <String>['onLanguage:styio'],
            trustedByDefault: true,
            metadata: <String, Object?>{'isolationMode': 'local-process'},
          ),
        );
      final session = ExtensionActivator(
        clock: () => DateTime.utc(2026, 5, 20),
      ).activate(registry: registry, event: 'onLanguage:styio');
      final snapshot = ExtensionHostSupervisor(
        clock: () => DateTime.utc(2026, 5, 20, 1),
      ).applyActivation(registry: registry, session: session);
      final record = snapshot.lookup('styio.language')!;
      final plan = ExtensionHostSupervisorExecutionPlan.fromRecord(
        record,
        manifest: registry.lookup('styio.language'),
      );
      final buffer = RuntimeOutputLiveBuffer();

      final dispatch = ExtensionHostSupervisorExecutionBridge().dispatchPlan(
        plan: plan,
        buffer: buffer,
        timestamp: DateTime.utc(2026, 5, 20, 2),
      );

      expect(plan.ready, isTrue);
      expect(plan.binding.managerId, 'shell-manager');
      expect(plan.definition.command, 'language.dart');
      expect(dispatch.status, RuntimeExecutionDispatchStatus.dispatched);
      expect(
        buffer
            .snapshot
            .visibleEvents
            .single
            .metadata['extensionHostSupervisor'],
        isTrue,
      );
      expect(plan.toJson()['ready'], isTrue);
    },
  );

  test(
    'extension host supervisor launches sandbox through registered launcher',
    () async {
      final registry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'styio.language',
            displayName: 'Styio Language',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'language.dart',
            activationEvents: <String>['onLanguage:styio'],
            trustedByDefault: true,
            metadata: <String, Object?>{'isolationMode': 'local-process'},
          ),
        );
      final session = ExtensionActivator(
        clock: () => DateTime.utc(2026, 5, 20),
      ).activate(registry: registry, event: 'onLanguage:styio');
      final snapshot = ExtensionHostSupervisor(
        clock: () => DateTime.utc(2026, 5, 20, 1),
      ).applyActivation(registry: registry, session: session);
      final plan = ExtensionHostSupervisorExecutionPlan.fromRecord(
        snapshot.lookup('styio.language')!,
        manifest: registry.lookup('styio.language'),
      );
      late final ExtensionHostSandboxLauncherRegistration launcher;
      launcher = ExtensionHostSandboxLauncherRegistration(
        launcherId: 'local-process-fixture',
        label: 'Local Process Fixture',
        action: ExtensionHostSupervisorAction.spawnLocalProcess,
        metadata: const <String, Object?>{'sandboxKind': 'fixture-process'},
        launcher: (request) async {
          return ExtensionHostSandboxLaunchResult.launched(
            request: request,
            launcher: launcher,
            message: 'Fixture sandbox launch accepted.',
            processHandleId: 'extension-host-proc-1',
            pid: 4242,
            activationTelemetryId: 'activation-telemetry-1',
            metadata: const <String, Object?>{'source': 'test'},
          );
        },
      );
      final bridge = ExtensionHostSupervisorExecutionBridge(
        sandboxLaunchers: ExtensionHostSandboxLauncherRegistry(
          launchers: <ExtensionHostSandboxLauncherRegistration>[launcher],
        ),
      );
      final buffer = RuntimeOutputLiveBuffer();

      final launch = await bridge.launchSandboxForPlan(
        plan: plan,
        buffer: buffer,
        timestamp: DateTime.utc(2026, 5, 20, 2),
      );

      expect(launch.status, ExtensionHostSandboxLaunchStatus.launched);
      expect(launch.launched, isTrue);
      expect(launch.processHandleId, 'extension-host-proc-1');
      expect(launch.pid, 4242);
      expect(launch.activationTelemetryId, 'activation-telemetry-1');
      expect(launch.metadata['sandboxKind'], 'fixture-process');
      expect(launch.request.dispatchReady, isTrue);
      expect(launch.toJson()['launcher'], isA<Map<String, Object?>>());
    },
  );

  test(
    'extension host sandbox launch reports missing launcher explicitly',
    () async {
      final registry = ExtensionManifestRegistry()
        ..register(
          const ExtensionManifest(
            extensionId: 'styio.language',
            displayName: 'Styio Language',
            version: '1.0.0',
            publisher: 'vityo',
            entrypoint: 'language.dart',
            activationEvents: <String>['onLanguage:styio'],
            trustedByDefault: true,
            metadata: <String, Object?>{'isolationMode': 'local-process'},
          ),
        );
      final session = ExtensionActivator(
        clock: () => DateTime.utc(2026, 5, 20),
      ).activate(registry: registry, event: 'onLanguage:styio');
      final snapshot = ExtensionHostSupervisor(
        clock: () => DateTime.utc(2026, 5, 20, 1),
      ).applyActivation(registry: registry, session: session);
      final plan = ExtensionHostSupervisorExecutionPlan.fromRecord(
        snapshot.lookup('styio.language')!,
        manifest: registry.lookup('styio.language'),
      );
      final buffer = RuntimeOutputLiveBuffer();

      final launch = await ExtensionHostSupervisorExecutionBridge()
          .launchSandboxForPlan(
            plan: plan,
            buffer: buffer,
            timestamp: DateTime.utc(2026, 5, 20, 2),
          );

      expect(launch.status, ExtensionHostSandboxLaunchStatus.missingLauncher);
      expect(launch.launched, isFalse);
      expect(launch.request.dispatchReady, isTrue);
      expect(launch.message, contains('missing'));
      expect(launch.toJson()['action'], 'spawn-local-process');
    },
  );
}
