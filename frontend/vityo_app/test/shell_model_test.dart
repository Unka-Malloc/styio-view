import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/frontend_shell/frontend_shell.dart';
import 'package:vityo_app/src/editor/editor_controller.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/backend_toolchain/adapter_contracts.dart';
import 'package:vityo_app/src/backend_toolchain/dependency_source_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/deployment_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/execution_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/project_graph_contract.dart';
import 'package:vityo_app/src/backend_toolchain/runtime_event_adapter.dart';
import 'package:vityo_app/src/backend_toolchain/toolchain_management_adapter.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/editor/session/editor_session_data_store.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/language/service/semantic_snapshot_event_bridge.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_catalog.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_configuration_store.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_install_executor.dart'
    show ToolchainInstallExecutionStatus;
import 'package:vityo_app/src/view_ide/toolchain/toolchain_install_policy.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_manager.dart';
import 'package:vityo_app/src/view_ide/toolchain/toolchain_resolver.dart';
import 'package:vityo_app/src/view_ide/testing/testing.dart';
import 'package:vityo_app/src/view_ide/workspace/workspace.dart';
import 'package:vityo_app/src/language/language_contract.dart';
import 'package:vityo_app/src/language/simple_styio_language_service.dart';
import 'package:vityo_app/src/module_host/module_registry.dart';
import 'package:vityo_app/src/platform/native_module_loader.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  Future<ConfigurationStore> createConfigurationStore(Directory root) async {
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: root.path,
        homePath: root.path,
      ),
    );
    return ConfigurationStore(
      dataStore: FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      ),
      credentialDataStore: InMemoryCredentialDataStore(),
    );
  }

  Future<PlatformManagerBundle> createTestPlatformManagers() {
    final context = PlatformContextSnapshot.compose(
      targetId: 'shell-toolchain-selection',
      fileSystem: FileSystemFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      shell: ShellFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
        defaultShellPath: '/bin/sh',
      ),
      process: ProcessFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      resource: ResourceFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      network: NetworkFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      clipboard: ClipboardFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      notification: NotificationFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      localService: LocalServiceFacts.linuxDebianArm(
        targetId: 'shell-toolchain-selection',
      ),
      pty: PtyFacts.linuxDebianArm(targetId: 'shell-toolchain-selection'),
    );
    return createPlatformManagerBundle(platformContext: context);
  }

  test('persists editor session through shell runtime store', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_shell_editor_session_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final dataStore = FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
    );
    final editorSessionDataStore = EditorSessionDataStore.fromDataStore(
      dataStore: dataStore,
    );
    final initialGraph = _projectGraph(
      compilerVersion: '0.0.1',
      compilePlanReady: false,
    );
    final shell = ShellModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _SequenceProjectGraphAdapter(
        snapshots: <ProjectGraphSnapshot>[initialGraph],
      ),
      workspaceController: WorkspaceController(projectSnapshot: initialGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: EditorSessionController.seedDocumentForPath(
          initialGraph.editorFiles.first,
        ),
        languageService: const SimpleStyioLanguageService(),
      ),
      executionAdapter: const _SuccessfulExecutionAdapter(
        sessionId: 'shell-editor-session',
      ),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          const _SuccessfulExecutionAdapter(sessionId: 'shell-editor-session'),
      runtimeEventAdapter: createRuntimeEventAdapter(
        platformTarget: PlatformTarget.macos,
      ),
      dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
      deploymentAdapter: const _SuccessfulDeploymentAdapter(),
      toolchainManagementAdapter: const _SuccessfulToolchainManagementAdapter(),
      editorSessionDataStore: editorSessionDataStore,
      editorSessionWorkspaceId: 'demo',
    );
    addTearDown(shell.dispose);

    shell.editorController.selectRange(baseOffset: 1, extentOffset: 4);
    await shell.persistEditorSession();
    shell.editorController.selectCollapsed(0);
    final restoredSnapshot = await shell.restoreEditorSession();

    final restored = await editorSessionDataStore.readSession(
      workspaceId: 'demo',
    );

    expect(restoredSnapshot?.activeDocumentId, initialGraph.editorFiles.first);
    expect(restored?.activeDocumentId, initialGraph.editorFiles.first);
    expect(restored?.openDocumentIds, contains(initialGraph.editorFiles.first));
    expect(restored?.cursorOffsets[initialGraph.editorFiles.first], 4);
    expect(restored?.selectionAnchors[initialGraph.editorFiles.first], 1);
    expect(shell.editorController.selection.start, 1);
    expect(shell.editorController.selection.end, 4);
    expect(
      shell.debugLog.any((entry) => entry.contains('Editor session persisted')),
      isTrue,
    );
    expect(
      shell.debugLog.any((entry) => entry.contains('Editor session restored')),
      isTrue,
    );
  });

  test(
    'shell agent context includes cached diagnostics and testing facts',
    () async {
      const documentPath = '/workspace/demo/src/main.styio';
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.1',
        compilePlanReady: false,
        editorFiles: const <String>[documentPath],
      );
      const snapshot = WorkspaceDiagnosticsSnapshot(
        providerId: 'static',
        diagnostics: <WorkspaceDiagnostic>[
          WorkspaceDiagnostic(
            documentId: documentPath,
            diagnostic: Diagnostic(
              severity: DiagnosticSeverity.warning,
              code: 'styio.shell',
              message: 'shell diagnostic',
              range: SourceRange(start: 0, end: 1),
            ),
          ),
        ],
      );
      final diagnosticsController = WorkspaceDiagnosticsController(
        provider: const StaticWorkspaceDiagnosticsProvider(
          providerId: 'static',
          snapshot: snapshot,
        ),
      );
      addTearDown(diagnosticsController.dispose);
      await diagnosticsController.refresh(
        const WorkspaceDiagnosticsRequest(documentIds: <String>[documentPath]),
      );
      final testingController = TestingSessionController(
        discoveryProvider: const StaticTestDiscoveryProvider(
          providerId: 'static-discovery',
          result: TestDiscoveryResult(
            providerId: 'static-discovery',
            roots: <TestNode>[
              TestNode(
                id: 'test:styio',
                label: 'Styio syntax',
                kind: TestNodeKind.test,
              ),
            ],
          ),
        ),
        runProvider: const StaticTestRunProvider(
          providerId: 'static-runner',
          result: TestRunResult(
            providerId: 'static-runner',
            runner: 'fixture',
            status: TestRunStatus.passed,
            message: 'Fixture tests passed.',
            totalCount: 1,
            passedCount: 1,
          ),
        ),
      );
      addTearDown(testingController.dispose);
      await testingController.discover(
        const TestDiscoveryRequest(workspaceRoot: '/workspace/demo'),
      );
      await testingController.run(
        const TestRunRequest(workspaceRoot: '/workspace/demo'),
      );
      final sourceControlController = SourceControlStatusController(
        provider: const StaticSourceControlStatusProvider(
          SourceControlStatusSnapshot(
            providerKind: SourceControlProviderKind.git,
            branchName: 'ai-dev',
            changes: <SourceControlFileChange>[
              SourceControlFileChange(
                path: documentPath,
                unstagedStatus: SourceControlFileStatus.modified,
              ),
            ],
          ),
        ),
        diffProvider: const StaticSourceControlDiffProvider(
          SourceControlDiffSnapshot(
            providerKind: SourceControlProviderKind.git,
            path: documentPath,
            unifiedDiff:
                'diff --git a/src/main.styio b/src/main.styio\n+changed\n',
          ),
        ),
        actionProvider: const _ShellSourceControlActionProvider(),
        branchProvider: const StaticSourceControlBranchProvider(
          SourceControlBranchSnapshot(
            providerKind: SourceControlProviderKind.git,
            currentBranch: 'ai-dev',
            branches: <String>['main', 'ai-dev', 'feature/scm'],
          ),
        ),
        workspaceRoot: '/workspace/demo',
      );
      addTearDown(sourceControlController.dispose);
      await sourceControlController.refresh();
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: const DocumentState(
            documentId: documentPath,
            text: '#main := () => {}',
            revision: 1,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: const _SuccessfulExecutionAdapter(
          sessionId: 'shell-diagnostics',
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            const _SuccessfulExecutionAdapter(sessionId: 'shell-diagnostics'),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
        workspaceDiagnosticsController: diagnosticsController,
        testingSessionController: testingController,
        sourceControlStatusController: sourceControlController,
      );
      addTearDown(shell.dispose);

      final workspaceJson =
          shell.agentSessionContext.toJson()['workspace']!
              as Map<String, Object?>;
      final diagnosticsJson =
          workspaceJson['diagnostics']! as Map<String, Object?>;
      final testingJson =
          shell.agentSessionContext.toJson()['testing']!
              as Map<String, Object?>;
      final sourceControlJson =
          workspaceJson['sourceControl']! as Map<String, Object?>;

      expect(shell.workspaceDiagnosticsSnapshot, same(snapshot));
      expect(diagnosticsJson['providerId'], 'static');
      expect(diagnosticsJson['totalCount'], 1);
      expect(shell.testDiscovery?.testCount, 1);
      expect(shell.lastTestRun?.status, TestRunStatus.passed);
      expect(testingJson['hasDiscovery'], isTrue);
      expect(testingJson['hasLastRun'], isTrue);
      expect(sourceControlJson['providerKind'], 'git');
      expect(sourceControlJson['branchName'], 'ai-dev');
      expect(sourceControlJson['changeCount'], 1);

      final diffPreview = await shell.previewSourceControlDiff(documentPath);
      final diffJson =
          shell.agentSessionContext.toJson()['workspace']!
              as Map<String, Object?>;
      final sourceControlDiffJson =
          diffJson['sourceControlDiff']! as Map<String, Object?>;
      expect(diffPreview.available, isTrue);
      expect(sourceControlDiffJson['path'], documentPath);
      expect(sourceControlDiffJson['unifiedDiff'], contains('+changed'));
      final diffConfirmationResult = await shell.confirmSourceControlDiffAction(
        SourceControlDiffConfirmationPlan.fromDiff(
          snapshot: diffPreview,
          kind: SourceControlActionKind.stage,
        ),
      );
      expect(diffConfirmationResult.applied, isTrue);
      expect(diffConfirmationResult.paths, <String>[documentPath]);

      final agentDiffApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(
          commandId: 'previewSourceControlDiff',
          input: documentPath,
        ),
      );
      final agentDiffResult = shell.agentSessionContext.commands.lastResult;
      expect(agentDiffApplied, isTrue);
      expect(agentDiffResult?.commandId, 'previewSourceControlDiff');
      expect(
        agentDiffResult?.metadata['sourceControlDiff'],
        isA<Map<String, Object?>>(),
      );

      final missingStageApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'stageSourceControl'),
      );
      final missingStageResult = shell.agentSessionContext.commands.lastResult;
      expect(missingStageApplied, isFalse);
      expect(missingStageResult?.commandId, 'stageSourceControl');
      expect(
        missingStageResult?.metadata['requiredInput'],
        'Changed file path(s)',
      );
      expect(
        missingStageResult?.metadata['inputContract'],
        contains('comma or newline'),
      );
      expect(
        missingStageResult?.metadata['inputExamples'],
        contains('src/a.styio, src/b.styio'),
      );

      final agentStageApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(
          commandId: 'stageSourceControl',
          input: documentPath,
        ),
      );
      final agentStageResult = shell.agentSessionContext.commands.lastResult;
      expect(agentStageApplied, isTrue);
      expect(agentStageResult?.commandId, 'stageSourceControl');
      expect(agentStageResult?.metadata['pathCount'], 1);
      final agentStageAction =
          agentStageResult?.metadata['sourceControlAction']!
              as Map<String, Object?>;
      expect(agentStageAction['kind'], 'stage');
      expect(agentStageAction['paths'], <String>[documentPath]);
      final agentStageContext =
          agentStageResult?.metadata['sourceControlContext']!
              as Map<String, Object?>;
      expect(
        (agentStageContext['lastActionResult']!
            as Map<String, Object?>)['kind'],
        'stage',
      );

      final agentUnstageApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(
          commandId: 'unstageSourceControl',
          input: documentPath,
        ),
      );
      final agentUnstageResult = shell.agentSessionContext.commands.lastResult;
      expect(agentUnstageApplied, isTrue);
      expect(agentUnstageResult?.commandId, 'unstageSourceControl');
      final agentUnstageAction =
          agentUnstageResult?.metadata['sourceControlAction']!
              as Map<String, Object?>;
      expect(agentUnstageAction['kind'], 'unstage');
      expect(agentUnstageAction['paths'], <String>[documentPath]);
      final agentUnstageContext =
          agentUnstageResult?.metadata['sourceControlContext']!
              as Map<String, Object?>;
      expect(
        (agentUnstageContext['lastActionResult']!
            as Map<String, Object?>)['kind'],
        'unstage',
      );

      final missingBranchPlanApplied = await shell
          .applyAgentIdeCommandSuggestion(
            const AgentIdeCommandSuggestion(
              commandId: 'planSourceControlBranchSwitch',
            ),
          );
      final missingBranchPlanResult =
          shell.agentSessionContext.commands.lastResult;
      expect(missingBranchPlanApplied, isFalse);
      expect(
        missingBranchPlanResult?.metadata['requiredInput'],
        'Target branch',
      );
      expect(
        missingBranchPlanResult?.metadata['inputContract'],
        contains('source-control facts'),
      );

      final agentBranchPlanApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(
          commandId: 'planSourceControlBranchSwitch',
          input: 'feature/scm',
        ),
      );
      final agentBranchPlanResult =
          shell.agentSessionContext.commands.lastResult;
      expect(agentBranchPlanApplied, isTrue);
      expect(agentBranchPlanResult?.commandId, 'planSourceControlBranchSwitch');
      final branchPlan =
          agentBranchPlanResult?.metadata['sourceControlBranchSwitchPlan']!
              as Map<String, Object?>;
      expect(branchPlan['targetBranch'], 'feature/scm');
      expect(branchPlan['canRun'], isTrue);
      final agentBranchContext =
          agentBranchPlanResult?.metadata['sourceControlContext']!
              as Map<String, Object?>;
      expect(
        (agentBranchContext['branches']!
            as Map<String, Object?>)['branchCount'],
        3,
      );
      expect(
        (agentBranchContext['pendingBranchSwitchPlan']!
            as Map<String, Object?>)['targetBranch'],
        'feature/scm',
      );

      final missingCommitDraftApplied = await shell
          .applyAgentIdeCommandSuggestion(
            const AgentIdeCommandSuggestion(
              commandId: 'planSourceControlCommitDraft',
            ),
          );
      final missingCommitDraftResult =
          shell.agentSessionContext.commands.lastResult;
      expect(missingCommitDraftApplied, isFalse);
      expect(
        missingCommitDraftResult?.metadata['requiredInput'],
        'Commit message or message -> path(s)',
      );
      expect(
        missingCommitDraftResult?.metadata['inputExamples'],
        contains('Add tests -> src/main.styio, test/main_test.dart'),
      );

      final agentCommitDraftApplied = await shell
          .applyAgentIdeCommandSuggestion(
            const AgentIdeCommandSuggestion(
              commandId: 'planSourceControlCommitDraft',
              input:
                  'Checkpoint source control -> /workspace/demo/src/main.styio',
            ),
          );
      final agentCommitDraftResult =
          shell.agentSessionContext.commands.lastResult;
      expect(agentCommitDraftApplied, isTrue);
      expect(agentCommitDraftResult?.commandId, 'planSourceControlCommitDraft');
      final commitDraft =
          agentCommitDraftResult?.metadata['sourceControlCommitDraft']!
              as Map<String, Object?>;
      final commitDialog =
          agentCommitDraftResult?.metadata['sourceControlCommitDialog']!
              as Map<String, Object?>;
      expect(commitDraft['message'], 'Checkpoint source control');
      expect(commitDraft['selectedPaths'], <String>[
        '/workspace/demo/src/main.styio',
      ]);
      expect(
        (commitDraft['commitPlan']! as Map<String, Object?>)['canRun'],
        isTrue,
      );
      expect(commitDialog['status'], 'ready');
      expect(shell.sourceControlCommitDialogState?.canSubmit, isTrue);

      testingController.recordRunResult(
        const TestRunResult(
          providerId: 'static-runner',
          runner: 'fixture',
          status: TestRunStatus.failed,
          message: 'Fixture tests failed.',
          totalCount: 1,
          failedCount: 1,
          cases: <TestCaseResult>[
            TestCaseResult(
              id: 'parser-syntax',
              name: 'parser syntax',
              status: TestRunStatus.failed,
              message: 'Expected parser success.',
            ),
          ],
        ),
      );
      final agentRerunFailedApplied = await shell
          .applyAgentIdeCommandSuggestion(
            const AgentIdeCommandSuggestion(commandId: 'rerunFailedTests'),
          );
      final agentRerunFailedResult =
          shell.agentSessionContext.commands.lastResult;
      expect(agentRerunFailedApplied, isTrue);
      expect(agentRerunFailedResult?.commandId, 'rerunFailedTests');
      final rerunFailedTestResult =
          agentRerunFailedResult?.metadata['testResult']!
              as Map<String, Object?>;
      final failedRetryHistory =
          agentRerunFailedResult?.metadata['failedRetryHistory']!
              as List<Object?>;
      expect(rerunFailedTestResult['status'], 'passed');
      expect(failedRetryHistory, hasLength(1));
      expect(shell.failedTestRetryHistory, hasLength(1));

      testingController.recordRunResult(
        const TestRunResult(
          providerId: 'static-runner',
          runner: 'fixture',
          status: TestRunStatus.failed,
          message: 'Fixture debug target failed.',
          totalCount: 1,
          failedCount: 1,
          cases: <TestCaseResult>[
            TestCaseResult(
              id: 'parser-syntax',
              name: 'parser syntax',
              status: TestRunStatus.failed,
              message: 'Expected parser success.',
            ),
          ],
        ),
      );
      final agentDebugFailedApplied = await shell
          .applyAgentIdeCommandSuggestion(
            const AgentIdeCommandSuggestion(commandId: 'debugFailedTests'),
          );
      final agentDebugFailedResult =
          shell.agentSessionContext.commands.lastResult;
      expect(agentDebugFailedApplied, isTrue);
      expect(agentDebugFailedResult?.commandId, 'debugFailedTests');
      final debugFailedTestResult =
          agentDebugFailedResult?.metadata['testResult']!
              as Map<String, Object?>;
      final debugFailedRetryHistory =
          agentDebugFailedResult?.metadata['failedRetryHistory']!
              as List<Object?>;
      expect(debugFailedTestResult['status'], 'passed');
      expect(debugFailedRetryHistory, hasLength(2));
      expect(
        (debugFailedRetryHistory.first! as Map<String, Object?>)['debug'],
        isTrue,
      );
      expect(shell.failedTestRetryHistory, hasLength(2));

      final missingRunConfigurationApplied = await shell
          .applyAgentIdeCommandSuggestion(
            const AgentIdeCommandSuggestion(commandId: 'runTestConfiguration'),
          );
      final missingRunConfigurationResult =
          shell.agentSessionContext.commands.lastResult;
      expect(missingRunConfigurationApplied, isFalse);
      expect(
        missingRunConfigurationResult?.metadata['availableConfigurationIds'],
        <String>['all-tests'],
      );

      final agentRunConfigurationApplied = await shell
          .applyAgentIdeCommandSuggestion(
            const AgentIdeCommandSuggestion(
              commandId: 'runTestConfiguration',
              input: 'all-tests',
            ),
          );
      final agentRunConfigurationResult =
          shell.agentSessionContext.commands.lastResult;
      expect(agentRunConfigurationApplied, isTrue);
      expect(agentRunConfigurationResult?.commandId, 'runTestConfiguration');
      final runConfiguration =
          agentRunConfigurationResult?.metadata['configuration']!
              as Map<String, Object?>;
      final runConfigurationResult =
          agentRunConfigurationResult?.metadata['testResult']!
              as Map<String, Object?>;
      expect(runConfiguration['id'], 'all-tests');
      expect(runConfigurationResult['status'], 'passed');

      final agentDebugConfigurationApplied = await shell
          .applyAgentIdeCommandSuggestion(
            const AgentIdeCommandSuggestion(
              commandId: 'debugTestConfiguration',
              input: 'all-tests',
            ),
          );
      final agentDebugConfigurationResult =
          shell.agentSessionContext.commands.lastResult;
      expect(agentDebugConfigurationApplied, isTrue);
      expect(
        agentDebugConfigurationResult?.commandId,
        'debugTestConfiguration',
      );
      final debugConfiguration =
          agentDebugConfigurationResult?.metadata['configuration']!
              as Map<String, Object?>;
      expect(debugConfiguration['id'], 'all-tests');

      await shell.executeCommand(AppCommandId.collectAgentCodingCheckpoint);
      final checkpointCommandResult =
          shell.agentSessionContext.commands.lastResult;
      expect(
        checkpointCommandResult?.commandId,
        'collectAgentCodingCheckpoint',
      );
      expect(checkpointCommandResult?.applied, isTrue);
      expect(
        checkpointCommandResult?.metadata['workspaceDiagnostics'],
        isA<Map<String, Object?>>(),
      );
      expect(
        checkpointCommandResult?.metadata['sourceControl'],
        isA<Map<String, Object?>>(),
      );
      expect(
        checkpointCommandResult?.metadata['sourceControlDiff'],
        isA<Map<String, Object?>>(),
      );
      expect(
        checkpointCommandResult?.metadata['projectLanguage'],
        isA<Map<String, Object?>>(),
      );
      expect(
        checkpointCommandResult?.metadata['agentContextSchemaVersion'],
        69,
      );
      expect(
        checkpointCommandResult?.metadata['sourceControlContext'],
        isA<Map<String, Object?>>(),
      );
      expect(
        checkpointCommandResult?.metadata['languageServiceStatus'],
        isA<Map<String, Object?>>(),
      );
      expect(
        checkpointCommandResult?.metadata['testing'],
        isA<Map<String, Object?>>(),
      );
      expect(
        (checkpointCommandResult?.metadata['sourceControlContext']!
            as Map<String, Object?>)['unstagedPaths'],
        contains(documentPath),
      );
      final checkpointSourceControlContext =
          checkpointCommandResult?.metadata['sourceControlContext']!
              as Map<String, Object?>;
      final lastSourceControlAction =
          checkpointSourceControlContext['lastActionResult']!
              as Map<String, Object?>;
      expect(lastSourceControlAction['kind'], 'unstage');
      expect(lastSourceControlAction['applied'], isTrue);
      expect(lastSourceControlAction['message'], contains('/workspace/demo'));

      final agentCheckpointApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(
          commandId: 'collectAgentCodingCheckpoint',
        ),
      );
      final agentCheckpointResult =
          shell.agentSessionContext.commands.lastResult;
      expect(agentCheckpointApplied, isTrue);
      expect(agentCheckpointResult?.commandId, 'collectAgentCodingCheckpoint');
      expect(
        agentCheckpointResult?.metadata['projectLanguage'],
        isA<Map<String, Object?>>(),
      );
      expect(
        agentCheckpointResult?.metadata['sourceControlContext'],
        isA<Map<String, Object?>>(),
      );

      await shell.executeCommand(AppCommandId.refreshWorkspaceDiagnostics);
      final diagnosticsCommandResult =
          shell.agentSessionContext.commands.lastResult;
      expect(
        diagnosticsCommandResult?.commandId,
        'refreshWorkspaceDiagnostics',
      );
      expect(diagnosticsCommandResult?.applied, isTrue);
      expect(
        diagnosticsCommandResult?.metadata['workspaceDiagnostics'],
        isA<Map<String, Object?>>(),
      );
      expect(
        shell.semanticProblemsPanelViewModel?.diagnosticEventCount,
        greaterThanOrEqualTo(1),
      );

      final agentDiagnosticsApplied = await shell
          .applyAgentIdeCommandSuggestion(
            const AgentIdeCommandSuggestion(
              commandId: 'refreshWorkspaceDiagnostics',
            ),
          );
      final agentDiagnosticsResult =
          shell.agentSessionContext.commands.lastResult;
      expect(agentDiagnosticsApplied, isTrue);
      expect(agentDiagnosticsResult?.commandId, 'refreshWorkspaceDiagnostics');
      expect(
        agentDiagnosticsResult?.message,
        contains('Workspace diagnostics refreshed'),
      );

      await shell.executeCommand(AppCommandId.refreshSourceControl);
      final refreshCommandResult =
          shell.agentSessionContext.commands.lastResult;
      expect(refreshCommandResult?.commandId, 'refreshSourceControl');
      expect(refreshCommandResult?.applied, isTrue);
      expect(
        refreshCommandResult?.metadata['sourceControl'],
        isA<Map<String, Object?>>(),
      );

      final agentRefreshApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'refreshSourceControl'),
      );
      final agentRefreshResult = shell.agentSessionContext.commands.lastResult;
      expect(agentRefreshApplied, isTrue);
      expect(agentRefreshResult?.commandId, 'refreshSourceControl');
      expect(agentRefreshResult?.message, contains('Source control refreshed'));

      await shell.executeCommand(AppCommandId.stageSourceControl);
      final directStageResult = shell.agentSessionContext.commands.lastResult;
      expect(directStageResult?.commandId, 'stageSourceControl');
      expect(directStageResult?.applied, isFalse);
      expect(
        directStageResult?.metadata['requiredInput'],
        'Changed file path(s)',
      );
      expect(
        directStageResult?.metadata['inputContract'],
        contains('comma or newline'),
      );

      await shell.executeCommand(AppCommandId.previewQuickFix);
      final semanticLanguageJson =
          shell.agentSessionContext.toJson()['language']!
              as Map<String, Object?>;
      expect(shell.semanticProblemsPanelViewModel?.codeActionCount, 1);
      expect(semanticLanguageJson['semanticPanelViewModelCount'], 1);

      shell.editorController.selectCollapsed(
        shell.editorController.document.length,
      );
      shell.editorController.insertText('\n#agent_save := 1');
      expect(shell.dirtyDocumentPaths, contains(documentPath));

      final agentSaveApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'save'),
      );
      final agentSaveResult = shell.agentSessionContext.commands.lastResult;
      expect(agentSaveApplied, isTrue);
      expect(agentSaveResult?.commandId, 'save');
      expect(agentSaveResult?.metadata['bindingState'], 'boundClean');
      expect(shell.dirtyDocumentPaths, isNot(contains(documentPath)));

      shell.editorController.insertText('\n#agent_save_all := 1');
      expect(shell.dirtyDocumentPaths, contains(documentPath));
      final agentSaveAllApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(
          commandId: 'saveAll',
          prerequisiteForCommandId: 'runTests',
        ),
      );
      final agentSaveAllResult = shell.agentSessionContext.commands.lastResult;
      expect(agentSaveAllApplied, isTrue);
      expect(agentSaveAllResult?.commandId, 'saveAll');
      expect(
        agentSaveAllResult?.metadata['savedDocumentIds'],
        contains(documentPath),
      );
      expect(
        agentSaveAllResult?.metadata['completedRequiredCommandFor'],
        'runTests',
      );
      expect(shell.dirtyDocumentPaths, isNot(contains(documentPath)));
    },
  );

  test('hydrates semantic panel events through shell runtime store', () async {
    const documentPath = '/workspace/demo/src/main.styio';
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_shell_semantic_panel_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final dataStore = FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
    );
    final semanticPanelStore = SemanticSnapshotPanelEventStore.fromDataStore(
      dataStore: dataStore,
    );
    final initialGraph = _projectGraph(
      compilerVersion: '0.0.1',
      compilePlanReady: false,
      editorFiles: const <String>[documentPath],
    );
    await semanticPanelStore.recordEvent(
      workspaceId: 'demo',
      event: SemanticSnapshotPanelEvent(
        target: SemanticSnapshotPanelEventTarget.problems,
        kind: SemanticSnapshotTelemetryEventKind.codeActionDiscovery,
        documentId: documentPath,
        message: 'Fixture quick fix facts are available.',
        payload: const <String, Object?>{'actionCount': 1},
        timestamp: DateTime.utc(2026, 5, 20, 1),
      ),
    );
    final shell = ShellModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _SequenceProjectGraphAdapter(
        snapshots: <ProjectGraphSnapshot>[initialGraph],
      ),
      workspaceController: WorkspaceController(projectSnapshot: initialGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: const DocumentState(
          documentId: documentPath,
          text: '#main := () => {}',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      ),
      executionAdapter: const _SuccessfulExecutionAdapter(
        sessionId: 'shell-semantic-panel',
      ),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          const _SuccessfulExecutionAdapter(sessionId: 'shell-semantic-panel'),
      runtimeEventAdapter: createRuntimeEventAdapter(
        platformTarget: PlatformTarget.macos,
      ),
      dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
      deploymentAdapter: const _SuccessfulDeploymentAdapter(),
      toolchainManagementAdapter: const _SuccessfulToolchainManagementAdapter(),
      semanticPanelEventStore: semanticPanelStore,
      semanticPanelEventWorkspaceId: 'demo',
    );
    addTearDown(shell.dispose);

    final restoredStates = await shell.restoreSemanticPanelEvents();
    final languageJson =
        shell.agentSessionContext.toJson()['language']! as Map<String, Object?>;

    expect(
      restoredStates.length,
      SemanticSnapshotPanelEventTarget.values.length,
    );
    expect(shell.semanticProblemsPanelViewModel?.itemCount, 1);
    expect(languageJson['semanticPanelViewModelCount'], 1);
    expect(languageJson['semanticPanelViewModels'], isA<List<Object?>>());

    await shell.recordSemanticPanelEvent(
      SemanticSnapshotPanelEvent(
        target: SemanticSnapshotPanelEventTarget.refactor,
        kind: SemanticSnapshotTelemetryEventKind.renameSafety,
        documentId: documentPath,
        message: 'Rename main to appMain is safe.',
        payload: const <String, Object?>{
          'safe': true,
          'targetName': 'main',
          'newName': 'appMain',
        },
        timestamp: DateTime.utc(2026, 5, 20, 2),
      ),
    );
    final storedRefactor = await semanticPanelStore.readState(
      workspaceId: 'demo',
      target: SemanticSnapshotPanelEventTarget.refactor,
    );
    final updatedLanguageJson =
        shell.agentSessionContext.toJson()['language']! as Map<String, Object?>;

    expect(shell.semanticRefactorPanelViewModel?.renameSafetyCount, 1);
    expect(storedRefactor.events.single.message, contains('safe'));
    expect(updatedLanguageJson['semanticPanelViewModelCount'], 2);
  });

  test('hydrates quick-fix telemetry through shell runtime store', () async {
    const documentPath = '/workspace/demo/src/main.styio';
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_shell_quick_fix_telemetry_test_',
    );
    addTearDown(() => tempRoot.delete(recursive: true));
    final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
    final resourceManager = LocalResourceManager(
      facts: ResourceFacts.linuxDebianArm(
        systemTempPath: tempRoot.path,
        homePath: tempRoot.path,
      ),
    );
    final dataStore = FoundationDataStore(
      resourceCoordinator: FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      ),
      fileSystemManager: fileSystemManager,
    );
    final telemetryStore = WorkspaceQuickFixTelemetryStore.fromDataStore(
      dataStore: dataStore,
    );
    await telemetryStore.recordOutcome(
      outcome: WorkspaceQuickFixReviewOutcome(
        workspaceId: 'demo',
        producerId: 'styio-service',
        documentId: documentPath,
        diagnosticCode: 'missing-assignment',
        quickFixIndex: 0,
        planId: 'quick-fix.src/main.styio.missing-assignment.0',
        outcomeKind: WorkspaceQuickFixReviewOutcomeKind.applied,
        confirmationStatus: WorkspaceQuickFixConfirmationStatus.ready,
        ready: true,
        message: 'Applied assignment fix.',
        affectedDocumentIds: const <String>[documentPath],
        timestamp: DateTime.utc(2026, 5, 20, 3),
      ),
    );
    final initialGraph = _projectGraph(
      compilerVersion: '0.0.1',
      compilePlanReady: false,
      editorFiles: const <String>[documentPath],
    );
    final shell = ShellModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _SequenceProjectGraphAdapter(
        snapshots: <ProjectGraphSnapshot>[initialGraph],
      ),
      workspaceController: WorkspaceController(projectSnapshot: initialGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: const DocumentState(
          documentId: documentPath,
          text: '#main := () => {}',
          revision: 1,
        ),
        languageService: const SimpleStyioLanguageService(),
      ),
      executionAdapter: const _SuccessfulExecutionAdapter(
        sessionId: 'shell-quick-fix-telemetry',
      ),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          const _SuccessfulExecutionAdapter(
            sessionId: 'shell-quick-fix-telemetry',
          ),
      runtimeEventAdapter: createRuntimeEventAdapter(
        platformTarget: PlatformTarget.macos,
      ),
      dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
      deploymentAdapter: const _SuccessfulDeploymentAdapter(),
      toolchainManagementAdapter: const _SuccessfulToolchainManagementAdapter(),
      workspaceQuickFixTelemetryStore: telemetryStore,
      workspaceQuickFixTelemetryWorkspaceId: 'demo',
    );
    addTearDown(shell.dispose);

    final restored = await shell.restoreWorkspaceQuickFixTelemetry();

    expect(restored.outcomes.single.diagnosticCode, 'missing-assignment');
    expect(shell.workspaceQuickFixTelemetrySnapshot?.appliedCount, 1);
    final recorded = await shell.recordWorkspaceQuickFixOutcome(
      WorkspaceQuickFixReviewOutcome(
        workspaceId: 'demo',
        producerId: 'styio-service',
        documentId: documentPath,
        diagnosticCode: 'unused-value',
        quickFixIndex: 1,
        planId: 'quick-fix.src/main.styio.unused-value.1',
        outcomeKind: WorkspaceQuickFixReviewOutcomeKind.blocked,
        confirmationStatus:
            WorkspaceQuickFixConfirmationStatus.blockedNoPreview,
        ready: false,
        message: 'Preview required before apply.',
        timestamp: DateTime.utc(2026, 5, 20, 4),
      ),
    );

    expect(recorded.outcomes.length, 2);
    expect(recorded.blockedCount, 1);
    expect(
      (await telemetryStore.readSnapshot(workspaceId: 'demo')).outcomes.length,
      2,
    );
  });

  test(
    'go to definition opens project definition across workspace documents',
    () async {
      const mainPath = '/workspace/demo/src/main.styio';
      const libPath = '/workspace/demo/src/lib/math.styio';
      final mainText = File(
        'test/fixtures/styio_language/project_definition/main.true.styio',
      ).readAsStringSync();
      final libText = File(
        'test/fixtures/styio_language/project_definition/lib_math.true.styio',
      ).readAsStringSync();
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
        editorFiles: const <String>[mainPath, libPath],
      );
      final workspaceDocumentStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: <String, DocumentState>{
          mainPath: DocumentState(
            documentId: mainPath,
            text: mainText,
            revision: 1,
          ),
          libPath: DocumentState(
            documentId: libPath,
            text: libText,
            revision: 1,
          ),
        },
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: workspaceDocumentStore,
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: DocumentState(
            documentId: mainPath,
            text: mainText,
            revision: 1,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: const _SuccessfulExecutionAdapter(
          sessionId: 'shell-project-definition',
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            const _SuccessfulExecutionAdapter(
              sessionId: 'shell-project-definition',
            ),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      shell.editorController.selectCollapsed(mainText.indexOf('blend()') + 1);

      await shell.executeCommand(AppCommandId.goToDefinition);

      final definitionStart = libText.indexOf('blend');
      expect(shell.workspaceController.activeFilePath, libPath);
      expect(shell.editorController.document.documentId, libPath);
      expect(shell.editorController.selection.start, definitionStart);
      expect(
        shell.editorController.selection.end,
        definitionStart + 'blend'.length,
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Project definition selected: blend'),
        ),
        isTrue,
      );

      final diagnosticStart = mainText.indexOf('value');
      final diagnosticSelected = await shell.selectWorkspaceDiagnostic(
        WorkspaceDiagnostic(
          documentId: mainPath,
          diagnostic: Diagnostic(
            severity: DiagnosticSeverity.warning,
            code: 'workspace-test',
            message: 'Workspace diagnostic selection test.',
            range: SourceRange(
              start: diagnosticStart,
              end: diagnosticStart + 'value'.length,
            ),
          ),
        ),
      );

      expect(diagnosticSelected, isTrue);
      expect(shell.workspaceController.activeFilePath, mainPath);
      expect(shell.editorController.document.documentId, mainPath);
      expect(shell.editorController.selection.start, diagnosticStart);
      expect(
        shell.editorController.selection.end,
        diagnosticStart + 'value'.length,
      );
    },
  );

  test(
    'next reference opens project references across workspace documents',
    () async {
      const mainPath = '/workspace/demo/src/main.styio';
      const libPath = '/workspace/demo/src/lib/math.styio';
      final mainText = File(
        'test/fixtures/styio_language/project_definition/main.true.styio',
      ).readAsStringSync();
      final libText = File(
        'test/fixtures/styio_language/project_definition/lib_math.true.styio',
      ).readAsStringSync();
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
        editorFiles: const <String>[mainPath, libPath],
      );
      final workspaceDocumentStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: <String, DocumentState>{
          mainPath: DocumentState(
            documentId: mainPath,
            text: mainText,
            revision: 1,
          ),
          libPath: DocumentState(
            documentId: libPath,
            text: libText,
            revision: 1,
          ),
        },
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: workspaceDocumentStore,
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: DocumentState(
            documentId: mainPath,
            text: mainText,
            revision: 1,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: const _SuccessfulExecutionAdapter(
          sessionId: 'shell-project-references',
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            const _SuccessfulExecutionAdapter(
              sessionId: 'shell-project-references',
            ),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      shell.editorController.selectCollapsed(mainText.indexOf('blend()') + 1);

      await shell.executeCommand(AppCommandId.collectProjectLanguageContext);
      final projectLanguage =
          shell
                  .agentSessionContext
                  .commands
                  .lastResult
                  ?.metadata['projectLanguage']
              as Map<String, Object?>;
      final hover = projectLanguage['hover']! as Map<String, Object?>;
      final languageServiceStatus =
          projectLanguage['languageServiceStatus']! as Map<String, Object?>;
      expect(projectLanguage['definitionCount'], 1);
      expect(projectLanguage['referenceCount'], 2);
      expect(
        projectLanguage['suggestedCommandIds'],
        contains('goToDefinition'),
      );
      expect(
        projectLanguage['suggestedCommandIds'],
        contains('nextReference'),
      );
      expect(languageServiceStatus['severity'], isA<String>());
      expect(
        shell.semanticProblemsPanelViewModel?.semanticTokenEventCount,
        greaterThanOrEqualTo(1),
      );
      expect(hover['label'], contains('function blend'));
      expect(
        shell.projectHoverAtSelection?.markdown,
        contains('function blend'),
      );
      expect(
        shell.mergedHoverAtSelection?.markdown,
        contains('function blend'),
      );
      expect(
        shell.mergedCompletionsAtSelection.map(
          (completion) => completion.label,
        ),
        contains('blend'),
      );

      await shell.executeCommand(AppCommandId.nextReference);

      final definitionStart = libText.indexOf('blend');
      expect(shell.workspaceController.activeFilePath, libPath);
      expect(shell.editorController.document.documentId, libPath);
      expect(shell.editorController.selection.start, definitionStart);
      expect(
        shell.editorController.selection.end,
        definitionStart + 'blend'.length,
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Project reference selected: blend'),
        ),
        isTrue,
      );
    },
  );

  test(
    'rename symbol applies project edits across workspace documents',
    () async {
      const mainPath = '/workspace/demo/src/main.styio';
      const libPath = '/workspace/demo/src/lib/math.styio';
      final mainText = File(
        'test/fixtures/styio_language/project_definition/main.true.styio',
      ).readAsStringSync();
      final libText = File(
        'test/fixtures/styio_language/project_definition/lib_math.true.styio',
      ).readAsStringSync();
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
        editorFiles: const <String>[mainPath, libPath],
      );
      final workspaceDocumentStore = InMemoryWorkspaceDocumentStore(
        seededDocuments: <String, DocumentState>{
          mainPath: DocumentState(
            documentId: mainPath,
            text: mainText,
            revision: 1,
          ),
          libPath: DocumentState(
            documentId: libPath,
            text: libText,
            revision: 1,
          ),
        },
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: workspaceDocumentStore,
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: DocumentState(
            documentId: mainPath,
            text: mainText,
            revision: 1,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: const _SuccessfulExecutionAdapter(
          sessionId: 'shell-project-rename',
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            const _SuccessfulExecutionAdapter(
              sessionId: 'shell-project-rename',
            ),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      shell.editorController.selectCollapsed(mainText.indexOf('blend()') + 1);

      final applied = await shell.renameSymbolAtSelection('combine');
      final renamedLibrary = await workspaceDocumentStore.loadDocument(libPath);

      expect(applied, isTrue);
      expect(shell.editorController.document.text, contains('combine()'));
      expect(shell.editorController.document.text, isNot(contains('blend()')));
      expect(renamedLibrary.text, contains('#combine := () =>'));
      expect(renamedLibrary.text, isNot(contains('#blend := () =>')));
      expect(shell.dirtyDocumentPaths, contains(mainPath));
      expect(shell.semanticRefactorPanelViewModel?.renameSafetyCount, 1);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Project rename applied: blend -> combine'),
        ),
        isTrue,
      );
    },
  );

  test('apply quick fix falls back to project workspace quick fixes', () async {
    const mainPath = '/workspace/demo/src/main.styio';
    final mainText = File(
      'test/fixtures/workspace_diagnostics/duplicate_import.true.styio',
    ).readAsStringSync();
    final initialGraph = _projectGraph(
      compilerVersion: '0.0.5',
      compilePlanReady: true,
      editorFiles: const <String>[mainPath],
    );

    ShellModel createShell(String sessionId) {
      return ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: <String, DocumentState>{
            mainPath: DocumentState(
              documentId: mainPath,
              text: mainText,
              revision: 1,
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
          initialDocument: DocumentState(
            documentId: mainPath,
            text: mainText,
            revision: 1,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _SuccessfulExecutionAdapter(sessionId: sessionId),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _SuccessfulExecutionAdapter(sessionId: sessionId),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
    }

    final commandShell = createShell('shell-project-workspace-fix-command');
    addTearDown(commandShell.dispose);
    await commandShell.executeCommand(AppCommandId.collectProjectLanguageContext);
    final projectLanguage =
        commandShell
                .agentSessionContext
                .commands
                .lastResult
                ?.metadata['projectLanguage']
            as Map<String, Object?>;
    expect(projectLanguage['diagnosticCount'], greaterThan(0));
    expect(projectLanguage['workspaceQuickFixCount'], greaterThan(0));
    expect(
      projectLanguage['suggestedCommandIds'],
      contains('previewQuickFix'),
    );
    expect(
      projectLanguage['suggestedCommandIds'],
      contains('applyQuickFix'),
    );
    expect(
      (projectLanguage['workspaceQuickFixes']! as List<Object?>).first,
      isA<Map<String, Object?>>(),
    );
    final fixes = await commandShell.collectProjectWorkspaceQuickFixes();
    expect(fixes.map((fix) => fix.label), contains('Clean up project imports'));
    final preview = await commandShell.previewFirstProjectWorkspaceQuickFix();
    expect(preview?.summary, 'Clean up project imports');
    expect(preview?.editCount, greaterThan(0));
    expect(commandShell.lastWorkspaceEditPreview, same(preview));
    final previewPlanId = preview?.planId;
    await commandShell.executeCommand(AppCommandId.previewQuickFix);
    final previewResult = commandShell.agentSessionContext.commands.lastResult;
    expect(previewResult?.commandId, 'previewQuickFix');
    expect(previewResult?.applied, isTrue);
    expect(commandShell.semanticProblemsPanelViewModel?.codeActionCount, 1);
    expect(
      previewResult?.metadata['workspaceEditPreview'],
      isA<Map<String, Object?>>(),
    );
    final checkpoint = await commandShell.collectAgentCodingCheckpoint();
    final workspaceEditPreview =
        checkpoint['workspaceEditPreview']! as Map<String, Object?>;
    expect(workspaceEditPreview['planId'], previewPlanId);
    expect(workspaceEditPreview['summary'], 'Clean up project imports');
    expect(workspaceEditPreview['editCount'], greaterThan(0));
    final agentWorkspaceEditJson =
        commandShell.agentSessionContext.toJson()['agent']!
            as Map<String, Object?>;
    final stableWorkspaceEdit =
        agentWorkspaceEditJson['workspaceEdit']! as Map<String, Object?>;
    final stablePreview =
        stableWorkspaceEdit['preview']! as Map<String, Object?>;
    final stableConfirmation =
        stablePreview['confirmationPlan']! as Map<String, Object?>;
    expect(stableWorkspaceEdit['hasPreview'], isTrue);
    expect(stablePreview['summary'], 'Clean up project imports');
    expect(stableConfirmation['riskLevel'], 'low');
    expect(stableConfirmation['blockingReasons'], isEmpty);

    await commandShell.executeCommand(AppCommandId.applyQuickFix);

    expect(commandShell.lastWorkspaceEditApplyResult?.successful, isTrue);
    expect(commandShell.semanticProblemsPanelViewModel?.codeActionCount, 2);
    expect(
      commandShell.lastWorkspaceEditApplyResult?.appliedEditCount,
      greaterThan(0),
    );
    expect(
      commandShell.lastWorkspaceEditApplyResult?.appliedDocumentIds,
      contains(mainPath),
    );
    expect(commandShell.lastWorkspaceEditPreview?.planId, previewPlanId);
    final stableAppliedWorkspaceEdit =
        commandShell.agentSessionContext.toJson()['agent']!
            as Map<String, Object?>;
    final stableAppliedResult =
        (stableAppliedWorkspaceEdit['workspaceEdit']!
                as Map<String, Object?>)['lastApplyResult']!
            as Map<String, Object?>;
    expect(stableAppliedResult['successful'], isTrue);
    expect(stableAppliedResult['appliedDocumentIds'], contains(mainPath));
    expect(commandShell.editorController.document.text, contains('@import'));
    expect(
      '@import'.allMatches(commandShell.editorController.document.text),
      hasLength(1),
    );
    expect(commandShell.dirtyDocumentPaths, contains(mainPath));

    final gatedAgentShell = createShell(
      'shell-project-workspace-fix-agent-gated',
    );
    addTearDown(gatedAgentShell.dispose);
    final gatedApply = await gatedAgentShell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(commandId: 'applyQuickFix'),
    );
    final gatedResult = gatedAgentShell.agentSessionContext.commands.lastResult;
    final gatedPreview =
        gatedResult?.metadata['workspaceEditPreview'] as Map<String, Object?>?;
    final gatedConfirmation =
        gatedPreview?['confirmationPlan'] as Map<String, Object?>?;
    expect(gatedApply, isFalse);
    expect(gatedResult?.metadata['requiredCommand'], 'previewQuickFix');
    expect(gatedResult?.message, contains('requires previewQuickFix'));
    expect(gatedConfirmation?['riskLevel'], 'low');

    final staleAgentShell = createShell(
      'shell-project-workspace-fix-agent-stale',
    );
    addTearDown(staleAgentShell.dispose);
    final stalePreview = await staleAgentShell
        .previewFirstProjectWorkspaceQuickFix();
    final staleApply = await staleAgentShell.applyFirstProjectWorkspaceQuickFix(
      expectedPreviewPlanId: 'project-workspace-fix-stale',
    );
    expect(stalePreview, isNotNull);
    expect(staleApply, isFalse);
    expect(
      staleAgentShell.lastWorkspaceEditPreview?.planId,
      stalePreview?.planId,
    );
    expect(staleAgentShell.lastWorkspaceEditApplyResult?.successful, isFalse);
    expect(
      staleAgentShell.lastWorkspaceEditApplyResult?.message,
      contains('preview is stale'),
    );

    final agentShell = createShell('shell-project-workspace-fix-agent');
    addTearDown(agentShell.dispose);
    final previewApplied = await agentShell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(commandId: 'previewQuickFix'),
    );
    expect(previewApplied, isTrue);
    final agentPreviewPlanId = agentShell.lastWorkspaceEditPreview?.planId;
    expect(
      agentShell
          .agentSessionContext
          .commands
          .lastResult
          ?.metadata['workspaceEditPreview'],
      isA<Map<String, Object?>>(),
    );
    final applied = await agentShell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(commandId: 'applyQuickFix'),
    );

    expect(applied, isTrue);
    expect(agentShell.lastWorkspaceEditPreview?.planId, agentPreviewPlanId);
    expect(
      agentShell.agentSessionContext.commands.lastResult?.message,
      contains('project workspace fix'),
    );
    expect(
      '@import'.allMatches(agentShell.editorController.document.text),
      hasLength(1),
    );
  });

  test(
    'restores editor session active document through workspace route',
    () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'vityo-editor-session-restore-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempDir.path,
          homePath: tempDir.path,
        ),
      );
      final dataStore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      final editorSessionDataStore = EditorSessionDataStore.fromDataStore(
        dataStore: dataStore,
      );
      const firstDocumentPath = '/workspace/demo/src/main.styio';
      const secondDocumentPath = '/workspace/demo/src/feature.styio';
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.1',
        compilePlanReady: false,
        editorFiles: const <String>[firstDocumentPath, secondDocumentPath],
      );
      await editorSessionDataStore.saveSession(
        workspaceId: 'demo',
        snapshot: const EditorSessionSnapshot(
          activeDocumentId: secondDocumentPath,
          openDocumentIds: <String>[firstDocumentPath, secondDocumentPath],
          dirtyDocumentIds: <String>[firstDocumentPath],
          cursorOffsets: <String, int>{
            firstDocumentPath: 5,
            secondDocumentPath: 4,
          },
          selectionAnchors: <String, int>{
            firstDocumentPath: 2,
            secondDocumentPath: 1,
          },
        ),
      );
      final workspaceController = WorkspaceController(
        projectSnapshot: initialGraph,
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: workspaceController,
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(
          seededDocuments: <String, DocumentState>{
            secondDocumentPath: const DocumentState(
              documentId: secondDocumentPath,
              text: 'feature',
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
          initialDocument: EditorSessionController.seedDocumentForPath(
            firstDocumentPath,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: const _SuccessfulExecutionAdapter(
          sessionId: 'shell-editor-session-restore',
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            const _SuccessfulExecutionAdapter(
              sessionId: 'shell-editor-session-restore',
            ),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
        editorSessionDataStore: editorSessionDataStore,
        editorSessionWorkspaceId: 'demo',
      );
      addTearDown(shell.dispose);

      final restoredSnapshot = await shell.restoreEditorSession();

      expect(restoredSnapshot?.activeDocumentId, secondDocumentPath);
      expect(shell.dirtyDocumentPaths, <String>[firstDocumentPath]);
      expect(workspaceController.openFilePaths, <String>[
        firstDocumentPath,
        secondDocumentPath,
      ]);
      expect(workspaceController.activeFilePath, secondDocumentPath);
      expect(shell.editorController.document.documentId, secondDocumentPath);
      expect(shell.editorController.selection.start, 1);
      expect(shell.editorController.selection.end, 4);

      workspaceController.openFile(firstDocumentPath);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(shell.editorController.document.documentId, firstDocumentPath);
      expect(shell.editorController.selection.start, 2);
      expect(shell.editorController.selection.end, 5);

      shell.editorController.selectRange(baseOffset: 0, extentOffset: 3);
      workspaceController.openFile(secondDocumentPath);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      workspaceController.openFile(firstDocumentPath);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(shell.editorController.document.documentId, firstDocumentPath);
      expect(shell.editorController.selection.start, 0);
      expect(shell.editorController.selection.end, 3);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Editor session restored'),
        ),
        isTrue,
      );
    },
  );

  test(
    'successful toolchain switch refreshes project graph and execution route',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.1',
        compilePlanReady: false,
      );
      final refreshedGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      const requirement = ToolchainRequirement(kind: ToolchainKind.runner);
      final toolchainReport = ValueNotifier<ToolchainManagerStatusReport>(
        const ToolchainManagerStatusReport(
          status: ToolchainManagerStatus.ready,
          snapshot: ToolchainStateSnapshot(
            targetId: 'shell-model',
            workspaceId: 'demo',
            entries: <ToolchainStateEntry>[
              ToolchainStateEntry(
                id: 'styio-runner',
                kind: ToolchainKind.runner,
                displayName: 'Styio Runner',
                executablePath: '/opt/styio/bin/styio',
                active: true,
                version: '0.0.8',
                channel: 'nightly',
              ),
            ],
          ),
          requirement: requirement,
          resolution: ToolchainResolution(
            status: ToolchainResolutionStatus.resolved,
            requirement: requirement,
            descriptor: ToolchainDescriptor(
              id: 'styio-runner',
              kind: ToolchainKind.runner,
              displayName: 'Styio Runner',
              executablePath: '/opt/styio/bin/styio',
              version: '0.0.8',
              channel: 'nightly',
            ),
          ),
        ),
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[refreshedGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _RefreshAwareExecutionAdapter(
          projectGraph: initialGraph,
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
        toolchainStatusReport: toolchainReport,
      );
      addTearDown(toolchainReport.dispose);
      addTearDown(shell.dispose);

      final result = await shell.useManagedCompiler(
        compilerVersion: '0.0.5',
        channel: 'stable',
      );

      expect(result.succeeded, isTrue);
      expect(
        shell.workspaceController.activeProject.activeCompiler?.compilerVersion,
        '0.0.5',
      );
      final cliCapability = shell.adapterCapabilities.firstWhere(
        (snapshot) => snapshot.adapterKind == AdapterKind.cli,
      );
      expect(cliCapability.execution.level, AdapterCapabilityLevel.available);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Project graph refreshed'),
        ),
        isTrue,
      );
      expect(shell.toolchainStatusSurface.source, 'manager-report');
      expect(shell.toolchainStatusSurface.version, '0.0.8');
    },
  );

  test('successful publish preflight is stored as deployment state', () async {
    final initialGraph = _projectGraph(
      compilerVersion: '0.0.5',
      compilePlanReady: true,
    );
    final shell = ShellModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _SequenceProjectGraphAdapter(
        snapshots: <ProjectGraphSnapshot>[initialGraph],
      ),
      workspaceController: WorkspaceController(projectSnapshot: initialGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: EditorSessionController.seedDocumentForPath(
          initialGraph.editorFiles.first,
        ),
        languageService: const SimpleStyioLanguageService(),
      ),
      executionAdapter: _RefreshAwareExecutionAdapter(
        projectGraph: initialGraph,
      ),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
      runtimeEventAdapter: createRuntimeEventAdapter(
        platformTarget: PlatformTarget.macos,
      ),
      dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
      deploymentAdapter: const _SuccessfulDeploymentAdapter(),
      toolchainManagementAdapter: const _SuccessfulToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    final result = await shell.preparePublish(packageName: 'demo/app');

    expect(result.succeeded, isTrue);
    expect(shell.lastDeploymentCommand, same(result));
    expect(
      shell.debugLog.any((entry) => entry.contains('deploy package: demo/app')),
      isTrue,
    );
    expect(
      shell.debugLog.any((entry) => entry.contains('deploy archive:')),
      isTrue,
    );
  });

  test(
    'toolchain and deployment commands dispatch through shell command flow',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final refreshedGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[refreshedGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _RefreshAwareExecutionAdapter(
          projectGraph: initialGraph,
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      await shell.executeCommand(AppCommandId.useActiveCompiler);
      await shell.executeCommand(AppCommandId.preparePublish);

      expect(shell.lastToolchainCommand?.command, 'tool use');
      expect(shell.lastToolchainCommand?.succeeded, isTrue);
      expect(shell.lastDeploymentCommand?.command, 'publish');
      expect(shell.lastDeploymentCommand?.succeeded, isTrue);
      expect(
        shell.debugLog.any((entry) => entry.contains('tool use succeeded')),
        isTrue,
      );
      expect(
        shell.debugLog.any((entry) => entry.contains('publish succeeded')),
        isTrue,
      );

      await shell.handleToolchainRecoveryAction(
        const ToolchainRecoveryAction(
          id: 'show-toolchain-logs',
          label: 'Show logs',
          description: 'Open the latest toolchain command logs.',
        ),
      );

      expect(shell.activeBottomTab, BottomSurfaceTab.debug);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Toolchain log view requested'),
        ),
        isTrue,
      );
    },
  );

  test(
    'agent project lifecycle commands dispatch through shell adapters',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final refreshedGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[refreshedGraph, refreshedGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _RefreshAwareExecutionAdapter(
          projectGraph: initialGraph,
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      final fetchApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'fetchDependencies'),
      );
      final fetchResult = shell.agentSessionContext.commands.lastResult;
      final fetchCommand =
          fetchResult?.metadata['dependencySourceCommand']!
              as Map<String, Object?>;
      expect(fetchApplied, isTrue);
      expect(fetchCommand['command'], 'fetch');
      expect(fetchCommand['status'], 'succeeded');

      final vendorApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'vendorDependencies'),
      );
      final vendorResult = shell.agentSessionContext.commands.lastResult;
      final vendorCommand =
          vendorResult?.metadata['dependencySourceCommand']!
              as Map<String, Object?>;
      expect(vendorApplied, isTrue);
      expect(vendorCommand['command'], 'vendor');
      expect(vendorCommand['payload'], isA<Map<String, Object?>>());

      final packApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'packProject'),
      );
      final packResult = shell.agentSessionContext.commands.lastResult;
      final packCommand =
          packResult?.metadata['deploymentCommand']! as Map<String, Object?>;
      expect(packApplied, isTrue);
      expect(packCommand['command'], 'pack');

      final publishApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'preparePublish'),
      );
      final publishResult = shell.agentSessionContext.commands.lastResult;
      final publishCommand =
          publishResult?.metadata['deploymentCommand']! as Map<String, Object?>;
      expect(publishApplied, isTrue);
      expect(publishCommand['command'], 'publish');
      expect(publishCommand['payload'], isA<Map<String, Object?>>());
    },
  );

  test(
    'agent toolchain lifecycle commands dispatch through shell adapters',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final refreshedGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[
            refreshedGraph,
            refreshedGraph,
            refreshedGraph,
          ],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _RefreshAwareExecutionAdapter(
          projectGraph: initialGraph,
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      final useApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'useActiveCompiler'),
      );
      final useResult = shell.agentSessionContext.commands.lastResult;
      final useCommand =
          useResult?.metadata['toolchainCommand']! as Map<String, Object?>;
      expect(useApplied, isTrue);
      expect(useCommand['command'], 'tool use');
      expect(useCommand['status'], 'succeeded');

      final pinApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'pinActiveCompiler'),
      );
      final pinResult = shell.agentSessionContext.commands.lastResult;
      final pinCommand =
          pinResult?.metadata['toolchainCommand']! as Map<String, Object?>;
      expect(pinApplied, isTrue);
      expect(pinCommand['command'], 'tool pin');
      expect(pinCommand['succeeded'], isTrue);

      final clearApplied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'clearPinnedCompiler'),
      );
      final clearResult = shell.agentSessionContext.commands.lastResult;
      expect(clearApplied, isFalse);
      expect(clearResult?.commandId, 'clearPinnedCompiler');
      expect(clearResult?.metadata['requiredCommand'], 'openSettings');
      expect(clearResult?.metadata['blockedReason'], isA<String>());
    },
  );

  test('agent module refresh command records module host metadata', () async {
    final initialGraph = _projectGraph(
      compilerVersion: '0.0.5',
      compilePlanReady: true,
    );
    final shell = ShellModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _SequenceProjectGraphAdapter(
        snapshots: <ProjectGraphSnapshot>[initialGraph],
      ),
      workspaceController: WorkspaceController(projectSnapshot: initialGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: EditorSessionController.seedDocumentForPath(
          initialGraph.editorFiles.first,
        ),
        languageService: const SimpleStyioLanguageService(),
      ),
      executionAdapter: _RefreshAwareExecutionAdapter(
        projectGraph: initialGraph,
      ),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
      runtimeEventAdapter: createRuntimeEventAdapter(
        platformTarget: PlatformTarget.macos,
      ),
      dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
      deploymentAdapter: const _SuccessfulDeploymentAdapter(),
      toolchainManagementAdapter: const _SuccessfulToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    final applied = await shell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(commandId: 'refreshModules'),
    );
    final result = shell.agentSessionContext.commands.lastResult;
    final metadata =
        result?.metadata['moduleHostRefresh']! as Map<String, Object?>;
    final bridge = metadata['nativeBridge']! as Map<String, Object?>;

    expect(applied, isTrue);
    expect(result?.commandId, 'refreshModules');
    expect(metadata['visibleModuleCount'], 0);
    expect(metadata['mountedModuleCount'], 0);
    expect(bridge['moduleId'], 'local.runtime.desktop');
    expect(bridge['state'], 'deferred');
  });

  test('agent surface commands focus bottom panels', () async {
    final initialGraph = _projectGraph(
      compilerVersion: '0.0.5',
      compilePlanReady: true,
    );
    final shell = ShellModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _SequenceProjectGraphAdapter(
        snapshots: <ProjectGraphSnapshot>[initialGraph],
      ),
      workspaceController: WorkspaceController(projectSnapshot: initialGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: EditorSessionController.seedDocumentForPath(
          initialGraph.editorFiles.first,
        ),
        languageService: const SimpleStyioLanguageService(),
      ),
      executionAdapter: _RefreshAwareExecutionAdapter(
        projectGraph: initialGraph,
      ),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
      runtimeEventAdapter: createRuntimeEventAdapter(
        platformTarget: PlatformTarget.macos,
      ),
      dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
      deploymentAdapter: const _SuccessfulDeploymentAdapter(),
      toolchainManagementAdapter: const _SuccessfulToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    final agentApplied = await shell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(commandId: 'showAgent'),
    );
    expect(agentApplied, isTrue);
    expect(shell.activeBottomTab, BottomSurfaceTab.agent);

    final runtimeApplied = await shell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(commandId: 'showRuntime'),
    );
    expect(runtimeApplied, isTrue);
    expect(shell.activeBottomTab, BottomSurfaceTab.runtime);

    final debugApplied = await shell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(commandId: 'showDebug'),
    );
    final result = shell.agentSessionContext.commands.lastResult;
    final surfaceCommand =
        result?.metadata['surfaceCommand']! as Map<String, Object?>;
    expect(debugApplied, isTrue);
    expect(shell.activeBottomTab, BottomSurfaceTab.debug);
    expect(surfaceCommand['targetSurface'], 'debug');
  });

  test('open settings command selects the settings bottom surface', () async {
    final initialGraph = _projectGraph(
      compilerVersion: '0.0.5',
      compilePlanReady: true,
    );
    final shell = ShellModel(
      platformTarget: PlatformTarget.macos,
      supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
      projectGraphAdapter: _SequenceProjectGraphAdapter(
        snapshots: <ProjectGraphSnapshot>[initialGraph],
      ),
      workspaceController: WorkspaceController(projectSnapshot: initialGraph),
      workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
      moduleRegistry: ModuleRegistry(
        platformTarget: PlatformTarget.macos,
        definitions: const [],
      ),
      nativeModuleLoader: const NoopNativeModuleLoader(
        platformTarget: PlatformTarget.macos,
      ),
      editorController: EditorSessionController(
        initialDocument: EditorSessionController.seedDocumentForPath(
          initialGraph.editorFiles.first,
        ),
        languageService: const SimpleStyioLanguageService(),
      ),
      executionAdapter: _RefreshAwareExecutionAdapter(
        projectGraph: initialGraph,
      ),
      executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
          _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
      runtimeEventAdapter: createRuntimeEventAdapter(
        platformTarget: PlatformTarget.macos,
      ),
      dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
      deploymentAdapter: const _SuccessfulDeploymentAdapter(),
      toolchainManagementAdapter: const _SuccessfulToolchainManagementAdapter(),
    );
    addTearDown(shell.dispose);

    await shell.executeCommand(AppCommandId.openSettings);

    expect(shell.activeBottomTab, BottomSurfaceTab.settings);
    expect(
      shell.debugLog.any((entry) => entry.contains('Settings surface opened')),
      isTrue,
    );

    shell.selectBottomTab(BottomSurfaceTab.runtime);
    final applied = await shell.applyAgentIdeCommandSuggestion(
      const AgentIdeCommandSuggestion(
        commandId: 'openSettings',
        prerequisiteForCommandId: 'runBuild',
      ),
    );
    final result = shell.agentSessionContext.commands.lastResult;

    expect(applied, isTrue);
    expect(shell.activeBottomTab, BottomSurfaceTab.settings);
    expect(result?.commandId, 'openSettings');
    expect(result?.metadata['recoveryForCommandId'], 'runBuild');
    expect(
      result?.metadata.containsKey('completedRequiredCommandFor'),
      isFalse,
    );
    expect(result?.metadata['settingsRoute'], 'settings');
    expect(result?.metadata['settingsSection'], 'toolchain');
  });

  test(
    'toolchain candidate selection reports unavailable without manager',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _RefreshAwareExecutionAdapter(
          projectGraph: initialGraph,
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      final result = await shell.selectToolchainCandidate('styio-service');

      expect(result, isNull);
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Toolchain selection unavailable'),
        ),
        isTrue,
      );
    },
  );

  test(
    'toolchain candidate selection activates catalog through manager',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_shell_toolchain_selection_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final configurationStore = await createConfigurationStore(tempRoot);
      final toolchainStore = ToolchainConfigurationStore(
        configurationStore: configurationStore,
      );
      final manager = ToolchainManager(
        configurationStore: toolchainStore,
        platformManagers: await createTestPlatformManagers(),
        workspaceId: 'demo',
      );
      await manager.registerToolchain(
        const ToolchainDescriptor(
          id: 'styio-service',
          kind: ToolchainKind.languageService,
          displayName: 'Styio Service',
          executablePath: '/opt/styio/bin/styio-service',
          version: '0.0.9',
          channel: 'nightly',
        ),
      );
      final toolchainReport = ValueNotifier<ToolchainManagerStatusReport>(
        await manager.statusReport(kind: ToolchainKind.languageService),
      );
      addTearDown(toolchainReport.dispose);
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _RefreshAwareExecutionAdapter(
          projectGraph: initialGraph,
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
        toolchainManager: manager,
        toolchainStatusReport: toolchainReport,
      );
      addTearDown(shell.dispose);

      expect(
        (await manager.loadCatalog()).active(ToolchainKind.languageService),
        isNull,
      );

      final result = await shell.selectToolchainCandidate('styio-service');

      expect(result?.status, ToolchainSelectionStatus.selected);
      expect(
        (await manager.loadCatalog()).active(ToolchainKind.languageService)?.id,
        'styio-service',
      );
      expect(
        toolchainReport.value.snapshot
            .active(ToolchainKind.languageService)
            ?.id,
        'styio-service',
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Toolchain selected: styio-service'),
        ),
        isTrue,
      );

      final clearResult = await shell.clearToolchainCandidate(
        ToolchainKind.languageService,
      );

      expect(clearResult?.status, ToolchainSelectionStatus.cleared);
      expect(
        (await manager.loadCatalog()).active(ToolchainKind.languageService),
        isNull,
      );
      expect(
        toolchainReport.value.snapshot.active(ToolchainKind.languageService),
        isNull,
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains(
            'Toolchain active selection cleared: language-service',
          ),
        ),
        isTrue,
      );

      await shell.handleToolchainRecoveryAction(
        const ToolchainRecoveryAction(
          id: 'install-managed-toolchain',
          label: 'Install managed toolchain',
          description: 'Prepare a toolchain installation plan.',
        ),
      );

      expect(
        shell.lastToolchainInstallPlan?.status,
        ToolchainInstallPlanStatus.planned,
      );
      expect(
        shell.lastToolchainInstallPlan?.mode,
        ToolchainInstallMode.manualSelection,
      );
      expect(shell.toolchainInstallPlanSurface?.mode, 'manualSelection');
      expect(shell.toolchainInstallPlanSurface?.kind, 'language-service');
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('Toolchain install plan planned'),
        ),
        isTrue,
      );

      final execution = await shell.executeLastToolchainInstallPlan();

      expect(
        execution?.status,
        ToolchainInstallExecutionStatus.requiresUserAction,
      );
      expect(
        shell.toolchainInstallExecutionSurface?.status,
        'requiresUserAction',
      );
      expect(
        toolchainReport.value.installHistory?.entries.first.status,
        'requiresUserAction',
      );
      expect(
        shell.debugLog.any(
          (entry) =>
              entry.contains('Toolchain install execution requiresUserAction'),
        ),
        isTrue,
      );
    },
  );

  test(
    'vendor command dispatch refreshes project graph and stores source state',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final refreshedGraph =
          _projectGraph(
            compilerVersion: '0.0.5',
            compilePlanReady: true,
          ).copyWith(
            sourceState: const ProjectSourceStateSnapshot(
              schemaVersion: 1,
              vendor: VendorSourceStateSnapshot(
                vendorRoot: '/workspace/demo/.spio/vendor',
                metadataPath: '/workspace/demo/.spio/vendor/spio-vendor.json',
                vendorPresent: true,
                metadataPresent: true,
                gitSnapshots: 1,
              ),
            ),
          );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[refreshedGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: _RefreshAwareExecutionAdapter(
          projectGraph: initialGraph,
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            _RefreshAwareExecutionAdapter(projectGraph: projectGraph),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      await shell.executeCommand(AppCommandId.vendorDependencies);

      expect(shell.lastDependencySourceCommand?.succeeded, isTrue);
      expect(shell.lastDependencySourceCommand?.command, 'vendor');
      expect(
        shell
            .workspaceController
            .activeProject
            .sourceState
            ?.vendor
            .gitSnapshots,
        1,
      );
      expect(
        shell.debugLog.any((entry) => entry.contains('vendor metadata:')),
        isTrue,
      );
    },
  );

  test(
    'run command logs runtime event summaries for published sessions',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      recordRuntimeEventsForSession(
        'shell-runtime-session',
        <RuntimeEventEnvelope>[
          RuntimeEventEnvelope(
            schemaVersion: 1,
            sessionId: 'shell-runtime-session',
            sequence: 1,
            timestamp: DateTime.utc(2026, 4, 17, 0, 0, 0),
            eventKind: 'compile.started',
            origin: 'styio.compile-plan',
            payload: const <String, Object?>{'intent': 'run'},
          ),
          RuntimeEventEnvelope(
            schemaVersion: 1,
            sessionId: 'shell-runtime-session',
            sequence: 2,
            timestamp: DateTime.utc(2026, 4, 17, 0, 0, 1),
            eventKind: 'run.finished',
            origin: 'styio.runtime',
            payload: const <String, Object?>{'success': true},
          ),
        ],
      );
      addTearDown(() => clearRuntimeEventsForSession('shell-runtime-session'));

      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: const _SuccessfulExecutionAdapter(
          sessionId: 'shell-runtime-session',
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            const _SuccessfulExecutionAdapter(
              sessionId: 'shell-runtime-session',
            ),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      await shell.executeCommand(AppCommandId.run);

      expect(shell.lastExecutionSession?.sessionId, 'shell-runtime-session');
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('runtime events: 2 event(s)'),
        ),
        isTrue,
      );
      expect(
        shell.debugLog.any(
          (entry) => entry.contains('runtime: compile.started'),
        ),
        isTrue,
      );
      expect(
        shell.debugLog.any((entry) => entry.contains('runtime: run.finished')),
        isTrue,
      );
    },
  );

  test(
    'agent run command blocks on dirty files then records execution',
    () async {
      final initialGraph = _projectGraph(
        compilerVersion: '0.0.5',
        compilePlanReady: true,
      );
      final shell = ShellModel(
        platformTarget: PlatformTarget.macos,
        supplementalAdapterCapabilities: const <AdapterCapabilitySnapshot>[],
        projectGraphAdapter: _SequenceProjectGraphAdapter(
          snapshots: <ProjectGraphSnapshot>[initialGraph],
        ),
        workspaceController: WorkspaceController(projectSnapshot: initialGraph),
        workspaceDocumentStore: InMemoryWorkspaceDocumentStore(),
        moduleRegistry: ModuleRegistry(
          platformTarget: PlatformTarget.macos,
          definitions: const [],
        ),
        nativeModuleLoader: const NoopNativeModuleLoader(
          platformTarget: PlatformTarget.macos,
        ),
        editorController: EditorSessionController(
          initialDocument: EditorSessionController.seedDocumentForPath(
            initialGraph.editorFiles.first,
          ),
          languageService: const SimpleStyioLanguageService(),
        ),
        executionAdapter: const _SuccessfulExecutionAdapter(
          sessionId: 'agent-run-session',
        ),
        executionAdapterFactory: (ProjectGraphSnapshot projectGraph) async =>
            const _SuccessfulExecutionAdapter(sessionId: 'agent-run-session'),
        runtimeEventAdapter: createRuntimeEventAdapter(
          platformTarget: PlatformTarget.macos,
        ),
        dependencySourceAdapter: const _SuccessfulDependencySourceAdapter(),
        deploymentAdapter: const _SuccessfulDeploymentAdapter(),
        toolchainManagementAdapter:
            const _SuccessfulToolchainManagementAdapter(),
      );
      addTearDown(shell.dispose);

      shell.editorController.selectCollapsed(
        shell.editorController.document.length,
      );
      shell.editorController.insertText('\n#agent_run := 1');

      final blocked = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'run'),
      );
      final blockedResult = shell.agentSessionContext.commands.lastResult;
      expect(blocked, isFalse);
      expect(blockedResult?.commandId, 'run');
      expect(blockedResult?.metadata['requiredCommand'], 'saveAll');

      final saved = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(
          commandId: 'saveAll',
          prerequisiteForCommandId: 'run',
        ),
      );
      final saveResult = shell.agentSessionContext.commands.lastResult;
      expect(saved, isTrue);
      expect(saveResult?.metadata['completedRequiredCommandFor'], 'run');

      final applied = await shell.applyAgentIdeCommandSuggestion(
        const AgentIdeCommandSuggestion(commandId: 'run'),
      );
      final runResult = shell.agentSessionContext.commands.lastResult;
      final executionSession =
          runResult?.metadata['executionSession']! as Map<String, Object?>;

      expect(applied, isTrue);
      expect(runResult?.commandId, 'run');
      expect(executionSession['sessionId'], 'agent-run-session');
      expect(executionSession['status'], 'succeeded');
      expect(runResult?.metadata['runtimeEventCount'], 0);
      expect(shell.lastExecutionSession?.sessionId, 'agent-run-session');
    },
  );
}

ProjectGraphSnapshot _projectGraph({
  required String compilerVersion,
  required bool compilePlanReady,
  List<String> editorFiles = const <String>['/workspace/demo/src/main.styio'],
}) {
  final primaryEditorFile = editorFiles.isNotEmpty
      ? editorFiles.first
      : '/workspace/demo/src/main.styio';
  return ProjectGraphSnapshot(
    id: '/workspace/demo/spio.toml',
    title: 'demo/app',
    kind: ProjectKind.package,
    workspaceRoot: '/workspace/demo',
    workspaceMembers: const <String>[],
    manifestPath: '/workspace/demo/spio.toml',
    packages: const <ProjectPackageSnapshot>[],
    dependencies: const <ProjectDependencySnapshot>[],
    targets: <ProjectTargetDescriptor>[
      ProjectTargetDescriptor(
        id: 'demo/app:bin:demo',
        packageName: 'demo/app',
        kind: ProjectTargetKind.bin,
        name: 'demo',
        filePath: primaryEditorFile,
      ),
    ],
    editorFiles: List<String>.unmodifiable(editorFiles),
    toolchain: const ToolchainStatusSnapshot(
      source: ToolchainResolutionSource.projectPin,
      detail: 'Project toolchain pin discovered for shell-model testing.',
      pinPath: '/workspace/demo/spio-toolchain.toml',
      channel: 'stable',
    ),
    lockState: ProjectLockState.unknown,
    vendorState: ProjectVendorState.present,
    activeCompiler: CompilerHandshakeSnapshot(
      binaryPath: '/toolchains/styio/bin/styio',
      tool: 'styio',
      compilerVersion: compilerVersion,
      channel: 'stable',
      variant: 'test-fixture',
      capabilities: const <String>[
        'machine_info_json',
        'single_file_entry',
        'jsonl_diagnostics',
      ],
      supportedContractVersions: <String, List<int>>{
        'machine_info': const <int>[1],
        'compile_plan': compilePlanReady ? const <int>[1] : const <int>[],
      },
      integrationPhase: compilePlanReady
          ? 'compile-plan-live'
          : 'bootstrap-single-file',
      featureFlags: <String, bool>{'compile_plan_consumer': compilePlanReady},
    ),
    notes: const <String>[],
  );
}

class _SequenceProjectGraphAdapter implements ProjectGraphAdapter {
  _SequenceProjectGraphAdapter({required List<ProjectGraphSnapshot> snapshots})
    : _snapshots = List<ProjectGraphSnapshot>.of(snapshots);

  final List<ProjectGraphSnapshot> _snapshots;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot =>
      const AdapterCapabilitySnapshot(
        adapterKind: AdapterKind.cli,
        languageService: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.partial,
          detail: 'Project graph adapter does not provide language services.',
        ),
        projectGraph: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.available,
          detail: 'Published project graph payload is available.',
        ),
        execution: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Project graph adapter does not execute documents.',
        ),
        runtimeEvents: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Project graph adapter does not emit runtime events.',
        ),
      );

  @override
  Future<ProjectGraphSnapshot> loadProjectGraph() async {
    if (_snapshots.isEmpty) {
      throw StateError('No project graph snapshots remain for the test.');
    }
    return _snapshots.removeAt(0);
  }
}

class _RefreshAwareExecutionAdapter implements ExecutionAdapter {
  const _RefreshAwareExecutionAdapter({required this.projectGraph});

  final ProjectGraphSnapshot projectGraph;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot => AdapterCapabilitySnapshot(
    adapterKind: AdapterKind.cli,
    languageService: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Execution adapter does not provide language services.',
    ),
    projectGraph: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Execution adapter does not own project graph data.',
    ),
    execution: AdapterEndpointCapability(
      level: projectGraph.compilePlanConsumerAdvertised
          ? AdapterCapabilityLevel.available
          : AdapterCapabilityLevel.partial,
      detail: projectGraph.compilePlanConsumerAdvertised
          ? 'Project execution is live through compile-plan v1.'
          : 'Project execution is blocked until compile-plan support is advertised.',
    ),
    runtimeEvents: const AdapterEndpointCapability(
      level: AdapterCapabilityLevel.unavailable,
      detail: 'Runtime events stay unavailable in this test fixture.',
    ),
  );

  @override
  Future<ExecutionSession> runActiveDocument({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
  }) async {
    return const ExecutionSession(
      sessionId: 'shell-model-test',
      kind: 'run',
      status: ExecutionSessionStatus.blocked,
      statusMessage: 'Execution is not exercised in this shell-model test.',
      diagnostics: <Diagnostic>[],
      stdoutEvents: <ExecutionLogEvent>[],
      stderrEvents: <ExecutionLogEvent>[],
    );
  }
}

class _SuccessfulExecutionAdapter implements ExecutionAdapter {
  const _SuccessfulExecutionAdapter({required this.sessionId});

  final String sessionId;

  @override
  AdapterCapabilitySnapshot get capabilitySnapshot =>
      const AdapterCapabilitySnapshot(
        adapterKind: AdapterKind.cli,
        languageService: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Execution adapter does not provide language services.',
        ),
        projectGraph: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.unavailable,
          detail: 'Execution adapter does not own project graph data.',
        ),
        execution: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.available,
          detail: 'Project execution is live through compile-plan v1.',
        ),
        runtimeEvents: AdapterEndpointCapability(
          level: AdapterCapabilityLevel.partial,
          detail: 'Runtime events are replayed from published artifacts.',
        ),
      );

  @override
  Future<ExecutionSession> runActiveDocument({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
  }) async {
    return ExecutionSession(
      sessionId: sessionId,
      kind: 'run',
      status: ExecutionSessionStatus.succeeded,
      statusMessage:
          'Execution completed through the shell-model test fixture.',
      diagnostics: const <Diagnostic>[],
      stdoutEvents: const <ExecutionLogEvent>[],
      stderrEvents: const <ExecutionLogEvent>[],
    );
  }
}

class _SuccessfulToolchainManagementAdapter
    implements ToolchainManagementAdapter {
  const _SuccessfulToolchainManagementAdapter();

  @override
  Future<ToolchainCommandResult> clearPinnedCompiler({
    required ProjectGraphSnapshot projectGraph,
  }) async {
    return _success('tool pin');
  }

  @override
  Future<ToolchainCommandResult> installManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String styioBinaryPath,
  }) async {
    return _success('tool install');
  }

  @override
  Future<ToolchainCommandResult> pinManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async {
    return _success('tool pin');
  }

  @override
  Future<ToolchainCommandResult> useManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async {
    return _success('tool use');
  }

  ToolchainCommandResult _success(String command) {
    return ToolchainCommandResult(
      command: command,
      status: ToolchainCommandStatus.succeeded,
      statusMessage: 'toolchain command succeeded in the shell-model fixture.',
      stdout: '',
      stderr: '',
    );
  }
}

class _SuccessfulDependencySourceAdapter implements DependencySourceAdapter {
  const _SuccessfulDependencySourceAdapter();

  @override
  Future<DependencySourceCommandResult> fetchDependencies({
    required ProjectGraphSnapshot projectGraph,
    bool locked = false,
    bool offline = false,
  }) async {
    return _success('fetch');
  }

  @override
  Future<DependencySourceCommandResult> vendorDependencies({
    required ProjectGraphSnapshot projectGraph,
    String? outputPath,
    bool locked = false,
    bool offline = false,
  }) async {
    return _success('vendor');
  }

  DependencySourceCommandResult _success(String command) {
    return DependencySourceCommandResult(
      command: command,
      status: DependencySourceCommandStatus.succeeded,
      statusMessage: '$command command succeeded in the shell-model fixture.',
      stdout: '',
      stderr: '',
      payload: <String, dynamic>{
        'packages': 2,
        'vendor_root': '/workspace/demo/.spio/vendor',
        'metadata_path': '/workspace/demo/.spio/vendor/spio-vendor.json',
      },
    );
  }
}

class _SuccessfulDeploymentAdapter implements DeploymentAdapter {
  const _SuccessfulDeploymentAdapter();

  @override
  Future<DeploymentCommandResult> packProject({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) async {
    return _success('pack', packageName: packageName);
  }

  @override
  Future<DeploymentCommandResult> preparePublish({
    required ProjectGraphSnapshot projectGraph,
    String? packageName,
    String? outputPath,
  }) async {
    return _success('publish', packageName: packageName);
  }

  @override
  Future<DeploymentCommandResult> publishToRegistry({
    required ProjectGraphSnapshot projectGraph,
    required String registryRoot,
    String? packageName,
    String? outputPath,
  }) async {
    return _success('publish', packageName: packageName);
  }

  DeploymentCommandResult _success(String command, {String? packageName}) {
    return DeploymentCommandResult(
      command: command,
      status: DeploymentCommandStatus.succeeded,
      statusMessage: 'deployment command succeeded in the shell-model fixture.',
      stdout: '',
      stderr: '',
      payload: <String, dynamic>{
        'package': packageName ?? 'demo/app',
        'archive_path': '/workspace/demo/dist/app-0.0.5.tar',
      },
    );
  }
}

class _ShellSourceControlActionProvider extends SourceControlActionProvider {
  const _ShellSourceControlActionProvider();

  @override
  SourceControlProviderKind get providerKind => SourceControlProviderKind.git;

  @override
  Future<SourceControlActionResult> runAction({
    required String workspaceRoot,
    required SourceControlActionRequest request,
  }) async {
    return SourceControlActionResult(
      kind: request.kind,
      applied: true,
      paths: request.paths,
      message: 'confirmed in $workspaceRoot',
    );
  }
}
