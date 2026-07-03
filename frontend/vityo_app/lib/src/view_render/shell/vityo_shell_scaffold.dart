import 'package:flutter/material.dart';

import '../agent/agent.dart';
import '../commands/command_palette_surface.dart';
import '../editor/editor.dart';
import '../extensions/extensions.dart';
import '../../view_ide/backend_toolchain/adapter_contracts.dart';
import '../../view_ide/backend_toolchain/dependency_source_adapter.dart';
import '../../view_ide/backend_toolchain/deployment_adapter.dart';
import '../../view_ide/backend_toolchain/execution_adapter.dart';
import '../../view_ide/backend_toolchain/execution_route_summary.dart';
import '../../view_ide/backend_toolchain/project_graph_contract.dart';
import '../../view_ide/backend_toolchain/required_handoff_summary.dart';
import '../../view_ide/backend_toolchain/toolchain_management_adapter.dart';
import '../../module_host/module_definition.dart';
import '../../module_host/module_manifest.dart';
import '../../platform/platform_target.dart';
import '../../view_ide/agent/agent.dart' show AgentWorkspaceSnapshotService;
import '../platform/platform.dart';
import '../problems/problems.dart';
import '../runtime/runtime.dart';
import '../search/search.dart';
import '../settings/settings_surface.dart';
import '../source_control/source_control.dart';
import '../terminal/terminal.dart';
import '../testing/testing.dart';
import '../../view_ide/workspace/workspace.dart';

import 'hosted_workspace_lifecycle_banner.dart';
import '../../app/commands/app_commands.dart';
import 'shell_layout_plan.dart';
import 'shell_model.dart';
import 'shell_scope.dart';

class VityoShellScaffold extends StatelessWidget {
  const VityoShellScaffold({super.key});

  @override
  Widget build(BuildContext context) {
    final shell = ShellScope.of(context);
    final project = shell.workspaceController.activeProject;
    final hostedClosePlan = const HostedWorkspaceLifecycle().closePlanFor(
      project,
    );
    final viewportProfile = resolveViewportProfile(
      platformTarget: shell.platformTarget,
      width: MediaQuery.sizeOf(context).width,
      height: MediaQuery.sizeOf(context).height,
    );

    return Shortcuts(
      shortcuts: AppCommandShortcutRegistry.shortcutIntents,
      child: Actions(
        actions: <Type, Action<Intent>>{
          AppCommandIntent: CallbackAction<AppCommandIntent>(
            onInvoke: (intent) {
              shell.executeCommand(intent.commandId);
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  children: [
                    _TopBar(
                      platformTarget: shell.platformTarget,
                      activeProjectTitle: project.title,
                      viewportProfile: viewportProfile,
                    ),
                    const SizedBox(height: 16),
                    if (hostedClosePlan != null) ...[
                      HostedWorkspaceLifecycleBanner(plan: hostedClosePlan),
                      const SizedBox(height: 16),
                    ],
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final layoutViewport = resolveViewportProfile(
                            platformTarget: shell.platformTarget,
                            width: constraints.maxWidth,
                            height: constraints.maxHeight,
                          );
                          final layoutBinding = shell
                              .shellLayoutPreferenceController
                              .renderBindingForViewport(
                                compact: layoutViewport.isMobile,
                              );

                          if (layoutViewport.isMobile) {
                            return _MobileShellBody(
                              shell: shell,
                              viewportProfile: layoutViewport,
                              layoutBinding: layoutBinding,
                              bottomSurface: _buildBottomSurface(
                                shell,
                                layoutViewport,
                              ),
                            );
                          }

                          return _DesktopShellBody(
                            shell: shell,
                            viewportProfile: layoutViewport,
                            layoutBinding: layoutBinding,
                            bottomSurface: _buildBottomSurface(
                              shell,
                              layoutViewport,
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    _ShellStatusBar(
                      platformTarget: shell.platformTarget,
                      viewportProfile: viewportProfile,
                      mountedModuleCount: shell.mountedModules.length,
                      visibleModuleCount: shell.visibleModules.length,
                      projectTitle: project.title,
                      activeFilePath: shell.workspaceController.activeFilePath,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBottomSurface(
    ShellModel shell,
    ViewportProfile viewportProfile,
  ) {
    switch (shell.activeBottomTab) {
      case BottomSurfaceTab.runtime:
        return RuntimeSurface(
          platformTarget: shell.platformTarget,
          viewportProfile: viewportProfile,
          projectGraph: shell.workspaceController.activeProject,
          toolchainStatus: shell.toolchainStatusSurface,
          onToolchainRecoveryAction: shell.handleToolchainRecoveryAction,
          mountedModules: shell.mountedModules,
          adapterCapabilities: shell.adapterCapabilities,
          executionSession: shell.lastExecutionSession,
          runtimeEvents: shell.lastRuntimeEvents,
          nativeToolResults: shell.nativeToolResults,
          outputSnapshot: shell.runtimeOutputBuffer.snapshot,
          onOpenNativeToolDiagnostics: shell.openFirstNativeToolDiagnostic,
        );
      case BottomSurfaceTab.terminal:
        return TerminalSurface(
          viewportProfile: viewportProfile,
          logEntries: shell.debugLog,
          runtimeEventSummaries: shell.lastRuntimeEvents
              .map(_terminalRuntimeEventSummary)
              .toList(growable: false),
          onRunActiveTarget: () {
            return shell.executeCommand(AppCommandId.run);
          },
        );
      case BottomSurfaceTab.commands:
      case BottomSurfaceTab.commandPalette:
        return CommandPaletteSurface(
          viewportProfile: viewportProfile,
          onExecuteCommand: shell.executeCommand,
          onExecuteCommandWithInput: shell.executeCommandWithInput,
          blockedReasonForCommand: shell.blockedReasonForCommand,
        );
      case BottomSurfaceTab.agent:
        return AgentSurface(
          platformTarget: shell.platformTarget,
          viewportProfile: viewportProfile,
          visibleModules: shell.visibleModules,
          adapterCapabilities: shell.adapterCapabilities,
          sessionContext: shell.agentSessionContext,
          codingController: shell.agentCodingController,
          activityHistory: shell.agentCodingController.sessionHistorySnapshot,
          onApplyPendingPatch: () async {
            await shell.applyAgentPendingPatch();
          },
          workspaceSnapshotService: AgentWorkspaceSnapshotService(
            editorController: shell.editorController,
            workspaceDocumentStore: shell.workspaceDocumentStore,
          ),
          extensionToolExecutionRegistry:
              shell.agentExtensionToolExecutionRegistry,
          onApplyAgentWorkspacePatch: (patch) async {
            return shell.applyAgentWorkspacePatchTool(patch);
          },
          onApplyIdeCommandSuggestion: (suggestion) async {
            return shell.applyAgentIdeCommandSuggestion(suggestion);
          },
          onResolveIdeCommandResult: (suggestion) {
            return shell.lastAgentIdeCommandResult;
          },
          onSaveProviderProfile: (profile, {bearerToken}) async {
            await shell.saveAndMountAgentProfile(
              profile,
              bearerToken: bearerToken,
            );
          },
          onMountSavedProviderProfile: (profileKey) async {
            await shell.failoverAgentProviderProfile(profileKey);
          },
        );
      case BottomSurfaceTab.sourceControl:
        final sourceControlController = shell.sourceControlStatusController;
        Widget buildSourceControlSurface() {
          return SourceControlSurface(
            viewportProfile: viewportProfile,
            workspaceFileCount: shell.workspaceController.files.length,
            changedDocumentIds: shell.dirtyDocumentPaths,
            status: shell.sourceControlStatusSnapshot,
            diffPreview: shell.sourceControlDiffPreview,
            commitDraft: shell.sourceControlCommitDraft,
            commitDialogState: shell.sourceControlCommitDialogState,
            branchSnapshot: shell.sourceControlBranchSnapshot,
            historySnapshot: shell.sourceControlHistorySnapshot,
            lastHunkActionResult: shell.sourceControlHunkActionResult,
            onOpenFile: shell.openWorkspaceFileForAgent,
            onSaveAll: () {
              return shell.executeCommand(AppCommandId.saveAll);
            },
            onRefresh: () {
              return shell.executeCommand(AppCommandId.refreshSourceControl);
            },
            onPreviewDiff: shell.previewSourceControlDiff,
            onStagePaths: shell.stageSourceControlPaths,
            onUnstagePaths: shell.unstageSourceControlPaths,
            onSwitchBranch: (plan) {
              return shell.planSourceControlBranchSwitch(plan.targetBranch);
            },
            onOpenCommit: () async {
              shell.planSourceControlCommitDraft(message: '');
            },
            onConfirmDiffAction: shell.confirmSourceControlDiffAction,
            pendingHunkDiscardConfirmation:
                sourceControlController?.pendingHunkDiscardConfirmation,
            onSelectHunkAction: shell.planSourceControlHunkAction,
            onConfirmHunkDiscard: () async {
              await shell.confirmPendingSourceControlHunkDiscard();
            },
          );
        }

        if (sourceControlController == null) {
          return buildSourceControlSurface();
        }
        return ListenableBuilder(
          listenable: sourceControlController,
          builder: (_, _) => buildSourceControlSurface(),
        );
      case BottomSurfaceTab.search:
        return WorkspaceSearchSurface(
          viewportProfile: viewportProfile,
          workspaceFileCount: shell.workspaceController.files.length,
          workspaceFiles: shell.workspaceController.files,
          lastSearch: shell.agentSessionContext.workspace.lastSearch,
          lastSymbolSearch:
              shell.agentSessionContext.workspace.lastSymbolSearch,
          lastReplacePreview: shell.lastWorkspaceReplacePreview,
          onSearch: shell.searchWorkspaceForAgent,
          onOpenFile: shell.openWorkspaceFileForAgent,
          onPreviewReplace: (query, replacement) async {
            await shell.previewWorkspaceReplace(
              query: query,
              replacement: replacement,
            );
          },
          onApplyReplacePreview: shell.applyWorkspaceReplacePreview,
          onOpenMatch: (match) =>
              shell.openWorkspaceFileForAgent(match.documentId),
          onOpenSymbolMatch: (match) =>
              shell.openWorkspaceFileForAgent(match.documentId),
        );
      case BottomSurfaceTab.problems:
        final diagnosticsController = shell.workspaceDiagnosticsController;
        Widget buildProblemsSurface() {
          return ProblemsSurface(
            viewportProfile: viewportProfile,
            documentId: shell.editorController.document.documentId,
            diagnostics: shell.editorController.analysis.diagnostics,
            workspaceDiagnostics: shell.workspaceDiagnosticsSnapshot,
            diagnosticsProducerLifecycles: shell.diagnosticsProducerLifecycles,
            onSelectDiagnostic: shell.editorController.selectDiagnostic,
            onSelectWorkspaceDiagnostic: (diagnostic) {
              shell.selectWorkspaceDiagnostic(diagnostic);
            },
            workspaceEditPreview: shell.lastWorkspaceEditPreview,
            workspaceEditApplyResult: shell.lastWorkspaceEditApplyResult,
            quickFixTelemetry: shell.workspaceQuickFixTelemetrySnapshot,
            semanticSnapshotPanelViewModel:
                shell.semanticProblemsPanelViewModel,
            onRefreshWorkspaceDiagnostics: () {
              return shell.executeCommand(
                AppCommandId.refreshWorkspaceDiagnostics,
              );
            },
            onCancelDiagnosticsProducer:
                shell.cancelWorkspaceDiagnosticsProducer,
            onPreviewWorkspaceQuickFix: () async {
              await shell.executeCommand(AppCommandId.previewQuickFix);
            },
            onApplyWorkspaceQuickFix: () {
              return shell.executeCommand(AppCommandId.applyQuickFix);
            },
            onPreviewDiagnosticQuickFix: (route) async {
              shell.selectWorkspaceDiagnostic(route.diagnostic);
              await shell.executeCommand(AppCommandId.previewQuickFix);
            },
            onApplyDiagnosticQuickFix: (route) async {
              shell.selectWorkspaceDiagnostic(route.diagnostic);
              await shell.executeCommand(AppCommandId.applyQuickFix);
            },
          );
        }

        if (diagnosticsController == null) {
          return buildProblemsSurface();
        }
        return ListenableBuilder(
          listenable: diagnosticsController,
          builder: (_, _) => buildProblemsSurface(),
        );
      case BottomSurfaceTab.testing:
        final testingController = shell.testingSessionController;
        Widget buildTestingSurface() {
          return TestingSurface(
            viewportProfile: viewportProfile,
            nativeToolResults: shell.nativeToolResults,
            discovery: shell.testDiscovery,
            lastRun: shell.lastTestRun,
            runHistory: shell.testRunHistory,
            failedRetryHistory: shell.failedTestRetryHistory,
            configurationSet: shell.testRunConfigurationSet,
            failedDebugCancellationRoute: shell.failedDebugCancellationRoute,
            onRunTests: () {
              return shell.executeCommand(AppCommandId.runTests);
            },
            onRunConfiguration: shell.runTestConfiguration,
            onDebugConfiguration: (configuration) async {
              await shell.debugTestConfiguration(configuration);
              shell.selectBottomTab(BottomSurfaceTab.debug);
            },
            onCancelFailedTestDebug: shell.cancelFailedTestDebug,
            onRerunFailed: () {
              return shell.rerunFailedTests();
            },
            onSelectRunConfiguration: shell.selectTestRunConfiguration,
            onSelectFailedTest: (_) {
              shell.openFirstNativeToolDiagnostic(AppCommandId.runTests);
            },
            onOpenDiagnostics: () {
              shell.openFirstNativeToolDiagnostic(AppCommandId.runTests);
            },
          );
        }

        if (testingController == null) {
          return buildTestingSurface();
        }
        return ListenableBuilder(
          listenable: testingController,
          builder: (_, _) => buildTestingSurface(),
        );
      case BottomSurfaceTab.extensions:
        return ExtensionsSurface(
          viewportProfile: viewportProfile,
          visibleModules: shell.visibleModules,
          mountedModules: shell.mountedModules,
          onRefreshModules: () {
            return shell.executeCommand(AppCommandId.refreshModules);
          },
        );
      case BottomSurfaceTab.debug:
        return DebugConsoleSurface(
          viewportProfile: viewportProfile,
          entries: shell.debugLog,
          runtimeEvents: shell.lastRuntimeEvents,
          debugSession: shell.debugSession,
          debugRuntimeExecution: shell.lastDebugRuntimeExecutionResult,
          onStartDebugging: () {
            return shell.executeCommand(AppCommandId.startDebugging);
          },
          onRetryDebugLaunch: () {
            return shell.executeCommand(AppCommandId.startDebugging);
          },
          onStopDebugging: () {
            return shell.executeCommand(AppCommandId.stopDebugging);
          },
          onContinueDebugging: () {
            return shell.executeCommand(AppCommandId.continueDebugging);
          },
          onStepOver: () {
            return shell.executeCommand(AppCommandId.stepOver);
          },
          onSelectStackFrame: (frameId) {
            shell.selectDebugStackFrame(frameId);
          },
          onSelectThread: (threadId) {
            shell.selectDebugThread(threadId);
          },
        );
      case BottomSurfaceTab.settings:
        return SettingsSurface(
          viewportProfile: viewportProfile,
          toolchainStatus: shell.toolchainStatusSurface,
          toolchainSettings: shell.toolchainSettingsSurface,
          toolchainInstallPlan: shell.toolchainInstallPlanSurface,
          toolchainInstallExecution: shell.toolchainInstallExecutionSurface,
          toolchainBootstrapSummary: shell.toolchainBootstrapSummary,
          toolchainBootstrapActionDispatch:
              shell.lastToolchainBootstrapActionDispatch,
          themeOverride: shell.themeOverride,
          commandPalettePreferences: shell.commandPalettePreferences,
          onToolchainRecoveryAction: shell.handleToolchainRecoveryAction,
          onToolchainBootstrapAction: shell.handleToolchainBootstrapAction,
          onSelectToolchain: shell.selectToolchainCandidate,
          onSelectClangCppVersion: (versionId, cppStandard) {
            return shell.selectClangCppVersion(
              versionId,
              cppStandard: cppStandard,
            );
          },
          onClearToolchain: shell.clearToolchainCandidate,
          onExecuteToolchainInstallPlan: shell.executeLastToolchainInstallPlan,
          onSaveCommandPalettePreferences: shell.saveCommandPalettePreferences,
          onSaveThemeOverride: shell.saveThemeOverride,
        );
      case BottomSurfaceTab.navigate:
      case BottomSurfaceTab.locations:
      default:
        return const SizedBox.shrink();
    }
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.platformTarget,
    required this.activeProjectTitle,
    required this.viewportProfile,
  });

  final PlatformTarget platformTarget;
  final String activeProjectTitle;
  final ViewportProfile viewportProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              viewportProfile.isMobile || constraints.maxWidth < 900;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vityo Editor Workbench',
                        style: theme.textTheme.headlineMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Editor, runtime, agent, settings, and workspace operations for the active Vityo project.',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 12,
                        runSpacing: 10,
                        children: [
                          Chip(label: Text(platformTarget.label)),
                          Chip(label: Text(viewportProfile.label)),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        activeProjectTitle,
                        style: theme.textTheme.bodySmall,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Vityo Editor Workbench',
                              style: theme.textTheme.headlineMedium,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Editor, runtime, agent, settings, and workspace operations for the active Vityo project.',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Chip(label: Text(platformTarget.label)),
                          const SizedBox(height: 8),
                          Chip(label: Text(viewportProfile.label)),
                          const SizedBox(height: 8),
                          Text(
                            activeProjectTitle,
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _ShellStatusBar extends StatelessWidget {
  const _ShellStatusBar({
    required this.platformTarget,
    required this.viewportProfile,
    required this.mountedModuleCount,
    required this.visibleModuleCount,
    required this.projectTitle,
    required this.activeFilePath,
  });

  final PlatformTarget platformTarget;
  final ViewportProfile viewportProfile;
  final int mountedModuleCount;
  final int visibleModuleCount;
  final String projectTitle;
  final String activeFilePath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: viewportProfile.isMobile
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Text(
                        'Platform ${platformTarget.label}',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        'Viewport ${viewportProfile.label}',
                        style: theme.textTheme.bodySmall,
                      ),
                      Text(
                        'Mounted $mountedModuleCount/$visibleModuleCount modules',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Project $projectTitle · $activeFilePath',
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              )
            : Row(
                children: [
                  Text(
                    'Platform ${platformTarget.label}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Viewport ${viewportProfile.label}',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 12),
                  Text(
                    'Mounted $mountedModuleCount/$visibleModuleCount modules',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Text(
                      'Project $projectTitle · $activeFilePath',
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

class _DesktopShellBody extends StatelessWidget {
  const _DesktopShellBody({
    required this.shell,
    required this.viewportProfile,
    required this.layoutBinding,
    required this.bottomSurface,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;
  final ShellLayoutRenderBinding layoutBinding;
  final Widget bottomSurface;

  @override
  Widget build(BuildContext context) {
    final denseDesktop = viewportProfile.width < 1440;
    final workspaceWidth = denseDesktop ? 252.0 : 288.0;
    final moduleWidth = denseDesktop ? 320.0 : 348.0;
    final bottomSurfaceHeight = viewportProfile.height >= 840
        ? 250.0
        : viewportProfile.height >= 680
        ? 200.0
        : 160.0;

    return KeyedSubtree(
      key: ValueKey(layoutBinding.viewportKey),
      child: Row(
        children: [
          SizedBox(
            width: workspaceWidth,
            child: _WorkspaceSidebar(shell: shell),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        flex: denseDesktop ? 6 : 5,
                        child: EditorSurface(
                          controller: shell.editorController,
                          viewportProfile: viewportProfile,
                          languageServiceStatus:
                              shell.languageServiceStatus.value,
                          projectHoverAtSelection:
                              shell.projectHoverAtSelection,
                          projectCompletionsAtSelection:
                              shell.projectCompletionsAtSelection,
                          fileBindingSnapshot: shell.editorFileBindingSnapshot,
                          closeRequestSurface: shell.closeRequestSurface,
                          onAcceptExternalChange:
                              shell.acceptEditorExternalChange,
                          onSaveLocalChanges: () {
                            shell.saveActiveWorkspaceFileChanges();
                          },
                          onDiscardLocalChanges: () {
                            shell.discardActiveWorkspaceFileChanges();
                          },
                          onSaveAndCloseRequest: () {
                            shell.saveAndCloseRequestedWorkspaceFile();
                          },
                          onDiscardAndCloseRequest: () {
                            shell.discardAndCloseRequestedWorkspaceFile();
                          },
                          onSwitchToCloseRequestFile:
                              shell.switchToCloseRequestFile,
                          onCancelCloseRequest: shell.clearCloseRequestResult,
                          openDocumentIds:
                              shell.workspaceController.openFilePaths,
                          dirtyDocumentIds: shell.dirtyDocumentPaths,
                          activeDocumentId:
                              shell.workspaceController.activeFilePath,
                          onSelectDocument: shell.workspaceController.openFile,
                          onCloseDocument: shell.requestCloseWorkspaceFile,
                          onRefreshLanguageService: () {
                            shell.executeCommand(
                              AppCommandId.refreshLanguageService,
                            );
                          },
                        ),
                      ),
                      const SizedBox(width: 16),
                      SizedBox(
                        width: moduleWidth,
                        child: _ModuleSidebar(shell: shell),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                _BottomSurfaceTabs(
                  shell: shell,
                  viewportProfile: viewportProfile,
                ),
                if (layoutBinding.bottomPanelExpanded) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: bottomSurfaceHeight,
                    child: KeyedSubtree(
                      key: ValueKey(layoutBinding.activeBottomPanelId),
                      child: bottomSurface,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileShellBody extends StatelessWidget {
  const _MobileShellBody({
    required this.shell,
    required this.viewportProfile,
    required this.layoutBinding,
    required this.bottomSurface,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;
  final ShellLayoutRenderBinding layoutBinding;
  final Widget bottomSurface;

  @override
  Widget build(BuildContext context) {
    final editorHeight = viewportProfile.height >= 820 ? 460.0 : 400.0;
    final workspaceHeight = viewportProfile.height >= 820 ? 320.0 : 280.0;
    final moduleHeight = viewportProfile.height >= 820 ? 320.0 : 280.0;
    final bottomSurfaceHeight = viewportProfile.height >= 820 ? 220.0 : 180.0;

    return KeyedSubtree(
      key: ValueKey(layoutBinding.viewportKey),
      child: ListView(
        key: const ValueKey('shell-mobile-scroll'),
        children: [
          SizedBox(
            height: editorHeight,
            child: EditorSurface(
              controller: shell.editorController,
              viewportProfile: viewportProfile,
              languageServiceStatus: shell.languageServiceStatus.value,
              projectHoverAtSelection: shell.projectHoverAtSelection,
              projectCompletionsAtSelection:
                  shell.projectCompletionsAtSelection,
              fileBindingSnapshot: shell.editorFileBindingSnapshot,
              closeRequestSurface: shell.closeRequestSurface,
              onAcceptExternalChange: shell.acceptEditorExternalChange,
              onSaveLocalChanges: () {
                shell.saveActiveWorkspaceFileChanges();
              },
              onDiscardLocalChanges: () {
                shell.discardActiveWorkspaceFileChanges();
              },
              onSaveAndCloseRequest: () {
                shell.saveAndCloseRequestedWorkspaceFile();
              },
              onDiscardAndCloseRequest: () {
                shell.discardAndCloseRequestedWorkspaceFile();
              },
              onSwitchToCloseRequestFile: shell.switchToCloseRequestFile,
              onCancelCloseRequest: shell.clearCloseRequestResult,
              openDocumentIds: shell.workspaceController.openFilePaths,
              dirtyDocumentIds: shell.dirtyDocumentPaths,
              activeDocumentId: shell.workspaceController.activeFilePath,
              onSelectDocument: shell.workspaceController.openFile,
              onCloseDocument: shell.requestCloseWorkspaceFile,
              onRefreshLanguageService: () {
                shell.executeCommand(AppCommandId.refreshLanguageService);
              },
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: workspaceHeight,
            child: _WorkspaceSidebar(shell: shell),
          ),
          const SizedBox(height: 16),
          SizedBox(
            height: moduleHeight,
            child: _ModuleSidebar(shell: shell),
          ),
          const SizedBox(height: 16),
          _BottomSurfaceTabs(shell: shell, viewportProfile: viewportProfile),
          if (layoutBinding.bottomPanelExpanded) ...[
            const SizedBox(height: 10),
            SizedBox(
              height: bottomSurfaceHeight,
              child: KeyedSubtree(
                key: ValueKey(layoutBinding.activeBottomPanelId),
                child: bottomSurface,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _WorkspaceSidebar extends StatelessWidget {
  const _WorkspaceSidebar({required this.shell});

  final ShellModel shell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = shell.workspaceController.activeProject;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: ListView(
          key: const ValueKey('workspace-sidebar-scroll'),
          children: [
            Text('Project Graph', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _ProjectSummaryCard(project: project),
            const SizedBox(height: 12),
            _ProjectWorkflowCard(
              platformTarget: shell.platformTarget,
              project: project,
              adapterCapabilities: shell.adapterCapabilities,
            ),
            const SizedBox(height: 12),
            _CompilerHandshakeCard(project: project),
            const SizedBox(height: 12),
            _ProjectOperationsCard(shell: shell),
            if (shell.pendingWorkspaceFileCommandConfirmation != null) ...[
              const SizedBox(height: 12),
              _WorkspaceFileCommandConfirmationCard(
                pending: shell.pendingWorkspaceFileCommandConfirmation!,
                onConfirm: () {
                  shell.confirmPendingWorkspaceFileCommand();
                },
                onCancel: shell.cancelPendingWorkspaceFileCommand,
              ),
            ],
            const SizedBox(height: 12),
            _RequiredHandoffsCard(
              platformTarget: shell.platformTarget,
              project: project,
              adapterCapabilities: shell.adapterCapabilities,
            ),
            if (project.workspaceMembers.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Workspace Members', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final member in project.workspaceMembers)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _WorkspaceMemberTile(memberPath: member),
                ),
            ],
            if (project.packages.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Packages', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final package in project.packages)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ProjectPackageTile(package: package),
                ),
            ],
            if (project.dependencies.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Dependencies', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final dependency in project.dependencies)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ProjectDependencyTile(dependency: dependency),
                ),
            ],
            if (shell.workspaceController.targets.isNotEmpty) ...[
              const SizedBox(height: 18),
              Text('Targets', style: theme.textTheme.titleMedium),
              const SizedBox(height: 12),
              for (final target in shell.workspaceController.targets)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _ProjectTargetTile(
                    target: target,
                    active:
                        target.filePath ==
                        shell.workspaceController.activeFilePath,
                    onTap: () => shell.workspaceController.openTarget(target),
                  ),
                ),
            ],
            const SizedBox(height: 18),
            Text('Files', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            for (final file in shell.workspaceController.files)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: _WorkspaceFileTile(
                  file: file,
                  active: file == shell.workspaceController.activeFilePath,
                  onTap: () => shell.workspaceController.openFile(file),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ProjectSummaryCard extends StatelessWidget {
  const _ProjectSummaryCard({required this.project});

  final ProjectGraphSnapshot project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF1ECE3),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(project.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(project.workspaceRoot, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(project.kind.label)),
                Chip(label: Text('lock ${project.lockState.label}')),
                Chip(label: Text('vendor ${project.vendorState.label}')),
                Chip(label: Text('${project.packageCount} package')),
                Chip(label: Text('${project.workspaceMemberCount} member')),
                Chip(label: Text('${project.dependencyCount} dependency')),
                Chip(label: Text('${project.targetCount} target')),
                Chip(label: Text('${project.editorFileCount} file')),
              ],
            ),
            const SizedBox(height: 10),
            Text(project.toolchain.detail, style: theme.textTheme.bodySmall),
            if (project.manifestPath != null) ...[
              const SizedBox(height: 6),
              Text(
                'manifest ${project.manifestPath}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (project.toolchainPinPath != null) ...[
              const SizedBox(height: 4),
              Text(
                'toolchain ${project.toolchainPinPath}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (project.styioConfigPath != null) ...[
              const SizedBox(height: 4),
              Text(
                'styio ${project.styioConfigPath}',
                style: theme.textTheme.bodySmall,
              ),
            ],
            if (project.notes.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(project.notes.first, style: theme.textTheme.bodySmall),
            ],
          ],
        ),
      ),
    );
  }
}

class _ProjectWorkflowCard extends StatelessWidget {
  const _ProjectWorkflowCard({
    required this.platformTarget,
    required this.project,
    required this.adapterCapabilities,
  });

  final PlatformTarget platformTarget;
  final ProjectGraphSnapshot project;
  final List<AdapterCapabilitySnapshot> adapterCapabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selection = selectBackendExecutionRoute(
      platformTarget: platformTarget,
      projectGraph: project,
      adapterCapabilities: adapterCapabilities,
    );
    final summary = summarizeExecutionRoute(
      platformTarget: platformTarget,
      projectGraph: project,
      adapterCapabilities: adapterCapabilities,
    );

    return DecoratedBox(
      key: const ValueKey('project-workflow-card'),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF0E5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Project Workflow', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(selection.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Text(selection.detail, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(selection.adapterKind.label)),
                Chip(label: Text(selection.routeKind.wireValue)),
                Chip(
                  label: Text(selection.allowed ? 'live-capable' : 'blocked'),
                ),
                if (project.compilePlanConsumerAdvertised)
                  const Chip(label: Text('compile-plan detected')),
                Chip(
                  label: Text(
                    summary.jitRoute.blocked ? 'JIT blocked' : 'JIT live',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompilerHandshakeCard extends StatelessWidget {
  const _CompilerHandshakeCard({required this.project});

  final ProjectGraphSnapshot project;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final compiler = project.activeCompiler;

    return DecoratedBox(
      key: const ValueKey('compiler-handshake-card'),
      decoration: BoxDecoration(
        color: const Color(0xFFE8EDF5),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Compiler Handshake', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            if (compiler == null)
              Text(
                'No local styio machine-info handshake has been resolved yet.',
                style: theme.textTheme.bodySmall,
              )
            else ...[
              Text(
                '${compiler.tool} ${compiler.compilerVersion} · ${compiler.channel}',
                style: theme.textTheme.titleSmall,
              ),
              const SizedBox(height: 6),
              Text(
                'variant ${compiler.variant} · phase ${compiler.integrationPhase}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Text(compiler.contractSummary, style: theme.textTheme.bodySmall),
              const SizedBox(height: 6),
              Text(
                compiler.capabilitySummary,
                style: theme.textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(project.toolchain.source.label)),
                if (project.toolchain.channel != null)
                  Chip(label: Text('channel ${project.toolchain.channel}')),
                if (compiler != null &&
                    compiler.supportsContract('compile_plan'))
                  const Chip(label: Text('compile-plan ready')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _RequiredHandoffsCard extends StatelessWidget {
  const _RequiredHandoffsCard({
    required this.platformTarget,
    required this.project,
    required this.adapterCapabilities,
  });

  final PlatformTarget platformTarget;
  final ProjectGraphSnapshot project;
  final List<AdapterCapabilitySnapshot> adapterCapabilities;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handoffs = summarizeRequiredHandoffs(
      platformTarget: platformTarget,
      projectGraph: project,
      adapterCapabilities: adapterCapabilities,
    );
    final blockingCount = handoffs.where((handoff) => handoff.blocking).length;
    final styioCount = handoffs
        .where((handoff) => handoff.owner == HandoffOwner.styio)
        .length;
    final pafioCount = handoffs
        .where((handoff) => handoff.owner == HandoffOwner.pafio)
        .length;

    return DecoratedBox(
      key: const ValueKey('required-handoffs-card'),
      decoration: BoxDecoration(
        color: const Color(0xFFF3ECE7),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Required Handoffs', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'This card only states what `Vityo` still needs from upstream machine contracts. It does not prescribe upstream internals.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('$blockingCount blocking')),
                Chip(label: Text('$styioCount styio')),
                Chip(label: Text('$pafioCount pafio')),
              ],
            ),
            const SizedBox(height: 10),
            if (handoffs.isEmpty)
              Text(
                'No product-side handoffs are currently outstanding for this route.',
                style: theme.textTheme.bodySmall,
              )
            else
              for (var index = 0; index < handoffs.length; index += 1) ...[
                if (index > 0) const SizedBox(height: 10),
                _RequiredHandoffTile(handoff: handoffs[index]),
              ],
          ],
        ),
      ),
    );
  }
}

class _ProjectOperationsCard extends StatelessWidget {
  const _ProjectOperationsCard({required this.shell});

  final ShellModel shell;

  String? _stringPayload(Map<String, dynamic>? payload, String key) {
    final value = payload?[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  List<String> _blockedWorkflowPreview() {
    return StyioCommandRegistry.workflowCommands
        .map((command) {
          final reason = shell.blockedReasonForCommand(command.id);
          if (reason == null) {
            return null;
          }
          return '${command.label}: $reason';
        })
        .whereType<String>()
        .take(3)
        .toList(growable: false);
  }

  Color _laneColor(BuildContext context, String status) {
    switch (status) {
      case 'succeeded':
      case 'resolved':
      case 'ready':
        return const Color(0xFFE3F1E1);
      case 'failed':
        return const Color(0xFFF5E1DE);
      case 'blocked':
        return const Color(0xFFF6E9D7);
      case 'running':
        return const Color(0xFFE3ECF6);
      case 'idle':
      case 'pending':
        return const Color(0xFFEEE9F2);
      default:
        return Theme.of(context).colorScheme.surfaceContainerHighest;
    }
  }

  String _executionStatusLabel(ExecutionSession? session) {
    if (session == null) {
      return 'idle';
    }
    return switch (session.status) {
      ExecutionSessionStatus.succeeded => 'succeeded',
      ExecutionSessionStatus.failed => 'failed',
      ExecutionSessionStatus.blocked => 'blocked',
      ExecutionSessionStatus.running => 'running',
    };
  }

  String _dependencyStatusLabel(DependencySourceCommandResult? result) {
    if (result == null) {
      return 'idle';
    }
    return switch (result.status) {
      DependencySourceCommandStatus.succeeded => 'succeeded',
      DependencySourceCommandStatus.failed => 'failed',
      DependencySourceCommandStatus.blocked => 'blocked',
    };
  }

  String _toolchainStatusLabel(ToolchainCommandResult? result) {
    if (result == null) {
      return 'resolved';
    }
    return switch (result.status) {
      ToolchainCommandStatus.succeeded => 'succeeded',
      ToolchainCommandStatus.failed => 'failed',
      ToolchainCommandStatus.blocked => 'blocked',
    };
  }

  String _deploymentStatusLabel(DeploymentCommandResult? result) {
    if (result == null) {
      return 'ready';
    }
    return switch (result.status) {
      DeploymentCommandStatus.succeeded => 'succeeded',
      DeploymentCommandStatus.failed => 'failed',
      DeploymentCommandStatus.blocked => 'blocked',
    };
  }

  Widget _buildCommandChip(
    BuildContext context,
    ThemeData theme,
    AppCommandDescriptor command,
  ) {
    final blockedReason = shell.blockedReasonForCommand(command.id);
    return Tooltip(
      message: blockedReason ?? command.description,
      child: ActionChip(
        key: ValueKey('project-operation-${command.id.name}'),
        onPressed: blockedReason == null
            ? () => shell.executeCommand(command.id)
            : null,
        avatar: Icon(
          _commandIcon(command.id),
          size: 18,
          color: blockedReason == null
              ? theme.colorScheme.primary
              : theme.disabledColor,
        ),
        label: Text(command.label),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final project = shell.workspaceController.activeProject;
    final activeCompiler = project.activeCompiler;
    final distribution = project.packageDistribution;
    final publishablePackages = distribution?.publishablePackages ?? 0;
    final blockedPackages = distribution?.blockedPackages ?? 0;
    final blockedWorkflowPreview = _blockedWorkflowPreview();
    final lastToolchain = shell.lastToolchainCommand;
    final lastDeployment = shell.lastDeploymentCommand;
    final lastExecution = shell.lastExecutionSession;
    final lastDependency = shell.lastDependencySourceCommand;
    final executionStatus = _executionStatusLabel(lastExecution);
    final dependencyStatus = _dependencyStatusLabel(lastDependency);
    final toolchainStatus = _toolchainStatusLabel(lastToolchain);
    final deploymentStatus = _deploymentStatusLabel(lastDeployment);
    final deploymentPackage = _stringPayload(
      lastDeployment?.payload,
      'package',
    );
    final deploymentArchive = _stringPayload(
      lastDeployment?.payload,
      'archive_path',
    );
    final vendorMetadata = _stringPayload(
      lastDependency?.payload,
      'metadata_path',
    );
    final vendorRoot = _stringPayload(lastDependency?.payload, 'vendor_root');
    final dependencyPackages = lastDependency?.payload?['packages'];
    final managedInstalls =
        project.toolchainEnvironment?.managedToolchains.installed.length ?? 0;

    return DecoratedBox(
      key: const ValueKey('project-operations-card'),
      decoration: BoxDecoration(
        color: const Color(0xFFEDE7F0),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Project Workflow', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'One shell-owned surface for execution, dependency materialization, toolchain routing, and deployment preflight.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _WorkflowStatusChip(
                  label: 'execution $executionStatus',
                  color: _laneColor(context, executionStatus),
                ),
                _WorkflowStatusChip(
                  label: 'dependencies $dependencyStatus',
                  color: _laneColor(context, dependencyStatus),
                ),
                _WorkflowStatusChip(
                  label: 'environment $toolchainStatus',
                  color: _laneColor(context, toolchainStatus),
                ),
                _WorkflowStatusChip(
                  label: 'deployment $deploymentStatus',
                  color: _laneColor(context, deploymentStatus),
                ),
                Chip(
                  label: Text(
                    activeCompiler == null
                        ? 'compiler unresolved'
                        : 'compiler ${activeCompiler.compilerVersion}',
                  ),
                ),
                Chip(
                  label: Text(
                    project.toolchainPinPath == null
                        ? 'pin unresolved'
                        : 'pin active',
                  ),
                ),
                Chip(label: Text('publishable $publishablePackages')),
                Chip(label: Text('blocked $blockedPackages')),
                Chip(
                  label: Text(
                    'workflow blockers ${StyioCommandRegistry.workflowCommands.where((command) => shell.blockedReasonForCommand(command.id) != null).length}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (blockedWorkflowPreview.isNotEmpty) ...[
              Text('Current Blockers', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              for (final blocker in blockedWorkflowPreview) ...[
                Text(blocker, style: theme.textTheme.bodySmall),
                const SizedBox(height: 4),
              ],
              const SizedBox(height: 8),
            ],
            _WorkflowLanePanel(
              title: 'Execution',
              statusLabel: executionStatus,
              statusColor: _laneColor(context, executionStatus),
              detail: lastExecution == null
                  ? 'Run has not been routed through the active project shell yet.'
                  : '${lastExecution.kind} ${lastExecution.status.name}: ${lastExecution.statusMessage}',
              metaLabels: [
                'runtime ${shell.lastRuntimeEvents.length}',
                if (lastExecution != null) ...[
                  'diagnostics ${lastExecution.diagnostics.length}',
                  'stdout ${lastExecution.stdoutEvents.length}',
                  'stderr ${lastExecution.stderrEvents.length}',
                ],
              ],
              actions: StyioCommandRegistry.executionCommands
                  .map((command) => _buildCommandChip(context, theme, command))
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            _WorkflowLanePanel(
              title: 'Dependencies',
              statusLabel: dependencyStatus,
              statusColor: _laneColor(context, dependencyStatus),
              detail: lastDependency == null
                  ? 'Fetch/vendor has not been materialized in this shell session yet.'
                  : '${lastDependency.command} ${lastDependency.status.name}: ${lastDependency.statusMessage}',
              metaLabels: [
                'git ${project.sourceState?.declaredGitDependencies ?? 0}',
                'registry ${project.sourceState?.declaredRegistryDependencies ?? 0}',
                'vendor ${project.vendorState.label}',
                if (dependencyPackages is num)
                  'packages ${dependencyPackages.toInt()}',
                if (vendorRoot != null) 'vendor root',
                if (vendorMetadata != null) 'vendor metadata',
              ],
              actions: StyioCommandRegistry.dependencyCommands
                  .map((command) => _buildCommandChip(context, theme, command))
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            _WorkflowLanePanel(
              title: 'Environment',
              statusLabel: toolchainStatus,
              statusColor: _laneColor(context, toolchainStatus),
              detail: lastToolchain == null
                  ? project.toolchain.detail
                  : '${lastToolchain.command} ${lastToolchain.status.name}: ${lastToolchain.statusMessage}',
              metaLabels: [
                'source ${project.toolchain.source.label}',
                'managed $managedInstalls',
                if (activeCompiler != null) 'channel ${activeCompiler.channel}',
                if (project.toolchainPinPath != null) 'pin present',
              ],
              actions: StyioCommandRegistry.toolchainCommands
                  .map((command) => _buildCommandChip(context, theme, command))
                  .toList(growable: false),
            ),
            const SizedBox(height: 12),
            _WorkflowLanePanel(
              title: 'Deployment',
              statusLabel: deploymentStatus,
              statusColor: _laneColor(context, deploymentStatus),
              detail: lastDeployment == null
                  ? 'Pack and publish preflight are ready to route through the active project shell.'
                  : '${lastDeployment.command} ${lastDeployment.status.name}: ${lastDeployment.statusMessage}',
              metaLabels: [
                'packages ${distribution?.packages.length ?? 0}',
                'publishable $publishablePackages',
                'blocked $blockedPackages',
                if (deploymentPackage != null) 'package $deploymentPackage',
                if (deploymentArchive != null) 'archive ready',
              ],
              actions: StyioCommandRegistry.deploymentCommands
                  .map((command) => _buildCommandChip(context, theme, command))
                  .toList(growable: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowLanePanel extends StatelessWidget {
  const _WorkflowLanePanel({
    required this.title,
    required this.statusLabel,
    required this.statusColor,
    required this.detail,
    required this.metaLabels,
    required this.actions,
  });

  final String title;
  final String statusLabel;
  final Color statusColor;
  final String detail;
  final List<String> metaLabels;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: Text(title, style: theme.textTheme.titleSmall)),
                _WorkflowStatusChip(label: statusLabel, color: statusColor),
              ],
            ),
            const SizedBox(height: 6),
            Text(detail, style: theme.textTheme.bodySmall),
            if (metaLabels.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: metaLabels
                    .map((label) => Chip(label: Text(label)))
                    .toList(growable: false),
              ),
            ],
            if (actions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ],
        ),
      ),
    );
  }
}

class _WorkflowStatusChip extends StatelessWidget {
  const _WorkflowStatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(label, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }
}

class _RequiredHandoffTile extends StatelessWidget {
  const _RequiredHandoffTile({required this.handoff});

  final RequiredHandoff handoff;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.68),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Chip(label: Text(handoff.owner.label)),
                Chip(label: Text(handoff.blocking ? 'blocking' : 'follow-up')),
              ],
            ),
            const SizedBox(height: 8),
            Text(handoff.title, style: theme.textTheme.titleSmall),
            const SizedBox(height: 6),
            Text(handoff.detail, style: theme.textTheme.bodySmall),
            const SizedBox(height: 6),
            Text(handoff.docPath, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceFileTile extends StatelessWidget {
  const _WorkspaceFileTile({
    required this.file,
    required this.active,
    required this.onTap,
  });

  final String file;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF1ECE3) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Icon(
              active ? Icons.article_rounded : Icons.article_outlined,
              size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(file, style: theme.textTheme.bodyMedium)),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceFileCommandConfirmationCard extends StatelessWidget {
  const _WorkspaceFileCommandConfirmationCard({
    required this.pending,
    required this.onConfirm,
    required this.onCancel,
  });

  final WorkspaceFileCommandRouteResult pending;
  final VoidCallback onConfirm;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = pending.confirmationPlan;
    final request = pending.request;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFF2D7),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5A93B)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              plan?.title ?? 'Confirm workspace file command',
              key: const ValueKey('workspace-file-confirmation-title'),
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              pending.message,
              key: const ValueKey('workspace-file-confirmation-message'),
              style: theme.textTheme.bodySmall,
            ),
            if (request != null) ...[
              const SizedBox(height: 8),
              Text(
                '${request.kind.wireValue}: ${request.path}',
                key: const ValueKey('workspace-file-confirmation-target'),
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.tonalIcon(
                  key: const ValueKey('workspace-file-confirmation-apply'),
                  onPressed: onConfirm,
                  icon: const Icon(Icons.check_rounded),
                  label: const Text('Confirm'),
                ),
                OutlinedButton.icon(
                  key: const ValueKey('workspace-file-confirmation-cancel'),
                  onPressed: onCancel,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectTargetTile extends StatelessWidget {
  const _ProjectTargetTile({
    required this.target,
    required this.active,
    required this.onTap,
  });

  final ProjectTargetDescriptor target;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: active ? const Color(0xFFF1ECE3) : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            const Icon(Icons.track_changes_rounded, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${target.kind.name} ${target.name}'),
                  Text(target.packageName, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectPackageTile extends StatelessWidget {
  const _ProjectPackageTile({required this.package});

  final ProjectPackageSnapshot package;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4ED),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    package.packageName,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Chip(label: Text(package.version)),
              ],
            ),
            const SizedBox(height: 6),
            Text(package.rootPath, style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text('${package.targets.length} target')),
                Chip(label: Text('${package.dependencies.length} dependency')),
                Chip(
                  label: Text(
                    package.isWorkspaceMember
                        ? 'workspace member'
                        : 'root package',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceMemberTile extends StatelessWidget {
  const _WorkspaceMemberTile({required this.memberPath});

  final String memberPath;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF0F3EA),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            const Icon(Icons.folder_open_rounded, size: 18),
            const SizedBox(width: 10),
            Expanded(
              child: Text(memberPath, style: theme.textTheme.bodyMedium),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProjectDependencyTile extends StatelessWidget {
  const _ProjectDependencyTile({required this.dependency});

  final ProjectDependencySnapshot dependency;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF5F0E8),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(dependency.kind.label)),
                if (dependency.isWorkspaceReference)
                  const Chip(label: Text('workspace ref')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '${dependency.sourcePackageName} -> ${dependency.dependencyName}',
              style: theme.textTheme.titleSmall,
            ),
            const SizedBox(height: 6),
            Text(dependency.requirement, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _ModuleSidebar extends StatelessWidget {
  const _ModuleSidebar({required this.shell});

  final ShellModel shell;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: ListView(
          children: [
            Text('Adapter Routes', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Product-owned capability surface across CLI, FFI, and Cloud adapters.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (final capability in shell.adapterCapabilities)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _AdapterCapabilityTile(capability: capability),
              ),
            const SizedBox(height: 8),
            Text('Module Host', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Capability matrix filtered for ${shell.platformTarget.label}.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (var index = 0; index < shell.visibleModules.length; index += 1)
              Padding(
                padding: EdgeInsets.only(
                  bottom: index == shell.visibleModules.length - 1 ? 0 : 10,
                ),
                child: _ModuleTile(
                  module: shell.visibleModules[index],
                  mounted: shell.visibleModules[index].isMountedOn(
                    shell.platformTarget,
                  ),
                  platformTarget: shell.platformTarget,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _AdapterCapabilityTile extends StatelessWidget {
  const _AdapterCapabilityTile({required this.capability});

  final AdapterCapabilitySnapshot capability;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8F4ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              capability.adapterKind.label,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'language ${capability.languageService.level.label} · project ${capability.projectGraph.level.label}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 4),
            Text(
              'execution ${capability.execution.level.label} · runtime ${capability.runtimeEvents.level.label}',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Text(capability.execution.detail, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _BottomSurfaceTabs extends StatelessWidget {
  const _BottomSurfaceTabs({
    required this.shell,
    required this.viewportProfile,
  });

  final ShellModel shell;
  final ViewportProfile viewportProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabs = <Widget>[
      _SurfaceTabChip(
        label: 'Runtime',
        active: shell.activeBottomTab == BottomSurfaceTab.runtime,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.runtime),
      ),
      _SurfaceTabChip(
        label: 'Terminal',
        active: shell.activeBottomTab == BottomSurfaceTab.terminal,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.terminal),
      ),
      _SurfaceTabChip(
        label: 'Commands',
        active: shell.activeBottomTab == BottomSurfaceTab.commandPalette,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.commandPalette),
      ),
      _SurfaceTabChip(
        label: 'Agent',
        active: shell.activeBottomTab == BottomSurfaceTab.agent,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.agent),
      ),
      _SurfaceTabChip(
        label: 'SCM',
        active: shell.activeBottomTab == BottomSurfaceTab.sourceControl,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.sourceControl),
      ),
      _SurfaceTabChip(
        label: 'Search',
        active: shell.activeBottomTab == BottomSurfaceTab.search,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.search),
      ),
      _SurfaceTabChip(
        label: 'Problems',
        active: shell.activeBottomTab == BottomSurfaceTab.problems,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.problems),
      ),
      _SurfaceTabChip(
        label: 'Tests',
        active: shell.activeBottomTab == BottomSurfaceTab.testing,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.testing),
      ),
      _SurfaceTabChip(
        label: 'Extensions',
        active: shell.activeBottomTab == BottomSurfaceTab.extensions,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.extensions),
      ),
      _SurfaceTabChip(
        label: 'Debug',
        active: shell.activeBottomTab == BottomSurfaceTab.debug,
        onTap: () => shell.selectBottomTab(BottomSurfaceTab.debug),
      ),
      if (viewportProfile.isMobile)
        _SurfaceTabChip(
          label: 'Settings',
          active: shell.activeBottomTab == BottomSurfaceTab.settings,
          onTap: () => shell.selectBottomTab(BottomSurfaceTab.settings),
        ),
    ];

    if (viewportProfile.isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 10, runSpacing: 10, children: tabs),
          const SizedBox(height: 8),
          Text(
            'Mobile shell keeps runtime, terminal, commands, agent, source control, search, problems, testing, extensions, debug, and settings on one vertical route. Hardware keyboard shortcuts remain optional.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var index = 0; index < tabs.length; index += 1) ...[
            if (index > 0) const SizedBox(width: 10),
            tabs[index],
          ],
          const SizedBox(width: 16),
          for (final command in StyioCommandRegistry.primaryCommands)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: Tooltip(
                message:
                    shell.blockedReasonForCommand(command.id) ??
                    '${command.description} (${command.shortcutHint})',
                child: ActionChip(
                  key: ValueKey('command-strip-${command.id.name}'),
                  onPressed: shell.blockedReasonForCommand(command.id) == null
                      ? () => shell.executeCommand(command.id)
                      : null,
                  avatar: Icon(
                    _commandIcon(command.id),
                    size: 18,
                    color: shell.blockedReasonForCommand(command.id) == null
                        ? theme.colorScheme.primary
                        : theme.disabledColor,
                  ),
                  label: Text('${command.label} · ${command.shortcutHint}'),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Tooltip(
              message: 'Open settings and profile routes. (Cmd/Ctrl+,)',
              child: ActionChip(
                key: const ValueKey('command-strip-openSettings'),
                onPressed: () =>
                    shell.executeCommand(AppCommandId.openSettings),
                avatar: Icon(
                  Icons.settings_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                label: const Text('Settings · Cmd/Ctrl+,'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _terminalRuntimeEventSummary(RuntimeEventEnvelope event) {
  final payloadMessage =
      event.payload['message'] ??
      event.payload['text'] ??
      event.payload['line'] ??
      event.payload['data'];
  if (payloadMessage == null) {
    return '${event.eventKind}: ${event.origin}';
  }
  return '${event.eventKind}: $payloadMessage';
}

IconData _commandIcon(AppCommandId commandId) {
  switch (commandId) {
    case AppCommandId.run:
      return Icons.play_arrow_rounded;
    case AppCommandId.fetchDependencies:
      return Icons.cloud_download_rounded;
    case AppCommandId.vendorDependencies:
      return Icons.inventory_2_rounded;
    case AppCommandId.useActiveCompiler:
      return Icons.sync_alt_rounded;
    case AppCommandId.pinActiveCompiler:
      return Icons.push_pin_outlined;
    case AppCommandId.clearPinnedCompiler:
      return Icons.push_pin_rounded;
    case AppCommandId.bootstrapStyioToolchain:
      return Icons.build_circle_outlined;
    case AppCommandId.executeToolchainInstallPlan:
      return Icons.download_for_offline_outlined;
    case AppCommandId.selectClangCppVersion:
      return Icons.developer_board_rounded;
    case AppCommandId.packProject:
      return Icons.archive_rounded;
    case AppCommandId.preparePublish:
      return Icons.publish_rounded;
    case AppCommandId.refreshModules:
      return Icons.refresh_rounded;
    case AppCommandId.save:
      return Icons.save_rounded;
    case AppCommandId.saveAll:
      return Icons.save_as_rounded;
    case AppCommandId.showRuntime:
      return Icons.terminal_rounded;
    case AppCommandId.showAgent:
      return Icons.smart_toy_outlined;
    case AppCommandId.showDebug:
      return Icons.bug_report_outlined;
    case AppCommandId.toggleBreakpoint:
      return Icons.radio_button_checked_rounded;
    case AppCommandId.startDebugging:
      return Icons.play_circle_outline_rounded;
    case AppCommandId.stopDebugging:
      return Icons.stop_circle_outlined;
    case AppCommandId.continueDebugging:
      return Icons.not_started_outlined;
    case AppCommandId.stepOver:
      return Icons.skip_next_rounded;
    case AppCommandId.selectDebugThread:
      return Icons.account_tree_outlined;
    case AppCommandId.selectDebugStackFrame:
      return Icons.layers_outlined;
    case AppCommandId.nextDiagnostic:
      return Icons.keyboard_double_arrow_down_rounded;
    case AppCommandId.previousDiagnostic:
      return Icons.keyboard_double_arrow_up_rounded;
    case AppCommandId.applyQuickFix:
      return Icons.auto_fix_high_rounded;
    case AppCommandId.previewQuickFix:
      return Icons.difference_outlined;
    case AppCommandId.refreshLanguageService:
      return Icons.manage_search_rounded;
    case AppCommandId.refreshWorkspaceDiagnostics:
      return Icons.rule_folder_outlined;
    case AppCommandId.refreshSourceControl:
      return Icons.account_tree_rounded;
    case AppCommandId.previewSourceControlDiff:
      return Icons.difference_outlined;
    case AppCommandId.stageSourceControl:
      return Icons.add_task_rounded;
    case AppCommandId.unstageSourceControl:
      return Icons.remove_done_outlined;
    case AppCommandId.planSourceControlBranchSwitch:
      return Icons.alt_route_rounded;
    case AppCommandId.planSourceControlCommitDraft:
      return Icons.commit_rounded;
    case AppCommandId.collectAgentCodingCheckpoint:
      return Icons.assignment_turned_in_outlined;
    case AppCommandId.collectProjectLanguageContext:
      return Icons.schema_outlined;
    case AppCommandId.retryAgentProvider:
      return Icons.replay_rounded;
    case AppCommandId.failoverAgentProvider:
      return Icons.swap_horiz_rounded;
    case AppCommandId.replayAgentPrompt:
      return Icons.history_edu_outlined;
    case AppCommandId.goToDefinition:
      return Icons.subdirectory_arrow_right_rounded;
    case AppCommandId.openWorkspaceFile:
      return Icons.file_open_outlined;
    case AppCommandId.createWorkspaceFile:
      return Icons.note_add_outlined;
    case AppCommandId.renameWorkspaceFile:
      return Icons.drive_file_rename_outline_rounded;
    case AppCommandId.deleteWorkspaceFile:
      return Icons.delete_outline_rounded;
    case AppCommandId.revealWorkspaceFile:
      return Icons.folder_open_outlined;
    case AppCommandId.searchWorkspace:
      return Icons.search_rounded;
    case AppCommandId.previewWorkspaceReplace:
      return Icons.find_replace_rounded;
    case AppCommandId.applyWorkspaceReplace:
      return Icons.playlist_add_check_rounded;
    case AppCommandId.runBuild:
      return Icons.construction_rounded;
    case AppCommandId.formatActiveDocument:
      return Icons.format_align_left_rounded;
    case AppCommandId.runStaticAnalysis:
      return Icons.fact_check_outlined;
    case AppCommandId.runTests:
      return Icons.science_outlined;
    case AppCommandId.rerunFailedTests:
      return Icons.replay_circle_filled_outlined;
    case AppCommandId.debugFailedTests:
      return Icons.bug_report_rounded;
    case AppCommandId.runTestConfiguration:
      return Icons.playlist_play_rounded;
    case AppCommandId.debugTestConfiguration:
      return Icons.science_rounded;
    case AppCommandId.nextReference:
      return Icons.keyboard_arrow_down_rounded;
    case AppCommandId.previousReference:
      return Icons.keyboard_arrow_up_rounded;
    case AppCommandId.renameSymbol:
      return Icons.drive_file_rename_outline_rounded;
    case AppCommandId.safeDelete:
      return Icons.delete_sweep_outlined;
    case AppCommandId.inlineVariable:
      return Icons.merge_type_rounded;
    case AppCommandId.openFile:
      return Icons.folder_open_rounded;
    case AppCommandId.reloadFile:
      return Icons.refresh_rounded;
    case AppCommandId.openSettings:
      return Icons.settings_outlined;
    default:
      return Icons.help_outline_rounded;
  }
}

class _SurfaceTabChip extends StatelessWidget {
  const _SurfaceTabChip({
    required this.label,
    required this.active,
    required this.onTap,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Ink(
        decoration: BoxDecoration(
          color: active ? const Color(0xFFEFE7DA) : const Color(0xFFF7F2E9),
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Text(label),
      ),
    );
  }
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({
    required this.module,
    required this.mounted,
    required this.platformTarget,
  });

  final ModuleDefinition module;
  final bool mounted;
  final PlatformTarget platformTarget;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rule = module.ruleFor(platformTarget);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: mounted ? const Color(0xFFF3ECDD) : const Color(0xFFF8F4ED),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    module.manifest.displayName,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Chip(label: Text(mounted ? 'Mounted' : 'Visible')),
              ],
            ),
            const SizedBox(height: 8),
            Text(module.manifest.description, style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(module.manifest.kind.wireValue)),
                Chip(label: Text(module.manifest.slot.wireValue)),
                Chip(label: Text(rule.distributionChannel)),
              ],
            ),
            const SizedBox(height: 10),
            Text(rule.note, style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
