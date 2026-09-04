import 'dart:async';

import 'package:flutter/foundation.dart';

import '../ide/agent_client/agent_client.dart';
import '../ide/workbench/agent_collaboration/agent_collaboration_service.dart';
import '../ide/workspace/workspace_transaction_service.dart';
import '../ide/editor/editor_controller.dart';
import '../view_ide/backend_toolchain/adapter_contracts.dart';
import '../view_ide/backend_toolchain/backend_provider.dart';
import '../view_ide/backend_toolchain/default_backend_providers.dart';
import '../view_ide/backend_toolchain/dependency_source_adapter.dart';
import '../view_ide/backend_toolchain/deployment_adapter.dart';
import '../view_ide/backend_toolchain/execution_adapter.dart';
import '../view_ide/backend_toolchain/hosted_control_plane.dart';
import '../view_ide/backend_toolchain/project_graph_adapter.dart';
import '../view_ide/backend_toolchain/project_graph_contract.dart';
import '../view_ide/backend_toolchain/runtime_event_adapter.dart';
import '../view_ide/interaction/interaction.dart';
import '../ide/editor/document_state.dart';
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
import '../view_ide/services/observable_topology/observable_topology.dart';
import '../view_ide/backend_toolchain/observable_snapshot_publisher_web.dart'
    if (dart.library.io) '../view_ide/backend_toolchain/observable_snapshot_publisher_io.dart';
import '../ide/workspace/workspace_diagnostics.dart';
import '../ide/workspace/workspace_diagnostics_controller.dart';
import '../ide/workspace/source_control_status.dart';
import '../ide/workspace/source_control_status_controller.dart';
import '../view_ide/platform/native_module_loader.dart';
import '../view_ide/platform/platform_target.dart';
import '../ide/workspace/workspace_document_store.dart';
import '../ide/workspace/workspace_controller.dart';

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

enum AppBootstrapServiceWiringState { injected, absent }

extension AppBootstrapServiceWiringStateWire on AppBootstrapServiceWiringState {
  String get wireValue {
    return switch (this) {
      AppBootstrapServiceWiringState.injected => 'injected',
      AppBootstrapServiceWiringState.absent => 'absent',
    };
  }
}

class AppBootstrapServiceDescriptor {
  const AppBootstrapServiceDescriptor({
    required this.serviceId,
    required this.ownerLayer,
    required this.requiredInjection,
    this.capabilityGapCode,
    this.recoveryAction,
  });

  final String serviceId;
  final String ownerLayer;
  final bool requiredInjection;
  final String? capabilityGapCode;
  final String? recoveryAction;

  bool get hasAbsentStateContract {
    return requiredInjection ||
        (capabilityGapCode != null && capabilityGapCode!.isNotEmpty);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'serviceId': serviceId,
      'ownerLayer': ownerLayer,
      'required': requiredInjection,
      if (capabilityGapCode != null) 'capabilityGapCode': capabilityGapCode,
      if (recoveryAction != null) 'recoveryAction': recoveryAction,
    };
  }
}

class AppBootstrapServiceWiringEntry {
  const AppBootstrapServiceWiringEntry({
    required this.descriptor,
    required this.state,
  });

  final AppBootstrapServiceDescriptor descriptor;
  final AppBootstrapServiceWiringState state;

  bool get injected => state == AppBootstrapServiceWiringState.injected;

  bool get accountedFor {
    return injected || descriptor.hasAbsentStateContract;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      ...descriptor.toJson(),
      'state': state.wireValue,
      'accountedFor': accountedFor,
    };
  }
}

class AppBootstrapServiceWiringManifest {
  AppBootstrapServiceWiringManifest({
    required this.platformTarget,
    required Iterable<AppBootstrapServiceWiringEntry> entries,
  }) : entries = List<AppBootstrapServiceWiringEntry>.unmodifiable(entries);

  final PlatformTarget platformTarget;
  final List<AppBootstrapServiceWiringEntry> entries;

  List<AppBootstrapServiceWiringEntry> get missingRequiredEntries {
    return entries
        .where((entry) => entry.descriptor.requiredInjection && !entry.injected)
        .toList(growable: false);
  }

  List<AppBootstrapServiceWiringEntry> get absentWithoutCapabilityGapEntries {
    return entries
        .where((entry) => !entry.injected && !entry.accountedFor)
        .toList(growable: false);
  }

  bool get allServicesAccountedFor {
    return missingRequiredEntries.isEmpty &&
        absentWithoutCapabilityGapEntries.isEmpty;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'platformTarget': platformTarget.name,
      'allServicesAccountedFor': allServicesAccountedFor,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

class AppBootstrap {
  AppBootstrap({
    required this.platformTarget,
    required this.backendProvider,
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
    this.agentClientRegistry,
    this.agentCollaboration,
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
    this.observableGraphController,
    this.sourceControlStatusController,
    this.projectLanguageService,
  }) : runtimeOutputBuffer = runtimeOutputBuffer ?? RuntimeOutputLiveBuffer(),
       languageServiceStatus =
           languageServiceStatus ??
           ValueNotifier<LanguageServiceStatusSurface>(
             LanguageServiceStatusSurface.unavailable(),
           );

  final PlatformTarget platformTarget;
  final BackendProvider backendProvider;
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
  final AgentClientRegistry? agentClientRegistry;
  final AgentCollaborationService? agentCollaboration;
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
  final ObservableGraphController? observableGraphController;
  final SourceControlStatusController? sourceControlStatusController;
  final ProjectStyioLanguageService? projectLanguageService;

  void dispose() {
    unawaited(toolchainCatalogSubscription?.cancel());
    unawaited(languageResultCacheBinding?.dispose());
    unawaited(styioServiceSubscriptionController?.dispose());
    unawaited(languageServiceStatusController?.dispose());
    workspaceDiagnosticsController?.dispose();
    testingSessionController?.dispose();
    observableGraphController?.dispose();
    sourceControlStatusController?.dispose();
    final collaboration = agentCollaboration;
    if (collaboration != null) {
      unawaited(collaboration.close());
    } else {
      final agentClients = agentClientRegistry;
      if (agentClients != null) {
        unawaited(agentClients.close());
      }
    }
  }

  List<AdapterCapabilitySnapshot> get adapterCapabilities =>
      normalizeCapabilitySnapshots([
        projectGraphAdapter.capabilitySnapshot,
        executionAdapter.capabilitySnapshot,
        runtimeEventAdapter.capabilitySnapshot,
        ...supplementalAdapterCapabilities,
      ]);

  static const List<AppBootstrapServiceDescriptor> serviceWiringDescriptors =
      <AppBootstrapServiceDescriptor>[
        AppBootstrapServiceDescriptor(
          serviceId: 'platform.target',
          ownerLayer: 'app',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'module.registry',
          ownerLayer: 'module-host',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'module.native-loader',
          ownerLayer: 'platform',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'project-graph.adapter',
          ownerLayer: 'backend-toolchain',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'adapter.supplemental-capabilities',
          ownerLayer: 'backend-toolchain',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'workspace.controller',
          ownerLayer: 'app',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'workspace.document-store',
          ownerLayer: 'app',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'editor.controller',
          ownerLayer: 'interaction',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'execution.adapter',
          ownerLayer: 'backend-toolchain',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'execution.adapter-factory',
          ownerLayer: 'backend-toolchain',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'runtime.event-adapter',
          ownerLayer: 'runtime',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'dependency-source.adapter',
          ownerLayer: 'backend-toolchain',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'deployment.adapter',
          ownerLayer: 'backend-toolchain',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'toolchain.management-adapter',
          ownerLayer: 'toolchain',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'runtime.output-buffer',
          ownerLayer: 'runtime',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'language.status',
          ownerLayer: 'service',
          requiredInjection: true,
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'agent.client-registry',
          ownerLayer: 'agent-client',
          requiredInjection: false,
          capabilityGapCode: 'agent.client.unavailable',
          recoveryAction: 'openSettings',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'agent.workspace-transactions',
          ownerLayer: 'workspace',
          requiredInjection: false,
          capabilityGapCode: 'agent.workspace-transactions.unavailable',
          recoveryAction: 'openSettings',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'agent.collaboration',
          ownerLayer: 'agent-client',
          requiredInjection: false,
          capabilityGapCode: 'agent.collaboration.unavailable',
          recoveryAction: 'openSettings',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'extension.startup-plan',
          ownerLayer: 'extension',
          requiredInjection: false,
          capabilityGapCode: 'extension.startup-plan.unavailable',
          recoveryAction: 'refreshModules',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'command-palette.preferences-store',
          ownerLayer: 'interaction',
          requiredInjection: false,
          capabilityGapCode: 'command-palette.preferences.unavailable',
          recoveryAction: 'openSettings',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'theme.override-store',
          ownerLayer: 'appearance',
          requiredInjection: false,
          capabilityGapCode: 'theme.override-store.unavailable',
          recoveryAction: 'openSettings',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'language.refresh-active-service',
          ownerLayer: 'service',
          requiredInjection: false,
          capabilityGapCode: 'language.refresh.unavailable',
          recoveryAction: 'refreshLanguageService',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'language.subscription-controller',
          ownerLayer: 'service',
          requiredInjection: false,
          capabilityGapCode: 'language.subscription.unavailable',
          recoveryAction: 'refreshLanguageService',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'language.status-controller',
          ownerLayer: 'service',
          requiredInjection: false,
          capabilityGapCode: 'language.status-controller.unavailable',
          recoveryAction: 'refreshLanguageService',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'toolchain.manager',
          ownerLayer: 'toolchain',
          requiredInjection: false,
          capabilityGapCode: 'toolchain.manager.unavailable',
          recoveryAction: 'openSettings',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'toolchain.status-report',
          ownerLayer: 'toolchain',
          requiredInjection: false,
          capabilityGapCode: 'toolchain.status-report.unavailable',
          recoveryAction: 'openSettings',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'toolchain.clang-cpp-preference',
          ownerLayer: 'toolchain',
          requiredInjection: false,
          capabilityGapCode: 'toolchain.clang-cpp-preference.unavailable',
          recoveryAction: 'openSettings',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'toolchain.catalog-subscription',
          ownerLayer: 'toolchain',
          requiredInjection: false,
          capabilityGapCode: 'toolchain.catalog-subscription.unavailable',
          recoveryAction: 'openSettings',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'language.result-cache-binding',
          ownerLayer: 'service',
          requiredInjection: false,
          capabilityGapCode: 'language.result-cache-binding.unavailable',
          recoveryAction: 'refreshLanguageService',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'workspace.diagnostics-controller',
          ownerLayer: 'workspace',
          requiredInjection: false,
          capabilityGapCode: 'workspace.diagnostics.unavailable',
          recoveryAction: 'refreshLanguageService',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'testing.session-controller',
          ownerLayer: 'testing',
          requiredInjection: false,
          capabilityGapCode: 'testing.session.unavailable',
          recoveryAction: 'runTests',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'observable.graph-controller',
          ownerLayer: 'service',
          requiredInjection: false,
          capabilityGapCode: 'observable.topology.unavailable',
          recoveryAction: 'refreshObservableGraph',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'source-control.status-controller',
          ownerLayer: 'source-control',
          requiredInjection: false,
          capabilityGapCode: 'source-control.status.unavailable',
          recoveryAction: 'refreshSourceControl',
        ),
        AppBootstrapServiceDescriptor(
          serviceId: 'language.project-service',
          ownerLayer: 'service',
          requiredInjection: false,
          capabilityGapCode: 'language.project-service.unavailable',
          recoveryAction: 'refreshLanguageService',
        ),
      ];

  AppBootstrapServiceWiringManifest serviceWiringManifest() {
    final injectedByServiceId = <String, bool>{
      'platform.target': true,
      'module.registry': true,
      'module.native-loader': true,
      'project-graph.adapter': true,
      'adapter.supplemental-capabilities': true,
      'workspace.controller': true,
      'workspace.document-store': true,
      'editor.controller': true,
      'execution.adapter': true,
      'execution.adapter-factory': true,
      'runtime.event-adapter': true,
      'dependency-source.adapter': true,
      'deployment.adapter': true,
      'toolchain.management-adapter': true,
      'runtime.output-buffer': true,
      'language.status': true,
      'agent.client-registry': agentClientRegistry != null,
      'agent.workspace-transactions': agentCollaboration != null,
      'agent.collaboration': agentCollaboration != null,
      'extension.startup-plan': extensionStartupPlan != null,
      'command-palette.preferences-store':
          commandPalettePreferencesStore != null,
      'theme.override-store': themeOverrideStore != null,
      'language.refresh-active-service': refreshActiveLanguageService != null,
      'language.subscription-controller':
          styioServiceSubscriptionController != null,
      'language.status-controller': languageServiceStatusController != null,
      'toolchain.manager': toolchainManager != null,
      'toolchain.status-report': toolchainStatusReport != null,
      'toolchain.clang-cpp-preference': clangCppVersionPreference != null,
      'toolchain.catalog-subscription': toolchainCatalogSubscription != null,
      'language.result-cache-binding': languageResultCacheBinding != null,
      'workspace.diagnostics-controller':
          workspaceDiagnosticsController != null,
      'testing.session-controller': testingSessionController != null,
      'observable.graph-controller': observableGraphController != null,
      'source-control.status-controller': sourceControlStatusController != null,
      'language.project-service': projectLanguageService != null,
    };
    return AppBootstrapServiceWiringManifest(
      platformTarget: platformTarget,
      entries: serviceWiringDescriptors.map((descriptor) {
        final injected = injectedByServiceId[descriptor.serviceId] ?? false;
        return AppBootstrapServiceWiringEntry(
          descriptor: descriptor,
          state: injected
              ? AppBootstrapServiceWiringState.injected
              : AppBootstrapServiceWiringState.absent,
        );
      }),
    );
  }

  static Future<AppBootstrap> load({
    BackendProviderRegistry? backendProviders,
    Map<String, AgentLaunchDescriptor> agentLaunchDescriptors =
        const <String, AgentLaunchDescriptor>{},
    AgentClientPolicy agentClientPolicy = const AgentClientPolicy(),
    WorkspaceTransactionService? agentWorkspaceTransactions,
  }) async {
    if (agentLaunchDescriptors.isNotEmpty &&
        agentWorkspaceTransactions == null) {
      throw ArgumentError.value(
        agentWorkspaceTransactions,
        'agentWorkspaceTransactions',
        'Configured Agents require an IDE-owned workspace transaction '
            'authority.',
      );
    }
    final platformTarget = detectPlatformTarget();
    final backendProvider =
        (backendProviders ?? createDefaultBackendProviderRegistry()).resolve(
          platformTarget,
        );
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
    final projectGraphAdapter = await backendProvider
        .createProjectGraphAdapter();
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
      return backendProvider.createExecutionAdapter(refreshedProjectGraph);
    }

    final executionAdapter = await executionAdapterFactory(projectSnapshot);
    final runtimeEventAdapter = backendProvider.createRuntimeEventAdapter();
    final dependencySourceAdapter = await backendProvider
        .createDependencySourceAdapter();
    final deploymentAdapter = await backendProvider.createDeploymentAdapter();
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
    final ioDesktop =
        platformTarget == PlatformTarget.windows ||
        platformTarget == PlatformTarget.linux ||
        platformTarget == PlatformTarget.macos;
    final observableGraphController =
        ioDesktop && !projectSnapshot.isHosted
        ? ObservableGraphController(
            publisher: createObservableSnapshotPublisher(),
            projectGraph: () => workspaceController.activeProject,
            ioPlatform: true,
            fileSystemManager: platformManagers.fileSystem,
          )
        : null;
    if (observableGraphController != null) {
      unawaited(observableGraphController.start());
    }
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
    final agentClientRegistry = createAgentClientRegistry(
      descriptors: agentLaunchDescriptors,
      policy: agentClientPolicy,
    );
    final agentCollaboration = createAgentCollaboration(
      registry: agentClientRegistry,
      transactions: agentWorkspaceTransactions,
      workspaceRoot: Uri.directory(
        workspaceController.activeProject.workspaceRoot,
      ),
    );

    return AppBootstrap(
      platformTarget: platformTarget,
      backendProvider: backendProvider,
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
      agentClientRegistry: agentClientRegistry,
      agentCollaboration: agentCollaboration,
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
      observableGraphController: observableGraphController,
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

  /// Supervises only the Agent runtimes Vityo was explicitly given.
  ///
  /// Vityo never configures a model provider, so an empty descriptor set is
  /// the normal state and leaves the IDE fully operable without an Agent.
  @visibleForTesting
  static AgentClientRegistry? createAgentClientRegistry({
    required Map<String, AgentLaunchDescriptor> descriptors,
    AgentClientPolicy policy = const AgentClientPolicy(),
  }) {
    if (descriptors.isEmpty) {
      return null;
    }
    return AgentClientRegistry(descriptors: descriptors, policy: policy);
  }

  @visibleForTesting
  static AgentCollaborationService? createAgentCollaboration({
    required AgentClientRegistry? registry,
    required WorkspaceTransactionService? transactions,
    required Uri workspaceRoot,
  }) {
    if (registry == null) {
      return null;
    }
    if (transactions == null) {
      throw ArgumentError.value(
        transactions,
        'transactions',
        'A configured Agent Client requires an IDE-owned workspace '
            'transaction authority.',
      );
    }
    return AgentCollaborationService(
      registry: registry,
      transactions: transactions,
      workspaceRoot: workspaceRoot,
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
  }) {
    return AppLanguageServiceProjectContext(
      workingDirectory: workspaceRoot,
      configPath: null,
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
