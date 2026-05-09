import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:styio_view_app/src/frontend_shell/frontend_shell.dart';
import 'package:styio_view_app/src/editor/editor_controller.dart';
import 'package:styio_view_app/src/editor/document_state.dart';
import 'package:styio_view_app/src/backend_toolchain/adapter_contracts.dart';
import 'package:styio_view_app/src/backend_toolchain/dependency_source_adapter.dart';
import 'package:styio_view_app/src/backend_toolchain/deployment_adapter.dart';
import 'package:styio_view_app/src/backend_toolchain/execution_adapter.dart';
import 'package:styio_view_app/src/backend_toolchain/project_graph_adapter.dart';
import 'package:styio_view_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:styio_view_app/src/backend_toolchain/runtime_event_adapter.dart';
import 'package:styio_view_app/src/backend_toolchain/toolchain_management_adapter.dart';
import 'package:styio_view_app/src/language/language_contract.dart';
import 'package:styio_view_app/src/language/simple_styio_language_service.dart';
import 'package:styio_view_app/src/module_host/module_registry.dart';
import 'package:styio_view_app/src/platform/native_module_loader.dart';
import 'package:styio_view_app/src/platform/platform_target.dart';

void main() {
  Future<void> revealMobileLanguagePane(WidgetTester tester) async {
    final mobileInspectorScroll = find.byKey(
      const ValueKey('editor-language-layout-scroll-mobile'),
      skipOffstage: false,
    );
    if (mobileInspectorScroll.evaluate().isNotEmpty) {
      for (var attempt = 0; attempt < 2; attempt += 1) {
        await tester.drag(mobileInspectorScroll, const Offset(0, -260));
        await tester.pumpAndSettle();
      }
    }
  }

  List<Color?> backgroundsForTextOnLine(
    WidgetTester tester, {
    required int lineIndex,
    required String text,
  }) {
    final colors = <Color?>[];

    void visit(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text == text) {
          colors.add(span.style?.backgroundColor);
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child);
        }
      }
    }

    final richTexts = tester.widgetList<RichText>(
      find.descendant(
        of: find.byKey(ValueKey('source-line-$lineIndex')),
        matching: find.byType(RichText),
      ),
    );
    for (final richText in richTexts) {
      visit(richText.text);
    }
    return colors;
  }

  ProjectGraphSnapshot createProjectSnapshot(PlatformTarget target) {
    final root = target == PlatformTarget.ios
        ? '/workspace/cloud-preview'
        : '/workspace/demo';
    final title = target == PlatformTarget.ios
        ? 'Cloud Preview Project'
        : 'Demo Project';
    const packageName = 'demo/app';
    final targets = <ProjectTargetDescriptor>[
      ProjectTargetDescriptor(
        id: '$packageName:bin:demo',
        packageName: packageName,
        kind: ProjectTargetKind.bin,
        name: 'demo',
        filePath: '$root/src/main.styio',
      ),
      ProjectTargetDescriptor(
        id: '$packageName:test:render-flow',
        packageName: packageName,
        kind: ProjectTargetKind.test,
        name: 'render-flow',
        filePath: '$root/src/render_flow.styio',
      ),
    ];

    return ProjectGraphSnapshot(
      id: '$root/spio.toml',
      title: title,
      kind: ProjectKind.combinedRoot,
      workspaceRoot: root,
      workspaceMembers: const <String>['packages/render-kit'],
      manifestPath: '$root/spio.toml',
      lockfilePath: '$root/spio.lock',
      toolchainPinPath: '$root/spio-toolchain.toml',
      styioConfigPath: '$root/styio.toml',
      vendorRoot: '$root/.spio/vendor',
      buildRoot: '$root/.spio/build',
      packages: <ProjectPackageSnapshot>[
        ProjectPackageSnapshot(
          packageName: packageName,
          version: '0.0.1',
          rootPath: root,
          manifestPath: '$root/spio.toml',
          dependencies: const <ProjectDependencySnapshot>[
            ProjectDependencySnapshot(
              sourcePackageName: 'demo/app',
              dependencyName: 'render/kit',
              kind: ProjectDependencyKind.runtime,
              requirement: 'workspace',
              isWorkspaceReference: true,
            ),
            ProjectDependencySnapshot(
              sourcePackageName: 'demo/app',
              dependencyName: 'assertions',
              kind: ProjectDependencyKind.dev,
              requirement: '^1.0.0',
            ),
          ],
          targets: targets,
        ),
      ],
      dependencies: const <ProjectDependencySnapshot>[
        ProjectDependencySnapshot(
          sourcePackageName: 'demo/app',
          dependencyName: 'render/kit',
          kind: ProjectDependencyKind.runtime,
          requirement: 'workspace',
          isWorkspaceReference: true,
        ),
        ProjectDependencySnapshot(
          sourcePackageName: 'demo/app',
          dependencyName: 'assertions',
          kind: ProjectDependencyKind.dev,
          requirement: '^1.0.0',
        ),
      ],
      targets: targets,
      editorFiles: <String>[
        '$root/src/main.styio',
        '$root/src/render_flow.styio',
        '$root/src/runtime_graph.styio',
      ],
      toolchain: const ToolchainStatusSnapshot(
        source: ToolchainResolutionSource.projectPin,
        detail: 'Project toolchain pin discovered for the smoke test fixture.',
        pinPath: '/workspace/demo/spio-toolchain.toml',
        channel: 'stable',
        version: '0.0.1',
      ),
      lockState: ProjectLockState.unknown,
      vendorState: ProjectVendorState.present,
      activeCompiler: const CompilerHandshakeSnapshot(
        binaryPath: '/toolchains/styio/bin/styio',
        tool: 'styio',
        compilerVersion: '0.0.1',
        channel: 'stable',
        variant: 'smoke-fixture',
        capabilities: <String>[
          'machine_info_json',
          'single_file_entry',
          'jsonl_diagnostics',
        ],
        supportedContractVersions: <String, List<int>>{
          'machine_info': <int>[1],
          'jsonl_diagnostics': <int>[1],
        },
        integrationPhase: 'bootstrap-single-file',
      ),
      notes: const <String>[
        'Smoke test fixture mirrors a canonical spio project.',
      ],
    );
  }

  Future<AppBootstrap> createBootstrap(PlatformTarget target) async {
    final projectSnapshot = createProjectSnapshot(target);
    final workspaceController = WorkspaceController(
      projectSnapshot: projectSnapshot,
    );
    final projectGraphAdapter = _FakeProjectGraphAdapter(projectSnapshot);
    return AppBootstrap(
      platformTarget: target,
      moduleRegistry: ModuleRegistry(
        platformTarget: target,
        definitions: const [],
      ),
      nativeModuleLoader: NoopNativeModuleLoader(platformTarget: target),
      projectGraphAdapter: projectGraphAdapter,
      supplementalAdapterCapabilities: normalizeCapabilitySnapshots([
        buildFfiAdapterCapability(
          visible: target != PlatformTarget.ios && target != PlatformTarget.web,
          executionSlotVisible:
              target != PlatformTarget.ios && target != PlatformTarget.web,
          detail: 'Smoke test FFI slot stays deferred.',
        ),
        buildCloudAdapterCapability(
          supportsCloudExecution:
              target == PlatformTarget.ios || target == PlatformTarget.android,
          supportsHostedProjectGraph:
              target == PlatformTarget.ios || target == PlatformTarget.web,
          detail: 'Smoke test cloud route remains illustrative.',
        ),
      ]),
      workspaceController: workspaceController,
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
      editorController: EditorSessionController(
        initialDocument: EditorSessionController.seedDocumentForPath(
          workspaceController.activeFilePath,
        ),
        languageService: const SimpleStyioLanguageService(),
      ),
      executionAdapter: const _FakeExecutionAdapter(),
      executionAdapterFactory: (ProjectGraphSnapshot _) async =>
          const _FakeExecutionAdapter(),
      runtimeEventAdapter: createRuntimeEventAdapter(platformTarget: target),
      dependencySourceAdapter: const _FakeDependencySourceAdapter(),
      deploymentAdapter: const _FakeDeploymentAdapter(),
      toolchainManagementAdapter: const _FakeToolchainManagementAdapter(),
    );
  }

  Future<AppBootstrap> createLiveWorkflowBootstrap(
    PlatformTarget target,
  ) async {
    final projectSnapshot = createProjectSnapshot(target).copyWith(
      activeCompiler: const CompilerHandshakeSnapshot(
        binaryPath: '/toolchains/styio/bin/styio',
        tool: 'styio',
        compilerVersion: '0.0.5',
        channel: 'stable',
        variant: 'live-mainline-fixture',
        capabilities: <String>[
          'machine_info_json',
          'single_file_entry',
          'jsonl_diagnostics',
          'runtime_event_stream',
        ],
        supportedContractVersions: <String, List<int>>{
          'machine_info': <int>[1],
          'compile_plan': <int>[1],
          'runtime_events': <int>[1],
        },
        integrationPhase: 'compile-plan-live',
        supportedAdapterModes: <String>['single-file', 'project'],
        featureFlags: <String, bool>{
          'compile_plan_consumer': true,
          'runtime_event_payload': true,
        },
      ),
      toolchainEnvironment: const ToolchainEnvironmentSnapshot(
        schemaVersion: 1,
        toolchain: ToolchainStatusSnapshot(
          source: ToolchainResolutionSource.projectPin,
          detail: 'Live workflow fixture resolves a pinned managed compiler.',
          pinPath: '/workspace/demo/spio-toolchain.toml',
          channel: 'stable',
          version: '0.0.5',
        ),
        activeCompiler: CompilerHandshakeSnapshot(
          binaryPath: '/toolchains/styio/bin/styio',
          tool: 'styio',
          compilerVersion: '0.0.5',
          channel: 'stable',
          variant: 'live-mainline-fixture',
          capabilities: <String>[
            'machine_info_json',
            'single_file_entry',
            'jsonl_diagnostics',
            'runtime_event_stream',
          ],
          supportedContractVersions: <String, List<int>>{
            'machine_info': <int>[1],
            'compile_plan': <int>[1],
            'runtime_events': <int>[1],
          },
          integrationPhase: 'compile-plan-live',
          supportedAdapterModes: <String>['single-file', 'project'],
          featureFlags: <String, bool>{
            'compile_plan_consumer': true,
            'runtime_event_payload': true,
          },
        ),
        currentCompiler: CompilerHandshakeSnapshot(
          binaryPath: '/toolchains/styio/bin/styio',
          tool: 'styio',
          compilerVersion: '0.0.5',
          channel: 'stable',
          variant: 'live-mainline-fixture',
          capabilities: <String>[
            'machine_info_json',
            'single_file_entry',
            'jsonl_diagnostics',
            'runtime_event_stream',
          ],
          supportedContractVersions: <String, List<int>>{
            'machine_info': <int>[1],
            'compile_plan': <int>[1],
            'runtime_events': <int>[1],
          },
          integrationPhase: 'compile-plan-live',
          supportedAdapterModes: <String>['single-file', 'project'],
          featureFlags: <String, bool>{
            'compile_plan_consumer': true,
            'runtime_event_payload': true,
          },
        ),
        managedToolchains: ManagedToolchainStateSnapshot(
          spioHome: '/workspace/demo/.spio',
          currentBinaryPath: '/workspace/demo/.spio/bin/styio',
          currentMetadataPath: '/workspace/demo/.spio/current.json',
          installed: <ManagedToolchainInstallSnapshot>[
            ManagedToolchainInstallSnapshot(
              channel: 'stable',
              compilerVersion: '0.0.5',
              installRoot: '/workspace/demo/.spio/toolchains/stable-0.0.5',
              installBinaryPath:
                  '/workspace/demo/.spio/toolchains/stable-0.0.5/bin/styio',
              installMetadataPath:
                  '/workspace/demo/.spio/toolchains/stable-0.0.5/install.json',
            ),
          ],
        ),
        notes: <String>[
          'Live workflow fixture exposes managed toolchain state.',
        ],
      ),
      packageDistribution: const PackageDistributionSnapshot(
        schemaVersion: 1,
        publishablePackages: 1,
        blockedPackages: 0,
        packages: <PackageDistributionPackageSnapshot>[
          PackageDistributionPackageSnapshot(
            packageName: 'demo/app',
            manifestPath: '/workspace/demo/spio.toml',
            publishEnabled: true,
            publishReady: true,
            runtimeRegistryDependencies: 1,
          ),
        ],
        registrySources: <RegistrySourceSnapshot>[
          RegistrySourceSnapshot(
            registryRoot: '/registry/local',
            transport: 'filesystem',
            dependencyRefs: 1,
            packages: <String>['assertions'],
          ),
        ],
      ),
      sourceState: const ProjectSourceStateSnapshot(
        schemaVersion: 1,
        spioHome: '/workspace/demo/.spio',
        declaredGitDependencies: 0,
        declaredRegistryDependencies: 1,
        vendor: VendorSourceStateSnapshot(
          vendorRoot: '/workspace/demo/.spio/vendor',
          metadataPath: '/workspace/demo/.spio/vendor/spio-vendor.json',
          vendorPresent: true,
          metadataPresent: true,
          gitSnapshots: 0,
        ),
      ),
      notes: const <String>[
        'Live workflow fixture mirrors a compile-plan-ready project route.',
      ],
    );
    final workspaceController = WorkspaceController(
      projectSnapshot: projectSnapshot,
    );
    recordRuntimeEventsForSession('live-workflow-run', <RuntimeEventEnvelope>[
      RuntimeEventEnvelope(
        schemaVersion: 1,
        sessionId: 'live-workflow-run',
        sequence: 1,
        timestamp: DateTime.utc(2026, 4, 18, 3, 0, 0),
        eventKind: 'compile.started',
        origin: 'styio.compile-plan',
        payload: const <String, Object?>{'intent': 'run'},
      ),
      RuntimeEventEnvelope(
        schemaVersion: 1,
        sessionId: 'live-workflow-run',
        sequence: 2,
        timestamp: DateTime.utc(2026, 4, 18, 3, 0, 1),
        eventKind: 'run.finished',
        origin: 'styio.runtime',
        payload: const <String, Object?>{'success': true},
      ),
    ]);
    addTearDown(() => clearRuntimeEventsForSession('live-workflow-run'));
    return AppBootstrap(
      platformTarget: target,
      moduleRegistry: ModuleRegistry(
        platformTarget: target,
        definitions: const [],
      ),
      nativeModuleLoader: NoopNativeModuleLoader(platformTarget: target),
      projectGraphAdapter: _FakeProjectGraphAdapter(projectSnapshot),
      supplementalAdapterCapabilities: normalizeCapabilitySnapshots([
        buildFfiAdapterCapability(
          visible: true,
          executionSlotVisible: true,
          detail: 'Live workflow fixture keeps desktop bridge available.',
        ),
        buildCloudAdapterCapability(
          supportsCloudExecution: false,
          supportsHostedProjectGraph: false,
          detail: 'Live workflow fixture stays on the desktop mainline path.',
        ),
      ]),
      workspaceController: workspaceController,
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
      editorController: EditorSessionController(
        initialDocument: EditorSessionController.seedDocumentForPath(
          workspaceController.activeFilePath,
        ),
        languageService: const SimpleStyioLanguageService(),
      ),
      executionAdapter: const _LiveExecutionAdapter(),
      executionAdapterFactory: (ProjectGraphSnapshot _) async =>
          const _LiveExecutionAdapter(),
      runtimeEventAdapter: createRuntimeEventAdapter(platformTarget: target),
      dependencySourceAdapter: const _LiveDependencySourceAdapter(),
      deploymentAdapter: const _LiveDeploymentAdapter(),
      toolchainManagementAdapter: const _LiveToolchainManagementAdapter(),
    );
  }

  testWidgets('builds shared shell scaffold in desktop viewport family', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));

    expect(
      find.byKey(const ValueKey('shell-viewport-desktop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-viewport-desktop')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('language-pane-desktop')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-language-family-desktop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('runtime-surface-desktop')),
      findsOneWidget,
    );
    expect(find.text('Styio View Integration Shell'), findsOneWidget);
    expect(find.text('Project Graph'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('project-operations-card')),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('workspace-sidebar-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Project Workflow'), findsOneWidget);
    expect(find.text('Execution'), findsOneWidget);
    expect(find.text('Dependencies'), findsOneWidget);
    expect(find.text('Environment'), findsOneWidget);
    expect(find.text('Deployment'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('project-operation-useActiveCompiler')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('project-operation-fetchDependencies')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('project-operation-preparePublish')),
      findsOneWidget,
    );
    final workspaceSidebarScrollable = find.descendant(
      of: find.byKey(const ValueKey('workspace-sidebar-scroll')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('project-operation-useActiveCompiler')),
      120,
      scrollable: workspaceSidebarScrollable,
    );
    await tester.pumpAndSettle();
    final shell = ShellScope.of(
      tester.element(find.byType(StyioShellScaffold)),
    );
    await tester.tap(
      find.byKey(const ValueKey('project-operation-useActiveCompiler')),
    );
    await tester.pumpAndSettle();
    expect(shell.lastToolchainCommand?.command, 'tool use');

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('project-operation-preparePublish')),
      120,
      scrollable: workspaceSidebarScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('project-operation-preparePublish')),
    );
    await tester.pumpAndSettle();
    expect(shell.lastDeploymentCommand?.command, 'publish');

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('required-handoffs-card')),
      120,
      scrollable: workspaceSidebarScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Required Handoffs'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Packages'),
      120,
      scrollable: workspaceSidebarScrollable,
    );
    await tester.pumpAndSettle();
    expect(find.text('Packages'), findsOneWidget);
    expect(find.text('demo/app'), findsWidgets);
    expect(find.text('Adapter Routes'), findsWidgets);
    expect(
      find.byKey(const ValueKey('required-handoffs-card'), skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('command-strip-run')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('command-strip-fetchDependencies')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('command-strip-vendorDependencies')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('command-strip-refreshModules')),
      findsOneWidget,
    );
    expect(find.byIcon(Icons.play_arrow_rounded), findsWidgets);
    expect(find.byIcon(Icons.arrow_right_alt_rounded), findsWidgets);

    await tester.tap(
      find.byKey(const ValueKey('command-strip-vendorDependencies')),
    );
    await tester.pumpAndSettle();

    expect(shell.lastDependencySourceCommand?.command, 'vendor');

    await tester.tap(find.byKey(const ValueKey('source-buffer-surface')));
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('source-line-0')));
    await tester.pump();

    expect(find.text('editing'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('inline-language-feedback-desktop')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('active-token-context')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(find.textContaining('selection '), findsOneWidget);

    await tester.tap(find.text('Debug'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('debug-surface-desktop')), findsOneWidget);
  });

  testWidgets('builds shared shell scaffold in mobile viewport family', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.android);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));

    expect(find.byKey(const ValueKey('shell-viewport-mobile')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-viewport-mobile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-language-family-mobile')),
      findsOneWidget,
    );
    expect(find.text('Mobile'), findsWidgets);
    expect(
      find.byKey(const ValueKey('command-strip-fetchDependencies')),
      findsNothing,
    );

    await revealMobileLanguagePane(tester);
    expect(
      find.byKey(const ValueKey('language-pane-mobile'), skipOffstage: false),
      findsOneWidget,
    );

    final shell = ShellScope.of(
      tester.element(find.byType(StyioShellScaffold)),
    );
    shell.selectBottomTab(BottomSurfaceTab.agent);
    await tester.pumpAndSettle();

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -720));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent-surface-mobile'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets(
    'executes sample project workflow through sidebar mainline lanes',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bootstrap = await createLiveWorkflowBootstrap(PlatformTarget.macos);

      await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));

      final workspaceSidebarScrollable = find.descendant(
        of: find.byKey(const ValueKey('workspace-sidebar-scroll')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('project-operations-card')),
        120,
        scrollable: workspaceSidebarScrollable,
      );
      await tester.pumpAndSettle();

      final shell = ShellScope.of(
        tester.element(find.byType(StyioShellScaffold)),
      );

      Future<void> tapWorkflowAction(String key) async {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey(key)),
          120,
          scrollable: workspaceSidebarScrollable,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
      }

      await tapWorkflowAction('project-operation-useActiveCompiler');
      await tapWorkflowAction('project-operation-fetchDependencies');
      await tapWorkflowAction('project-operation-vendorDependencies');
      await tapWorkflowAction('project-operation-run');
      await tapWorkflowAction('project-operation-preparePublish');

      expect(shell.lastToolchainCommand?.succeeded, isTrue);
      expect(shell.lastDependencySourceCommand?.command, 'vendor');
      expect(shell.lastDependencySourceCommand?.succeeded, isTrue);
      expect(
        shell.lastExecutionSession?.status,
        ExecutionSessionStatus.succeeded,
      );
      expect(shell.lastDeploymentCommand?.succeeded, isTrue);
      expect(shell.lastRuntimeEvents, hasLength(2));

      expect(find.text('execution succeeded'), findsOneWidget);
      expect(find.text('dependencies succeeded'), findsOneWidget);
      expect(find.text('environment succeeded'), findsOneWidget);
      expect(find.text('deployment succeeded'), findsOneWidget);
      expect(find.text('workflow blockers 0'), findsOneWidget);
      expect(find.textContaining('runtime 2'), findsWidgets);
      expect(find.textContaining('publishable 1'), findsWidgets);
    },
  );

  testWidgets('keeps mobile editor layout on wide iOS viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.ios);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));

    expect(find.byKey(const ValueKey('shell-viewport-mobile')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-viewport-mobile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-language-family-mobile')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-language-family-desktop')),
      findsNothing,
    );

    await revealMobileLanguagePane(tester);
    expect(
      find.byKey(const ValueKey('language-pane-mobile'), skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('shows token context for the caret-resolved token', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    final sourceOffset = bootstrap.editorController.document.text.indexOf(
      'source',
    );
    bootstrap.editorController.selectCollapsed(sourceOffset + 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));

    expect(find.byKey(const ValueKey('active-token-context')), findsOneWidget);
    expect(find.textContaining('Token `source`'), findsOneWidget);
  });

  testWidgets('highlights resolved current-file usages at caret', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = value\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(documentId: 'usages.styio', text: text, revision: 0),
    );
    bootstrap.editorController.selectCollapsed(text.lastIndexOf('value') + 2);
    expect(bootstrap.editorController.referencesAtSelection.length, 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));

    expect(
      backgroundsForTextOnLine(tester, lineIndex: 0, text: 'value'),
      contains(const Color(0xFFF5DA91)),
    );
    bootstrap.editorController.selectCollapsed(2);
    await tester.pump();
    expect(
      backgroundsForTextOnLine(tester, lineIndex: 0, text: 'value'),
      contains(const Color(0xFFDDEACB)),
    );
  });

  testWidgets('shows unresolved reference diagnostics from symbol index', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'unresolved.styio',
        text: 'known = 1\nmissingPrice -> @stdout\n',
        revision: 0,
      ),
    );

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));

    expect(
      find.textContaining(
        'Identifier is not resolved by the current symbol index.',
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('navigates diagnostics from editor keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'let stream\nmissingPrice -> @stdout\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'diagnostic-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(0);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();

    expect(bootstrap.editorController.selection.start, 0);
    expect(bootstrap.editorController.selection.end, text.indexOf('\n'));

    await tester.sendKeyEvent(LogicalKeyboardKey.f2);
    await tester.pump();

    expect(
      bootstrap.editorController.selection.start,
      text.indexOf('missingPrice'),
    );
  });

  testWidgets('selects diagnostics from problems list', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'let stream\nmissingPrice -> @stdout\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'problems-list.styio',
        text: text,
        revision: 0,
      ),
    );

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));

    final languageScrollable = find.descendant(
      of: find.byKey(const ValueKey('language-pane-desktop')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('language-diagnostic-1')),
      120,
      scrollable: languageScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-diagnostic-1')));
    await tester.pump();

    expect(
      bootstrap.editorController.selection.start,
      text.indexOf('missingPrice'),
    );
    expect(bootstrap.editorController.canUndo, isFalse);
  });

  testWidgets('navigates to resolved definition from language pane', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = value\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'definition.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.lastIndexOf('value') + 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('language-go-to-definition')),
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('language-pane-desktop')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-go-to-definition')));
    await tester.pump();

    expect(bootstrap.editorController.selection.start, 0);
    expect(bootstrap.editorController.selection.end, 'value'.length);
  });

  testWidgets('navigates to definition from editor keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = value\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'definition-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.lastIndexOf('value') + 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyB);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(bootstrap.editorController.selection.start, 0);
    expect(bootstrap.editorController.selection.end, 'value'.length);
  });

  testWidgets('extends and shrinks structural selection from editor keymap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'fn main(user) {\n  value = user\n}\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'selection-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('value') + 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(bootstrap.editorController.selection.start, text.indexOf('value'));
    expect(
      bootstrap.editorController.selection.end,
      text.indexOf('value') + 'value'.length,
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyW);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(bootstrap.editorController.selection.isCollapsed, isTrue);
    expect(bootstrap.editorController.selection.end, text.indexOf('value') + 2);
    expect(bootstrap.editorController.canUndo, isFalse);
  });

  testWidgets('toggles line comment from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = 1\nnext = 2\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'line-comment-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('value') + 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(
      bootstrap.editorController.document.text,
      '// value = 1\nnext = 2\n',
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(bootstrap.editorController.document.text, text);
  });

  testWidgets('duplicates current line from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = 1\nnext = 2\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'duplicate-line-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('value') + 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyD);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(
      bootstrap.editorController.document.text,
      'value = 1\nvalue = 1\nnext = 2\n',
    );
    expect(bootstrap.editorController.canUndo, isTrue);
  });

  testWidgets('moves current line from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'alpha\nbeta\ngamma\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'move-line-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('beta') + 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    expect(bootstrap.editorController.document.text, 'alpha\ngamma\nbeta\n');
    expect(bootstrap.editorController.selection.end, 14);
    expect(bootstrap.editorController.canUndo, isTrue);
  });

  testWidgets('joins lines from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value =\n  source\nnext\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'join-lines-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(bootstrap.editorController.document.text, 'value = source\nnext\n');
    expect(bootstrap.editorController.selection.end, 'value = '.length);
    expect(bootstrap.editorController.canUndo, isTrue);
  });

  testWidgets('deletes current line from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'alpha\nbeta\ngamma\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'delete-line-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('beta') + 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(bootstrap.editorController.document.text, 'alpha\ngamma\n');
    expect(bootstrap.editorController.selection.end, 'alpha\n'.length);
    expect(bootstrap.editorController.canUndo, isTrue);
  });

  testWidgets('opens surround with lookup from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'fn main() {\n  value = 1\n  next = 2\n}\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'surround-with-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('value') + 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyT);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byKey(const ValueKey('source-surround-lookup')), findsOne);
    expect(find.text('Surround With'), findsOne);
    expect(find.text('task block'), findsOne);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      bootstrap.editorController.document.text,
      'fn main() {\n  ||> {\n    value = 1\n  }\n  next = 2\n}\n',
    );
    expect(bootstrap.editorController.canUndo, isTrue);
  });

  testWidgets('moves to matching brace from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'fn main() {\n  value = [1]\n}\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'matching-brace-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('['));

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(bootstrap.editorController.selection.end, text.indexOf(']') + 1);
    expect(bootstrap.editorController.canUndo, isFalse);
  });

  testWidgets('inserts smart brace pair from source typing', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'fn main() ';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'smart-brace-pair.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.length);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft, character: '{');
    await tester.pump();

    expect(bootstrap.editorController.document.text, 'fn main() {}');
    expect(bootstrap.editorController.selection.end, text.length + 1);
    expect(bootstrap.editorController.canUndo, isTrue);
  });

  testWidgets('applies best completion from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'job = ||> { <| 42 }\njo';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'best-completion-keymap.styio',
        text: text,
        revision: 0,
      ),
    );

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(
      bootstrap.editorController.document.text,
      'job = ||> { <| 42 }\njob',
    );
  });

  testWidgets('opens parameter info from editor keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = '''
fn blend(left: f64, right: f64) {
  emit left
}
value = blend(price, tax)
''';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'parameter-info-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('tax') + 1);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-parameter-info-panel')),
      findsOneWidget,
    );
    expect(find.text('Parameter Info: blend'), findsOneWidget);
    expect(find.text('fn blend(left: f64, right: f64)'), findsOneWidget);
    expect(find.text('Argument 2 of 2: right: f64'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('source-parameter-info-close')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('source-parameter-info-panel')),
      findsNothing,
    );
  });

  testWidgets('opens quick documentation from editor keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = value\nvalue -> @stdout\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'quick-doc-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('= value') + 3);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-quick-doc-panel')),
      findsOneWidget,
    );
    expect(find.text('Quick Documentation: value'), findsOneWidget);
    expect(find.text('Identifier `value`.'), findsOneWidget);
    expect(find.text('3 current-file usages'), findsOneWidget);

    final sourceScrollable = find.descendant(
      of: find.byKey(const ValueKey('source-buffer-surface')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-quick-doc-definition')),
      80,
      scrollable: sourceScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('source-quick-doc-definition')));
    await tester.pump();

    expect(bootstrap.editorController.selection.start, 0);
    expect(bootstrap.editorController.canUndo, isFalse);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-quick-doc-usages')),
      80,
      scrollable: sourceScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('source-quick-doc-usages')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('source-usages-panel')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-quick-doc-close')),
      -80,
      scrollable: sourceScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('source-quick-doc-close')));
    await tester.pump();

    expect(find.byKey(const ValueKey('source-quick-doc-panel')), findsNothing);
  });

  testWidgets('selects document symbol from language pane', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'fn main(user) {\n  value = user\n}\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'structure.styio',
        text: text,
        revision: 0,
      ),
    );

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));

    final languageScrollable = find.descendant(
      of: find.byKey(const ValueKey('language-pane-desktop')),
      matching: find.byType(Scrollable),
    );
    const mainSymbolKey = ValueKey('language-document-symbol-function-main-3');
    await tester.scrollUntilVisible(
      find.byKey(mainSymbolKey),
      120,
      scrollable: languageScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(mainSymbolKey));
    await tester.pump();

    expect(bootstrap.editorController.selection.start, text.indexOf('main'));
    expect(
      bootstrap.editorController.selection.end,
      text.indexOf('main') + 'main'.length,
    );
    expect(bootstrap.editorController.canUndo, isFalse);
  });

  testWidgets('cycles resolved usages from editor keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = value\nvalue -> @stdout\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'usage-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('= value') + 3);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.pump();

    expect(
      bootstrap.editorController.selection.start,
      text.lastIndexOf('value'),
    );

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(
      bootstrap.editorController.selection.start,
      text.indexOf('= value') + 2,
    );
  });

  testWidgets('opens find usages panel from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = value\nvalue -> @stdout\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'find-usages-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('= value') + 3);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('source-usages-panel')), findsOneWidget);
    expect(find.text('3 current-file usages'), findsOneWidget);

    final sourceScrollable = find.descendant(
      of: find.byKey(const ValueKey('source-buffer-surface')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-usage-2')),
      80,
      scrollable: sourceScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('source-usage-2')));
    await tester.pump();

    expect(
      bootstrap.editorController.selection.start,
      text.lastIndexOf('value'),
    );
    expect(bootstrap.editorController.canUndo, isFalse);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-usages-close')),
      -80,
      scrollable: sourceScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('source-usages-close')));
    await tester.pump();

    expect(find.byKey(const ValueKey('source-usages-panel')), findsNothing);
  });

  testWidgets('cycles resolved usages from language pane', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = value\nvalue -> @stdout\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(documentId: 'usages.styio', text: text, revision: 0),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('= value') + 3);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));

    final languageScrollable = find.descendant(
      of: find.byKey(const ValueKey('language-pane-desktop')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('language-next-usage')),
      120,
      scrollable: languageScrollable,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-next-usage')));
    await tester.pump();

    expect(
      bootstrap.editorController.selection.start,
      text.lastIndexOf('value'),
    );

    expect(
      find.byKey(
        const ValueKey('language-previous-usage'),
        skipOffstage: false,
      ),
      findsOneWidget,
    );
  });

  testWidgets('applies completion from editor keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'job = ||> { <| 42 }\njo';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'completion-keymap.styio',
        text: text,
        revision: 0,
      ),
    );

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();
    expect(
      bootstrap.editorController.completionsAtSelection.map(
        (item) => item.label,
      ),
      contains('job'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(
      bootstrap.editorController.document.text,
      'job = ||> { <| 42 }\njob',
    );
  });

  testWidgets('opens completion lookup from editor keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'job = ||> { <| 42 }\njo';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'completion-lookup-keymap.styio',
        text: text,
        revision: 0,
      ),
    );

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-completion-lookup')),
      findsOneWidget,
    );
    expect(find.text('Code Completion'), findsOneWidget);
    expect(find.text('job · variable'), findsOneWidget);
    expect(bootstrap.editorController.document.text, text);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      bootstrap.editorController.document.text,
      'job = ||> { <| 42 }\njob',
    );
    expect(
      find.byKey(const ValueKey('source-completion-lookup')),
      findsNothing,
    );
  });

  testWidgets('applies quick fix from editor keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'let stream\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'quickfix-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('stream') + 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pump();

    expect(bootstrap.editorController.document.text, 'let stream = value\n');
  });

  testWidgets('applies rename edits from language pane', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = value\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(documentId: 'rename.styio', text: text, revision: 0),
    );
    bootstrap.editorController.selectCollapsed(text.lastIndexOf('value') + 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));

    final languageScrollable = find.descendant(
      of: find.byKey(const ValueKey('language-pane-desktop')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('language-rename-input')),
      120,
      scrollable: languageScrollable,
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('language-rename-input')),
      'price',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('language-apply-rename')));
    await tester.pump();

    expect(bootstrap.editorController.document.text, 'price = price\n');
  });

  testWidgets('opens inline rename from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = value\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'inline-rename.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.lastIndexOf('value') + 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('source-buffer-surface')),
        matching: find.text('Source Buffer'),
      ),
    );
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('source-inline-rename-panel')), findsOne);
    final renameField = tester.widget<TextField>(
      find.byKey(const ValueKey('source-inline-rename-input')),
    );
    expect(renameField.controller!.text, 'value');

    await tester.enterText(
      find.byKey(const ValueKey('source-inline-rename-input')),
      'price',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(bootstrap.editorController.document.text, 'price = price\n');
    expect(
      find.byKey(const ValueKey('source-inline-rename-panel')),
      findsNothing,
    );
  });

  testWidgets('keeps inline rename open for invalid identifiers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = value\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'inline-rename-invalid.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('value') + 2);

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));
    await tester.tap(find.byKey(const ValueKey('source-buffer-surface')));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('source-inline-rename-input')),
      '1bad',
    );
    await tester.tap(find.byKey(const ValueKey('source-inline-rename-apply')));
    await tester.pump();

    expect(bootstrap.editorController.document.text, text);
    expect(find.byKey(const ValueKey('source-inline-rename-panel')), findsOne);
    expect(find.text('Invalid rename target.'), findsOne);
  });

  testWidgets('applies inline diagnostic quick fix from the active line', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'broken.styio',
        text: 'fn broken() {\n  emit stream\n',
        revision: 0,
      ),
    );

    await tester.pumpWidget(StyioViewApp(bootstrap: bootstrap));

    await tester.tap(find.byKey(const ValueKey('source-buffer-surface')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('source-line-0')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('inline-diagnostic-fix-0')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('inline-diagnostic-fix-0')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('inline-diagnostic-fix-0')));
    await tester.pump();

    expect(bootstrap.editorController.document.text.endsWith('}'), isTrue);
    expect(
      bootstrap.editorController.analysis.diagnostics.where(
        (item) => item.code == 'unclosed-block',
      ),
      isEmpty,
    );
  });
}

class _FakeProjectGraphAdapter implements ProjectGraphAdapter {
  const _FakeProjectGraphAdapter(this.projectSnapshot);

  final ProjectGraphSnapshot projectSnapshot;

  @override
  AdapterCapabilitySnapshot
  get capabilitySnapshot => const AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cli,
    languageService: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.partial,
      detail:
          'Smoke test CLI adapter keeps language-service contracts partial.',
    ),
    projectGraph: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail: 'Smoke test project graph is resolved from a canonical fixture.',
    ),
    execution: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Fake project graph adapter does not own execution routes.',
    ),
    runtimeEvents: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Fake project graph adapter does not emit runtime events.',
    ),
  );

  @override
  Future<ProjectGraphSnapshot> loadProjectGraph() async => projectSnapshot;
}

class _FakeExecutionAdapter implements ExecutionAdapter {
  const _FakeExecutionAdapter();

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot =>
      const AdapterCapabilitySnapshot(
        adapterKind: AdapterKind.cli,
        languageService: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Fake execution adapter exposes no language-service data.',
        ),
        projectGraph: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Fake execution adapter does not own project graph data.',
        ),
        execution: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.partial,
          detail: 'Fake execution adapter keeps run requests blocked.',
        ),
        runtimeEvents: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Fake execution adapter does not emit runtime events.',
        ),
      );

  @override
  Future<ExecutionSession> runActiveDocument({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
  }) async {
    return const ExecutionSession(
      sessionId: 'smoke-test',
      kind: 'run',
      status: ExecutionSessionStatus.blocked,
      statusMessage: 'Smoke test execution route remains blocked.',
      diagnostics: <Diagnostic>[],
      stdoutEvents: <ExecutionLogEvent>[],
      stderrEvents: <ExecutionLogEvent>[],
    );
  }
}

class _FakeToolchainManagementAdapter implements ToolchainManagementAdapter {
  const _FakeToolchainManagementAdapter();

  @override
  Future<ToolchainCommandResult> clearPinnedCompiler({
    required ProjectGraphSnapshot projectGraph,
  }) async {
    return const ToolchainCommandResult(
      command: 'tool pin',
      status: ToolchainCommandStatus.blocked,
      statusMessage: 'Smoke test toolchain operations remain blocked.',
      stdout: '',
      stderr: '',
    );
  }

  @override
  Future<ToolchainCommandResult> installManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String styioBinaryPath,
  }) async {
    return const ToolchainCommandResult(
      command: 'tool install',
      status: ToolchainCommandStatus.blocked,
      statusMessage: 'Smoke test toolchain operations remain blocked.',
      stdout: '',
      stderr: '',
    );
  }

  @override
  Future<ToolchainCommandResult> pinManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async {
    return const ToolchainCommandResult(
      command: 'tool pin',
      status: ToolchainCommandStatus.blocked,
      statusMessage: 'Smoke test toolchain operations remain blocked.',
      stdout: '',
      stderr: '',
    );
  }

  @override
  Future<ToolchainCommandResult> useManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async {
    return const ToolchainCommandResult(
      command: 'tool use',
      status: ToolchainCommandStatus.blocked,
      statusMessage: 'Smoke test toolchain operations remain blocked.',
      stdout: '',
      stderr: '',
    );
  }
}

class _FakeDependencySourceAdapter implements DependencySourceAdapter {
  const _FakeDependencySourceAdapter();

  @override
  Future<DependencySourceCommandResult> fetchDependencies({
    required ProjectGraphSnapshot projectGraph,
    bool locked = false,
    bool offline = false,
  }) async {
    return const DependencySourceCommandResult(
      command: 'fetch',
      status: DependencySourceCommandStatus.blocked,
      statusMessage: 'Smoke test dependency-source operations remain blocked.',
      stdout: '',
      stderr: '',
    );
  }

  @override
  Future<DependencySourceCommandResult> vendorDependencies({
    required ProjectGraphSnapshot projectGraph,
    String? outputPath,
    bool locked = false,
    bool offline = false,
  }) async {
    return const DependencySourceCommandResult(
      command: 'vendor',
      status: DependencySourceCommandStatus.blocked,
      statusMessage: 'Smoke test dependency-source operations remain blocked.',
      stdout: '',
      stderr: '',
    );
  }
}

class _FakeDeploymentAdapter implements DeploymentAdapter {
  const _FakeDeploymentAdapter();

  @override
  Future<DeploymentCommandResult> packProject({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) async {
    return const DeploymentCommandResult(
      command: 'pack',
      status: DeploymentCommandStatus.blocked,
      statusMessage: 'Smoke test deployment operations remain blocked.',
      stdout: '',
      stderr: '',
    );
  }

  @override
  Future<DeploymentCommandResult> preparePublish({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) async {
    return const DeploymentCommandResult(
      command: 'publish',
      status: DeploymentCommandStatus.blocked,
      statusMessage: 'Smoke test deployment operations remain blocked.',
      stdout: '',
      stderr: '',
    );
  }

  @override
  Future<DeploymentCommandResult> publishToRegistry({
    required ProjectGraphSnapshot projectGraph,
    required String registryRoot,
    String? packageName,
    String? outputPath,
  }) async {
    return const DeploymentCommandResult(
      command: 'publish',
      status: DeploymentCommandStatus.blocked,
      statusMessage: 'Smoke test deployment operations remain blocked.',
      stdout: '',
      stderr: '',
    );
  }
}

class _LiveExecutionAdapter implements ExecutionAdapter {
  const _LiveExecutionAdapter();

  @override
  AdapterCapabilitySnapshot
  get capabilitySnapshot => const AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cli,
    languageService: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Live workflow fixture does not expose language-service data.',
    ),
    projectGraph: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Live workflow execution stays on the published shell route.',
    ),
    execution: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail:
          'Live workflow fixture exposes project execution through compile-plan v1.',
    ),
    runtimeEvents: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.partial,
      detail: 'Live workflow fixture replays published runtime events.',
    ),
  );

  @override
  Future<ExecutionSession> runActiveDocument({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
  }) async {
    return const ExecutionSession(
      sessionId: 'live-workflow-run',
      kind: 'run',
      status: ExecutionSessionStatus.succeeded,
      statusMessage: 'Live workflow fixture executed the active project route.',
      diagnostics: <Diagnostic>[],
      stdoutEvents: <ExecutionLogEvent>[ExecutionLogEvent(message: 'run-ok')],
      stderrEvents: <ExecutionLogEvent>[],
    );
  }
}

class _LiveToolchainManagementAdapter implements ToolchainManagementAdapter {
  const _LiveToolchainManagementAdapter();

  @override
  Future<ToolchainCommandResult> clearPinnedCompiler({
    required ProjectGraphSnapshot projectGraph,
  }) async {
    return _success('tool pin');
  }

  @override
  Future<ToolchainCommandResult> installManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String styioBinaryPath,
  }) async {
    return _success('tool install');
  }

  @override
  Future<ToolchainCommandResult> pinManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async {
    return _success('tool pin');
  }

  @override
  Future<ToolchainCommandResult> useManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async {
    return _success('tool use');
  }

  ToolchainCommandResult _success(String command) {
    return ToolchainCommandResult(
      command: command,
      status: ToolchainCommandStatus.succeeded,
      statusMessage: 'live workflow toolchain command succeeded.',
      stdout: '',
      stderr: '',
    );
  }
}

class _LiveDependencySourceAdapter implements DependencySourceAdapter {
  const _LiveDependencySourceAdapter();

  @override
  Future<DependencySourceCommandResult> fetchDependencies({
    required ProjectGraphSnapshot projectGraph,
    bool locked = false,
    bool offline = false,
  }) async {
    return _success('fetch');
  }

  @override
  Future<DependencySourceCommandResult> vendorDependencies({
    required ProjectGraphSnapshot projectGraph,
    String? outputPath,
    bool locked = false,
    bool offline = false,
  }) async {
    return _success('vendor');
  }

  DependencySourceCommandResult _success(String command) {
    return DependencySourceCommandResult(
      command: command,
      status: DependencySourceCommandStatus.succeeded,
      statusMessage: 'live workflow dependency command succeeded.',
      stdout: '',
      stderr: '',
      payload: <String, dynamic>{
        'packages': 2,
        'vendor_root': '/workspace/demo/.spio/vendor',
        'metadata_path': '/workspace/demo/.spio/vendor/spio-vendor.json',
      },
    );
  }
}

class _LiveDeploymentAdapter implements DeploymentAdapter {
  const _LiveDeploymentAdapter();

  @override
  Future<DeploymentCommandResult> packProject({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) async {
    return _success('pack', packageName: packageName);
  }

  @override
  Future<DeploymentCommandResult> preparePublish({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) async {
    return _success('publish', packageName: packageName);
  }

  @override
  Future<DeploymentCommandResult> publishToRegistry({
    required ProjectGraphSnapshot projectGraph,
    required String registryRoot,
    String? packageName,
    String? outputPath,
  }) async {
    return _success('publish', packageName: packageName);
  }

  DeploymentCommandResult _success(String command, {String? packageName}) {
    return DeploymentCommandResult(
      command: command,
      status: DeploymentCommandStatus.succeeded,
      statusMessage: 'live workflow deployment command succeeded.',
      stdout: '',
      stderr: '',
      payload: <String, dynamic>{
        'package': packageName ?? 'demo/app',
        'archive_path': '/workspace/demo/dist/app-0.0.5.tar',
      },
    );
  }
}
