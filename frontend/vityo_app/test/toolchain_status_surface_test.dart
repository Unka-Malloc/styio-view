import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/toolchain_management_adapter.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_configuration_store.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_manager.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_resolver.dart';

void main() {
  test('toolchain status surface projects ready project pin state', () {
    final surface = ToolchainStatusSurface.fromProjectToolchain(
      const ToolchainStatusSnapshot(
        source: ToolchainResolutionSource.projectPin,
        detail: 'Project toolchain pin resolved.',
        pinPath: '/workspace/demo/spio-toolchain.toml',
        channel: 'stable',
        version: '0.0.5',
      ),
    );

    expect(surface.severity, ToolchainStatusSeverity.ready);
    expect(surface.title, 'Toolchain ready');
    expect(surface.source, 'project-pin');
    expect(surface.version, '0.0.5');
    expect(surface.channel, 'stable');
    expect(surface.actionable, isFalse);
    expect(surface.recoveryActions, isEmpty);
    expect(surface.toJson()['pinPath'], '/workspace/demo/spio-toolchain.toml');
  });

  test('toolchain status surface projects failed command recovery', () {
    final surface = ToolchainStatusSurface.fromProjectToolchain(
      const ToolchainStatusSnapshot(
        source: ToolchainResolutionSource.managedCurrent,
        detail: 'Managed toolchain resolved.',
        channel: 'nightly',
        version: '0.0.6',
      ),
      lastCommand: const ToolchainCommandResult(
        command: 'tool use',
        status: ToolchainCommandStatus.failed,
        statusMessage: 'spio tool use failed with exit code 64.',
        stdout: '',
        stderr: 'exit 64',
      ),
    );

    expect(surface.severity, ToolchainStatusSeverity.failed);
    expect(surface.title, 'Toolchain command failed');
    expect(surface.message, 'spio tool use failed with exit code 64.');
    expect(surface.lastCommand, 'tool use');
    expect(surface.actionable, isTrue);
    expect(
      surface.recoveryActions.map((action) => action.id),
      containsAll(<String>[
        'retry-tool-use',
        'show-toolchain-logs',
        'select-existing-toolchain',
      ]),
    );
    expect(surface.toJson()['lastCommandStatus'], 'failed');
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

    final surface = ToolchainSettingsSurface.fromManagerStatusReport(report);

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
}
