import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_coding_session_controller.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
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
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_launcher.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_protocol.dart';
import 'package:vityo_app/src/view_ide/debugger/debug_adapter_transport.dart';
import 'package:vityo_app/src/view_ide/editor/controller/editor_controller.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/editor/selection/selection_state.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_service_connector.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_language_service.dart';
import 'package:vityo_app/src/view_ide/language/service/simple_styio_language_service.dart';
import 'package:vityo_app/src/view_ide/module_host/module_registry.dart';
import 'package:vityo_app/src/view_ide/platform/native_module_loader.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/shell_runtime_model.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_controller.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_store.dart';

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
    var languageRefreshCount = 0;
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
      refreshActiveLanguageService: () async {
        languageRefreshCount += 1;
      },
    );
    addTearDown(shell.dispose);

    shell.editorController.insertText('value := 2');

    expect(
      shell.editorFileBindingSnapshot.state,
      DocumentResourceBindingState.boundDirty,
    );

    final saveApplied = await shell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(commandId: 'save'),
    );
    final saveResult = shell.agentSessionContext.commands.lastResult;

    expect(saveApplied, isTrue);
    expect(saveResult?.commandId, 'save');
    expect(saveResult?.applied, isTrue);
    expect(saveResult?.metadata['bindingState'], 'boundClean');
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
    expect(languageRefreshCount, 1);
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Language service refresh requested'),
      ),
      isTrue,
    );
  });

  test(
    'shell blocks agent disk-backed native tool commands while workspace is dirty',
    () async {
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: 'src/main.cc',
        title: 'Demo',
        notes: const <String>[],
      );
      const initialDocument = DocumentState(
        documentId: 'src/main.cc',
        text: 'int main(){return 0;}\n',
        revision: 0,
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: WorkspaceController(projectSnapshot: projectGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: const <String, DocumentState>{
            'src/main.cc': initialDocument,
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

      shell.editorController.insertText('// dirty\n');

      for (final commandId in <String>[
        'runBuild',
        'runStaticAnalysis',
        'runTests',
        'startDebugging',
      ]) {
        final applied = await shell.applyAgentIdeCommandSuggestion(
          AgentIdeCommandSuggestion(commandId: commandId),
        );
        final result = shell.agentSessionContext.commands.lastResult;

        expect(applied, isFalse);
        expect(result?.commandId, commandId);
        expect(result?.applied, isFalse);
        expect(result?.message, contains('save dirty workspace documents'));
        expect(result?.metadata['requiredCommand'], 'saveAll');
        expect(result?.metadata['dirtyDocumentIds'], contains('src/main.cc'));
      }

      final saveAllApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'saveAll'),
      );
      final saveAllResult = shell.agentSessionContext.commands.lastResult;

      expect(saveAllApplied, isTrue);
      expect(saveAllResult?.commandId, 'saveAll');
      expect(
        saveAllResult?.metadata['completedRequiredCommandFor'],
        'startDebugging',
      );
      expect(shell.dirtyDocumentPaths, isEmpty);

      shell.editorController.insertText('// dirty again\n');
      final directRequiredSaveAllApplied = await shell
          .applyAgentIdeCommandSuggestion(
            const AgentIdeCommandSuggestion(
              commandId: 'saveAll',
              prerequisiteForCommandId: 'runBuild',
            ),
          );
      final directRequiredSaveAllResult =
          shell.agentSessionContext.commands.lastResult;

      expect(directRequiredSaveAllApplied, isTrue);
      expect(
        directRequiredSaveAllResult?.metadata['completedRequiredCommandFor'],
        'runBuild',
      );
      expect(shell.dirtyDocumentPaths, isEmpty);
    },
  );

  test('shell run blocks at route snapshot before adapter execution', () async {
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/blocked-run',
      activeFilePath: 'src/main.styio',
      title: 'Blocked Run',
      notes: const <String>[],
    );
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'value := 1\n',
      revision: 0,
    );
    final adapter = _CountingExecutionAdapter();
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': initialDocument,
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
        initialDocument: initialDocument,
        languageService: const _NoopStyioLanguageService(),
      ),
      executionAdapter: adapter,
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          adapter,
      runtimeEventAdapter: const _NoopRuntimeEventAdapter(),
      dependencySourceAdapter: const _NoopDependencySourceAdapter(),
      deploymentAdapter: const _NoopDeploymentAdapter(),
      toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    await shell.executeCommand(AppCommandId.run);

    expect(adapter.callCount, 0);
    expect(shell.lastExecutionSession!.status, ExecutionSessionStatus.blocked);
    expect(
      shell.debugLog.any(
        (entry) => entry.contains('Run blocked by route snapshot'),
      ),
      isTrue,
    );
  });

  test('shell saves all active and inactive dirty documents', () async {
    final projectGraph = _multiFileProjectGraph();
    const mainDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'value := 1\n',
      revision: 0,
    );
    const libDocument = DocumentState(
      documentId: 'src/lib.styio',
      text: 'lib := 1\n',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': mainDocument,
        'src/lib.styio': libDocument,
      },
    );
    final workspaceController = WorkspaceController(
      projectSnapshot: projectGraph,
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: workspaceController,
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

    shell.editorController.selectCollapsed(0);
    shell.editorController.insertText('// dirty main\n');
    workspaceController.openFile('src/lib.styio');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    shell.editorController.selectCollapsed(0);
    shell.editorController.insertText('// dirty lib\n');

    final saveAllApplied = await shell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(commandId: 'saveAll'),
    );
    final commandResult = shell.agentSessionContext.commands.lastResult;
    final commandResults = shell.agentSessionContext.commands.recentResults;
    final persistedMain = await documentStore.loadDocument('src/main.styio');
    final persistedLib = await documentStore.loadDocument('src/lib.styio');

    expect(saveAllApplied, isTrue);
    expect(commandResult?.commandId, 'saveAll');
    expect(commandResult?.applied, isTrue);
    expect(commandResult?.completedAt, isNotNull);
    expect(commandResult?.toJson()['completedAt'], isA<String>());
    expect(commandResult?.metadata['savedCount'], 2);
    expect(commandResult?.metadata['skippedCount'], 0);
    expect(
      commandResult?.metadata['savedDocumentIds'],
      unorderedEquals(<String>['src/main.styio', 'src/lib.styio']),
    );
    expect(commandResults.length, 1);
    expect(commandResults.single.commandId, 'saveAll');
    expect(commandResults.single.completedAt, commandResult?.completedAt);
    expect(commandResults.single.metadata['savedCount'], 2);
    expect(shell.dirtyDocumentPaths, isEmpty);
    expect(persistedMain.text, startsWith('// dirty main\n'));
    expect(persistedLib.text, startsWith('// dirty lib\n'));

    await shell.executeCommand(AppCommandId.saveAll);

    expect(
      shell.debugLog.any((entry) => entry.contains('Save all skipped')),
      isTrue,
    );
  });

  test(
    'late workspace document load cannot replace current active file',
    () async {
      final projectGraph = _multiFileProjectGraph(
        editorFiles: const <String>[
          'src/main.styio',
          'src/lib.styio',
          'src/extra.styio',
        ],
      );
      const mainDocument = DocumentState(
        documentId: 'src/main.styio',
        text: 'main := 1\n',
        revision: 0,
      );
      final documentStore = _DeferredWorkspaceDocumentStore();
      final workspaceController = WorkspaceController(
        projectSnapshot: projectGraph,
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: workspaceController,
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

      workspaceController.openFile('src/lib.styio');
      workspaceController.openFile('src/extra.styio');
      await Future<void>.delayed(Duration.zero);

      documentStore.completeLoad(
        const DocumentState(
          documentId: 'src/extra.styio',
          text: 'extra := 1\n',
          revision: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(shell.editorController.document.documentId, 'src/extra.styio');
      expect(shell.editorFileBindingSnapshot.resourceId, 'src/extra.styio');

      documentStore.completeLoad(
        const DocumentState(
          documentId: 'src/lib.styio',
          text: 'lib := late\n',
          revision: 1,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(workspaceController.activeFilePath, 'src/extra.styio');
      expect(shell.editorController.document.documentId, 'src/extra.styio');
      expect(shell.editorController.document.text, 'extra := 1\n');
      expect(shell.editorFileBindingSnapshot.resourceId, 'src/extra.styio');

      workspaceController.openFile('src/lib.styio');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(shell.editorController.document.documentId, 'src/lib.styio');
      expect(shell.editorController.document.text, 'lib := late\n');
      expect(shell.editorFileBindingSnapshot.resourceId, 'src/lib.styio');
    },
  );

  test(
    'shell run command records the selected top-level run unit range',
    () async {
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: 'src/main.styio',
        title: 'Demo',
        activeCompiler: _singleFileCompiler,
        notes: const <String>[],
      );
      const text = '''
#first := () => {
  <| 1
}
#second := () => {
  <| 2
}
''';
      const initialDocument = DocumentState(
        documentId: 'src/main.styio',
        text: text,
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
          initialSelection: SelectionState.collapsed(text.indexOf('<| 2')),
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

      await shell.executeCommand(AppCommandId.run);

      final range = shell.lastExecutionSession?.unitRange;
      expect(range, isNotNull);
      final unitRange = range!;
      expect(unitRange.start, text.indexOf('#second'));
      expect(initialDocument.text.substring(unitRange.start, unitRange.end), '''
#second := () => {
  <| 2
}''');
      expect(
        shell.debugLog.any((entry) => entry.contains('Run unit topLevelBlock')),
        isTrue,
      );
    },
  );

  test(
    'shell run command routes execution diagnostics back to editor',
    () async {
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: 'src/main.styio',
        title: 'Demo',
        activeCompiler: _singleFileCompiler,
        notes: const <String>[],
      );
      const initialDocument = DocumentState(
        documentId: 'src/main.styio',
        text: '#main := () => {\n  <| 1\n}\n',
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
        executionAdapter: const _DiagnosticExecutionAdapter(),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            const _DiagnosticExecutionAdapter(),
        runtimeEventAdapter: const _NoopRuntimeEventAdapter(),
        dependencySourceAdapter: const _NoopDependencySourceAdapter(),
        deploymentAdapter: const _NoopDeploymentAdapter(),
        toolchainManagementAdapter: const _NoopToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      await shell.executeCommand(AppCommandId.run);

      expect(
        shell.editorController.analysis.diagnostics.any(
          (diagnostic) => diagnostic.code == 'execution.compile',
        ),
        isTrue,
      );
      await shell.executeCommand(AppCommandId.nextDiagnostic);

      expect(
        shell.editorController.selection.start,
        initialDocument.text.indexOf('<|'),
      );
      await shell.executeCommand(AppCommandId.previousDiagnostic);
      expect(
        shell.editorController.selection.start,
        initialDocument.text.indexOf('<|'),
      );
      expect(
        shell.debugLog.any((entry) => entry.contains('diagnostics: 1 issue')),
        isTrue,
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Next diagnostic selected'),
        ),
        isTrue,
      );
    },
  );

  test(
    'shell quick fix command applies the first editor code action',
    () async {
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: 'src/main.styio',
        title: 'Demo',
        notes: const <String>[],
      );
      const text = 'let stream\n';
      const initialDocument = DocumentState(
        documentId: 'src/main.styio',
        text: text,
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
          initialSelection: SelectionState.collapsed(
            text.indexOf('stream') + 2,
          ),
          languageService: const SimpleStyioLanguageService(),
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

      await shell.executeCommand(AppCommandId.applyQuickFix);

      expect(shell.editorController.document.text, 'let stream = value\n');
      expect(shell.dirtyDocumentPaths, contains('src/main.styio'));
      expect(
        shell.debugLog.any((entry) => entry.contains('Quick fix applied')),
        isTrue,
      );
    },
  );

  test(
    'shell go to definition command moves editor selection to definition',
    () async {
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: 'src/main.styio',
        title: 'Demo',
        notes: const <String>[],
      );
      const text = 'value = 1\nvalue\n';
      const initialDocument = DocumentState(
        documentId: 'src/main.styio',
        text: text,
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
          initialSelection: SelectionState.collapsed(text.lastIndexOf('value')),
          languageService: const SimpleStyioLanguageService(),
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

      await shell.executeCommand(AppCommandId.goToDefinition);

      expect(shell.editorController.selection.start, 0);
      expect(shell.editorController.selection.end, 'value'.length);
      expect(
        shell.debugLog.any((entry) => entry.contains('Definition selected')),
        isTrue,
      );
    },
  );

  test('shell reference commands move through resolved references', () async {
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/demo',
      activeFilePath: 'src/main.styio',
      title: 'Demo',
      notes: const <String>[],
    );
    const text = 'value = value\nvalue -> @stdout\n';
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: text,
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
        initialSelection: SelectionState.collapsed(text.indexOf('= value') + 3),
        languageService: const SimpleStyioLanguageService(),
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

    await shell.executeCommand(AppCommandId.nextReference);
    expect(shell.editorController.selection.start, text.lastIndexOf('value'));

    await shell.executeCommand(AppCommandId.previousReference);
    expect(shell.editorController.selection.start, text.indexOf('= value') + 2);

    expect(
      shell.debugLog.any((entry) => entry.contains('Next reference selected')),
      isTrue,
    );
  });

  test(
    'shell refactor commands apply safe delete and inline variable',
    () async {
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: 'src/main.styio',
        title: 'Demo',
        notes: const <String>[],
      );
      const safeDeleteText = 'used = 1\nunused = 2\nused -> @stdout\n';
      const safeDeleteDocument = DocumentState(
        documentId: 'src/main.styio',
        text: safeDeleteText,
        revision: 0,
      );
      final documentStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': safeDeleteDocument,
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
          initialDocument: safeDeleteDocument,
          initialSelection: SelectionState.collapsed(
            safeDeleteText.indexOf('unused'),
          ),
          languageService: const SimpleStyioLanguageService(),
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

      await shell.executeCommand(AppCommandId.safeDelete);

      expect(
        shell.editorController.document.text,
        'used = 1\nused -> @stdout\n',
      );
      expect(shell.dirtyDocumentPaths, contains('src/main.styio'));
      expect(
        shell.debugLog.any((entry) => entry.contains('Safe delete applied')),
        isTrue,
      );

      const inlineText = 'seed = 40 + 2\nvalue = seed\nseed -> @stdout\n';
      shell.editorController.loadDocument(
        const DocumentState(
          documentId: 'src/main.styio',
          text: inlineText,
          revision: 0,
        ),
      );
      shell.editorController.selectCollapsed(inlineText.indexOf('seed'));

      await shell.executeCommand(AppCommandId.inlineVariable);

      expect(
        shell.editorController.document.text,
        'value = 40 + 2\n40 + 2 -> @stdout\n',
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Inline variable applied'),
        ),
        isTrue,
      );
    },
  );

  test('shell runtime applies parameterized rename symbol refactor', () async {
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/demo',
      activeFilePath: 'src/main.styio',
      title: 'Demo',
      notes: const <String>[],
    );
    const text = '''
@resource : f64|..2| := {
  value = 10
  value -> @resource
}
''';
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: text,
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
        initialSelection: SelectionState.collapsed(text.lastIndexOf('value')),
        languageService: const SimpleStyioLanguageService(),
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
      await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'renameSymbol'),
      ),
      isFalse,
    );
    expect(
      await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'unsupportedCommand'),
      ),
      isFalse,
    );
    expect(
      await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(
          commandId: 'renameSymbol',
          input: 'price',
          reason: 'Use safe rename.',
        ),
      ),
      isTrue,
    );

    expect(shell.editorController.document.text, contains('price = 10'));
    expect(
      shell.editorController.document.text,
      contains('price -> @resource'),
    );
    expect(shell.dirtyDocumentPaths, contains('src/main.styio'));
    expect(
      shell.debugLog.any((entry) => entry.contains('Rename symbol applied')),
      isTrue,
    );
  });

  test(
    'shell runtime applies no-input agent refactor command suggestions',
    () async {
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: 'src/main.styio',
        title: 'Demo',
        notes: const <String>[],
      );
      const safeDeleteText = 'used = 1\nunused = 2\nused -> @stdout\n';
      const initialDocument = DocumentState(
        documentId: 'src/main.styio',
        text: safeDeleteText,
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
          initialSelection: SelectionState.collapsed(
            safeDeleteText.indexOf('unused'),
          ),
          languageService: const SimpleStyioLanguageService(),
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
        await shell.applyAgentIdeCommandSuggestion(
          const AgentIdeCommandSuggestion(commandId: 'safeDelete'),
        ),
        isTrue,
      );
      expect(
        shell.editorController.document.text,
        'used = 1\nused -> @stdout\n',
      );

      const inlineText = 'seed = 40 + 2\nvalue = seed\nseed -> @stdout\n';
      shell.editorController.loadDocument(
        const DocumentState(
          documentId: 'src/main.styio',
          text: inlineText,
          revision: 0,
        ),
      );
      shell.editorController.selectCollapsed(inlineText.indexOf('seed'));

      expect(
        await shell.applyAgentIdeCommandSuggestion(
          const AgentIdeCommandSuggestion(commandId: 'inlineVariable'),
        ),
        isTrue,
      );
      expect(
        shell.editorController.document.text,
        'value = 40 + 2\n40 + 2 -> @stdout\n',
      );
    },
  );

  test('shell runtime applies agent quick fix command suggestion', () async {
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/demo',
      activeFilePath: 'src/main.styio',
      title: 'Demo',
      notes: const <String>[],
    );
    const text = 'let stream\n';
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: text,
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
        initialSelection: SelectionState.collapsed(text.indexOf('stream') + 2),
        languageService: const SimpleStyioLanguageService(),
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
      await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'applyQuickFix'),
      ),
      isTrue,
    );

    expect(shell.editorController.document.text, 'let stream = value\n');
    expect(shell.dirtyDocumentPaths, contains('src/main.styio'));
    expect(
      shell.debugLog.any((entry) => entry.contains('applyQuickFix applied')),
      isTrue,
    );
  });

  test('shell runtime applies agent navigation command suggestions', () async {
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/demo',
      activeFilePath: 'src/main.styio',
      title: 'Demo',
      notes: const <String>[],
    );
    const text = 'value = value\nvalue -> @stdout\n';
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: text,
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
        initialSelection: SelectionState.collapsed(text.lastIndexOf('value')),
        languageService: const SimpleStyioLanguageService(),
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
      await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'goToDefinition'),
      ),
      isTrue,
    );
    expect(shell.editorController.selection.start, 0);

    expect(
      await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'nextReference'),
      ),
      isTrue,
    );
    expect(shell.editorController.selection.start, text.indexOf('= value') + 2);

    expect(
      await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'previousReference'),
      ),
      isTrue,
    );
    expect(shell.editorController.selection.start, 0);
  });

  test(
    'shell runtime applies agent diagnostic navigation suggestions',
    () async {
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: 'src/main.styio',
        title: 'Demo',
        notes: const <String>[],
      );
      const text = 'first\nsecond\n';
      const initialDocument = DocumentState(
        documentId: 'src/main.styio',
        text: text,
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
      shell.editorController.applyExternalDiagnostics(const <Diagnostic>[
        Diagnostic(
          severity: DiagnosticSeverity.warning,
          code: 'first-warning',
          message: 'First warning.',
          range: SourceRange(start: 0, end: 5),
        ),
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'second-error',
          message: 'Second error.',
          range: SourceRange(start: 6, end: 12),
        ),
      ]);

      expect(
        await shell.applyAgentIdeCommandSuggestion(
          const AgentIdeCommandSuggestion(commandId: 'nextDiagnostic'),
        ),
        isTrue,
      );
      expect(shell.editorController.selection.start, 0);

      expect(
        await shell.applyAgentIdeCommandSuggestion(
          const AgentIdeCommandSuggestion(commandId: 'nextDiagnostic'),
        ),
        isTrue,
      );
      expect(shell.editorController.selection.start, 6);

      expect(
        await shell.applyAgentIdeCommandSuggestion(
          const AgentIdeCommandSuggestion(commandId: 'previousDiagnostic'),
        ),
        isTrue,
      );
      expect(shell.editorController.selection.start, 0);
    },
  );

  test('shell agent context exposes live language facts at selection', () {
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/demo',
      activeFilePath: 'src/main.styio',
      title: 'Demo',
      notes: const <String>[],
    );
    const text = 'value = 1\nvalue\n';
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: text,
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
        initialSelection: SelectionState.collapsed(text.lastIndexOf('value')),
        languageService: const SimpleStyioLanguageService(),
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

    final languageContext = shell.agentSessionContext.language;

    expect(languageContext.hasHover, isTrue);
    expect(languageContext.focusToken?.lexeme, 'value');
    expect(languageContext.focusToken?.kind, 'identifier');
    expect(languageContext.definition?.name, 'value');
    expect(languageContext.resolvedElement?.name, 'value');
    expect(languageContext.resolvedReference?.name, 'value');
    expect(languageContext.resolvedReference?.target.name, 'value');
    expect(languageContext.referenceCount, greaterThanOrEqualTo(2));
    expect(languageContext.completionCount, greaterThan(0));
    expect(languageContext.codeActionCount, greaterThanOrEqualTo(0));
    expect(languageContext.semanticSpanCount, greaterThan(0));
    expect(
      languageContext.semanticSpans.map((span) => span.kind),
      contains('variable'),
    );
    expect(languageContext.documentSymbolCount, greaterThan(0));
    expect(
      languageContext.documentSymbols.map((symbol) => symbol.name),
      contains('value'),
    );
  });

  test('shell agent context exposes parameter info at selection', () {
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/demo',
      activeFilePath: 'src/main.styio',
      title: 'Demo',
      notes: const <String>[],
    );
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'value',
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
        initialSelection: const SelectionState(baseOffset: 0, extentOffset: 5),
        languageService: const _NoopStyioLanguageService(
          parameterInfo: ParameterInfoPayload(
            callableName: 'blend',
            signature: 'fn blend(left: f64, right: f64 = 0.0)',
            parameters: <ParameterInfoParameter>[
              ParameterInfoParameter(
                name: 'left',
                range: SourceRange(start: 0, end: 9),
                type: 'f64',
              ),
              ParameterInfoParameter(
                name: 'right',
                range: SourceRange(start: 11, end: 28),
                type: 'f64',
                defaultValue: '0.0',
              ),
            ],
            activeParameterIndex: 1,
            invocationRange: SourceRange(start: 30, end: 47),
            callableRange: SourceRange(start: 30, end: 35),
          ),
          analysisInlayHints: <InlayHint>[
            InlayHint(
              label: 'right:',
              kind: InlayHintKind.parameter,
              position: 40,
              range: SourceRange(start: 36, end: 45),
            ),
          ],
          analysisSemanticBlocks: <SemanticBlockRange>[
            SemanticBlockRange(
              label: 'call expression',
              range: SourceRange(start: 30, end: 47),
            ),
          ],
          analysisDiagnostics: <Diagnostic>[
            Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'focused-warning',
              message: 'Selection diagnostic.',
              range: SourceRange(start: 0, end: 5),
            ),
          ],
          safeDeletePlan: SafeDeletePlan(
            target: DocumentSymbol(
              name: 'unused',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 5),
              declarationRange: SourceRange(start: 0, end: 5),
            ),
            references: <ReferenceSpan>[],
            edits: <FormattingEdit>[
              FormattingEdit(range: SourceRange(start: 0, end: 5), newText: ''),
            ],
          ),
          inlineVariablePlan: InlineVariablePlan(
            target: DocumentSymbol(
              name: 'value',
              kind: SymbolKind.variable,
              nameRange: SourceRange(start: 0, end: 5),
              declarationRange: SourceRange(start: 0, end: 5),
            ),
            initializerRange: SourceRange(start: 0, end: 5),
            initializerText: '1',
            references: <ReferenceSpan>[],
            edits: <FormattingEdit>[
              FormattingEdit(
                range: SourceRange(start: 0, end: 5),
                newText: '1',
              ),
            ],
          ),
          surroundTemplates: <SurroundTemplate>[
            SurroundTemplate(
              id: 'if-block',
              label: 'if block',
              openingLine: 'if condition {',
              closingLine: '}',
            ),
          ],
        ),
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

    final parameterInfo = shell.agentSessionContext.language.parameterInfo;
    final selection = shell.agentSessionContext.selection;

    expect(parameterInfo?.callableName, 'blend');
    expect(selection.coordinateBase, 'zero-based');
    expect(selection.startLine, 0);
    expect(selection.startColumn, 0);
    expect(selection.endLine, 0);
    expect(selection.endColumn, 5);
    expect(parameterInfo?.activeParameter?.name, 'right');
    expect(parameterInfo?.parameterCount, 2);
    expect(parameterInfo?.parametersTruncated, isFalse);
    expect(shell.agentSessionContext.language.inlayHintCount, 1);
    expect(
      shell.agentSessionContext.language.inlayHints.single.label,
      'right:',
    );
    expect(shell.agentSessionContext.language.semanticBlockCount, 1);
    expect(
      shell.agentSessionContext.language.semanticBlocks.single.label,
      'call expression',
    );
    expect(shell.agentSessionContext.language.focusedDiagnosticCount, 1);
    expect(
      shell.agentSessionContext.language.focusedDiagnostics.single.code,
      'focused-warning',
    );
    expect(shell.agentSessionContext.language.refactorPreviewCount, 2);
    expect(
      shell.agentSessionContext.language.refactorPreviews.first.kind,
      'safeDelete',
    );
    expect(
      shell.agentSessionContext.language.refactorPreviews.last.kind,
      'inlineVariable',
    );
    expect(shell.agentSessionContext.language.surroundTemplateCount, 1);
    expect(
      shell.agentSessionContext.language.surroundTemplates.single.id,
      'if-block',
    );
  });

  test('shell applies refreshLanguageService command paths', () async {
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/demo',
      activeFilePath: 'src/main.styio',
      title: 'Demo',
      notes: const <String>[],
    );
    const initialDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'value = 1\n',
      revision: 0,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': initialDocument,
      },
    );
    var refreshCount = 0;
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
      refreshActiveLanguageService: () async {
        refreshCount += 1;
      },
    );
    addTearDown(shell.dispose);

    final applied = await shell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(commandId: 'refreshLanguageService'),
    );

    final lastResult = shell.agentSessionContext.commands.lastResult;
    expect(applied, isTrue);
    expect(refreshCount, 1);
    expect(lastResult?.commandId, 'refreshLanguageService');
    expect(lastResult?.applied, isTrue);
    expect(lastResult?.metadata['languageServiceSeverity'], 'unavailable');
    expect(
      lastResult?.metadata['languageServicePrimaryCapabilityStates'],
      isA<Map<String, String>>(),
    );

    await shell.executeCommand(AppCommandId.refreshLanguageService);

    expect(refreshCount, 2);
  });

  test(
    'shell exposes active and cached document samples to agent context',
    () async {
      final projectGraph =
          ProjectGraphSnapshot.scratch(
            workspaceRoot: '/workspace/demo',
            activeFilePath: 'src/main.styio',
            title: 'Demo',
            notes: const <String>[],
          ).copyWith(
            editorFiles: const <String>['src/main.styio', 'src/lib.styio'],
          );
      const mainDocument = DocumentState(
        documentId: 'src/main.styio',
        text: 'main := 1\n',
        revision: 1,
      );
      const libDocument = DocumentState(
        documentId: 'src/lib.styio',
        text: 'lib := 2\n',
        revision: 2,
      );
      final documentStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': mainDocument,
          'src/lib.styio': libDocument,
        },
      );
      final workspaceController = WorkspaceController(
        projectSnapshot: projectGraph,
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: workspaceController,
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

      workspaceController.openFile('src/lib.styio');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final workspaceContext = shell.agentSessionContext.workspace;

      expect(workspaceContext.documentSampleCount, 2);
      expect(workspaceContext.documentSamplesTruncated, isFalse);
      expect(
        workspaceContext.documentSamples.first.documentId,
        'src/lib.styio',
      );
      expect(workspaceContext.documentSamples.first.active, isTrue);
      expect(workspaceContext.documentSamples.first.text, 'lib := 2\n');
      expect(
        workspaceContext.documentSamples.last.documentId,
        'src/main.styio',
      );
      expect(workspaceContext.documentSamples.last.active, isFalse);
      expect(workspaceContext.documentSamples.last.open, isTrue);
      expect(workspaceContext.documentSamples.last.text, 'main := 1\n');
    },
  );

  test('shell applies agent openWorkspaceFile command suggestion', () async {
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/demo',
      activeFilePath: 'src/main.styio',
      title: 'Demo',
      notes: const <String>[],
    ).copyWith(editorFiles: const <String>['src/main.styio', 'src/lib.styio']);
    const mainDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'main := 1\n',
      revision: 1,
    );
    const libDocument = DocumentState(
      documentId: 'src/lib.styio',
      text: 'lib := 2\n',
      revision: 2,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': mainDocument,
        'src/lib.styio': libDocument,
      },
    );
    final workspaceController = WorkspaceController(
      projectSnapshot: projectGraph,
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: workspaceController,
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

    final applied = await shell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(
        commandId: 'openWorkspaceFile',
        input: 'src/lib.styio',
      ),
    );
    final workspaceContext = shell.agentSessionContext.workspace;

    expect(applied, isTrue);
    expect(workspaceController.activeFilePath, 'src/lib.styio');
    expect(shell.editorController.document.text, 'lib := 2\n');
    expect(workspaceContext.documentSamples.first.documentId, 'src/lib.styio');
    expect(workspaceContext.documentSamples.first.active, isTrue);
    expect(workspaceContext.documentSamples.last.documentId, 'src/main.styio');
  });

  test('shell applies agent searchWorkspace command suggestion', () async {
    final projectGraph =
        ProjectGraphSnapshot.scratch(
          workspaceRoot: '/workspace/demo',
          activeFilePath: 'src/main.styio',
          title: 'Demo',
          notes: const <String>[],
        ).copyWith(
          editorFiles: const <String>[
            'src/main.styio',
            'src/lib.styio',
            'src/extra.styio',
          ],
        );
    const mainDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'needle := 1\n',
      revision: 1,
    );
    const libDocument = DocumentState(
      documentId: 'src/lib.styio',
      text: 'lib := needle\n',
      revision: 2,
    );
    const extraDocument = DocumentState(
      documentId: 'src/extra.styio',
      text: 'other := 3\n',
      revision: 3,
    );
    final documentStore = InMemoryWorkspaceDocumentStore(
      seededDocuments: const <String, DocumentState>{
        'src/main.styio': mainDocument,
        'src/lib.styio': libDocument,
        'src/extra.styio': extraDocument,
      },
    );
    final workspaceController = WorkspaceController(
      projectSnapshot: projectGraph,
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: workspaceController,
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

    final applied = await shell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(
        commandId: 'searchWorkspace',
        input: 'needle',
      ),
    );
    final lastSearch = shell.agentSessionContext.workspace.lastSearch;
    final lastCommandResult = shell.agentSessionContext.commands.lastResult;

    expect(applied, isTrue);
    expect(lastCommandResult?.commandId, 'searchWorkspace');
    expect(lastCommandResult?.applied, isTrue);
    expect(lastCommandResult?.input, 'needle');
    expect(lastSearch?.query, 'needle');
    expect(lastSearch?.scannedDocumentCount, 3);
    expect(lastSearch?.matchCount, 2);
    expect(lastSearch?.matches.map((match) => match.documentId), <String>[
      'src/main.styio',
      'src/lib.styio',
    ]);
  });

  test(
    'shell records blocked native tool commands without toolchain manager',
    () async {
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: '/workspace/demo',
        activeFilePath: 'src/main.cc',
        title: 'Demo',
        notes: const <String>[],
      );
      const initialDocument = DocumentState(
        documentId: 'src/main.cc',
        text: 'int main(){return 0;}\n',
        revision: 0,
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: WorkspaceController(projectSnapshot: projectGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: const <String, DocumentState>{
            'src/main.cc': initialDocument,
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

      final applied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'formatActiveDocument'),
      );
      final lastCommandResult = shell.agentSessionContext.commands.lastResult;

      expect(applied, isFalse);
      expect(lastCommandResult?.commandId, 'formatActiveDocument');
      expect(lastCommandResult?.applied, isFalse);
      expect(lastCommandResult?.message, contains('no toolchain manager'));
      expect(
        shell.lastNativeToolResult?.command,
        AppCommandId.formatActiveDocument,
      );
      expect(shell.nativeToolResults, hasLength(1));
      expect(
        shell.debugLog.any((entry) => entry.contains('no toolchain manager')),
        isTrue,
      );

      await shell.executeCommand(AppCommandId.runBuild);
      final directCommandResult = shell.agentSessionContext.commands.lastResult;

      expect(directCommandResult?.commandId, 'runBuild');
      expect(directCommandResult?.applied, isFalse);
      expect(directCommandResult?.message, contains('no toolchain manager'));
      expect(shell.lastNativeToolResult?.command, AppCommandId.runBuild);
      expect(
        shell.nativeToolResults.map((result) => result.command),
        <AppCommandId>[
          AppCommandId.runBuild,
          AppCommandId.formatActiveDocument,
        ],
      );
      final breakpointApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'toggleBreakpoint'),
      );
      final breakpointResult = shell.agentSessionContext.commands.lastResult;
      expect(breakpointApplied, isTrue);
      expect(breakpointResult?.commandId, 'toggleBreakpoint');
      expect(breakpointResult?.applied, isTrue);
      expect(breakpointResult?.metadata['debugStatus'], 'idle');
      expect(shell.debugBreakpoints, hasLength(1));
      final startApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'startDebugging'),
      );
      final startResult = shell.agentSessionContext.commands.lastResult;
      expect(startApplied, isFalse);
      expect(startResult?.commandId, 'startDebugging');
      expect(startResult?.applied, isFalse);
      expect(startResult?.message, contains('no toolchain manager'));
      expect(startResult?.metadata['debugStatus'], 'blocked');
      expect(shell.debugSession.status, DebugSessionStatus.blocked);
      expect(shell.debugSession.message, contains('no toolchain manager'));
      final debugJson =
          shell.agentSessionContext.toJson()['debug']! as Map<String, Object?>;
      final breakpointsJson = debugJson['breakpoints']! as List<Object?>;
      expect(debugJson['status'], 'blocked');
      expect(debugJson['breakpointCount'], 1);
      expect(
        (breakpointsJson.single! as Map<String, Object?>)['filePath'],
        'src/main.cc',
      );
    },
  );

  test(
    'shell applies agent format command through toolchain manager',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_shell_native_tool_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final formatter = File('${tempRoot.path}/fake-clang-format.sh');
      await formatter.writeAsString('''
#!/bin/sh
cat >/dev/null
printf 'int main() { return 0; }\\n'
''');
      await Process.run('chmod', <String>['+x', formatter.path]);
      final configurationStore = await _createShellTestConfigurationStore(
        tempRoot,
      );
      final platformManagers = await createDetectedPlatformManagerBundle();
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );
      final catalog = ToolchainCatalog()
        ..register(
          ToolchainDescriptor(
            id: 'fake-clang-format',
            kind: ToolchainKind.formatter,
            displayName: 'Fake clang-format',
            executablePath: formatter.path,
            metadata: const <String, Object?>{'toolFamily': 'clang-format'},
          ),
          activate: true,
        );
      await toolchainStore.saveCatalog(
        catalog,
        targetId: platformManagers.context.targetId,
      );
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: tempRoot.path,
        activeFilePath: 'src/main.cc',
        title: 'Demo',
        notes: const <String>[],
      );
      const initialDocument = DocumentState(
        documentId: 'src/main.cc',
        text: 'int main(){return 0;}\n',
        revision: 0,
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: WorkspaceController(projectSnapshot: projectGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: const <String, DocumentState>{
            'src/main.cc': initialDocument,
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
        toolchainManager: ToolchainManager(
          configurationStore: toolchainStore,
          platformManagers: platformManagers,
        ),
      );
      addTearDown(shell.dispose);

      final applied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'formatActiveDocument'),
      );
      final lastCommandResult = shell.agentSessionContext.commands.lastResult;

      expect(applied, isTrue);
      expect(
        shell.editorController.document.text,
        'int main() { return 0; }\n',
      );
      expect(shell.dirtyDocumentPaths, contains('src/main.cc'));
      expect(lastCommandResult?.commandId, 'formatActiveDocument');
      expect(lastCommandResult?.applied, isTrue);
      expect(lastCommandResult?.message, 'Format Active Document completed.');
      final formatResult =
          lastCommandResult?.metadata['formatResult']! as Map<String, Object?>;
      expect(formatResult['runner'], 'clang-format');
      expect(formatResult['status'], 'passed');
      expect(formatResult['changed'], isTrue);
      expect(formatResult['outputLength'], 'int main() { return 0; }\n'.length);
    },
  );

  test(
    'shell start debugging sends DAP launch plan through injected launcher',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_shell_dap_launch_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await _createShellTestConfigurationStore(
        tempRoot,
      );
      final platformManagers = await createDetectedPlatformManagerBundle();
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );
      final catalog = ToolchainCatalog()
        ..register(
          const ToolchainDescriptor(
            id: 'fake-lldb',
            kind: ToolchainKind.debugger,
            displayName: 'Fake LLDB',
            executablePath: '/usr/bin/lldb-dap',
            metadata: <String, Object?>{
              'toolFamily': 'lldb',
              'adapterProtocol': 'dap',
              'programPath': 'build/demo',
            },
          ),
          activate: true,
        );
      await toolchainStore.saveCatalog(
        catalog,
        targetId: platformManagers.context.targetId,
      );
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: tempRoot.path,
        activeFilePath: 'src/main.cc',
        title: 'Demo',
        notes: const <String>[],
      );
      const initialDocument = DocumentState(
        documentId: 'src/main.cc',
        text: 'int main(){return 0;}\n',
        revision: 0,
      );
      late _FakeDapByteTransport fakeTransport;
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: WorkspaceController(projectSnapshot: projectGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: const <String, DocumentState>{
            'src/main.cc': initialDocument,
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
        toolchainManager: ToolchainManager(
          configurationStore: toolchainStore,
          platformManagers: platformManagers,
        ),
        debugAdapterLauncher: DapDebugAdapterLauncher(
          transportFactory: (launch) async {
            fakeTransport = _FakeDapByteTransport();
            return fakeTransport;
          },
        ),
      );
      addTearDown(shell.dispose);

      final startApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'startDebugging'),
      );
      final startResult = shell.agentSessionContext.commands.lastResult;
      expect(startApplied, isTrue);
      expect(startResult?.commandId, 'startDebugging');
      expect(startResult?.applied, isTrue);
      expect(startResult?.metadata['debugStatus'], 'launching');
      final debugJson =
          shell.agentSessionContext.toJson()['debug']! as Map<String, Object?>;

      expect(shell.debugSession.status, DebugSessionStatus.launching);
      expect(shell.debugSession.adapterSessionStatus, 'launching');
      expect(shell.debugSession.adapterPendingRequestCount, 3);
      expect(fakeTransport.sentBytes, hasLength(3));
      expect(debugJson['status'], 'launching');
      expect(debugJson['adapterSessionStatus'], 'launching');
      expect(debugJson['adapterPendingRequestCount'], 3);

      const codec = DapContentFrameCodec();
      fakeTransport.addInbound(
        codec.encode(const <String, Object?>{
          'type': 'event',
          'event': 'stopped',
          'body': <String, Object?>{'reason': 'breakpoint', 'threadId': 1},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final stackTraceRequest = codec
          .decodeFirst(fakeTransport.sentBytes.last)!
          .message;
      expect(stackTraceRequest['command'], 'stackTrace');
      expect(
        (stackTraceRequest['arguments']! as Map<String, Object?>)['threadId'],
        1,
      );
      fakeTransport.addInbound(
        codec.encode(<String, Object?>{
          'type': 'response',
          'request_seq': stackTraceRequest['seq'],
          'command': 'stackTrace',
          'success': true,
          'body': <String, Object?>{
            'stackFrames': <Object?>[
              <String, Object?>{
                'id': 7,
                'name': 'main',
                'source': <String, Object?>{'path': 'src/main.cc'},
                'line': 12,
                'column': 3,
              },
              <String, Object?>{
                'id': 8,
                'name': 'worker',
                'source': <String, Object?>{'path': 'src/worker.cc'},
                'line': 21,
                'column': 1,
              },
            ],
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final scopesRequest = codec
          .decodeFirst(fakeTransport.sentBytes.last)!
          .message;
      expect(scopesRequest['command'], 'scopes');
      expect(
        (scopesRequest['arguments']! as Map<String, Object?>)['frameId'],
        7,
      );
      fakeTransport.addInbound(
        codec.encode(<String, Object?>{
          'type': 'response',
          'request_seq': scopesRequest['seq'],
          'command': 'scopes',
          'success': true,
          'body': <String, Object?>{
            'scopes': <Object?>[
              <String, Object?>{'name': 'Locals', 'variablesReference': 101},
            ],
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final variablesRequest = codec
          .decodeFirst(fakeTransport.sentBytes.last)!
          .message;
      expect(variablesRequest['command'], 'variables');
      expect(
        (variablesRequest['arguments']!
            as Map<String, Object?>)['variablesReference'],
        101,
      );
      fakeTransport.addInbound(
        codec.encode(<String, Object?>{
          'type': 'response',
          'request_seq': variablesRequest['seq'],
          'command': 'variables',
          'success': true,
          'body': <String, Object?>{
            'variables': <Object?>[
              <String, Object?>{'name': 'argc', 'value': '1', 'type': 'int'},
            ],
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final refreshedDebugJson =
          shell.agentSessionContext.toJson()['debug']! as Map<String, Object?>;
      final stackFrames = refreshedDebugJson['stackFrames']! as List<Object?>;
      final variables = refreshedDebugJson['variables']! as List<Object?>;
      expect(shell.debugSession.status, DebugSessionStatus.paused);
      expect(shell.debugSession.adapterSessionStatus, 'paused');
      expect(shell.debugSession.adapterEventCount, 1);
      expect(shell.debugSession.stackFrames.first.name, 'main');
      expect(shell.debugSession.stackFrames.last.name, 'worker');
      expect(shell.debugSession.variables.single.name, 'argc');
      expect(refreshedDebugJson['status'], 'paused');
      expect(refreshedDebugJson['adapterSessionStatus'], 'paused');
      expect(refreshedDebugJson['adapterEventCount'], 1);
      expect((stackFrames.first! as Map<String, Object?>)['name'], 'main');
      expect((variables.single! as Map<String, Object?>)['name'], 'argc');

      final selectFrameApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(
          commandId: 'selectDebugStackFrame',
          input: '8',
          reason: 'Inspect the worker frame locals.',
        ),
      );
      final selectFrameResult = shell.agentSessionContext.commands.lastResult;
      expect(selectFrameApplied, isTrue);
      expect(selectFrameResult?.commandId, 'selectDebugStackFrame');
      expect(selectFrameResult?.applied, isTrue);
      expect(selectFrameResult?.metadata['frameId'], '8');
      expect(shell.debugSession.variables, isEmpty);
      final selectedScopesRequest = codec
          .decodeFirst(fakeTransport.sentBytes.last)!
          .message;
      expect(selectedScopesRequest['command'], 'scopes');
      expect(
        (selectedScopesRequest['arguments']!
            as Map<String, Object?>)['frameId'],
        8,
      );
      fakeTransport.addInbound(
        codec.encode(<String, Object?>{
          'type': 'response',
          'request_seq': selectedScopesRequest['seq'],
          'command': 'scopes',
          'success': true,
          'body': <String, Object?>{
            'scopes': <Object?>[
              <String, Object?>{'name': 'Locals', 'variablesReference': 202},
            ],
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final selectedVariablesRequest = codec
          .decodeFirst(fakeTransport.sentBytes.last)!
          .message;
      expect(selectedVariablesRequest['command'], 'variables');
      expect(
        (selectedVariablesRequest['arguments']!
            as Map<String, Object?>)['variablesReference'],
        202,
      );
      fakeTransport.addInbound(
        codec.encode(<String, Object?>{
          'type': 'response',
          'request_seq': selectedVariablesRequest['seq'],
          'command': 'variables',
          'success': true,
          'body': <String, Object?>{
            'variables': <Object?>[
              <String, Object?>{'name': 'local', 'value': '42', 'type': 'int'},
            ],
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(shell.debugSession.variables.single.name, 'local');

      final continueApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'continueDebugging'),
      );
      final continueResult = shell.agentSessionContext.commands.lastResult;
      expect(continueApplied, isTrue);
      expect(continueResult?.commandId, 'continueDebugging');
      expect(continueResult?.applied, isTrue);
      expect(continueResult?.metadata['debugStatus'], 'running');
      expect(shell.debugSession.status, DebugSessionStatus.running);
      expect(shell.debugSession.adapterSessionStatus, 'running');
      expect(
        codec.decodeFirst(fakeTransport.sentBytes.last)?.message['command'],
        'continue',
      );

      fakeTransport.addInbound(
        codec.encode(const <String, Object?>{
          'type': 'event',
          'event': 'continued',
          'body': <String, Object?>{'threadId': 1},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(shell.debugSession.stackFrames, isEmpty);
      expect(shell.debugSession.variables, isEmpty);

      fakeTransport.addInbound(
        codec.encode(const <String, Object?>{
          'type': 'event',
          'event': 'stopped',
          'body': <String, Object?>{'reason': 'step', 'threadId': 1},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(shell.debugSession.status, DebugSessionStatus.paused);
      final stepApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'stepOver'),
      );
      final stepResult = shell.agentSessionContext.commands.lastResult;
      expect(stepApplied, isTrue);
      expect(stepResult?.commandId, 'stepOver');
      expect(stepResult?.applied, isTrue);
      expect(stepResult?.metadata['debugStatus'], 'running');
      expect(shell.debugSession.status, DebugSessionStatus.running);
      expect(shell.debugSession.adapterSessionStatus, 'running');
      expect(
        codec.decodeFirst(fakeTransport.sentBytes.last)?.message['command'],
        'next',
      );

      final stopApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'stopDebugging'),
      );
      final stopResult = shell.agentSessionContext.commands.lastResult;
      expect(stopApplied, isTrue);
      expect(stopResult?.commandId, 'stopDebugging');
      expect(stopResult?.applied, isTrue);
      expect(stopResult?.metadata['debugStatus'], 'stopped');
      expect(shell.debugSession.status, DebugSessionStatus.stopped);
      expect(
        codec.decodeFirst(fakeTransport.sentBytes.last)?.message['command'],
        'disconnect',
      );

      final restartApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'startDebugging'),
      );
      final restartResult = shell.agentSessionContext.commands.lastResult;
      expect(restartApplied, isTrue);
      expect(restartResult?.commandId, 'startDebugging');
      expect(restartResult?.applied, isTrue);
      expect(restartResult?.metadata['debugStatus'], 'launching');
      expect(shell.debugSession.status, DebugSessionStatus.launching);
      fakeTransport.addInbound(
        codec.encode(const <String, Object?>{
          'type': 'event',
          'event': 'stopped',
          'body': <String, Object?>{'reason': 'pause'},
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final threadsRequest = codec
          .decodeFirst(fakeTransport.sentBytes.last)!
          .message;
      expect(threadsRequest['command'], 'threads');
      fakeTransport.addInbound(
        codec.encode(<String, Object?>{
          'type': 'response',
          'request_seq': threadsRequest['seq'],
          'command': 'threads',
          'success': true,
          'body': <String, Object?>{
            'threads': <Object?>[
              <String, Object?>{'id': 5, 'name': 'worker thread'},
              <String, Object?>{'id': 6, 'name': 'io thread'},
            ],
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final fallbackStackTraceRequest = codec
          .decodeFirst(fakeTransport.sentBytes.last)!
          .message;
      expect(fallbackStackTraceRequest['command'], 'stackTrace');
      expect(
        (fallbackStackTraceRequest['arguments']!
            as Map<String, Object?>)['threadId'],
        5,
      );
      final threadFallbackDebugJson =
          shell.agentSessionContext.toJson()['debug']! as Map<String, Object?>;
      final debugThreads = threadFallbackDebugJson['threads']! as List<Object?>;
      expect(shell.debugSession.threads.first.name, 'worker thread');
      expect(shell.debugSession.threads.last.name, 'io thread');
      expect(threadFallbackDebugJson['threadCount'], 2);
      expect(
        (debugThreads.first! as Map<String, Object?>)['name'],
        'worker thread',
      );
      final selectThreadApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(
          commandId: 'selectDebugThread',
          input: '6',
          reason: 'Inspect the IO thread stack.',
        ),
      );
      final selectThreadResult = shell.agentSessionContext.commands.lastResult;
      expect(selectThreadApplied, isTrue);
      expect(selectThreadResult?.commandId, 'selectDebugThread');
      expect(selectThreadResult?.applied, isTrue);
      expect(selectThreadResult?.metadata['threadId'], '6');
      expect(shell.debugSession.stackFrames, isEmpty);
      expect(shell.debugSession.variables, isEmpty);
      final selectedThreadStackTraceRequest = codec
          .decodeFirst(fakeTransport.sentBytes.last)!
          .message;
      expect(selectedThreadStackTraceRequest['command'], 'stackTrace');
      expect(
        (selectedThreadStackTraceRequest['arguments']!
            as Map<String, Object?>)['threadId'],
        6,
      );
      fakeTransport.addInbound(
        codec.encode(const <String, Object?>{
          'type': 'event',
          'event': 'terminated',
        }),
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      final terminatedDebugJson =
          shell.agentSessionContext.toJson()['debug']! as Map<String, Object?>;
      expect(shell.debugSession.status, DebugSessionStatus.stopped);
      expect(shell.debugSession.adapterSessionStatus, 'terminated');
      expect(terminatedDebugJson['status'], 'stopped');
      expect(terminatedDebugJson['adapterSessionStatus'], 'terminated');
    },
  );

  test(
    'shell applies agent build static-analysis and test commands through toolchain manager',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_shell_native_tool_run_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final buildTool = File('${tempRoot.path}/fake-cmake.sh');
      final analyzer = File('${tempRoot.path}/fake-clang-tidy.sh');
      final testRunner = File('${tempRoot.path}/fake-ctest.sh');
      await buildTool.writeAsString('''
#!/bin/sh
printf 'src/main.cc:1:5: warning: build warning\\n'
''');
      await analyzer.writeAsString('''
#!/bin/sh
printf 'src/main.cc:1:5: warning: compact main [readability-compact-main]\\n'
''');
      await testRunner.writeAsString('''
#!/bin/sh
printf '100%% tests passed, 0 tests failed out of 2\\n'
''');
      await Process.run('chmod', <String>['+x', buildTool.path]);
      await Process.run('chmod', <String>['+x', analyzer.path]);
      await Process.run('chmod', <String>['+x', testRunner.path]);
      final configurationStore = await _createShellTestConfigurationStore(
        tempRoot,
      );
      final platformManagers = await createDetectedPlatformManagerBundle();
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );
      final catalog = ToolchainCatalog()
        ..register(
          ToolchainDescriptor(
            id: 'fake-lldb',
            kind: ToolchainKind.debugger,
            displayName: 'Fake LLDB',
            executablePath: buildTool.path,
            metadata: const <String, Object?>{
              'toolFamily': 'lldb',
              'adapterProtocol': 'dap',
              'programPath': 'build/demo',
            },
          ),
          activate: true,
        )
        ..register(
          ToolchainDescriptor(
            id: 'fake-cmake',
            kind: ToolchainKind.buildTool,
            displayName: 'Fake CMake',
            executablePath: buildTool.path,
            metadata: const <String, Object?>{'toolFamily': 'cmake'},
          ),
          activate: true,
        )
        ..register(
          ToolchainDescriptor(
            id: 'fake-clang-tidy',
            kind: ToolchainKind.staticAnalyzer,
            displayName: 'Fake clang-tidy',
            executablePath: analyzer.path,
            metadata: const <String, Object?>{'toolFamily': 'clang-tidy'},
          ),
          activate: true,
        )
        ..register(
          ToolchainDescriptor(
            id: 'fake-ctest',
            kind: ToolchainKind.testRunner,
            displayName: 'Fake CTest',
            executablePath: testRunner.path,
            metadata: const <String, Object?>{'toolFamily': 'ctest'},
          ),
          activate: true,
        );
      await toolchainStore.saveCatalog(
        catalog,
        targetId: platformManagers.context.targetId,
      );
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: tempRoot.path,
        activeFilePath: 'src/main.cc',
        title: 'Demo',
        notes: const <String>[],
      );
      const initialDocument = DocumentState(
        documentId: 'src/main.cc',
        text: 'int main(){return 0;}\n',
        revision: 0,
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: WorkspaceController(projectSnapshot: projectGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: const <String, DocumentState>{
            'src/main.cc': initialDocument,
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
        toolchainManager: ToolchainManager(
          configurationStore: toolchainStore,
          platformManagers: platformManagers,
        ),
      );
      addTearDown(shell.dispose);

      await shell.executeCommand(AppCommandId.startDebugging);
      expect(shell.debugSession.status, DebugSessionStatus.configured);
      expect(shell.debugSession.debuggerId, 'fake-lldb');
      expect(
        shell.debugSession.message,
        contains('Debug session configured with Fake LLDB'),
      );
      final debugJson =
          shell.agentSessionContext.toJson()['debug']! as Map<String, Object?>;
      final debugLaunch = debugJson['launch']! as Map<String, Object?>;
      expect(debugJson['status'], 'configured');
      expect(debugJson['debuggerId'], 'fake-lldb');
      expect(debugJson['debuggerLabel'], 'Fake LLDB');
      expect(debugLaunch['ready'], isTrue);
      expect(debugLaunch['readiness'], 'ready');
      expect(debugLaunch['programPath'], '${tempRoot.path}/build/demo');
      final buildApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'runBuild'),
      );
      final buildResult = shell.agentSessionContext.commands.lastResult;
      final analysisApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'runStaticAnalysis'),
      );
      final analysisResult = shell.agentSessionContext.commands.lastResult;
      final testsApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'runTests'),
      );
      final testsResult = shell.agentSessionContext.commands.lastResult;

      expect(buildApplied, isTrue);
      expect(buildResult?.commandId, 'runBuild');
      expect(buildResult?.applied, isTrue);
      expect(buildResult?.message, 'Run Build completed.');
      final structuredBuildResult =
          buildResult?.metadata['buildResult']! as Map<String, Object?>;
      expect(structuredBuildResult['runner'], 'cmake');
      expect(structuredBuildResult['status'], 'passed');
      expect(structuredBuildResult['diagnosticCount'], 1);
      expect(analysisApplied, isTrue);
      expect(analysisResult?.commandId, 'runStaticAnalysis');
      expect(analysisResult?.applied, isTrue);
      expect(analysisResult?.message, 'Run Static Analysis completed.');
      final staticAnalysisResult =
          analysisResult?.metadata['staticAnalysisResult']!
              as Map<String, Object?>;
      expect(staticAnalysisResult['runner'], 'clang-tidy');
      expect(staticAnalysisResult['status'], 'passed');
      expect(staticAnalysisResult['diagnosticCount'], 1);
      expect(shell.editorController.diagnostics, hasLength(2));
      final buildDiagnostic = shell.editorController.diagnostics.firstWhere(
        (diagnostic) => diagnostic.code == 'native-build',
      );
      final analysisDiagnostic = shell.editorController.diagnostics.firstWhere(
        (diagnostic) => diagnostic.code == 'readability-compact-main',
      );
      expect(buildDiagnostic.severity, DiagnosticSeverity.warning);
      expect(buildDiagnostic.message, 'build warning');
      expect(analysisDiagnostic.severity, DiagnosticSeverity.warning);
      expect(analysisDiagnostic.message, 'compact main');
      expect(testsApplied, isTrue);
      expect(testsResult?.commandId, 'runTests');
      expect(testsResult?.applied, isTrue);
      expect(testsResult?.message, 'Run Tests completed.');
      final testResult =
          testsResult?.metadata['testResult']! as Map<String, Object?>;
      expect(testResult['runner'], 'ctest');
      expect(testResult['status'], 'passed');
      expect(testResult['totalCount'], 2);
      expect(testResult['passedCount'], 2);
      expect(testResult['failedCount'], 0);
      expect(
        shell.nativeToolResults.map((result) => result.command),
        <AppCommandId>[
          AppCommandId.runTests,
          AppCommandId.runStaticAnalysis,
          AppCommandId.runBuild,
        ],
      );
      expect(
        shell.nativeToolResults.first.metadata['testResult'],
        isA<Map<String, Object?>>(),
      );
      expect(
        shell.nativeToolResults[1].metadata['staticAnalysisResult'],
        isA<Map<String, Object?>>(),
      );
      expect(
        shell.nativeToolResults.last.metadata['buildResult'],
        isA<Map<String, Object?>>(),
      );
      expect(shell.nativeToolResults.last.diagnostics, hasLength(1));
      expect(
        shell.openFirstNativeToolDiagnostic(AppCommandId.runBuild),
        isTrue,
      );
      expect(shell.editorController.selection.start, 4);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Run Build diagnostic selected in editor.'),
        ),
        isTrue,
      );
      expect(
        shell.debugLog.any((entry) => entry.contains('Run Build completed.')),
        isTrue,
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Run Static Analysis completed.'),
        ),
        isTrue,
      );
      expect(
        shell.debugLog.any((entry) => entry.contains('Run Tests completed.')),
        isTrue,
      );
    },
  );

  test(
    'shell configures CMake build with Clang C++ handoff before first build',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_shell_cmake_configure_handoff_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final cmakeLog = File('${tempRoot.path}/cmake-args.log');
      final cmake = File('${tempRoot.path}/fake-cmake.sh');
      final ninja = File('${tempRoot.path}/fake-ninja.sh');
      final analyzerLog = File('${tempRoot.path}/clang-tidy-args.log');
      final analyzer = File('${tempRoot.path}/fake-clang-tidy.sh');
      final clang = File('${tempRoot.path}/clang');
      final clangxx = File('${tempRoot.path}/clang++');
      await cmake.writeAsString('''
#!/bin/sh
printf '%s\\n' "\$*" >> '${cmakeLog.path}'
if [ "\$1" = "-S" ]; then
  mkdir -p "\$4"
  printf 'configured\\n'
  exit 0
fi
printf 'src/main.cc:1:5: warning: configured build warning\\n'
''');
      await ninja.writeAsString('#!/bin/sh\nexit 0\n');
      await analyzer.writeAsString('''
#!/bin/sh
printf '%s\\n' "\$*" >> '${analyzerLog.path}'
printf 'src/main.cc:1:5: warning: tidy after configure [readability-demo]\\n'
''');
      await clang.writeAsString('#!/bin/sh\nexit 0\n');
      await clangxx.writeAsString('#!/bin/sh\nexit 0\n');
      await Process.run('chmod', <String>[
        '+x',
        cmake.path,
        ninja.path,
        analyzer.path,
        clang.path,
        clangxx.path,
      ]);
      final configurationStore = await _createShellTestConfigurationStore(
        tempRoot,
      );
      final platformManagers = await createDetectedPlatformManagerBundle();
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );
      final catalog = ToolchainCatalog()
        ..register(
          ToolchainDescriptor(
            id: 'fake-clang',
            kind: ToolchainKind.compiler,
            displayName: 'Fake Clang',
            executablePath: clangxx.path,
            version: '18.1.8',
            metadata: <String, Object?>{
              'compilerFamily': 'clang',
              'cCompilerPath': clang.path,
              'cxxCompilerPath': clangxx.path,
            },
          ),
          activate: true,
        )
        ..register(
          ToolchainDescriptor(
            id: 'fake-cmake',
            kind: ToolchainKind.buildTool,
            displayName: 'Fake CMake',
            executablePath: cmake.path,
            metadata: const <String, Object?>{'toolFamily': 'cmake'},
          ),
          activate: true,
        )
        ..register(
          ToolchainDescriptor(
            id: 'fake-ninja',
            kind: ToolchainKind.buildTool,
            displayName: 'Fake Ninja',
            executablePath: ninja.path,
            metadata: const <String, Object?>{'toolFamily': 'ninja'},
          ),
        )
        ..register(
          ToolchainDescriptor(
            id: 'fake-clang-tidy',
            kind: ToolchainKind.staticAnalyzer,
            displayName: 'Fake clang-tidy',
            executablePath: analyzer.path,
            metadata: const <String, Object?>{'toolFamily': 'clang-tidy'},
          ),
          activate: true,
        );
      await toolchainStore.saveCatalog(
        catalog,
        targetId: platformManagers.context.targetId,
      );
      final projectGraph = ProjectGraphSnapshot.scratch(
        workspaceRoot: tempRoot.path,
        activeFilePath: 'src/main.cc',
        title: 'Demo',
        notes: const <String>[],
      ).copyWith(editorFiles: <String>['src/main.cc', 'CMakeLists.txt']);
      const initialDocument = DocumentState(
        documentId: 'src/main.cc',
        text: 'int main(){return 0;}\n',
        revision: 0,
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: WorkspaceController(projectSnapshot: projectGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: const <String, DocumentState>{
            'src/main.cc': initialDocument,
            'CMakeLists.txt': DocumentState(
              documentId: 'CMakeLists.txt',
              text: 'cmake_minimum_required(VERSION 3.20)\n',
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
        toolchainManager: ToolchainManager(
          configurationStore: toolchainStore,
          platformManagers: platformManagers,
        ),
        clangCppVersionPreference: const ClangCppVersionPreference(
          versionId: 'fake-clang',
          cppStandard: CppLanguageStandard.cpp23,
        ),
      );
      addTearDown(shell.dispose);

      await shell.executeCommand(AppCommandId.runBuild);

      final buildResult =
          shell.lastNativeToolResult!.metadata['buildResult']!
              as Map<String, Object?>;
      final configureResult =
          buildResult['configureResult']! as Map<String, Object?>;
      final configureArguments = configureResult['arguments']! as List<Object?>;
      final cmakeCalls = await cmakeLog.readAsLines();
      expect(shell.lastNativeToolResult?.applied, isTrue);
      expect(buildResult['configuredBeforeBuild'], isTrue);
      expect(buildResult['buildDirectory'], 'build');
      expect(buildResult['status'], 'passed');
      expect(buildResult['diagnosticCount'], 1);
      expect(configureResult['status'], 'passed');
      expect(configureArguments, contains('-G'));
      expect(configureArguments, contains('Ninja'));
      expect(configureArguments, contains('-DCMAKE_CXX_STANDARD=23'));
      expect(
        configureArguments,
        contains('-DCMAKE_CXX_COMPILER=${clangxx.path}'),
      );
      expect(cmakeCalls, hasLength(2));
      expect(cmakeCalls.first, contains('-S . -B build -G Ninja'));
      expect(cmakeCalls.first, contains('-DCMAKE_MAKE_PROGRAM=${ninja.path}'));
      expect(cmakeCalls.last, '--build build');
      expect(
        shell.workspaceController.files,
        containsAll(<String>[
          'build/CMakeCache.txt',
          'build/compile_commands.json',
          'build/build.ninja',
        ]),
      );

      await shell.executeCommand(AppCommandId.runStaticAnalysis);
      final analysisResult =
          shell.lastNativeToolResult!.metadata['staticAnalysisResult']!
              as Map<String, Object?>;
      expect(analysisResult['compilationDatabase'], 'build');
      expect(analysisResult['arguments'], <Object?>[
        '-p',
        'build',
        'src/main.cc',
      ]);
      expect(await analyzerLog.readAsString(), '-p build src/main.cc\n');
    },
  );

  test('shell runs direct Ninja build when CMake is unavailable', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_shell_direct_ninja_build_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final ninjaLog = File('${tempRoot.path}/ninja-args.log');
    final ninja = File('${tempRoot.path}/fake-ninja.sh');
    await ninja.writeAsString('''
#!/bin/sh
printf '%s\\n' "\$*" >> '${ninjaLog.path}'
printf 'src/main.cc:1:5: warning: ninja build warning\\n'
''');
    await Process.run('chmod', <String>['+x', ninja.path]);
    final configurationStore = await _createShellTestConfigurationStore(
      tempRoot,
    );
    final platformManagers = await createDetectedPlatformManagerBundle();
    final toolchainStore = ToolchainConfigurationStore(
      configurationStore: configurationStore,
    );
    final catalog = ToolchainCatalog()
      ..register(
        ToolchainDescriptor(
          id: 'fake-ninja',
          kind: ToolchainKind.buildTool,
          displayName: 'Fake Ninja',
          executablePath: ninja.path,
          metadata: const <String, Object?>{'toolFamily': 'ninja'},
        ),
        activate: true,
      );
    await toolchainStore.saveCatalog(
      catalog,
      targetId: platformManagers.context.targetId,
    );
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: tempRoot.path,
      activeFilePath: 'src/main.cc',
      title: 'Demo',
      notes: const <String>[],
    ).copyWith(editorFiles: <String>['src/main.cc', 'build/build.ninja']);
    const initialDocument = DocumentState(
      documentId: 'src/main.cc',
      text: 'int main(){return 0;}\n',
      revision: 0,
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.cc': initialDocument,
          'build/build.ninja': DocumentState(
            documentId: 'build/build.ninja',
            text: 'rule cc\n  command = clang++ main.cc\n',
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
      toolchainManager: ToolchainManager(
        configurationStore: toolchainStore,
        platformManagers: platformManagers,
      ),
    );
    addTearDown(shell.dispose);

    await shell.executeCommand(AppCommandId.runBuild);

    final buildResult =
        shell.lastNativeToolResult!.metadata['buildResult']!
            as Map<String, Object?>;
    expect(shell.lastNativeToolResult?.applied, isTrue);
    expect(buildResult['runner'], 'ninja');
    expect(buildResult['status'], 'passed');
    expect(buildResult['buildDirectory'], 'build');
    expect(buildResult['configuredBeforeBuild'], isFalse);
    expect(buildResult['arguments'], <Object?>['-C', 'build']);
    expect(buildResult['diagnosticCount'], 1);
    expect(buildResult['exitCode'], 0);
    expect(buildResult['stdoutPreview'], contains('ninja build warning'));
    expect(await ninjaLog.readAsString(), '-C build\n');
  });

  test('shell runs CTest from configured CMake build directory', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_shell_ctest_build_dir_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final ctestLog = File('${tempRoot.path}/ctest-args.log');
    final ctest = File('${tempRoot.path}/fake-ctest.sh');
    await ctest.writeAsString('''
#!/bin/sh
printf '%s\\n' "\$*" >> '${ctestLog.path}'
printf '100%% tests passed, 0 tests failed out of 3\\n'
''');
    await Process.run('chmod', <String>['+x', ctest.path]);
    final configurationStore = await _createShellTestConfigurationStore(
      tempRoot,
    );
    final platformManagers = await createDetectedPlatformManagerBundle();
    final toolchainStore = ToolchainConfigurationStore(
      configurationStore: configurationStore,
    );
    final catalog = ToolchainCatalog()
      ..register(
        ToolchainDescriptor(
          id: 'fake-ctest',
          kind: ToolchainKind.testRunner,
          displayName: 'Fake CTest',
          executablePath: ctest.path,
          metadata: const <String, Object?>{'toolFamily': 'ctest'},
        ),
        activate: true,
      );
    await toolchainStore.saveCatalog(
      catalog,
      targetId: platformManagers.context.targetId,
    );
    final projectGraph =
        ProjectGraphSnapshot.scratch(
          workspaceRoot: tempRoot.path,
          activeFilePath: 'src/main.cc',
          title: 'Demo',
          notes: const <String>[],
        ).copyWith(
          editorFiles: <String>['src/main.cc', 'build/CTestTestfile.cmake'],
        );
    const initialDocument = DocumentState(
      documentId: 'src/main.cc',
      text: 'int main(){return 0;}\n',
      revision: 0,
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.cc': initialDocument,
          'build/CTestTestfile.cmake': DocumentState(
            documentId: 'build/CTestTestfile.cmake',
            text: '# CTest generated file\n',
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
      toolchainManager: ToolchainManager(
        configurationStore: toolchainStore,
        platformManagers: platformManagers,
      ),
    );
    addTearDown(shell.dispose);

    await shell.executeCommand(AppCommandId.runTests);

    final testResult =
        shell.lastNativeToolResult!.metadata['testResult']!
            as Map<String, Object?>;
    expect(shell.lastNativeToolResult?.applied, isTrue);
    expect(testResult['runner'], 'ctest');
    expect(testResult['status'], 'passed');
    expect(testResult['totalCount'], 3);
    expect(testResult['testDirectory'], 'build');
    expect(testResult['arguments'], <Object?>[
      '--test-dir',
      'build',
      '--output-on-failure',
    ]);
    expect(testResult['exitCode'], 0);
    expect(testResult['stdoutPreview'], contains('100% tests passed'));
    expect(
      await ctestLog.readAsString(),
      '--test-dir build --output-on-failure\n',
    );
  });

  test('shell blocks CTest before CMake build directory exists', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_shell_ctest_requires_build_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final ctest = File('${tempRoot.path}/fake-ctest.sh');
    await ctest.writeAsString('#!/bin/sh\nexit 0\n');
    await Process.run('chmod', <String>['+x', ctest.path]);
    final configurationStore = await _createShellTestConfigurationStore(
      tempRoot,
    );
    final platformManagers = await createDetectedPlatformManagerBundle();
    final toolchainStore = ToolchainConfigurationStore(
      configurationStore: configurationStore,
    );
    final catalog = ToolchainCatalog()
      ..register(
        ToolchainDescriptor(
          id: 'fake-ctest',
          kind: ToolchainKind.testRunner,
          displayName: 'Fake CTest',
          executablePath: ctest.path,
          metadata: const <String, Object?>{'toolFamily': 'ctest'},
        ),
        activate: true,
      );
    await toolchainStore.saveCatalog(
      catalog,
      targetId: platformManagers.context.targetId,
    );
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: tempRoot.path,
      activeFilePath: 'src/main.cc',
      title: 'Demo',
      notes: const <String>[],
    ).copyWith(editorFiles: <String>['src/main.cc', 'CMakeLists.txt']);
    const initialDocument = DocumentState(
      documentId: 'src/main.cc',
      text: 'int main(){return 0;}\n',
      revision: 0,
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.cc': initialDocument,
          'CMakeLists.txt': DocumentState(
            documentId: 'CMakeLists.txt',
            text: 'enable_testing()\n',
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
      toolchainManager: ToolchainManager(
        configurationStore: toolchainStore,
        platformManagers: platformManagers,
      ),
    );
    addTearDown(shell.dispose);

    final applied = await shell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(commandId: 'runTests'),
    );

    final agentCommandResult = shell.agentSessionContext.commands.lastResult;
    final testResult =
        agentCommandResult?.metadata['testResult']! as Map<String, Object?>;
    expect(applied, isFalse);
    expect(agentCommandResult?.commandId, 'runTests');
    expect(agentCommandResult?.metadata['requiredCommand'], 'runBuild');
    expect(testResult['status'], 'blocked');
    expect(testResult['reason'], 'missing-ctest-build-directory');
    expect(testResult['requiredCommand'], 'runBuild');
  });

  test('shell blocks clang-tidy before compile commands exist', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_shell_clang_tidy_requires_build_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final analyzer = File('${tempRoot.path}/fake-clang-tidy.sh');
    await analyzer.writeAsString('#!/bin/sh\nexit 0\n');
    await Process.run('chmod', <String>['+x', analyzer.path]);
    final configurationStore = await _createShellTestConfigurationStore(
      tempRoot,
    );
    final platformManagers = await createDetectedPlatformManagerBundle();
    final toolchainStore = ToolchainConfigurationStore(
      configurationStore: configurationStore,
    );
    final catalog = ToolchainCatalog()
      ..register(
        ToolchainDescriptor(
          id: 'fake-clang-tidy',
          kind: ToolchainKind.staticAnalyzer,
          displayName: 'Fake clang-tidy',
          executablePath: analyzer.path,
          metadata: const <String, Object?>{'toolFamily': 'clang-tidy'},
        ),
        activate: true,
      );
    await toolchainStore.saveCatalog(
      catalog,
      targetId: platformManagers.context.targetId,
    );
    final projectGraph = ProjectGraphSnapshot.scratch(
      workspaceRoot: tempRoot.path,
      activeFilePath: 'src/main.cc',
      title: 'Demo',
      notes: const <String>[],
    ).copyWith(editorFiles: <String>['src/main.cc', 'CMakeLists.txt']);
    const initialDocument = DocumentState(
      documentId: 'src/main.cc',
      text: 'int main(){return 0;}\n',
      revision: 0,
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.cc': initialDocument,
          'CMakeLists.txt': DocumentState(
            documentId: 'CMakeLists.txt',
            text: 'add_executable(demo src/main.cc)\n',
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
      toolchainManager: ToolchainManager(
        configurationStore: toolchainStore,
        platformManagers: platformManagers,
      ),
    );
    addTearDown(shell.dispose);

    final applied = await shell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(commandId: 'runStaticAnalysis'),
    );

    final agentCommandResult = shell.agentSessionContext.commands.lastResult;
    final analysisResult =
        agentCommandResult?.metadata['staticAnalysisResult']!
            as Map<String, Object?>;
    expect(applied, isFalse);
    expect(agentCommandResult?.commandId, 'runStaticAnalysis');
    expect(agentCommandResult?.metadata['requiredCommand'], 'runBuild');
    expect(analysisResult['status'], 'blocked');
    expect(analysisResult['reason'], 'missing-compile-commands');
    expect(analysisResult['requiredCommand'], 'runBuild');
  });

  test('shell runs clang-tidy with compilation database directory', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_shell_clang_tidy_compile_commands_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final analyzerLog = File('${tempRoot.path}/clang-tidy-args.log');
    final analyzer = File('${tempRoot.path}/fake-clang-tidy.sh');
    await analyzer.writeAsString('''
#!/bin/sh
printf '%s\\n' "\$*" >> '${analyzerLog.path}'
printf 'src/main.cc:1:5: warning: tidy warning [readability-demo]\\n'
''');
    await Process.run('chmod', <String>['+x', analyzer.path]);
    final configurationStore = await _createShellTestConfigurationStore(
      tempRoot,
    );
    final platformManagers = await createDetectedPlatformManagerBundle();
    final toolchainStore = ToolchainConfigurationStore(
      configurationStore: configurationStore,
    );
    final catalog = ToolchainCatalog()
      ..register(
        ToolchainDescriptor(
          id: 'fake-clang-tidy',
          kind: ToolchainKind.staticAnalyzer,
          displayName: 'Fake clang-tidy',
          executablePath: analyzer.path,
          metadata: const <String, Object?>{'toolFamily': 'clang-tidy'},
        ),
        activate: true,
      );
    await toolchainStore.saveCatalog(
      catalog,
      targetId: platformManagers.context.targetId,
    );
    final projectGraph =
        ProjectGraphSnapshot.scratch(
          workspaceRoot: tempRoot.path,
          activeFilePath: 'src/main.cc',
          title: 'Demo',
          notes: const <String>[],
        ).copyWith(
          editorFiles: <String>['src/main.cc', 'build/compile_commands.json'],
        );
    const initialDocument = DocumentState(
      documentId: 'src/main.cc',
      text: 'int main(){return 0;}\n',
      revision: 0,
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.cc': initialDocument,
          'build/compile_commands.json': DocumentState(
            documentId: 'build/compile_commands.json',
            text: '[]\n',
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
      toolchainManager: ToolchainManager(
        configurationStore: toolchainStore,
        platformManagers: platformManagers,
      ),
    );
    addTearDown(shell.dispose);

    await shell.executeCommand(AppCommandId.runStaticAnalysis);

    final analysisResult =
        shell.lastNativeToolResult!.metadata['staticAnalysisResult']!
            as Map<String, Object?>;
    expect(shell.lastNativeToolResult?.applied, isTrue);
    expect(analysisResult['runner'], 'clang-tidy');
    expect(analysisResult['status'], 'passed');
    expect(analysisResult['compilationDatabase'], 'build');
    expect(analysisResult['arguments'], <Object?>[
      '-p',
      'build',
      'src/main.cc',
    ]);
    expect(analysisResult['diagnosticCount'], 1);
    expect(analysisResult['exitCode'], 0);
    expect(analysisResult['stdoutPreview'], contains('tidy warning'));
    final agentCommandResult = shell.agentSessionContext.commands.lastResult;
    final agentAnalysisResult =
        agentCommandResult?.metadata['staticAnalysisResult']!
            as Map<String, Object?>;
    expect(agentCommandResult?.commandId, 'runStaticAnalysis');
    expect(agentAnalysisResult['stdoutPreview'], contains('tidy warning'));
    expect(agentAnalysisResult['arguments'], <Object?>[
      '-p',
      'build',
      'src/main.cc',
    ]);
    expect(await analyzerLog.readAsString(), '-p build src/main.cc\n');
  });

  test(
    'shell blocks active file close while editor binding is dirty',
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
      final documentStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': initialDocument,
        },
      );
      final workspaceController = WorkspaceController(
        projectSnapshot: projectGraph,
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: workspaceController,
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

      shell.editorController.insertText('// local edit\n');

      final result = shell.requestCloseWorkspaceFile('src/main.styio');

      expect(
        result.status,
        WorkspaceFileCloseRequestStatus.blockedUnsavedChanges,
      );
      expect(result.requiresUserChoice, isTrue);
      expect(result.canSave, isTrue);
      expect(result.canDiscard, isTrue);
      expect(shell.closeRequestSurface?.requiresUserChoice, isTrue);
      expect(shell.closeRequestSurface?.canSave, isTrue);
      expect(shell.closeRequestSurface?.canDiscard, isTrue);
      expect(workspaceController.activeFilePath, 'src/main.styio');
      expect(workspaceController.openFilePaths, <String>['src/main.styio']);
      expect(
        shell.debugLog.any((entry) => entry.contains('Close blocked')),
        isTrue,
      );

      shell.clearCloseRequestResult();

      expect(shell.closeRequestSurface, isNull);
    },
  );

  test('shell reports close request for file that is not open', () async {
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
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: WorkspaceController(projectSnapshot: projectGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': initialDocument,
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

    final result = shell.requestCloseWorkspaceFile('src/missing.styio');

    expect(result.status, WorkspaceFileCloseRequestStatus.notOpen);
    expect(result.closed, isFalse);
    expect(result.requiresUserChoice, isFalse);
  });

  test('shell blocks inactive dirty file close request', () async {
    final projectGraph = _multiFileProjectGraph();
    const mainDocument = DocumentState(
      documentId: 'src/main.styio',
      text: 'value := 1\n',
      revision: 0,
    );
    const libDocument = DocumentState(
      documentId: 'src/lib.styio',
      text: 'lib := 1\n',
      revision: 0,
    );
    final workspaceController = WorkspaceController(
      projectSnapshot: projectGraph,
    );
    final shell = ShellRuntimeModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
      workspaceController: workspaceController,
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': mainDocument,
          'src/lib.styio': libDocument,
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

    shell.editorController.insertText('// dirty main\n');
    workspaceController.openFile('src/lib.styio');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    expect(shell.dirtyDocumentPaths, contains('src/main.styio'));

    final result = shell.requestCloseWorkspaceFile('src/main.styio');

    expect(
      result.status,
      WorkspaceFileCloseRequestStatus.blockedUnsavedChanges,
    );
    expect(result.canSave, isFalse);
    expect(result.canDiscard, isFalse);
    expect(result.canSwitchToFile, isTrue);
    expect(workspaceController.activeFilePath, 'src/lib.styio');

    shell.switchToCloseRequestFile();

    expect(workspaceController.activeFilePath, 'src/main.styio');
    expect(shell.closeRequestSurface?.canSave, isTrue);
    expect(shell.closeRequestSurface?.canDiscard, isTrue);

    final saveAllResult = await shell.saveAllWorkspaceFileChanges();

    expect(saveAllResult.savedAll, isTrue);
    expect(shell.closeRequestSurface, isNull);
  });

  test(
    'shell blocks agent workspace patch for inactive dirty document',
    () async {
      final projectGraph = _multiFileProjectGraph();
      const mainDocument = DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 0,
      );
      const libDocument = DocumentState(
        documentId: 'src/lib.styio',
        text: 'lib := 1\n',
        revision: 0,
      );
      const patch = AgentCodePatch(
        patchId: 'patch-dirty-inactive-shell',
        summary: 'Update inactive dirty file.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'src/main.styio',
            baseRevision: 0,
            start: 9,
            end: 10,
            replacementText: '2',
          ),
        ],
      );
      final documentStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': mainDocument,
          'src/lib.styio': libDocument,
        },
      );
      final workspaceController = WorkspaceController(
        projectSnapshot: projectGraph,
      );
      final agentController = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.macos),
        adapter: const _StaticAgentProviderAdapter(
          response: AgentProviderResponseEnvelope(
            requestId: 'agent-request-1',
            role: 'assistant',
            finishReason: 'stop',
            contentParts: <AgentContentPart>[
              AgentContentPart(
                kind: AgentContentPartKind.codePatch,
                text: 'Patch ready.',
                patch: patch,
              ),
            ],
          ),
        ),
        contextProvider: () => throw StateError(
          'ShellRuntimeModel should replace the agent context provider.',
        ),
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: workspaceController,
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
        agentCodingController: agentController,
      );
      addTearDown(() {
        shell.dispose();
        agentController.dispose();
      });

      shell.editorController.insertText('// dirty main\n');
      workspaceController.openFile('src/lib.styio');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      agentController.updatePrompt('Apply patch.');
      await agentController.sendPrompt();

      final result = await shell.applyAgentPendingPatch();
      final persistedMain = await documentStore.loadDocument('src/main.styio');

      expect(result?.applied, isFalse);
      expect(
        result?.message,
        contains('inactive dirty document src/main.styio'),
      );
      expect(agentController.pendingPatch, isNotNull);
      expect(workspaceController.activeFilePath, 'src/lib.styio');
      expect(shell.dirtyDocumentPaths, contains('src/main.styio'));
      expect(persistedMain.text, 'value := 1\n');
    },
  );

  test(
    'shell blocks agent workspace patch for unsampled inactive document',
    () async {
      final projectGraph = _multiFileProjectGraph();
      const mainDocument = DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 0,
      );
      const libDocument = DocumentState(
        documentId: 'src/lib.styio',
        text: 'lib := 1\n',
        revision: 0,
      );
      const patch = AgentCodePatch(
        patchId: 'patch-unsampled-inactive-shell',
        summary: 'Update unsampled inactive file.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'src/lib.styio',
            baseRevision: 0,
            start: 7,
            end: 8,
            replacementText: '2',
          ),
        ],
      );
      final documentStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': mainDocument,
          'src/lib.styio': libDocument,
        },
      );
      final workspaceController = WorkspaceController(
        projectSnapshot: projectGraph,
      );
      final agentController = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.macos),
        adapter: const _StaticAgentProviderAdapter(
          response: AgentProviderResponseEnvelope(
            requestId: 'agent-request-1',
            role: 'assistant',
            finishReason: 'stop',
            contentParts: <AgentContentPart>[
              AgentContentPart(
                kind: AgentContentPartKind.codePatch,
                text: 'Patch ready.',
                patch: patch,
              ),
            ],
          ),
        ),
        contextProvider: () => throw StateError(
          'ShellRuntimeModel should replace the agent context provider.',
        ),
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: workspaceController,
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
        agentCodingController: agentController,
      );
      addTearDown(() {
        shell.dispose();
        agentController.dispose();
      });

      agentController.updatePrompt('Apply patch.');
      await agentController.sendPrompt();

      final result = await shell.applyAgentPendingPatch();
      final persistedLib = await documentStore.loadDocument('src/lib.styio');

      expect(result?.applied, isFalse);
      expect(
        result?.message,
        contains('unsampled inactive document src/lib.styio'),
      );
      expect(agentController.pendingPatch, isNotNull);
      expect(workspaceController.activeFilePath, 'src/main.styio');
      expect(persistedLib.text, 'lib := 1\n');
    },
  );

  test(
    'shell reloads inactive open document after successful agent workspace patch',
    () async {
      final projectGraph = _multiFileProjectGraph();
      const mainDocument = DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 0,
      );
      const libDocument = DocumentState(
        documentId: 'src/lib.styio',
        text: 'lib := 1\n',
        revision: 0,
      );
      const patch = AgentCodePatch(
        patchId: 'patch-refresh-inactive-open',
        summary: 'Update inactive clean file.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'src/lib.styio',
            baseRevision: 0,
            start: 7,
            end: 8,
            replacementText: '2',
          ),
        ],
      );
      final documentStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': mainDocument,
          'src/lib.styio': libDocument,
        },
      );
      final workspaceController = WorkspaceController(
        projectSnapshot: projectGraph,
      );
      final agentController = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.macos),
        adapter: const _StaticAgentProviderAdapter(
          response: AgentProviderResponseEnvelope(
            requestId: 'agent-request-1',
            role: 'assistant',
            finishReason: 'stop',
            contentParts: <AgentContentPart>[
              AgentContentPart(
                kind: AgentContentPartKind.codePatch,
                text: 'Patch ready.',
                patch: patch,
              ),
            ],
          ),
        ),
        contextProvider: () => throw StateError(
          'ShellRuntimeModel should replace the agent context provider.',
        ),
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: workspaceController,
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
        agentCodingController: agentController,
      );
      addTearDown(() {
        shell.dispose();
        agentController.dispose();
      });

      workspaceController.openFile('src/lib.styio');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      workspaceController.openFile('src/main.styio');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(shell.cachedDocumentPaths, contains('src/lib.styio'));
      agentController.updatePrompt('Apply patch.');
      await agentController.sendPrompt();

      final result = await shell.applyAgentPendingPatch();
      workspaceController.openFile('src/lib.styio');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(result?.applied, isTrue);
      expect(result?.appliedDocumentIds, <String>['src/lib.styio']);
      expect(shell.editorController.document.text, 'lib := 2\n');
    },
  );

  test(
    'shell closes inactive open document after successful agent delete patch',
    () async {
      final projectGraph = _multiFileProjectGraph();
      const mainDocument = DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 0,
      );
      const libDocument = DocumentState(
        documentId: 'src/lib.styio',
        text: 'lib := 1\n',
        revision: 0,
      );
      const patch = AgentCodePatch(
        patchId: 'patch-delete-inactive-open',
        summary: 'Delete inactive clean file.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'src/main.styio',
            operation: AgentCodePatchEditOperation.delete,
            baseRevision: 0,
            start: 0,
            end: 0,
            replacementText: '',
          ),
        ],
      );
      final documentStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': mainDocument,
          'src/lib.styio': libDocument,
        },
      );
      final workspaceController = WorkspaceController(
        projectSnapshot: projectGraph,
      );
      final agentController = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.macos),
        adapter: const _StaticAgentProviderAdapter(
          response: AgentProviderResponseEnvelope(
            requestId: 'agent-request-1',
            role: 'assistant',
            finishReason: 'stop',
            contentParts: <AgentContentPart>[
              AgentContentPart(
                kind: AgentContentPartKind.codePatch,
                text: 'Patch ready.',
                patch: patch,
              ),
            ],
          ),
        ),
        contextProvider: () => throw StateError(
          'ShellRuntimeModel should replace the agent context provider.',
        ),
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: workspaceController,
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
        agentCodingController: agentController,
      );
      addTearDown(() {
        shell.dispose();
        agentController.dispose();
      });

      workspaceController.openFile('src/lib.styio');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      agentController.updatePrompt('Apply patch.');
      await agentController.sendPrompt();

      final result = await shell.applyAgentPendingPatch();

      expect(result?.applied, isTrue);
      expect(result?.deletedDocumentIds, <String>['src/main.styio']);
      expect(await documentStore.documentExists('src/main.styio'), isFalse);
      expect(workspaceController.activeFilePath, 'src/lib.styio');
      expect(
        workspaceController.openFilePaths,
        isNot(contains('src/main.styio')),
      );
      expect(workspaceController.files, isNot(contains('src/main.styio')));
      expect(
        shell.agentSessionContext.workspace.files,
        isNot(contains('src/main.styio')),
      );
    },
  );

  test(
    'shell registers agent-created workspace documents in the file list',
    () async {
      final projectGraph = _multiFileProjectGraph();
      const mainDocument = DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 0,
      );
      const patch = AgentCodePatch(
        patchId: 'patch-create-visible-file',
        summary: 'Create visible file.',
        edits: <AgentCodePatchEdit>[
          AgentCodePatchEdit(
            documentId: 'src/generated.styio',
            operation: AgentCodePatchEditOperation.create,
            start: 0,
            end: 0,
            replacementText: 'generated := 1\n',
          ),
        ],
      );
      final documentStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: const <String, DocumentState>{
          'src/main.styio': mainDocument,
        },
      );
      final workspaceController = WorkspaceController(
        projectSnapshot: projectGraph,
      );
      final agentController = AgentCodingSessionController(
        profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.macos),
        adapter: const _StaticAgentProviderAdapter(
          response: AgentProviderResponseEnvelope(
            requestId: 'agent-request-1',
            role: 'assistant',
            finishReason: 'stop',
            contentParts: <AgentContentPart>[
              AgentContentPart(
                kind: AgentContentPartKind.codePatch,
                text: 'Patch ready.',
                patch: patch,
              ),
            ],
          ),
        ),
        contextProvider: () => throw StateError(
          'ShellRuntimeModel should replace the agent context provider.',
        ),
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: workspaceController,
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
        agentCodingController: agentController,
      );
      addTearDown(() {
        shell.dispose();
        agentController.dispose();
      });

      agentController.updatePrompt('Apply patch.');
      await agentController.sendPrompt();

      final result = await shell.applyAgentPendingPatch();
      final createdDocument = await documentStore.loadDocument(
        'src/generated.styio',
      );

      expect(result?.applied, isTrue);
      expect(result?.createdDocumentIds, <String>['src/generated.styio']);
      expect(createdDocument.text, 'generated := 1\n');
      expect(workspaceController.files, contains('src/generated.styio'));
      expect(
        shell.agentSessionContext.workspace.files,
        contains('src/generated.styio'),
      );
      expect(workspaceController.openFilePaths, <String>['src/main.styio']);
    },
  );

  test(
    'shell evicts clean closed documents from editor document cache',
    () async {
      final projectGraph = _multiFileProjectGraph(
        editorFiles: const <String>[
          'src/main.styio',
          'src/lib.styio',
          'src/extra.styio',
        ],
      );
      const mainDocument = DocumentState(
        documentId: 'src/main.styio',
        text: 'value := 1\n',
        revision: 0,
      );
      const libDocument = DocumentState(
        documentId: 'src/lib.styio',
        text: 'lib := 1\n',
        revision: 0,
      );
      const extraDocument = DocumentState(
        documentId: 'src/extra.styio',
        text: 'extra := 1\n',
        revision: 0,
      );
      final workspaceController = WorkspaceController(
        projectSnapshot: projectGraph,
      );
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: workspaceController,
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: const <String, DocumentState>{
            'src/main.styio': mainDocument,
            'src/lib.styio': libDocument,
            'src/extra.styio': extraDocument,
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
        documentCacheLimit: 2,
      );
      addTearDown(shell.dispose);

      workspaceController.openFile('src/lib.styio');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      workspaceController.closeFile('src/main.styio');
      workspaceController.openFile('src/extra.styio');
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(shell.cachedDocumentPaths, isNot(contains('src/main.styio')));
      expect(shell.cachedDocumentPaths, contains('src/lib.styio'));
      expect(shell.cachedDocumentPaths, contains('src/extra.styio'));
    },
  );

  test('shell discards active editor changes from backing document', () async {
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

    shell.editorController.insertText('// local edit\n');
    shell.requestCloseWorkspaceFile('src/main.styio');
    expect(shell.closeRequestSurface?.requiresUserChoice, isTrue);

    final snapshot = await shell.discardActiveWorkspaceFileChanges();

    expect(snapshot.state, DocumentResourceBindingState.boundClean);
    expect(shell.editorController.document.text, initialDocument.text);
    expect(shell.closeRequestSurface, isNull);
    expect(
      shell.debugLog.any((entry) => entry.contains('Discarded local changes')),
      isTrue,
    );
  });

  test(
    'shell saves active editor changes through dirty action method',
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

      shell.editorController.insertText('// saved edit\n');
      shell.requestCloseWorkspaceFile('src/main.styio');
      expect(shell.closeRequestSurface?.requiresUserChoice, isTrue);

      final snapshot = await shell.saveActiveWorkspaceFileChanges();

      expect(snapshot.state, DocumentResourceBindingState.boundClean);
      expect(shell.closeRequestSurface, isNull);
      final persisted = await documentStore.loadDocument('src/main.styio');
      expect(persisted.text, shell.editorController.document.text);
    },
  );

  test(
    'shell save or discard close request continues original close',
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
      final shell = ShellRuntimeModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _StaticProjectGraphAdapter(projectGraph),
        workspaceController: WorkspaceController(projectSnapshot: projectGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: const <String, DocumentState>{
            'src/main.styio': initialDocument,
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

      shell.editorController.insertText('// save and close\n');
      shell.requestCloseWorkspaceFile('src/main.styio');

      final saveClose = await shell.saveAndCloseRequestedWorkspaceFile();

      expect(saveClose?.status, WorkspaceFileCloseRequestStatus.closed);
      expect(shell.closeRequestSurface?.requiresUserChoice, isFalse);

      shell.editorController.insertText('// discard and close\n');
      shell.requestCloseWorkspaceFile('src/main.styio');

      final discardClose = await shell.discardAndCloseRequestedWorkspaceFile();

      expect(discardClose?.status, WorkspaceFileCloseRequestStatus.closed);
      expect(shell.closeRequestSurface?.requiresUserChoice, isFalse);
    },
  );

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

class _DeferredWorkspaceDocumentStore implements WorkspaceDocumentStore {
  final Map<String, Completer<DocumentState>> _pendingLoads =
      <String, Completer<DocumentState>>{};
  final Map<String, DocumentState> _documents = <String, DocumentState>{};

  void completeLoad(DocumentState document) {
    _documents[document.documentId] = document;
    final completer = _pendingLoads.putIfAbsent(
      document.documentId,
      Completer<DocumentState>.new,
    );
    if (!completer.isCompleted) {
      completer.complete(document);
    }
  }

  @override
  Future<DocumentState> loadDocument(String path) {
    final existing = _documents[path];
    if (existing != null) {
      return Future<DocumentState>.value(existing);
    }
    return _pendingLoads.putIfAbsent(path, Completer<DocumentState>.new).future;
  }

  @override
  Future<void> saveDocument(DocumentState document) async {
    _documents[document.documentId] = document;
  }

  @override
  Future<bool> deleteDocument(String path) async {
    return _documents.remove(path) != null;
  }

  @override
  Future<bool> documentExists(String path) async {
    return _documents.containsKey(path);
  }

  @override
  String? filePathForDocumentId(String documentId) => null;
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
    level: AdapterCapabilityLevel.partial,
    detail: 'single-file execution available for shell file binding tests',
  ),
  runtimeEvents: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'not needed for shell file binding test',
  ),
);

const _singleFileCompiler = CompilerHandshakeSnapshot(
  binaryPath: '/toolchains/styio/bin/styio',
  tool: 'styio',
  compilerVersion: '0.1.0',
  channel: 'stable',
  variant: 'test',
  capabilities: <String>['machine_info_json', 'single_file_entry'],
  supportedContractVersions: <String, List<int>>{
    'machine_info': <int>[1],
  },
  integrationPhase: 'single-file-test',
);

class _StaticProjectGraphAdapter implements ProjectGraphAdapter {
  const _StaticProjectGraphAdapter(this._projectGraph);

  final ProjectGraphSnapshot _projectGraph;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => _capabilitySnapshot;

  @override
  Future<ProjectGraphSnapshot> loadProjectGraph() async => _projectGraph;
}

class _StaticAgentProviderAdapter implements AgentProviderAdapter {
  const _StaticAgentProviderAdapter({required this.response});

  final AgentProviderResponseEnvelope response;

  @override
  String get adapterId => 'static-shell-file-binding-agent';

  @override
  AgentProviderKind get kind => AgentProviderKind.localOnlyFallback;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return response;
  }
}

class _DiagnosticExecutionAdapter implements ExecutionAdapter {
  const _DiagnosticExecutionAdapter();

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => _capabilitySnapshot;

  @override
  Future<ExecutionSession> runActiveDocument({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
  }) async {
    final start = document.text.indexOf('<|');
    return ExecutionSession(
      sessionId: 'diagnostic',
      kind: 'run',
      status: ExecutionSessionStatus.failed,
      statusMessage: 'compile failed',
      diagnostics: <Diagnostic>[
        Diagnostic(
          severity: DiagnosticSeverity.error,
          code: 'execution.compile',
          message: 'Compiler rejected the active run unit.',
          range: SourceRange(start: start, end: start + 2),
        ),
      ],
      stdoutEvents: const <ExecutionLogEvent>[],
      stderrEvents: const <ExecutionLogEvent>[],
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

class _CountingExecutionAdapter implements ExecutionAdapter {
  int callCount = 0;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => _capabilitySnapshot;

  @override
  Future<ExecutionSession> runActiveDocument({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
  }) async {
    callCount += 1;
    return const ExecutionSession(
      sessionId: 'counting',
      kind: 'run',
      status: ExecutionSessionStatus.succeeded,
      statusMessage: 'unexpected adapter execution',
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

class _FakeDapByteTransport implements DapByteTransport {
  final StreamController<List<int>> _incoming =
      StreamController<List<int>>.broadcast();
  final List<List<int>> sentBytes = <List<int>>[];

  @override
  Stream<List<int>> get incomingBytes => _incoming.stream;

  @override
  Future<void> send(List<int> bytes) async {
    sentBytes.add(List<int>.unmodifiable(bytes));
  }

  void addInbound(List<int> bytes) {
    _incoming.add(bytes);
  }

  @override
  Future<void> close() {
    return _incoming.close();
  }
}

Future<ConfigurationStore> _createShellTestConfigurationStore(
  Directory root,
) async {
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: root.path,
      homePath: root.path,
    ),
  );
  final coordinator = FoundationResourceCoordinator(
    resourceManager: resourceManager,
    fileSystemManager: fileSystemManager,
  );
  return ConfigurationStore(
    dataStore: FoundationDataStore(
      resourceCoordinator: coordinator,
      fileSystemManager: fileSystemManager,
    ),
    credentialDataStore: InMemoryCredentialDataStore(),
  );
}

class _NoopStyioLanguageService implements StyioLanguageService {
  const _NoopStyioLanguageService({
    this.parameterInfo,
    this.analysisDiagnostics = const <Diagnostic>[],
    this.analysisInlayHints = const <InlayHint>[],
    this.analysisSemanticBlocks = const <SemanticBlockRange>[],
    this.documentSymbols = const <DocumentSymbol>[],
    this.safeDeletePlan,
    this.inlineVariablePlan,
    this.surroundTemplates = const <SurroundTemplate>[],
  });

  final ParameterInfoPayload? parameterInfo;
  final List<Diagnostic> analysisDiagnostics;
  final List<InlayHint> analysisInlayHints;
  final List<SemanticBlockRange> analysisSemanticBlocks;
  final List<DocumentSymbol> documentSymbols;
  final SafeDeletePlan? safeDeletePlan;
  final InlineVariablePlan? inlineVariablePlan;
  final List<SurroundTemplate> surroundTemplates;

  @override
  StyioDocumentAnalysis analyzeDocument(DocumentState document) {
    return StyioDocumentAnalysis(
      tokenSpans: <TokenSpan>[],
      semanticSpans: <SemanticSpan>[],
      diagnostics: analysisDiagnostics,
      formattingEdits: <FormattingEdit>[],
      semanticBlocks: analysisSemanticBlocks,
      inlayHints: analysisInlayHints,
      documentSymbols: documentSymbols,
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
      inlineVariablePlan;

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
      parameterInfo;

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
  SafeDeletePlan? safeDeleteAt(DocumentState document, int offset) =>
      safeDeletePlan;

  @override
  List<SurroundTemplate> surroundTemplatesAt(
    DocumentState document,
    SourceRange range,
  ) => surroundTemplates;
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

ProjectGraphSnapshot _multiFileProjectGraph({
  List<String> editorFiles = const <String>['src/main.styio', 'src/lib.styio'],
}) {
  return ProjectGraphSnapshot(
    id: '/workspace/demo/spio.toml',
    title: 'demo/app',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: const <String>[],
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: const <ProjectTargetDescriptor>[],
    editorFiles: editorFiles,
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'fixture',
    ),
    lockState: ProjectLockState.unknown,
    vendorState: ProjectVendorState.unknown,
    notes: const <String>[],
  );
}
