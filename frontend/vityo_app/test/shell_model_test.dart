import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/editor/session/editor_session_data_store.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_configuration_store.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_install_executor.dart'
    show ToolchainInstallExecutionStatus;
import 'package:vityo_app/src/view_ide/toolchain/toolchain_install_policy.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_manager.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_resolver.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/module_host/module_registry.dart';
import 'package:vityo_app/src/platform/native_module_loader.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  Future<ConfigurationStore> createConfigurationStore(Directory root) async {
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: root.path,
        homePath: root.path,
      ),
    );
    return ConfigurationStore(
      dataStore: FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      ),
      credentialDataStore: InMemoryCredentialDataStore(),
    );
  }

  Future<PlatformManagerBundle> createTestPlatformManagers() {
    final context = PlatformContextSnapshot.compose(
      targetId: 'shell-toolchain-selection',
      fileSystem: FileSystemFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
        defaultShellPath: '/bin/sh',
      ),
      process: ProcessFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      resource: ResourceFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      network: NetworkFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      clipboard: ClipboardFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      notification: NotificationFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      localService: LocalServiceFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      pty: PtyFacts.linuxDebianArm(targetId: 'shell-toolchain-selection'),
    );
    return createPlatformManagerBundle(platformContext: context);
  }

  test('persists editor session through shell runtime store', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_shell_editor_session_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final dataStore = FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
    );
    final editorSessionDataStore = EditorSessionDataStore.fromDataStore(
      dataStore: dataStore,
    );
    final initialGraph = _projectGraph(
      compilerVersion: '0.0.1',
      compilePlanReady: false,
    );
    final shell = ShellModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _SequenceProjectGraphAdapter(
        snapshots: <ProjectGraphSnapshot>[initialGraph],
      ),
      workspaceController: WorkspaceController(projectSnapshot: initialGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: EditorSessionController.seedDocumentForPath(
          initialGraph.editorFiles.first,
        ),
        languageService: const SimpleStyioLanguageService(),
      ),
      executionAdapter: const _SuccessfulExecutionAdapter(
        sessionId: 'shell-editor-session',
      ),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          const _SuccessfulExecutionAdapter(sessionId: 'shell-editor-session'),
      runtimeEventAdapter: createRuntimeEventAdapter(
        platformTarget: PlatformTarget.macos,
      ),
      dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
      deploymentAdapter: const _SuccessfulDeploymentAdapter(),
      toolchainManagementAdapter: const _SuccessfulToolchainManagementAdapter(),
      editorSessionDataStore: editorSessionDataStore,
      editorSessionWorkspaceId: 'demo',
    );
    addTearDown(shell.dispose);

    shell.editorController.selectRange(baseOffset: 1, extentOffset: 4);
    await shell.persistEditorSession();
    shell.editorController.selectCollapsed(0);
    final restoredSnapshot = await shell.restoreEditorSession();

    final restored = await editorSessionDataStore.readSession(
      workspaceId: 'demo',
    );

    expect(restoredSnapshot?.activeDocumentId, initialGraph.editorFiles.first);
    expect(restored?.activeDocumentId, initialGraph.editorFiles.first);
    expect(restored?.openDocumentIds, contains(initialGraph.editorFiles.first));
    expect(restored?.cursorOffsets[initialGraph.editorFiles.first], 4);
    expect(restored?.selectionAnchors[initialGraph.editorFiles.first], 1);
    expect(shell.editorController.selection.start, 1);
    expect(shell.editorController.selection.end, 4);
    expect(
      shell.debugLog.any((entry) => entry.contains('Editor session persisted')),
      isTrue,
    );
    expect(
      shell.debugLog.any((entry) => entry.contains('Editor session restored')),
      isTrue,
    );
  });

  test(
    'restores editor session active document through workspace route',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'vityo-editor-session-restore-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempDir.path,
          homePath: tempDir.path,
        ),
      );
      final dataStore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      final editorSessionDataStore = EditorSessionDataStore.fromDataStore(
        dataStore: dataStore,
      );
      const firstDocumentPath = '/workspace/demo/src/main.styio';
      const secondDocumentPath = '/workspace/demo/src/feature.styio';
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.1',
        compilePlanReady: false,
        editorFiles: const <String>[firstDocumentPath, secondDocumentPath],
      );
      await editorSessionDataStore.saveSession(
        workspaceId: 'demo',
        snapshot: const EditorSessionSnapshot(
          activeDocumentId: secondDocumentPath,
          openDocumentIds: <String>[firstDocumentPath, secondDocumentPath],
          cursorOffsets: <String, int>{secondDocumentPath: 4},
          selectionAnchors: <String, int>{secondDocumentPath: 1},
        ),
      );
      final workspaceController = WorkspaceController(
        projectSnapshot: initialGraph,
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: workspaceController,
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: <String, DocumentState>{
            secondDocumentPath: const DocumentState(
              documentId: secondDocumentPath,
              text: 'feature',
              revision: 0,
            ),
          },
        ),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            firstDocumentPath,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: const _SuccessfulExecutionAdapter(
          sessionId: 'shell-editor-session-restore',
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            const _SuccessfulExecutionAdapter(
              sessionId: 'shell-editor-session-restore',
            ),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
        editorSessionDataStore: editorSessionDataStore,
        editorSessionWorkspaceId: 'demo',
      );
      addTearDown(shell.dispose);

      final restoredSnapshot = await shell.restoreEditorSession();

      expect(restoredSnapshot?.activeDocumentId, secondDocumentPath);
      expect(workspaceController.activeFilePath, secondDocumentPath);
      expect(shell.editorController.document.documentId, secondDocumentPath);
      expect(shell.editorController.selection.start, 1);
      expect(shell.editorController.selection.end, 4);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Editor session restored'),
        ),
        isTrue,
      );
    },
  );

  test(
    'successful toolchain switch refreshes project graph and execution route',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.1',
        compilePlanReady: false,
      );
      final refreshedGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      const requirement = ToolchainRequirement(kind: ToolchainKind.runner);
      final toolchainReport = ValueNotifier<ToolchainManagerStatusReport>(
        const ToolchainManagerStatusReport(
          status: ToolchainManagerStatus.ready,
          snapshot: ToolchainStateSnapshot(
            targetId: 'shell-model',
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
          resolution: ToolchainResolution(
            status: ToolchainResolutionStatus.resolved,
            requirement: requirement,
            descriptor: ToolchainDescriptor(
              id: 'styio-runner',
              kind: ToolchainKind.runner,
              displayName: 'Styio Runner',
              executablePath: '/opt/styio/bin/styio',
              version: '0.0.8',
              channel: 'nightly',
            ),
          ),
        ),
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[refreshedGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _RefreshAwareExecutionAdapter(
          projectGraph: initialGraph,
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
        toolchainStatusReport: toolchainReport,
      );
      addTearDown(toolchainReport.dispose);
      addTearDown(shell.dispose);

      final result = await shell.useManagedCompiler(
        compilerVersion: '0.0.5',
        channel: 'stable',
      );

      expect(result.succeeded, isTrue);
      expect(
        shell.workspaceController.activeProject.activeCompiler?.compilerVersion,
        '0.0.5',
      );
      final cliCapability = shell.adapterCapabilities.firstWhere(
        (snapshot) => snapshot.adapterKind == AdapterKind.cli,
      );
      expect(cliCapability.execution.level, AdapterCapabilityLevel.available);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Project graph refreshed'),
        ),
        isTrue,
      );
      expect(shell.toolchainStatusSurface.source, 'manager-report');
      expect(shell.toolchainStatusSurface.version, '0.0.8');
    },
  );

  test('successful publish preflight is stored as deployment state', () async {
    final initialGraph = _projectGraph(
      compilerVersion: '0.0.5',
      compilePlanReady: true,
    );
    final shell = ShellModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _SequenceProjectGraphAdapter(
        snapshots: <ProjectGraphSnapshot>[initialGraph],
      ),
      workspaceController: WorkspaceController(projectSnapshot: initialGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: EditorSessionController.seedDocumentForPath(
          initialGraph.editorFiles.first,
        ),
        languageService: const SimpleStyioLanguageService(),
      ),
      executionAdapter: _RefreshAwareExecutionAdapter(
        projectGraph: initialGraph,
      ),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
      runtimeEventAdapter: createRuntimeEventAdapter(
        platformTarget: PlatformTarget.macos,
      ),
      dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
      deploymentAdapter: const _SuccessfulDeploymentAdapter(),
      toolchainManagementAdapter: const _SuccessfulToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    final result = await shell.preparePublish(packageName: 'demo/app');

    expect(result.succeeded, isTrue);
    expect(shell.lastDeploymentCommand, same(result));
    expect(
      shell.debugLog.any((entry) => entry.contains('deploy package: demo/app')),
      isTrue,
    );
    expect(
      shell.debugLog.any((entry) => entry.contains('deploy archive:')),
      isTrue,
    );
  });

  test(
    'toolchain and deployment commands dispatch through shell command flow',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final refreshedGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[refreshedGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _RefreshAwareExecutionAdapter(
          projectGraph: initialGraph,
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      await shell.executeCommand(AppCommandId.useActiveCompiler);
      await shell.executeCommand(AppCommandId.preparePublish);

      expect(shell.lastToolchainCommand?.command, 'tool use');
      expect(shell.lastToolchainCommand?.succeeded, isTrue);
      expect(shell.lastDeploymentCommand?.command, 'publish');
      expect(shell.lastDeploymentCommand?.succeeded, isTrue);
      expect(
        shell.debugLog.any((entry) => entry.contains('tool use succeeded')),
        isTrue,
      );
      expect(
        shell.debugLog.any((entry) => entry.contains('publish succeeded')),
        isTrue,
      );

      await shell.handleToolchainRecoveryAction(
        const ToolchainRecoveryAction(
          id: 'show-toolchain-logs',
          label: 'Show logs',
          description: 'Open the latest toolchain command logs.',
        ),
      );

      expect(shell.activeBottomTab, BottomSurfaceTab.debug);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Toolchain log view requested'),
        ),
        isTrue,
      );
    },
  );

  test(
    'command palette, quick open, locations, links, highlights, declarations, '
    'definitions, implementation, type hierarchy, outline, rename, symbols, '
    'usages, calls, search, problems, actions, and settings commands select '
    'shell bottom surfaces',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _RefreshAwareExecutionAdapter(
          projectGraph: initialGraph,
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      await shell.executeCommand(AppCommandId.quickOpen);

      expect(shell.activeBottomTab, BottomSurfaceTab.navigate);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Quick Open route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.commandPalette);

      expect(shell.activeBottomTab, BottomSurfaceTab.commandPalette);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Command Palette route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.showRecentLocations);

      expect(shell.activeBottomTab, BottomSurfaceTab.locations);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Recent Locations route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.showWorkspaceDocumentLinks);

      expect(shell.activeBottomTab, BottomSurfaceTab.documentLinks);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Document Links route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.showWorkspaceDocumentHighlights);

      expect(shell.activeBottomTab, BottomSurfaceTab.documentHighlights);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Document Highlights route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.showWorkspaceCodeLenses);

      expect(shell.activeBottomTab, BottomSurfaceTab.codeLenses);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Code Lens route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.goToWorkspaceDeclaration);

      expect(shell.activeBottomTab, BottomSurfaceTab.declarations);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Go to Declaration route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.goToWorkspaceDefinition);

      expect(shell.activeBottomTab, BottomSurfaceTab.definitions);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Go to Definition route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.goToWorkspaceTypeDefinition);

      expect(shell.activeBottomTab, BottomSurfaceTab.typeDefinitions);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Go to Type Definition route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.goToWorkspaceImplementation);

      expect(shell.activeBottomTab, BottomSurfaceTab.implementations);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Go to Implementation route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.showWorkspaceTypeHierarchy);

      expect(shell.activeBottomTab, BottomSurfaceTab.typeHierarchy);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Type Hierarchy route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.showWorkspaceOutline);

      expect(shell.activeBottomTab, BottomSurfaceTab.outline);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Outline route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.renameWorkspaceSymbol);

      expect(shell.activeBottomTab, BottomSurfaceTab.rename);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Rename Symbol route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.searchWorkspaceSymbols);

      expect(shell.activeBottomTab, BottomSurfaceTab.symbols);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Symbols route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.findWorkspaceReferences);

      expect(shell.activeBottomTab, BottomSurfaceTab.usages);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Find Usages route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.showWorkspaceCallHierarchy);

      expect(shell.activeBottomTab, BottomSurfaceTab.calls);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Call Hierarchy route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.searchWorkspace);

      expect(shell.activeBottomTab, BottomSurfaceTab.search);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Workspace search surface opened'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.showWorkspaceProblems);

      expect(shell.activeBottomTab, BottomSurfaceTab.problems);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Problems route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.showWorkspaceCodeActions);

      expect(shell.activeBottomTab, BottomSurfaceTab.actions);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Code Actions route requested'),
        ),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.openSettings);

      expect(shell.activeBottomTab, BottomSurfaceTab.settings);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Settings surface opened'),
        ),
        isTrue,
      );
    },
  );

  test(
    'toolchain candidate selection reports unavailable without manager',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _RefreshAwareExecutionAdapter(
          projectGraph: initialGraph,
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      final result = await shell.selectToolchainCandidate('styio-service');

      expect(result, isNull);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Toolchain selection unavailable'),
        ),
        isTrue,
      );
    },
  );

  test(
    'toolchain candidate selection activates catalog through manager',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_shell_toolchain_selection_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );
      final manager = ToolchainManager(
        configurationStore: toolchainStore,
        platformManagers: await createTestPlatformManagers(),
        workspaceId: 'demo',
      );
      await manager.registerToolchain(
        const ToolchainDescriptor(
          id: 'styio-service',
          kind: ToolchainKind.languageService,
          displayName: 'Styio Service',
          executablePath: '/opt/styio/bin/styio-service',
          version: '0.0.9',
          channel: 'nightly',
        ),
      );
      final toolchainReport = ValueNotifier<ToolchainManagerStatusReport>(
        await manager.statusReport(kind: ToolchainKind.languageService),
      );
      addTearDown(toolchainReport.dispose);
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _RefreshAwareExecutionAdapter(
          projectGraph: initialGraph,
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
        toolchainManager: manager,
        toolchainStatusReport: toolchainReport,
      );
      addTearDown(shell.dispose);

      expect(
        (await manager.loadCatalog()).active(ToolchainKind.languageService),
        isNull,
      );

      final result = await shell.selectToolchainCandidate('styio-service');

      expect(result?.status, ToolchainSelectionStatus.selected);
      expect(
        (await manager.loadCatalog()).active(ToolchainKind.languageService)?.id,
        'styio-service',
      );
      expect(
        toolchainReport.value.snapshot
            .active(ToolchainKind.languageService)
            ?.id,
        'styio-service',
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Toolchain selected: styio-service'),
        ),
        isTrue,
      );

      final clearResult = await shell.clearToolchainCandidate(
        ToolchainKind.languageService,
      );

      expect(clearResult?.status, ToolchainSelectionStatus.cleared);
      expect(
        (await manager.loadCatalog()).active(ToolchainKind.languageService),
        isNull,
      );
      expect(
        toolchainReport.value.snapshot.active(ToolchainKind.languageService),
        isNull,
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains(
            'Toolchain active selection cleared: language-service',
          ),
        ),
        isTrue,
      );

      await shell.handleToolchainRecoveryAction(
        const ToolchainRecoveryAction(
          id: 'install-managed-toolchain',
          label: 'Install managed toolchain',
          description: 'Prepare a toolchain installation plan.',
        ),
      );

      expect(
        shell.lastToolchainInstallPlan?.status,
        ToolchainInstallPlanStatus.planned,
      );
      expect(
        shell.lastToolchainInstallPlan?.mode,
        ToolchainInstallMode.manualSelection,
      );
      expect(shell.toolchainInstallPlanSurface?.mode, 'manualSelection');
      expect(shell.toolchainInstallPlanSurface?.kind, 'language-service');
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Toolchain install plan planned'),
        ),
        isTrue,
      );

      final execution = await shell.executeLastToolchainInstallPlan();

      expect(
        execution?.status,
        ToolchainInstallExecutionStatus.requiresUserAction,
      );
      expect(
        shell.toolchainInstallExecutionSurface?.status,
        'requiresUserAction',
      );
      expect(
        toolchainReport.value.installHistory?.entries.first.status,
        'requiresUserAction',
      );
      expect(
        shell.debugLog.any(
          (entry) =>
              entry.contains('Toolchain install execution requiresUserAction'),
        ),
        isTrue,
      );
    },
  );

  test(
    'vendor command dispatch refreshes project graph and stores source state',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final refreshedGraph =
          _projectGraph(
            compilerVersion: '0.0.5',
            compilePlanReady: true,
          ).copyWith(
            sourceState: const ProjectSourceStateSnapshot(
              schemaVersion: 1,
              vendor: VendorSourceStateSnapshot(
                vendorRoot: '/workspace/demo/.pafio/vendor',
                metadataPath: '/workspace/demo/.pafio/vendor/pafio-vendor.json',
                vendorPresent: true,
                metadataPresent: true,
                gitSnapshots: 1,
              ),
            ),
          );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[refreshedGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _RefreshAwareExecutionAdapter(
          projectGraph: initialGraph,
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      await shell.executeCommand(AppCommandId.vendorDependencies);

      expect(shell.lastDependencySourceCommand?.succeeded, isTrue);
      expect(shell.lastDependencySourceCommand?.command, 'vendor');
      expect(
        shell
            .workspaceController
            .activeProject
            .sourceState
            ?.vendor
            .gitSnapshots,
        1,
      );
      expect(
        shell.debugLog.any((entry) => entry.contains('vendor metadata:')),
        isTrue,
      );
    },
  );

  test(
    'run command logs runtime event summaries for published sessions',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      recordRuntimeEventsForSession(
        'shell-runtime-session',
        <RuntimeEventEnvelope>[
          RuntimeEventEnvelope(
            schemaVersion: 1,
            sessionId: 'shell-runtime-session',
            sequence: 1,
            timestamp: DateTime.utc(2026, 4, 17, 0, 0, 0),
            eventKind: 'compile.started',
            origin: 'styio.compile-plan',
            payload: const <String, Object?>{'intent': 'run'},
          ),
          RuntimeEventEnvelope(
            schemaVersion: 1,
            sessionId: 'shell-runtime-session',
            sequence: 2,
            timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
            eventKind: 'run.finished',
            origin: 'styio.runtime',
            payload: const <String, Object?>{'success': true},
          ),
        ],
      );
      addTearDown(() => clearRuntimeEventsForSession('shell-runtime-session'));

      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: const _SuccessfulExecutionAdapter(
          sessionId: 'shell-runtime-session',
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            const _SuccessfulExecutionAdapter(
              sessionId: 'shell-runtime-session',
            ),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      await shell.executeCommand(AppCommandId.run);

      expect(shell.lastExecutionSession?.sessionId, 'shell-runtime-session');
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('runtime events: 2 event(s)'),
        ),
        isTrue,
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('runtime: compile.started'),
        ),
        isTrue,
      );
      expect(
        shell.debugLog.any((entry) => entry.contains('runtime: run.finished')),
        isTrue,
      );
    },
  );

  test(
    'toolchain command variants and recovery actions dispatch through shell flow',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final refreshedGraph = _projectGraph(
        compilerVersion: '0.0.6',
        compilePlanReady: true,
      );
      final shell = _createShell(
        initialGraph: initialGraph,
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: List<ProjectGraphSnapshot>.filled(6, refreshedGraph),
        ),
      );
      addTearDown(shell.dispose);

      await shell.executeCommand(AppCommandId.pinActiveCompiler);
      await shell.executeCommand(AppCommandId.clearPinnedCompiler);
      await shell.executeCommand(AppCommandId.packProject);
      await shell.executeCommand(AppCommandId.refreshModules);
      await shell.installManagedCompiler(
        styioBinaryPath: '/opt/styio/bin/styio',
      );
      await shell.handleToolchainRecoveryAction(
        const ToolchainRecoveryAction(
          id: 'select-existing-toolchain',
          label: 'Select toolchain',
          description: 'Open toolchain selection.',
        ),
      );
      await shell.handleToolchainRecoveryAction(
        const ToolchainRecoveryAction(
          id: 'use-degraded-mode',
          label: 'Use degraded mode',
          description: 'Continue without a managed toolchain.',
        ),
      );
      await shell.handleToolchainRecoveryAction(
        const ToolchainRecoveryAction(
          id: 'fix-toolchain-precondition',
          label: 'Fix precondition',
          description: 'Resolve missing manifest state.',
        ),
      );
      await shell.handleToolchainRecoveryAction(
        const ToolchainRecoveryAction(
          id: 'retry-tool-use',
          label: 'Retry use',
          description: 'Retry tool use command.',
        ),
      );
      await shell.handleToolchainRecoveryAction(
        const ToolchainRecoveryAction(
          id: 'retry-tool-pin',
          label: 'Retry pin',
          description: 'Retry tool pin command.',
        ),
      );
      await shell.handleToolchainRecoveryAction(
        const ToolchainRecoveryAction(
          id: 'unknown-recovery-action',
          label: 'Unknown',
          description: 'Exercise unknown recovery branch.',
        ),
      );

      expect(shell.lastToolchainCommand?.succeeded, isTrue);
      expect(shell.lastDeploymentCommand?.command, 'pack');
      expect(
        shell.debugLog.any((entry) => entry.contains('tool install succeeded')),
        isTrue,
      );
      expect(
        shell.debugLog.any((entry) => entry.contains('Native bridge')),
        isTrue,
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Toolchain selection route requested'),
        ),
        isTrue,
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Toolchain recovery action is not wired'),
        ),
        isTrue,
      );
    },
  );

  test(
    'shell session and file binding edge states log unavailable paths',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final shell = _createShell(initialGraph: initialGraph);
      addTearDown(shell.dispose);

      final acceptedSnapshot = shell.acceptEditorExternalChange();
      await shell.persistEditorSession();
      final restoredSnapshot = await shell.restoreEditorSession();

      expect(acceptedSnapshot.document, shell.editorController.document);
      expect(restoredSnapshot, isNull);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Editor session persistence unavailable'),
        ),
        isTrue,
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Editor session restore unavailable'),
        ),
        isTrue,
      );
    },
  );

  test('save command logs blocked resource-store failures', () async {
    final initialGraph = _projectGraph(
      compilerVersion: '0.0.5',
      compilePlanReady: true,
    );
    final shell = _createShell(
      initialGraph: initialGraph,
      workspaceDocumentStore: const _FailingSaveWorkspaceDocumentStore(),
    );
    addTearDown(shell.dispose);

    shell.editorController.insertText('changed');
    await shell.executeCommand(AppCommandId.save);

    expect(
      shell.debugLog.any((entry) => entry.contains('Save blocked for')),
      isTrue,
    );
    expect(
      shell.debugLog.any((entry) => entry.contains('Unable to save')),
      isTrue,
    );
  });

  test(
    'deployment and toolchain command blockers report platform and package state',
    () {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final iosShell = _createShell(
        platformTarget: PlatformTarget.ios,
        initialGraph: initialGraph,
      );
      addTearDown(iosShell.dispose);

      expect(
        iosShell.blockedReasonForCommand(AppCommandId.useActiveCompiler),
        contains('does not expose local pafio toolchain management'),
      );
      expect(
        iosShell.blockedReasonForCommand(AppCommandId.preparePublish),
        contains('does not expose local pafio deployment commands'),
      );

      final blockedDistributionShell = _createShell(
        initialGraph: initialGraph.copyWith(
          packageDistribution: const PackageDistributionSnapshot(
            schemaVersion: 1,
            packages: <PackageDistributionPackageSnapshot>[
              PackageDistributionPackageSnapshot(
                packageName: 'demo/core',
                manifestPath: '/workspace/demo/pafio.toml',
                publishEnabled: false,
                publishReady: false,
                blockingReasons: <String>['publish disabled'],
              ),
              PackageDistributionPackageSnapshot(
                packageName: 'demo/cli',
                manifestPath: '/workspace/demo/cli/pafio.toml',
                publishEnabled: true,
                publishReady: false,
              ),
            ],
          ),
        ),
      );
      addTearDown(blockedDistributionShell.dispose);

      expect(
        blockedDistributionShell.blockedReasonForCommand(
          AppCommandId.preparePublish,
        ),
        allOf(contains('No publish-ready package'), contains('demo/core')),
      );

      final ambiguousDistributionShell = _createShell(
        initialGraph: initialGraph.copyWith(
          packageDistribution: const PackageDistributionSnapshot(
            schemaVersion: 1,
            packages: <PackageDistributionPackageSnapshot>[
              PackageDistributionPackageSnapshot(
                packageName: 'demo/core',
                manifestPath: '/workspace/demo/pafio.toml',
                publishEnabled: true,
                publishReady: true,
              ),
              PackageDistributionPackageSnapshot(
                packageName: 'demo/cli',
                manifestPath: '/workspace/demo/cli/pafio.toml',
                publishEnabled: true,
                publishReady: true,
              ),
            ],
          ),
        ),
      );
      addTearDown(ambiguousDistributionShell.dispose);

      expect(
        ambiguousDistributionShell.blockedReasonForCommand(
          AppCommandId.preparePublish,
        ),
        contains('Multiple publish-ready packages'),
      );
    },
  );

  test(
    'editor session restore handles empty, missing, and cursor-only snapshots',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_shell_editor_session_edges_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final store = EditorSessionDataStore.fromDataStore(
        dataStore: FoundationDataStore(
          resourceCoordinator: FoundationResourceCoordinator(
            resourceManager: LocalResourceManager(
              facts: ResourceFacts.linuxDebianArm(
                systemTempPath: tempRoot.path,
                homePath: tempRoot.path,
              ),
            ),
            fileSystemManager: fileSystemManager,
          ),
          fileSystemManager: fileSystemManager,
        ),
      );
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final shell = _createShell(
        initialGraph: initialGraph,
        editorSessionDataStore: store,
        editorSessionWorkspaceId: 'session-edge',
      );
      addTearDown(shell.dispose);

      expect(await shell.restoreEditorSession(), isNull);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('No editor session snapshot'),
        ),
        isTrue,
      );

      await store.saveSession(
        workspaceId: 'session-edge',
        snapshot: const EditorSessionSnapshot(
          activeDocumentId: '/workspace/demo/src/missing.styio',
          openDocumentIds: <String>['/workspace/demo/src/missing.styio'],
        ),
      );

      final missingSnapshot = await shell.restoreEditorSession();

      expect(
        missingSnapshot?.activeDocumentId,
        '/workspace/demo/src/missing.styio',
      );
      expect(
        shell.debugLog.any(
          (entry) =>
              entry.contains('document is not available in the workspace'),
        ),
        isTrue,
      );

      await store.saveSession(
        workspaceId: 'session-edge',
        snapshot: const EditorSessionSnapshot(
          activeDocumentId: '/workspace/demo/src/main.styio',
          openDocumentIds: <String>['/workspace/demo/src/main.styio'],
          cursorOffsets: <String, int>{'/workspace/demo/src/main.styio': 3},
        ),
      );

      final cursorOnlySnapshot = await shell.restoreEditorSession();

      expect(
        cursorOnlySnapshot?.activeDocumentId,
        initialGraph.editorFiles.first,
      );
      expect(shell.editorController.selection.start, 3);
      expect(shell.editorController.selection.end, 3);
    },
  );

  test('workspace navigation commands route without mutating active file', () async {
    const firstDocumentPath = '/workspace/demo/src/main.styio';
    const secondDocumentPath = '/workspace/demo/src/feature.styio';
    const firstDocumentText =
        '01234567890123456789012345678901234567890123456789'
        '01234567890123456789012345678901234567890123456789\n';
    final initialGraph = _projectGraph(
      compilerVersion: '0.0.5',
      compilePlanReady: true,
      editorFiles: const <String>[firstDocumentPath, secondDocumentPath],
    );
    final shell = _createShell(
      initialGraph: initialGraph,
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          firstDocumentPath: DocumentState(
            documentId: firstDocumentPath,
            text: firstDocumentText,
            revision: 0,
          ),
          secondDocumentPath: DocumentState(
            documentId: secondDocumentPath,
            text: 'feature document\n',
            revision: 0,
          ),
        },
      ),
    );
    addTearDown(shell.dispose);

    await shell.executeCommand(AppCommandId.navigateBack);
    await shell.executeCommand(AppCommandId.navigateForward);

    expect(shell.workspaceController.activeFilePath, firstDocumentPath);
    expect(
      shell.debugLog.any((entry) => entry.contains('Go Back route requested')),
      isTrue,
    );
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Go Forward route requested'),
      ),
      isTrue,
    );
  });

  test('shell relays language service status changes', () {
    final status = ValueNotifier<LanguageServiceStatusSurface>(
      LanguageServiceStatusSurface.refreshing(),
    );
    addTearDown(status.dispose);
    final initialGraph = _projectGraph(
      compilerVersion: '0.0.5',
      compilePlanReady: true,
    );
    final shell = _createShell(
      initialGraph: initialGraph,
      languageServiceStatus: status,
    );
    addTearDown(shell.dispose);
    var notifications = 0;
    shell.addListener(() {
      notifications += 1;
    });

    status.value = LanguageServiceStatusSurface.unavailable();

    expect(notifications, greaterThan(0));
  });
}

ShellModel _createShell({
  required ProjectGraphSnapshot initialGraph,
  PlatformTarget platformTarget = PlatformTarget.macos,
  ProjectGraphAdapter? projectGraphAdapter,
  WorkspaceDocumentStore? workspaceDocumentStore,
  WorkspaceController? workspaceController,
  ToolchainManagementAdapter toolchainManagementAdapter =
      const _SuccessfulToolchainManagementAdapter(),
  DependencySourceAdapter dependencySourceAdapter =
      const _SuccessfulDependencySourceAdapter(),
  DeploymentAdapter deploymentAdapter = const _SuccessfulDeploymentAdapter(),
  ExecutionAdapter? executionAdapter,
  ExecutionAdapterFactory? executionAdapterFactory,
  ToolchainManager? toolchainManager,
  ValueNotifier<LanguageServiceStatusSurface>? languageServiceStatus,
  ValueListenable<ToolchainManagerStatusReport>? toolchainStatusReport,
  EditorSessionDataStore? editorSessionDataStore,
  String editorSessionWorkspaceId = 'demo',
}) {
  final resolvedWorkspaceController =
      workspaceController ?? WorkspaceController(projectSnapshot: initialGraph);
  final resolvedExecutionAdapter =
      executionAdapter ??
      _RefreshAwareExecutionAdapter(projectGraph: initialGraph);
  return ShellModel(
    platformTarget: platformTarget,
    supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
    projectGraphAdapter:
        projectGraphAdapter ??
        _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
    workspaceController: resolvedWorkspaceController,
    workspaceDocumentStore:
        workspaceDocumentStore ?? InMemoryWorkspaceDocumentStore(),
    moduleRegistry: ModuleRegistry(
      platformTarget: platformTarget,
      definitions: const [],
    ),
    nativeModuleLoader: NoopNativeModuleLoader(platformTarget: platformTarget),
    editorController: EditorSessionController(
      initialDocument: EditorSessionController.seedDocumentForPath(
        resolvedWorkspaceController.activeFilePath,
      ),
      languageService: const SimpleStyioLanguageService(),
    ),
    executionAdapter: resolvedExecutionAdapter,
    executionAdapterFactory:
        executionAdapterFactory ??
        ((ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph)),
    runtimeEventAdapter: createRuntimeEventAdapter(
      platformTarget: platformTarget,
    ),
    dependencySourceAdapter: dependencySourceAdapter,
    deploymentAdapter: deploymentAdapter,
    toolchainManagementAdapter: toolchainManagementAdapter,
    toolchainManager: toolchainManager,
    languageServiceStatus: languageServiceStatus,
    toolchainStatusReport: toolchainStatusReport,
    editorSessionDataStore: editorSessionDataStore,
    editorSessionWorkspaceId: editorSessionWorkspaceId,
  );
}

ProjectGraphSnapshot _projectGraph({
  required String compilerVersion,
  required bool compilePlanReady,
  List<String> editorFiles = const <String>['/workspace/demo/src/main.styio'],
}) {
  final primaryEditorFile = editorFiles.isNotEmpty
      ? editorFiles.first
      : '/workspace/demo/src/main.styio';
  return ProjectGraphSnapshot(
    id: '/workspace/demo/pafio.toml',
    title: 'demo/app',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/demo/pafio.toml',
    toolchainPinPath: '/workspace/demo/pafio-toolchain.toml',
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: <ProjectTargetDescriptor>[
      ProjectTargetDescriptor(
        id: 'demo/app:bin:demo',
        packageName: 'demo/app',
        kind: ProjectTargetKind.bin,
        name: 'demo',
        filePath: primaryEditorFile,
      ),
    ],
    editorFiles: List<String>.unmodifiable(editorFiles),
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'Project toolchain pin discovered for shell-model testing.',
      pinPath: '/workspace/demo/pafio-toolchain.toml',
      channel: 'stable',
    ),
    lockState: ProjectLockState.unknown,
    vendorState: ProjectVendorState.present,
    activeCompiler: CompilerHandshakeSnapshot(
      binaryPath: '/toolchains/styio/bin/styio',
      tool: 'styio',
      compilerVersion: compilerVersion,
      channel: 'stable',
      variant: 'test-fixture',
      capabilities: const <String>[
        'machine_info_json',
        'single_file_entry',
        'jsonl_diagnostics',
      ],
      supportedContractVersions: <String, List<int>>{
        'machine_info': const <int>[1],
        'compile_plan': compilePlanReady ? const <int>[1] : const <int>[],
      },
      integrationPhase: compilePlanReady
          ? 'compile-plan-live'
          : 'bootstrap-single-file',
      featureFlags: <String, bool>{'compile_plan_consumer': compilePlanReady},
    ),
    notes: const <String>[],
  );
}

class _FailingSaveWorkspaceDocumentStore implements WorkspaceDocumentStore {
  const _FailingSaveWorkspaceDocumentStore();

  @override
  Future<DocumentState> loadDocument(String path) async {
    return EditorSessionController.seedDocumentForPath(path);
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    throw StateError('Unable to save test document.');
  }

  @override
  Future<bool> deleteDocument(String path) async => false;

  @override
  Future<bool> documentExists(String path) async => false;

  @override
  String? filePathForDocumentId(String documentId) => null;
}

class _SequenceProjectGraphAdapter implements ProjectGraphAdapter {
  _SequenceProjectGraphAdapter({required List<ProjectGraphSnapshot> snapshots})
    : _snapshots = List<ProjectGraphSnapshot>.of(snapshots);

  final List<ProjectGraphSnapshot> _snapshots;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot =>
      const AdapterCapabilitySnapshot(
        adapterKind: AdapterKind.cli,
        languageService: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.partial,
          detail: 'Project graph adapter does not provide language services.',
        ),
        projectGraph: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.available,
          detail: 'Published project graph payload is available.',
        ),
        execution: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Project graph adapter does not execute documents.',
        ),
        runtimeEvents: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Project graph adapter does not emit runtime events.',
        ),
      );

  @override
  Future<ProjectGraphSnapshot> loadProjectGraph() async {
    if (_snapshots.isEmpty) {
      throw StateError('No project graph snapshots remain for the test.');
    }
    return _snapshots.removeAt(0);
  }
}

class _RefreshAwareExecutionAdapter implements ExecutionAdapter {
  const _RefreshAwareExecutionAdapter({required this.projectGraph});

  final ProjectGraphSnapshot projectGraph;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cli,
    languageService: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Execution adapter does not provide language services.',
    ),
    projectGraph: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Execution adapter does not own project graph data.',
    ),
    execution: AdapterEndpointCapability(
      level: projectGraph.compilePlanConsumerAdvertised
          ? AdapterCapabilityLevel.available
          : AdapterCapabilityLevel.partial,
      detail: projectGraph.compilePlanConsumerAdvertised
          ? 'Project execution is live through published compile-plan support.'
          : 'Project execution is blocked until compile-plan support is advertised.',
    ),
    runtimeEvents: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Runtime events stay unavailable in this test fixture.',
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
      sessionId: 'shell-model-test',
      kind: 'run',
      status: ExecutionSessionStatus.blocked,
      statusMessage: 'Execution is not exercised in this shell-model test.',
      diagnostics: <Diagnostic>[],
      stdoutEvents: <ExecutionLogEvent>[],
      stderrEvents: <ExecutionLogEvent>[],
    );
  }
}

class _SuccessfulExecutionAdapter implements ExecutionAdapter {
  const _SuccessfulExecutionAdapter({required this.sessionId});

  final String sessionId;

  @override
  AdapterCapabilitySnapshot
  get capabilitySnapshot => const AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cli,
    languageService: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Execution adapter does not provide language services.',
    ),
    projectGraph: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Execution adapter does not own project graph data.',
    ),
    execution: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail:
          'Project execution is live through published compile-plan support.',
    ),
    runtimeEvents: AdapterEndpointCapability(
      level: AdapterCapabilityLevel.partial,
      detail: 'Runtime events are replayed from published artifacts.',
    ),
  );

  @override
  Future<ExecutionSession> runActiveDocument({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
  }) async {
    return ExecutionSession(
      sessionId: sessionId,
      kind: 'run',
      status: ExecutionSessionStatus.succeeded,
      statusMessage:
          'Execution completed through the shell-model test fixture.',
      diagnostics: const <Diagnostic>[],
      stdoutEvents: const <ExecutionLogEvent>[],
      stderrEvents: const <ExecutionLogEvent>[],
    );
  }
}

class _SuccessfulToolchainManagementAdapter
    implements ToolchainManagementAdapter {
  const _SuccessfulToolchainManagementAdapter();

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
      statusMessage: 'toolchain command succeeded in the shell-model fixture.',
      stdout: '',
      stderr: '',
    );
  }
}

class _SuccessfulDependencySourceAdapter implements DependencySourceAdapter {
  const _SuccessfulDependencySourceAdapter();

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
      statusMessage: '$command command succeeded in the shell-model fixture.',
      stdout: '',
      stderr: '',
      payload: <String, dynamic>{
        'packages': 2,
        'vendor_root': '/workspace/demo/.pafio/vendor',
        'metadata_path': '/workspace/demo/.pafio/vendor/pafio-vendor.json',
      },
    );
  }
}

class _SuccessfulDeploymentAdapter implements DeploymentAdapter {
  const _SuccessfulDeploymentAdapter();

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
      statusMessage: 'deployment command succeeded in the shell-model fixture.',
      stdout: '',
      stderr: '',
      payload: <String, dynamic>{
        'package': packageName ?? 'demo/app',
        'archive_path': '/workspace/demo/dist/app-0.0.5.tar',
      },
    );
  }
}
