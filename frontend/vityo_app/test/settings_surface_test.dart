import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_configuration_store.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_manager.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_resolver.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';
import 'package:vityo_app/src/view_render/settings/settings_surface.dart';

void main() {
  testWidgets('settings surface renders manager-backed toolchain status', (
    tester,
  ) async {
    final handledActions = <String>[];
    final selectedToolchains = <String>[];
    final clearedToolchains = <ToolchainKind>[];
    var executeInstallPlanCount = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            toolchainStatus: const ToolchainStatusSurface(
              source: 'manager-report',
              severity: ToolchainStatusSeverity.unavailable,
              title: 'Toolchain unavailable',
              message: 'Select or install a Styio toolchain.',
              version: '0.0.9',
              channel: 'nightly',
              recoveryActions: <ToolchainRecoveryAction>[
                ToolchainRecoveryAction(
                  id: 'install-managed-toolchain',
                  label: 'Install managed toolchain',
                  description: 'Install a managed Styio toolchain.',
                ),
              ],
            ),
            toolchainSettings: ToolchainSettingsSurface.fromManagerStatusReport(
              ToolchainManagerStatusReport(
                status: ToolchainManagerStatus.unresolved,
                snapshot: const ToolchainStateSnapshot(
                  targetId: 'settings-test',
                  workspaceId: 'demo',
                  entries: <ToolchainStateEntry>[
                    ToolchainStateEntry(
                      id: 'styio-runner',
                      kind: ToolchainKind.runner,
                      displayName: 'Styio Runner',
                      executablePath: '/opt/styio/bin/styio',
                      active: true,
                      version: '0.0.9',
                      channel: 'nightly',
                    ),
                    ToolchainStateEntry(
                      id: 'styio-service',
                      kind: ToolchainKind.languageService,
                      displayName: 'Styio Service',
                      executablePath: '/opt/styio/bin/styio-service',
                      active: false,
                      version: '0.0.9',
                      channel: 'nightly',
                    ),
                  ],
                ),
                requirement: const ToolchainRequirement(
                  kind: ToolchainKind.languageService,
                ),
                resolution: const ToolchainResolution(
                  status: ToolchainResolutionStatus.missingKind,
                  requirement: ToolchainRequirement(
                    kind: ToolchainKind.languageService,
                  ),
                  message: 'No language service descriptor.',
                ),
                capabilities: const <ToolchainCapabilityStatus>[
                  ToolchainCapabilityStatus(
                    kind: ToolchainKind.runner,
                    state: ToolchainCapabilityState.active,
                    active: true,
                    descriptorId: 'styio-runner',
                  ),
                ],
                recoveryState: const ToolchainRecoveryState(
                  kind: ToolchainRecoveryStateKind.needsSelection,
                  actionIds: <String>['install-managed-toolchain'],
                  message: 'Install a managed language service toolchain.',
                ),
                installHistory: ToolchainInstallHistorySnapshot(
                  entries: <ToolchainInstallHistoryEntry>[
                    ToolchainInstallHistoryEntry(
                      id: 'history-1',
                      status: 'failed',
                      mode: 'externalCommand',
                      kind: 'language-service',
                      succeeded: false,
                      recordedAt: DateTime.utc(2026, 5, 17),
                    ),
                  ],
                ),
              ),
            ),
            toolchainInstallPlan: const ToolchainInstallPlanSurface(
              status: 'planned',
              mode: 'manualSelection',
              kind: 'language-service',
              actionable: true,
              message: 'Select an existing toolchain executable.',
            ),
            toolchainInstallExecution: const ToolchainInstallExecutionSurface(
              status: 'requiresUserAction',
              mode: 'manualSelection',
              kind: 'language-service',
              succeeded: false,
              message: 'Select an existing toolchain executable.',
            ),
            onToolchainRecoveryAction: (action) async {
              handledActions.add(action.id);
            },
            onSelectToolchain: (id) async {
              selectedToolchains.add(id);
            },
            onClearToolchain: (kind) async {
              clearedToolchains.add(kind);
            },
            onExecuteToolchainInstallPlan: () async {
              executeInstallPlanCount += 1;
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('settings-surface')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-toolchain-status-card')),
      findsOneWidget,
    );
    expect(find.text('source manager-report'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-toolchain-candidates')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-toolchain-styio-runner')),
      findsOneWidget,
    );
    expect(
      find.text('active runner Styio Runner 0.0.9 nightly'),
      findsOneWidget,
    );
    expect(
      find.text('language-service Styio Service 0.0.9 nightly'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-toolchain-capability-runner')),
      findsOneWidget,
    );
    expect(find.text('state needsSelection'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-toolchain-install-history')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-toolchain-install-history-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-toolchain-install-plan')),
      findsOneWidget,
    );
    expect(find.text('mode manualSelection'), findsWidgets);
    expect(find.text('kind language-service'), findsWidgets);
    expect(find.text('Select an existing toolchain executable.'), findsWidgets);
    expect(
      find.byKey(const ValueKey('settings-toolchain-install-execution')),
      findsOneWidget,
    );
    expect(find.text('execution requiresUserAction'), findsOneWidget);

    final executeInstallPlanButton = find.byKey(
      const ValueKey('settings-toolchain-execute-install-plan'),
    );
    await tester.ensureVisible(executeInstallPlanButton);
    await tester.tap(executeInstallPlanButton);
    await tester.pump();

    expect(executeInstallPlanCount, 1);

    expect(find.text('Select an existing toolchain executable.'), findsWidgets);

    final installRecoveryButton = find.byKey(
      const ValueKey('settings-toolchain-recovery-install-managed-toolchain'),
    );
    await tester.ensureVisible(installRecoveryButton);
    await tester.tap(installRecoveryButton);
    await tester.pump();

    expect(handledActions, <String>['install-managed-toolchain']);

    final selectServiceButton = find.byTooltip('Select Styio Service');
    await tester.ensureVisible(selectServiceButton);
    await tester.tap(selectServiceButton);
    await tester.pump();

    expect(selectedToolchains, <String>['styio-service']);

    final clearRunnerButton = find.byTooltip('Clear active Styio Runner');
    await tester.ensureVisible(clearRunnerButton);
    await tester.tap(clearRunnerButton);
    await tester.pump();

    expect(clearedToolchains, <ToolchainKind>[ToolchainKind.runner]);
  });
}
