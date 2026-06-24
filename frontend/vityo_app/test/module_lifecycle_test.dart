import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/module_host/module_capability_matrix.dart';
import 'package:vityo_app/src/module_host/module_definition.dart';
import 'package:vityo_app/src/module_host/module_lifecycle.dart';
import 'package:vityo_app/src/module_host/module_manifest.dart';
import 'package:vityo_app/src/module_host/module_registry.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('core modules mount and stage updates when platform rule allows it', () {
    final plan = planModuleLifecycle(
      module: _module(kind: ModuleKind.core),
      platformTarget: PlatformTarget.macos,
      updateAvailable: true,
    );

    expect(plan.action, ModuleLifecycleAction.mount);
    expect(plan.stageUpdate, isTrue);
    expect(plan.reclaimData, isFalse);
  });

  test('module lifecycle state blocks untrusted activation', () {
    final module = _module(kind: ModuleKind.optional);
    final state = defaultModuleLifecycleState(module).copyWith(
      trustState: ModuleTrustState.untrusted,
      message: 'Requires user trust.',
    );

    final plan = planModuleLifecycle(
      module: module,
      platformTarget: PlatformTarget.macos,
      trustState: state.trustState,
    );
    final json = state.toJson();

    expect(state.enabled, isTrue);
    expect(state.trusted, isFalse);
    expect(state.canMount, isFalse);
    expect(json['trustState'], 'untrusted');
    expect(plan.action, ModuleLifecycleAction.blocked);
    expect(plan.reason, contains('requires user trust'));
  });

  test('mobile optional module uninstall reclaims package cache and data', () {
    final plan = planModuleLifecycle(
      module: _module(kind: ModuleKind.optional),
      platformTarget: PlatformTarget.android,
      uninstallRequested: true,
    );

    expect(plan.action, ModuleLifecycleAction.uninstall);
    expect(plan.reclaimPackage, isTrue);
    expect(plan.reclaimCache, isTrue);
    expect(plan.reclaimData, isTrue);
  });

  test('users can install optional modules on supported devices', () {
    final optional = _module(kind: ModuleKind.optional);
    final desktopRegistry = ModuleRegistry(
      platformTarget: PlatformTarget.macos,
      definitions: <ModuleDefinition>[optional],
    );
    final androidRegistry = ModuleRegistry(
      platformTarget: PlatformTarget.android,
      definitions: <ModuleDefinition>[optional],
    );

    final desktopPlan = planOptionalModuleInstall(
      registry: desktopRegistry,
      moduleId: optional.manifest.moduleId,
      platformTarget: PlatformTarget.macos,
    );
    final androidPlan = planOptionalModuleInstall(
      registry: androidRegistry,
      moduleId: optional.manifest.moduleId,
      platformTarget: PlatformTarget.android,
    );

    expect(desktopPlan.action, ModuleLifecycleAction.install);
    expect(androidPlan.action, ModuleLifecycleAction.install);
  });

  test('optional module install respects platform distribution policy', () {
    final unsafeLocalRuntime = _module(
      kind: ModuleKind.optional,
      moduleId: 'local.runtime.unsafe',
      slot: ModuleSlot.localRuntime,
      iosSafe: false,
      iosDistributionChannel: 'self-hosted',
    );
    final registry = ModuleRegistry(
      platformTarget: PlatformTarget.ios,
      definitions: <ModuleDefinition>[unsafeLocalRuntime],
    );

    final plan = planOptionalModuleInstall(
      registry: registry,
      moduleId: unsafeLocalRuntime.manifest.moduleId,
      platformTarget: PlatformTarget.ios,
    );

    expect(plan.action, ModuleLifecycleAction.blocked);
    expect(plan.reason, contains('distribution policy blocks installation'));
  });

  test('core module install is blocked because it ships with product', () {
    final core = _module(kind: ModuleKind.core);
    final registry = ModuleRegistry(
      platformTarget: PlatformTarget.macos,
      definitions: <ModuleDefinition>[core],
    );

    final plan = planOptionalModuleInstall(
      registry: registry,
      moduleId: core.manifest.moduleId,
      platformTarget: PlatformTarget.macos,
    );

    expect(plan.action, ModuleLifecycleAction.blocked);
    expect(plan.reason, contains('installed with the product'));
  });

  test('desktop optional module uninstall can retain or clear user data', () {
    final keepData = planModuleLifecycle(
      module: _module(kind: ModuleKind.optional),
      platformTarget: PlatformTarget.macos,
      uninstallRequested: true,
    );
    final clearData = planModuleLifecycle(
      module: _module(kind: ModuleKind.optional),
      platformTarget: PlatformTarget.macos,
      uninstallRequested: true,
      uninstallDataPolicy: ModuleUninstallDataPolicy.clearData,
    );

    expect(keepData.reclaimPackage, isTrue);
    expect(keepData.reclaimCache, isTrue);
    expect(keepData.reclaimData, isFalse);
    expect(clearData.reclaimData, isTrue);
  });

  test('module uninstall reconciliation removes menus and workspace refs', () {
    final core = _module(kind: ModuleKind.core);
    final optional = _module(kind: ModuleKind.optional);
    final registry = ModuleRegistry(
      platformTarget: PlatformTarget.macos,
      definitions: <ModuleDefinition>[core, optional],
    );

    final reconciliation = reconcileModuleUninstall(
      registry: registry,
      uninstalledModuleIds: <String>[optional.manifest.moduleId],
      workspaceReferences: <ModuleWorkspaceReference>[
        ModuleWorkspaceReference(
          referenceId: 'agent-panel',
          moduleId: optional.manifest.moduleId,
          path: '.vityo/modules/optional.agent',
        ),
        ModuleWorkspaceReference(
          referenceId: 'core-shell',
          moduleId: core.manifest.moduleId,
        ),
      ],
    );

    expect(reconciliation.registry.findById(optional.manifest.moduleId), isNull);
    expect(reconciliation.registry.visibleModules, hasLength(1));
    expect(reconciliation.registry.mountedModules, hasLength(1));
    expect(reconciliation.removedWorkspaceReferences.single.referenceId, 'agent-panel');
    expect(reconciliation.retainedWorkspaceReferences.single.referenceId, 'core-shell');
  });

  test('staged update keeps old module running until restart', () {
    final running = _module(
      kind: ModuleKind.optional,
      moduleId: 'runtime.surface',
      version: '1.0.0',
      slot: ModuleSlot.runtimeSurface,
    );
    final staged = _module(
      kind: ModuleKind.optional,
      moduleId: 'runtime.surface',
      version: '1.1.0',
      slot: ModuleSlot.runtimeSurface,
    );
    final registry = ModuleRegistry(
      platformTarget: PlatformTarget.macos,
      definitions: <ModuleDefinition>[running],
    );

    final resolution = resolveStagedModuleUpdates(
      runningRegistry: registry,
      stagedModules: <ModuleDefinition>[staged],
      restartCompleted: false,
    );

    expect(resolution.requiresRestart, isTrue);
    expect(resolution.pendingRestartModuleIds, <String>['runtime.surface']);
    expect(resolution.activatedModuleIds, isEmpty);
    expect(
      resolution.registry.findById('runtime.surface')!.manifest.version,
      '1.0.0',
    );
  });

  test('staged update switches to new module version after restart', () {
    final running = _module(
      kind: ModuleKind.optional,
      moduleId: 'runtime.surface',
      version: '1.0.0',
      slot: ModuleSlot.runtimeSurface,
    );
    final staged = _module(
      kind: ModuleKind.optional,
      moduleId: 'runtime.surface',
      version: '1.1.0',
      slot: ModuleSlot.runtimeSurface,
    );
    final registry = ModuleRegistry(
      platformTarget: PlatformTarget.macos,
      definitions: <ModuleDefinition>[running],
    );

    final resolution = resolveStagedModuleUpdates(
      runningRegistry: registry,
      stagedModules: <ModuleDefinition>[staged],
      restartCompleted: true,
    );

    expect(resolution.requiresRestart, isFalse);
    expect(resolution.activatedModuleIds, <String>['runtime.surface']);
    expect(resolution.blockedModuleIds, isEmpty);
    expect(
      resolution.registry.findById('runtime.surface')!.manifest.version,
      '1.1.0',
    );
  });

  test('staged update keeps old module when new module is unsupported', () {
    final running = _module(
      kind: ModuleKind.optional,
      moduleId: 'runtime.surface',
      version: '1.0.0',
      slot: ModuleSlot.runtimeSurface,
    );
    final staged = _module(
      kind: ModuleKind.optional,
      moduleId: 'runtime.surface',
      version: '1.1.0',
      slot: ModuleSlot.runtimeSurface,
      macosSupported: false,
      macosVisible: false,
    );
    final registry = ModuleRegistry(
      platformTarget: PlatformTarget.macos,
      definitions: <ModuleDefinition>[running],
    );

    final resolution = resolveStagedModuleUpdates(
      runningRegistry: registry,
      stagedModules: <ModuleDefinition>[staged],
      restartCompleted: true,
    );

    expect(resolution.activatedModuleIds, isEmpty);
    expect(resolution.blockedModuleIds, <String>['runtime.surface']);
    expect(
      resolution.registry.findById('runtime.surface')!.manifest.version,
      '1.0.0',
    );
  });

  test('iOS registry hides non iosSafe self-hosted runtime modules', () {
    final unsafeLocalRuntime = _module(
      kind: ModuleKind.optional,
      moduleId: 'local.runtime.unsafe',
      slot: ModuleSlot.localRuntime,
      iosSafe: false,
      iosDistributionChannel: 'self-hosted',
    );
    final cloudRuntime = _module(
      kind: ModuleKind.optional,
      moduleId: 'cloud.runtime.safe',
      slot: ModuleSlot.cloudRuntime,
      iosSafe: true,
      iosDistributionChannel: 'app-store',
    );
    final registry = ModuleRegistry(
      platformTarget: PlatformTarget.ios,
      definitions: <ModuleDefinition>[unsafeLocalRuntime, cloudRuntime],
    );

    expect(registry.findById(unsafeLocalRuntime.manifest.moduleId), isNotNull);
    expect(
      registry.visibleModules.map((module) => module.manifest.moduleId),
      isNot(contains(unsafeLocalRuntime.manifest.moduleId)),
    );
    expect(
      registry.mountedModules.map((module) => module.manifest.moduleId),
      contains(cloudRuntime.manifest.moduleId),
    );
    expect(registry.isMounted(unsafeLocalRuntime.manifest.moduleId), isFalse);
  });

  test('desktop and android keep self-hosted non iosSafe modules available', () {
    final localRuntime = _module(
      kind: ModuleKind.optional,
      moduleId: 'local.runtime.self-hosted',
      slot: ModuleSlot.localRuntime,
      iosSafe: false,
      iosDistributionChannel: 'self-hosted',
    );
    final desktopRegistry = ModuleRegistry(
      platformTarget: PlatformTarget.macos,
      definitions: <ModuleDefinition>[localRuntime],
    );
    final androidRegistry = ModuleRegistry(
      platformTarget: PlatformTarget.android,
      definitions: <ModuleDefinition>[localRuntime],
    );

    expect(desktopRegistry.visibleModules.single.manifest.moduleId, localRuntime.manifest.moduleId);
    expect(androidRegistry.visibleModules.single.manifest.moduleId, localRuntime.manifest.moduleId);
    expect(desktopRegistry.mountedModules.single.manifest.moduleId, localRuntime.manifest.moduleId);
    expect(androidRegistry.mountedModules.single.manifest.moduleId, localRuntime.manifest.moduleId);
  });

  test('core module uninstall is blocked', () {
    final plan = planModuleLifecycle(
      module: _module(kind: ModuleKind.core),
      platformTarget: PlatformTarget.macos,
      uninstallRequested: true,
    );

    expect(plan.action, ModuleLifecycleAction.blocked);
    expect(plan.reason, contains('Core modules cannot be uninstalled'));
  });
}

ModuleDefinition _module({
  required ModuleKind kind,
  String? moduleId,
  String version = '1.0.0',
  ModuleSlot? slot,
  bool iosSafe = true,
  String iosDistributionChannel = 'app-store',
  bool macosSupported = true,
  bool macosVisible = true,
}) {
  return ModuleDefinition(
    manifest: ModuleManifest(
      moduleId: moduleId ?? (kind == ModuleKind.core ? 'core.shell' : 'optional.agent'),
      displayName: kind == ModuleKind.core ? 'Core Shell' : 'Agent Adapter',
      version: version,
      kind: kind,
      slot: slot ?? (kind == ModuleKind.core ? ModuleSlot.shell : ModuleSlot.agentSurface),
      description: 'test module',
      enabledByDefault: true,
      entrypoint: 'module.dart',
      distributionPolicyRef: 'test',
      capabilityFlags: const <String, bool>{},
    ),
    matrix: ModuleCapabilityMatrix(
      moduleId: 'test-module',
      platforms: <PlatformTarget, ModuleCapabilityRule>{
        PlatformTarget.macos: ModuleCapabilityRule(
          supported: macosSupported,
          visible: macosVisible,
          installable: true,
          mountedByDefault: true,
          iosSafe: true,
          distributionChannel: 'bundled',
          note: 'macOS test rule',
        ),
        PlatformTarget.android: ModuleCapabilityRule(
          supported: true,
          visible: true,
          installable: true,
          mountedByDefault: true,
          iosSafe: iosSafe,
          distributionChannel: 'self-hosted',
          note: 'Android test rule',
        ),
        PlatformTarget.ios: ModuleCapabilityRule(
          supported: true,
          visible: true,
          installable: true,
          mountedByDefault: true,
          iosSafe: iosSafe,
          distributionChannel: iosDistributionChannel,
          note: 'iOS test rule',
        ),
      },
    ),
  );
}
