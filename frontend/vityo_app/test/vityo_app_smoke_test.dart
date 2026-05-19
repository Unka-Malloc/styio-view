import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_coding_session_controller.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_configurator.dart';
import 'package:vityo_app/src/frontend_shell/frontend_shell.dart';
import 'package:vityo_app/src/editor/editor_controller.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/backend_toolchain/dependency_source_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/deployment_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/backend_toolchain/runtime_event_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/toolchain_management_adapter.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/module_host/module_registry.dart';
import 'package:vityo_app/src/platform/native_module_loader.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_manager.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_resolver.dart';
import 'package:vityo_app/src/view_render/theme/theme.dart';

AgentCodingSessionController createSmokeAgentController(
  PlatformTarget target,
  EditorSessionController editorController,
) {
  return AgentCodingSessionController(
    profile: AgentPromptProfile.defaultForPlatform(target),
    adapter: const LocalOnlyAgentProviderAdapter(),
    contextProvider: () => AgentSessionContext.fromEditorState(
      document: editorController.document,
      selection: editorController.selection,
      diagnostics: editorController.analysis.diagnostics,
    ),
  );
}

AgentProviderConfigurator createSmokeAgentProviderConfigurator() {
  return AgentProviderConfigurator(
    workspaceId: 'smoke',
    saveProfile:
        ({
          required String workspaceId,
          required String key,
          required AgentPromptProfile profile,
        }) async {},
    createAdapter: (profile) async => const LocalOnlyAgentProviderAdapter(),
  );
}

void main() {
  Future<void> pumpVityoApp(
    WidgetTester tester,
    AppBootstrap bootstrap, {
    String? initialPath,
  }) async {
    final documentId = bootstrap.editorController.document.documentId;
    final selection = bootstrap.editorController.selection;
    await tester.pumpWidget(
      VityoApp(bootstrap: bootstrap, initialPath: initialPath),
    );
    await tester.pumpAndSettle();
    if (bootstrap.editorController.document.documentId == documentId &&
        selection.end <= bootstrap.editorController.document.length) {
      bootstrap.editorController.selectRange(
        baseOffset: selection.baseOffset,
        extentOffset: selection.extentOffset,
      );
      await tester.pump();
    }
  }

  Future<void> pumpShellScaffold(
    WidgetTester tester,
    AppBootstrap bootstrap,
  ) async {
    await tester.pumpWidget(_ShellScaffoldHarness(bootstrap: bootstrap));
    await tester.pump();
  }

  Future<void> tapVisibleKey(WidgetTester tester, String key) async {
    final finder = find.byKey(ValueKey(key), skipOffstage: false);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder, warnIfMissed: false);
    await tester.pump();
  }

  Future<void> tapVisibleText(WidgetTester tester, String text) async {
    final finder = find.text(text, skipOffstage: false);
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder, warnIfMissed: false);
    await tester.pump();
  }

  Future<void> focusSourceBuffer(
    WidgetTester tester, [
    EditorSessionController? controller,
  ]) async {
    final selection = controller?.selection;
    final surface = find.byKey(
      const ValueKey('source-buffer-surface'),
      skipOffstage: false,
    );
    await tester.ensureVisible(surface);
    await tester.pump();
    final header = find.descendant(
      of: surface,
      matching: find.text('Source Buffer', skipOffstage: false),
      skipOffstage: false,
    );
    if (header.evaluate().isNotEmpty) {
      await tester.tap(header, warnIfMissed: false);
    } else {
      final surfaceRect = tester.getRect(surface);
      await tester.tapAt(surfaceRect.topLeft + const Offset(24, 24));
    }
    await tester.pump();
    if (selection != null &&
        controller != null &&
        selection.end <= controller.document.length) {
      controller.selectRange(
        baseOffset: selection.baseOffset,
        extentOffset: selection.extentOffset,
      );
      await tester.pump();
    }
  }

  Future<void> revealMobileLanguagePane(WidgetTester tester) async {
    final languagePane = find.byKey(
      const ValueKey('language-pane-mobile'),
      skipOffstage: false,
    );
    if (languagePane.evaluate().isNotEmpty) {
      await tester.ensureVisible(languagePane);
      await tester.pump();
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
        of: find.byKey(ValueKey('source-line-$lineIndex'), skipOffstage: false),
        matching: find.byType(RichText, skipOffstage: false),
        skipOffstage: false,
      ),
    );
    for (final richText in richTexts) {
      visit(richText.text);
    }
    return colors;
  }

  List<String> spanTextsOnLine(WidgetTester tester, {required int lineIndex}) {
    final texts = <String>[];

    void visit(InlineSpan span) {
      if (span is TextSpan) {
        if (span.text != null) {
          texts.add(span.text!);
        }
        for (final child in span.children ?? const <InlineSpan>[]) {
          visit(child);
        }
      }
    }

    final richTexts = tester.widgetList<RichText>(
      find.descendant(
        of: find.byKey(ValueKey('source-line-$lineIndex'), skipOffstage: false),
        matching: find.byType(RichText, skipOffstage: false),
        skipOffstage: false,
      ),
    );
    for (final richText in richTexts) {
      visit(richText.text);
    }
    return texts;
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
    final toolchainStatusReport = ValueNotifier<ToolchainManagerStatusReport>(
      const ToolchainManagerStatusReport(
        status: ToolchainManagerStatus.ready,
        snapshot: ToolchainStateSnapshot(
          targetId: 'smoke-target',
          workspaceId: 'smoke-workspace',
          entries: <ToolchainStateEntry>[
            ToolchainStateEntry(
              id: 'smoke-language-service',
              kind: ToolchainKind.languageService,
              displayName: 'Smoke StyioService',
              executablePath: '/workspace/demo/.spio/bin/styio',
              active: true,
              version: '0.0.9',
              channel: 'smoke',
            ),
          ],
        ),
        requirement: ToolchainRequirement(kind: ToolchainKind.languageService),
        resolution: ToolchainResolution(
          status: ToolchainResolutionStatus.resolved,
          requirement: ToolchainRequirement(
            kind: ToolchainKind.languageService,
          ),
          descriptor: ToolchainDescriptor(
            id: 'smoke-language-service',
            kind: ToolchainKind.languageService,
            displayName: 'Smoke StyioService',
            executablePath: '/workspace/demo/.spio/bin/styio',
            version: '0.0.9',
            channel: 'smoke',
          ),
        ),
      ),
    );
    addTearDown(toolchainStatusReport.dispose);
    final editorController = EditorSessionController(
      initialDocument: EditorSessionController.seedDocumentForPath(
        workspaceController.activeFilePath,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
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
      editorController: editorController,
      executionAdapter: const _FakeExecutionAdapter(),
      executionAdapterFactory: (ProjectGraphSnapshot _) async =>
          const _FakeExecutionAdapter(),
      runtimeEventAdapter: createRuntimeEventAdapter(platformTarget: target),
      dependencySourceAdapter: const _FakeDependencySourceAdapter(),
      deploymentAdapter: const _FakeDeploymentAdapter(),
      toolchainManagementAdapter: const _FakeToolchainManagementAdapter(),
      agentCodingController: createSmokeAgentController(
        target,
        editorController,
      ),
      agentProviderConfigurator: createSmokeAgentProviderConfigurator(),
      toolchainStatusReport: toolchainStatusReport,
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
    final editorController = EditorSessionController(
      initialDocument: EditorSessionController.seedDocumentForPath(
        workspaceController.activeFilePath,
      ),
      languageService: const SimpleStyioLanguageService(),
    );
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
      editorController: editorController,
      executionAdapter: const _LiveExecutionAdapter(),
      executionAdapterFactory: (ProjectGraphSnapshot _) async =>
          const _LiveExecutionAdapter(),
      runtimeEventAdapter: createRuntimeEventAdapter(platformTarget: target),
      dependencySourceAdapter: const _LiveDependencySourceAdapter(),
      deploymentAdapter: const _LiveDeploymentAdapter(),
      toolchainManagementAdapter: const _LiveToolchainManagementAdapter(),
      agentCodingController: createSmokeAgentController(
        target,
        editorController,
      ),
      agentProviderConfigurator: createSmokeAgentProviderConfigurator(),
    );
  }

  testWidgets('app entry renders the full editor workbench shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);

    await pumpVityoApp(tester, bootstrap);

    expect(
      find.byKey(const ValueKey('editor-viewport-desktop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-language-family-desktop')),
      findsOneWidget,
    );
    expect(find.text('Vityo Integration Shell'), findsNothing);
    expect(find.text('Vityo Editor Workbench'), findsOneWidget);
    expect(find.text('Project Graph'), findsOneWidget);
  });

  testWidgets('editor route renders the full editor workbench shell', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);

    await pumpVityoApp(tester, bootstrap, initialPath: '/editor');

    expect(
      find.byKey(const ValueKey('editor-viewport-desktop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-language-family-desktop')),
      findsOneWidget,
    );
    expect(find.text('Vityo Integration Shell'), findsNothing);
    expect(find.text('Vityo Editor Workbench'), findsOneWidget);
    expect(find.text('Project Graph'), findsOneWidget);
  });

  testWidgets('legacy guide path canonicalizes to the full editor workbench', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);

    await pumpVityoApp(tester, bootstrap, initialPath: '/guide');

    expect(
      find.byKey(const ValueKey('editor-viewport-desktop')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('editor-language-family-desktop')),
      findsOneWidget,
    );
    expect(find.text('Vityo Integration Shell'), findsNothing);
    expect(find.text('Vityo Editor Workbench'), findsOneWidget);
    expect(find.text('Project Graph'), findsOneWidget);
  });

  testWidgets('builds shared shell scaffold as an internal component', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);

    await pumpShellScaffold(tester, bootstrap);

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
    expect(find.text('source manager-report'), findsOneWidget);
    expect(find.text('Vityo Editor Workbench'), findsOneWidget);
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
      tester.element(find.byType(VityoShellScaffold)),
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
    expect(find.byKey(const ValueKey('command-strip-save')), findsOneWidget);
    expect(find.byKey(const ValueKey('command-strip-saveAll')), findsOneWidget);
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

    await tapVisibleKey(tester, 'command-strip-vendorDependencies');

    expect(shell.lastDependencySourceCommand?.command, 'vendor');

    await tester.tap(find.byKey(const ValueKey('command-strip-openSettings')));
    await tester.pumpAndSettle();

    expect(shell.activeBottomTab, BottomSurfaceTab.settings);
    expect(find.byKey(const ValueKey('settings-surface')), findsOneWidget);

    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.tap(find.byKey(const ValueKey('source-line-0')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('source-buffer-surface'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('inline-language-feedback-desktop')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('active-token-context')), findsOneWidget);

    await tapVisibleText(tester, 'Debug');

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

    await pumpShellScaffold(tester, bootstrap);

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
  });

  testWidgets(
    'executes sample project workflow through sidebar mainline lanes',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final bootstrap = await createLiveWorkflowBootstrap(PlatformTarget.macos);

      await pumpShellScaffold(tester, bootstrap);

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
        tester.element(find.byType(VityoShellScaffold)),
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

    await pumpVityoApp(tester, bootstrap);

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

  testWidgets('app entry renders mobile workbench shell on wide iOS viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1366, 1024);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.ios);

    await pumpVityoApp(tester, bootstrap);

    expect(find.text('Vityo Integration Shell'), findsNothing);
    expect(find.text('Vityo Editor Workbench'), findsOneWidget);
    expect(find.text('Project Graph'), findsOneWidget);
    expect(find.byType(VityoShellScaffold), findsOneWidget);
    expect(
      find.byKey(const ValueKey('editor-viewport-mobile')),
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

    await pumpVityoApp(tester, bootstrap);

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

    await pumpVityoApp(tester, bootstrap);

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

    await pumpVityoApp(tester, bootstrap);

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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

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

    await pumpVityoApp(tester, bootstrap);

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

    await pumpVityoApp(tester, bootstrap);

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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyY);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(bootstrap.editorController.document.text, 'alpha\ngamma\n');
    expect(bootstrap.editorController.selection.end, 'alpha\n'.length);
    expect(bootstrap.editorController.canUndo, isTrue);
  });

  testWidgets('deletes previous word from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'alpha beta';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'delete-word-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.length);

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(bootstrap.editorController.document.text, 'alpha ');
    expect(bootstrap.editorController.selection.end, 'alpha '.length);
    expect(bootstrap.editorController.canUndo, isTrue);
  });

  testWidgets('moves to smart line start from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'fn main() {\n  value = 1\n}\n';
    final valueStart = text.indexOf('value');
    final lineStart = text.lastIndexOf('\n', valueStart) + 1;
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'smart-home-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(valueStart + 3);

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(bootstrap.editorController.selection.end, valueStart);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pump();
    expect(bootstrap.editorController.selection.end, lineStart);
    expect(bootstrap.editorController.canUndo, isFalse);
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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(bootstrap.editorController.selection.end, text.indexOf(']') + 1);
    expect(bootstrap.editorController.canUndo, isFalse);
  });

  testWidgets('folds and expands semantic blocks from source keymap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'fn main() {\n  value = 1\n  next = 2\n}\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'semantic-fold-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('value') + 2);

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    expect(find.byKey(const ValueKey('source-fold-toggle-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('source-line-2')), findsOneWidget);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byKey(const ValueKey('source-fold-summary-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('source-line-2')), findsNothing);
    expect(bootstrap.editorController.document.text, text);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.minus);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.byKey(const ValueKey('source-fold-summary-0')), findsNothing);
    expect(find.byKey(const ValueKey('source-line-2')), findsOneWidget);
  });

  testWidgets('moves by word from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'alpha beta';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'word-navigation-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(1);

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(bootstrap.editorController.selection.end, 'alpha'.length);
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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyEvent(LogicalKeyboardKey.bracketLeft, character: '{');
    await tester.pump();

    expect(bootstrap.editorController.document.text, 'fn main() {}');
    expect(bootstrap.editorController.selection.end, text.length + 1);
    expect(bootstrap.editorController.canUndo, isTrue);
  });

  testWidgets('splits smart brace pair from source enter keymap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'fn main() {}';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'smart-newline-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('{') + 1);

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(bootstrap.editorController.document.text, 'fn main() {\n  \n}');
    expect(bootstrap.editorController.selection.end, 'fn main() {\n  '.length);
    expect(bootstrap.editorController.canUndo, isTrue);
  });

  testWidgets('indents and outdents current line from source keymap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'alpha\nbeta\n';
    final lineStart = text.indexOf('beta');
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'indent-line-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(lineStart);

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(bootstrap.editorController.document.text, 'alpha\n  beta\n');
    expect(bootstrap.editorController.selection.end, lineStart + 2);
    expect(bootstrap.editorController.canUndo, isTrue);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(bootstrap.editorController.document.text, text);
    expect(bootstrap.editorController.selection.end, lineStart);
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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

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
/// Blends price and tax inputs.
/// @param left Base price before tax.
/// @param right Tax component to add.
fn blend(left: f64, right: f64 = 0.0) {
  emit left
}
value = blend(right: tax, left: price)
''';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'parameter-info-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.lastIndexOf('tax') + 1);

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyP);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-parameter-info-panel')),
      findsOneWidget,
    );
    expect(find.text('Parameter Info: blend'), findsOneWidget);
    expect(find.text('fn blend(left: f64, right: f64 = 0.0)'), findsOneWidget);
    expect(find.text('Blends price and tax inputs.'), findsOneWidget);
    expect(find.text('Argument 2 of 2: right: f64 = 0.0'), findsOneWidget);
    expect(find.text('Tax component to add.'), findsOneWidget);

    await tapVisibleKey(tester, 'source-parameter-info-close');

    expect(
      find.byKey(const ValueKey('source-parameter-info-panel')),
      findsNothing,
    );
  });

  testWidgets('renders parameter inlay hints in source lines', (tester) async {
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
        documentId: 'parameter-inlay-source.styio',
        text: text,
        revision: 0,
      ),
    );

    await pumpVityoApp(tester, bootstrap);
    await tester.pump();

    final callLine = bootstrap.editorController.document
        .positionForOffset(text.indexOf('value = blend'))
        .line;
    final callLineSpans = spanTextsOnLine(tester, lineIndex: callLine);
    final inlaySection = find.byKey(
      const ValueKey('language-desktop-section-inlays'),
    );

    expect(bootstrap.editorController.analysis.inlayHintCount, 2);
    expect(callLineSpans, containsAll(<String>['left: ', 'right: ']));
    await tester.scrollUntilVisible(
      inlaySection,
      120,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('language-pane-desktop')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(inlaySection, findsOneWidget);
  });

  testWidgets('renders type inlay hints in source lines', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = '''
fn blend(left: f64, right: f64): f64 {
  emit left
}
price = 12.5
value = blend(price, price)
''';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'type-inlay-source.styio',
        text: text,
        revision: 0,
      ),
    );

    await pumpVityoApp(tester, bootstrap);
    await tester.pump();

    final priceLine = bootstrap.editorController.document
        .positionForOffset(text.indexOf('price = 12.5'))
        .line;
    final valueLine = bootstrap.editorController.document
        .positionForOffset(text.indexOf('value = blend'))
        .line;

    expect(bootstrap.editorController.analysis.inlayHintCount, 4);
    expect(
      spanTextsOnLine(tester, lineIndex: priceLine),
      containsAll(<String>[': f64 ']),
    );
    expect(
      spanTextsOnLine(tester, lineIndex: valueLine),
      containsAll(<String>[': f64 ', 'left: ', 'right: ']),
    );
  });

  testWidgets('opens quick documentation from editor keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = '''
/**
 * Primary value binding
 */
value = value
value -> @stdout
''';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'quick-doc-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('= value') + 3);

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyQ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-quick-doc-panel')),
      findsOneWidget,
    );
    expect(find.text('Quick Documentation: value'), findsOneWidget);
    expect(find.textContaining('Styio variable `value`'), findsOneWidget);
    expect(find.textContaining('Primary value binding'), findsOneWidget);
    expect(find.textContaining('Declared at 4:1'), findsOneWidget);
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
    await tapVisibleKey(tester, 'source-quick-doc-definition');

    expect(bootstrap.editorController.selection.start, text.indexOf('value ='));
    expect(bootstrap.editorController.canUndo, isFalse);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-quick-doc-usages')),
      80,
      scrollable: sourceScrollable,
    );
    await tester.pumpAndSettle();
    await tapVisibleKey(tester, 'source-quick-doc-usages');

    expect(find.byKey(const ValueKey('source-usages-panel')), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-quick-doc-close')),
      -80,
      scrollable: sourceScrollable,
    );
    await tester.pumpAndSettle();
    await tapVisibleKey(tester, 'source-quick-doc-close');

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

    await pumpVityoApp(tester, bootstrap);

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

  testWidgets('opens symbol lookup from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text =
        'fn buildPipe(user) {\n'
        '  value = user\n'
        '}\n'
        'fn renderPipe() {\n'
        '}\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'symbol-lookup-keymap.styio',
        text: text,
        revision: 0,
      ),
    );

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('source-symbol-lookup')), findsOneWidget);
    expect(find.text('Go to Symbol'), findsOneWidget);
    expect(find.text('buildPipe · function · 1:4'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyE);
    await tester.pump();

    expect(find.text('renderPipe · function · 4:4'), findsOneWidget);
    expect(find.text('buildPipe · function · 1:4'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      bootstrap.editorController.selection.start,
      text.indexOf('renderPipe'),
    );
    expect(
      bootstrap.editorController.selection.end,
      text.indexOf('renderPipe') + 'renderPipe'.length,
    );
    expect(bootstrap.editorController.document.text, text);
    expect(find.byKey(const ValueKey('source-symbol-lookup')), findsNothing);
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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

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
    const text = '@sink : i64|..1| := {}\nvalue -> @sink\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'find-usages-keymap.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.lastIndexOf('sink') + 2);

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f7);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('source-usages-panel')), findsOneWidget);
    expect(find.text('2 current-file usages'), findsOneWidget);
    expect(find.text('write · resource · 2:11'), findsOneWidget);

    final sourceScrollable = find.descendant(
      of: find.byKey(const ValueKey('source-buffer-surface')),
      matching: find.byType(Scrollable),
    );
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-usage-1')),
      80,
      scrollable: sourceScrollable,
    );
    await tester.pumpAndSettle();
    await tapVisibleKey(tester, 'source-usage-1');

    expect(
      bootstrap.editorController.selection.start,
      text.lastIndexOf('sink'),
    );
    expect(bootstrap.editorController.canUndo, isFalse);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('source-usages-close')),
      -80,
      scrollable: sourceScrollable,
    );
    await tester.pumpAndSettle();
    await tapVisibleKey(tester, 'source-usages-close');

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

    await pumpVityoApp(tester, bootstrap);

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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);
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

  testWidgets('applies postfix completion from editor keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = '  blend(price, tax).em';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'postfix-completion-keymap.styio',
        text: text,
        revision: 0,
      ),
    );

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);
    expect(
      bootstrap.editorController.completionsAtSelection.map(
        (item) => item.label,
      ),
      contains('.emit'),
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();

    expect(
      bootstrap.editorController.document.text,
      '  emit blend(price, tax)',
    );
  });

  testWidgets('opens completion lookup while typing source identifiers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'job = ||> { <| 42 }\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'completion-auto-popup.styio',
        text: text,
        revision: 0,
      ),
    );

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ, character: 'j');
    await tester.pumpAndSettle();

    expect(bootstrap.editorController.document.text, '${text}j');
    expect(
      find.byKey(const ValueKey('source-completion-lookup')),
      findsOneWidget,
    );
    expect(find.text('job · variable'), findsOneWidget);
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('source-completion-preview-insert')),
          )
          .data,
      'Insert `job`',
    );
  });

  testWidgets('skips completion auto-popup while typing comments', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = '// comment ';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'completion-auto-popup-comment.styio',
        text: text,
        revision: 0,
      ),
    );

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyJ, character: 'j');
    await tester.pumpAndSettle();

    expect(bootstrap.editorController.document.text, '${text}j');
    expect(
      find.byKey(const ValueKey('source-completion-lookup')),
      findsNothing,
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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

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
    expect(
      find.byKey(const ValueKey('source-completion-preview')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('source-completion-preview-detail')),
          )
          .data,
      'Current file variable symbol.',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('source-completion-preview-insert')),
          )
          .data,
      'Insert `job`',
    );
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

  testWidgets('opens completion documentation from lookup action', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = '/// Runs async price work.\njob = ||> { <| 42 }\njo';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'completion-doc-keymap.styio',
        text: text,
        revision: 0,
      ),
    );

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('source-completion-lookup')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('source-completion-preview-doc')),
    );
    await tester.pump();
    await tapVisibleKey(tester, 'source-completion-preview-doc');

    expect(
      find.byKey(const ValueKey('source-completion-lookup')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('source-quick-doc-panel')), findsOne);
    expect(find.text('Quick Documentation: job'), findsOneWidget);
    expect(
      tester
          .widget<Text>(find.byKey(const ValueKey('source-quick-doc-body')))
          .data,
      'Runs async price work.',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('source-quick-doc-completion-insert')),
          )
          .data,
      'Completion variable · insert `job`',
    );
  });

  testWidgets('updates completion preview from keyboard selection', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'completion-preview-keymap.styio',
        text: '',
        revision: 0,
      ),
    );

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('source-completion-preview-title')),
          )
          .data,
      '@import',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('source-completion-preview-detail')),
          )
          .data,
      'Declare a top-level Styio import.',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('source-completion-preview-title')),
          )
          .data,
      '#function',
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('source-completion-preview-insert')),
          )
          .data,
      'Insert `#main := () => {\\n  <| 0\\n}`',
    );
  });

  testWidgets('opens quick fix lookup from editor keymap', (tester) async {
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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-quick-fix-lookup')),
      findsOneWidget,
    );
    expect(find.text('Context Actions'), findsOneWidget);
    expect(find.text('Insert assignment'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('source-quick-fix-preview')),
      findsOneWidget,
    );
    expect(find.text('Preview 1 edit'), findsOneWidget);
    expect(find.text('Insert ` = value` at 1:11'), findsOneWidget);
    expect(bootstrap.editorController.document.text, text);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(bootstrap.editorController.document.text, 'let stream = value\n');
    expect(find.byKey(const ValueKey('source-quick-fix-lookup')), findsNothing);
  });

  testWidgets('opens add-argument-names intention from editor keymap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = '''
fn blend(left: f64, right: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
blend(price, tax) -> @stdout
''';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'argument-name-intention.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.lastIndexOf('price, tax'));

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-quick-fix-lookup')),
      findsOneWidget,
    );
    expect(find.text('Add argument names'), findsOneWidget);
    expect(find.text('Add left: to argument'), findsOneWidget);
    expect(find.text('Preview 2 edits'), findsOneWidget);
    expect(bootstrap.editorController.document.text, text);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(bootstrap.editorController.document.text, '''
fn blend(left: f64, right: f64) {
  emit left + right
}
price = 1.0
tax = 0.5
blend(left: price, right: tax) -> @stdout
''');
    expect(find.byKey(const ValueKey('source-quick-fix-lookup')), findsNothing);
  });

  testWidgets('applies unused parameter quick fix from editor keymap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text =
        'fn blend(left: f64, right: f64) {\n'
        '  emit left\n'
        '}\n'
        'value = blend(price, tax)\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'unused-parameter-quickfix.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('right') + 2);

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('source-quick-fix-lookup')), findsOne);
    expect(find.text('Remove unused parameter'), findsOne);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      bootstrap.editorController.document.text,
      'fn blend(left: f64) {\n'
      '  emit left\n'
      '}\n'
      'value = blend(price)\n',
    );
  });

  testWidgets('opens safe delete blockers from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'used = 1\nused -> @stdout\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'safe-delete-blocked.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('used'));

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('source-safe-delete-panel')), findsOne);
    expect(find.text('Safe Delete: used'), findsOne);
    expect(find.byKey(const ValueKey('source-safe-delete-blockers')), findsOne);
    expect(
      find.textContaining('Symbol `used` is still used in this file.'),
      findsOne,
    );
    expect(bootstrap.editorController.document.text, text);
  });

  testWidgets('applies safe delete from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'used = 1\nunused = 2\nused -> @stdout\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'safe-delete-unused.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('unused'));

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.delete);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('source-safe-delete-panel')), findsOne);
    expect(find.byKey(const ValueKey('source-safe-delete-preview')), findsOne);

    await tapVisibleKey(tester, 'source-safe-delete-apply');

    expect(
      bootstrap.editorController.document.text,
      'used = 1\nused -> @stdout\n',
    );
    expect(
      find.byKey(const ValueKey('source-safe-delete-panel')),
      findsNothing,
    );
  });

  testWidgets('opens inline variable blockers from source keymap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'let pending\npending -> @stdout\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'inline-variable-blocked.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('pending'));

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-inline-variable-panel')),
      findsOne,
    );
    expect(find.text('Inline Variable: pending'), findsOne);
    expect(
      find.byKey(const ValueKey('source-inline-variable-blockers')),
      findsOne,
    );
    expect(
      find.textContaining(
        'Inline variable requires a declaration initializer.',
      ),
      findsOne,
    );
    expect(bootstrap.editorController.document.text, text);
  });

  testWidgets('applies inline variable from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'seed = 40 + 2\nvalue = seed\nseed -> @stdout\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'inline-variable.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('seed'));

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-inline-variable-panel')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('source-inline-variable-preview')),
      findsOne,
    );

    await tapVisibleKey(tester, 'source-inline-variable-apply');

    expect(
      bootstrap.editorController.document.text,
      'value = 40 + 2\n40 + 2 -> @stdout\n',
    );
    expect(
      find.byKey(const ValueKey('source-inline-variable-panel')),
      findsNothing,
    );
  });

  testWidgets('opens introduce variable blockers from source keymap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = 40 + 2\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'introduce-variable-blocked.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectRange(
      baseOffset: text.indexOf('value'),
      extentOffset: text.indexOf('value') + 'value'.length,
    );

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-introduce-variable-panel')),
      findsOne,
    );
    expect(find.text('Introduce Variable'), findsOne);
    expect(
      find.textContaining(
        'Cannot introduce a variable from an assignment target.',
      ),
      findsOne,
    );
    expect(bootstrap.editorController.document.text, text);
  });

  testWidgets('applies introduce variable from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = 40 + 2\n';
    final start = text.indexOf('40 + 2');
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'introduce-variable.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectRange(
      baseOffset: start,
      extentOffset: start + '40 + 2'.length,
    );

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-introduce-variable-panel')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('source-introduce-variable-input')),
      findsOne,
    );

    await tapVisibleKey(tester, 'source-introduce-variable-apply');

    expect(
      bootstrap.editorController.document.text,
      'extractedValue = 40 + 2\nvalue = extractedValue\n',
    );
    expect(
      find.byKey(const ValueKey('source-introduce-variable-panel')),
      findsNothing,
    );
  });

  testWidgets('opens extract function blockers from source keymap', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'value = 40 + 2\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'extract-function-blocked.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectRange(
      baseOffset: text.indexOf('value'),
      extentOffset: text.indexOf('value') + 'value'.length,
    );

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-extract-function-panel')),
      findsOne,
    );
    expect(find.text('Extract Function'), findsOne);
    expect(
      find.textContaining(
        'Cannot extract a function from an assignment target.',
      ),
      findsOne,
    );
    expect(bootstrap.editorController.document.text, text);
  });

  testWidgets('applies extract function from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text =
        'fn main(user) {\n  first = user + 1\n  second = user + 1\n}\n';
    final start = text.indexOf('user + 1');
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'extract-function.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectRange(
      baseOffset: start,
      extentOffset: start + 'user + 1'.length,
    );

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-extract-function-panel')),
      findsOne,
    );
    expect(
      find.byKey(const ValueKey('source-extract-function-preview')),
      findsOne,
    );
    expect(
      find.text(
        'Replace selection and 1 duplicate with `extractedFunction(user)`',
      ),
      findsOne,
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(
      bootstrap.editorController.document.text,
      '#extractedFunction := (user) => {\n'
      '  <| user + 1\n'
      '}\n'
      '\n'
      'fn main(user) {\n'
      '  first = extractedFunction(user)\n'
      '  second = extractedFunction(user)\n'
      '}\n',
    );
    expect(
      find.byKey(const ValueKey('source-extract-function-panel')),
      findsNothing,
    );
  });

  testWidgets('applies change signature from source keymap', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text =
        'fn blend(left: f64, right: f64) {\n'
        '  result = left + right\n'
        '}\n'
        'value = blend(price, tax)\n'
        'again = blend(right: fee, left: total)\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'change-signature.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('blend') + 1);

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('source-change-signature-panel')),
      findsOne,
    );
    expect(find.text('Change Signature'), findsOne);
    expect(
      find.byKey(const ValueKey('source-change-signature-preview')),
      findsOne,
    );
    expect(
      find.text('Change `blend(left, right)` to `blend(left, right)`'),
      findsOne,
    );

    await tester.enterText(
      find.byKey(const ValueKey('source-change-signature-name-input')),
      'combine',
    );
    await tester.enterText(
      find.byKey(const ValueKey('source-change-signature-parameters-input')),
      'right, left',
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Change `blend(left, right)` to `combine(right, left)`'),
      findsOne,
    );

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(
      bootstrap.editorController.document.text,
      'fn combine(right: f64, left: f64) {\n'
      '  result = left + right\n'
      '}\n'
      'value = combine(tax, price)\n'
      'again = combine(right: fee, left: total)\n',
    );
    expect(
      find.byKey(const ValueKey('source-change-signature-panel')),
      findsNothing,
    );
  });

  testWidgets('removes a parameter from change signature', (tester) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text =
        'fn blend(left: f64, right: f64) {\n'
        '  emit left\n'
        '}\n'
        'value = blend(price, tax)\n'
        'again = blend(total, fee)\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'change-signature-remove-parameter.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('blend') + 1);

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('source-change-signature-parameters-input')),
      'left',
    );
    await tester.pumpAndSettle();

    expect(find.text('Change `blend(left, right)` to `blend(left)`'), findsOne);

    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(
      bootstrap.editorController.document.text,
      'fn blend(left: f64) {\n'
      '  emit left\n'
      '}\n'
      'value = blend(price)\n'
      'again = blend(total)\n',
    );
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

    await pumpVityoApp(tester, bootstrap);

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
    await tapVisibleKey(tester, 'language-apply-rename');

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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

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

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('source-inline-rename-input')),
      '1bad',
    );
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pump();

    expect(bootstrap.editorController.document.text, text);
    expect(find.byKey(const ValueKey('source-inline-rename-panel')), findsOne);
    expect(find.text('Invalid rename target.'), findsOne);
  });

  testWidgets('keeps inline rename open for conflicting identifiers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 1200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final bootstrap = await createBootstrap(PlatformTarget.macos);
    const text = 'price = 1\ntotal = price\ntotal -> @stdout\n';
    bootstrap.editorController.loadDocument(
      const DocumentState(
        documentId: 'inline-rename-conflict.styio',
        text: text,
        revision: 0,
      ),
    );
    bootstrap.editorController.selectCollapsed(text.indexOf('price'));

    await pumpVityoApp(tester, bootstrap);
    await focusSourceBuffer(tester, bootstrap.editorController);

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.f6);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('source-inline-rename-input')),
      'total',
    );
    await tapVisibleKey(tester, 'source-inline-rename-apply');

    expect(bootstrap.editorController.document.text, text);
    expect(find.byKey(const ValueKey('source-inline-rename-panel')), findsOne);
    expect(
      find.text(
        'Name `total` already declares a current-file variable. '
        'Conflict at 2:1.',
      ),
      findsOne,
    );
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

    await pumpVityoApp(tester, bootstrap);

    await focusSourceBuffer(tester, bootstrap.editorController);
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

class _ShellScaffoldHarness extends StatefulWidget {
  const _ShellScaffoldHarness({required this.bootstrap});

  final AppBootstrap bootstrap;

  @override
  State<_ShellScaffoldHarness> createState() => _ShellScaffoldHarnessState();
}

class _ShellScaffoldHarnessState extends State<_ShellScaffoldHarness> {
  late final ShellModel _shellModel;

  @override
  void initState() {
    super.initState();
    final bootstrap = widget.bootstrap;
    _shellModel = ShellModel(
      platformTarget: bootstrap.platformTarget,
      supplementalAdapterCapabilities:
          bootstrap.supplementalAdapterCapabilities,
      projectGraphAdapter: bootstrap.projectGraphAdapter,
      workspaceController: bootstrap.workspaceController,
      workspaceDocumentStore: bootstrap.workspaceDocumentStore,
      moduleRegistry: bootstrap.moduleRegistry,
      nativeModuleLoader: bootstrap.nativeModuleLoader,
      editorController: bootstrap.editorController,
      executionAdapter: bootstrap.executionAdapter,
      executionAdapterFactory: bootstrap.executionAdapterFactory,
      runtimeEventAdapter: bootstrap.runtimeEventAdapter,
      dependencySourceAdapter: bootstrap.dependencySourceAdapter,
      deploymentAdapter: bootstrap.deploymentAdapter,
      toolchainManagementAdapter: bootstrap.toolchainManagementAdapter,
      agentCodingController: bootstrap.agentCodingController,
      agentProviderConfigurator: bootstrap.agentProviderConfigurator,
      toolchainManager: bootstrap.toolchainManager,
      languageServiceStatus: bootstrap.languageServiceStatus,
      toolchainStatusReport: bootstrap.toolchainStatusReport,
    );
  }

  @override
  void dispose() {
    _shellModel.dispose();
    widget.bootstrap.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ShellScope(
      model: _shellModel,
      child: MaterialApp(
        title: 'Vityo shell scaffold harness',
        debugShowCheckedModeBanner: false,
        theme: VityoTheme.light(),
        home: const VityoShellScaffold(),
      ),
    );
  }
}
