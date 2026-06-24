import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';
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
      ExtensionInstallPlan? installPlan;
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
              marketplaceIndex: const ExtensionMarketplaceIndex(
                workspaceId: 'demo',
                listings: <ExtensionMarketplaceListing>[
                  ExtensionMarketplaceListing(
                    manifest: ExtensionManifest(
                      extensionId: 'styio.language',
                      displayName: 'Styio Language',
                      version: '1.0.0',
                      publisher: 'vityo',
                      entrypoint: 'styio_language.dart',
                      description: 'Styio language support.',
                      trustedByDefault: true,
                      metadata: <String, Object?>{
                        'isolationMode': 'local-process',
                      },
                    ),
                    sourceUri:
                        'https://marketplace.vityo.invalid/styio.language.zip',
                    summary: 'Language support for Styio projects.',
                    categories: <String>['language', 'styio'],
                    verified: true,
                  ),
                ],
              ),
              marketplaceQuery: 'styio',
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
              onInstallExtension: (plan) async {
                installPlan = plan;
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
      expect(find.text('marketplace 1'), findsOneWidget);
      expect(find.text('query styio'), findsOneWidget);
      expect(find.text('Marketplace'), findsOneWidget);
      expect(find.text('Styio Language'), findsOneWidget);
      expect(find.text('ready'), findsOneWidget);
      expect(find.text('execution ready'), findsOneWidget);
      expect(find.text('steps 5'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey('extensions-install-execution-styio.language'),
        ),
        findsOneWidget,
      );
      expect(find.text('download-package ready'), findsOneWidget);
      expect(find.text('verify-signature ready'), findsOneWidget);
      expect(find.text('Runtime Panel'), findsOneWidget);
      expect(find.text('update'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('extensions-refresh-modules')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('extensions-disable-runtime.panel')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('extensions-disable-runtime.panel')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('extensions-install-styio.language')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('extensions-install-styio.language')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('extensions-enable-agent.panel')),
      );
      await tester.pump();
      expect(find.text('Agent Panel'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('extensions-enable-agent.panel')),
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey('extensions-trust-agent.panel')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('extensions-trust-agent.panel')),
      );
      await tester.pump();

      expect(refreshCount, 1);
      expect(disabledModuleId, 'runtime.panel');
      expect(installPlan?.extensionId, 'styio.language');
      expect(installPlan?.ready, isTrue);
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
