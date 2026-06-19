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
import 'package:vityo_app/src/view_ide/language/service/project_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/module_host/module_registry.dart';
import 'package:vityo_app/src/view_ide/platform/native_module_loader.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/shell_runtime_model.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_controller.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_breadcrumbs.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_call_hierarchy.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_code_actions.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_code_lens.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_declaration.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_definition.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_highlights.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_links.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_store.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_navigation_history.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_outline.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_problems.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_quick_open.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_reference_search.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_rename.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_search.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_symbol_search.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_implementation.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_type_definition.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_type_hierarchy.dart';

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

  test('workspace replace applies edits and refreshes active document', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['src/main.styio', 'src/worker.styio'],
    );
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'task main {\n  emit "needle"\n}\n',
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

    final preview = await shell.previewWorkspaceReplace(
      const WorkspaceTextReplaceQuery(
        pattern: 'needle',
        replacement: 'thread',
      ),
    );

    expect(preview.status, WorkspaceTextSearchStatus.completed);
    expect(preview.replacementCount, 2);
    expect(shell.lastWorkspaceReplace, preview);

    final result = await shell.applyWorkspaceReplace(
      const WorkspaceTextReplaceQuery(
        pattern: 'needle',
        replacement: 'thread',
      ),
    );

    expect(result.applied, isTrue);
    expect(result.replacementsApplied, 2);
    expect(shell.editorController.document.text, contains('"thread"'));
    expect(
      shell.editorController.selection.start,
      initialDocument.text.indexOf('needle'),
    );
    expect(
      shell.editorController.selection.end,
      initialDocument.text.indexOf('needle') + 'thread'.length,
    );
    final workerAfter = await documentStore.loadDocument('src/worker.styio');
    expect(workerAfter.text, contains('"thread"'));
    expect(
      shell.editorFileBindingSnapshot.state,
      DocumentResourceBindingState.boundClean,
    );
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Workspace replace applied'),
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

  test('workspace document link opens a resolved import target', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['main.styio', 'lib/runtime.styio'],
    );
    const runtimeDocument = DocumentState(
      documentId: 'lib/runtime.styio',
      text: '#blend := () => {}\n',
      revision: 0,
    );
    const mainDocument = DocumentState(
      documentId: 'main.styio',
      text: '''
@import { lib/runtime }
value = blend()
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
        initialDocument: mainDocument,
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

    expect(shell.workspaceDocumentLinksTargetFilePath, 'main.styio');

    final result = await shell.collectWorkspaceDocumentLinks(
      const WorkspaceDocumentLinksQuery(targetFilePath: 'main.styio'),
    );

    expect(result.status, WorkspaceDocumentLinksStatus.completed);
    expect(result.links.single.resolvedFilePath, 'lib/runtime.styio');

    await shell.openWorkspaceDocumentLink(result.links.single);

    expect(shell.workspaceController.activeFilePath, 'lib/runtime.styio');
    expect(shell.editorController.document.documentId, 'lib/runtime.styio');
    expect(shell.editorController.selection.start, 0);
    expect(shell.editorController.selection.end, 0);
    expect(
      shell.debugLog.any((entry) => entry.contains('Document link opened')),
      isTrue,
    );
  });

  test('workspace document highlight opens an occurrence range', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['resources.styio'],
    );
    const resourceDocument = DocumentState(
      documentId: 'resources.styio',
      text: '''
@prices: f64 := {}
latest = @prices
next -> @prices
''',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'resources.styio': resourceDocument,
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
        initialDocument: resourceDocument,
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

    shell.editorController.selectCollapsed(
      resourceDocument.text.indexOf(
            '@prices',
            resourceDocument.text.indexOf('latest'),
          ) +
          1,
    );

    final result = await shell.collectWorkspaceDocumentHighlights(
      WorkspaceDocumentHighlightsQuery(
        targetFilePath: shell.workspaceDocumentHighlightsTargetFilePath,
        offset: shell.workspaceDocumentHighlightsOffset,
      ),
    );

    expect(result.status, WorkspaceDocumentHighlightsStatus.completed);
    expect(result.writeCount, 1);

    final write = result.highlights.singleWhere(
      (item) => item.kind == WorkspaceDocumentHighlightKind.write,
    );
    await shell.openWorkspaceDocumentHighlight(write);

    expect(shell.workspaceController.activeFilePath, 'resources.styio');
    expect(shell.editorController.selection.start, write.range.start);
    expect(shell.editorController.selection.end, write.range.end);
    expect(
      shell.debugLog.any((entry) => entry.contains('Document highlight opened')),
      isTrue,
    );
  });

  test('workspace code lens opens a symbol range', () async {
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

    final result = await shell.collectWorkspaceCodeLenses(
      WorkspaceCodeLensQuery(
        targetFilePath: shell.workspaceCodeLensTargetFilePath,
      ),
    );

    expect(result.status, WorkspaceCodeLensStatus.completed);
    expect(result.lensCount, 1);
    expect(result.lenses.single.usageCount, 1);

    final lens = result.lenses.single;
    await shell.openWorkspaceCodeLens(lens);

    expect(shell.workspaceController.activeFilePath, 'lib/runtime.styio');
    expect(shell.editorController.selection.start, lens.range.start);
    expect(shell.editorController.selection.end, lens.range.end);
    expect(
      shell.debugLog.any((entry) => entry.contains('Code lens opened')),
      isTrue,
    );
  });

  test('workspace declaration opens a declaration range', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['main.styio', 'lib/types.styio'],
    );
    const typeDocument = DocumentState(
      documentId: 'lib/types.styio',
      text: '''
schema OrderBook {
  bids: f64
  asks: f64
}
''',
      revision: 0,
    );
    const mainDocument = DocumentState(
      documentId: 'main.styio',
      text: '''
@import { lib/types }
book: OrderBook
''',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/types.styio': typeDocument,
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
        initialDocument: mainDocument,
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

    final orderBookUsageOffset = mainDocument.text.indexOf('OrderBook');
    shell.editorController.selectRange(
      baseOffset: orderBookUsageOffset,
      extentOffset: orderBookUsageOffset + 'OrderBook'.length,
    );
    expect(shell.workspaceDeclarationQuerySeed, 'OrderBook');

    final result = await shell.findWorkspaceDeclarations(
      const WorkspaceDeclarationQuery(pattern: 'OrderBook'),
    );

    expect(result.status, WorkspaceDeclarationStatus.completed);
    expect(result.declarations.first.filePath, 'lib/types.styio');
    expect(result.declarations.first.kind, WorkspaceDeclarationKind.schema);

    await shell.openWorkspaceDeclaration(result.declarations.first);

    expect(shell.workspaceController.activeFilePath, 'lib/types.styio');
    expect(shell.editorController.document.documentId, 'lib/types.styio');
    final orderBookDeclarationOffset = typeDocument.text.indexOf('OrderBook');
    expect(shell.editorController.selection.start, orderBookDeclarationOffset);
    expect(
      shell.editorController.selection.end,
      orderBookDeclarationOffset + 'OrderBook'.length,
    );
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Workspace declaration opened'),
      ),
      isTrue,
    );
  });

  test('workspace definition opens a definition range', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['main.styio', 'lib/runtime.styio'],
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
        initialDocument: mainDocument,
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

    shell.editorController.selectRange(
      baseOffset: mainDocument.text.indexOf('blend'),
      extentOffset: mainDocument.text.indexOf('blend') + 'blend'.length,
    );
    expect(shell.workspaceDefinitionQuerySeed, 'blend');

    final result = await shell.findWorkspaceDefinitions(
      const WorkspaceDefinitionQuery(pattern: 'blend'),
    );

    expect(result.status, WorkspaceDefinitionStatus.completed);
    expect(result.definitions.first.filePath, 'lib/runtime.styio');

    await shell.openWorkspaceDefinition(result.definitions.first);

    expect(shell.workspaceController.activeFilePath, 'lib/runtime.styio');
    expect(shell.editorController.document.documentId, 'lib/runtime.styio');
    expect(
      shell.editorController.selection.start,
      runtimeDocument.text.indexOf('blend'),
    );
    expect(
      shell.editorController.selection.end,
      runtimeDocument.text.indexOf('blend') + 'blend'.length,
    );
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Workspace definition opened'),
      ),
      isTrue,
    );
  });

  test('workspace type definition opens a schema range', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['main.styio', 'lib/types.styio'],
    );
    const typeDocument = DocumentState(
      documentId: 'lib/types.styio',
      text: '''
schema OrderBook {
  bids: f64
  asks: f64
}
''',
      revision: 0,
    );
    const mainDocument = DocumentState(
      documentId: 'main.styio',
      text: '''
@import { lib/types }
book: OrderBook
''',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/types.styio': typeDocument,
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
        initialDocument: mainDocument,
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

    final orderBookUsageOffset = mainDocument.text.indexOf('OrderBook');
    shell.editorController.selectRange(
      baseOffset: orderBookUsageOffset,
      extentOffset: orderBookUsageOffset + 'OrderBook'.length,
    );
    expect(shell.workspaceTypeDefinitionQuerySeed, 'OrderBook');

    final result = await shell.findWorkspaceTypeDefinitions(
      const WorkspaceTypeDefinitionQuery(pattern: 'OrderBook'),
    );

    expect(result.status, WorkspaceTypeDefinitionStatus.completed);
    expect(result.types.first.filePath, 'lib/types.styio');
    expect(result.types.first.kind, WorkspaceTypeDefinitionKind.schema);

    await shell.openWorkspaceTypeDefinition(result.types.first);

    expect(shell.workspaceController.activeFilePath, 'lib/types.styio');
    expect(shell.editorController.document.documentId, 'lib/types.styio');
    final orderBookDefinitionOffset = typeDocument.text.indexOf('OrderBook');
    expect(
      shell.editorController.selection.start,
      orderBookDefinitionOffset,
    );
    expect(
      shell.editorController.selection.end,
      orderBookDefinitionOffset + 'OrderBook'.length,
    );
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Workspace type definition opened'),
      ),
      isTrue,
    );
  });

  test('workspace implementation opens a related implementor', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['main.styio', 'lib/types.styio'],
    );
    const typeDocument = DocumentState(
      documentId: 'lib/types.styio',
      text: '''
schema Price {
}

schema OrderBook {
  price: Price
}
''',
      revision: 0,
    );
    const mainDocument = DocumentState(
      documentId: 'main.styio',
      text: '''
@import { lib/types }
target: Price
''',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/types.styio': typeDocument,
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
        initialDocument: mainDocument,
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

    final priceUsageOffset = mainDocument.text.indexOf('Price');
    shell.editorController.selectRange(
      baseOffset: priceUsageOffset,
      extentOffset: priceUsageOffset + 'Price'.length,
    );
    expect(shell.workspaceImplementationQuerySeed, 'Price');

    final result = await shell.findWorkspaceImplementations(
      const WorkspaceImplementationQuery(pattern: 'Price'),
    );

    expect(result.status, WorkspaceImplementationStatus.completed);
    expect(result.implementations.single.name, 'OrderBook');

    await shell.openWorkspaceImplementation(result.implementations.single);

    expect(shell.workspaceController.activeFilePath, 'lib/types.styio');
    expect(shell.editorController.document.documentId, 'lib/types.styio');
    final orderBookDefinitionOffset = typeDocument.text.indexOf('OrderBook');
    expect(shell.editorController.selection.start, orderBookDefinitionOffset);
    expect(
      shell.editorController.selection.end,
      orderBookDefinitionOffset + 'OrderBook'.length,
    );
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Workspace implementation opened'),
      ),
      isTrue,
    );
  });

  test('workspace type hierarchy opens a related type declaration', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['main.styio', 'lib/types.styio'],
    );
    const typeDocument = DocumentState(
      documentId: 'lib/types.styio',
      text: '''
schema Price {
}

schema OrderBook {
  price: Price
}
''',
      revision: 0,
    );
    const mainDocument = DocumentState(
      documentId: 'main.styio',
      text: '''
@import { lib/types }
book: OrderBook
''',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'lib/types.styio': typeDocument,
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
        initialDocument: mainDocument,
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

    final orderBookUsageOffset = mainDocument.text.indexOf('OrderBook');
    shell.editorController.selectRange(
      baseOffset: orderBookUsageOffset,
      extentOffset: orderBookUsageOffset + 'OrderBook'.length,
    );
    expect(shell.workspaceTypeHierarchyQuerySeed, 'OrderBook');

    final result = await shell.buildWorkspaceTypeHierarchy(
      const WorkspaceTypeHierarchyQuery(pattern: 'OrderBook'),
    );

    expect(result.status, WorkspaceTypeHierarchyStatus.completed);
    expect(result.relations.single.symbol.name, 'Price');

    await shell.openWorkspaceTypeHierarchySymbol(
      result.relations.single.symbol,
    );

    expect(shell.workspaceController.activeFilePath, 'lib/types.styio');
    expect(shell.editorController.document.documentId, 'lib/types.styio');
    final priceDefinitionOffset = typeDocument.text.indexOf('Price');
    expect(shell.editorController.selection.start, priceDefinitionOffset);
    expect(
      shell.editorController.selection.end,
      priceDefinitionOffset + 'Price'.length,
    );
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Type hierarchy symbol opened'),
      ),
      isTrue,
    );
  });

  test('workspace rename applies edits across project files', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['main.styio', 'lib/runtime.styio'],
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
        initialDocument: mainDocument,
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

    final targetOffset = mainDocument.text.indexOf('blend');
    shell.editorController.selectRange(
      baseOffset: targetOffset,
      extentOffset: targetOffset + 'blend'.length,
    );
    expect(shell.workspaceRenameQuerySeed, 'blend');

    final preview = await shell.previewWorkspaceRename(
      WorkspaceRenameQuery(
        targetFilePath: 'main.styio',
        targetOffset: targetOffset,
        newName: 'mix',
      ),
    );

    expect(preview.status, WorkspaceRenameStatus.ready);
    expect(preview.editCount, 2);

    final apply = await shell.applyWorkspaceRename(preview.query);

    expect(apply.applied, isTrue);
    expect(apply.documentsChanged, 2);
    expect(
      (await documentStore.loadDocument('main.styio')).text,
      contains('mix('),
    );
    expect(
      (await documentStore.loadDocument('lib/runtime.styio')).text,
      contains('fn mix'),
    );
    expect(shell.editorController.document.text, contains('mix(1.0'));
    expect(shell.editorController.selection.start, targetOffset);
    expect(shell.editorController.selection.end, targetOffset + 'mix'.length);
    expect(
      shell.debugLog.any((entry) => entry.contains('Rename Symbol applied')),
      isTrue,
    );
  });

  test('workspace outline opens an active file symbol range', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['src/main.styio'],
    );
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: '''
entry = 1
#calculate := (input) => {
  <| input
}
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

    final result = await shell.collectWorkspaceOutline(
      const WorkspaceOutlineQuery(targetFilePath: 'src/main.styio'),
    );
    final item = result.items.firstWhere(
      (item) => item.name == 'calculate' && item.kind == SymbolKind.function,
    );

    await shell.openWorkspaceOutlineItem(item);

    expect(shell.workspaceController.activeFilePath, 'src/main.styio');
    expect(
      shell.editorController.selection.start,
      initialDocument.text.indexOf('calculate'),
    );
    expect(
      shell.editorController.selection.end,
      initialDocument.text.indexOf('calculate') + 'calculate'.length,
    );
    expect(
      shell.debugLog.any((entry) => entry.contains('Outline symbol opened')),
      isTrue,
    );
  });

  test('workspace breadcrumbs open active editor symbol context', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['src/main.styio'],
    );
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: '''
entry = 1
#calculate := (input) => {
  <| input
}
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

    shell.editorController.selectCollapsed(
      initialDocument.text.indexOf('<| input'),
    );

    final breadcrumbs = shell.currentWorkspaceBreadcrumbs;
    final symbol = breadcrumbs.activeSymbol;

    expect(breadcrumbs.status, WorkspaceBreadcrumbsStatus.ready);
    expect(breadcrumbs.items.map((item) => item.label), <String>[
      'src',
      'main.styio',
      'calculate',
    ]);
    expect(symbol, isNotNull);

    await shell.openWorkspaceBreadcrumbItem(symbol!);

    expect(
      shell.editorController.selection.start,
      initialDocument.text.indexOf('calculate'),
    );
    expect(
      shell.editorController.selection.end,
      initialDocument.text.indexOf('calculate') + 'calculate'.length,
    );
    expect(
      shell.debugLog.any((entry) => entry.contains('Breadcrumb opened')),
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
      initialDocument.text.indexOf('prices', initialDocument.text.indexOf('@')),
    );
    expect(
      shell.editorController.selection.end,
      initialDocument.text.indexOf('prices', initialDocument.text.indexOf('@')) +
          'prices'.length,
    );
    expect(
      shell.debugLog.any((entry) => entry.contains('Workspace problem opened')),
      isTrue,
    );
  });

  test('workspace code action applies a project fix to the editor file', () async {
    final projectGraph = _projectGraphWithFiles(
      const <String>['src/main.styio'],
    );
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: '''
@import { lib/missing }
value = 1
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

    final preview = await shell.collectWorkspaceCodeActions(
      const WorkspaceCodeActionsQuery(),
    );
    final action = preview.actions.singleWhere(
      (action) => action.id == 'clean-up-project-imports',
    );
    final apply = await shell.applyWorkspaceCodeAction(
      query: preview.query,
      actionId: action.id,
    );

    expect(apply.applied, isTrue);
    expect(apply.documentsChanged, 1);
    expect(shell.editorController.document.text, 'value = 1\n');
    expect(
      (await documentStore.loadDocument('src/main.styio')).text,
      'value = 1\n',
    );
    expect(shell.editorController.selection.start, 0);
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Workspace Code Action applied'),
      ),
      isTrue,
    );
  });

  test(
    'workspace quick open records navigation history and recent locations',
    () async {
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

    final history = shell.workspaceNavigationHistory;
    expect(history.canGoBack, isTrue);
    expect(history.canGoForward, isFalse);
    expect(history.recentLocations.first.filePath, 'src/worker.styio');
    expect(
      history.recentLocations.first.kind,
      WorkspaceNavigationLocationKind.file,
    );

    await shell.navigateWorkspaceHistory(forward: false);

    expect(shell.workspaceController.activeFilePath, 'src/main.styio');
    expect(shell.editorController.document.documentId, 'src/main.styio');
    expect(shell.workspaceNavigationHistory.canGoForward, isTrue);
    expect(
      shell.debugLog.any((entry) => entry.contains('Go Back opened')),
      isTrue,
    );

    await shell.navigateWorkspaceHistory(forward: true);

    expect(shell.workspaceController.activeFilePath, 'src/worker.styio');
    expect(shell.editorController.selection.start, 0);
    expect(
      shell.debugLog.any((entry) => entry.contains('Go Forward opened')),
      isTrue,
    );

    final mainLocation = shell.workspaceNavigationHistory.recentLocations
        .singleWhere((location) => location.filePath == 'src/main.styio');

    await shell.openWorkspaceNavigationLocation(mainLocation);

    expect(shell.workspaceController.activeFilePath, 'src/main.styio');
    expect(shell.editorController.document.documentId, 'src/main.styio');
    expect(
      shell.debugLog.any((entry) => entry.contains('Recent location opened')),
      isTrue,
    );
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

  test('shell runtime logs unavailable workspace open targets', () async {
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'value = 1\n',
      revision: 0,
    );
    final shell = _createNoopShellRuntime(
      projectGraph: _projectGraphWithFiles(const <String>['src/main.styio']),
      documentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': initialDocument,
        },
      ),
      initialDocument: initialDocument,
    );
    addTearDown(shell.dispose);

    await shell.navigateWorkspaceHistory(forward: false);
    await shell.navigateWorkspaceHistory(forward: true);
    await shell.openWorkspaceNavigationLocation(
      const WorkspaceNavigationLocation(
        filePath: 'missing.styio',
        range: SourceRange(start: 0, end: 0),
        line: 0,
        column: 0,
        previewText: '',
        label: 'Missing',
      ),
    );
    await shell.openWorkspaceQuickOpenItem(
      const WorkspaceQuickOpenItem(
        filePath: 'missing.styio',
        fileName: 'missing.styio',
        parentPath: '',
        score: 1,
        matches: <WorkspaceQuickOpenMatch>[],
      ),
    );
    await shell.openWorkspaceSearchMatch(
      const WorkspaceTextSearchMatch(
        filePath: 'missing.styio',
        range: WorkspaceTextRange(start: 0, end: 5),
        line: 0,
        column: 0,
        previewText: 'missing',
      ),
    );
    await shell.openWorkspaceSymbol(
      const WorkspaceSymbolSearchItem(
        filePath: 'missing.styio',
        name: 'missingSymbol',
        kind: SymbolKind.function,
        detail: 'missing',
        nameRange: SourceRange(start: 0, end: 7),
        declarationRange: SourceRange(start: 0, end: 7),
        line: 0,
        column: 0,
        previewText: 'missingSymbol',
        score: 1,
        matches: <WorkspaceSymbolSearchMatch>[],
      ),
    );
    await shell.openWorkspaceOutlineItem(
      const WorkspaceOutlineItem(
        filePath: 'missing.styio',
        name: 'missingOutline',
        kind: SymbolKind.function,
        detail: 'missing',
        nameRange: SourceRange(start: 0, end: 7),
        declarationRange: SourceRange(start: 0, end: 7),
        line: 0,
        column: 0,
        previewText: 'missingOutline',
      ),
    );
    await shell.openWorkspaceBreadcrumbItem(
      const WorkspaceBreadcrumbItem(
        label: 'src',
        kind: WorkspaceBreadcrumbItemKind.folder,
        filePath: 'src',
      ),
    );
    await shell.openWorkspaceBreadcrumbItem(
      const WorkspaceBreadcrumbItem(
        label: 'missing.styio',
        kind: WorkspaceBreadcrumbItemKind.file,
        filePath: 'missing.styio',
      ),
    );
    await shell.openWorkspaceDefinition(
      const WorkspaceDefinitionItem(
        filePath: 'missing.styio',
        name: 'missingDefinition',
        kind: StyioProjectSymbolKind.function,
        range: SourceRange(start: 0, end: 7),
        line: 0,
        column: 0,
        previewText: 'missingDefinition',
      ),
    );
    await shell.openWorkspaceDocumentLink(
      const WorkspaceDocumentLinkItem(
        sourceFilePath: 'src/main.styio',
        target: 'pkg/external',
        kind: WorkspaceDocumentLinkKind.externalImport,
        range: SourceRange(start: 0, end: 12),
        line: 0,
        column: 0,
        previewText: '@import { pkg/external }',
      ),
    );
    await shell.openWorkspaceDocumentLink(
      const WorkspaceDocumentLinkItem(
        sourceFilePath: 'src/main.styio',
        target: 'missing',
        kind: WorkspaceDocumentLinkKind.workspaceImport,
        range: SourceRange(start: 0, end: 7),
        line: 0,
        column: 0,
        previewText: '@import { missing }',
        resolvedFilePath: 'missing.styio',
      ),
    );
    await shell.openWorkspaceDocumentHighlight(
      const WorkspaceDocumentHighlightItem(
        filePath: 'missing.styio',
        name: 'value',
        kind: WorkspaceDocumentHighlightKind.text,
        range: SourceRange(start: 0, end: 5),
        line: 0,
        column: 0,
        previewText: 'value',
        isActive: false,
      ),
    );
    await shell.openWorkspaceCodeLens(
      const WorkspaceCodeLensItem(
        filePath: 'missing.styio',
        symbolName: 'value',
        symbolKind: StyioProjectSymbolKind.function,
        kind: WorkspaceCodeLensKind.references,
        commandTitle: '1 reference',
        range: SourceRange(start: 0, end: 5),
        line: 0,
        column: 0,
        previewText: 'value',
        referenceCount: 1,
        usageCount: 1,
      ),
    );
    await shell.openWorkspaceDeclaration(
      const WorkspaceDeclarationItem(
        filePath: 'missing.styio',
        name: 'missingDeclaration',
        kind: WorkspaceDeclarationKind.function,
        range: SourceRange(start: 0, end: 7),
        line: 0,
        column: 0,
        previewText: 'missingDeclaration',
      ),
    );
    await shell.openWorkspaceTypeDefinition(
      const WorkspaceTypeDefinitionItem(
        filePath: 'missing.styio',
        name: 'MissingType',
        kind: WorkspaceTypeDefinitionKind.schema,
        range: SourceRange(start: 0, end: 11),
        line: 0,
        column: 0,
        previewText: 'schema MissingType {}',
      ),
    );
    await shell.openWorkspaceTypeHierarchySymbol(
      const WorkspaceTypeHierarchySymbol(
        filePath: 'missing.styio',
        name: 'MissingType',
        kind: WorkspaceTypeDefinitionKind.schema,
        range: SourceRange(start: 0, end: 11),
        line: 0,
        column: 0,
        previewText: 'schema MissingType {}',
      ),
    );
    await shell.openWorkspaceImplementation(
      const WorkspaceImplementationItem(
        filePath: 'missing.styio',
        name: 'MissingType',
        kind: WorkspaceTypeDefinitionKind.schema,
        range: SourceRange(start: 0, end: 11),
        line: 0,
        column: 0,
        previewText: 'schema MissingType {}',
        references: <WorkspaceTypeHierarchyLocation>[],
      ),
    );
    await shell.openWorkspaceReference(
      const WorkspaceReferenceSearchItem(
        filePath: 'missing.styio',
        name: 'value',
        kind: StyioProjectSymbolKind.function,
        range: SourceRange(start: 0, end: 5),
        line: 0,
        column: 0,
        previewText: 'value',
        isDefinition: false,
        access: ReferenceAccess.read,
        definition: WorkspaceReferenceDefinition(
          filePath: 'src/main.styio',
          name: 'value',
          kind: StyioProjectSymbolKind.function,
          range: SourceRange(start: 0, end: 5),
          line: 0,
          column: 0,
          referenceCount: 1,
        ),
      ),
    );
    await shell.openWorkspaceCallHierarchyLocation(
      const WorkspaceCallHierarchyLocation(
        filePath: 'missing.styio',
        range: SourceRange(start: 0, end: 5),
        line: 0,
        column: 0,
        previewText: 'value',
      ),
    );
    await shell.openWorkspaceProblem(
      const WorkspaceProblemItem(
        filePath: 'missing.styio',
        diagnostic: Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'missing-file',
          message: 'missing',
          range: SourceRange(start: 0, end: 5),
        ),
        line: 0,
        column: 0,
        previewText: 'missing',
      ),
    );

    for (final fragment in const <String>[
      'Go Back unavailable',
      'Go Forward unavailable',
      'Recent location unavailable',
      'Quick Open file unavailable',
      'Workspace search match unavailable',
      'Workspace symbol unavailable',
      'Outline symbol unavailable',
      'Breadcrumb segment is not openable',
      'Breadcrumb target unavailable',
      'Workspace definition unavailable',
      'Document link unavailable: pkg/external',
      'Document link unavailable: missing.styio',
      'Document highlight unavailable',
      'Code lens unavailable',
      'Workspace declaration unavailable',
      'Workspace type definition unavailable',
      'Type hierarchy symbol unavailable',
      'Workspace implementation unavailable',
      'Workspace usage unavailable',
      'Call hierarchy location unavailable',
      'Workspace problem unavailable',
    ]) {
      expect(shell.debugLog.any((entry) => entry.contains(fragment)), isTrue);
    }
  });

  test('shell runtime logs command routes and non-applied workspace edits', () async {
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'value = 1\n',
      revision: 0,
    );
    final shell = _createNoopShellRuntime(
      projectGraph: _projectGraphWithFiles(const <String>['src/main.styio']),
      documentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': initialDocument,
        },
      ),
      initialDocument: initialDocument,
    );
    addTearDown(shell.dispose);

    await shell.executeCommand(AppCommandId.fetchDependencies);
    await shell.executeCommand(AppCommandId.refreshModules);
    await shell.executeCommand(AppCommandId.openSettings);

    final hierarchy = await shell.buildWorkspaceTypeHierarchy(
      const WorkspaceTypeHierarchyQuery(pattern: 'MissingType'),
    );
    final implementations = await shell.findWorkspaceImplementations(
      const WorkspaceImplementationQuery(pattern: 'MissingType'),
    );
    final calls = await shell.buildWorkspaceCallHierarchy(
      const WorkspaceCallHierarchyQuery(pattern: 'missingCall'),
    );
    final replace = await shell.applyWorkspaceReplace(
      const WorkspaceTextReplaceQuery(pattern: 'absent', replacement: 'next'),
    );
    final rename = await shell.applyWorkspaceRename(
      const WorkspaceRenameQuery(
        targetFilePath: 'src/main.styio',
        targetOffset: 0,
        newName: 'renamed',
      ),
    );
    final action = await shell.applyWorkspaceCodeAction(
      query: const WorkspaceCodeActionsQuery(pattern: 'none'),
      actionId: 'missing-action',
    );

    expect(hierarchy.target, isNull);
    expect(implementations.target, isNull);
    expect(calls.target, isNull);
    expect(replace.applied, isFalse);
    expect(rename.applied, isFalse);
    expect(action.applied, isFalse);
    expect(
      shell.blockedReasonForCommand(AppCommandId.fetchDependencies),
      'fetch requires a resolved spio manifest path.',
    );
    for (final fragment in const <String>[
      'Fetch blocked: fetch requires a resolved spio manifest path',
      'Module host refresh requested',
      'Native bridge local.runtime.desktop',
      'Settings route is reserved',
      'Type Hierarchy "MissingType" found no type target',
      'Go to Implementation "MissingType" found no type target',
      'Call Hierarchy "missingCall" found no callable target',
      'Workspace replace not applied',
      'Rename Symbol not applied',
      'Workspace Code Action not applied',
    ]) {
      expect(
        shell.debugLog.any((entry) => entry.contains(fragment)),
        isTrue,
        reason: 'Expected debug log to contain "$fragment".',
      );
    }
  });

  test(
    'shell runtime exposes cached palette, quick open, '
    'and unavailable toolchain paths',
    () async {
      const initialDocument = DocumentState(
        documentId: 'src/main.styio',
        text: 'value = 1\n',
        revision: 0,
      );
      final shell = _createNoopShellRuntime(
        projectGraph: _projectGraphWithFiles(
          const <String>['src/main.styio', 'src/worker.styio'],
        ),
        documentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: const <String, DocumentState>{
            'src/main.styio': initialDocument,
          },
        ),
        initialDocument: initialDocument,
      );
      addTearDown(shell.dispose);

      final palette = shell.searchCommandPalette(
        const CommandPaletteQuery(pattern: 'save'),
      );
      final quickOpen = shell.quickOpenWorkspace(
        const WorkspaceQuickOpenQuery(pattern: 'worker'),
      );

      expect(shell.lastCommandPalette, same(palette));
      expect(shell.lastWorkspaceQuickOpen, same(quickOpen));
      expect(quickOpen.items.single.filePath, 'src/worker.styio');
      expect(shell.lastWorkspaceRename, isNull);
      expect(shell.lastToolchainInstallExecutionResult, isNull);

      expect(await shell.selectToolchainCandidate('styio-service'), isNull);
      expect(await shell.clearToolchainCandidate(ToolchainKind.runner), isNull);
      expect(shell.planManagedToolchainInstallation(), isNull);
      expect(await shell.executeLastToolchainInstallPlan(), isNull);

      shell.editorController.insertText('local ');
      final conflict = shell.markEditorResourceExternalChanged(
        const DocumentState(
          documentId: 'src/main.styio',
          text: 'external = 2\n',
          revision: 4,
        ),
      );

      expect(conflict.state, DocumentResourceBindingState.conflicted);
      for (final fragment in const <String>[
        'Toolchain selection unavailable',
        'Toolchain clear unavailable',
        'Toolchain install planning unavailable',
        'Toolchain install execution unavailable',
        'External change conflicted',
      ]) {
        expect(shell.debugLog.any((entry) => entry.contains(fragment)), isTrue);
      }
    },
  );

  test('shell runtime records verbose run output and command navigation', () async {
    const mainDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'value = 1\n',
      revision: 0,
    );
    const workerDocument = DocumentState(
      documentId: 'src/worker.styio',
      text: 'worker = 2\n',
      revision: 0,
    );
    final shell = _createNoopShellRuntime(
      projectGraph: _projectGraphWithFiles(
        const <String>['src/main.styio', 'src/worker.styio'],
      ),
      documentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': mainDocument,
          'src/worker.styio': workerDocument,
        },
      ),
      initialDocument: mainDocument,
      executionAdapter: const _VerboseExecutionAdapter(),
    );
    addTearDown(shell.dispose);

    await shell.openWorkspaceQuickOpenItem(
      const WorkspaceQuickOpenItem(
        filePath: 'src/worker.styio',
        fileName: 'worker.styio',
        parentPath: 'src',
        score: 10,
        matches: <WorkspaceQuickOpenMatch>[],
      ),
    );
    await shell.executeCommand(AppCommandId.navigateBack);
    await shell.executeCommand(AppCommandId.navigateForward);
    await shell.executeCommand(AppCommandId.run);

    expect(shell.workspaceController.activeFilePath, 'src/worker.styio');
    expect(shell.lastExecutionSession?.sessionId, 'verbose-run');
    for (final fragment in const <String>[
      'Go Back opened',
      'Go Forward opened',
      'stdout: first stdout',
      'stderr: first stderr',
      'diagnostics: 1 issue',
    ]) {
      expect(shell.debugLog.any((entry) => entry.contains(fragment)), isTrue);
    }
  });
}

ShellRuntimeModel _createNoopShellRuntime({
  required ProjectGraphSnapshot projectGraph,
  required WorkspaceDocumentStore documentStore,
  required DocumentState initialDocument,
  ExecutionAdapter executionAdapter = const _NoopExecutionAdapter(),
  RuntimeEventAdapter runtimeEventAdapter = const _NoopRuntimeEventAdapter(),
}) {
  return ShellRuntimeModel(
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
    executionAdapter: executionAdapter,
    executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
        executionAdapter,
    runtimeEventAdapter: runtimeEventAdapter,
    dependencySourceAdapter: const _NoopDependencySourceAdapter(),
    deploymentAdapter: const _NoopDeploymentAdapter(),
    toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
  );
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

class _VerboseExecutionAdapter implements ExecutionAdapter {
  const _VerboseExecutionAdapter();

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
      sessionId: 'verbose-run',
      kind: 'run',
      status: ExecutionSessionStatus.failed,
      statusMessage: 'verbose run failed with structured output',
      diagnostics: <Diagnostic>[
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'verbose-diagnostic',
          message: 'verbose diagnostic',
          range: SourceRange(start: 0, end: 5),
        ),
      ],
      stdoutEvents: <ExecutionLogEvent>[
        ExecutionLogEvent(message: 'first stdout'),
        ExecutionLogEvent(message: 'second stdout'),
      ],
      stderrEvents: <ExecutionLogEvent>[
        ExecutionLogEvent(message: 'first stderr'),
      ],
    );
  }
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
