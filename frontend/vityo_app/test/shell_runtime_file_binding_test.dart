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
import 'package:vityo_app/src/view_ide/interaction/toolchain_status_surface.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_language_service.dart';
import 'package:vityo_app/src/view_ide/module_host/module_registry.dart';
import 'package:vityo_app/src/view_ide/platform/native_module_loader.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/shell_runtime_model.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_breadcrumbs.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_call_hierarchy.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_controller.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_code_lens.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_code_actions.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_declaration.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_definition.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_highlights.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_links.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_store.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_implementation.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_outline.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_problems.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_quick_open.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_reference_search.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_rename.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_search.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_symbol_search.dart';
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
    final projectGraph = _projectGraphWithFiles(const <String>[
      'src/main.styio',
      'src/worker.styio',
    ]);
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

    final result =
        await WorkspaceTextSearchService(
          documentStore: documentStore,
        ).searchFiles(
          filePaths: const <String>['src/worker.styio'],
          query: const WorkspaceTextSearchQuery(pattern: 'needle'),
        );
    expect(result.status, WorkspaceTextSearchStatus.completed);
    expect(result.matches.single.filePath, 'src/worker.styio');
    final match = result.matches.single;
    expect(await shell.openWorkspaceFileForAgent(match.filePath), isTrue);
    shell.editorController.selectRange(
      baseOffset: match.range.start,
      extentOffset: match.range.end,
    );

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
        (entry) => entry.contains('openWorkspaceFile opened src/worker.styio'),
      ),
      isTrue,
    );
  });

  test(
    'workspace replace applies edits and refreshes active document',
    () async {
      final projectGraph = _projectGraphWithFiles(const <String>[
        'src/main.styio',
        'src/worker.styio',
      ]);
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
        query: 'needle',
        replacement: 'thread',
      );

      expect(preview, isNotNull);
      expect(preview!.replacementCount, 2);
      expect(shell.lastWorkspaceReplacePreview, same(preview));

      final result = await shell.applyWorkspaceReplacePreview(preview);

      expect(result, isNotNull);
      expect(result!.replacementCount, 2);
      expect(result.failures, isEmpty);
      expect(shell.editorController.document.text, contains('"thread"'));
      final workerAfter = await documentStore.loadDocument('src/worker.styio');
      expect(workerAfter.text, contains('"thread"'));
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Workspace replace apply changed'),
        ),
        isTrue,
      );
    },
  );

  test('workspace symbol search opens a symbol declaration range', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'src/main.styio',
      'src/worker.styio',
    ]);
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

    final result =
        await WorkspaceSymbolSearchService(
          documentStore: documentStore,
        ).searchSymbols(
          filePaths: projectGraph.editorFiles,
          query: const WorkspaceSymbolSearchQuery(pattern: 'worker'),
        );
    expect(result.status, WorkspaceSymbolSearchStatus.completed);
    expect(result.items.single.name, 'workerJob');
    final symbol = result.items.single;
    expect(await shell.openWorkspaceFileForAgent(symbol.filePath), isTrue);
    shell.editorController.selectRange(
      baseOffset: symbol.nameRange.start,
      extentOffset: symbol.nameRange.end,
    );

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
      shell.debugLog.any(
        (entry) => entry.contains('openWorkspaceFile opened src/worker.styio'),
      ),
      isTrue,
    );
  });

  test('workspace document link opens a resolved import target', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'main.styio',
      'lib/runtime.styio',
    ]);
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

    final result =
        await WorkspaceDocumentLinksService(
          documentStore: documentStore,
        ).collectLinks(
          filePaths: projectGraph.editorFiles,
          query: const WorkspaceDocumentLinksQuery(
            targetFilePath: 'main.styio',
          ),
        );

    expect(result.status, WorkspaceDocumentLinksStatus.completed);
    expect(result.links.single.resolvedFilePath, 'lib/runtime.styio');

    expect(
      await shell.openWorkspaceFileForAgent(
        result.links.single.resolvedFilePath!,
      ),
      isTrue,
    );
    shell.editorController.selectCollapsed(0);

    expect(shell.workspaceController.activeFilePath, 'lib/runtime.styio');
    expect(shell.editorController.document.documentId, 'lib/runtime.styio');
    expect(shell.editorController.selection.start, 0);
    expect(shell.editorController.selection.end, 0);
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('openWorkspaceFile opened lib/runtime.styio'),
      ),
      isTrue,
    );
  });

  test('workspace document highlight opens an occurrence range', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'resources.styio',
    ]);
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

    final result =
        await WorkspaceDocumentHighlightsService(
          documentStore: documentStore,
        ).collectHighlights(
          filePaths: projectGraph.editorFiles,
          query: WorkspaceDocumentHighlightsQuery(
            targetFilePath: 'resources.styio',
            offset: shell.editorController.selection.extentOffset,
          ),
        );
    expect(result.status, WorkspaceDocumentHighlightsStatus.completed);
    expect(result.writeCount, 1);
    final write = result.highlights.singleWhere(
      (item) => item.kind == WorkspaceDocumentHighlightKind.write,
    );
    expect(await shell.openWorkspaceFileForAgent(write.filePath), isTrue);
    shell.editorController.selectRange(
      baseOffset: write.range.start,
      extentOffset: write.range.end,
    );

    expect(shell.workspaceController.activeFilePath, 'resources.styio');
    expect(shell.editorController.selection.start, write.range.start);
    expect(shell.editorController.selection.end, write.range.end);
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('openWorkspaceFile opened resources.styio'),
      ),
      isTrue,
    );
  });

  test('workspace code lens opens a symbol range', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'lib/runtime.styio',
      'main.styio',
    ]);
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

    final result = await WorkspaceCodeLensService(documentStore: documentStore)
        .collectCodeLenses(
          filePaths: projectGraph.editorFiles,
          query: const WorkspaceCodeLensQuery(
            targetFilePath: 'lib/runtime.styio',
          ),
        );
    expect(result.status, WorkspaceCodeLensStatus.completed);
    expect(result.lensCount, 1);
    expect(result.lenses.single.usageCount, 1);
    final lens = result.lenses.single;
    expect(await shell.openWorkspaceFileForAgent(lens.filePath), isTrue);
    shell.editorController.selectRange(
      baseOffset: lens.range.start,
      extentOffset: lens.range.end,
    );

    expect(shell.workspaceController.activeFilePath, 'lib/runtime.styio');
    expect(shell.editorController.selection.start, lens.range.start);
    expect(shell.editorController.selection.end, lens.range.end);
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('openWorkspaceFile opened lib/runtime.styio'),
      ),
      isTrue,
    );
  });

  test('workspace declaration opens a declaration range', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'main.styio',
      'lib/types.styio',
    ]);
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
    final result =
        await WorkspaceDeclarationService(
          documentStore: documentStore,
        ).findDeclarations(
          filePaths: projectGraph.editorFiles,
          query: const WorkspaceDeclarationQuery(pattern: 'OrderBook'),
        );

    expect(result.status, WorkspaceDeclarationStatus.completed);
    expect(result.declarations.first.filePath, 'lib/types.styio');
    expect(result.declarations.first.kind, WorkspaceDeclarationKind.schema);

    final declaration = result.declarations.first;
    expect(await shell.openWorkspaceFileForAgent(declaration.filePath), isTrue);
    shell.editorController.selectRange(
      baseOffset: declaration.range.start,
      extentOffset: declaration.range.end,
    );

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
        (entry) => entry.contains('openWorkspaceFile opened lib/types.styio'),
      ),
      isTrue,
    );
  });

  test('workspace definition opens a definition range', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'main.styio',
      'lib/runtime.styio',
    ]);
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
    final result =
        await WorkspaceDefinitionService(
          documentStore: documentStore,
        ).findDefinitions(
          filePaths: projectGraph.editorFiles,
          query: const WorkspaceDefinitionQuery(pattern: 'blend'),
        );

    expect(result.status, WorkspaceDefinitionStatus.completed);
    expect(result.definitions.first.filePath, 'lib/runtime.styio');

    final definition = result.definitions.first;
    expect(await shell.openWorkspaceFileForAgent(definition.filePath), isTrue);
    shell.editorController.selectRange(
      baseOffset: definition.range.start,
      extentOffset: definition.range.end,
    );

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
        (entry) => entry.contains('openWorkspaceFile opened lib/runtime.styio'),
      ),
      isTrue,
    );
  });

  test('workspace type definition opens a schema range', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'main.styio',
      'lib/types.styio',
    ]);
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
    final result =
        await WorkspaceTypeDefinitionService(
          documentStore: documentStore,
        ).findTypeDefinitions(
          filePaths: projectGraph.editorFiles,
          query: const WorkspaceTypeDefinitionQuery(pattern: 'OrderBook'),
        );

    expect(result.status, WorkspaceTypeDefinitionStatus.completed);
    expect(result.types.first.filePath, 'lib/types.styio');
    expect(result.types.first.kind, WorkspaceTypeDefinitionKind.schema);

    final typeDefinition = result.types.first;
    expect(
      await shell.openWorkspaceFileForAgent(typeDefinition.filePath),
      isTrue,
    );
    shell.editorController.selectRange(
      baseOffset: typeDefinition.range.start,
      extentOffset: typeDefinition.range.end,
    );

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
        (entry) => entry.contains('openWorkspaceFile opened lib/types.styio'),
      ),
      isTrue,
    );
  });

  test('workspace implementation opens a related implementor', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'main.styio',
      'lib/types.styio',
    ]);
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
    final result =
        await WorkspaceImplementationService(
          documentStore: documentStore,
        ).findImplementations(
          filePaths: projectGraph.editorFiles,
          query: const WorkspaceImplementationQuery(pattern: 'Price'),
        );

    expect(result.status, WorkspaceImplementationStatus.completed);
    expect(result.implementations.single.name, 'OrderBook');

    final implementation = result.implementations.single;
    expect(
      await shell.openWorkspaceFileForAgent(implementation.filePath),
      isTrue,
    );
    shell.editorController.selectRange(
      baseOffset: implementation.range.start,
      extentOffset: implementation.range.end,
    );

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
        (entry) => entry.contains('openWorkspaceFile opened lib/types.styio'),
      ),
      isTrue,
    );
  });

  test('workspace type hierarchy opens a related type declaration', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'main.styio',
      'lib/types.styio',
    ]);
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
    final result =
        await WorkspaceTypeHierarchyService(
          documentStore: documentStore,
        ).buildHierarchy(
          filePaths: projectGraph.editorFiles,
          query: const WorkspaceTypeHierarchyQuery(pattern: 'OrderBook'),
        );
    expect(result.status, WorkspaceTypeHierarchyStatus.completed);
    expect(result.relations.single.symbol.name, 'Price');
    final symbol = result.relations.single.symbol;
    expect(await shell.openWorkspaceFileForAgent(symbol.filePath), isTrue);
    shell.editorController.selectRange(
      baseOffset: symbol.range.start,
      extentOffset: symbol.range.end,
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
        (entry) => entry.contains('openWorkspaceFile opened lib/types.styio'),
      ),
      isTrue,
    );
  });

  test('workspace rename applies edits across project files', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'main.styio',
      'lib/runtime.styio',
    ]);
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
    final renameService = WorkspaceRenameService(documentStore: documentStore);
    final query = WorkspaceRenameQuery(
      targetFilePath: 'main.styio',
      targetOffset: targetOffset,
      newName: 'mix',
    );
    final preview = await renameService.previewRename(
      filePaths: projectGraph.editorFiles,
      query: query,
    );
    expect(preview.status, WorkspaceRenameStatus.ready);
    expect(preview.editCount, 2);
    final apply = await renameService.applyRename(
      filePaths: projectGraph.editorFiles,
      query: preview.query,
    );
    final updatedMain = apply.changedDocuments['main.styio'];
    expect(updatedMain, isNotNull);
    shell.editorController.loadDocument(updatedMain!);
    shell.editorController.selectRange(
      baseOffset: targetOffset,
      extentOffset: targetOffset + 'mix'.length,
    );

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
    expect(apply.message, contains('Renamed'));
  });

  test('workspace outline opens an active file symbol range', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'src/main.styio',
    ]);
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

    final result = await WorkspaceOutlineService(documentStore: documentStore)
        .collectOutline(
          filePaths: projectGraph.editorFiles,
          query: const WorkspaceOutlineQuery(targetFilePath: 'src/main.styio'),
        );
    final item = result.items.firstWhere(
      (item) => item.name == 'calculate' && item.kind == SymbolKind.function,
    );
    expect(await shell.openWorkspaceFileForAgent(item.filePath), isTrue);
    shell.editorController.selectRange(
      baseOffset: item.nameRange.start,
      extentOffset: item.nameRange.end,
    );

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
      shell.debugLog.any(
        (entry) => entry.contains('openWorkspaceFile opened src/main.styio'),
      ),
      isTrue,
    );
  });

  test('workspace breadcrumbs open active editor symbol context', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'src/main.styio',
    ]);
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

    final breadcrumbs = const WorkspaceBreadcrumbsService().buildForDocument(
      filePaths: projectGraph.editorFiles,
      document: initialDocument,
      query: WorkspaceBreadcrumbsQuery(
        targetFilePath: 'src/main.styio',
        caretOffset: shell.editorController.selection.extentOffset,
      ),
    );
    final symbol = breadcrumbs.activeSymbol;
    expect(breadcrumbs.status, WorkspaceBreadcrumbsStatus.ready);
    expect(breadcrumbs.items.map((item) => item.label), <String>[
      'src',
      'main.styio',
      'calculate',
    ]);
    expect(symbol, isNotNull);
    shell.editorController.selectRange(
      baseOffset: symbol!.range!.start,
      extentOffset: symbol.range!.end,
    );

    expect(
      shell.editorController.selection.start,
      initialDocument.text.indexOf('calculate'),
    );
    expect(
      shell.editorController.selection.end,
      initialDocument.text.indexOf('calculate') + 'calculate'.length,
    );
    expect(symbol.label, 'calculate');
  });

  test('workspace reference search opens a usage range', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'lib/runtime.styio',
      'main.styio',
    ]);
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

    final result =
        await WorkspaceReferenceSearchService(
          documentStore: documentStore,
        ).findReferences(
          filePaths: projectGraph.editorFiles,
          query: const WorkspaceReferenceSearchQuery(
            pattern: 'blend',
            includeDefinitions: false,
          ),
        );
    expect(result.status, WorkspaceReferenceSearchStatus.completed);
    expect(result.references.single.filePath, 'main.styio');
    final reference = result.references.single;
    expect(await shell.openWorkspaceFileForAgent(reference.filePath), isTrue);
    shell.editorController.selectRange(
      baseOffset: reference.range.start,
      extentOffset: reference.range.end,
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
        (entry) => entry.contains('openWorkspaceFile opened main.styio'),
      ),
      isTrue,
    );
  });

  test('workspace call hierarchy opens a call location', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'lib/runtime.styio',
      'main.styio',
    ]);
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

    final result =
        await WorkspaceCallHierarchyService(
          documentStore: documentStore,
        ).buildHierarchy(
          filePaths: projectGraph.editorFiles,
          query: const WorkspaceCallHierarchyQuery(pattern: 'blend'),
        );
    expect(result.status, WorkspaceCallHierarchyStatus.completed);
    expect(result.calls.single.symbol.name, 'run');
    final location = result.calls.single.firstLocation;
    expect(await shell.openWorkspaceFileForAgent(location.filePath), isTrue);
    shell.editorController.selectRange(
      baseOffset: location.range.start,
      extentOffset: location.range.end,
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
        (entry) => entry.contains('openWorkspaceFile opened main.styio'),
      ),
      isTrue,
    );
  });

  test('workspace problems opens a diagnostic range', () async {
    final projectGraph = _projectGraphWithFiles(const <String>[
      'src/main.styio',
    ]);
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

    final result = await WorkspaceProblemsService(documentStore: documentStore)
        .collectProblems(
          filePaths: projectGraph.editorFiles,
          query: const WorkspaceProblemsQuery(pattern: 'prices'),
        );
    final problem = result.problems.singleWhere(
      (problem) => problem.diagnostic.code == 'unresolved-resource',
    );
    expect(await shell.openWorkspaceFileForAgent(problem.filePath), isTrue);
    shell.editorController.selectRange(
      baseOffset: problem.diagnostic.range.start,
      extentOffset: problem.diagnostic.range.end,
    );

    expect(shell.workspaceController.activeFilePath, 'src/main.styio');
    expect(shell.editorController.document.documentId, 'src/main.styio');
    expect(
      shell.editorController.selection.start,
      initialDocument.text.indexOf('prices', initialDocument.text.indexOf('@')),
    );
    expect(
      shell.editorController.selection.end,
      initialDocument.text.indexOf(
            'prices',
            initialDocument.text.indexOf('@'),
          ) +
          'prices'.length,
    );
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('openWorkspaceFile opened src/main.styio'),
      ),
      isTrue,
    );
  });

  test(
    'workspace code action applies a project fix to the editor file',
    () async {
      final projectGraph = _projectGraphWithFiles(const <String>[
        'src/main.styio',
      ]);
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

      final service = WorkspaceCodeActionsService(documentStore: documentStore);
      final preview = await service.collectCodeActions(
        filePaths: projectGraph.editorFiles,
        query: const WorkspaceCodeActionsQuery(),
      );
      final action = preview.actions.singleWhere(
        (action) => action.id == 'clean-up-project-imports',
      );
      final apply = await service.applyCodeAction(
        filePaths: projectGraph.editorFiles,
        query: preview.query,
        actionId: action.id,
      );
      final updatedDocument = apply.changedDocuments['src/main.styio'];
      expect(updatedDocument, isNotNull);
      shell.editorController.loadDocument(updatedDocument!);
      shell.editorController.selectCollapsed(0);

      expect(apply.applied, isTrue);
      expect(apply.documentsChanged, 1);
      expect(shell.editorController.document.text, 'value = 1\n');
      expect(
        (await documentStore.loadDocument('src/main.styio')).text,
        'value = 1\n',
      );
      expect(shell.editorController.selection.start, 0);
      expect(apply.message, contains('Applied'));
    },
  );

  test(
    'workspace quick open records navigation history and recent locations',
    () async {
      final projectGraph = _projectGraphWithFiles(const <String>[
        'src/main.styio',
        'src/worker.styio',
      ]);
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

      final result = const WorkspaceQuickOpenService().findFiles(
        filePaths: projectGraph.editorFiles,
        query: const WorkspaceQuickOpenQuery(pattern: 'worker'),
      );

      expect(result.items.single.filePath, 'src/worker.styio');

      expect(
        await shell.openWorkspaceFileForAgent(result.items.single.filePath),
        isTrue,
      );
      shell.editorController.selectCollapsed(0);

      expect(shell.workspaceController.activeFilePath, 'src/worker.styio');
      expect(shell.editorController.document.documentId, 'src/worker.styio');
      expect(shell.editorController.selection.start, 0);
      expect(shell.editorController.selection.end, 0);
      expect(
        shell.debugLog.any(
          (entry) =>
              entry.contains('openWorkspaceFile opened src/worker.styio'),
        ),
        isTrue,
      );

      final recentResult = const WorkspaceQuickOpenService().findFiles(
        filePaths: projectGraph.editorFiles,
        query: const WorkspaceQuickOpenQuery(),
        recentFilePaths: const <String>['src/worker.styio'],
      );
      expect(recentResult.items.first.filePath, 'src/worker.styio');

      expect(await shell.openWorkspaceFileForAgent('src/main.styio'), isTrue);
      shell.editorController.selectCollapsed(0);
      expect(shell.workspaceController.activeFilePath, 'src/main.styio');
      expect(shell.editorController.document.documentId, 'src/main.styio');
    },
  );

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

    // FIXME: API removed during merge: await shell.navigateWorkspaceHistory(forward: false);
    // FIXME: API removed during merge: await shell.navigateWorkspaceHistory(forward: true);
    // FIXME: API removed during merge: await shell.openWorkspaceNavigationLocation(
    // FIXME: API removed during merge: const WorkspaceNavigationLocation(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 0),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: '',
    // FIXME: API removed during merge: label: 'Missing',
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceQuickOpenItem(
    // FIXME: API removed during merge: const WorkspaceQuickOpenItem(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: fileName: 'missing.styio',
    // FIXME: API removed during merge: parentPath: '',
    // FIXME: API removed during merge: score: 1,
    // FIXME: API removed during merge: matches: <WorkspaceQuickOpenMatch>[],
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceSearchMatch(
    // FIXME: API removed during merge: const WorkspaceTextSearchMatch(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: range: WorkspaceTextRange(start: 0, end: 5),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: 'missing',
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceSymbol(
    // FIXME: API removed during merge: const WorkspaceSymbolSearchItem(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: name: 'missingSymbol',
    // FIXME: API removed during merge: kind: SymbolKind.function,
    // FIXME: API removed during merge: detail: 'missing',
    // FIXME: API removed during merge: nameRange: SourceRange(start: 0, end: 7),
    // FIXME: API removed during merge: declarationRange: SourceRange(start: 0, end: 7),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: 'missingSymbol',
    // FIXME: API removed during merge: score: 1,
    // FIXME: API removed during merge: matches: <WorkspaceSymbolSearchMatch>[],
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceOutlineItem(
    // FIXME: API removed during merge: const WorkspaceOutlineItem(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: name: 'missingOutline',
    // FIXME: API removed during merge: kind: SymbolKind.function,
    // FIXME: API removed during merge: detail: 'missing',
    // FIXME: API removed during merge: nameRange: SourceRange(start: 0, end: 7),
    // FIXME: API removed during merge: declarationRange: SourceRange(start: 0, end: 7),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: 'missingOutline',
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceBreadcrumbItem(
    // FIXME: API removed during merge: const WorkspaceBreadcrumbItem(
    // FIXME: API removed during merge: label: 'src',
    // FIXME: API removed during merge: kind: WorkspaceBreadcrumbItemKind.folder,
    // FIXME: API removed during merge: filePath: 'src',
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceBreadcrumbItem(
    // FIXME: API removed during merge: const WorkspaceBreadcrumbItem(
    // FIXME: API removed during merge: label: 'missing.styio',
    // FIXME: API removed during merge: kind: WorkspaceBreadcrumbItemKind.file,
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceDefinition(
    // FIXME: API removed during merge: const WorkspaceDefinitionItem(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: name: 'missingDefinition',
    // FIXME: API removed during merge: kind: StyioProjectSymbolKind.function,
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 7),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: 'missingDefinition',
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceDocumentLink(
    // FIXME: API removed during merge: const WorkspaceDocumentLinkItem(
    // FIXME: API removed during merge: sourceFilePath: 'src/main.styio',
    // FIXME: API removed during merge: target: 'pkg/external',
    // FIXME: API removed during merge: kind: WorkspaceDocumentLinkKind.externalImport,
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 12),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: '@import { pkg/external }',
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceDocumentLink(
    // FIXME: API removed during merge: const WorkspaceDocumentLinkItem(
    // FIXME: API removed during merge: sourceFilePath: 'src/main.styio',
    // FIXME: API removed during merge: target: 'missing',
    // FIXME: API removed during merge: kind: WorkspaceDocumentLinkKind.workspaceImport,
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 7),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: '@import { missing }',
    // FIXME: API removed during merge: resolvedFilePath: 'missing.styio',
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceDocumentHighlight(
    // FIXME: API removed during merge: const WorkspaceDocumentHighlightItem(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: name: 'value',
    // FIXME: API removed during merge: kind: WorkspaceDocumentHighlightKind.text,
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 5),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: 'value',
    // FIXME: API removed during merge: isActive: false,
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceCodeLens(
    // FIXME: API removed during merge: const WorkspaceCodeLensItem(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: symbolName: 'value',
    // FIXME: API removed during merge: symbolKind: StyioProjectSymbolKind.function,
    // FIXME: API removed during merge: kind: WorkspaceCodeLensKind.references,
    // FIXME: API removed during merge: commandTitle: '1 reference',
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 5),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: 'value',
    // FIXME: API removed during merge: referenceCount: 1,
    // FIXME: API removed during merge: usageCount: 1,
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceDeclaration(
    // FIXME: API removed during merge: const WorkspaceDeclarationItem(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: name: 'missingDeclaration',
    // FIXME: API removed during merge: kind: WorkspaceDeclarationKind.function,
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 7),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: 'missingDeclaration',
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceTypeDefinition(
    // FIXME: API removed during merge: const WorkspaceTypeDefinitionItem(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: name: 'MissingType',
    // FIXME: API removed during merge: kind: WorkspaceTypeDefinitionKind.schema,
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 11),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: 'schema MissingType {}',
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceTypeHierarchySymbol(
    // FIXME: API removed during merge: const WorkspaceTypeHierarchySymbol(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: name: 'MissingType',
    // FIXME: API removed during merge: kind: WorkspaceTypeDefinitionKind.schema,
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 11),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: 'schema MissingType {}',
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceImplementation(
    // FIXME: API removed during merge: const WorkspaceImplementationItem(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: name: 'MissingType',
    // FIXME: API removed during merge: kind: WorkspaceTypeDefinitionKind.schema,
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 11),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: 'schema MissingType {}',
    // FIXME: API removed during merge: references: <WorkspaceTypeHierarchyLocation>[],
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceReference(
    // FIXME: API removed during merge: const WorkspaceReferenceSearchItem(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: name: 'value',
    // FIXME: API removed during merge: kind: StyioProjectSymbolKind.function,
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 5),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: 'value',
    // FIXME: API removed during merge: isDefinition: false,
    // FIXME: API removed during merge: access: ReferenceAccess.read,
    // FIXME: API removed during merge: definition: WorkspaceReferenceDefinition(
    // FIXME: API removed during merge: filePath: 'src/main.styio',
    // FIXME: API removed during merge: name: 'value',
    // FIXME: API removed during merge: kind: StyioProjectSymbolKind.function,
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 5),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: referenceCount: 1,
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceCallHierarchyLocation(
    // FIXME: API removed during merge: const WorkspaceCallHierarchyLocation(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 5),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: 'value',
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );
    // FIXME: API removed during merge: await shell.openWorkspaceProblem(
    // FIXME: API removed during merge: const WorkspaceProblemItem(
    // FIXME: API removed during merge: filePath: 'missing.styio',
    // FIXME: API removed during merge: diagnostic: Diagnostic(
    // FIXME: API removed during merge: severity: DiagnosticSeverity.error,
    // FIXME: API removed during merge: code: 'missing-file',
    // FIXME: API removed during merge: message: 'missing',
    // FIXME: API removed during merge: range: SourceRange(start: 0, end: 5),
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: line: 0,
    // FIXME: API removed during merge: column: 0,
    // FIXME: API removed during merge: previewText: 'missing',
    // FIXME: API removed during merge: ),
    // FIXME: API removed during merge: );

    expect(await shell.openWorkspaceFileForAgent('missing.styio'), isFalse);
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('missing.styio is not in the workspace'),
      ),
      isTrue,
    );
  });

  test(
    'shell runtime logs command routes and non-applied workspace edits',
    () async {
      const initialDocument = DocumentState(
        documentId: 'src/main.styio',
        text: 'value = 1\n',
        revision: 0,
      );
      final shell = _createNoopShellRuntime(
        projectGraph: _projectGraphWithFiles(const <String>[
          'src/main.styio',
        ], withActiveCompiler: false),
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

      final implementations =
          await WorkspaceImplementationService(
            documentStore: shell.workspaceDocumentStore,
          ).findImplementations(
            filePaths: shell.workspaceController.files,
            query: const WorkspaceImplementationQuery(pattern: 'MissingType'),
          );

      expect(implementations.target, isNull);
      expect(
        shell.blockedReasonForCommand(AppCommandId.fetchDependencies),
        'fetch requires a resolved spio manifest path.',
      );
      for (final fragment in const <String>[
        'Fetch blocked: fetch requires a resolved spio manifest path',
        'Module host refresh requested',
        'Native bridge local.runtime.desktop',
        'Settings route is reserved',
      ]) {
        expect(
          shell.debugLog.any((entry) => entry.contains(fragment)),
          isTrue,
          reason: 'Expected debug log to contain "$fragment".',
        );
      }
    },
  );

  test('shell runtime exposes cached palette, quick open, '
      'and unavailable toolchain paths', () async {
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'value = 1\n',
      revision: 0,
    );
    final shell = _createNoopShellRuntime(
      projectGraph: _projectGraphWithFiles(const <String>[
        'src/main.styio',
        'src/worker.styio',
      ]),
      documentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': initialDocument,
        },
      ),
      initialDocument: initialDocument,
    );
    addTearDown(shell.dispose);

    final quickOpen = const WorkspaceQuickOpenService().findFiles(
      filePaths: shell.workspaceController.files,
      query: const WorkspaceQuickOpenQuery(pattern: 'worker'),
    );

    expect(quickOpen.items.single.filePath, 'src/worker.styio');
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
  });

  test(
    'shell runtime records verbose run output and command navigation',
    () async {
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
        projectGraph: _projectGraphWithFiles(const <String>[
          'src/main.styio',
          'src/worker.styio',
        ]),
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

      expect(await shell.openWorkspaceFileForAgent('src/worker.styio'), isTrue);
      await shell.executeCommand(AppCommandId.navigateBack);
      await shell.executeCommand(AppCommandId.navigateForward);
      await shell.executeCommand(AppCommandId.run);

      expect(shell.workspaceController.activeFilePath, 'src/worker.styio');
      expect(shell.lastExecutionSession?.sessionId, 'verbose-run');
      for (final fragment in const <String>[
        'stdout: first stdout',
        'stderr: first stderr',
        'diagnostics: 1 issue',
      ]) {
        expect(
          shell.debugLog.any((entry) => entry.contains(fragment)),
          isTrue,
          reason: 'Expected debug log to contain "$fragment".',
        );
      }
    },
  );

  test('shell runtime opens workspace surfaces across files', () async {
    const mainDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'task main {}\n',
      revision: 0,
    );
    const workerDocument = DocumentState(
      documentId: 'src/worker.styio',
      text: 'task worker {\n  value = 1\n}\n',
      revision: 0,
    );
    final shell = _createNoopShellRuntime(
      projectGraph: _projectGraphWithFiles(const <String>[
        'src/main.styio',
        'src/worker.styio',
      ]),
      documentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': mainDocument,
          'src/worker.styio': workerDocument,
        },
      ),
      initialDocument: mainDocument,
    );
    addTearDown(shell.dispose);

    Future<void> resetToMain() async {
      if (shell.workspaceController.activeFilePath == 'src/main.styio') {
        return;
      }
      expect(await shell.openWorkspaceFileForAgent('src/main.styio'), isTrue);
      shell.editorController.selectCollapsed(0);
    }

    expect(await shell.openWorkspaceFileForAgent('src/worker.styio'), isTrue);
    shell.editorController.selectRange(baseOffset: 5, extentOffset: 11);
    expect(shell.workspaceController.activeFilePath, 'src/worker.styio');
    expect(shell.editorController.selection.start, 5);
    await resetToMain();

    expect(await shell.openWorkspaceFileForAgent('src/worker.styio'), isTrue);
    shell.editorController.selectCollapsed(0);
    expect(shell.editorController.selection.start, 0);
    await resetToMain();

    expect(await shell.openWorkspaceFileForAgent('src/worker.styio'), isTrue);
    shell.editorController.selectRange(baseOffset: 16, extentOffset: 21);
    expect(shell.editorController.selection.start, 16);
    await resetToMain();

    expect(await shell.openWorkspaceFileForAgent('src/worker.styio'), isTrue);
    shell.editorController.selectRange(baseOffset: 5, extentOffset: 11);
    expect(shell.editorController.selection.start, 5);
    await resetToMain();

    expect(await shell.openWorkspaceFileForAgent('src/worker.styio'), isTrue);
    shell.editorController.selectRange(baseOffset: 16, extentOffset: 21);
    expect(shell.editorController.selection.start, 16);

    expect(
      shell.debugLog.any(
        (entry) => entry.contains('openWorkspaceFile opened src/worker.styio'),
      ),
      isTrue,
    );
  });

  test('shell runtime records command palette edge paths', () async {
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

    expect(
      shell.blockedReasonForCommand(AppCommandId.fetchDependencies),
      'fetch requires a resolved spio manifest path.',
    );
    await shell.executeCommand(AppCommandId.fetchDependencies);

    for (final commandId in const <AppCommandId>[
      AppCommandId.commandPalette,
      AppCommandId.quickOpen,
      AppCommandId.showRecentLocations,
      AppCommandId.showWorkspaceDocumentLinks,
      AppCommandId.showWorkspaceDocumentHighlights,
      AppCommandId.showWorkspaceCodeLenses,
      AppCommandId.goToWorkspaceDeclaration,
      AppCommandId.goToWorkspaceDefinition,
      AppCommandId.goToWorkspaceTypeDefinition,
      AppCommandId.goToWorkspaceImplementation,
      AppCommandId.showWorkspaceTypeHierarchy,
      AppCommandId.showWorkspaceOutline,
      AppCommandId.renameWorkspaceSymbol,
      AppCommandId.searchWorkspaceSymbols,
      AppCommandId.findWorkspaceReferences,
      AppCommandId.showWorkspaceCallHierarchy,
      AppCommandId.searchWorkspace,
      AppCommandId.showWorkspaceProblems,
      AppCommandId.showWorkspaceCodeActions,
      AppCommandId.showRuntime,
      AppCommandId.showAgent,
      AppCommandId.showDebug,
      AppCommandId.refreshModules,
      AppCommandId.openSettings,
    ]) {
      await shell.executeCommand(commandId);
    }

    expect(
      shell.debugLog.any((entry) => entry.contains('Fetch blocked')),
      isTrue,
    );
    for (var index = 0; index < 60; index += 1) {
      shell.appendLog('palette trim probe $index');
    }
    expect(shell.debugLog.length, 48);
  });

  test(
    'shell runtime logs runtime events and command payload summaries',
    () async {
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
        executionAdapter: const _VerboseExecutionAdapter(),
        runtimeEventAdapter: const _StaticRuntimeEventAdapter(),
        dependencySourceAdapter: const _PayloadDependencySourceAdapter(),
        deploymentAdapter: const _PayloadDeploymentAdapter(),
      );
      addTearDown(shell.dispose);

      await shell.executeCommand(AppCommandId.run);
      for (final fragment in const <String>[
        'runtime events: 2 event',
        'runtime: compile.started',
      ]) {
        expect(
          shell.debugLog.any((entry) => entry.contains(fragment)),
          isTrue,
          reason: 'Expected debug log to contain "$fragment".',
        );
      }
      await shell.fetchDependencies();
      await shell.vendorDependencies(outputPath: '/workspace/demo/vendor');
      await shell.packProject(
        packageName: 'demo/app',
        outputPath: '/workspace/demo/dist/app.tar',
      );
      await shell.publishToRegistry(
        registryRoot: '/registry',
        packageName: 'demo/app',
        outputPath: '/workspace/demo/dist/app.tar',
      );

      for (final fragment in const <String>[
        'fetch packages: 2',
        'vendor root: /workspace/demo/vendor',
        'vendor metadata: /workspace/demo/vendor/spio-vendor.json',
        'deploy package: demo/app',
        'deploy archive: /workspace/demo/dist/app.tar',
      ]) {
        expect(
          shell.debugLog.any((entry) => entry.contains(fragment)),
          isTrue,
          reason: 'Expected debug log to contain "$fragment".',
        );
      }
    },
  );

  test(
    'shell runtime handles toolchain recovery actions without manager',
    () async {
      const initialDocument = DocumentState(
        documentId: 'src/main.styio',
        text: 'value = 1\n',
        revision: 0,
      );
      final shell = _createNoopShellRuntime(
        projectGraph: _projectGraphWithFiles(const <String>[
          'src/main.styio',
        ], withActiveCompiler: false),
        documentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: const <String, DocumentState>{
            'src/main.styio': initialDocument,
          },
        ),
        initialDocument: initialDocument,
      );
      addTearDown(shell.dispose);

      for (final action in const <ToolchainRecoveryAction>[
        ToolchainRecoveryAction(
          id: 'show-toolchain-logs',
          label: 'Show logs',
          description: 'Open logs',
        ),
        ToolchainRecoveryAction(
          id: 'select-existing-toolchain',
          label: 'Select existing',
          description: 'Select a local compiler',
        ),
        ToolchainRecoveryAction(
          id: 'install-managed-toolchain',
          label: 'Install',
          description: 'Install a managed compiler',
        ),
        ToolchainRecoveryAction(
          id: 'use-degraded-mode',
          label: 'Use degraded mode',
          description: 'Continue without the compiler',
        ),
        ToolchainRecoveryAction(
          id: 'fix-toolchain-precondition',
          label: 'Fix precondition',
          description: 'Create the expected directory',
        ),
        ToolchainRecoveryAction(
          id: 'retry-tool-use',
          label: 'Retry use',
          description: 'Retry tool use',
        ),
        ToolchainRecoveryAction(
          id: 'retry-tool-pin',
          label: 'Retry pin',
          description: 'Retry tool pin',
        ),
        ToolchainRecoveryAction(
          id: 'unknown-recovery',
          label: 'Unknown',
          description: 'Unknown action',
        ),
      ]) {
        await shell.handleToolchainRecoveryAction(action);
      }

      for (final fragment in const <String>[
        'Toolchain log view requested',
        'Toolchain selection route requested',
        'Toolchain install planning unavailable',
        'Toolchain degraded mode requested',
        'Toolchain precondition recovery',
        'Toolchain retry blocked',
        'Toolchain recovery action is not wired',
      ]) {
        expect(
          shell.debugLog.any((entry) => entry.contains(fragment)),
          isTrue,
          reason: 'Expected debug log to contain "$fragment".',
        );
      }
    },
  );
}

ShellRuntimeModel _createNoopShellRuntime({
  required ProjectGraphSnapshot projectGraph,
  required WorkspaceDocumentStore documentStore,
  required DocumentState initialDocument,
  ExecutionAdapter executionAdapter = const _NoopExecutionAdapter(),
  RuntimeEventAdapter runtimeEventAdapter = const _NoopRuntimeEventAdapter(),
  DependencySourceAdapter dependencySourceAdapter =
      const _NoopDependencySourceAdapter(),
  DeploymentAdapter deploymentAdapter = const _NoopDeploymentAdapter(),
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
    dependencySourceAdapter: dependencySourceAdapter,
    deploymentAdapter: deploymentAdapter,
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
    level: AdapterCapabilityLevel.available,
    detail: 'static CLI execution route',
  ),
  runtimeEvents: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.available,
    detail: 'static runtime event stream',
  ),
);

const _compilerSnapshot = CompilerHandshakeSnapshot(
  binaryPath: '/toolchains/styio/bin/styio',
  tool: 'styio',
  compilerVersion: '2026.6.19',
  channel: 'test',
  variant: 'fixture',
  capabilities: <String>['single_file_run'],
  supportedContractVersions: <String, List<int>>{},
  integrationPhase: 'fixture',
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

class _StaticRuntimeEventAdapter implements RuntimeEventAdapter {
  const _StaticRuntimeEventAdapter();

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => _capabilitySnapshot;

  @override
  Stream<RuntimeEventEnvelope> sessionEvents(String sessionId) {
    return Stream<RuntimeEventEnvelope>.fromIterable(<RuntimeEventEnvelope>[
      RuntimeEventEnvelope(
        schemaVersion: 1,
        sessionId: sessionId,
        sequence: 1,
        timestamp: DateTime.utc(2026, 6, 19),
        eventKind: 'compile.started',
        origin: 'styio.compile-plan',
        payload: const <String, Object?>{'intent': 'run'},
      ),
      RuntimeEventEnvelope(
        schemaVersion: 1,
        sessionId: sessionId,
        sequence: 2,
        timestamp: DateTime.utc(2026, 6, 19, 0, 0, 1),
        eventKind: 'run.finished',
        origin: 'styio.runtime',
        payload: const <String, Object?>{'success': true},
      ),
    ]);
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

class _PayloadDependencySourceAdapter implements DependencySourceAdapter {
  const _PayloadDependencySourceAdapter();

  @override
  Future<DependencySourceCommandResult> fetchDependencies({
    required ProjectGraphSnapshot projectGraph,
    bool locked = false,
    bool offline = false,
  }) async {
    return const DependencySourceCommandResult(
      command: 'fetch',
      status: DependencySourceCommandStatus.succeeded,
      statusMessage: 'fetched dependencies',
      stdout: '',
      stderr: '',
      payload: <String, dynamic>{'packages': 2},
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
      status: DependencySourceCommandStatus.succeeded,
      statusMessage: 'vendored dependencies',
      stdout: '',
      stderr: '',
      payload: <String, dynamic>{
        'packages': 2,
        'vendor_root': '/workspace/demo/vendor',
        'metadata_path': '/workspace/demo/vendor/spio-vendor.json',
      },
    );
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

class _PayloadDeploymentAdapter implements DeploymentAdapter {
  const _PayloadDeploymentAdapter();

  @override
  Future<DeploymentCommandResult> packProject({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) async {
    return DeploymentCommandResult(
      command: 'pack',
      status: DeploymentCommandStatus.succeeded,
      statusMessage: 'packed project',
      stdout: '',
      stderr: '',
      payload: <String, dynamic>{
        'package': packageName ?? 'demo/app',
        'archive_path': outputPath ?? '/workspace/demo/dist/app.tar',
      },
    );
  }

  @override
  Future<DeploymentCommandResult> preparePublish({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) async {
    return DeploymentCommandResult(
      command: 'publish',
      status: DeploymentCommandStatus.succeeded,
      statusMessage: 'prepared publish',
      stdout: '',
      stderr: '',
      payload: <String, dynamic>{
        'package': packageName ?? 'demo/app',
        'archive_path': outputPath ?? '/workspace/demo/dist/app.tar',
      },
    );
  }

  @override
  Future<DeploymentCommandResult> publishToRegistry({
    required ProjectGraphSnapshot projectGraph,
    required String registryRoot,
    String? packageName,
    String? outputPath,
  }) async {
    return DeploymentCommandResult(
      command: 'publish-registry',
      status: DeploymentCommandStatus.succeeded,
      statusMessage: 'published to registry',
      stdout: '',
      stderr: '',
      payload: <String, dynamic>{
        'package': packageName ?? 'demo/app',
        'archive_path': outputPath ?? '/workspace/demo/dist/app.tar',
      },
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

ProjectGraphSnapshot _projectGraphWithFiles(
  List<String> editorFiles, {
  bool withActiveCompiler = true,
}) {
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
    toolchain: withActiveCompiler
        ? const ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.environment,
            detail: 'Static CLI fixture is available for scratch runs.',
            channel: 'test',
            version: '2026.6.19',
          )
        : const ToolchainStatusSnapshot(
            source: ToolchainResolutionSource.unavailable,
            detail: 'No project toolchain pin is active in scratch mode.',
          ),
    lockState: ProjectLockState.missing,
    vendorState: ProjectVendorState.missing,
    activeCompiler: withActiveCompiler ? _compilerSnapshot : null,
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
