import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/toolchain_management_adapter.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';
import 'package:vityo_app/src/view_render/platform/viewport_profile.dart';
import 'package:vityo_app/src/view_render/runtime/runtime.dart';

void main() {
  testWidgets('runtime surface renders toolchain recovery status', (
    tester,
  ) async {
    final projectGraph = _projectGraph(
      const ToolchainStatusSnapshot(
        source: ToolchainResolutionSource.managedCurrent,
        detail: 'Managed toolchain resolved.',
        channel: 'nightly',
        version: '0.0.6',
      ),
    );
    final status = ToolchainStatusSurface.fromProjectToolchain(
      projectGraph.toolchain,
      lastCommand: const ToolchainCommandResult(
        command: 'tool use',
        status: ToolchainCommandStatus.failed,
        statusMessage: 'spio tool use failed with exit code 64.',
        stdout: '',
        stderr: 'exit 64',
      ),
    );
    final invokedActions = <String>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 1100,
            height: 900,
            child: RuntimeSurface(
              platformTarget: PlatformTarget.macos,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1100,
                height: 900,
              ),
              projectGraph: projectGraph,
              toolchainStatus: status,
              onToolchainRecoveryAction: (action) async {
                invokedActions.add(action.id);
              },
              mountedModules: const [],
              adapterCapabilities: const <AdapterCapabilitySnapshot>[],
              executionSession: null,
              runtimeEvents: const [],
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('toolchain-status-card')), findsOneWidget);
    expect(find.text('Toolchain command failed'), findsOneWidget);
    expect(
      find.text('spio tool use failed with exit code 64.'),
      findsOneWidget,
    );
    expect(find.text('command tool use'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('toolchain-recovery-retry-tool-use')),
      findsOneWidget,
    );
    expect(find.text('Show logs'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('toolchain-recovery-retry-tool-use')),
    );
    await tester.pump();

    expect(invokedActions, <String>['retry-tool-use']);
  });
}

ProjectGraphSnapshot _projectGraph(ToolchainStatusSnapshot toolchain) {
  return ProjectGraphSnapshot(
    id: '/workspace/demo/spio.toml',
    title: 'demo/app',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/demo/spio.toml',
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: const <String>['/workspace/demo/src/main.styio'],
    toolchain: toolchain,
    lockState: ProjectLockState.fresh,
    vendorState: ProjectVendorState.present,
    notes: const <String>[],
  );
}
