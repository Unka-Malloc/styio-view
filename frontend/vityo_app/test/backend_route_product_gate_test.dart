import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/backend_toolchain/execution_route_summary.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/interaction/toolchain_status_surface.dart';
import 'package:vityo_app/src/view_ide/module_host/android_runtime_package_budget.dart';
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

  group('2) Android local-first route scenarios', () {
    test(
      'Android with CLI execution available resolves to localCli local-first',
      () {
        const androidCliAvailable = AdapterCapabilityLevel.partial;
        final selection = selectBackendExecutionRoute(
          platformTarget: PlatformTarget.android,
          projectGraph: ProjectGraphSnapshot.scratch(
            workspaceRoot: '/workspace/android-local',
            activeFilePath: '/workspace/android-local/main.styio',
            title: 'Android Local',
            activeCompiler: const CompilerHandshakeSnapshot(
              binaryPath: '/toolchains/styio/bin/styio',
              tool: 'styio',
              compilerVersion: '0.1.0',
              channel: 'stable',
              variant: 'mobile',
              capabilities: <String>['machine_info_json', 'single_file_entry'],
              supportedContractVersions: <String, List<int>>{
                'machine_info': <int>[1],
              },
              integrationPhase: 'single-file-live',
            ),
            notes: const <String>[],
          ),
          adapterCapabilities: _androidCapabilities(
            cliExecution: androidCliAvailable,
          ),
        );

        expect(selection.routeKind, BackendExecutionRouteKind.localCli);
        expect(selection.allowed, isTrue);
        expect(selection.title, contains('Android local-first'));
        expect(selection.detail, contains('resolved compiler'));
      },
    );

    test('Android without CLI but with cloud fallback resolves to hosted', () {
      const cloudAvailable = AdapterCapabilityLevel.available;
      final selection = selectBackendExecutionRoute(
        platformTarget: PlatformTarget.android,
        projectGraph: ProjectGraphSnapshot.scratch(
          workspaceRoot: '/workspace/android-cloud-fallback',
          activeFilePath: '/workspace/android-cloud-fallback/main.styio',
          title: 'Android Cloud Fallback',
          notes: const <String>[],
        ),
        adapterCapabilities: _androidCapabilities(
          cloudExecution: cloudAvailable,
        ),
      );

      expect(selection.routeKind, BackendExecutionRouteKind.hosted);
      expect(selection.allowed, isTrue);
      expect(selection.title, contains('cloud fallback'));
      expect(selection.detail, contains('fallback route'));
    });

    test('Android without CLI or cloud is blocked with explicit reason', () {
      final selection = selectBackendExecutionRoute(
        platformTarget: PlatformTarget.android,
        projectGraph: ProjectGraphSnapshot.scratch(
          workspaceRoot: '/workspace/android-blocked',
          activeFilePath: '/workspace/android-blocked/main.styio',
          title: 'Android Blocked',
          notes: const <String>[],
        ),
        adapterCapabilities: _androidCapabilities(),
      );

      expect(selection.routeKind, BackendExecutionRouteKind.blocked);
      expect(selection.allowed, isFalse);
      expect(selection.blockedReason, isNotNull);
      expect(selection.blockedReason, contains('Android local-first'));
      expect(selection.blockedReason, contains('blocked'));
    });

    test(
      'Android runtime package budget and capability route are validated together',
      () {
        const gate = AndroidRuntimeCapabilityRouteJointGate();

        // Scenario A: package within budget + local route available
        final budgetPass = const AndroidRuntimePackageBudgetGate().evaluate(
          const AndroidRuntimePackageArtifact(
            artifactId: 'android-arm64-release',
            sizeBytes: 30 * 1024 * 1024,
            moduleIds: <String>['styio_runtime', 'vityo_shell'],
          ),
        );
        expect(
          gate.evaluate(
            budgetResult: budgetPass,
            hasLocalExecutionRoute: true,
            hasCloudFallbackRoute: false,
          ),
          AndroidRuntimeCapabilityRouteStatus.packageReadyRouteLive,
        );

        // Scenario B: package within budget + no local route = route blocked
        expect(
          gate.evaluate(
            budgetResult: budgetPass,
            hasLocalExecutionRoute: false,
            hasCloudFallbackRoute: false,
          ),
          AndroidRuntimeCapabilityRouteStatus.packageReadyRouteBlocked,
        );

        // Scenario C: package within budget + no local + cloud fallback
        expect(
          gate.evaluate(
            budgetResult: budgetPass,
            hasLocalExecutionRoute: false,
            hasCloudFallbackRoute: true,
          ),
          AndroidRuntimeCapabilityRouteStatus.packageReadyRouteBlocked,
        );

        // Scenario D: package over budget with cloud fallback
        final budgetFail = const AndroidRuntimePackageBudgetGate().evaluate(
          const AndroidRuntimePackageArtifact(
            artifactId: 'android-arm64-release',
            sizeBytes: 60 * 1024 * 1024,
          ),
        );
        expect(
          gate.evaluate(
            budgetResult: budgetFail,
            hasLocalExecutionRoute: false,
            hasCloudFallbackRoute: true,
          ),
          AndroidRuntimeCapabilityRouteStatus.packageOverBudgetWithFallback,
        );

        // Scenario E: package over budget without cloud fallback
        expect(
          gate.evaluate(
            budgetResult: budgetFail,
            hasLocalExecutionRoute: false,
            hasCloudFallbackRoute: false,
          ),
          AndroidRuntimeCapabilityRouteStatus.packageOverBudget,
        );

        // Scenario F: invalid artifact
        final budgetInvalid = const AndroidRuntimePackageBudgetGate().evaluate(
          const AndroidRuntimePackageArtifact(artifactId: '', sizeBytes: 100),
        );
        expect(
          gate.evaluate(
            budgetResult: budgetInvalid,
            hasLocalExecutionRoute: false,
            hasCloudFallbackRoute: false,
          ),
          AndroidRuntimeCapabilityRouteStatus.invalidInput,
        );
      },
    );
  });
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
    manifestPath: '/workspace/hosted-route-gate/pafio.toml',
    dependencies: const <ProjectDependencySnapshot>[],
    packages: const <ProjectPackageSnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: const <String>['/workspace/hosted-route-gate/src/main.styio'],
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

List<AdapterCapabilitySnapshot> _androidCapabilities({
  AdapterCapabilityLevel cliExecution = AdapterCapabilityLevel.unavailable,
  AdapterCapabilityLevel cloudExecution = AdapterCapabilityLevel.unavailable,
}) {
  return <AdapterCapabilitySnapshot>[
    AdapterCapabilitySnapshot(
      adapterKind: AdapterKind.cli,
      languageService: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.partial,
        detail: 'android cli language',
      ),
      projectGraph: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.partial,
        detail: 'android cli project graph',
      ),
      execution: AdapterEndpointCapability(
        level: cliExecution,
        detail: 'android cli execution',
      ),
      runtimeEvents: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail: 'android cli runtime events',
      ),
    ),
    AdapterCapabilitySnapshot(
      adapterKind: AdapterKind.cloud,
      languageService: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.partial,
        detail: 'android cloud language',
      ),
      projectGraph: AdapterEndpointCapability(
        level: cloudExecution,
        detail: 'android cloud project graph',
      ),
      execution: AdapterEndpointCapability(
        level: cloudExecution,
        detail: 'android cloud execution',
      ),
      runtimeEvents: AdapterEndpointCapability(
        level: cloudExecution,
        detail: 'android cloud runtime events',
      ),
    ),
  ];
}
