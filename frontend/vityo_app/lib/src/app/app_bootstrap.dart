import 'dart:async';
import 'dart:convert';

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
import '../view_ide/commands/commands.dart';
import '../view_ide/language/service/language_service_foundation.dart';
import '../view_ide/language/service/project_styio_language_service.dart';
import '../view_ide/language/service/styio_service_capability_detector.dart';
import '../view_ide/language/service/styio_service_connector.dart';
import '../view_ide/language/service/styio_service_runtime.dart';
import '../view_ide/language/service/styio_service_subscription.dart';
import '../view_ide/language/service/styio_workspace_diagnostics_provider.dart';
import '../view_ide/module_host/module_host.dart';
import '../view_ide/runtime/runtime.dart';
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

class AppExtensionStartupPlan {
  const AppExtensionStartupPlan({
    required this.manifestRegistry,
    required this.activationSession,
    required this.supervisorSnapshot,
    required this.contributionRoutes,
  });

  final ExtensionManifestRegistry manifestRegistry;
  final ExtensionActivationSession activationSession;
  final ExtensionHostSupervisorSnapshot supervisorSnapshot;
  final ExtensionContributionRouteManifest contributionRoutes;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'manifestCount': manifestRegistry.list().length,
      'activationSession': activationSession.toJson(),
      'supervisorSnapshot': supervisorSnapshot.toJson(),
      'contributionRoutes': contributionRoutes.toJson(),
    };
  }
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
    this.agentExtensionToolExecutionRegistry,
    this.extensionStartupPlan,
    RuntimeOutputLiveBuffer? runtimeOutputBuffer,
    this.commandPalettePreferencesStore,
    this.themeOverrideStore,
    this.refreshActiveLanguageService,
    this.styioServiceSubscriptionController,
    this.languageServiceStatusController,
    ValueNotifier<LanguageServiceStatusSurface>? languageServiceStatus,
    this.toolchainManager,
    this.toolchainStatusReport,
    this.clangCppVersionPreference,
    this.toolchainCatalogSubscription,
    this.languageResultCacheBinding,
    this.workspaceDiagnosticsController,
    this.testingSessionController,
    this.sourceControlStatusController,
    this.projectLanguageService,
  }) : runtimeOutputBuffer = runtimeOutputBuffer ?? RuntimeOutputLiveBuffer(),
       languageServiceStatus =
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
  final ExtensionAgentToolExecutionRegistry?
  agentExtensionToolExecutionRegistry;
  final AppExtensionStartupPlan? extensionStartupPlan;
  final RuntimeOutputLiveBuffer runtimeOutputBuffer;
  final CommandPaletteDisplayPreferencesStore? commandPalettePreferencesStore;
  final VityoThemeOverrideStore? themeOverrideStore;
  final ToolchainManager? toolchainManager;
  final ClangCppVersionPreference? clangCppVersionPreference;
  final Future<void> Function()? refreshActiveLanguageService;
  final StyioServiceSubscriptionController? styioServiceSubscriptionController;
  final LanguageServiceStatusController? languageServiceStatusController;
  final ValueNotifier<LanguageServiceStatusSurface> languageServiceStatus;
  final ValueListenable<ToolchainManagerStatusReport>? toolchainStatusReport;
  final StreamSubscription<ToolchainCatalogConfigurationChange>?
  toolchainCatalogSubscription;
  final StyioServiceToolchainCacheBinding? languageResultCacheBinding;
  final WorkspaceDiagnosticsController? workspaceDiagnosticsController;
  final TestingSessionController? testingSessionController;
  final SourceControlStatusController? sourceControlStatusController;
  final ProjectStyioLanguageService? projectLanguageService;

  void dispose() {
    unawaited(toolchainCatalogSubscription?.cancel());
    unawaited(languageResultCacheBinding?.dispose());
    unawaited(styioServiceSubscriptionController?.dispose());
    unawaited(languageServiceStatusController?.dispose());
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
    final runtimeOutputBuffer = RuntimeOutputLiveBuffer();
    final extensionStartupPlan = createExtensionStartupPlan(
      moduleRegistry: moduleRegistry,
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
    final commandPalettePreferencesStore =
        CommandPaletteDisplayPreferencesStore.fromDataStore(
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
    final languageServiceStatusController = LanguageServiceStatusController(
      initialStatus: LanguageServiceStatusSurface.refreshing(),
    );
    final languageServiceStatus = languageServiceStatusController.notifier;
    final languageServiceDriver =
        await createPlatformStyioServiceAnalysisDriver(
          resultCache: languageResultCache,
          toolchainManager: toolchainManager,
        );
    final styioServiceSubscriptionController =
        StyioServiceSubscriptionController(driver: languageServiceDriver);
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
    final projectLanguageService = createRoutedProjectStyioLanguageService(
      resultCache: languageResultCache,
      configPath: languageProjectContext.configPath,
      workingDirectory: languageProjectContext.workingDirectory,
    );
    final workspaceDiagnosticsController = WorkspaceDiagnosticsController(
      provider: StyioWorkspaceDiagnosticsProvider(
        projectService: projectLanguageService,
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
          languageServiceStatusController: languageServiceStatusController,
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
    final agentSessionHistoryStore =
        AgentCodingSessionHistoryStore.fromDataStore(
          dataStore: foundationDataStore,
        );
    final agentWorkspaceSnapshotStore =
        AgentWorkspaceSnapshotStore.fromDataStore(
          dataStore: foundationDataStore,
        );
    final agentProviderFactory = createAgentProviderFactory(
      configurationStore: configurationStore,
      transport: createNetworkAgentProviderTransport(
        networkManager: platformManagers.network,
      ),
      localServiceManager: platformManagers.localService,
      environment: readHostEnvironment(),
    );
    final agentProviderRegistry = agentProviderFactory.createRegistry();
    final builtInExtensionRpcTransports =
        createBuiltInExtensionAgentToolRpcTransports(
          platformTarget: platformTarget,
          agentProviderRegistry: agentProviderRegistry,
        );
    final agentCodingController = await createAgentCodingSessionController(
      platformTarget: platformTarget,
      loadPersistedProfile: () {
        return agentProfileStore.readProfile(workspaceId: projectSnapshot.id);
      },
      createConfiguredAdapter: agentProviderRegistry.createAdapter,
      selectConfiguredProvider: agentProviderRegistry.selectionPlan,
      resolveConfiguredExecution: agentProviderFactory.resolveExecution,
      sessionHistoryStore: agentSessionHistoryStore,
      sessionHistoryWorkspaceId: projectSnapshot.id,
      workspaceSnapshotStore: agentWorkspaceSnapshotStore,
      workspaceSnapshotWorkspaceId: projectSnapshot.id,
      workspaceSnapshotService: AgentWorkspaceSnapshotService(
        editorController: editorController,
        workspaceDocumentStore: workspaceDocumentStore,
      ),
      extensionContributionRoutes: extensionStartupPlan.contributionRoutes,
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
    final agentExtensionToolExecutionRegistry =
        createAgentExtensionToolExecutionRegistry(
          extensionContributionRoutes: extensionStartupPlan.contributionRoutes,
          extensionHostSupervisorSnapshot:
              extensionStartupPlan.supervisorSnapshot,
          runtimeOutputBuffer: runtimeOutputBuffer,
          extensionManifestRegistry: extensionStartupPlan.manifestRegistry,
          rpcTransports: builtInExtensionRpcTransports,
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
      agentExtensionToolExecutionRegistry: agentExtensionToolExecutionRegistry,
      extensionStartupPlan: extensionStartupPlan,
      runtimeOutputBuffer: runtimeOutputBuffer,
      commandPalettePreferencesStore: commandPalettePreferencesStore,
      themeOverrideStore: themeOverrideStore,
      refreshActiveLanguageService: refreshActiveLanguageService,
      styioServiceSubscriptionController: styioServiceSubscriptionController,
      languageServiceStatusController: languageServiceStatusController,
      toolchainManager: toolchainManager,
      languageServiceStatus: languageServiceStatus,
      toolchainStatusReport: toolchainStatusReport,
      clangCppVersionPreference: clangCppVersionPreference,
      toolchainCatalogSubscription: toolchainCatalogSubscription,
      languageResultCacheBinding: languageResultCacheBinding,
      workspaceDiagnosticsController: workspaceDiagnosticsController,
      testingSessionController: testingSessionController,
      sourceControlStatusController: sourceControlStatusController,
      projectLanguageService: projectLanguageService,
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
  static ConfiguredAgentProviderAdapterFactory createAgentProviderFactory({
    required ConfigurationStore configurationStore,
    required AgentProviderTransport transport,
    LocalServiceManager? localServiceManager,
    Map<String, String> environment = const <String, String>{},
  }) {
    return ConfiguredAgentProviderAdapterFactory(
      configurationStore: configurationStore,
      transport: transport,
      localServiceManager: localServiceManager,
      environment: environment,
    );
  }

  @visibleForTesting
  static SourceControlStatusController createSourceControlStatusController({
    required PlatformManagerBundle platformManagers,
    required String workspaceRoot,
  }) {
    final runner = ProcessSourceControlCommandRunner(
      processManager: platformManagers.process,
    ).call;
    return SourceControlStatusController(
      provider: GitPorcelainStatusProvider(runner: runner),
      diffProvider: GitSourceControlDiffProvider(runner: runner),
      actionProvider: GitSourceControlActionProvider(runner: runner),
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
    AgentProviderSelectionPlan Function(AgentPromptProfile profile)?
    selectConfiguredProvider,
    Future<AgentProviderExecutionResolution> Function(
      AgentPromptProfile profile,
    )?
    resolveConfiguredExecution,
    AgentCodingSessionHistoryStore? sessionHistoryStore,
    String sessionHistoryWorkspaceId = 'default',
    AgentWorkspaceSnapshotStore? workspaceSnapshotStore,
    String? workspaceSnapshotWorkspaceId,
    AgentWorkspaceSnapshotService? workspaceSnapshotService,
    AgentToolRegistry? toolRegistry,
    ExtensionContributionRouteManifest? extensionContributionRoutes,
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
    var providerSelectionPlan = _selectConfiguredAgentProvider(
      profile: profile,
      selectConfiguredProvider: selectConfiguredProvider,
    );
    final executionResolution = persistedProfile == null
        ? null
        : await _resolveConfiguredAgentExecution(
            profile: profile,
            resolveConfiguredExecution: resolveConfiguredExecution,
          );
    if (providerSelectionPlan != null && executionResolution != null) {
      providerSelectionPlan = providerSelectionPlan.withExecutionResolution(
        executionResolution,
      );
    }
    final controller = AgentCodingSessionController(
      profile: profile,
      adapter: adapter,
      providerSelectionPlan: providerSelectionPlan,
      providerExecutionResolution: executionResolution,
      contextProvider: contextProvider,
      sessionHistoryStore: sessionHistoryStore,
      sessionHistoryWorkspaceId: sessionHistoryWorkspaceId,
      workspaceSnapshotStore: workspaceSnapshotStore,
      workspaceSnapshotWorkspaceId: workspaceSnapshotWorkspaceId,
      toolRegistry:
          toolRegistry ??
          createAgentToolRegistry(
            extensionContributionRoutes: extensionContributionRoutes,
          ),
    );
    await controller.loadSessionHistory();
    await controller.loadWorkspaceSnapshot(
      snapshotService: workspaceSnapshotService,
    );
    return controller;
  }

  @visibleForTesting
  static AgentToolRegistry createAgentToolRegistry({
    ExtensionContributionRouteManifest? extensionContributionRoutes,
  }) {
    if (extensionContributionRoutes == null) {
      return AgentToolRegistry();
    }
    return ExtensionAgentToolContributionCatalog.fromRoutes(
      extensionContributionRoutes,
    ).toRegistry();
  }

  @visibleForTesting
  static AppExtensionStartupPlan createExtensionStartupPlan({
    required ModuleRegistry moduleRegistry,
    String publisher = 'vityo',
    String activationEvent = 'onStartup',
    DateTime Function()? clock,
  }) {
    final manifestRegistry = ExtensionManifestRegistry(
      moduleRegistry.mountedModules.map((definition) {
        final extensionActivationEvents =
            definition.manifest.extensionActivationEvents.isEmpty
            ? <String>[activationEvent]
            : definition.manifest.extensionActivationEvents;
        final extensionContributions = definition
            .manifest
            .extensionContributions
            .map(ExtensionContributionPoint.fromJson)
            .toList(growable: false);
        return ExtensionManifest.fromModuleManifest(
          module: definition.manifest,
          publisher: publisher,
          activationEvents: extensionActivationEvents,
          contributions: extensionContributions,
          metadata: <String, Object?>{
            'source': 'module-registry',
            'moduleSlot': definition.manifest.slot.wireValue,
            ...definition.manifest.extensionMetadata,
          },
        );
      }),
    );
    final activator = ExtensionActivator(clock: clock);
    final activationSession = activator.activate(
      registry: manifestRegistry,
      event: activationEvent,
    );
    final activeRegistry = ExtensionManifestRegistry(
      activationSession.activatedExtensionIds
          .map(manifestRegistry.lookup)
          .whereType<ExtensionManifest>(),
    );
    final contributionRoutes = const ExtensionContributionRouter()
        .routeRegistry(activeRegistry);
    final supervisorSnapshot = ExtensionHostSupervisor(
      clock: clock,
    ).applyActivation(registry: manifestRegistry, session: activationSession);
    return AppExtensionStartupPlan(
      manifestRegistry: manifestRegistry,
      activationSession: activationSession,
      supervisorSnapshot: supervisorSnapshot,
      contributionRoutes: contributionRoutes,
    );
  }

  @visibleForTesting
  static ExtensionAgentToolExecutionRegistry?
  createAgentExtensionToolExecutionRegistry({
    ExtensionContributionRouteManifest? extensionContributionRoutes,
    ExtensionAgentToolHostBridge? hostBridge,
    ExtensionHostSupervisorSnapshot? extensionHostSupervisorSnapshot,
    RuntimeOutputLiveBuffer? runtimeOutputBuffer,
    ExtensionManifestRegistry? extensionManifestRegistry,
    ExtensionHostSupervisorExecutionBridge? extensionHostSupervisorBridge,
    Map<ExtensionHostSupervisorAction, ExtensionAgentToolHostRpcTransport>
        rpcTransports =
        const <
          ExtensionHostSupervisorAction,
          ExtensionAgentToolHostRpcTransport
        >{},
    Map<ExtensionHostSupervisorAction, String> rpcTransportIds =
        const <ExtensionHostSupervisorAction, String>{},
    Map<ExtensionHostSupervisorAction, String> rpcTransportLabels =
        const <ExtensionHostSupervisorAction, String>{},
    Map<ExtensionHostSupervisorAction, String> rpcTransportEndpoints =
        const <ExtensionHostSupervisorAction, String>{},
    Map<ExtensionHostSupervisorAction, Map<String, Object?>>
        rpcTransportMetadataByAction =
        const <ExtensionHostSupervisorAction, Map<String, Object?>>{},
    DateTime Function()? clock,
    Map<String, Object?> hostBridgeMetadata = const <String, Object?>{},
    Map<String, ExtensionAgentToolHandler> handlers =
        const <String, ExtensionAgentToolHandler>{},
  }) {
    if (extensionContributionRoutes == null) {
      return null;
    }
    final catalog = ExtensionAgentToolContributionCatalog.fromRoutes(
      extensionContributionRoutes,
    );
    var resolvedHostBridge = hostBridge;
    if (resolvedHostBridge == null &&
        extensionHostSupervisorSnapshot != null &&
        runtimeOutputBuffer != null) {
      final transportCatalog = createExtensionAgentToolRpcTransportCatalog(
        extensionContributionRoutes: extensionContributionRoutes,
        snapshot: extensionHostSupervisorSnapshot,
        rpcTransports: rpcTransports,
        rpcTransportIds: rpcTransportIds,
        rpcTransportLabels: rpcTransportLabels,
        rpcTransportEndpoints: rpcTransportEndpoints,
        rpcTransportMetadataByAction: rpcTransportMetadataByAction,
      );
      resolvedHostBridge = createExtensionAgentToolHostBridge(
        snapshot: extensionHostSupervisorSnapshot,
        buffer: runtimeOutputBuffer,
        manifestRegistry: extensionManifestRegistry,
        supervisorBridge: extensionHostSupervisorBridge,
        invoker: transportCatalog.toRegistry().invoke,
        clock: clock,
        metadata: hostBridgeMetadata,
      );
    }
    if (resolvedHostBridge != null) {
      return ExtensionAgentToolExecutionRegistry.fromHostBridge(
        catalog: catalog,
        hostBridge: resolvedHostBridge,
        handlers: handlers,
      );
    }
    return ExtensionAgentToolExecutionRegistry(
      catalog: catalog,
      handlers: handlers,
    );
  }

  @visibleForTesting
  static Map<ExtensionHostSupervisorAction, ExtensionAgentToolHostRpcTransport>
  createBuiltInExtensionAgentToolRpcTransports({
    required PlatformTarget platformTarget,
    required AgentProviderRegistry agentProviderRegistry,
  }) {
    return <ExtensionHostSupervisorAction, ExtensionAgentToolHostRpcTransport>{
      ExtensionHostSupervisorAction.runInProcess: (request) {
        return dispatchBuiltInExtensionAgentToolRpc(
          request: request,
          platformTarget: platformTarget,
          agentProviderRegistry: agentProviderRegistry,
        );
      },
    };
  }

  @visibleForTesting
  static Future<AgentToolCallDispatchResult>
  dispatchBuiltInExtensionAgentToolRpc({
    required ExtensionAgentToolHostRpcRequest request,
    required PlatformTarget platformTarget,
    required AgentProviderRegistry agentProviderRegistry,
  }) async {
    if (request.handlerId != 'collect-agent-surface-context') {
      return AgentToolCallDispatchResult.failure(
        callId: request.toolCall.callId,
        toolId: request.toolCall.toolId,
        message:
            'No built-in in-process extension RPC handler is registered for '
            '${request.extensionId}/${request.handlerId}.',
        metadata: <String, Object?>{
          'source': 'app-bootstrap-in-process-extension-rpc',
          'missingBuiltInHandler': true,
          'extensionId': request.extensionId,
          'handlerId': request.handlerId,
        },
      );
    }
    final input = _decodeToolInputObject(request.toolCall.inputText);
    final includeProviderStatus = input['includeProviderStatus'] == true;
    final output = <String, Object?>{
      'schema': 'vityo.agent-surface-context.v1',
      'extensionId': request.extensionId,
      'contributionId': request.contributionId,
      'handlerId': request.handlerId,
      'toolId': request.toolCall.toolId,
      'platformTarget': platformTarget.wireValue,
      'transportId': request.transportId,
      'transportAction': request.action.wireValue,
      if (includeProviderStatus)
        'providerRegistry': agentProviderRegistry.manifest().toJson(),
    };
    return AgentToolCallDispatchResult.success(
      callId: request.toolCall.callId,
      toolId: request.toolCall.toolId,
      output: jsonEncode(output),
      metadata: <String, Object?>{
        'source': 'app-bootstrap-in-process-extension-rpc',
        'extensionId': request.extensionId,
        'handlerId': request.handlerId,
        'includeProviderStatus': includeProviderStatus,
      },
    );
  }

  @visibleForTesting
  static ExtensionAgentToolHostRpcTransportCatalog
  createExtensionAgentToolRpcTransportCatalog({
    required ExtensionContributionRouteManifest extensionContributionRoutes,
    required ExtensionHostSupervisorSnapshot snapshot,
    required Map<
      ExtensionHostSupervisorAction,
      ExtensionAgentToolHostRpcTransport
    >
    rpcTransports,
    Map<ExtensionHostSupervisorAction, String> rpcTransportIds =
        const <ExtensionHostSupervisorAction, String>{},
    Map<ExtensionHostSupervisorAction, String> rpcTransportLabels =
        const <ExtensionHostSupervisorAction, String>{},
    Map<ExtensionHostSupervisorAction, String> rpcTransportEndpoints =
        const <ExtensionHostSupervisorAction, String>{},
    Map<ExtensionHostSupervisorAction, Map<String, Object?>>
        rpcTransportMetadataByAction =
        const <ExtensionHostSupervisorAction, Map<String, Object?>>{},
  }) {
    return ExtensionAgentToolHostRpcTransportCatalog.fromContributions(
      catalog: ExtensionAgentToolContributionCatalog.fromRoutes(
        extensionContributionRoutes,
      ),
      snapshot: snapshot,
      transports: rpcTransports,
      transportIds: rpcTransportIds,
      labels: rpcTransportLabels,
      endpoints: rpcTransportEndpoints,
      metadataByAction: rpcTransportMetadataByAction,
    );
  }

  @visibleForTesting
  static ExtensionAgentToolHostBridge createExtensionAgentToolHostBridge({
    required ExtensionHostSupervisorSnapshot snapshot,
    required RuntimeOutputLiveBuffer buffer,
    ExtensionManifestRegistry? manifestRegistry,
    ExtensionHostSupervisorExecutionBridge? supervisorBridge,
    ExtensionAgentToolHostInvoker? invoker,
    DateTime Function()? clock,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return ExtensionAgentToolActivatedHostBridge(
      snapshot: snapshot,
      buffer: buffer,
      manifestRegistry: manifestRegistry,
      supervisorBridge: supervisorBridge,
      invoker: invoker,
      clock: clock,
      metadata: metadata,
    ).call;
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

  static AgentProviderSelectionPlan? _selectConfiguredAgentProvider({
    required AgentPromptProfile profile,
    required AgentProviderSelectionPlan Function(AgentPromptProfile profile)?
    selectConfiguredProvider,
  }) {
    if (selectConfiguredProvider == null) {
      return null;
    }
    try {
      return selectConfiguredProvider(profile);
    } on Object {
      return null;
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
    LanguageServiceStatusController? languageServiceStatusController,
  }) async {
    languageServiceStatusController?.handleRuntimeEvent(
      StyioServiceRuntimeSessionEvent(
        state: StyioServiceRuntimeSessionState.refreshing,
      ),
    );
    final document = editorController.document;
    final report = await driver.analyzeDocumentWithReport(
      document,
      filePath: workspaceDocumentStore.filePathForDocumentId(
        document.documentId,
      ),
      configPath: projectContext.configPath,
      workingDirectory: projectContext.workingDirectory,
    );
    final event = _languageStatusEventFromReport(report);
    if (languageServiceStatusController == null) {
      languageServiceStatus.value =
          LanguageServiceStatusController.surfaceForRuntimeEvent(event);
    } else {
      languageServiceStatusController.handleRuntimeEvent(event);
    }
    editorController.refreshAnalysis();
    return report;
  }

  static StyioServiceRuntimeSessionEvent _languageStatusEventFromReport(
    StyioServiceAnalysisReport report,
  ) {
    final capabilitySnapshot = const StyioServiceCapabilityDetector()
        .detectReport(report);
    final state = report.serviceSucceeded
        ? StyioServiceRuntimeSessionState.active
        : StyioServiceRuntimeSessionState.failed;
    return StyioServiceRuntimeSessionEvent(
      state: state,
      statusSnapshot: StyioServiceRuntimeStatusSnapshot(
        state: state,
        disposed: false,
        providerManifest: LanguageProviderRegistry<Object?>().manifest(),
        capabilitySnapshot: capabilitySnapshot,
      ),
    );
  }
}

Map<String, Object?> _decodeToolInputObject(String inputText) {
  if (inputText.trim().isEmpty) {
    return const <String, Object?>{};
  }
  try {
    final decoded = jsonDecode(inputText);
    if (decoded is Map) {
      return decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
  } on Object {
    return const <String, Object?>{};
  }
  return const <String, Object?>{};
}
