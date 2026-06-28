import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/configuration/vityo_theme_override.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_configuration_store.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_manager.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_resolver.dart';
import 'package:vityo_app/src/view_ide/toolchain/styio_toolchain_lifecycle.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';
import 'package:vityo_app/src/view_render/settings/settings_surface.dart';

void main() {
  testWidgets('settings surface saves persisted theme accent override', (
    tester,
  ) async {
    VityoThemeOverride? savedOverride;
    CommandPaletteDisplayPreferences? savedCommandPalettePreferences;

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
              source: 'project',
              severity: ToolchainStatusSeverity.ready,
              title: 'Toolchain ready',
              message: 'Ready.',
              recoveryActions: <ToolchainRecoveryAction>[],
            ),
            commandPalettePreferences: const CommandPaletteDisplayPreferences(
              workspaceId: 'demo',
              defaultCategory: AppCommandCategory.navigation,
            ),
            onSaveCommandPalettePreferences: (preferences) async {
              savedCommandPalettePreferences = preferences;
            },
            onSaveThemeOverride: (override) async {
              savedOverride = override;
            },
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('settings-theme-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-command-palette-card')),
      findsOneWidget,
    );
    expect(find.text('default navigation'), findsOneWidget);
    final showRecentSwitch = find.byKey(
      const ValueKey('settings-command-palette-show-recent'),
    );
    await tester.ensureVisible(showRecentSwitch);
    await tester.tap(showRecentSwitch);
    await tester.pump();
    final saveCommandPaletteButton = find.byKey(
      const ValueKey('settings-command-palette-save'),
    );
    await tester.ensureVisible(saveCommandPaletteButton);
    await tester.tap(saveCommandPaletteButton);
    await tester.pump();

    expect(savedCommandPalettePreferences?.workspaceId, 'demo');
    expect(
      savedCommandPalettePreferences?.defaultCategory,
      AppCommandCategory.navigation,
    );
    expect(savedCommandPalettePreferences?.showRecentCommands, isFalse);

    await tester.enterText(
      find.byKey(const ValueKey('settings-theme-accent-input')),
      '#00A878',
    );
    final saveThemeButton = find.byKey(
      const ValueKey('settings-theme-save-button'),
    );
    await tester.ensureVisible(saveThemeButton);
    await tester.tap(saveThemeButton);
    await tester.pump();

    expect(savedOverride?.accent, const Color(0xFF00A878).toARGB32());
  });

  testWidgets('settings surface renders manager-backed toolchain status', (
    tester,
  ) async {
    final handledActions = <String>[];
    final handledBootstrapActions = <String>[];
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
              recoveryActions: <ToolchainRecoveryAction>[
                ToolchainRecoveryAction(
                  id: 'select-existing-toolchain',
                  label: 'Select existing toolchain',
                  description:
                      'Choose a local executable and register it manually.',
                ),
              ],
            ),
            toolchainBootstrapSummary: const ToolchainManagerBootstrapSummary(
              managerReport: ToolchainManagerStatusReport(
                status: ToolchainManagerStatus.unresolved,
                snapshot: ToolchainStateSnapshot(
                  targetId: 'settings-test',
                  workspaceId: 'demo',
                  entries: <ToolchainStateEntry>[],
                ),
                requirement: ToolchainRequirement(kind: ToolchainKind.compiler),
                resolution: ToolchainResolution(
                  status: ToolchainResolutionStatus.missingKind,
                  requirement: ToolchainRequirement(
                    kind: ToolchainKind.compiler,
                  ),
                  message: 'No compiler descriptor.',
                ),
                recoveryState: ToolchainRecoveryState(
                  kind: ToolchainRecoveryStateKind.needsSelection,
                  actionIds: <String>['select-styio-compiler'],
                ),
              ),
              styioLifecycle: StyioToolchainLifecycleReport(
                state: StyioToolchainLifecycleState.selectable,
                requiredRoles: <StyioToolchainRole>[
                  StyioToolchainRole.compiler,
                ],
                roles: <StyioToolchainRoleStatus>[
                  StyioToolchainRoleStatus(
                    role: StyioToolchainRole.compiler,
                    state: StyioToolchainRoleState.available,
                    required: true,
                    candidates: <ToolchainDescriptor>[
                      ToolchainDescriptor(
                        id: 'styio-compiler',
                        kind: ToolchainKind.compiler,
                        displayName: 'Styio Compiler',
                        executablePath: '/opt/styio/bin/styio',
                      ),
                    ],
                    message: 'Select Styio compiler.',
                  ),
                ],
                message: 'Select a Styio compiler before project bootstrap.',
              ),
              settingsActionIds: <String>['select-styio-compiler'],
              installerActionIds: <String>['install-managed-styio-toolchain'],
              projectBootstrapActionIds: <String>['open-toolchain-settings'],
            ),
            toolchainBootstrapActionDispatch:
                const ToolchainBootstrapActionDispatchResult(
                  status: ToolchainBootstrapActionDispatchStatus.dispatched,
                  actionId: 'install-managed-styio-toolchain',
                  message:
                      'Managed install plan prepared for language-service.',
                ),
            onToolchainRecoveryAction: (action) async {
              handledActions.add(action.id);
            },
            onToolchainBootstrapAction: (actionId) async {
              handledBootstrapActions.add(actionId);
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
      find.byKey(const ValueKey('settings-ide-capability-framework')),
      findsOneWidget,
    );
    expect(find.text('IDE Capability Framework'), findsOneWidget);
    expect(
      find.text('version vityo-ide-capability-framework-v1'),
      findsOneWidget,
    );
    expect(find.textContaining('required '), findsOneWidget);
    expect(find.text('Missing Required Capabilities'), findsNothing);
    expect(find.text('TODO Follow-ups'), findsOneWidget);
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
    expect(
      find.byKey(
        const ValueKey('settings-toolchain-install-execution-recovery'),
      ),
      findsOneWidget,
    );
    expect(find.text('Install Recovery'), findsOneWidget);
    expect(find.text('Select existing toolchain'), findsOneWidget);
    expect(
      find.text('Choose a local executable and register it manually.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-toolchain-bootstrap-summary')),
      findsOneWidget,
    );
    expect(find.text('Toolchain Bootstrap'), findsOneWidget);
    expect(find.text('manager unresolved'), findsOneWidget);
    expect(find.text('styio selectable'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('settings-toolchain-bootstrap-dispatch-result'),
      ),
      findsOneWidget,
    );
    expect(
      find.text(
        'Last dispatch: dispatched · install-managed-styio-toolchain',
      ),
      findsOneWidget,
    );
    expect(
      find.text('Managed install plan prepared for language-service.'),
      findsOneWidget,
    );

    final executeInstallPlanButton = find.byKey(
      const ValueKey('settings-toolchain-execute-install-plan'),
    );
    await tester.ensureVisible(executeInstallPlanButton);
    await tester.tap(executeInstallPlanButton);
    await tester.pump();

    expect(executeInstallPlanCount, 1);

    final executionRecoveryButton = find.byKey(
      const ValueKey(
        'settings-toolchain-install-execution-recovery-select-existing-toolchain',
      ),
    );
    await tester.ensureVisible(executionRecoveryButton);
    await tester.tap(executionRecoveryButton);
    await tester.pump();

    expect(handledActions, <String>['select-existing-toolchain']);

    final bootstrapSettingsButton = find.byKey(
      const ValueKey(
        'settings-toolchain-bootstrap-settings-select-styio-compiler',
      ),
    );
    await tester.ensureVisible(bootstrapSettingsButton);
    await tester.tap(bootstrapSettingsButton);
    await tester.pump();

    expect(handledBootstrapActions, <String>['select-styio-compiler']);

    expect(find.text('Select an existing toolchain executable.'), findsWidgets);

    final installRecoveryButton = find.byKey(
      const ValueKey('settings-toolchain-recovery-install-managed-toolchain'),
    );
    await tester.ensureVisible(installRecoveryButton);
    await tester.tap(installRecoveryButton);
    await tester.pump();

    expect(
      handledActions,
      <String>['select-existing-toolchain', 'install-managed-toolchain'],
    );

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

  testWidgets('settings surface renders Clang C++ version manager', (
    tester,
  ) async {
    final selectedClangCppVersions = <String>[];

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
              severity: ToolchainStatusSeverity.ready,
              title: 'Toolchain ready',
              message: 'Ready.',
              recoveryActions: <ToolchainRecoveryAction>[],
            ),
            toolchainSettings: ToolchainSettingsSurface.fromManagerStatusReport(
              const ToolchainManagerStatusReport(
                status: ToolchainManagerStatus.ready,
                snapshot: ToolchainStateSnapshot(
                  targetId: 'settings-test',
                  workspaceId: 'demo',
                  entries: <ToolchainStateEntry>[
                    ToolchainStateEntry(
                      id: 'clang-17',
                      kind: ToolchainKind.compiler,
                      displayName: 'Clang 17',
                      executablePath: '/opt/clang-17/bin/clang++',
                      active: true,
                      version: '17.0.6',
                      metadata: <String, Object?>{
                        'compilerFamily': 'clang',
                        'cCompilerPath': '/opt/clang-17/bin/clang',
                        'cxxCompilerPath': '/opt/clang-17/bin/clang++',
                        'clangVendor': 'llvm',
                        'source': 'system',
                      },
                    ),
                    ToolchainStateEntry(
                      id: 'clang-18',
                      kind: ToolchainKind.compiler,
                      displayName: 'Clang 18',
                      executablePath: '/opt/clang-18/bin/clang++',
                      active: false,
                      version: '18.1.8',
                      metadata: <String, Object?>{
                        'compilerFamily': 'clang',
                        'cCompilerPath': '/opt/clang-18/bin/clang',
                        'cxxCompilerPath': '/opt/clang-18/bin/clang++',
                        'clangVendor': 'apple',
                        'source': 'manual',
                      },
                    ),
                    ToolchainStateEntry(
                      id: 'cmake',
                      kind: ToolchainKind.buildTool,
                      displayName: 'CMake',
                      executablePath: '/usr/bin/cmake',
                      active: true,
                      metadata: <String, Object?>{'toolFamily': 'cmake'},
                    ),
                    ToolchainStateEntry(
                      id: 'ninja',
                      kind: ToolchainKind.buildTool,
                      displayName: 'Ninja',
                      executablePath: '/usr/bin/ninja',
                      active: false,
                      metadata: <String, Object?>{'toolFamily': 'ninja'},
                    ),
                  ],
                ),
                requirement: ToolchainRequirement(kind: ToolchainKind.compiler),
                resolution: ToolchainResolution(
                  status: ToolchainResolutionStatus.resolved,
                  requirement: ToolchainRequirement(
                    kind: ToolchainKind.compiler,
                  ),
                ),
              ),
            ),
            onSelectClangCppVersion: (versionId, cppStandard) async {
              selectedClangCppVersions.add('$versionId:$cppStandard');
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('settings-clang-cpp-version-manager')),
      findsOneWidget,
    );
    expect(find.text('preference activeDefault'), findsOneWidget);
    expect(find.text('standard c++20'), findsOneWidget);
    expect(find.text('flag -std=c++20'), findsOneWidget);
    expect(find.text('handoff cmake+ninja'), findsOneWidget);
    expect(
      find.text('active clang Clang 17 17.0.6 llvm system'),
      findsOneWidget,
    );
    expect(find.text('clang Clang 18 18.1.8 apple manual'), findsOneWidget);

    final selectCpp23Button = find.byKey(
      const ValueKey('settings-clang-cpp-standard-23'),
    );
    await tester.ensureVisible(selectCpp23Button);
    await tester.tap(selectCpp23Button);
    await tester.pump();

    final selectClang18Button = find.descendant(
      of: find.byKey(const ValueKey('settings-clang-cpp-version-clang-18')),
      matching: find.byTooltip('Select Clang 18'),
    );
    await tester.ensureVisible(selectClang18Button);
    await tester.tap(selectClang18Button);
    await tester.pump();

    expect(selectedClangCppVersions, <String>['clang-17:23', 'clang-18:20']);
  });
}
