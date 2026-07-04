import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/app/commands/app_commands.dart';
import 'package:vityo_app/src/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/backend_toolchain/execution_route_summary.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/platform/viewport_profile.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/toolchain_management_adapter.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/editor/transactions/transactions.dart';
import 'package:vityo_app/src/view_ide/interaction/toolchain_status_surface.dart';
import 'package:vityo_app/src/view_ide/language/language_contract.dart';
import 'package:vityo_app/src/view_render/native_tool_result_summary.dart';
import 'package:vityo_app/src/view_render/runtime/runtime_surface.dart';

void main() {
  group('1) Android/iOS viewport family mobile interaction matrix', () {
    test(
      'Android phone viewport resolves to mobile with correct dimensions',
      () {
        final profile = resolveViewportProfile(
          platformTarget: PlatformTarget.android,
          width: 412,
          height: 915,
        );

        expect(profile.isMobile, isTrue);
        expect(profile.isDesktop, isFalse);
        expect(profile.family, ViewportFamily.mobile);
        expect(profile.width, 412);
        expect(profile.height, 915);
        expect(profile.platformTarget, PlatformTarget.android);
        expect(profile.label, 'Mobile');
      },
    );

    test('iOS phone viewport resolves to mobile with correct dimensions', () {
      final profile = resolveViewportProfile(
        platformTarget: PlatformTarget.ios,
        width: 390,
        height: 844,
      );

      expect(profile.isMobile, isTrue);
      expect(profile.isDesktop, isFalse);
      expect(profile.family, ViewportFamily.mobile);
      expect(profile.width, 390);
      expect(profile.height, 844);
      expect(profile.platformTarget, PlatformTarget.ios);
      expect(profile.label, 'Mobile');
    });

    test('Android tablet viewport resolves to mobile despite large width', () {
      final profile = resolveViewportProfile(
        platformTarget: PlatformTarget.android,
        width: 1280,
        height: 800,
      );

      expect(profile.isMobile, isTrue);
      expect(profile.family, ViewportFamily.mobile);
      expect(profile.width, 1280);
      expect(profile.platformTarget, PlatformTarget.android);
    });

    test('iOS iPad viewport resolves to mobile despite large width', () {
      final profile = resolveViewportProfile(
        platformTarget: PlatformTarget.ios,
        width: 1024,
        height: 1366,
      );

      expect(profile.isMobile, isTrue);
      expect(profile.family, ViewportFamily.mobile);
      expect(profile.width, 1024);
      expect(profile.platformTarget, PlatformTarget.ios);
    });

    test('Android small-screen viewport stays mobile', () {
      final profile = resolveViewportProfile(
        platformTarget: PlatformTarget.android,
        width: 320,
        height: 480,
      );

      expect(profile.isMobile, isTrue);
      expect(profile.width, 320);
      expect(profile.height, 480);
    });

    test('iOS SE viewport stays mobile', () {
      final profile = resolveViewportProfile(
        platformTarget: PlatformTarget.ios,
        width: 375,
        height: 667,
      );

      expect(profile.isMobile, isTrue);
      expect(profile.width, 375);
      expect(profile.height, 667);
    });

    test('desktop platforms are never mobile regardless of dimensions', () {
      for (final target in [
        PlatformTarget.windows,
        PlatformTarget.macos,
        PlatformTarget.linux,
      ]) {
        final profile = resolveViewportProfile(
          platformTarget: target,
          width: 360,
          height: 640,
        );

        expect(profile.isDesktop, isTrue, reason: '$target should be desktop');
        expect(
          profile.isMobile,
          isFalse,
          reason: '$target should not be mobile',
        );
        expect(
          profile.family,
          ViewportFamily.desktop,
          reason: '$target family mismatch',
        );
      }
    });

    test('Web mobile-width viewport resolves to mobile', () {
      final profile = resolveViewportProfile(
        platformTarget: PlatformTarget.web,
        width: 430,
        height: 932,
      );

      expect(profile.isMobile, isTrue);
      expect(profile.platformTarget, PlatformTarget.web);
    });

    test('Web desktop-width viewport resolves to desktop', () {
      final profile = resolveViewportProfile(
        platformTarget: PlatformTarget.web,
        width: 1440,
        height: 900,
      );

      expect(profile.isDesktop, isTrue);
      expect(profile.platformTarget, PlatformTarget.web);
    });

    test('Unknown target resolves by width threshold', () {
      final mobileUnknown = resolveViewportProfile(
        platformTarget: PlatformTarget.unknown,
        width: 480,
        height: 800,
      );
      final desktopUnknown = resolveViewportProfile(
        platformTarget: PlatformTarget.unknown,
        width: 1280,
        height: 720,
      );

      expect(mobileUnknown.isMobile, isTrue);
      expect(desktopUnknown.isDesktop, isTrue);
    });

    test('mobile viewport profile product gate labels are consistent', () {
      const androidProfile = ViewportProfile(
        family: ViewportFamily.mobile,
        width: 412,
        height: 915,
        platformTarget: PlatformTarget.android,
      );
      const iosProfile = ViewportProfile(
        family: ViewportFamily.mobile,
        width: 390,
        height: 844,
        platformTarget: PlatformTarget.ios,
      );

      expect(androidProfile.label, 'Mobile');
      expect(androidProfile.isMobile, isTrue);
      expect(androidProfile.platformTarget, PlatformTarget.android);

      expect(iosProfile.label, 'Mobile');
      expect(iosProfile.isMobile, isTrue);
      expect(iosProfile.platformTarget, PlatformTarget.ios);
    });
  });

  group('2) Mobile editor input behavior matrix', () {
    for (final target in <PlatformTarget>[
      PlatformTarget.android,
      PlatformTarget.ios,
    ]) {
      test(
        '$target user input edit applies through the editor transaction',
        () {
          final profile = resolveViewportProfile(
            platformTarget: target,
            width: target == PlatformTarget.android ? 412 : 390,
            height: target == PlatformTarget.android ? 915 : 844,
          );
          const document = DocumentState(
            documentId: 'mobile/main.styio',
            text: 'print("hello desktop")',
            revision: 7,
          );
          final edit = WorkspaceEdit.singleDocument(
            document: document,
            source: WorkspaceEditSource.userInput,
            edits: const <WorkspaceTextEdit>[
              WorkspaceTextEdit(
                documentId: 'mobile/main.styio',
                range: SourceRange(start: 13, end: 20),
                newText: 'mobile',
              ),
            ],
          );

          const service = EditorTransactionService();
          final validation = service.validateForDocument(
            document: document,
            edit: edit,
          );
          final result = service.applyToDocument(
            document: document,
            edit: edit,
          );

          expect(profile.isMobile, isTrue);
          expect(edit.source, WorkspaceEditSource.userInput);
          expect(validation.isValid, isTrue);
          expect(result.isApplied, isTrue);
          expect(result.document.revision, 8);
          expect(result.document.text, 'print("hello mobile")');
        },
      );
    }
  });

  group('3) Command availability and runtime route messaging matrix', () {
    test('StyioCommandRegistry registers surface commands for mobile', () {
      final surfaceCommands = StyioCommandRegistry.surfaceCommands.toList(
        growable: false,
      );

      expect(surfaceCommands, isNotEmpty);
      expect(
        surfaceCommands.any((cmd) => cmd.id == AppCommandId.showRuntime),
        isTrue,
      );
      expect(
        surfaceCommands.any((cmd) => cmd.id == AppCommandId.showAgent),
        isTrue,
      );
      expect(
        surfaceCommands.any((cmd) => cmd.id == AppCommandId.showDebug),
        isTrue,
      );
    });

    test('primary commands include navigation and search ops for mobile', () {
      final primaryIds = StyioCommandRegistry.primaryCommands
          .map((c) => c.id)
          .toSet();

      expect(primaryIds, contains(AppCommandId.save));
      expect(primaryIds, contains(AppCommandId.run));
      expect(primaryIds, contains(AppCommandId.commandPalette));
      expect(primaryIds, contains(AppCommandId.quickOpen));
      expect(primaryIds, contains(AppCommandId.searchWorkspace));
      expect(primaryIds, contains(AppCommandId.showWorkspaceProblems));
      expect(primaryIds, contains(AppCommandId.fetchDependencies));
    });

    test('mobile-friendly workflow commands exclude debug-only commands', () {
      final workflowIds = StyioCommandRegistry.workflowCommands
          .map((c) => c.id)
          .toSet();

      expect(workflowIds, contains(AppCommandId.run));
      expect(workflowIds, contains(AppCommandId.commandPalette));
      expect(workflowIds, contains(AppCommandId.quickOpen));
      expect(workflowIds, contains(AppCommandId.searchWorkspace));
      expect(workflowIds, isNot(contains(AppCommandId.startDebugging)));
      expect(workflowIds, isNot(contains(AppCommandId.stopDebugging)));
      expect(workflowIds, isNot(contains(AppCommandId.stepOver)));
    });

    test('deployment commands are accessible for mobile publish flows', () {
      final deployIds = StyioCommandRegistry.deploymentCommands
          .map((c) => c.id)
          .toList(growable: false);

      expect(deployIds, contains(AppCommandId.packProject));
      expect(deployIds, contains(AppCommandId.preparePublish));
    });

    test(
      'Android hosted route selection yields hosted kind with allowed true',
      () {
        final selection = selectBackendExecutionRoute(
          platformTarget: PlatformTarget.android,
          projectGraph: _hostedProject(),
          adapterCapabilities: _mockedCapabilities(
            cloudExecution: AdapterCapabilityLevel.available,
          ),
        );

        expect(selection.routeKind, BackendExecutionRouteKind.hosted);
        expect(selection.allowed, isTrue);
        expect(selection.blockedReason, isNull);
        expect(selection.adapterKind, AdapterKind.cloud);
      },
    );

    test('iOS hosted route is allowed through cloud adapter', () {
      final selection = selectBackendExecutionRoute(
        platformTarget: PlatformTarget.ios,
        projectGraph: _hostedProject(),
        adapterCapabilities: _mockedCapabilities(
          cloudExecution: AdapterCapabilityLevel.available,
        ),
      );

      expect(selection.routeKind, BackendExecutionRouteKind.hosted);
      expect(selection.allowed, isTrue);
      expect(selection.blockedReason, isNull);
      expect(selection.adapterKind, AdapterKind.cloud);
    });

    test('Android non-hosted project with partial CLI shows blocked route', () {
      final selection = selectBackendExecutionRoute(
        platformTarget: PlatformTarget.android,
        projectGraph: _scratchProjectWithoutCompiler(),
        adapterCapabilities: _mockedCapabilities(
          cliExecution: AdapterCapabilityLevel.partial,
        ),
      );

      expect(selection.routeKind, BackendExecutionRouteKind.blocked);
      expect(selection.allowed, isFalse);
      expect(selection.blockedReason, isNotNull);
    });

    test('iOS non-hosted project is blocked without cloud execution', () {
      final selection = selectBackendExecutionRoute(
        platformTarget: PlatformTarget.ios,
        projectGraph: _scratchProject(),
        adapterCapabilities: _mockedCapabilities(
          cloudExecution: AdapterCapabilityLevel.partial,
        ),
      );

      expect(selection.routeKind, BackendExecutionRouteKind.blocked);
      expect(selection.allowed, isFalse);
      expect(selection.previewOnly, isTrue);
      expect(selection.blockedReason, isNotNull);
    });

    test(
      'Android with cloud partial and CLI partial routes localCli preview',
      () {
        final selection = selectBackendExecutionRoute(
          platformTarget: PlatformTarget.android,
          projectGraph: _scratchProject(),
          adapterCapabilities: _mockedCapabilities(
            cliExecution: AdapterCapabilityLevel.partial,
            cloudExecution: AdapterCapabilityLevel.partial,
          ),
        );

        expect(selection.routeKind, BackendExecutionRouteKind.localCli);
        expect(selection.previewOnly, isFalse);
        expect(selection.allowed, isTrue);
        expect(selection.blockedReason, isNull);
      },
    );

    test('iOS JIT route is blocked due to iOS policy', () {
      final jitRoute = summarizeJitRoute(
        platformTarget: PlatformTarget.ios,
        projectGraph: _hostedProject(),
        adapterCapabilities: _mockedCapabilities(
          cloudExecution: AdapterCapabilityLevel.available,
        ),
      );

      expect(jitRoute.blocked, isTrue);
      expect(jitRoute.title, contains('JIT disabled by iOS policy'));
      expect(jitRoute.primaryAdapterKind, AdapterKind.cloud);
    });

    test('Android JIT route blocked until compiler contract', () {
      final jitRoute = summarizeJitRoute(
        platformTarget: PlatformTarget.android,
        projectGraph: _scratchProject(),
        adapterCapabilities: _mockedCapabilities(
          cliExecution: AdapterCapabilityLevel.partial,
        ),
      );

      expect(jitRoute.blocked, isTrue);
      expect(jitRoute.title, contains('Android JIT route pending'));
    });

    test('hosted project JIT route blocked with hosted route messaging', () {
      final jitRoute = summarizeJitRoute(
        platformTarget: PlatformTarget.android,
        projectGraph: _hostedProject(),
        adapterCapabilities: _mockedCapabilities(
          cloudExecution: AdapterCapabilityLevel.available,
        ),
      );

      expect(jitRoute.blocked, isTrue);
      expect(jitRoute.title, contains('JIT unavailable on hosted route'));
      expect(jitRoute.primaryAdapterKind, AdapterKind.cloud);
    });

    test('evaluateExecutionRouteGate blocks for preview-only routes', () {
      final gate = evaluateExecutionRouteGate(
        platformTarget: PlatformTarget.android,
        projectGraph: _scratchProject(),
        adapterCapabilities: _mockedCapabilities(),
      );

      expect(gate.allowed, isFalse);
      expect(gate.blockedReason, isNotNull);
      expect(gate.blockedReason, contains('blocked'));
    });

    test(
      'nativeToolMetadataSummaryText reports blocked route for mobile target',
      () {
        final selection = selectBackendExecutionRoute(
          platformTarget: PlatformTarget.ios,
          projectGraph: _scratchProjectWithoutCompiler(),
          adapterCapabilities: _mockedCapabilities(),
        );

        final summary = nativeToolMetadataSummaryText(<String, Object?>{
          'backendRouteSelection': selection.toJson(),
        });

        expect(summary, isNotNull);
        expect(summary, contains('blocked'));
      },
    );
  });

  group('4) Recovery UI and blocked state matrix', () {
    test(
      'ToolchainStatusSurface for unavailable toolchain has recovery actions',
      () {
        final status = ToolchainStatusSurface.fromProjectToolchain(
          const ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.unavailable,
            detail: 'No toolchain resolved for this project.',
          ),
        );

        expect(status.severity, ToolchainStatusSeverity.unavailable);
        expect(status.actionable, isTrue);
        expect(status.recoveryActions, isNotEmpty);
        expect(status.title, isNotNull);
        expect(status.source, 'unavailable');
      },
    );

    test(
      'ToolchainStatusSurface for project-pin is ready and not actionable',
      () {
        final status = ToolchainStatusSurface.fromProjectToolchain(
          const ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.projectPin,
            detail: 'Toolchain resolved by project pin.',
          ),
        );

        expect(status.severity, ToolchainStatusSeverity.ready);
        expect(status.actionable, isFalse);
        expect(status.recoveryActions, isEmpty);
      },
    );

    test(
      'ToolchainStatusSurface from failed lastCommand surfaces recovery actions',
      () {
        final status = ToolchainStatusSurface.fromProjectToolchain(
          const ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.managedCurrent,
            detail: 'Managed toolchain resolved.',
          ),
          lastCommand: const ToolchainCommandResult(
            command: 'styio build',
            status: ToolchainCommandStatus.failed,
            statusMessage: 'Build failed: compiler not found',
            stdout: '',
            stderr: 'compiler not found',
          ),
        );

        expect(status.severity, ToolchainStatusSeverity.failed);
        expect(status.actionable, isTrue);
        expect(status.lastCommand, 'styio build');
        expect(status.lastCommandStatus, 'failed');
        expect(status.lastCommandMessage, 'Build failed: compiler not found');
      },
    );

    test('blocked BackendExecutionRouteSelection carries blockedReason', () {
      final selection = selectBackendExecutionRoute(
        platformTarget: PlatformTarget.android,
        projectGraph: _scratchProjectWithoutCompiler(),
        adapterCapabilities: _mockedCapabilities(),
      );

      expect(selection.routeKind, BackendExecutionRouteKind.blocked);
      expect(selection.allowed, isFalse);
      expect(selection.blockedReason, isNotNull);
      expect(selection.blockedReason, contains('blocked'));
    });

    test(
      'Android blocked JIT route translated into recovery surface message',
      () {
        final status = ToolchainStatusSurface.fromProjectToolchain(
          const ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.unavailable,
            detail:
                'Android stays local-first for JIT, but no local compiler has advertised a JIT contract yet.',
          ),
        );

        expect(status.severity, ToolchainStatusSeverity.unavailable);
        expect(status.actionable, isTrue);
        expect(status.message, contains('Android'));
        expect(status.message, contains('JIT'));
      },
    );

    testWidgets(
      'RuntimeSurface renders blocked state text for mobile viewport profile',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: RuntimeSurface(
              platformTarget: PlatformTarget.android,
              viewportProfile: const ViewportProfile(
                family: ViewportFamily.mobile,
                width: 412,
                height: 915,
                platformTarget: PlatformTarget.android,
              ),
              projectGraph: _scratchProjectWithoutCompiler(),
              toolchainStatus: ToolchainStatusSurface.fromProjectToolchain(
                const ToolchainStatusSnapshot(
                  source: ToolchainResolutionSource.unavailable,
                  detail: 'No toolchain resolved.',
                ),
              ),
              mountedModules: const [],
              adapterCapabilities: _mockedCapabilities(),
              executionSession: null,
              runtimeEvents: const [],
            ),
          ),
        );

        expect(find.textContaining('Execution Route'), findsOneWidget);
        expect(find.textContaining('blocked'), findsWidgets);
      },
    );

    test(
      'nativeToolMetadataSummaryText with blocked route includes blocked keyword',
      () {
        final selection = selectBackendExecutionRoute(
          platformTarget: PlatformTarget.android,
          projectGraph: _scratchProjectWithoutCompiler(),
          adapterCapabilities: _mockedCapabilities(),
        );

        final buildSummary = nativeToolMetadataSummaryText(<String, Object?>{
          'buildResult': <String, Object?>{
            'status': 'failed',
            'diagnosticCount': 2,
          },
          'backendRouteSelection': selection.toJson(),
        });

        expect(buildSummary, isNotNull);
        expect(buildSummary, contains('blocked'));
        expect(
          buildSummary,
          contains('route ${selection.routeKind.wireValue}'),
        );
      },
    );

    test(
      'ToolchainRecoveryAction toJson and construction round-trips correctly',
      () {
        const action = ToolchainRecoveryAction(
          id: 'install-styio',
          label: 'Install Styio Toolchain',
          description: 'Downloads and installs the styio compiler.',
        );

        final json = action.toJson();

        expect(json['id'], 'install-styio');
        expect(json['label'], 'Install Styio Toolchain');
        expect(
          json['description'],
          'Downloads and installs the styio compiler.',
        );
      },
    );

    test(
      'ToolchainStatusSurface.toJson serializes actionable state and recovery actions',
      () {
        final status = ToolchainStatusSurface.fromProjectToolchain(
          const ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.unavailable,
            detail: 'Toolchain missing.',
          ),
        );

        final json = status.toJson();

        expect(json['source'], 'unavailable');
        expect(json['severity'], 'unavailable');
        expect(json['actionable'], isTrue);
        expect(json['recoveryActions'], isA<List>());
        expect((json['recoveryActions'] as List), isNotEmpty);
      },
    );
  });
}

/// Constructs a hosted project graph snapshot for route testing.
ProjectGraphSnapshot _hostedProject() {
  return ProjectGraphSnapshot(
    id: 'mobile-hosted-matrix',
    title: 'Mobile Hosted Matrix',
    kind: ProjectKind.hosted,
    workspaceRoot: '/workspace/mobile-hosted',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/mobile-hosted/pafio.toml',
    dependencies: const <ProjectDependencySnapshot>[],
    packages: const <ProjectPackageSnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: const <String>['/workspace/mobile-hosted/src/main.styio'],
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'hosted pin',
    ),
    lockState: ProjectLockState.fresh,
    vendorState: ProjectVendorState.present,
    hostedWorkspace: HostedWorkspaceRecordSnapshot(
      workspaceId: 'mobile-hosted-matrix',
      schemaVersion: '1',
      ownerRef: 'Vityo',
      status: HostedWorkspaceStatus.active,
      entryUrl: 'https://hosted.test/workspaces/mobile-hosted-matrix',
      createdAt: DateTime.utc(2026, 5, 19),
      lastActiveAt: DateTime.utc(2026, 5, 19, 1),
      retentionDays: 7,
      exportState: HostedWorkspaceExportState.notRequested,
    ),
    notes: const <String>[],
  );
}

/// Constructs a scratch project graph with a basic compiler handshake.
ProjectGraphSnapshot _scratchProject() {
  return ProjectGraphSnapshot.scratch(
    workspaceRoot: '/workspace/mobile-scratch',
    activeFilePath: '/workspace/mobile-scratch/main.styio',
    title: 'Mobile Scratch',
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
  );
}

/// Constructs a scratch project without a compiler handshake (simulates blocked
/// state).
ProjectGraphSnapshot _scratchProjectWithoutCompiler() {
  return ProjectGraphSnapshot.scratch(
    workspaceRoot: '/workspace/mobile-blocked',
    activeFilePath: '/workspace/mobile-blocked/main.styio',
    title: 'Mobile Blocked',
    notes: const <String>[],
  );
}

/// Builds the mocked adapter capabilities list used across route tests.
List<AdapterCapabilitySnapshot> _mockedCapabilities({
  AdapterCapabilityLevel cliExecution = AdapterCapabilityLevel.unavailable,
  AdapterCapabilityLevel cloudExecution = AdapterCapabilityLevel.unavailable,
}) {
  return <AdapterCapabilitySnapshot>[
    AdapterCapabilitySnapshot(
      adapterKind: AdapterKind.cli,
      languageService: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.partial,
        detail: 'mobile cli language',
      ),
      projectGraph: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.partial,
        detail: 'mobile cli project graph',
      ),
      execution: AdapterEndpointCapability(
        level: cliExecution,
        detail: 'mobile cli execution',
      ),
      runtimeEvents: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.unavailable,
        detail: 'mobile cli runtime events',
      ),
    ),
    AdapterCapabilitySnapshot(
      adapterKind: AdapterKind.cloud,
      languageService: const AdapterEndpointCapability(
        level: AdapterCapabilityLevel.partial,
        detail: 'mobile cloud language',
      ),
      projectGraph: AdapterEndpointCapability(
        level: cloudExecution,
        detail: 'mobile cloud project graph',
      ),
      execution: AdapterEndpointCapability(
        level: cloudExecution,
        detail: 'mobile cloud execution',
      ),
      runtimeEvents: AdapterEndpointCapability(
        level: cloudExecution,
        detail: 'mobile cloud runtime events',
      ),
    ),
  ];
}
