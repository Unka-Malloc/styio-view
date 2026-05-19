import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/module_host/module_capability_matrix.dart';
import 'package:vityo_app/src/module_host/module_definition.dart';
import 'package:vityo_app/src/module_host/module_manifest.dart';
import 'package:vityo_app/src/module_host/module_registry.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('module manifest and capability matrix parse module contracts', () {
    final manifest = ModuleManifest.parse('''
{
  "moduleId": "runtime.surface.basic",
  "displayName": "Runtime Surface",
  "version": "1.2.3",
  "kind": "optional",
  "slot": "runtimeSurface",
  "description": "Runtime panel",
  "enabledByDefault": true,
  "entrypoint": "runtime.dart",
  "distributionPolicyRef": "runtime-policy",
  "capabilityFlags": {
    "runtimeEvents": true,
    "nativeBridge": false
  }
}
''');
    final matrix = ModuleCapabilityMatrix.parse('''
{
  "moduleId": "runtime.surface.basic",
  "platforms": {
    "android": {
      "supported": true,
      "visible": true,
      "installable": true,
      "mountedByDefault": false,
      "iosSafe": true,
      "distributionChannel": "self-hosted",
      "note": "Android optional runtime surface."
    }
  }
}
''');

    expect(manifest.moduleId, 'runtime.surface.basic');
    expect(manifest.kind, ModuleKind.optional);
    expect(manifest.slot, ModuleSlot.runtimeSurface);
    expect(manifest.capabilityFlags['runtimeEvents'], isTrue);
    expect(manifest.capabilityFlags['nativeBridge'], isFalse);
    expect(matrix.moduleId, manifest.moduleId);
    expect(matrix.ruleFor(PlatformTarget.android).supported, isTrue);
    expect(matrix.ruleFor(PlatformTarget.android).distributionChannel, 'self-hosted');
  });

  test('module registry hides unsupported platform entries', () {
    final module = ModuleDefinition(
      manifest: ModuleManifest(
        moduleId: 'debug.console',
        displayName: 'Debug Console',
        version: '1.0.0',
        kind: ModuleKind.optional,
        slot: ModuleSlot.debugTools,
        description: 'Debug tools',
        enabledByDefault: true,
        entrypoint: 'debug.dart',
        distributionPolicyRef: 'debug-policy',
        capabilityFlags: const <String, bool>{},
      ),
      matrix: const ModuleCapabilityMatrix(
        moduleId: 'debug.console',
        platforms: <PlatformTarget, ModuleCapabilityRule>{
          PlatformTarget.android: ModuleCapabilityRule(
            supported: false,
            visible: true,
            installable: false,
            mountedByDefault: false,
            iosSafe: true,
            distributionChannel: 'self-hosted',
            note: 'Visible flag must not override unsupported Android rule.',
          ),
          PlatformTarget.macos: ModuleCapabilityRule(
            supported: true,
            visible: true,
            installable: true,
            mountedByDefault: true,
            iosSafe: true,
            distributionChannel: 'self-hosted',
            note: 'Enabled on desktop.',
          ),
        },
      ),
    );

    final androidRegistry = ModuleRegistry(
      platformTarget: PlatformTarget.android,
      definitions: <ModuleDefinition>[module],
    );
    final desktopRegistry = ModuleRegistry(
      platformTarget: PlatformTarget.macos,
      definitions: <ModuleDefinition>[module],
    );

    expect(module.isVisibleOn(PlatformTarget.android), isFalse);
    expect(androidRegistry.visibleModules, isEmpty);
    expect(androidRegistry.mountedModules, isEmpty);
    expect(desktopRegistry.visibleModules.single.manifest.moduleId, 'debug.console');
    expect(desktopRegistry.mountedModules.single.manifest.moduleId, 'debug.console');
  });
}
