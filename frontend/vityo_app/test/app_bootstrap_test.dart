import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_configurator.dart';
import 'package:vityo_app/src/app/app_bootstrap.dart';
import 'package:vityo_app/src/app/state/workspace_controller.dart';
import 'package:vityo_app/src/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/backend_toolchain/dependency_source_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/deployment_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/runtime_event_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/toolchain_management_adapter.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/integration/hosted_control_plane.dart';
import 'package:vityo_app/src/integration/project_graph_contract.dart';
import 'package:vityo_app/src/platform/native_module_loader.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/agent/agent_coding_session_controller.dart';
import 'package:vityo_app/src/view_ide/editor/editor_controller.dart';
import 'package:vityo_app/src/view_ide/editor/document_state.dart';
import 'package:vityo_app/src/view_ide/environment/configuration/configuration.dart';
import 'package:vityo_app/src/view_ide/interaction/language_service_status_surface.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/service.dart';
import 'package:vityo_app/src/view_ide/module_host/module_host.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_store_types.dart';

void main() {
  test('app bootstrap resolves language service project context', () {
    final context = AppBootstrap.resolveLanguageServiceProjectContext(
      workspaceRoot: '/workspace/demo',
      styioConfigPath: '/workspace/demo/styio.toml',
    );

    expect(context.workingDirectory, '/workspace/demo');
    expect(context.configPath, '/workspace/demo/styio.toml');
  });

  test('app bootstrap allows missing Styio config path', () {
    final context = AppBootstrap.resolveLanguageServiceProjectContext(
      workspaceRoot: '/workspace/scratch',
    );

    expect(context.workingDirectory, '/workspace/scratch');
    expect(context.configPath, isNull);
  });

  test(
    'app bootstrap binds language result cache to toolchain catalog changes',
    () async {
      final cache = StyioServiceResultCache()
        ..store(
          const StyioServiceResponse(
            status: StyioServiceStatus.succeeded,
            documentId: 'fixture://app-cache',
            revision: 1,
            toolchainId: 'styio-old',
          ),
        );
      final changes =
          StreamController<ToolchainCatalogConfigurationChange>.broadcast(
            sync: true,
          );
      addTearDown(changes.close);
      final binding = AppBootstrap.bindLanguageResultCacheToToolchainCatalog(
        resultCache: cache,
        catalogChanges: changes.stream,
      );
      addTearDown(binding.dispose);

      changes.add(
        ToolchainCatalogConfigurationChange(
          kind: ConfigurationSettingChangeKind.deleted,
          workspaceId: 'demo',
          catalog: null,
          emittedAt: DateTime.utc(2026, 5, 17),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(cache.length, 0);
    },
  );

  test('app bootstrap refreshes language service for active editor', () async {
    final cache = StyioServiceResultCache();
    final connector = _RecordingStyioConnector();
    final driver = StyioServiceAnalysisDriver(
      connector: connector,
      resultCache: cache,
    );
    const document = DocumentState(
      documentId: 'fixture://app-editor',
      text: '#main := () => {}',
      revision: 2,
    );
    final editorController = EditorSessionController(
      initialDocument: document,
      languageService: createRoutedStyioLanguageService(resultCache: cache),
    );
    final status = ValueNotifier<LanguageServiceStatusSurface>(
      LanguageServiceStatusSurface.refreshing(),
    );
    final statusController = LanguageServiceStatusController(notifier: status);
    addTearDown(statusController.dispose);
    addTearDown(status.dispose);

    final report = await AppBootstrap.refreshLanguageServiceForEditor(
      driver: driver,
      editorController: editorController,
      workspaceDocumentStore: const _MappedWorkspaceDocumentStore(
        filePath: '/workspace/src/main.styio',
      ),
      projectContext: const AppLanguageServiceProjectContext(
        workingDirectory: '/workspace',
        configPath: '/workspace/styio.toml',
      ),
      languageServiceStatus: status,
      languageServiceStatusController: statusController,
    );

    expect(report.response.configPath, '/workspace/styio.toml');
    expect(report.response.workingDirectory, '/workspace');
    expect(connector.documents.single.filePath, '/workspace/src/main.styio');
    expect(connector.documents.single.configPath, '/workspace/styio.toml');
    expect(connector.documents.single.workingDirectory, '/workspace');
    expect(editorController.analysis.diagnostics.single.code, 'styio.app');
    expect(status.value.primaryCapabilityStates['diagnostics'], 'available');
  });

  test('app bootstrap creates workspace diagnostics request', () {
    const activeDocument = DocumentState(
      documentId: '/workspace/demo/src/main.styio',
      text: '#main := () => {}',
      revision: 1,
    );
    final projectGraph = _hostedProjectGraph();
    final workspaceController = WorkspaceController(
      projectSnapshot: projectGraph,
    );
    final editorController = EditorSessionController(
      initialDocument: activeDocument,
      languageService: createRoutedStyioLanguageService(
        resultCache: StyioServiceResultCache(),
      ),
    );

    final request = AppBootstrap.createWorkspaceDiagnosticsRequest(
      editorController: editorController,
      workspaceController: workspaceController,
      workspaceDocuments: const <DocumentState>[
        DocumentState(
          documentId: '/workspace/demo/src/feature.styio',
          text: '#feature := () => {}',
          revision: 1,
        ),
      ],
    );

    expect(request.activeDocumentId, activeDocument.documentId);
    expect(request.documentIds, contains(activeDocument.documentId));
    expect(
      request.documents.map((document) => document.documentId),
      contains(activeDocument.documentId),
    );
    expect(
      request.documents.map((document) => document.documentId),
      contains('/workspace/demo/src/feature.styio'),
    );
  });

  test(
    'app bootstrap uses hosted document store for hosted workspaces',
    () async {
      final localStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          '/workspace/demo/src/main.styio': DocumentState(
            documentId: '/workspace/demo/src/main.styio',
            text: 'local := true\n',
            revision: 1,
          ),
        },
      );
      final hostedClient = _RecordingHostedControlPlaneClient();
      final store = await AppBootstrap.createEditorWorkspaceDocumentStore(
        platformTarget: PlatformTarget.ios,
        localStore: localStore,
        projectSnapshot: _hostedProjectGraph(),
        hostedClientProvider: ({required platformTarget}) async => hostedClient,
      );

      final document = await store.loadDocument(
        '/workspace/demo/src/main.styio',
      );
      expect(document.text, 'remote := true\n');
      expect(document.revision, 3);

      final edited = document.replaceRange(
        start: document.text.indexOf('true'),
        end: document.text.indexOf('true') + 'true'.length,
        replacement: 'false',
      );
      await store.saveDocument(edited);

      expect(hostedClient.loadedPaths, <String>[
        '/workspace/demo/src/main.styio',
      ]);
      expect(hostedClient.savedDocuments.single['path'], edited.documentId);
      expect(
        hostedClient.savedDocuments.single['documentText'],
        'remote := false\n',
      );
      expect(hostedClient.savedDocuments.single['revision'], 4);
    },
  );

  test('app bootstrap service wiring manifest accounts for injections', () {
    final bootstrap = _createMinimalBootstrap();
    addTearDown(bootstrap.dispose);

    final manifest = bootstrap.serviceWiringManifest();
    final serviceIds = manifest.entries
        .map((entry) => entry.descriptor.serviceId)
        .toList(growable: false);

    expect(serviceIds.toSet(), hasLength(serviceIds.length));
    expect(serviceIds, contains('module.registry'));
    expect(serviceIds, contains('toolchain.manager'));
    expect(serviceIds, contains('workspace.diagnostics-controller'));
    expect(manifest.missingRequiredEntries, isEmpty);
    expect(manifest.absentWithoutCapabilityGapEntries, isEmpty);
    expect(manifest.allServicesAccountedFor, isTrue);
    expect(
      manifest.entries
          .where((entry) => !entry.descriptor.requiredInjection)
          .every(
            (entry) =>
                entry.descriptor.capabilityGapCode != null &&
                entry.descriptor.capabilityGapCode!.isNotEmpty,
          ),
      isTrue,
    );

    final json = manifest.toJson();
    expect(json['platformTarget'], PlatformTarget.windows.name);
    expect(json['allServicesAccountedFor'], isTrue);
    expect(json.toString(), isNot(contains('Instance of')));
  });
}

AppBootstrap _createMinimalBootstrap() {
  const projectGraph = ProjectGraphSnapshot(
    id: 'bootstrap-fixture',
    title: 'bootstrap/fixture',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/bootstrap',
    workspaceMembers: <String>[],
    manifestPath: '/workspace/bootstrap/pafio.toml',
    packages: <ProjectPackageSnapshot>[],
    dependencies: <ProjectDependencySnapshot>[],
    targets: <ProjectTargetDescriptor>[],
    editorFiles: <String>['/workspace/bootstrap/src/main.styio'],
    toolchain: ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'bootstrap fixture toolchain',
    ),
    lockState: ProjectLockState.fresh,
    vendorState: ProjectVendorState.present,
    notes: <String>[],
  );
  final workspaceController = WorkspaceController(
    projectSnapshot: projectGraph,
  );
  final editorController = EditorSessionController(
    initialDocument: const DocumentState(
      documentId: '/workspace/bootstrap/src/main.styio',
      text: '#main := () => {}',
      revision: 1,
    ),
    languageService: createRoutedStyioLanguageService(
      resultCache: StyioServiceResultCache(),
    ),
  );
  final agentController = AgentCodingSessionController(
    profile: AgentPromptProfile.openAICodexSparkForPlatform(
      PlatformTarget.windows,
    ),
    adapter: const LocalOnlyAgentProviderAdapter(),
    contextProvider: _emptyAgentContext,
  );
  return AppBootstrap(
    platformTarget: PlatformTarget.windows,
    moduleRegistry: ModuleRegistry(
      platformTarget: PlatformTarget.windows,
      definitions: const <ModuleDefinition>[],
    ),
    nativeModuleLoader: const NoopNativeModuleLoader(
      platformTarget: PlatformTarget.windows,
    ),
    projectGraphAdapter: _NoopProjectGraphAdapter(),
    supplementalAdapterCapabilities: normalizeCapabilitySnapshots(
      const <AdapterCapabilitySnapshot>[],
    ),
    workspaceController: workspaceController,
    workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
    editorController: editorController,
    executionAdapter: _NoopExecutionAdapter(),
    executionAdapterFactory: (_) async => _NoopExecutionAdapter(),
    runtimeEventAdapter: NoopRuntimeEventAdapter(
      capabilitySnapshot: _capabilitySnapshot(),
    ),
    dependencySourceAdapter: _NoopDependencySourceAdapter(),
    deploymentAdapter: _NoopDeploymentAdapter(),
    toolchainManagementAdapter: _NoopToolchainManagementAdapter(),
    agentCodingController: agentController,
    agentProviderConfigurator: AgentProviderConfigurator(
      workspaceId: 'bootstrap-fixture',
      saveProfile:
          ({required workspaceId, required key, required profile}) async {},
      createAdapter: (_) async => const LocalOnlyAgentProviderAdapter(),
    ),
  );
}

AgentSessionContext _emptyAgentContext() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: '/workspace/bootstrap/src/main.styio',
      text: '#main := () => {}',
      revision: 1,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const <Diagnostic>[],
  );
}

class _NoopProjectGraphAdapter implements ProjectGraphAdapter {
  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => _capabilitySnapshot(
    projectGraph: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail: 'bootstrap fixture project graph',
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopExecutionAdapter implements ExecutionAdapter {
  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => _capabilitySnapshot(
    execution: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.available,
      detail: 'bootstrap fixture execution',
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopDependencySourceAdapter implements DependencySourceAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopDeploymentAdapter implements DeploymentAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoopToolchainManagementAdapter implements ToolchainManagementAdapter {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

AdapterCapabilitySnapshot _capabilitySnapshot({
  AdapterEndpointCapability languageService = const AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'bootstrap fixture language service unavailable',
  ),
  AdapterEndpointCapability projectGraph = const AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'bootstrap fixture project graph unavailable',
  ),
  AdapterEndpointCapability execution = const AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'bootstrap fixture execution unavailable',
  ),
  AdapterEndpointCapability runtimeEvents = const AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'bootstrap fixture runtime events unavailable',
  ),
}) {
  return AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cli,
    languageService: languageService,
    projectGraph: projectGraph,
    execution: execution,
    runtimeEvents: runtimeEvents,
  );
}

class _RecordingStyioConnector implements StyioServiceConnector {
  final List<StyioServiceDocument> documents = <StyioServiceDocument>[];

  @override
  Future<StyioServiceResponse> analyzeDocument(
    StyioServiceDocument document,
  ) async {
    documents.add(document);
    return StyioServiceResponse(
      status: StyioServiceStatus.succeeded,
      documentId: document.documentId,
      revision: document.revision,
      configPath: document.configPath,
      workingDirectory: document.workingDirectory,
      diagnostics: const <StyioServiceDiagnosticDto>[
        StyioServiceDiagnosticDto(
          severity: DiagnosticSeverity.warning,
          code: 'styio.app',
          message: 'app diagnostic',
          range: SourceRange(start: 0, end: 1),
        ),
      ],
    );
  }
}

class _RecordingHostedControlPlaneClient implements HostedControlPlaneClient {
  final List<String> loadedPaths = <String>[];
  final List<Map<String, Object?>> savedDocuments = <Map<String, Object?>>[];

  @override
  HostedControlPlaneConfig get config => const HostedControlPlaneConfig(
    baseUrl: 'https://hosted.example.test',
    workspaceRoot: '/workspace/demo',
    workspaceId: 'demo-workspace',
  );

  @override
  Future<Map<String, dynamic>> loadDocument({
    required String workspaceId,
    required String path,
  }) async {
    loadedPaths.add(path);
    return <String, dynamic>{
      'returncode': 0,
      'message': 'loaded hosted document',
      'payload': <String, Object?>{
        'path': path,
        'document_text': 'remote := true\n',
        'revision': 3,
      },
    };
  }

  @override
  Future<Map<String, dynamic>> saveDocument({
    required String workspaceId,
    required String path,
    required String documentText,
    required int revision,
  }) async {
    savedDocuments.add(<String, Object?>{
      'workspaceId': workspaceId,
      'path': path,
      'documentText': documentText,
      'revision': revision,
    });
    return <String, dynamic>{
      'returncode': 0,
      'message': 'saved hosted document',
      'payload': <String, Object?>{
        'path': path,
        'revision': revision,
        'saved': true,
      },
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProjectGraphSnapshot _hostedProjectGraph() {
  return ProjectGraphSnapshot(
    id: '/workspace/demo/pafio.toml',
    title: 'demo/app',
    kind: ProjectKind.hosted,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/demo/pafio.toml',
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: const <String>['/workspace/demo/src/main.styio'],
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.managedCurrent,
      detail: 'hosted toolchain',
      channel: 'stable',
      version: '0.0.2',
    ),
    lockState: ProjectLockState.fresh,
    vendorState: ProjectVendorState.present,
    hostedWorkspace: HostedWorkspaceRecordSnapshot(
      workspaceId: 'demo-workspace',
      schemaVersion: '1',
      ownerRef: 'Vityo',
      status: HostedWorkspaceStatus.active,
      entryUrl: 'https://hosted.example.test/workspaces/demo-workspace',
      createdAt: DateTime.utc(2026, 5, 17),
      lastActiveAt: DateTime.utc(2026, 5, 17, 1),
      retentionDays: 7,
      exportState: HostedWorkspaceExportState.notRequested,
    ),
    notes: const <String>[],
  );
}

class _MappedWorkspaceDocumentStore implements WorkspaceDocumentStore {
  const _MappedWorkspaceDocumentStore({required this.filePath});

  final String filePath;

  @override
  String? filePathForDocumentId(String documentId) => filePath;

  @override
  Future<DocumentState> loadDocument(String path) async {
    return DocumentState(documentId: path, text: '', revision: 0);
  }

  @override
  Future<void> saveDocument(DocumentState document) async {}

  @override
  Future<bool> deleteDocument(String path) async => false;

  @override
  Future<bool> documentExists(String path) async => true;
}
