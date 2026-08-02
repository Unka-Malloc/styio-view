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
    expect(ids, containsAll(<String>['agent.client', 'agent.workbench']));
    expect(ids, isNot(contains('agent.provider')));
    expect(ids, isNot(contains('agent.coding-loop')));
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
      contains('typed command input routing'),
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
      contains('WorkspaceFileCommandRouter'),
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
    expect(entriesById['runtime.terminal']?.status, IdeCapabilityStatus.wired);
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
      contains('native forkpty/ConPTY execution plans'),
    );
    expect(
      entriesById['runtime.terminal']?.summary,
      contains('TerminalSessionRecoveryPlan'),
    );
    expect(
      entriesById['runtime.terminal']?.todo,
      contains('fixed-version macOS and Linux product matrices'),
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
      contains('generic bootstrap summaries'),
    );
    expect(
      entriesById['toolchain.manager']?.summary,
      contains(
        'Styio compiler identity is consumed through its machine contract',
      ),
    );
    expect(
      entriesById['toolchain.manager']?.summary,
      contains('Clang/C++ selection'),
    );
    expect(
      entriesById['toolchain.manager']?.summary,
      contains('install execution recovery action rendering'),
    );
    expect(
      entriesById['toolchain.manager']?.todo,
      contains('ToolchainBootstrapExecutionBridge'),
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
      isNot(contains('Agent context snapshots')),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('last action results'),
    );
    expect(
      entriesById['interaction.source-control']?.summary,
      contains('typed stage/unstage command routing'),
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
      entriesById['agent.workbench']?.dependencies,
      containsAll(<String>['agent.client', 'workspace.edit-application']),
    );
    expect(
      entriesById['agent.client']?.summary,
      contains('Supervised Agent process lifecycle'),
    );
    expect(
      entriesById['agent.client']?.summary,
      contains('versioned protocol session negotiation'),
    );
    expect(
      entriesById['agent.client']?.summary,
      contains('does not own model endpoints'),
    );
    expect(
      entriesById['agent.workbench']?.summary,
      contains('Immutable bounded collaboration projections'),
    );
    expect(
      entriesById['agent.workbench']?.summary,
      contains('revision-bound transactions'),
    );
    expect(
      entriesById['debugger.dap']?.summary,
      contains('DebugLaunchTelemetryStore'),
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
