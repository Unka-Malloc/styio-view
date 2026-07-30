import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/toolchain/clang_cpp_version_configuration.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_configuration_store.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_install_executor.dart'
    as install;
import 'package:vityo_app/src/view_ide/toolchain/toolchain_install_policy.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_manager.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_resolver.dart';

void main() {
  test('toolchain status surface projects system compiler state', () {
    final surface = ToolchainStatusSurface.fromProjectToolchain(
      const ToolchainStatusSnapshot(
        source: ToolchainResolutionSource.environment,
        detail: 'System Styio machine contract resolved.',
        channel: 'system',
        version: '0.0.5',
      ),
    );

    expect(surface.severity, ToolchainStatusSeverity.ready);
    expect(surface.title, 'Toolchain ready');
    expect(surface.source, 'environment');
    expect(surface.version, '0.0.5');
    expect(surface.channel, 'system');
    expect(surface.actionable, isFalse);
    expect(surface.recoveryActions, isEmpty);
  });

  test('toolchain status surface projects unavailable compiler recovery', () {
    final surface = ToolchainStatusSurface.fromProjectToolchain(
      const ToolchainStatusSnapshot(
        source: ToolchainResolutionSource.unavailable,
        detail: 'System Styio is unavailable.',
      ),
    );

    expect(surface.severity, ToolchainStatusSeverity.unavailable);
    expect(surface.title, 'Toolchain unavailable');
    expect(surface.message, 'System Styio is unavailable.');
    expect(surface.actionable, isTrue);
    expect(
      surface.recoveryActions.map((action) => action.id),
      containsAll(<String>[
        'select-existing-toolchain',
        'use-degraded-mode',
      ]),
    );
  });

  test('toolchain status surface projects manager status report', () {
    const requirement = ToolchainRequirement(
      kind: ToolchainKind.languageService,
    );
    const descriptor = ToolchainDescriptor(
      id: 'styio-service',
      kind: ToolchainKind.languageService,
      displayName: 'Styio Service',
      executablePath: '/opt/styio/bin/styio',
      version: '0.0.7',
      channel: 'nightly',
    );
    const report = ToolchainManagerStatusReport(
      status: ToolchainManagerStatus.ready,
      snapshot: ToolchainStateSnapshot(
        targetId: 'test-target',
        workspaceId: 'demo',
        entries: <ToolchainStateEntry>[
          ToolchainStateEntry(
            id: 'styio-service',
            kind: ToolchainKind.languageService,
            displayName: 'Styio Service',
            executablePath: '/opt/styio/bin/styio',
            active: true,
            version: '0.0.7',
            channel: 'nightly',
          ),
        ],
      ),
      requirement: requirement,
      resolution: ToolchainResolution(
        status: ToolchainResolutionStatus.resolved,
        requirement: requirement,
        descriptor: descriptor,
      ),
    );

    final surface = ToolchainStatusSurface.fromManagerStatusReport(report);

    expect(surface.source, 'manager-report');
    expect(surface.severity, ToolchainStatusSeverity.ready);
    expect(surface.version, '0.0.7');
    expect(surface.channel, 'nightly');
    expect(surface.message, 'Toolchain manager resolved a usable toolchain.');
    expect(surface.recoveryActions, isEmpty);
  });

  test('toolchain settings surface projects manager details', () {
    const requirement = ToolchainRequirement(kind: ToolchainKind.runner);
    final report = ToolchainManagerStatusReport(
      status: ToolchainManagerStatus.unresolved,
      snapshot: const ToolchainStateSnapshot(
        targetId: 'test-target',
        workspaceId: 'demo',
        entries: <ToolchainStateEntry>[
          ToolchainStateEntry(
            id: 'styio-runner',
            kind: ToolchainKind.runner,
            displayName: 'Styio Runner',
            executablePath: '/opt/styio/bin/styio',
            active: true,
            version: '0.0.8',
            channel: 'nightly',
          ),
        ],
      ),
      requirement: requirement,
      resolution: const ToolchainResolution(
        status: ToolchainResolutionStatus.missingKind,
        requirement: requirement,
        message: 'No language service toolchain resolved.',
      ),
      capabilities: const <ToolchainCapabilityStatus>[
        ToolchainCapabilityStatus(
          kind: ToolchainKind.runner,
          state: ToolchainCapabilityState.active,
          active: true,
          descriptorId: 'styio-runner',
        ),
        ToolchainCapabilityStatus(
          kind: ToolchainKind.languageService,
          state: ToolchainCapabilityState.unresolved,
          active: false,
          message: 'No language service descriptor.',
        ),
      ],
      recoveryState: const ToolchainRecoveryState(
        kind: ToolchainRecoveryStateKind.needsSelection,
        actionIds: <String>[
          'select-existing-toolchain',
          'install-managed-toolchain',
        ],
        message: 'Select or install a StyioService toolchain.',
      ),
      installHistory: ToolchainInstallHistorySnapshot(
        entries: <ToolchainInstallHistoryEntry>[
          ToolchainInstallHistoryEntry(
            id: 'install-1',
            status: 'failed',
            mode: 'externalCommand',
            kind: 'language-service',
            succeeded: false,
            recordedAt: DateTime.utc(2026, 5, 17),
            message: 'installer exited 64',
          ),
        ],
      ),
    );

    final surface = ToolchainSettingsSurface.fromManagerStatusReport(
      report,
      clangCppVersionPreference: const ClangCppVersionPreference(
        versionId: 'clang-18',
        cppStandard: CppLanguageStandard.cpp23,
      ),
    );

    expect(surface.targetId, 'test-target');
    expect(surface.workspaceId, 'demo');
    expect(surface.status.source, 'manager-report');
    expect(surface.toolchains.single.id, 'styio-runner');
    expect(surface.toolchains.single.active, isTrue);
    expect(
      surface.capabilities.map((capability) => capability.state),
      containsAll(<String>['active', 'unresolved']),
    );
    expect(surface.recoveryState.kind, 'needsSelection');
    expect(surface.recoveryState.actionable, isTrue);
    expect(surface.installHistory.single.id, 'install-1');
    expect(surface.toJson()['hasManagerSnapshot'], isTrue);
  });

  test('toolchain settings surface projects Clang C++ version manager', () {
    const report = ToolchainManagerStatusReport(
      status: ToolchainManagerStatus.ready,
      snapshot: ToolchainStateSnapshot(
        targetId: 'test-target',
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
        requirement: ToolchainRequirement(kind: ToolchainKind.compiler),
      ),
    );

    final surface = ToolchainSettingsSurface.fromManagerStatusReport(
      report,
      clangCppVersionPreference: const ClangCppVersionPreference(
        versionId: 'clang-18',
        cppStandard: CppLanguageStandard.cpp23,
      ),
    );
    final clangCpp = surface.clangCppVersions;
    final json = surface.toJson();

    expect(clangCpp, isNotNull);
    expect(clangCpp!.activeVersionId, 'clang-18');
    expect(clangCpp.requestedVersionId, 'clang-18');
    expect(clangCpp.preferenceStatus, 'configured');
    expect(clangCpp.defaultCppStandard, '23');
    expect(clangCpp.defaultCompilerFlag, '-std=c++23');
    expect(
      clangCpp.supportedStandards
          .where((standard) => standard.active)
          .map((standard) => standard.cmakeValue),
      <String>['23'],
    );
    expect(
      clangCpp.candidates.map((candidate) => candidate.versionId),
      <String>['clang-17', 'clang-18'],
    );
    expect(clangCpp.candidates.first.vendor, 'llvm');
    expect(clangCpp.candidates.last.vendor, 'apple');
    expect(clangCpp.candidates.first.active, isFalse);
    expect(clangCpp.candidates.last.active, isTrue);
    expect(clangCpp.cmakeAvailable, isTrue);
    expect(clangCpp.ninjaAvailable, isTrue);
    expect(clangCpp.preferredBuildEngineHandoff?.label, 'cmake+ninja');
    final clangCppJson = json['clangCppVersions']! as Map<String, Object?>;
    final candidateJson = clangCppJson['candidates']! as List<Object?>;
    expect(
      (candidateJson.first! as Map<String, Object?>)['vendor'],
      'llvm',
    );
    expect(json['clangCppVersions'], isA<Map<String, Object?>>());
  });

  test('toolchain install execution surface projects recovery actions', () {
    final surface = ToolchainInstallExecutionSurface.fromResult(
      const install.ToolchainInstallExecutionResult(
        status: install.ToolchainInstallExecutionStatus.requiresUserAction,
        plan: ToolchainInstallPlan(
          status: ToolchainInstallPlanStatus.planned,
          mode: ToolchainInstallMode.manualSelection,
          requirement: ToolchainRequirement(kind: ToolchainKind.languageService),
          message: 'Select an existing toolchain executable.',
        ),
        recoveryActions: <install.ToolchainRecoveryAction>[
          install.ToolchainRecoveryAction(
            id: 'select-existing-toolchain',
            label: 'Select existing toolchain',
            detail: 'Choose a local executable and register it manually.',
          ),
        ],
        message: 'Select an existing toolchain executable.',
      ),
    );

    expect(surface.status, 'requiresUserAction');
    expect(surface.recoveryActions.single.id, 'select-existing-toolchain');
    expect(
      surface.recoveryActions.single.description,
      'Choose a local executable and register it manually.',
    );
    expect(
      surface.toJson()['recoveryActions'],
      isA<List<Object?>>(),
    );
  });
}
