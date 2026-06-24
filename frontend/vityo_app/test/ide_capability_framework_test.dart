import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test('IDE capability framework provides a cross-layer closure manifest', () {
    final snapshot = const VityoIdeCapabilityFramework().snapshot();
    final json = snapshot.toJson();
    final ids = snapshot.entries.map((entry) => entry.id).toSet();
    final entriesById = <String, IdeCapabilityDescriptor>{
      for (final entry in snapshot.entries) entry.id: entry,
    };

    expect(snapshot.version, 'vityo-ide-capability-framework-v1');
    expect(snapshot.entries.length, ids.length);
    expect(ids, contains('service.styio-language'));
    expect(ids, contains('service.language-result-cache'));
    expect(ids, contains('agent.coding-loop'));
    expect(ids, contains('editor.document-model'));
    expect(ids, contains('interaction.search'));
    expect(ids, contains('interaction.source-control'));
    expect(ids, contains('interaction.testing'));
    expect(ids, contains('workspace.edit-application'));
    expect(ids, contains('workspace.diagnostics'));
    expect(ids, contains('runtime.terminal'));
    expect(ids, contains('presentation.problems-panel'));
    expect(ids, contains('presentation.shell'));
    expect(
      entriesById['interaction.search']?.status,
      IdeCapabilityStatus.scaffolded,
    );
    expect(
      entriesById['service.language-result-cache']?.summary,
      contains('snapshot metadata'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('match-level navigation callback'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('file quick open service'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('symbol search service'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('replace preview contract'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('Agent workspace replace preview/apply command routing'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('WorkspaceSearchIndexController stale-revision refresh'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('persisted result filter state'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('WorkspaceSearchWatcherPolicy'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('WorkspaceSearchWatcherRecoveryPlan'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('WorkspaceSearchWatcherEventBatchController'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('WorkspaceSearchWatcherRecoveryStore'),
    );
    expect(
      entriesById['interaction.search']?.summary,
      contains('WorkspaceSearchWatcherStreamBatcher'),
    );
    expect(
      entriesById['interaction.search']?.todo,
      contains('production watcher backpressure telemetry'),
    );
    expect(entriesById['interaction.search']?.runtimeMaturityBlocking, isFalse);
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('SourceControlHunkSelectionState'),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('SourceControlHunkDiscardConfirmationPlan'),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('partial patch results'),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('SourceControlDiffSessionStore'),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('diff-session restore/persist hooks'),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('hunk discard modal UI'),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('shell hunk discard confirmation routing'),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('SourceControlMergeWorkflowPlan'),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('SourceControlConflictResolutionPlan'),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('SourceControlConflictResolutionProviderRegistry'),
    );
    expect(
      entriesById['interaction.source-control']?.todo,
      contains('merge editor UI'),
    );
    expect(
      entriesById['interaction.source-control']?.runtimeMaturityBlocking,
      isFalse,
    );
    expect(
      entriesById['environment.platform']?.summary,
      contains('PlatformManagerRecoveryActionRouter settings routes'),
    );
    expect(
      entriesById['environment.platform']?.summary,
      contains('manager live-operation probe metadata'),
    );
    expect(
      entriesById['environment.platform']?.summary,
      contains('PlatformManagerLiveOperationProbeRegistry'),
    );
    expect(
      entriesById['environment.platform']?.todo,
      contains('live-operation smoke callbacks'),
    );
    expect(
      entriesById['environment.platform']?.runtimeMaturityBlocking,
      isFalse,
    );
    expect(
      entriesById['environment.credential-store']?.summary,
      contains('audit retention policies'),
    );
    expect(
      entriesById['environment.credential-store']?.summary,
      contains('PlatformSecureCredentialStorageAdapterRegistry'),
    );
    expect(
      entriesById['environment.credential-store']?.todo,
      contains('production adapters'),
    );
    expect(
      entriesById['environment.credential-store']?.runtimeMaturityBlocking,
      isFalse,
    );
    expect(
      entriesById['presentation.problems-panel']?.status,
      IdeCapabilityStatus.scaffolded,
    );
    expect(
      entriesById['presentation.shell']?.summary,
      contains('ShellLayoutPreferenceController live scaffold binding'),
    );
    expect(
      entriesById['presentation.shell']?.summary,
      contains('collapsed bottom-panel state'),
    );
    expect(entriesById['presentation.shell']?.runtimeMaturityBlocking, isFalse);
    expect(
      entriesById['presentation.problems-panel']?.summary,
      contains('workspace diagnostics grouping'),
    );
    expect(
      entriesById['presentation.problems-panel']?.runtimeMaturityBlocking,
      isFalse,
    );
    expect(
      entriesById['workspace.diagnostics']?.status,
      IdeCapabilityStatus.wired,
    );
    expect(
      entriesById['service.semantic-snapshot']?.status,
      IdeCapabilityStatus.wired,
    );
    expect(
      entriesById['service.semantic-snapshot']?.summary,
      contains('SemanticSnapshotProvider'),
    );
    expect(
      entriesById['service.semantic-snapshot']?.summary,
      contains('SemanticSnapshotPanelEventStateController'),
    );
    expect(
      entriesById['service.semantic-snapshot']?.summary,
      contains('SemanticSnapshotPanelEventStore persisted telemetry'),
    );
    expect(
      entriesById['service.semantic-snapshot']?.summary,
      contains(
        'StyioLanguageProviderReadinessReport active capability coverage',
      ),
    );
    expect(
      entriesById['service.semantic-snapshot']?.summary,
      contains('service-backed/local-fallback/unavailable counts'),
    );
    expect(
      entriesById['service.semantic-snapshot']?.summary,
      contains('StyioServiceDaemonRestartPlan'),
    );
    expect(
      entriesById['service.semantic-snapshot']?.summary,
      contains('StyioServiceDaemonRestartDispatchResult'),
    );
    expect(
      entriesById['service.semantic-snapshot']?.summary,
      contains('StyioServiceDaemonProcessSupervisor restart handler contract'),
    );
    expect(
      entriesById['service.semantic-snapshot']?.summary,
      contains(
        'StyioServiceDaemonProcessAdapter launch request/result contracts',
      ),
    );
    expect(
      entriesById['service.semantic-snapshot']?.summary,
      contains('StyioServiceDaemonSupervisorControls'),
    );
    expect(
      entriesById['service.semantic-snapshot']?.summary,
      contains('restart dispatch controls'),
    );
    expect(
      entriesById['service.semantic-snapshot']?.summary,
      contains('language-service refresh callback fallback'),
    );
    expect(
      entriesById['service.semantic-snapshot']?.todo,
      contains(
        'platform-specific StyioService process/service implementations',
      ),
    );
    expect(
      entriesById['service.semantic-snapshot']?.runtimeMaturityBlocking,
      isFalse,
    );
    expect(
      entriesById['service.remote-service']?.summary,
      contains('HostedBackendRetryActionExecutor'),
    );
    expect(
      entriesById['service.remote-service']?.summary,
      contains('HostedBackendRetryEndpointPlan'),
    );
    expect(
      entriesById['service.remote-service']?.summary,
      contains('retry/reopen/export/settings route contracts'),
    );
    expect(
      entriesById['service.remote-service']?.summary,
      contains('HostedControlPlaneRetryTransport'),
    );
    expect(
      entriesById['service.remote-service']?.todo,
      contains('hosted settings recovery handlers'),
    );
    expect(
      entriesById['service.remote-service']?.runtimeMaturityBlocking,
      isFalse,
    );
    expect(
      entriesById['editor.rendering']?.summary,
      contains('EditorRenderViewportBinding'),
    );
    expect(
      entriesById['editor.rendering']?.summary,
      contains('EditorRenderPipelinePlan'),
    );
    expect(
      entriesById['editor.rendering']?.summary,
      contains('concrete ScrollController facts'),
    );
    expect(
      entriesById['editor.rendering']?.todo,
      contains('high-volume editor layer backend'),
    );
    expect(entriesById['editor.rendering']?.runtimeMaturityBlocking, isFalse);
    expect(
      entriesById['workspace.file-explorer']?.summary,
      contains('create, rename, delete, and reveal contracts'),
    );
    expect(
      entriesById['workspace.file-explorer']?.summary,
      contains('Agent workspace file command routing'),
    );
    expect(
      entriesById['workspace.file-explorer']?.summary,
      contains('WorkspaceFileExplorerActionRisk'),
    );
    expect(
      entriesById['workspace.file-explorer']?.summary,
      contains('WorkspaceFileExplorerBatchActionPlan'),
    );
    expect(
      entriesById['workspace.file-explorer']?.summary,
      contains('WorkspaceFileExplorerIgnoreRules'),
    );
    expect(
      entriesById['workspace.file-explorer']?.summary,
      contains('WorkspaceFileExplorerWatchDebouncePolicy'),
    );
    expect(
      entriesById['workspace.file-explorer']?.summary,
      contains('WorkspaceFileExplorerWatchStreamBatcher'),
    );
    expect(
      entriesById['workspace.file-explorer']?.summary,
      contains('shell sidebar renders confirmation apply/cancel controls'),
    );
    expect(
      entriesById['workspace.file-explorer']?.todo,
      contains('watcher overflow/backpressure telemetry'),
    );
    expect(
      entriesById['workspace.file-explorer']?.runtimeMaturityBlocking,
      isFalse,
    );
    expect(
      entriesById['presentation.problems-panel']?.dependencies,
      contains('workspace.diagnostics'),
    );
    expect(
      entriesById['presentation.output-panel']?.summary,
      contains('Output Channels'),
    );
    expect(
      entriesById['presentation.output-panel']?.summary,
      contains('RuntimeOutputProducerAdapterRegistry'),
    );
    expect(
      entriesById['presentation.output-panel']?.summary,
      contains('language-service, debug-adapter, and agent producers'),
    );
    expect(
      entriesById['presentation.output-panel']?.summary,
      contains(
        'RuntimeOutputProducerBindingController multi-producer live binding',
      ),
    );
    expect(
      entriesById['presentation.output-panel']?.summary,
      contains('live RuntimeOutputLiveBuffer agent activity'),
    );
    expect(
      entriesById['presentation.output-panel']?.runtimeMaturityBlocking,
      isFalse,
    );
    expect(
      entriesById['interaction.diagnostics']?.dependencies,
      contains('workspace.diagnostics'),
    );
    expect(
      entriesById['interaction.diagnostics']?.summary,
      contains('RuntimeOutputLiveBuffer quick-fix action telemetry'),
    );
    expect(
      entriesById['interaction.diagnostics']?.summary,
      contains('WorkspaceDiagnosticsProducerCancellationRoute'),
    );
    expect(
      entriesById['interaction.diagnostics']?.summary,
      contains('WorkspaceDiagnosticsProducerProcessHandleRegistry'),
    );
    expect(
      entriesById['interaction.diagnostics']?.summary,
      contains('WorkspaceDiagnosticsProducerProcessHandleBinder'),
    );
    expect(
      entriesById['interaction.diagnostics']?.summary,
      contains('ShellRuntime diagnostics producer cancellation bridge'),
    );
    expect(
      entriesById['interaction.diagnostics']?.todo,
      contains('processHandleId/pid metadata'),
    );
    expect(
      entriesById['interaction.diagnostics']?.runtimeMaturityBlocking,
      isFalse,
    );
    expect(
      entriesById['interaction.diagnostics']?.summary,
      contains('WorkspaceQuickFixTelemetryStore review outcomes'),
    );
    expect(
      entriesById['workspace.diagnostics']?.summary,
      contains('WorkspaceDiagnosticsProducerProcessHandleRegistry'),
    );
    expect(
      entriesById['workspace.diagnostics']?.summary,
      contains('WorkspaceDiagnosticsProducerProcessHandleBinder'),
    );
    expect(
      entriesById['workspace.diagnostics']?.summary,
      contains('WorkspaceDiagnosticsController producer cancellation dispatch'),
    );
    expect(
      entriesById['workspace.diagnostics']?.summary,
      contains('WorkspaceQuickFixTelemetryStore persisted review outcomes'),
    );
    expect(
      entriesById['runtime.terminal']?.status,
      IdeCapabilityStatus.scaffolded,
    );
    expect(
      entriesById['runtime.terminal']?.summary,
      contains('TerminalInteractionController'),
    );
    expect(
      entriesById['runtime.terminal']?.summary,
      contains('RuntimeOutputProducerEmission adapter binding'),
    );
    expect(
      entriesById['runtime.terminal']?.summary,
      contains('script-PTY stdout/stderr merged output streams'),
    );
    expect(
      entriesById['runtime.terminal']?.summary,
      contains('TerminalSessionRecoveryPlan'),
    );
    expect(
      entriesById['runtime.terminal']?.todo,
      contains('native OS process signal delivery'),
    );
    expect(
      entriesById['runtime.terminal']?.summary,
      contains('recovery action controls'),
    );
    expect(entriesById['runtime.terminal']?.runtimeMaturityBlocking, isFalse);
    expect(
      entriesById['runtime.terminal']?.summary,
      contains('line-chunked ShellCommandResult stdout/stderr events'),
    );
    expect(
      entriesById['debugger.dap']?.summary,
      contains('DebugSessionTerminationPlan'),
    );
    expect(
      entriesById['debugger.dap']?.summary,
      contains('DebugSessionTerminationExecutor'),
    );
    expect(
      entriesById['debugger.dap']?.todo,
      contains('production process-kill handlers'),
    );
    expect(entriesById['debugger.dap']?.runtimeMaturityBlocking, isFalse);
    expect(
      entriesById['toolchain.manager']?.summary,
      contains(
        'Agent toolchain bootstrap context facts, suggested command ids, and prompt guidance',
      ),
    );
    expect(
      entriesById['toolchain.manager']?.summary,
      contains(
        'bootstrapStyioToolchain and executeToolchainInstallPlan registered command routing',
      ),
    );
    expect(
      entriesById['toolchain.manager']?.summary,
      contains('ToolchainBootstrapExecutionBridge'),
    );
    expect(
      entriesById['toolchain.manager']?.summary,
      contains('project bootstrap managed install planning'),
    );
    expect(
      entriesById['toolchain.manager']?.summary,
      contains('install execution recovery action rendering'),
    );
    expect(
      entriesById['toolchain.manager']?.summary,
      contains('installer recovery route handling'),
    );
    expect(
      entriesById['toolchain.manager']?.summary,
      contains('ToolchainBootstrapExecutionPlan'),
    );
    expect(
      entriesById['toolchain.manager']?.summary,
      contains('ToolchainBootstrapActionRouter dispatch contracts'),
    );
    expect(
      entriesById['toolchain.manager']?.summary,
      contains('ShellRuntimeModel bootstrap action dispatch'),
    );
    expect(
      entriesById['toolchain.manager']?.summary,
      contains('SettingsSurface bootstrap dispatch result rendering'),
    );
    expect(
      entriesById['toolchain.manager']?.todo,
      contains('concrete installer UX'),
    );
    expect(entriesById['toolchain.manager']?.runtimeMaturityBlocking, isFalse);
    expect(
      entriesById['extension.manifest']?.summary,
      contains('ExtensionActivationPlan'),
    );
    expect(entriesById['extension.manifest']?.runtimeMaturityBlocking, isFalse);
    expect(
      entriesById['extension.marketplace']?.summary,
      contains('ExtensionMarketplaceUpdatePlan'),
    );
    expect(
      entriesById['extension.marketplace']?.runtimeMaturityBlocking,
      isFalse,
    );
    expect(
      entriesById['interaction.testing']?.status,
      IdeCapabilityStatus.scaffolded,
    );
    expect(
      entriesById['interaction.testing']?.summary,
      contains('TestRunProvider'),
    );
    expect(
      entriesById['interaction.testing']?.summary,
      contains('TestDiscoveryProvider'),
    );
    expect(
      entriesById['interaction.testing']?.summary,
      contains('run history'),
    );
    expect(
      entriesById['interaction.testing']?.summary,
      contains('RuntimeOutputLiveBuffer test-result publishing'),
    );
    expect(
      entriesById['interaction.testing']?.summary,
      contains('failed-test DebugLaunchRoutePlan bridge'),
    );
    expect(
      entriesById['interaction.testing']?.summary,
      contains('TestingProviderCatalog health snapshots'),
    );
    expect(
      entriesById['interaction.testing']?.summary,
      contains('TestingProviderRetryPlan retry action facts'),
    );
    expect(
      entriesById['interaction.testing']?.summary,
      contains('FailedTestDebugCancellationRoute process-handle metadata'),
    );
    expect(
      entriesById['interaction.testing']?.summary,
      contains('FailedTestDebugCancellationHandleRegistry'),
    );
    expect(
      entriesById['interaction.testing']?.summary,
      contains('FailedTestDebugProcessHandleBinder'),
    );
    expect(
      entriesById['interaction.testing']?.todo,
      contains('processHandleId/pid metadata'),
    );
    expect(
      entriesById['interaction.testing']?.runtimeMaturityBlocking,
      isFalse,
    );
    expect(
      entriesById['interaction.testing']?.dependencies,
      contains('runtime.execution'),
    );
    expect(
      entriesById['runtime.execution']?.summary,
      contains(
        'ExtensionRuntimeTaskDataStoreTelemetrySink, ExtensionRuntimeTaskRetryPolicy',
      ),
    );
    expect(
      entriesById['runtime.execution']?.summary,
      contains('ExtensionRuntimeTaskCancellationRegistry'),
    );
    expect(
      entriesById['runtime.execution']?.summary,
      contains('ExtensionRuntimeTaskTerminationRequest/Result'),
    );
    expect(
      entriesById['runtime.execution']?.summary,
      contains('ExtensionRuntimeTaskProcessHandleBinder'),
    );
    expect(
      entriesById['runtime.execution']?.summary,
      contains('ShellManager/ProcessManager cancellation adapter factories'),
    );
    expect(
      entriesById['runtime.execution']?.todo,
      contains('processHandleId/pid metadata'),
    );
    expect(entriesById['runtime.execution']?.runtimeMaturityBlocking, isFalse);
    expect(
      entriesById['interaction.language-service-status']?.summary,
      contains('cache telemetry'),
    );
    expect(
      entriesById['interaction.language-service-status']?.summary,
      contains('syntax-validation readiness'),
    );
    expect(
      entriesById['interaction.language-service-status']?.summary,
      contains(
        'Styio language provider readiness derived from StyioService capability snapshots',
      ),
    );
    expect(
      entriesById['interaction.source-control']?.status,
      IdeCapabilityStatus.scaffolded,
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('staging action contracts'),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('Agent context snapshots'),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('last action results'),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('Agent stage/unstage command routing'),
    );
    expect(
      entriesById['extension.marketplace']?.status,
      IdeCapabilityStatus.scaffolded,
    );
    expect(
      entriesById['extension.marketplace']?.summary,
      contains('enable/disable/trust actions'),
    );
    expect(
      entriesById['interaction.command-palette']?.status,
      IdeCapabilityStatus.wired,
    );
    expect(
      entriesById['interaction.command-palette']?.summary,
      contains('blocked command availability reasons'),
    );
    expect(
      entriesById['interaction.command-palette']?.summary,
      contains('category contribution manifests'),
    );
    expect(
      entriesById['interaction.command-palette']?.summary,
      contains('shell-level DataStore preference hydration/persistence'),
    );
    expect(
      entriesById['interaction.command-palette']?.summary,
      contains('app bootstrap preference hydration'),
    );
    expect(
      entriesById['interaction.command-palette']?.summary,
      contains('top-level SettingsSurface preference saves'),
    );
    expect(
      entriesById['interaction.command-palette']?.summary,
      contains('keybinding remap persistence'),
    );
    expect(
      entriesById['interaction.command-palette']?.summary,
      contains('conflict review contracts'),
    );
    expect(
      entriesById['interaction.command-palette']?.summary,
      contains('platform-specific reserved shortcut host policies'),
    );
    expect(
      entriesById['interaction.command-palette']?.summary,
      contains('accessibility hints'),
    );
    expect(
      entriesById['editor.rendering']?.summary,
      contains('EditorSemanticThemeBinding render styles'),
    );
    expect(
      entriesById['editor.rendering']?.summary,
      contains('Flutter TextSpan/TextStyle binding'),
    );
    expect(
      entriesById['editor.rendering']?.todo,
      contains('Flutter ListView preview renderer'),
    );
    expect(
      entriesById['workspace.edit-application']?.status,
      IdeCapabilityStatus.wired,
    );
    expect(
      entriesById['workspace.edit-application']?.summary,
      contains('WorkspaceEditPreview'),
    );
    expect(
      entriesById['workspace.edit-application']?.summary,
      contains('serialized confirmation plans'),
    );
    expect(
      entriesById['workspace.edit-application']?.summary,
      contains('WorkspaceEditDiffPaginationStore'),
    );
    expect(
      entriesById['workspace.edit-application']?.summary,
      contains(
        'WorkspaceEditConfirmationPlan risk levels and blocking reasons',
      ),
    );
    expect(
      entriesById['workspace.edit-application']?.todo,
      isNot(contains('add preview')),
    );
    expect(
      entriesById['agent.coding-loop']?.dependencies,
      contains('workspace.edit-application'),
    );
    expect(
      entriesById['agent.provider']?.summary,
      contains('OpenAI Codex Spark preset'),
    );
    expect(
      entriesById['agent.provider']?.summary,
      contains('structured response tool definitions'),
    );
    expect(
      entriesById['agent.provider']?.summary,
      contains('checkpoint-aware prompt rules'),
    );
    expect(
      entriesById['agent.provider']?.summary,
      contains('Credential DataStore-backed bearer token references'),
    );
    expect(
      entriesById['agent.provider']?.summary,
      contains('saved profile loading by profile key/profile id'),
    );
    expect(
      entriesById['agent.provider']?.summary,
      contains('mounted provider profile key tracking'),
    );
    expect(
      entriesById['agent.provider']?.summary,
      contains('Agent Surface saved provider profile picker mount action'),
    );
    expect(
      entriesById['agent.provider']?.summary,
      contains('failover provider mount execution'),
    );
    expect(
      entriesById['debugger.dap']?.summary,
      contains('DebugLaunchTelemetryStore'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('stable workspace edit preview/apply-result context'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('deterministic workspace fix plan ids'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('agent applyQuickFix preview gate'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('stale preview rejection'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('workspace apply failure metadata propagation'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('workspace-edit risk prompt guidance'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('Source Control Agent context bridge'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('Source Control stage/unstage command routing'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('failed-test rerun context'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('StyioService readiness checkpoints'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('Styio language provider readiness context'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains(
        'semantic feature confidence matrix context and prompt guidance',
      ),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('AgentCodingExecutionReadiness issue facts'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('provider execution health blocking/degraded readiness facts'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('Agent Surface readiness issue visibility'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('provider dispatch gate enforcement'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('blocked dispatch runtime activity evidence'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('AgentCodingChangeReviewGate patch review facts'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('concrete review surface action ids'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('AgentCodingAutonomyPolicy review-before-apply contracts'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('Agent Surface autonomy policy visibility'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains(
        'AgentCodingValidationPlan and '
        'AgentCodingValidationCommandPlan registered command routing',
      ),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('Agent Surface validation command controls'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('AgentCodingValidationResult validation outcome summaries'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('AgentCodingValidationPipeline next-command progress facts'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('blocked validation plan activity visibility'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('failed patch repair prompt drafting'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('patch application runtime activity evidence'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('patch application validation snapshot binding'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('immediate validation snapshot persistence'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('provider adapter coding gate metadata summaries'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('checkpoint result prompt replay'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('validation-summary-aware persisted coding session history'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('ShellRuntime retry/replay recovery command dispatch'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('Agent Surface recovery command action controls'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('recovery validation summary visibility'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('recovery continue-validation action routing'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('recovery validation failure fix draft'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('recovery validation failure evidence prompt drafting'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('validation failure command evidence persistence'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('RuntimeOutputLiveBuffer agent activity publishing'),
    );
    expect(
      entriesById['agent.provider']?.summary,
      contains('AgentProviderSelectionPlan registry selection'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('AgentProviderSelectionContext prompt injection'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('provider selection status rendering'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('validation summary visibility'),
    );
    expect(
      entriesById['agent.coding-loop']?.summary,
      contains('validation failure evidence visibility'),
    );
    expect(snapshot.missingRequiredCapabilityIds, isEmpty);
    expect(json['missingRequiredCapabilityIds'], isEmpty);
    expect(
      json['requiredCapabilityIds'],
      containsAll(requiredVityoIdeCapabilityIds),
    );
    expect(snapshot.entriesForLayer(IdeCapabilityLayer.agent), isNotEmpty);
    expect(snapshot.entriesForLayer(IdeCapabilityLayer.service), isNotEmpty);
    expect(
      snapshot.entriesForLayer(IdeCapabilityLayer.environment),
      isNotEmpty,
    );
    expect(snapshot.followUps, isNotEmpty);
    expect(
      snapshot.followUps.every((entry) => entry.todo.startsWith('TODO:')),
      isTrue,
    );
    expect(json['entryCount'], snapshot.entries.length);
    expect(
      (json['statusCounts']! as Map<String, Object?>)['scaffolded'],
      greaterThan(0),
    );
    expect(
      (json['layerCounts']! as Map<String, Object?>)['agent'],
      greaterThanOrEqualTo(2),
    );
  });
}
