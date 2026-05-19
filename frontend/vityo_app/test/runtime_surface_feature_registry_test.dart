import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/module_host/module_capability_matrix.dart';
import 'package:vityo_app/src/module_host/module_definition.dart';
import 'package:vityo_app/src/module_host/module_lifecycle.dart';
import 'package:vityo_app/src/module_host/module_manifest.dart';
import 'package:vityo_app/src/module_host/module_registry.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/runtime/runtime_surface_feature_registry.dart';

void main() {
  test('runtime surface feature entries load only from mounted runtime modules', () {
    final registry = ModuleRegistry(
      platformTarget: PlatformTarget.macos,
      definitions: <ModuleDefinition>[
        _module(
          moduleId: 'runtime.surface.timeline',
          displayName: 'Timeline',
          slot: ModuleSlot.runtimeSurface,
        ),
        _module(
          moduleId: 'debug.console',
          displayName: 'Debug Console',
          slot: ModuleSlot.debugTools,
        ),
        _module(
          moduleId: 'theme.default',
          displayName: 'Theme',
          slot: ModuleSlot.theme,
        ),
        _module(
          moduleId: 'runtime.surface.disabled',
          displayName: 'Disabled Timeline',
          slot: ModuleSlot.runtimeSurface,
          mountedByDefault: false,
        ),
      ],
    );

    final entries = runtimeSurfaceFeatureEntriesFor(registry.mountedModules);

    expect(entries.map((entry) => entry.moduleId), <String>[
      'runtime.surface.timeline',
      'debug.console',
    ]);
    expect(entries.map((entry) => entry.featureKey), <String>[
      'runtimeSurface:runtime.surface.timeline',
      'debugTools:debug.console',
    ]);
  });

  test('uninstalled runtime module removes runtime surface feature entry', () {
    final runtimeModule = _module(
      moduleId: 'runtime.surface.timeline',
      displayName: 'Timeline',
      slot: ModuleSlot.runtimeSurface,
    );
    final debugModule = _module(
      moduleId: 'debug.console',
      displayName: 'Debug Console',
      slot: ModuleSlot.debugTools,
    );
    final registry = ModuleRegistry(
      platformTarget: PlatformTarget.macos,
      definitions: <ModuleDefinition>[runtimeModule, debugModule],
    );

    final reconciliation = reconcileModuleUninstall(
      registry: registry,
      uninstalledModuleIds: <String>[runtimeModule.manifest.moduleId],
    );
    final entries = runtimeSurfaceFeatureEntriesFor(
      reconciliation.registry.mountedModules,
    );

    expect(entries.map((entry) => entry.moduleId), <String>['debug.console']);
  });

  test('staged update keeps old runtime feature until restart then switches', () {
    final running = _module(
      moduleId: 'runtime.surface.timeline',
      displayName: 'Timeline',
      version: '1.0.0',
      slot: ModuleSlot.runtimeSurface,
    );
    final staged = _module(
      moduleId: 'runtime.surface.timeline',
      displayName: 'Timeline',
      version: '1.1.0',
      slot: ModuleSlot.runtimeSurface,
    );
    final registry = ModuleRegistry(
      platformTarget: PlatformTarget.macos,
      definitions: <ModuleDefinition>[running],
    );

    final beforeRestart = resolveStagedModuleUpdates(
      runningRegistry: registry,
      stagedModules: <ModuleDefinition>[staged],
      restartCompleted: false,
    );
    final afterRestart = resolveStagedModuleUpdates(
      runningRegistry: registry,
      stagedModules: <ModuleDefinition>[staged],
      restartCompleted: true,
    );

    expect(
      runtimeSurfaceFeatureEntriesFor(
        beforeRestart.registry.mountedModules,
      ).single.version,
      '1.0.0',
    );
    expect(
      runtimeSurfaceFeatureEntriesFor(
        afterRestart.registry.mountedModules,
      ).single.version,
      '1.1.0',
    );
  });
}

ModuleDefinition _module({
  required String moduleId,
  required String displayName,
  required ModuleSlot slot,
  String version = '1.0.0',
  bool mountedByDefault = true,
}) {
  return ModuleDefinition(
    manifest: ModuleManifest(
      moduleId: moduleId,
      displayName: displayName,
      version: version,
      kind: ModuleKind.optional,
      slot: slot,
      description: 'runtime feature test module',
      enabledByDefault: true,
      entrypoint: '$moduleId.dart',
      distributionPolicyRef: 'test-policy',
      capabilityFlags: const <String, bool>{},
    ),
    matrix: ModuleCapabilityMatrix(
      moduleId: moduleId,
      platforms: <PlatformTarget, ModuleCapabilityRule>{
        PlatformTarget.macos: ModuleCapabilityRule(
          supported: true,
          visible: true,
          installable: true,
          mountedByDefault: mountedByDefault,
          iosSafe: true,
          distributionChannel: 'bundled',
          note: 'test',
        ),
      },
    ),
  );
}
