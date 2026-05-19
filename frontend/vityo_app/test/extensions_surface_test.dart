import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/module_host/module_capability_matrix.dart';
import 'package:vityo_app/src/view_ide/module_host/module_definition.dart';
import 'package:vityo_app/src/view_ide/module_host/module_lifecycle.dart';
import 'package:vityo_app/src/view_ide/module_host/module_manifest.dart';
import 'package:vityo_app/src/view_render/extensions/extensions.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets(
    'extensions surface renders module inventory and refresh action',
    (tester) async {
      var refreshCount = 0;
      String? enabledModuleId;
      String? disabledModuleId;
      String? trustedModuleId;
      final runtime = _module(
        moduleId: 'runtime.panel',
        displayName: 'Runtime Panel',
        slot: ModuleSlot.runtimeSurface,
      );
      final agent = _module(
        moduleId: 'agent.panel',
        displayName: 'Agent Panel',
        slot: ModuleSlot.agentSurface,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ExtensionsSurface(
              viewportProfile: resolveViewportProfile(
                platformTarget: PlatformTarget.macos,
                width: 1200,
                height: 800,
              ),
              visibleModules: <ModuleDefinition>[runtime, agent],
              mountedModules: <ModuleDefinition>[runtime],
              moduleStates: const <ModuleLifecycleState>[
                ModuleLifecycleState(
                  moduleId: 'runtime.panel',
                  enabled: true,
                  updateAvailable: true,
                ),
                ModuleLifecycleState(
                  moduleId: 'agent.panel',
                  enabled: false,
                  trustState: ModuleTrustState.untrusted,
                ),
              ],
              onRefreshModules: () async {
                refreshCount += 1;
              },
              onEnableModule: (moduleId) async {
                enabledModuleId = moduleId;
              },
              onDisableModule: (moduleId) async {
                disabledModuleId = moduleId;
              },
              onTrustModule: (moduleId) async {
                trustedModuleId = moduleId;
              },
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('extensions-surface')), findsOneWidget);
      expect(find.text('Extensions'), findsOneWidget);
      expect(find.text('visible 2'), findsOneWidget);
      expect(find.text('mounted 1'), findsOneWidget);
      expect(find.text('disabled 1'), findsOneWidget);
      expect(find.text('untrusted 1'), findsOneWidget);
      expect(find.text('marketplace scaffolded'), findsOneWidget);
      expect(find.text('Runtime Panel'), findsOneWidget);
      expect(find.text('update'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('extensions-refresh-modules')),
      );
      await tester.tap(
        find.byKey(const ValueKey('extensions-disable-runtime.panel')),
      );
      await tester.drag(
        find.byKey(const ValueKey('extensions-module-list')),
        const Offset(0, -240),
      );
      await tester.pump();
      expect(find.text('Agent Panel'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('extensions-enable-agent.panel')),
      );
      await tester.tap(
        find.byKey(const ValueKey('extensions-trust-agent.panel')),
      );
      await tester.pump();

      expect(refreshCount, 1);
      expect(disabledModuleId, 'runtime.panel');
      expect(enabledModuleId, 'agent.panel');
      expect(trustedModuleId, 'agent.panel');
    },
  );
}

ModuleDefinition _module({
  required String moduleId,
  required String displayName,
  required ModuleSlot slot,
}) {
  return ModuleDefinition(
    manifest: ModuleManifest(
      moduleId: moduleId,
      displayName: displayName,
      version: '1.0.0',
      kind: ModuleKind.optional,
      slot: slot,
      description: '$displayName module.',
      enabledByDefault: true,
      entrypoint: 'lib/main.dart',
      distributionPolicyRef: 'local',
      capabilityFlags: const <String, bool>{'ui': true},
    ),
    matrix: const ModuleCapabilityMatrix(
      moduleId: 'test',
      platforms: <PlatformTarget, ModuleCapabilityRule>{
        PlatformTarget.macos: ModuleCapabilityRule(
          supported: true,
          visible: true,
          installable: true,
          mountedByDefault: true,
          iosSafe: true,
          distributionChannel: 'local',
          note: 'test',
        ),
      },
    ),
  );
}
