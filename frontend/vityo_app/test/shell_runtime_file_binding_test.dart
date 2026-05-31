import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/interaction/document_resource_binding.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/dependency_source_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/deployment_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/hosted_control_plane.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/runtime_event_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/toolchain_management_adapter.dart';
import 'package:vityo_app/src/view_ide/commands/app_commands.dart';
import 'package:vityo_app/src/view_ide/editor/controller/editor_controller.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_language_service.dart';
import 'package:vityo_app/src/view_ide/module_host/module_registry.dart';
import 'package:vityo_app/src/view_ide/platform/native_module_loader.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/shell_runtime_model.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_controller.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_call_hierarchy.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_store.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_problems.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_quick_open.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_reference_search.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_search.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_symbol_search.dart';

void main() {
  test('shell save command persists through editor file binding', () async {
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/demo',
      activeFilePath: 'src/main.styio',
      title: 'Demo',
      notes: const <String>[],
    );
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'value := 1\n',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': initialDocument,
      },
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: documentStore,
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: initialDocument,
        languageService: const _NoopStyioLanguageService(),
      ),
      executionAdapter: const _NoopExecutionAdapter(),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          const _NoopExecutionAdapter(),
      runtimeEventAdapter: const _NoopRuntimeEventAdapter(),
      dependencySourceAdapter: const _NoopDependencySourceAdapter(),
      deploymentAdapter: const _NoopDeploymentAdapter(),
      toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    shell.editorController.insertText('value := 2');

    expect(
      shell.editorFileBindingSnapshot.state,
      DocumentResourceBindingState.boundDirty,
    );

    await shell.executeCommand(AppCommandId.save);

    expect(
      shell.editorFileBindingSnapshot.state,
      DocumentResourceBindingState.boundClean,
    );
    final persisted = await documentStore.loadDocument('src/main.styio');
    expect(persisted.text, shell.editorController.document.text);
    expect(
      shell.debugLog.any((entry) => entry.contains('Save requested')),
      isTrue,
    );
  });

  test('shell save command persists through hosted document store', () async {
    final projectGraph = _hostedProjectGraph();
    final hostedClient = _RecordingHostedControlPlaneClient();
    final documentStore = HostedWorkspaceDocumentStore(
      hostedClient: hostedClient,
      workspaceId: 'demo-workspace',
    );
    final initialDocument = await documentStore.loadDocument(
      '/workspace/demo/src/main.styio',
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.ios,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: documentStore,
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.ios,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.ios,
      ),
      editorController: EditorSessionController(
        initialDocument: initialDocument,
        languageService: const _NoopStyioLanguageService(),
      ),
      executionAdapter: const _NoopExecutionAdapter(),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          const _NoopExecutionAdapter(),
      runtimeEventAdapter: const _NoopRuntimeEventAdapter(),
      dependencySourceAdapter: const _NoopDependencySourceAdapter(),
      deploymentAdapter: const _NoopDeploymentAdapter(),
      toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    shell.editorController.insertText('// remote edit\n');
    await shell.executeCommand(AppCommandId.save);

    expect(
      shell.editorFileBindingSnapshot.state,
      DocumentResourceBindingState.boundClean,
    );
    expect(hostedClient.loadedPaths, <String>[
      '/workspace/demo/src/main.styio',
    ]);
    expect(hostedClient.savedDocuments.single['workspaceId'], 'demo-workspace');
    expect(
      hostedClient.savedDocuments.single['path'],
      '/workspace/demo/src/main.styio',
    );
    expect(
      hostedClient.savedDocuments.single['documentText'],
      shell.editorController.document.text,
    );
  });

  test('workspace search opens a matched file and selection range', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['src/main.styio', 'src/worker.styio'],
    );
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'task main {}\n',
      revision: 0,
    );
    const workerDocument = DocumentState(
      documentId: 'src/worker.styio',
      text: 'task worker {\n  emit "needle"\n}\n',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': initialDocument,
        'src/worker.styio': workerDocument,
      },
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: documentStore,
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: initialDocument,
        languageService: const _NoopStyioLanguageService(),
      ),
      executionAdapter: const _NoopExecutionAdapter(),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          const _NoopExecutionAdapter(),
      runtimeEventAdapter: const _NoopRuntimeEventAdapter(),
      dependencySourceAdapter: const _NoopDependencySourceAdapter(),
      deploymentAdapter: const _NoopDeploymentAdapter(),
      toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    final result = await shell.searchWorkspaceText(
      const WorkspaceTextSearchQuery(pattern: 'needle'),
    );

    expect(result.status, WorkspaceTextSearchStatus.completed);
    expect(result.matches.single.filePath, 'src/worker.styio');

    await shell.openWorkspaceSearchMatch(result.matches.single);

    expect(shell.workspaceController.activeFilePath, 'src/worker.styio');
    expect(shell.editorController.document.documentId, 'src/worker.styio');
    expect(
      shell.editorController.selection.start,
      workerDocument.text.indexOf('needle'),
    );
    expect(
      shell.editorController.selection.end,
      workerDocument.text.indexOf('needle') + 'needle'.length,
    );
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Workspace search match opened'),
      ),
      isTrue,
    );
  });

  test('workspace symbol search opens a symbol declaration range', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['src/main.styio', 'src/worker.styio'],
    );
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'task main {}\n',
      revision: 0,
    );
    const workerDocument = DocumentState(
      documentId: 'src/worker.styio',
      text: '#workerJob := () => {\n  <| 42\n}\n',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': initialDocument,
        'src/worker.styio': workerDocument,
      },
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: documentStore,
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: initialDocument,
        languageService: const _NoopStyioLanguageService(),
      ),
      executionAdapter: const _NoopExecutionAdapter(),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          const _NoopExecutionAdapter(),
      runtimeEventAdapter: const _NoopRuntimeEventAdapter(),
      dependencySourceAdapter: const _NoopDependencySourceAdapter(),
      deploymentAdapter: const _NoopDeploymentAdapter(),
      toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    final result = await shell.searchWorkspaceSymbols(
      const WorkspaceSymbolSearchQuery(pattern: 'worker'),
    );

    expect(result.status, WorkspaceSymbolSearchStatus.completed);
    expect(result.items.single.name, 'workerJob');

    await shell.openWorkspaceSymbol(result.items.single);

    expect(shell.workspaceController.activeFilePath, 'src/worker.styio');
    expect(shell.editorController.document.documentId, 'src/worker.styio');
    expect(
      shell.editorController.selection.start,
      workerDocument.text.indexOf('workerJob'),
    );
    expect(
      shell.editorController.selection.end,
      workerDocument.text.indexOf('workerJob') + 'workerJob'.length,
    );
    expect(
      shell.debugLog.any((entry) => entry.contains('Workspace symbol opened')),
      isTrue,
    );
  });

  test('workspace reference search opens a usage range', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['lib/runtime.styio', 'main.styio'],
    );
    const runtimeDocument = DocumentState(
      documentId: 'lib/runtime.styio',
      text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
      revision: 0,
    );
    const mainDocument = DocumentState(
      documentId: 'main.styio',
      text: '''
@import { lib/runtime }
value = blend(1.0, 2.0)
''',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/runtime.styio': runtimeDocument,
        'main.styio': mainDocument,
      },
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: documentStore,
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: runtimeDocument,
        languageService: const _NoopStyioLanguageService(),
      ),
      executionAdapter: const _NoopExecutionAdapter(),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          const _NoopExecutionAdapter(),
      runtimeEventAdapter: const _NoopRuntimeEventAdapter(),
      dependencySourceAdapter: const _NoopDependencySourceAdapter(),
      deploymentAdapter: const _NoopDeploymentAdapter(),
      toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    final result = await shell.findWorkspaceReferences(
      const WorkspaceReferenceSearchQuery(
        pattern: 'blend',
        includeDefinitions: false,
      ),
    );

    expect(result.status, WorkspaceReferenceSearchStatus.completed);
    expect(result.references.single.filePath, 'main.styio');

    await shell.openWorkspaceReference(result.references.single);

    expect(shell.workspaceController.activeFilePath, 'main.styio');
    expect(shell.editorController.document.documentId, 'main.styio');
    expect(
      shell.editorController.selection.start,
      mainDocument.text.indexOf('blend'),
    );
    expect(
      shell.editorController.selection.end,
      mainDocument.text.indexOf('blend') + 'blend'.length,
    );
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Workspace reference opened'),
      ),
      isTrue,
    );
  });

  test('workspace call hierarchy opens a call location', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['lib/runtime.styio', 'main.styio'],
    );
    const runtimeDocument = DocumentState(
      documentId: 'lib/runtime.styio',
      text: '''
fn blend(left: f64, right: f64): f64 {
  emit left + right
}
''',
      revision: 0,
    );
    const mainDocument = DocumentState(
      documentId: 'main.styio',
      text: '''
@import { lib/runtime }
fn run(): f64 {
  emit blend(1.0, 2.0)
}
''',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/runtime.styio': runtimeDocument,
        'main.styio': mainDocument,
      },
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: documentStore,
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: runtimeDocument,
        languageService: const _NoopStyioLanguageService(),
      ),
      executionAdapter: const _NoopExecutionAdapter(),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          const _NoopExecutionAdapter(),
      runtimeEventAdapter: const _NoopRuntimeEventAdapter(),
      dependencySourceAdapter: const _NoopDependencySourceAdapter(),
      deploymentAdapter: const _NoopDeploymentAdapter(),
      toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    final result = await shell.buildWorkspaceCallHierarchy(
      const WorkspaceCallHierarchyQuery(pattern: 'blend'),
    );

    expect(result.status, WorkspaceCallHierarchyStatus.completed);
    expect(result.calls.single.symbol.name, 'run');

    await shell.openWorkspaceCallHierarchyLocation(
      result.calls.single.firstLocation,
    );

    expect(shell.workspaceController.activeFilePath, 'main.styio');
    expect(shell.editorController.document.documentId, 'main.styio');
    expect(
      shell.editorController.selection.start,
      mainDocument.text.indexOf('blend'),
    );
    expect(
      shell.editorController.selection.end,
      mainDocument.text.indexOf('blend') + 'blend'.length,
    );
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Call hierarchy location opened'),
      ),
      isTrue,
    );
  });

  test('workspace problems opens a diagnostic range', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['src/main.styio'],
    );
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: '''
price = 1.0
price -> @prices
''',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': initialDocument,
      },
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: documentStore,
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: initialDocument,
        languageService: const _NoopStyioLanguageService(),
      ),
      executionAdapter: const _NoopExecutionAdapter(),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          const _NoopExecutionAdapter(),
      runtimeEventAdapter: const _NoopRuntimeEventAdapter(),
      dependencySourceAdapter: const _NoopDependencySourceAdapter(),
      deploymentAdapter: const _NoopDeploymentAdapter(),
      toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    final result = await shell.collectWorkspaceProblems(
      const WorkspaceProblemsQuery(pattern: 'prices'),
    );
    final problem = result.problems.singleWhere(
      (problem) => problem.diagnostic.code == 'unresolved-resource',
    );

    await shell.openWorkspaceProblem(problem);

    expect(shell.workspaceController.activeFilePath, 'src/main.styio');
    expect(shell.editorController.document.documentId, 'src/main.styio');
    expect(
      shell.editorController.selection.start,
      initialDocument.text.indexOf('@prices'),
    );
    expect(
      shell.editorController.selection.end,
      initialDocument.text.indexOf('@prices') + '@prices'.length,
    );
    expect(
      shell.debugLog.any((entry) => entry.contains('Workspace problem opened')),
      isTrue,
    );
  });

  test('workspace quick open opens a file and promotes it to recent', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['src/main.styio', 'src/worker.styio'],
    );
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'task main {}\n',
      revision: 0,
    );
    const workerDocument = DocumentState(
      documentId: 'src/worker.styio',
      text: 'task worker {}\n',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': initialDocument,
        'src/worker.styio': workerDocument,
      },
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: documentStore,
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: initialDocument,
        languageService: const _NoopStyioLanguageService(),
      ),
      executionAdapter: const _NoopExecutionAdapter(),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          const _NoopExecutionAdapter(),
      runtimeEventAdapter: const _NoopRuntimeEventAdapter(),
      dependencySourceAdapter: const _NoopDependencySourceAdapter(),
      deploymentAdapter: const _NoopDeploymentAdapter(),
      toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    final result = shell.quickOpenWorkspace(
      const WorkspaceQuickOpenQuery(pattern: 'worker'),
    );

    expect(result.items.single.filePath, 'src/worker.styio');

    await shell.openWorkspaceQuickOpenItem(result.items.single);

    expect(shell.workspaceController.activeFilePath, 'src/worker.styio');
    expect(shell.editorController.document.documentId, 'src/worker.styio');
    expect(shell.editorController.selection.start, 0);
    expect(shell.editorController.selection.end, 0);
    expect(shell.workspaceController.recentFiles.first, 'src/worker.styio');
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Quick Open file opened'),
      ),
      isTrue,
    );

    final recentResult = shell.quickOpenWorkspace(
      const WorkspaceQuickOpenQuery(),
    );
    expect(recentResult.items.first.filePath, 'src/worker.styio');
  });

  test(
    'accepting external editor change reloads revision and invalidates language cache',
    () async {
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: 'src/main.styio',
        title: 'Demo',
        notes: const <String>[],
      );
      const initialDocument = DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 0,
      );
      final externalDocument = initialDocument.replaceRange(
        start: initialDocument.text.indexOf('1'),
        end: initialDocument.text.indexOf('1') + 1,
        replacement: '2',
      );
      final documentStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': initialDocument,
        },
      );
      final cache = StyioServiceResultCache()
        ..store(
          const StyioServiceResponse(
            status: StyioServiceStatus.succeeded,
            documentId: 'src/main.styio',
            revision: 0,
            diagnostics: <StyioServiceDiagnosticDto>[
              StyioServiceDiagnosticDto(
                severity: DiagnosticSeverity.error,
                code: 'styio.old-revision',
                message: 'old cached diagnostic',
                range: SourceRange(start: 0, end: 5),
              ),
            ],
          ),
        );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: WorkspaceController(projectSnapshot: projectGraph),
        workspaceDocumentStore: documentStore,
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: initialDocument,
          languageService: CachedStyioLanguageService(cache: cache),
        ),
        executionAdapter: const _NoopExecutionAdapter(),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            const _NoopExecutionAdapter(),
        runtimeEventAdapter: const _NoopRuntimeEventAdapter(),
        dependencySourceAdapter: const _NoopDependencySourceAdapter(),
        deploymentAdapter: const _NoopDeploymentAdapter(),
        toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      expect(
        shell.editorController.analysis.diagnostics.single.code,
        'styio.old-revision',
      );

      await documentStore.saveDocument(externalDocument);
      final detected = shell.markEditorResourceExternalChanged(
        externalDocument,
      );
      expect(detected.state, DocumentResourceBindingState.externalChanged);

      final accepted = shell.acceptEditorExternalChange();

      expect(accepted.state, DocumentResourceBindingState.boundClean);
      expect(shell.editorController.document.text, externalDocument.text);
      expect(
        shell.editorController.document.revision,
        externalDocument.revision,
      );
      expect(
        shell.editorController.analysis.diagnostics.map(
          (diagnostic) => diagnostic.code,
        ),
        isNot(contains('styio.old-revision')),
      );
    },
  );

  test(
    'resource watch external change reloads clean editor revision',
    () async {
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: 'src/main.styio',
        title: 'Demo',
        notes: const <String>[],
      );
      const initialDocument = DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 0,
      );
      final externalDocument = initialDocument.replaceRange(
        start: initialDocument.text.indexOf('1'),
        end: initialDocument.text.indexOf('1') + 1,
        replacement: '3',
      );
      final documentStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': initialDocument,
        },
      );
      final resourceStore = _WatchingDocumentResourceStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': initialDocument,
        },
      );
      final cache = StyioServiceResultCache()
        ..store(
          const StyioServiceResponse(
            status: StyioServiceStatus.succeeded,
            documentId: 'src/main.styio',
            revision: 0,
            diagnostics: <StyioServiceDiagnosticDto>[
              StyioServiceDiagnosticDto(
                severity: DiagnosticSeverity.error,
                code: 'styio.watch-old-revision',
                message: 'old cached diagnostic',
                range: SourceRange(start: 0, end: 5),
              ),
            ],
          ),
        );
      final binding = EditorDocumentResourceBinding.withResourceStore(
        resourceStore: resourceStore,
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: WorkspaceController(projectSnapshot: projectGraph),
        workspaceDocumentStore: documentStore,
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: initialDocument,
          languageService: CachedStyioLanguageService(cache: cache),
        ),
        executionAdapter: const _NoopExecutionAdapter(),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            const _NoopExecutionAdapter(),
        runtimeEventAdapter: const _NoopRuntimeEventAdapter(),
        dependencySourceAdapter: const _NoopDependencySourceAdapter(),
        deploymentAdapter: const _NoopDeploymentAdapter(),
        toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
        editorFileBinding: binding,
      );
      addTearDown(shell.dispose);

      expect(
        shell.editorController.analysis.diagnostics.single.code,
        'styio.watch-old-revision',
      );

      resourceStore.emit(
        DocumentResourceEvent.externalChanged(externalDocument),
      );

      expect(
        shell.editorFileBindingSnapshot.state,
        DocumentResourceBindingState.boundClean,
      );
      expect(shell.editorController.document.text, externalDocument.text);
      expect(
        shell.editorController.document.revision,
        externalDocument.revision,
      );
      expect(
        shell.editorController.analysis.diagnostics.map(
          (diagnostic) => diagnostic.code,
        ),
        isNot(contains('styio.watch-old-revision')),
      );
    },
  );

  test('resource watch readonly and writable states reach shell', () async {
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/demo',
      activeFilePath: 'src/main.styio',
      title: 'Demo',
      notes: const <String>[],
    );
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'value := 1\n',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': initialDocument,
      },
    );
    final resourceStore = _WatchingDocumentResourceStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': initialDocument,
      },
    );
    final binding = EditorDocumentResourceBinding.withResourceStore(
      resourceStore: resourceStore,
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: documentStore,
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: initialDocument,
        languageService: const _NoopStyioLanguageService(),
      ),
      executionAdapter: const _NoopExecutionAdapter(),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          const _NoopExecutionAdapter(),
      runtimeEventAdapter: const _NoopRuntimeEventAdapter(),
      dependencySourceAdapter: const _NoopDependencySourceAdapter(),
      deploymentAdapter: const _NoopDeploymentAdapter(),
      toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
      editorFileBinding: binding,
    );
    addTearDown(shell.dispose);

    resourceStore.emit(const DocumentResourceEvent.readonly());

    expect(
      shell.editorFileBindingSnapshot.state,
      DocumentResourceBindingState.readonly,
    );
    expect(shell.debugLog.any((entry) => entry.contains('readonly')), isTrue);

    resourceStore.emit(const DocumentResourceEvent.writable());

    expect(
      shell.editorFileBindingSnapshot.state,
      DocumentResourceBindingState.boundClean,
    );
  });
}

class _WatchingDocumentResourceStore implements DocumentResourceStore {
  _WatchingDocumentResourceStore({Map<String, DocumentState>? seededDocuments})
    : _documents = Map<String, DocumentState>.from(
        seededDocuments ?? const <String, DocumentState>{},
      );

  final Map<String, DocumentState> _documents;
  final StreamController<DocumentResourceEvent> _events =
      StreamController<DocumentResourceEvent>.broadcast(sync: true);

  void emit(DocumentResourceEvent event) {
    _events.add(event);
  }

  @override
  Future<DocumentState> loadDocument(String resourceId) async {
    return _documents[resourceId] ??
        DocumentState(documentId: resourceId, text: '', revision: 0);
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    _documents[document.documentId] = document;
  }

  @override
  Stream<DocumentResourceEvent> watchResource(String resourceId) {
    return _events.stream;
  }
}

const _capabilitySnapshot = AdapterCapabilitySnapshot(
  adapterKind: AdapterKind.cli,
  languageService: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'not needed for shell file binding test',
  ),
  projectGraph: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.available,
    detail: 'static project graph',
  ),
  execution: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'not needed for shell file binding test',
  ),
  runtimeEvents: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'not needed for shell file binding test',
  ),
);

class _StaticProjectGraphAdapter implements ProjectGraphAdapter {
  const _StaticProjectGraphAdapter(this._projectGraph);

  final ProjectGraphSnapshot _projectGraph;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => _capabilitySnapshot;

  @override
  Future<ProjectGraphSnapshot> loadProjectGraph() async => _projectGraph;
}

class _NoopExecutionAdapter implements ExecutionAdapter {
  const _NoopExecutionAdapter();

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => _capabilitySnapshot;

  @override
  Future<ExecutionSession> runActiveDocument({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
  }) async {
    return const ExecutionSession(
      sessionId: 'noop',
      kind: 'noop',
      status: ExecutionSessionStatus.blocked,
      statusMessage: 'not needed for shell file binding test',
      diagnostics: <Diagnostic>[],
      stdoutEvents: <ExecutionLogEvent>[],
      stderrEvents: <ExecutionLogEvent>[],
    );
  }
}

class _NoopRuntimeEventAdapter implements RuntimeEventAdapter {
  const _NoopRuntimeEventAdapter();

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => _capabilitySnapshot;

  @override
  Stream<RuntimeEventEnvelope> sessionEvents(String sessionId) {
    return const Stream<RuntimeEventEnvelope>.empty();
  }
}

class _NoopDependencySourceAdapter implements DependencySourceAdapter {
  const _NoopDependencySourceAdapter();

  @override
  Future<DependencySourceCommandResult> fetchDependencies({
    required ProjectGraphSnapshot projectGraph,
    bool locked = false,
    bool offline = false,
  }) async {
    return const DependencySourceCommandResult(
      command: 'fetch',
      status: DependencySourceCommandStatus.blocked,
      statusMessage: 'not needed for shell file binding test',
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
      statusMessage: 'not needed for shell file binding test',
      stdout: '',
      stderr: '',
    );
  }
}

class _NoopDeploymentAdapter implements DeploymentAdapter {
  const _NoopDeploymentAdapter();

  @override
  Future<DeploymentCommandResult> packProject({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) async {
    return const DeploymentCommandResult(
      command: 'pack',
      status: DeploymentCommandStatus.blocked,
      statusMessage: 'not needed for shell file binding test',
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
      statusMessage: 'not needed for shell file binding test',
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
      command: 'publish-registry',
      status: DeploymentCommandStatus.blocked,
      statusMessage: 'not needed for shell file binding test',
      stdout: '',
      stderr: '',
    );
  }
}

class _NoopToolchainManagementAdapter implements ToolchainManagementAdapter {
  const _NoopToolchainManagementAdapter();

  @override
  Future<ToolchainCommandResult> installManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String styioBinaryPath,
  }) async {
    return _blocked('tool install');
  }

  @override
  Future<ToolchainCommandResult> useManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async {
    return _blocked('tool use');
  }

  @override
  Future<ToolchainCommandResult> pinManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async {
    return _blocked('tool pin');
  }

  @override
  Future<ToolchainCommandResult> clearPinnedCompiler({
    required ProjectGraphSnapshot projectGraph,
  }) async {
    return _blocked('tool pin clear');
  }

  ToolchainCommandResult _blocked(String command) {
    return ToolchainCommandResult(
      command: command,
      status: ToolchainCommandStatus.blocked,
      statusMessage: 'not needed for shell file binding test',
      stdout: '',
      stderr: '',
    );
  }
}

class _NoopStyioLanguageService implements StyioLanguageService {
  const _NoopStyioLanguageService();

  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    return const StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: <Diagnostic>[],
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: <SemanticBlockRange>[],
      inlayHints: <InlayHint>[],
      documentSymbols: <DocumentSymbol>[],
      referenceSpans: <ReferenceSpan>[],
    );
  }

  @override
  ChangeSignaturePlan? changeSignatureAt(
    DocumentState document,
    int offset, {
    required String newName,
    required List<ChangeSignatureParameterUpdate> parameters,
  }) => null;

  @override
  List<CompletionItem> completeAt(DocumentState document, int offset) =>
      const <CompletionItem>[];

  @override
  DefinitionTarget? definitionAt(DocumentState document, int offset) => null;

  @override
  ExtractFunctionPlan? extractFunction(
    DocumentState document,
    SourceRange range,
    String name,
  ) => null;

  @override
  List<FormattingEdit> formatDocument(DocumentState document) =>
      const <FormattingEdit>[];

  @override
  HoverPayload? hoverAt(DocumentState document, int offset) => null;

  @override
  List<InlayHint> inlayHints(DocumentState document) => const <InlayHint>[];

  @override
  InlineVariablePlan? inlineVariableAt(DocumentState document, int offset) =>
      null;

  @override
  List<DiagnosticQuickFix> intentionsAt(DocumentState document, int offset) =>
      const <DiagnosticQuickFix>[];

  @override
  IntroduceVariablePlan? introduceVariable(
    DocumentState document,
    SourceRange range,
    String name,
  ) => null;

  @override
  ParameterInfoPayload? parameterInfoAt(DocumentState document, int offset) =>
      null;

  @override
  List<DiagnosticQuickFix> quickFixesForDiagnostic(
    DocumentState document,
    Diagnostic diagnostic,
  ) => const <DiagnosticQuickFix>[];

  @override
  List<ReferenceSpan> referencesAt(DocumentState document, int offset) =>
      const <ReferenceSpan>[];

  @override
  RenamePlan? renameAt(DocumentState document, int offset, String newName) =>
      null;

  @override
  SafeDeletePlan? safeDeleteAt(DocumentState document, int offset) => null;

  @override
  List<SurroundTemplate> surroundTemplatesAt(
    DocumentState document,
    SourceRange range,
  ) => const <SurroundTemplate>[];
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

ProjectGraphSnapshot _projectGraphWithFiles(List<String> editorFiles) {
  return ProjectGraphSnapshot(
    id: '/workspace/demo',
    title: 'Demo',
    kind: ProjectKind.scratch,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: const <String>[],
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: editorFiles,
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.unavailable,
      detail: 'No project toolchain pin is active in scratch mode.',
    ),
    lockState: ProjectLockState.missing,
    vendorState: ProjectVendorState.missing,
    notes: const <String>[],
  );
}

ProjectGraphSnapshot _hostedProjectGraph() {
  return ProjectGraphSnapshot(
    id: '/workspace/demo/spio.toml',
    title: 'demo/app',
    kind: ProjectKind.hosted,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/demo/spio.toml',
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
