import 'dart:async';

import 'package:flutter/foundation.dart';

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
import '../view_ide/environment/environment.dart';
import '../view_ide/foundation/foundation.dart';
import '../view_ide/language/service/language_service_foundation.dart';
import '../view_ide/language/service/styio_service_capability_detector.dart';
import '../view_ide/language/service/styio_service_connector.dart';
import '../view_ide/language/service/styio_service_runtime.dart';
import '../view_ide/toolchain/toolchain_catalog.dart';
import '../view_ide/toolchain/toolchain_configuration_store.dart';
import '../view_ide/toolchain/toolchain_manager.dart';
import '../view_ide/toolchain/styio_toolchain_discovery.dart';
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
    ValueNotifier<LanguageServiceStatusSurface>? languageServiceStatus,
    this.toolchainManager,
    this.toolchainStatusReport,
    this.toolchainCatalogSubscription,
    this.languageResultCacheBinding,
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
  final ToolchainManager? toolchainManager;
  final ValueNotifier<LanguageServiceStatusSurface> languageServiceStatus;
  final ValueListenable<ToolchainManagerStatusReport>? toolchainStatusReport;
  final StreamSubscription<ToolchainCatalogConfigurationChange>?
  toolchainCatalogSubscription;
  final StyioServiceToolchainCacheBinding? languageResultCacheBinding;

  void dispose() {
    unawaited(toolchainCatalogSubscription?.cancel());
    unawaited(languageResultCacheBinding?.dispose());
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
    final configurationStore = _createConfigurationStore(platformManagers);
    final toolchainStore = ToolchainConfigurationStore(
      configurationStore: configurationStore,
    );
    await ensureDefaultLanguageServiceToolchainCatalog(
      toolchainStore: toolchainStore,
      workspaceId: projectSnapshot.id,
      targetId: platformManagers.context.targetId,
    );
    final toolchainManager = ToolchainManager(
      configurationStore: toolchainStore,
      platformManagers: platformManagers,
      workspaceId: projectSnapshot.id,
    );
    final toolchainStatusReport = ValueNotifier<ToolchainManagerStatusReport>(
      await toolchainManager.statusReport(kind: ToolchainKind.languageService),
    );
    final toolchainCatalogChanges = toolchainStore
        .watchCatalog(workspaceId: projectSnapshot.id)
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
    unawaited(() async {
      try {
        await refreshLanguageServiceForEditor(
          driver: languageServiceDriver,
          editorController: editorController,
          workspaceDocumentStore: workspaceDocumentStore,
          projectContext: languageProjectContext,
          languageServiceStatus: languageServiceStatus,
        );
      } on Object catch (error) {
        languageServiceStatus.value = LanguageServiceStatusSurface.failed(
          message:
              'StyioService failed while refreshing language facts: $error',
        );
      }
    }());
    toolchainCatalogSubscription = toolchainCatalogChanges.listen((_) {
      unawaited(
        toolchainManager.statusReport(kind: ToolchainKind.languageService).then(
          (report) {
            toolchainStatusReport.value = report;
          },
        ),
      );
      unawaited(() async {
        try {
          await refreshLanguageServiceForEditor(
            driver: languageServiceDriver,
            editorController: editorController,
            workspaceDocumentStore: workspaceDocumentStore,
            projectContext: languageProjectContext,
            languageServiceStatus: languageServiceStatus,
          );
        } on Object catch (error) {
          languageServiceStatus.value = LanguageServiceStatusSurface.failed(
            message:
                'StyioService failed while refreshing language facts: $error',
          );
        }
      }());
    });

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
      toolchainManager: toolchainManager,
      languageServiceStatus: languageServiceStatus,
      toolchainStatusReport: toolchainStatusReport,
      toolchainCatalogSubscription: toolchainCatalogSubscription,
      languageResultCacheBinding: languageResultCacheBinding,
    );
  }

  static ConfigurationStore _createConfigurationStore(
    PlatformManagerBundle platformManagers,
  ) {
    final dataStore = FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: platformManagers.resource,
        fileSystemManager: platformManagers.fileSystem,
      ),
      fileSystemManager: platformManagers.fileSystem,
    );
    return ConfigurationStore(
      dataStore: dataStore,
      credentialDataStore: FoundationCredentialDataStore(dataStore: dataStore),
    );
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
