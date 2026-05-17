import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/module_host/module_capability_matrix.dart';
import 'package:vityo_app/src/module_host/module_definition.dart';
import 'package:vityo_app/src/module_host/module_lifecycle.dart';
import 'package:vityo_app/src/module_host/module_manifest.dart';
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

  test('optional module uninstall reclaims package cache and data', () {
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

ModuleDefinition _module({required ModuleKind kind}) {
  return ModuleDefinition(
    manifest: ModuleManifest(
      moduleId: kind == ModuleKind.core ? 'core.shell' : 'optional.agent',
      displayName: kind == ModuleKind.core ? 'Core Shell' : 'Agent Adapter',
      version: '1.0.0',
      kind: kind,
      slot: kind == ModuleKind.core
          ? ModuleSlot.shell
          : ModuleSlot.agentSurface,
      description: 'test module',
      enabledByDefault: true,
      entrypoint: 'module.dart',
      distributionPolicyRef: 'test',
      capabilityFlags: const <String, bool>{},
    ),
    matrix: const ModuleCapabilityMatrix(
      moduleId: 'test-module',
      platforms: <PlatformTarget, ModuleCapabilityRule>{
        PlatformTarget.macos: ModuleCapabilityRule(
          supported: true,
          visible: true,
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
          iosSafe: true,
          distributionChannel: 'self-hosted',
          note: 'Android test rule',
        ),
      },
    ),
  );
}
