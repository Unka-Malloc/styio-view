import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
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
        source: ToolchainResolutionSource.unavailable,
        detail: 'System Styio is unavailable.',
      ),
    );
    final status = ToolchainStatusSurface.fromProjectToolchain(
      projectGraph.toolchain,
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
    expect(find.text('Toolchain unavailable'), findsOneWidget);
    expect(find.text('System Styio is unavailable.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('toolchain-recovery-select-existing-toolchain')),
      findsOneWidget,
    );
    expect(find.text('Use degraded mode'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey('toolchain-recovery-select-existing-toolchain')),
    );
    await tester.pump();

    expect(invokedActions, <String>['select-existing-toolchain']);
  });
}

ProjectGraphSnapshot _projectGraph(ToolchainStatusSnapshot toolchain) {
  return ProjectGraphSnapshot(
    id: '/workspace/demo/pafio.toml',
    title: 'demo/app',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/demo/pafio.toml',
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
