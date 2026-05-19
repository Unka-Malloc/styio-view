import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/backend_toolchain/execution_route_summary.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/interaction/toolchain_status_surface.dart';
import 'package:vityo_app/src/view_render/native_tool_result_summary.dart';
import 'package:vityo_app/src/view_render/platform/viewport_profile.dart';
import 'package:vityo_app/src/view_render/runtime/runtime_surface.dart';

void main() {
  testWidgets(
    'backend route product gate matrix renders normalized route states',
    (tester) async {
      final scenarios = <_BackendRouteScenario>[
        _BackendRouteScenario(
          label: 'local-cli scratch',
          platformTarget: PlatformTarget.macos,
          projectGraph: ProjectGraphSnapshot.scratch(
            workspaceRoot: '/workspace/local-cli',
            activeFilePath: '/workspace/local-cli/main.styio',
            title: 'Local CLI',
            activeCompiler: const CompilerHandshakeSnapshot(
              binaryPath: '/toolchains/styio/bin/styio',
              tool: 'styio',
              compilerVersion: '0.1.0',
              channel: 'stable',
              variant: 'desktop',
              capabilities: <String>['machine_info_json', 'single_file_entry'],
              supportedContractVersions: <String, List<int>>{
                'machine_info': <int>[1],
              },
              integrationPhase: 'single-file-live',
            ),
            notes: const <String>[],
          ),
          adapterCapabilities: _capabilities(
            cliExecution: AdapterCapabilityLevel.partial,
          ),
          expectedRouteKind: BackendExecutionRouteKind.localCli,
          expectedAllowed: true,
        ),
        _BackendRouteScenario(
          label: 'hosted project',
          platformTarget: PlatformTarget.web,
          projectGraph: _hostedProjectGraph(),
          adapterCapabilities: _capabilities(
            cloudExecution: AdapterCapabilityLevel.available,
          ),
          expectedRouteKind: BackendExecutionRouteKind.hosted,
          expectedAllowed: true,
        ),
        _BackendRouteScenario(
          label: 'blocked local project',
          platformTarget: PlatformTarget.macos,
          projectGraph: ProjectGraphSnapshot.scratch(
            workspaceRoot: '/workspace/blocked',
            activeFilePath: '/workspace/blocked/main.styio',
            title: 'Blocked',
            notes: const <String>[],
          ),
          adapterCapabilities: _capabilities(),
          expectedRouteKind: BackendExecutionRouteKind.blocked,
          expectedAllowed: false,
        ),
      ];

      for (final scenario in scenarios) {
        final selection = selectBackendExecutionRoute(
          platformTarget: scenario.platformTarget,
          projectGraph: scenario.projectGraph,
          adapterCapabilities: scenario.adapterCapabilities,
        );

        expect(selection.routeKind, scenario.expectedRouteKind);
        expect(selection.allowed, scenario.expectedAllowed);
        final buildSummary = nativeToolMetadataSummaryText(<String, Object?>{
          'buildResult': const <String, Object?>{
            'status': 'passed',
            'diagnosticCount': 0,
          },
          'backendRouteSelection': selection.toJson(),
        });
        final testSummary = nativeToolMetadataSummaryText(<String, Object?>{
          'testResult': const <String, Object?>{
            'status': 'passed',
            'passedCount': 2,
            'totalCount': 2,
          },
          'backendRouteSelection': selection.toJson(),
        });
        expect(
          buildSummary,
          contains('route ${scenario.expectedRouteKind.wireValue}'),
          reason: scenario.label,
        );
        expect(
          testSummary,
          contains('route ${scenario.expectedRouteKind.wireValue}'),
          reason: scenario.label,
        );
        if (!scenario.expectedAllowed) {
          expect(buildSummary, contains('blocked'), reason: scenario.label);
          expect(testSummary, contains('blocked'), reason: scenario.label);
        }

        await tester.pumpWidget(
          MaterialApp(
            home: RuntimeSurface(
              platformTarget: scenario.platformTarget,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.desktop,
                width: 1440,
                height: 900,
              ),
              projectGraph: scenario.projectGraph,
              toolchainStatus: ToolchainStatusSurface.fromProjectToolchain(
                scenario.projectGraph.toolchain,
              ),
              mountedModules: const [],
              adapterCapabilities: scenario.adapterCapabilities,
              executionSession: null,
              runtimeEvents: const [],
            ),
          ),
        );

        expect(
          find.textContaining('(${scenario.expectedRouteKind.wireValue})'),
          findsOneWidget,
          reason: scenario.label,
        );
      }
    },
  );
}

class _BackendRouteScenario {
  const _BackendRouteScenario({
    required this.label,
    required this.platformTarget,
    required this.projectGraph,
    required this.adapterCapabilities,
    required this.expectedRouteKind,
    required this.expectedAllowed,
  });

  final String label;
  final PlatformTarget platformTarget;
  final ProjectGraphSnapshot projectGraph;
  final List<AdapterCapabilitySnapshot> adapterCapabilities;
  final BackendExecutionRouteKind expectedRouteKind;
  final bool expectedAllowed;
}

ProjectGraphSnapshot _hostedProjectGraph() {
  return ProjectGraphSnapshot(
    id: 'hosted-route-gate',
    title: 'Hosted Route Gate',
    kind: ProjectKind.hosted,
    workspaceRoot: '/workspace/hosted-route-gate',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/hosted-route-gate/spio.toml',
    dependencies: const <ProjectDependencySnapshot>[],
    packages: const <ProjectPackageSnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: const <String>[
      '/workspace/hosted-route-gate/src/main.styio',
    ],
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'hosted pin',
    ),
    lockState: ProjectLockState.fresh,
    vendorState: ProjectVendorState.present,
    hostedWorkspace: HostedWorkspaceRecordSnapshot(
      workspaceId: 'hosted-route-gate',
      schemaVersion: '1',
      ownerRef: 'Vityo',
      status: HostedWorkspaceStatus.active,
      entryUrl: 'https://hosted.test/workspaces/hosted-route-gate',
      createdAt: DateTime.utc(2026, 5, 19),
      lastActiveAt: DateTime.utc(2026, 5, 19, 1),
      retentionDays: 7,
      exportState: HostedWorkspaceExportState.notRequested,
    ),
    notes: const <String>[],
  );
}

List<AdapterCapabilitySnapshot> _capabilities({
  AdapterCapabilityLevel cliExecution = AdapterCapabilityLevel.unavailable,
  AdapterCapabilityLevel cloudExecution = AdapterCapabilityLevel.unavailable,
}) {
  return <AdapterCapabilitySnapshot>[
    AdapterCapabilitySnapshot(
      adapterKind: AdapterKind.cli,
      languageService: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.partial,
        detail: 'cli language',
      ),
      projectGraph: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.partial,
        detail: 'cli project graph',
      ),
      execution: AdapterEndpointCapability(
        level: cliExecution,
        detail: 'cli execution',
      ),
      runtimeEvents: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail: 'cli runtime events',
      ),
    ),
    AdapterCapabilitySnapshot(
      adapterKind: AdapterKind.cloud,
      languageService: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.partial,
        detail: 'cloud language',
      ),
      projectGraph: AdapterEndpointCapability(
        level: cloudExecution,
        detail: 'cloud project graph',
      ),
      execution: AdapterEndpointCapability(
        level: cloudExecution,
        detail: 'cloud execution',
      ),
      runtimeEvents: AdapterEndpointCapability(
        level: cloudExecution,
        detail: 'cloud runtime events',
      ),
    ),
  ];
}
