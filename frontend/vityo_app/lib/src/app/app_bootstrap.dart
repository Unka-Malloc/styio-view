import 'dart:async';

import 'package:flutter/foundation.dart';

import '../agent/agent.dart';
import '../backend_toolchain/adapter_contracts.dart';
import '../backend_toolchain/dependency_source_adapter.dart';
import '../backend_toolchain/deployment_adapter.dart';
import '../backend_toolchain/execution_adapter.dart';
import '../backend_toolchain/hosted_control_plane.dart';
import '../backend_toolchain/project_graph_adapter.dart';
import '../backend_toolchain/project_graph_contract.dart';
import '../backend_toolchain/runtime_event_adapter.dart';
import '../backend_toolchain/toolchain_management_adapter.dart';
import '../editor/editor_controller.dart';
import '../view_ide/interaction/interaction.dart';
import '../view_ide/editor/document_state.dart';
import '../view_ide/environment/environment.dart';
import '../view_ide/foundation/foundation.dart';
import '../view_ide/language/service/language_service_foundation.dart';
import '../view_ide/language/service/styio_service_capability_detector.dart';
import '../view_ide/language/service/styio_service_connector.dart';
import '../view_ide/language/service/styio_service_runtime.dart';
import '../view_ide/language/service/styio_workspace_diagnostics_provider.dart';
import '../view_ide/toolchain/clang_cpp_version_configuration.dart';
import '../view_ide/toolchain/toolchain_catalog.dart';
import '../view_ide/toolchain/toolchain_configuration_store.dart';
import '../view_ide/toolchain/toolchain_manager.dart';
import '../view_ide/toolchain/native_compiler_toolchain_discovery.dart';
import '../view_ide/toolchain/styio_toolchain_discovery.dart';
import '../view_ide/testing/testing.dart';
import '../view_ide/workspace/workspace_diagnostics.dart';
import '../view_ide/workspace/workspace_diagnostics_controller.dart';
import '../view_ide/workspace/source_control_status.dart';
import '../view_ide/workspace/source_control_status_controller.dart';
import '../module_host/module_registry.dart';
import '../platform/native_module_loader.dart';
import '../platform/platform_target.dart';
import 'state/workspace_document_store.dart';
import 'state/workspace_controller.dart';

typedef AppHostedControlPlaneClientProvider =
    Future<HostedControlPlaneClient?> Function({
      required PlatformTarget platformTarget,
    });

class AppLanguageServiceProjectContext {
  const AppLanguageServiceProjectContext({
    required this.workingDirectory,
    this.configPath,
  });

  final String workingDirectory;
  final String? configPath;
}

class AppBootstrap {
  AppBootstrap({
    required this.platformTarget,
    required this.moduleRegistry,
    required this.nativeModuleLoader,
    required this.projectGraphAdapter,
    required this.supplementalAdapterCapabilities,
    required this.workspaceController,
    required this.workspaceDocumentStore,
    required this.editorController,
    required this.executionAdapter,
    required this.executionAdapterFactory,
    required this.runtimeEventAdapter,
    required this.dependencySourceAdapter,
    required this.deploymentAdapter,
    required this.toolchainManagementAdapter,
    required this.agentCodingController,
    required this.agentProviderConfigurator,
    this.themeOverrideStore,
    this.refreshActiveLanguageService,
    ValueNotifier<LanguageServiceStatusSurface>? languageServiceStatus,
    this.toolchainManager,
    this.toolchainStatusReport,
    this.clangCppVersionPreference,
    this.toolchainCatalogSubscription,
    this.languageResultCacheBinding,
    this.workspaceDiagnosticsController,
    this.testingSessionController,
    this.sourceControlStatusController,
  }) : languageServiceStatus =
           languageServiceStatus ??
           ValueNotifier<LanguageServiceStatusSurface>(
             LanguageServiceStatusSurface.unavailable(),
           );

  final PlatformTarget platformTarget;
  final ModuleRegistry moduleRegistry;
  final NativeModuleLoader nativeModuleLoader;
  final ProjectGraphAdapter projectGraphAdapter;
  final List<AdapterCapabilitySnapshot> supplementalAdapterCapabilities;
  final WorkspaceController workspaceController;
  final WorkspaceDocumentStore workspaceDocumentStore;
  final EditorSessionController editorController;
  final ExecutionAdapter executionAdapter;
  final ExecutionAdapterFactory executionAdapterFactory;
  final RuntimeEventAdapter runtimeEventAdapter;
  final DependencySourceAdapter dependencySourceAdapter;
  final DeploymentAdapter deploymentAdapter;
  final ToolchainManagementAdapter toolchainManagementAdapter;
  final AgentCodingSessionController agentCodingController;
  final AgentProviderConfigurator agentProviderConfigurator;
  final VityoThemeOverrideStore? themeOverrideStore;
  final ToolchainManager? toolchainManager;
  final ClangCppVersionPreference? clangCppVersionPreference;
  final Future<void> Function()? refreshActiveLanguageService;
  final ValueNotifier<LanguageServiceStatusSurface> languageServiceStatus;
  final ValueListenable<ToolchainManagerStatusReport>? toolchainStatusReport;
  final StreamSubscription<ToolchainCatalogConfigurationChange>?
  toolchainCatalogSubscription;
  final StyioServiceToolchainCacheBinding? languageResultCacheBinding;
  final WorkspaceDiagnosticsController? workspaceDiagnosticsController;
  final TestingSessionController? testingSessionController;
  final SourceControlStatusController? sourceControlStatusController;

  void dispose() {
    unawaited(toolchainCatalogSubscription?.cancel());
    unawaited(languageResultCacheBinding?.dispose());
    workspaceDiagnosticsController?.dispose();
    testingSessionController?.dispose();
    sourceControlStatusController?.dispose();
    agentCodingController.dispose();
  }

  List<AdapterCapabilitySnapshot> get adapterCapabilities =>
      normalizeCapabilitySnapshots([
        projectGraphAdapter.capabilitySnapshot,
        executionAdapter.capabilitySnapshot,
        runtimeEventAdapter.capabilitySnapshot,
        ...supplementalAdapterCapabilities,
      ]);

  static Future<AppBootstrap> load() async {
    final platformTarget = detectPlatformTarget();
    var workspaceDocumentStore = await createWorkspaceDocumentStore();
    final moduleRegistry = await ModuleRegistry.loadFromAssets(
      indexAssetPath: 'assets/module_manifests/index.json',
      platformTarget: platformTarget,
    );
    final nativeModuleLoader = NoopNativeModuleLoader(
      platformTarget: platformTarget,
    );
    final projectGraphAdapter = await createProjectGraphAdapter(
      platformTarget: platformTarget,
    );
    final projectSnapshot = await projectGraphAdapter.loadProjectGraph();
    workspaceDocumentStore = await createEditorWorkspaceDocumentStore(
      platformTarget: platformTarget,
      localStore: workspaceDocumentStore,
      projectSnapshot: projectSnapshot,
    );
    final platformManagers = await createDetectedPlatformManagerBundle();
    final foundationDataStore = _createFoundationDataStore(platformManagers);
    final credentialDataStore = FoundationCredentialDataStore(
      dataStore: foundationDataStore,
    );
    final configurationStore = _createConfigurationStore(
      dataStore: foundationDataStore,
      credentialDataStore: credentialDataStore,
    );
    final themeOverrideStore = VityoThemeOverrideStore.fromDataStore(
      dataStore: foundationDataStore,
    );
    final toolchainStore = ToolchainConfigurationStore(
      configurationStore: configurationStore,
    );
    await ensureDefaultLanguageServiceToolchainCatalog(
      toolchainStore: toolchainStore,
      workspaceId: projectSnapshot.id,
      targetId: platformManagers.context.targetId,
    );
    await ensureDefaultNativeCompilerToolchainCatalog(
      toolchainStore: toolchainStore,
      workspaceId: projectSnapshot.id,
      targetId: platformManagers.context.targetId,
      defaultCatalogProvider: () {
        return createPlatformNativeCompilerToolchainCatalog(
          platformManagers: platformManagers,
        );
      },
    );
    final toolchainManager = ToolchainManager(
      configurationStore: toolchainStore,
      platformManagers: platformManagers,
      workspaceId: projectSnapshot.id,
    );
    final clangCppVersionPreference = await toolchainManager
        .loadClangCppVersionPreference();
    final toolchainStatusReport = ValueNotifier<ToolchainManagerStatusReport>(
      await toolchainManager.statusReport(kind: ToolchainKind.languageService),
    );
    final toolchainCatalogChanges = toolchainStore
        .watchCatalog(
          workspaceId: projectSnapshot.id,
          targetId: platformManagers.context.targetId,
        )
        .asBroadcastStream();
    late final StreamSubscription<ToolchainCatalogConfigurationChange>
    toolchainCatalogSubscription;
    final workspaceController = WorkspaceController(
      projectSnapshot: projectSnapshot,
    );
    Future<ExecutionAdapter> executionAdapterFactory(
      ProjectGraphSnapshot refreshedProjectGraph,
    ) {
      return createExecutionAdapter(
        platformTarget: platformTarget,
        projectGraph: refreshedProjectGraph,
      );
    }

    final executionAdapter = await executionAdapterFactory(projectSnapshot);
    final runtimeEventAdapter = createRuntimeEventAdapter(
      platformTarget: platformTarget,
    );
    final dependencySourceAdapter = await createDependencySourceAdapter(
      platformTarget: platformTarget,
    );
    final deploymentAdapter = await createDeploymentAdapter(
      platformTarget: platformTarget,
    );
    final toolchainManagementAdapter = await createToolchainManagementAdapter(
      platformTarget: platformTarget,
    );
    final ffiBridge = await nativeModuleLoader.describe(
      'local.runtime.desktop',
    );
    final supplementalAdapterCapabilities = normalizeCapabilitySnapshots([
      buildFfiAdapterCapability(
        visible: ffiBridge.state != NativeBridgeState.unavailable,
        executionSlotVisible: ffiBridge.state != NativeBridgeState.unavailable,
        detail: ffiBridge.detail,
      ),
      buildCloudAdapterCapability(
        supportsCloudExecution:
            platformTarget == PlatformTarget.ios ||
            platformTarget == PlatformTarget.web ||
            platformTarget == PlatformTarget.android,
        supportsHostedProjectGraph:
            platformTarget == PlatformTarget.ios ||
            platformTarget == PlatformTarget.web,
        detail: platformTarget == PlatformTarget.web
            ? 'Hosted/cloud adapters back Web workspaces while local binaries stay unavailable.'
            : platformTarget == PlatformTarget.ios
            ? 'iOS keeps cloud execution as the compliance floor.'
            : 'Cloud adapters remain a supplement for mobile fallback and hosted workspaces.',
      ),
    ]);
    final initialDocument = await workspaceDocumentStore.loadDocument(
      workspaceController.activeFilePath,
    );
    final languageResultCache = StyioServiceResultCache();
    final languageResultCacheBinding =
        bindLanguageResultCacheToToolchainCatalog(
          resultCache: languageResultCache,
          catalogChanges: toolchainCatalogChanges,
        );
    final languageServiceStatus = ValueNotifier<LanguageServiceStatusSurface>(
      LanguageServiceStatusSurface.refreshing(),
    );
    final languageServiceDriver =
        await createPlatformStyioServiceAnalysisDriver(
          resultCache: languageResultCache,
          toolchainManager: toolchainManager,
        );
    final languageProjectContext = resolveLanguageServiceProjectContext(
      workspaceRoot: projectSnapshot.workspaceRoot,
      styioConfigPath: projectSnapshot.styioConfigPath,
    );
    final editorController = EditorSessionController(
      initialDocument: initialDocument,
      languageService: createRoutedStyioLanguageService(
        resultCache: languageResultCache,
        configPath: languageProjectContext.configPath,
        workingDirectory: languageProjectContext.workingDirectory,
      ),
    );
    final workspaceDiagnosticsController = WorkspaceDiagnosticsController(
      provider: StyioWorkspaceDiagnosticsProvider(
        projectService: createRoutedProjectStyioLanguageService(
          resultCache: languageResultCache,
          configPath: languageProjectContext.configPath,
          workingDirectory: languageProjectContext.workingDirectory,
        ),
      ),
    );
    final testingSessionController = TestingSessionController();
    final sourceControlStatusController =
        AppBootstrap.createSourceControlStatusController(
          platformManagers: platformManagers,
          workspaceRoot: projectSnapshot.workspaceRoot,
        );
    unawaited(sourceControlStatusController.refresh());
    Future<void> refreshActiveLanguageService() async {
      try {
        await refreshLanguageServiceForEditor(
          driver: languageServiceDriver,
          editorController: editorController,
          workspaceDocumentStore: workspaceDocumentStore,
          projectContext: languageProjectContext,
          languageServiceStatus: languageServiceStatus,
        );
        await workspaceDiagnosticsController.refresh(
          AppBootstrap.createWorkspaceDiagnosticsRequest(
            editorController: editorController,
            workspaceController: workspaceController,
            workspaceDocuments: <DocumentState>[editorController.document],
          ),
        );
      } on Object catch (error) {
        languageServiceStatus.value = LanguageServiceStatusSurface.failed(
          message:
              'StyioService failed while refreshing language facts: $error',
        );
      }
    }

    unawaited(refreshActiveLanguageService());
    toolchainCatalogSubscription = toolchainCatalogChanges.listen((_) {
      unawaited(
        toolchainManager.statusReport(kind: ToolchainKind.languageService).then(
          (report) {
            toolchainStatusReport.value = report;
          },
        ),
      );
      unawaited(refreshActiveLanguageService());
    });
    final agentProfileStore = AgentPromptProfileStore.fromDataStore(
      dataStore: foundationDataStore,
    );
    final agentProviderFactory = ConfiguredAgentProviderAdapterFactory(
      configurationStore: configurationStore,
      transport: NetworkAgentProviderTransport(
        networkManager: platformManagers.network,
      ),
      localServiceManager: platformManagers.localService,
    );
    final agentProviderRegistry = agentProviderFactory.createRegistry();
    final agentCodingController = await createAgentCodingSessionController(
      platformTarget: platformTarget,
      loadPersistedProfile: () {
        return agentProfileStore.readProfile(workspaceId: projectSnapshot.id);
      },
      createConfiguredAdapter: agentProviderRegistry.createAdapter,
      resolveConfiguredExecution: agentProviderFactory.resolveExecution,
      contextProvider: () => AgentSessionContext.fromEditorState(
        document: editorController.document,
        selection: editorController.selection,
        diagnostics: editorController.analysis.diagnostics,
        hover: editorController.hoverAtSelection,
        definition: editorController.definitionAtSelection,
        references: editorController.referencesAtSelection,
        completions: editorController.completionsAtSelection,
        codeActions: editorController.contextActionsAtSelection,
        languageServiceStatus: languageServiceStatus.value,
        workspaceFiles: workspaceController.files,
        workspaceDocuments: [editorController.document],
        workspaceDiagnostics: workspaceDiagnosticsController.snapshot,
        activeFilePath: workspaceController.activeFilePath,
        toolchainSnapshot: toolchainStatusReport.value.snapshot,
        clangCppVersionPreference: clangCppVersionPreference,
      ),
    );
    final agentProviderConfigurator = AgentProviderConfigurator.fromStores(
      workspaceId: projectSnapshot.id,
      profileStore: agentProfileStore,
      providerFactory: agentProviderFactory,
      providerRegistry: agentProviderRegistry,
      credentialDataStore: credentialDataStore,
    );

    return AppBootstrap(
      platformTarget: platformTarget,
      moduleRegistry: moduleRegistry,
      nativeModuleLoader: nativeModuleLoader,
      projectGraphAdapter: projectGraphAdapter,
      supplementalAdapterCapabilities: supplementalAdapterCapabilities,
      workspaceController: workspaceController,
      workspaceDocumentStore: workspaceDocumentStore,
      editorController: editorController,
      executionAdapter: executionAdapter,
      executionAdapterFactory: executionAdapterFactory,
      runtimeEventAdapter: runtimeEventAdapter,
      dependencySourceAdapter: dependencySourceAdapter,
      deploymentAdapter: deploymentAdapter,
      toolchainManagementAdapter: toolchainManagementAdapter,
      agentCodingController: agentCodingController,
      agentProviderConfigurator: agentProviderConfigurator,
      themeOverrideStore: themeOverrideStore,
      refreshActiveLanguageService: refreshActiveLanguageService,
      toolchainManager: toolchainManager,
      languageServiceStatus: languageServiceStatus,
      toolchainStatusReport: toolchainStatusReport,
      clangCppVersionPreference: clangCppVersionPreference,
      toolchainCatalogSubscription: toolchainCatalogSubscription,
      languageResultCacheBinding: languageResultCacheBinding,
      workspaceDiagnosticsController: workspaceDiagnosticsController,
      testingSessionController: testingSessionController,
      sourceControlStatusController: sourceControlStatusController,
    );
  }

  static FoundationDataStore _createFoundationDataStore(
    PlatformManagerBundle platformManagers,
  ) {
    return FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: platformManagers.resource,
        fileSystemManager: platformManagers.fileSystem,
      ),
      fileSystemManager: platformManagers.fileSystem,
    );
  }

  static ConfigurationStore _createConfigurationStore({
    required FoundationDataStore dataStore,
    required CredentialDataStore credentialDataStore,
  }) {
    return ConfigurationStore(
      dataStore: dataStore,
      credentialDataStore: credentialDataStore,
    );
  }

  @visibleForTesting
  static SourceControlStatusController createSourceControlStatusController({
    required PlatformManagerBundle platformManagers,
    required String workspaceRoot,
  }) {
    return SourceControlStatusController(
      provider: GitPorcelainStatusProvider(
        runner: ProcessSourceControlCommandRunner(
          processManager: platformManagers.process,
        ).call,
      ),
      workspaceRoot: workspaceRoot,
    );
  }

  @visibleForTesting
  static WorkspaceDiagnosticsRequest createWorkspaceDiagnosticsRequest({
    required EditorSessionController editorController,
    required WorkspaceController workspaceController,
    Iterable<DocumentState> workspaceDocuments = const <DocumentState>[],
  }) {
    final documentsById = <String, DocumentState>{
      editorController.document.documentId: editorController.document,
      for (final document in workspaceDocuments) document.documentId: document,
    };
    final documentIds = <String>{
      ...workspaceController.openFilePaths,
      editorController.document.documentId,
    }.toList(growable: false);
    return WorkspaceDiagnosticsRequest(
      documentIds: documentIds,
      activeDocumentId: editorController.document.documentId,
      documents: documentsById.values.toList(growable: false),
    );
  }

  @visibleForTesting
  static Future<AgentCodingSessionController>
  createAgentCodingSessionController({
    required PlatformTarget platformTarget,
    required Future<AgentPromptProfile?> Function() loadPersistedProfile,
    required Future<AgentProviderAdapter> Function(AgentPromptProfile profile)
    createConfiguredAdapter,
    Future<AgentProviderExecutionResolution> Function(
      AgentPromptProfile profile,
    )?
    resolveConfiguredExecution,
    required AgentSessionContextProvider contextProvider,
  }) async {
    final persistedProfile = await loadPersistedProfile();
    final profile =
        persistedProfile ??
        AgentPromptProfile.defaultForPlatform(platformTarget);
    final adapter = persistedProfile == null
        ? const LocalOnlyAgentProviderAdapter()
        : await _createConfiguredAgentAdapter(
            profile: profile,
            createConfiguredAdapter: createConfiguredAdapter,
          );
    final executionResolution = persistedProfile == null
        ? null
        : await _resolveConfiguredAgentExecution(
            profile: profile,
            resolveConfiguredExecution: resolveConfiguredExecution,
          );
    return AgentCodingSessionController(
      profile: profile,
      adapter: adapter,
      providerExecutionResolution: executionResolution,
      contextProvider: contextProvider,
    );
  }

  static Future<AgentProviderAdapter> _createConfiguredAgentAdapter({
    required AgentPromptProfile profile,
    required Future<AgentProviderAdapter> Function(AgentPromptProfile profile)
    createConfiguredAdapter,
  }) async {
    try {
      return await createConfiguredAdapter(profile);
    } on Object {
      return const LocalOnlyAgentProviderAdapter();
    }
  }

  static Future<AgentProviderExecutionResolution?>
  _resolveConfiguredAgentExecution({
    required AgentPromptProfile profile,
    required Future<AgentProviderExecutionResolution> Function(
      AgentPromptProfile profile,
    )?
    resolveConfiguredExecution,
  }) async {
    if (resolveConfiguredExecution == null) {
      return null;
    }
    try {
      return await resolveConfiguredExecution(profile);
    } on Object {
      return null;
    }
  }

  @visibleForTesting
  static Future<WorkspaceDocumentStore> createEditorWorkspaceDocumentStore({
    required PlatformTarget platformTarget,
    required WorkspaceDocumentStore localStore,
    required ProjectGraphSnapshot projectSnapshot,
    AppHostedControlPlaneClientProvider? hostedClientProvider,
  }) async {
    final hostedWorkspace = projectSnapshot.hostedWorkspace;
    if (hostedWorkspace == null) {
      return localStore;
    }
    final provider = hostedClientProvider ?? createHostedControlPlaneClient;
    final hostedClient = await provider(platformTarget: platformTarget);
    if (hostedClient == null) {
      return localStore;
    }
    return HostedWorkspaceDocumentStore(
      hostedClient: hostedClient,
      workspaceId: hostedWorkspace.workspaceId,
    );
  }

  @visibleForTesting
  static AppLanguageServiceProjectContext resolveLanguageServiceProjectContext({
    required String workspaceRoot,
    String? styioConfigPath,
  }) {
    return AppLanguageServiceProjectContext(
      workingDirectory: workspaceRoot,
      configPath: styioConfigPath,
    );
  }

  @visibleForTesting
  static StyioServiceToolchainCacheBinding
  bindLanguageResultCacheToToolchainCatalog({
    required StyioServiceResultCache resultCache,
    required Stream<ToolchainCatalogConfigurationChange> catalogChanges,
  }) {
    return StyioServiceToolchainCacheBinding.bind(
      cache: resultCache,
      catalogChanges: catalogChanges,
    );
  }

  @visibleForTesting
  static Future<ToolchainCatalog> ensureDefaultLanguageServiceToolchainCatalog({
    required ToolchainConfigurationStore toolchainStore,
    required String targetId,
    String? workspaceId,
    Future<ToolchainCatalog> Function()? defaultCatalogProvider,
  }) async {
    final catalog = await toolchainStore.loadCatalog(
      workspaceId: workspaceId,
      targetId: targetId,
    );
    if (catalog.list(kind: ToolchainKind.languageService).isNotEmpty) {
      return catalog;
    }

    final defaultCatalog =
        await (defaultCatalogProvider ??
            createPlatformStyioLanguageToolchainCatalog)();
    final defaultLanguageServices = defaultCatalog.list(
      kind: ToolchainKind.languageService,
    );
    if (defaultLanguageServices.isEmpty) {
      return catalog;
    }

    var changed = false;
    for (final descriptor in defaultLanguageServices) {
      if (catalog.lookup(descriptor.id) != null) {
        continue;
      }
      catalog.register(descriptor);
      changed = true;
    }

    final defaultActive = defaultCatalog.active(ToolchainKind.languageService);
    if (catalog.active(ToolchainKind.languageService) == null &&
        defaultActive != null &&
        catalog.lookup(defaultActive.id) != null) {
      catalog.activate(defaultActive.id);
      changed = true;
    }

    if (changed) {
      await toolchainStore.saveCatalog(
        catalog,
        workspaceId: workspaceId,
        targetId: targetId,
      );
    }
    return catalog;
  }

  @visibleForTesting
  static Future<ToolchainCatalog> ensureDefaultNativeCompilerToolchainCatalog({
    required ToolchainConfigurationStore toolchainStore,
    required String targetId,
    String? workspaceId,
    Future<ToolchainCatalog> Function()? defaultCatalogProvider,
  }) async {
    final catalog = await toolchainStore.loadCatalog(
      workspaceId: workspaceId,
      targetId: targetId,
    );
    final defaultCatalog =
        await (defaultCatalogProvider ??
            createPlatformNativeCompilerToolchainCatalog)();
    final defaultToolchains = defaultCatalog.list();
    if (defaultToolchains.isEmpty) {
      return catalog;
    }

    var changed = false;
    for (final descriptor in defaultToolchains) {
      if (catalog.lookup(descriptor.id) != null) {
        continue;
      }
      catalog.register(descriptor);
      changed = true;
    }

    for (final kind in ToolchainKind.values) {
      final defaultActive = defaultCatalog.active(kind);
      if (catalog.active(kind) == null &&
          defaultActive != null &&
          catalog.lookup(defaultActive.id) != null) {
        catalog.activate(defaultActive.id);
        changed = true;
      }
    }

    if (changed) {
      await toolchainStore.saveCatalog(
        catalog,
        workspaceId: workspaceId,
        targetId: targetId,
      );
    }
    return catalog;
  }

  @visibleForTesting
  static Future<StyioServiceAnalysisReport> refreshLanguageServiceForEditor({
    required StyioServiceAnalysisDriver driver,
    required EditorSessionController editorController,
    required WorkspaceDocumentStore workspaceDocumentStore,
    required AppLanguageServiceProjectContext projectContext,
    required ValueNotifier<LanguageServiceStatusSurface> languageServiceStatus,
  }) async {
    final document = editorController.document;
    final report = await driver.analyzeDocumentWithReport(
      document,
      filePath: workspaceDocumentStore.filePathForDocumentId(
        document.documentId,
      ),
      configPath: projectContext.configPath,
      workingDirectory: projectContext.workingDirectory,
    );
    languageServiceStatus.value = _languageStatusFromReport(report);
    editorController.refreshAnalysis();
    return report;
  }

  static LanguageServiceStatusSurface _languageStatusFromReport(
    StyioServiceAnalysisReport report,
  ) {
    final capabilitySnapshot = const StyioServiceCapabilityDetector()
        .detectReport(report);
    return LanguageServiceStatusSurface.fromRuntimeSnapshot(
      StyioServiceRuntimeStatusSnapshot(
        state: report.serviceSucceeded
            ? StyioServiceRuntimeSessionState.active
            : StyioServiceRuntimeSessionState.failed,
        disposed: false,
        providerManifest: LanguageProviderRegistry<Object?>().manifest(),
        capabilitySnapshot: capabilitySnapshot,
      ),
    );
  }
}
