import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/dependency_source_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/deployment_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/runtime_event_adapter.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/toolchain_management_adapter.dart';
import 'package:vityo_app/src/view_ide/commands/app_commands.dart';
import 'package:vityo_app/src/view_ide/editor/controller/editor_controller.dart';
import 'package:vityo_app/src/view_ide/editor/document/document_state.dart';
import 'package:vityo_app/src/view_ide/language/contract/language_contract.dart';
import 'package:vityo_app/src/view_ide/language/service/styio_language_service.dart';
import 'package:vityo_app/src/view_ide/module_host/module_registry.dart';
import 'package:vityo_app/src/view_ide/platform/native_module_loader.dart';
import 'package:vityo_app/src/view_ide/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/shell_runtime_model.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_controller.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace_document_store.dart';

void main() {
  test(
    'executeCommand and executeCommandWithInput never throw for any AppCommandId',
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

      expect(AppCommandId.values, isNotEmpty);

      for (final commandId in AppCommandId.values) {
        await expectLater(
          shell.executeCommand(commandId),
          completes,
          reason: 'executeCommand($commandId) must not throw',
        );
        await expectLater(
          shell.executeCommandWithInput(commandId, 'sample-input'),
          completes,
          reason: 'executeCommandWithInput($commandId) must not throw',
        );
      }
    },
  );
}

const _capabilitySnapshot = AdapterCapabilitySnapshot(
  adapterKind: AdapterKind.cli,
  languageService: AdapterEndpointCapability(
    level: AdapterCapabilityLevel.unavailable,
    detail: 'not needed for dispatch totality test',
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
      statusMessage: 'not needed for dispatch totality test',
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
      statusMessage: 'not needed for dispatch totality test',
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
      statusMessage: 'not needed for dispatch totality test',
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
      statusMessage: 'not needed for dispatch totality test',
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
      statusMessage: 'not needed for dispatch totality test',
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
      statusMessage: 'not needed for dispatch totality test',
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
      statusMessage: 'not needed for dispatch totality test',
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
