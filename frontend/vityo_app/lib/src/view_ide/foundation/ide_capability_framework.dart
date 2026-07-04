enum IdeCapabilityLayer {
  foundation,
  environment,
  service,
  interaction,
  editor,
  workspace,
  runtime,
  debugger,
  toolchain,
  agent,
  extension,
  presentation,
}

extension IdeCapabilityLayerX on IdeCapabilityLayer {
  String get wireValue {
    return switch (this) {
      IdeCapabilityLayer.foundation => 'foundation',
      IdeCapabilityLayer.environment => 'environment',
      IdeCapabilityLayer.service => 'service',
      IdeCapabilityLayer.interaction => 'interaction',
      IdeCapabilityLayer.editor => 'editor',
      IdeCapabilityLayer.workspace => 'workspace',
      IdeCapabilityLayer.runtime => 'runtime',
      IdeCapabilityLayer.debugger => 'debugger',
      IdeCapabilityLayer.toolchain => 'toolchain',
      IdeCapabilityLayer.agent => 'agent',
      IdeCapabilityLayer.extension => 'extension',
      IdeCapabilityLayer.presentation => 'presentation',
    };
  }
}

enum IdeCapabilityStatus { ready, wired, scaffolded, todo }

extension IdeCapabilityStatusX on IdeCapabilityStatus {
  String get wireValue {
    return switch (this) {
      IdeCapabilityStatus.ready => 'ready',
      IdeCapabilityStatus.wired => 'wired',
      IdeCapabilityStatus.scaffolded => 'scaffolded',
      IdeCapabilityStatus.todo => 'todo',
    };
  }
}

const List<String> requiredVityoIdeCapabilityIds = <String>[
  'foundation.datastore',
  'foundation.registry',
  'environment.platform',
  'environment.file-system',
  'environment.configuration',
  'environment.credential-store',
  'service.styio-language',
  'service.semantic-snapshot',
  'service.language-result-cache',
  'service.remote-service',
  'interaction.commands',
  'interaction.diagnostics',
  'interaction.language-service-status',
  'interaction.search',
  'interaction.source-control',
  'interaction.testing',
  'interaction.command-palette',
  'editor.document-model',
  'editor.rendering',
  'workspace.project-model',
  'workspace.diagnostics',
  'workspace.file-explorer',
  'workspace.edit-application',
  'runtime.execution',
  'runtime.terminal',
  'debugger.dap',
  'toolchain.manager',
  'agent.provider',
  'agent.coding-loop',
  'extension.manifest',
  'extension.marketplace',
  'presentation.shell',
  'presentation.problems-panel',
  'presentation.output-panel',
];

class IdeCapabilityDescriptor {
  const IdeCapabilityDescriptor({
    required this.id,
    required this.layer,
    required this.title,
    required this.status,
    required this.ownerPath,
    this.summary = '',
    this.todo = '',
    this.runtimeMaturityBlocking,
    this.references = const <String>[],
    this.dependencies = const <String>[],
  });

  final String id;
  final IdeCapabilityLayer layer;
  final String title;
  final IdeCapabilityStatus status;
  final String ownerPath;
  final String summary;
  final String todo;
  final bool? runtimeMaturityBlocking;
  final List<String> references;
  final List<String> dependencies;

  bool get needsFollowUp =>
      status == IdeCapabilityStatus.todo || todo.isNotEmpty;

  bool get blocksRuntimeMaturity {
    return runtimeMaturityBlocking ??
        (status == IdeCapabilityStatus.todo ||
            status == IdeCapabilityStatus.scaffolded);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'layer': layer.wireValue,
      'title': title,
      'status': status.wireValue,
      'ownerPath': ownerPath,
      if (summary.isNotEmpty) 'summary': summary,
      if (todo.isNotEmpty) 'todo': todo,
      'runtimeMaturityBlocking': blocksRuntimeMaturity,
      if (references.isNotEmpty) 'references': references,
      if (dependencies.isNotEmpty) 'dependencies': dependencies,
      'needsFollowUp': needsFollowUp,
    };
  }
}

class IdeCapabilityFrameworkSnapshot {
  const IdeCapabilityFrameworkSnapshot({
    required this.version,
    required this.entries,
    this.references = const <String>[
      'VS Code workbench and extension host',
      'IntelliJ Platform services and project model',
      'Eclipse Theia frontend/backend split',
      'Language Server Protocol',
      'Debug Adapter Protocol',
    ],
  });

  final String version;
  final List<IdeCapabilityDescriptor> entries;
  final List<String> references;

  Iterable<IdeCapabilityDescriptor> entriesForLayer(IdeCapabilityLayer layer) {
    return entries.where((entry) => entry.layer == layer);
  }

  Iterable<IdeCapabilityDescriptor> get followUps {
    return entries.where((entry) => entry.needsFollowUp);
  }

  Iterable<String> get missingRequiredCapabilityIds {
    final ids = entries.map((entry) => entry.id).toSet();
    return requiredVityoIdeCapabilityIds.where((id) => !ids.contains(id));
  }

  Map<String, int> get statusCounts {
    return <String, int>{
      for (final status in IdeCapabilityStatus.values)
        status.wireValue: entries
            .where((entry) => entry.status == status)
            .length,
    };
  }

  Map<String, int> get layerCounts {
    return <String, int>{
      for (final layer in IdeCapabilityLayer.values)
        layer.wireValue: entries.where((entry) => entry.layer == layer).length,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': version,
      'references': references,
      'entryCount': entries.length,
      'requiredCapabilityIds': requiredVityoIdeCapabilityIds,
      'missingRequiredCapabilityIds': missingRequiredCapabilityIds.toList(
        growable: false,
      ),
      'statusCounts': statusCounts,
      'layerCounts': layerCounts,
      'followUpCount': followUps.length,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

class VityoIdeCapabilityFramework {
  const VityoIdeCapabilityFramework();

  IdeCapabilityFrameworkSnapshot snapshot() {
    return const IdeCapabilityFrameworkSnapshot(
      version: 'vityo-ide-capability-framework-v1',
      entries: <IdeCapabilityDescriptor>[
        IdeCapabilityDescriptor(
          id: 'foundation.datastore',
          layer: IdeCapabilityLayer.foundation,
          title: 'DataStore ownership and persistence',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/foundation/datastore',
          summary:
              'Shared persistence base for configuration, registry, and IDE state.',
          references: <String>[
            'IntelliJ PersistentStateComponent',
            'VS Code storage service',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'foundation.registry',
          layer: IdeCapabilityLayer.foundation,
          title: 'Cross-layer registry contract',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/foundation/registry',
          summary:
              'Manifest-oriented registration contract for providers, commands, and capabilities.',
          references: <String>[
            'VS Code contribution points',
            'Theia contribution providers',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'environment.platform',
          layer: IdeCapabilityLayer.environment,
          title: 'Platform context and system compatibility',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/environment/system_compatibility',
          summary:
              'Platform Detector, Platform Context, Platform Adapter, Platform Manager bundle, fact-level health snapshots, PlatformManagerHealthProbe contracts, PlatformManagerLiveOperationProbeRegistry callback contracts, probe-kind counts, manager live-operation probe metadata, PlatformManagerRecoveryActionRouter settings routes with settings section ids, and UI-facing recovery actions are available for file system, shell, process, resource, network, clipboard, notification, local service, and PTY managers.',
          todo:
              'TODO: register platform-specific live-operation smoke callbacks and bind recovery actions to Settings UI panels.',
          runtimeMaturityBlocking: false,
          references: <String>[
            'VS Code platform services',
            'IntelliJ virtual file system',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'environment.file-system',
          layer: IdeCapabilityLayer.environment,
          title: 'File System Manager',
          status: IdeCapabilityStatus.wired,
          ownerPath:
              'lib/src/view_ide/environment/system_compatibility/file_system',
          summary:
              'System specific file access base for editor binding and DataStore.',
        ),
        IdeCapabilityDescriptor(
          id: 'environment.configuration',
          layer: IdeCapabilityLayer.environment,
          title: 'Configuration and settings storage',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/environment/configuration',
          summary:
              'Configuration DataStore ownership for IDE settings, provider profiles, and toolchain preferences.',
          references: <String>[
            'VS Code configuration service',
            'IntelliJ application and project settings',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'environment.credential-store',
          layer: IdeCapabilityLayer.environment,
          title: 'Credential DataStore',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/environment/configuration',
          summary:
              'Credential references, redacted metadata, injection results, batch injection, access audit trails, persisted FoundationDataStore credentials, platform secure storage adapter contracts, PlatformSecureCredentialDataStore, PlatformSecureCredentialStorageAdapterRegistry backend selection, policy-enforcing credential stores, credential storage health facts, adapter backend descriptors, audit retention policies, and storage policy decisions are wired.',
          todo:
              'TODO: register OS SecretStorage/Keychain/Credential Manager/libsecret production adapters in PlatformSecureCredentialStorageAdapterRegistry.',
          runtimeMaturityBlocking: false,
          references: <String>[
            'VS Code SecretStorage',
            'IntelliJ PasswordSafe',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'service.styio-language',
          layer: IdeCapabilityLayer.service,
          title: 'StyioService connector',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/language/service',
          summary:
              'Styio-first parser, diagnostics, semantic facts, grammar-version facts, runtime status snapshots, capability health summaries, StyioServiceRuntimeOutputBinding language-service health output events, extension language route consumption, and structured missing capability facts for provider binding.',
          references: <String>['Language Server Protocol'],
        ),
        IdeCapabilityDescriptor(
          id: 'service.semantic-snapshot',
          layer: IdeCapabilityLayer.service,
          title: 'Semantic snapshot and resolved symbols',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/language/service',
          summary:
              'SemanticSnapshotProvider converts StyioService analysis into resolved elements/references, exposes StyioService-backed code action raw edit facts, code action apply/result telemetry, document rename safety facts, workspace rename safety facts, diagnostics snapshot telemetry, semantic-token snapshot telemetry, SemanticSnapshotEventBridge runtime-output events, Problems/Refactor panel event sink dispatching, SemanticSnapshotPanelEventStateController, SemanticSnapshotPanelViewModel Problems/Refactor projections, concrete Problems and Refactor panel projection rendering, SemanticSnapshotPanelEventStore persisted telemetry with retention policy, ShellRuntimeModel lifecycle hydration, Agent context projection, StyioServiceSubscriptionController background document streams, provider daemon event stream binding, daemon lifecycle snapshots, StyioServiceDaemonRestartPolicy, StyioServiceDaemonRestartPlan, StyioServiceDaemonRestartDispatchResult, StyioServiceDaemonProcessSupervisor restart handler contract, StyioServiceDaemonProcessAdapter launch request/result contracts, StyioServiceDaemonProcessLauncherRegistry platform/service launcher selection, StyioServiceDaemonLocalProcessLauncher executable/starter bridge, StyioServiceDaemonSupervisorControls process-supervisor control path, ShellRuntimeModel subscription start/refresh/cancel/restart dispatch controls, language-service refresh callback fallback, StyioService response telemetry routing into runtime output and semantic panel events, StyioLanguageProviderReadinessReport active capability coverage, publishes a feature coverage/confidence matrix with service-backed/local-fallback/unavailable counts for hover/definition/references/completion/rename/code action consumers, and only falls back to local snapshots when service semantic facts are missing.',
          todo:
              'TODO: resolve StyioService executable from ToolchainManager and register platform-specific StyioService process/service implementations, including dart:io Process.start-backed launcher registration where desktop platforms are available.',
          runtimeMaturityBlocking: false,
          references: <String>[
            'LSP textDocument/semanticTokens',
            'IntelliJ PSI and symbol resolve',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'service.language-result-cache',
          layer: IdeCapabilityLayer.service,
          title: 'Language result cache',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/language/service',
          summary:
              'Caches StyioService results with protocol, parser engine, grammar version metadata, hit/miss telemetry counters, and snapshot metadata.',
        ),
        IdeCapabilityDescriptor(
          id: 'service.remote-service',
          layer: IdeCapabilityLayer.service,
          title: 'Remote service connector',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/agent',
          summary:
              'Agent provider route selection, user-managed OpenAI API credential references for Codex/Codex Spark profiles, AgentSurface preset credential binding and credential-reference visibility, preferred credential writes through AgentProviderConfigurator, credential readiness, endpoint probing, fallback selection, retry policy execution, remote service health reports, Foundation DataStore-backed health history, OpenAI-compatible/Responses provider routing, hosted backend connector parity action plans, HostedBackendRetryEndpointPlan retry/reopen/export/settings route contracts, HostedBackendRetryActionExecutor, HostedControlPlaneRetryTransport, and HostedBackendRetryRuntimeOutputBinding telemetry snapshots are wired.',
          todo:
              'TODO: bind hosted settings recovery handlers to concrete Settings UI.',
          runtimeMaturityBlocking: false,
          references: <String>[
            'VS Code remote authority and extension host services',
            'Theia backend service connections',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'interaction.commands',
          layer: IdeCapabilityLayer.interaction,
          title: 'IDE command catalog',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/commands',
          summary:
              'Registered commands for persistence, language refresh, navigation, refactor, tools, settings, debug, Agent coding recovery, and extension command contribution route consumption.',
          references: <String>[
            'VS Code command registry',
            'IntelliJ action system',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'interaction.diagnostics',
          layer: IdeCapabilityLayer.interaction,
          title: 'Diagnostics interaction surface',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/interaction',
          summary:
              'Diagnostics interaction can consume workspace diagnostics provider snapshots, serializable diagnostics filters, persisted panel state, panel-state restoration in ProblemsSurface, source groups, reusable diagnostics view models, quick-fix confirmation plans, WorkspaceQuickFixTelemetryStore review outcomes, WorkspaceDiagnosticsRuntimeOutputBinding producer telemetry, WorkspaceDiagnosticsProducerExecutionPlan native toolchain handoff triggers and WorkspaceDiagnosticsProducerLifecycleController progress/cancel snapshots, WorkspaceDiagnosticsProducerCancellationRoute, WorkspaceDiagnosticsProducerProcessHandleRegistry, RuntimeProcessHandleIdentity-aware WorkspaceDiagnosticsProducerProcessHandleBinder dispatch-result binding, ShellRuntime diagnostics producer cancellation bridge, Problems producer lifecycle progress/cancel controls, RuntimeOutputLiveBuffer quick-fix action telemetry, WorkspaceQuickFixReviewPlan bridges into concrete Problems diff/apply controls, focused problem actions, and keyboard-navigable Problems panel bindings.',
          todo:
              'TODO: ensure every production diagnostics provider dispatch exposes processHandleId/pid metadata.',
          runtimeMaturityBlocking: false,
          dependencies: <String>['workspace.diagnostics'],
        ),
        IdeCapabilityDescriptor(
          id: 'interaction.language-service-status',
          layer: IdeCapabilityLayer.interaction,
          title: 'StyioService status interaction',
          status: IdeCapabilityStatus.wired,
          ownerPath:
              'lib/src/view_ide/interaction/language_service_status_surface.dart',
          summary:
              'LanguageServiceStatusSurface and LanguageServiceStatusController map StyioService runtime events, capability health summaries, Styio language provider readiness derived from StyioService capability snapshots, cache telemetry, syntax-validation readiness, semantic-fact readiness, and unavailable capability summaries into ValueListenable status snapshots for editor, shell, and Agent consumers.',
          dependencies: <String>['service.styio-language'],
          references: <String>[
            'VS Code language status item',
            'IntelliJ code insight daemon status',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'interaction.search',
          layer: IdeCapabilityLayer.interaction,
          title: 'Search, symbols, and quick open',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/workspace',
          summary:
              'Workspace text search service, in-memory search index snapshot, WorkspaceSearchIndexController stale-revision refresh execution, WorkspaceSearchIndexFileSystemWatcherBinding File System Manager watch refresh execution, WorkspaceSearchWatcherPolicy debounce/queue/ignore contracts, WorkspaceSearchWatcherRefreshPlan batched refresh facts, WorkspaceSearchWatcherEventBatchController project-scale event batches, WorkspaceSearchWatcherStreamBatcher timer-backed watcher stream flushing, WorkspaceSearchWatcherRecoveryPlan recovery action facts, WorkspaceSearchWatcherRecoveryStore DataStore-backed recovery persistence, persistent index invalidation key contract, symbol search service with semantic snapshot source/confidence propagation and Search Surface rendering, file quick open service, replace preview contract with before/after diff summary, virtualized replace-preview document windows, persisted multi-file diff expansion state, replace apply confirmation, search history persistence, persisted result filter state, search history/index/filter/expansion summaries in the user surface, agent search command, Agent workspace replace preview/apply command routing, and match-level navigation callback are wired.',
          todo:
              'TODO: add production watcher backpressure telemetry and platform-specific overflow recovery.',
          runtimeMaturityBlocking: false,
          references: <String>[
            'VS Code search service',
            'IntelliJ Search Everywhere',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'interaction.source-control',
          layer: IdeCapabilityLayer.interaction,
          title: 'Source control interaction',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/workspace',
          summary:
              'Source Control surface is wired to dirty editor documents, Git porcelain status parsing, diff preview, diff review summaries, parsed diff hunks, SourceControlHunkSelectionState multi-hunk selection, SourceControlHunkDiscardConfirmationPlan destructive discard confirmation, hunk discard modal UI, hunk action selection plans, selected hunk patch generation, Git partial patch execution provider, shell hunk discard confirmation routing, shell hunk action execution routing, hunk action result rows, Agent context snapshots with hunk selection and partial patch results, virtualized diff window binding, persisted SourceControlDiffSessionStore window and hunk-selection state, SourceControlStatusController diff-session restore/persist hooks, SourceControlMergeWorkflowPlan conflict-resolution facts, SourceControlConflictResolutionPlan merge workflow actions, SourceControlConflictResolutionProviderRegistry provider operation bridge, diff confirmation plans and controls, Agent context snapshots with pending action plans and last action results, staging action contracts, Agent stage/unstage command routing, branch-switch plan command routing, commit-draft plan command routing, persisted commit drafts, commit dialog state validation, commit draft summaries, branch picker summaries, branch switch plans, Git branch switch provider, history summaries, expandable history rows, action planning and confirmation, Git stage/unstage/discard/commit action provider, Git branch/history provider contracts, non-Git provider adapter descriptors and surface summaries, file open, and save-all handoff.',
          todo:
              'TODO: bind SourceControlMergeWorkflowPlan to concrete merge editor UI.',
          runtimeMaturityBlocking: false,
          references: <String>[
            'VS Code SCM provider API',
            'IntelliJ VCS subsystem',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'interaction.testing',
          layer: IdeCapabilityLayer.interaction,
          title: 'Test explorer and results',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/testing',
          summary:
              'Testing surface is wired to runTests, native tool testResult records, TestRunProvider registry, TestDiscoveryProvider registry, TestingProviderCatalog controller fallback, TestingProviderCatalog health snapshots, TestingProviderRetryPlan retry action facts, test run configurations, persisted run configuration sets, run/debug selected configuration controls, test tree model, persisted test run history, persisted failed-test retry history, runtime task lifecycle snapshots, persisted runtime task history, output stream subscription plans, RuntimeOutputLiveBuffer test-result publishing, failed-test rerun planning, failed-test interaction, per-failed-test debug cancellation routing, FailedTestDebugCancellationRoute process-handle metadata, FailedTestDebugCancellationHandleRegistry debug-adapter/test-runner handle resolution, RuntimeProcessHandleIdentity-aware FailedTestDebugProcessHandleBinder runtime snapshot handle binding, rerun-failed handoff, failed-test DebugLaunchRoutePlan bridge, debug launch route plans, failure navigation actions, DebugRuntimeExecutionAdapter result visibility, cancellation telemetry, debug retry handoff, and CTest result parsing.',
          todo:
              'TODO: ensure production debug adapter and test runner runtime snapshots expose processHandleId/pid metadata.',
          runtimeMaturityBlocking: false,
          dependencies: <String>['foundation.registry', 'runtime.execution'],
          references: <String>['VS Code Testing API', 'IntelliJ test runner'],
        ),
        IdeCapabilityDescriptor(
          id: 'interaction.command-palette',
          layer: IdeCapabilityLayer.interaction,
          title: 'Command palette and keybinding resolver',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/commands',
          summary:
              'Command Palette surface is wired to StyioCommandRegistry, category contribution manifests, shell command execution, reusable query scoring, overlay selection state, live display preference updates, top-level SettingsSurface preference saves, shell-level DataStore preference hydration/persistence, app bootstrap preference hydration, category filter chips, display preferences, Settings UI preference controls, Up/Down/Enter keyboard navigation, typed input draft contracts, keyboard shortcuts, physical key capture, platform-specific reserved shortcut host policies, accessibility hints, keybinding remap persistence, surface-level keybinding editor, rich conflict review contracts and preview actions, persisted recent command ranking, recent command record hooks, and blocked command availability reasons.',
          references: <String>[
            'VS Code command palette',
            'IntelliJ action search',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'editor.document-model',
          layer: IdeCapabilityLayer.editor,
          title: 'Document model and text buffer',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/editor',
          summary:
              'Document state, selection, transactions, editor controller, and file binding.',
          references: <String>['Monaco text model', 'IntelliJ document model'],
        ),
        IdeCapabilityDescriptor(
          id: 'editor.rendering',
          layer: IdeCapabilityLayer.editor,
          title: 'Editor rendering and presentation bridge',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_render/editor',
          summary:
              'Editor surface renders document, tabs, selection, token/semantic/diagnostic layers, folding, hover, completion, code-action facts, language-service health status pills, EditorCodeActionWidgetState, EditorSemanticThemeBinding render styles, concrete Flutter TextSpan/TextStyle binding, EditorRenderViewportBinding concrete ScrollController facts, EditorRenderPipelinePlan renderer/fallback facts, viewport-bound source scroll telemetry, and serializable EditorRenderSnapshot contracts for UI and Agent consumers.',
          todo:
              'TODO: bind high-volume editor layer backend beyond the current Flutter ListView preview renderer.',
          runtimeMaturityBlocking: false,
          references: <String>['Monaco editor', 'VS Code workbench editor'],
        ),
        IdeCapabilityDescriptor(
          id: 'workspace.project-model',
          layer: IdeCapabilityLayer.workspace,
          title: 'Workspace and project model',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/workspace',
          summary:
              'Workspace documents, project graph, file lists, dirty state, and samples for agent context.',
        ),
        IdeCapabilityDescriptor(
          id: 'workspace.diagnostics',
          layer: IdeCapabilityLayer.workspace,
          title: 'Workspace diagnostics provider',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/workspace/workspace_diagnostics.dart',
          summary:
              'WorkspaceDiagnosticsSnapshot and WorkspaceDiagnosticsProviderRegistry provide shared workspace problem facts for Problems, Agent, and code actions, including document grouping, source grouping, persisted filters, workspace diagnostic stream snapshots, WorkspaceDiagnosticsRuntimeOutputBinding output-panel events, WorkspaceDiagnosticsProducerExecutionPlan toolchain execution triggers, WorkspaceDiagnosticsProducerLifecycleController progress/cancel snapshots and registered plan lookup, diagnostics producer cancellation adapter contracts, WorkspaceDiagnosticsProducerProcessHandleRegistry provider handle resolution, WorkspaceDiagnosticsProducerProcessHandleBinder runtime dispatch-result handle binding, ToolchainRuntime process identity metadata, WorkspaceDiagnosticsController producer cancellation dispatch, runtime task cancellation metadata, attached quick-fix facts, source-kind classification, workspace quick-fix confirmation plans, WorkspaceQuickFixTelemetryStore persisted review outcomes, preview/apply action routing, and native tool result diagnostic snapshots.',
          todo:
              'TODO: ensure every native process backend can populate processHandleId/pid metadata for diagnostics producers.',
          dependencies: <String>[
            'foundation.registry',
            'service.styio-language',
          ],
          references: <String>[
            'Language Server Protocol publishDiagnostics',
            'VS Code diagnostics collection',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'workspace.file-explorer',
          layer: IdeCapabilityLayer.workspace,
          title: 'File explorer and workspace operations',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/workspace',
          summary:
              'WorkspaceFileOperationService provides create, rename, delete, and reveal contracts backed by WorkspaceDocumentStore and WorkspaceController synchronization. WorkspaceFileExplorerController exposes a file tree snapshot, unified explorer actions, command palette file operation contributions, WorkspaceFileExplorerActionRisk classifications, confirmation plans, WorkspaceFileExplorerBatchActionPlan multi-action confirmation contracts, restored expanded/selected/revealed state, sort preferences, Foundation DataStore-backed explorer state persistence, normalized File System Manager discovery results, watch event snapshots, WorkspaceFileExplorerIgnoreRules, WorkspaceFileExplorerWatchDebouncePolicy, WorkspaceFileExplorerWatchStreamBatcher timer-backed debounce flushing, and WorkspaceFileExplorerFileSystemWatcherBinding concrete File System Manager watch execution. WorkspaceFileCommandRouter and WorkspaceFileCommandPaletteAdapter route typed command palette input into file operation requests, confirmation plans, or immediate reveal actions. ShellRuntimeModel exposes pending workspace file command confirmation controls for destructive command routes, the shell sidebar renders confirmation apply/cancel controls, and Agent workspace file command routing covers create, rename, reveal, and confirmation-staged delete.',
          todo:
              'TODO: bind batch plans to concrete dialogs, richer file tree UI, and watcher overflow/backpressure telemetry.',
          runtimeMaturityBlocking: false,
          references: <String>[
            'VS Code Explorer view',
            'IntelliJ Project tool window',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'workspace.edit-application',
          layer: IdeCapabilityLayer.workspace,
          title: 'Workspace edit application',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/workspace/workspace_edit.dart',
          summary:
              'WorkspaceEditPlan, WorkspaceEditPreview with serialized confirmation plans, WorkspaceEditDiffWindow, WorkspaceEditDiffPaginationStore, WorkspaceEditConfirmationPlan risk levels and blocking reasons, WorkspaceEditReviewControls, WorkspaceEditReviewResultTelemetry, WorkspaceEditApplyResultViewModel, file create/delete operations, Problems diff-window rendering, Problems apply-result rendering, ShellRuntime quick-fix result projection, serializable application results, and WorkspaceEditApplier provide a shared preview, confirmation, review-control, result telemetry, and edit application path for agent patches, code actions, rename, and formatting.',
          dependencies: <String>[
            'foundation.registry',
            'workspace.project-model',
          ],
          references: <String>[
            'Language Server Protocol WorkspaceEdit',
            'VS Code workspace edits',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'runtime.execution',
          layer: IdeCapabilityLayer.runtime,
          title: 'Execution manager and shell runtime',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/environment/execution',
          summary:
              'ExecutionSession, runtime events, native tool results, runtime execution plans, dependency readiness checks, runtime execution handoff contracts, manager binding routes, default RuntimeExecutionManagerRegistry registrations, dispatch-to-live-output-buffer results, RuntimeProcessHandleIdentity metadata exposure, ShellManagerRuntimeExecutionAdapter local shell execution with process identity metadata, ToolchainManagerRuntimeExecutionAdapter, ToolchainInstallRuntimeExecutionAdapter managed tool execution, HostedRuntimeExecutionAdapter hosted workflow execution, output-channel attachment contracts, runtime task lifecycle snapshots, persisted runtime task history, and extension task contribution definitions, ExtensionRuntimeTaskExecutionPlan, ExtensionRuntimeTaskExecutionBridge dispatch, ExtensionRuntimeTaskTelemetrySnapshot, ExtensionRuntimeTaskDataStoreTelemetrySink, ExtensionRuntimeTaskRetryPolicy, ExtensionRuntimeTaskRetryPlan, ExtensionRuntimeTaskCancellationRegistry, RuntimeProcessHandleIdentity-aware ExtensionRuntimeTaskProcessHandleBinder dispatch-result handle binding, ExtensionRuntimeTaskTerminationRequest/Result, and ShellManager/ProcessManager cancellation adapter factories expose stable serializable execution contracts for UI and Agent consumers.',
          todo:
              'TODO: connect every production ShellManager/ProcessManager backend to populate processHandleId/pid metadata for cancellation binding.',
          runtimeMaturityBlocking: false,
          references: <String>['VS Code tasks', 'Theia task service'],
        ),
        IdeCapabilityDescriptor(
          id: 'runtime.terminal',
          layer: IdeCapabilityLayer.runtime,
          title: 'Terminal, PTY, and task runner',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/toolchain/terminal_runtime.dart',
          summary:
              'Terminal surface is wired to shell/runtime output, RuntimeOutputLiveBuffer panel snapshots, TerminalRuntimeStartPlan readiness, PtyExecutionPlan backend details, PtyNativeOperationBackendRegistry resize/signal backend delegation, TerminalRuntimeOutputBinding start-plan/session output snapshots, TerminalSessionRecoveryPlan replay/rebind/stale-close recovery facts, recovery action controls, TerminalInteractionController live RuntimeOutputEvent streams, RuntimeOutputProducerEmission adapter binding, ShellManager runtime output adapter bindings, line-chunked ShellCommandResult stdout/stderr events, run handoff, PTY session snapshots, script-PTY stdout/stderr merged output streams, explicit start/resize/signal/close UI controls, TerminalInteractionController input/resize/signal/close contracts, serializable interaction events, terminal-to-runtime-output event conversion, ShellCommandResult output binding, shared runtime task lifecycle snapshots on start/close, and persisted terminal task history.',
          todo:
              'TODO: register native POSIX PTY/ConPTY resize and native OS process signal delivery backends to replace script-PTY placeholders where available.',
          runtimeMaturityBlocking: false,
          references: <String>[
            'VS Code integrated terminal',
            'IntelliJ terminal and run tool windows',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'debugger.dap',
          layer: IdeCapabilityLayer.debugger,
          title: 'Debug Adapter Protocol framework',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/debugger',
          summary:
              'DAP launch contracts, breakpoint serialization, persisted workspace breakpoint sets, launch profiles, workspace launch configuration sets, Foundation DataStore persistence, runtime task projection, runtime execution handoff, debug route plans, failure navigation actions, DapDebugAdapterExecutionPlan, DebugSessionTerminationPlan graceful/forced termination facts, DebugSessionTerminationExecutor DAP disconnect/terminate and process-kill handler bridge, DebugRuntimeExecutionAdapter, DebugLaunchTelemetryStore, DebugLaunchRuntimeOutputBinding output events, DebugConsoleSurface launch plan, telemetry summaries, runtime execution result controls, retry handoff, launcher execution-plan handoff, DAP snapshot task-history binding, live ShellRuntime DAP history appends, and extension debugger route consumption are wired.',
          todo:
              'TODO: wire breakpoint UI editing, non-C++ debug adapters, launch UI editing, and production process-kill handlers for debug adapters.',
          runtimeMaturityBlocking: false,
          references: <String>['Debug Adapter Protocol'],
        ),
        IdeCapabilityDescriptor(
          id: 'toolchain.manager',
          layer: IdeCapabilityLayer.toolchain,
          title: 'Toolchain manager',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/toolchain',
          summary:
              'Toolchain catalog, resolver, install policy, health checks, configuration persistence, managed downloads, Styio-first toolchain lifecycle reports, bootstrap summaries for settings/project/agent consumers, Agent toolchain bootstrap context facts, suggested command ids, and prompt guidance, bootstrapStyioToolchain and executeToolchainInstallPlan registered command routing, project bootstrap managed install planning, install execution recovery action rendering, installer recovery route handling, ToolchainBootstrapExecutionPlan settings/installer/project action steps, ToolchainBootstrapActionRouter dispatch contracts, ToolchainBootstrapExecutionBridge sequential step execution, ShellRuntimeModel bootstrap action dispatch, SettingsSurface bootstrap dispatch result rendering, settings bootstrap action controls, and extension toolchain route consumption are wired.',
          todo:
              'TODO: bind concrete installer UX and project bootstrap runners to ToolchainBootstrapExecutionBridge handlers.',
          runtimeMaturityBlocking: false,
          references: <String>[
            'VS Code extensions toolchain model',
            'IntelliJ SDK model',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'agent.provider',
          layer: IdeCapabilityLayer.agent,
          title: 'Agent provider and credential framework',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/agent',
          summary:
              'OpenAI-compatible and OpenAI Responses providers, explicit OpenAI Codex Spark preset, serializable client credential policy, Credential DataStore-backed bearer token references, redacted AgentProviderCredentialLookupPlan, credential-backed routes, AgentProviderSelectionPlan registry selection, configurator selection result propagation, saved profile loading by profile key/profile id, mounted provider profile key tracking, Agent Surface saved provider profile picker mount action, failover provider mount execution, explicit retrying adapter mount policy, configurator retry telemetry propagation, retry execution telemetry sink, retry RuntimeOutput event binding, fallback readiness, provider execution context, checkpoint-aware prompt rules, structured response tool definitions, streaming provider event contracts, OpenAI-compatible and Responses streaming transport contracts, streaming response collection, streaming runtime output binding, and extension agent provider contribution manifests.',
        ),
        IdeCapabilityDescriptor(
          id: 'agent.coding-loop',
          layer: IdeCapabilityLayer.agent,
          title: 'Agent coding loop',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/agent',
          summary:
              'Structured plan, diagnostics, code patch, IDE command, command result, streaming content deltas, AgentCodingSessionController streaming adapter dispatch, WorkspaceEdit bridge, stable workspace edit preview/apply-result context, deterministic workspace fix plan ids, agent applyQuickFix preview gate, stale preview rejection, workspace apply failure metadata propagation, workspace-edit risk prompt guidance, Source Control Agent context bridge, Source Control stage/unstage command routing, failed-test rerun context, StyioService readiness checkpoints, StyioService capability-health-aware skill activation and prompt guidance, Styio language provider readiness context and skill activation reasons, SemanticSnapshotPanelViewModel Problems/Refactor context, semantic feature confidence matrix context and prompt guidance, AgentCodingExecutionReadiness issue facts, provider execution health blocking/degraded readiness facts, Agent Surface readiness issue visibility, provider dispatch gate enforcement, blocked dispatch runtime activity evidence, AgentCodingChangeReviewGate patch review facts with concrete review surface action ids, AgentCodingAutonomyPolicy review-before-apply contracts, Agent Surface autonomy policy visibility, AgentCodingValidationPlan and AgentCodingValidationCommandPlan registered command routing, Agent Surface validation command controls, AgentCodingValidationResult validation outcome summaries, AgentCodingValidationPipeline next-command progress facts, blocked validation plan activity visibility, failed patch repair prompt drafting, patch application runtime activity evidence, patch application validation snapshot binding, immediate validation snapshot persistence, provider adapter coding gate metadata summaries, checkpoint result prompt replay, patch application loop, validation-summary-aware persisted coding session history, serializable AgentCodingSessionCheckpoint recovery facts, AgentCodingSessionRecoveryPlan retry/failover/replay facts, AgentCodingSessionRecoveryCommandPlan command routing facts, AgentCodingSessionRecoveryRequestDraft prompt restoration, explicit AgentCodingSessionRecoveryDispatchResult confirmation gates, ShellRuntime retry/replay recovery command dispatch, Agent Surface recovery command action controls, recovery validation summary visibility, validation failure evidence visibility, recovery continue-validation action routing, recovery validation failure fix draft, recovery validation failure evidence prompt drafting, validation failure command evidence persistence, Agent Surface recovery dispatch status feedback, history restore/persistence failure output events, RuntimeOutputLiveBuffer agent activity publishing, AgentProviderSelectionContext prompt injection, provider credential/execution readiness selection, provider readiness context serialization, provider selection status rendering, and embeddable activity history surface with controller snapshot binding, failed-record reason, and diagnostic summary count visibility, and validation summary visibility.',
          dependencies: <String>['workspace.edit-application'],
          references: <String>[
            'VS Code chat participants',
            'JetBrains AI Assistant workflows',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'extension.manifest',
          layer: IdeCapabilityLayer.extension,
          title: 'Extension and module manifest',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/module_host',
          summary:
              'Module manifests can be projected into stable extension manifests with activation events, ExtensionActivationPlan enabled/trusted gating, contribution points, capability flags, registry lookup, Foundation DataStore persistence, extension activation sessions, persisted activation history, lifecycle snapshots, lifecycle hook catalogs/runners, host isolation plans, trust-policy gating, host supervisor snapshots, ExtensionHostSupervisorExecutionBridge runtime dispatch, ExtensionHostSandboxLauncherRegistry launcher dispatch, activation telemetry events, theme/view contribution catalogs, and contribution route manifests for target registries.',
          todo:
              'TODO: implement concrete OS/web sandbox launcher registrations and render activation telemetry UI.',
          runtimeMaturityBlocking: false,
          references: <String>[
            'VS Code extension manifest',
            'Theia extension model',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'extension.marketplace',
          layer: IdeCapabilityLayer.extension,
          title: 'Extension lifecycle and marketplace',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/module_host',
          summary:
              'Extensions surface is wired to visible and mounted module manifests, lifecycle state, enable/disable/trust actions, update flags, ExtensionMarketplaceUpdatePlan version comparison, refreshModules handoff, rendered marketplace index search results, install-plan controls, install execution steps, package download/verification executor contracts, ExtensionMarketplaceIoBridge install/update IO operation routing, manifest registration after verified install, signature verification policy gates, lifecycle policy decisions, host-isolation planning, and Foundation DataStore-backed marketplace cache.',
          todo:
              'TODO: register concrete marketplace network/cache IO handlers and persist lifecycle policy choices through the product settings flow.',
          runtimeMaturityBlocking: false,
          references: <String>[
            'VS Code extension gallery',
            'IntelliJ plugin repository',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'presentation.shell',
          layer: IdeCapabilityLayer.presentation,
          title: 'IDE shell and panels',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_render/shell',
          summary:
              'Shell model, bottom tab routing, serializable shell layout plans, ShellPanelContributionRegistry core IDE panel coverage, ShellLayoutPreferenceController live scaffold binding, ShellLayoutRenderBinding, and Foundation DataStore-backed shell layout preferences define top bar, activity rail, editor, bottom panel, active panel keys, panel visibility, pinned panels, collapsed bottom-panel state, and status bar contracts for desktop and compact viewports.',
          todo:
              'TODO: mature panels for diagnostics, search, settings, extensions, debug, and agent activity.',
          runtimeMaturityBlocking: false,
          references: <String>['VS Code workbench', 'IntelliJ tool windows'],
        ),
        IdeCapabilityDescriptor(
          id: 'presentation.problems-panel',
          layer: IdeCapabilityLayer.presentation,
          title: 'Problems panel',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_render',
          summary:
              'Active document diagnostics panel is wired into the IDE shell and has workspace diagnostics grouping, source grouping, severity filter, provider contract, per-diagnostic quick-fix selection, per-fix preview/apply command routing, quick-fix confirmation planning, WorkspaceQuickFixReviewPlan preview/control contracts, concrete diff/apply controls, persisted quick-fix telemetry Shell hydration and outcome row rendering, preview, and navigation available.',
          todo: 'TODO: add virtualized multi-file diff expansion.',
          runtimeMaturityBlocking: false,
          dependencies: <String>['workspace.diagnostics'],
          references: <String>[
            'VS Code Problems panel',
            'IntelliJ Problems tool window',
          ],
        ),
        IdeCapabilityDescriptor(
          id: 'presentation.output-panel',
          layer: IdeCapabilityLayer.presentation,
          title: 'Output, logs, and activity panel',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_render/runtime',
          summary:
              'Runtime Surface exposes Output Channels for runtime events, stdout, stderr, native tool activity, live output event previews, live RuntimeOutputLiveBuffer agent activity, language-service logs, debug events, serializable output channel filters, event-level output panel snapshots, reusable output channel snapshots, stream subscription plans, retention policies, RuntimeOutputProducerRegistry contracts, RuntimeOutputProducerAdapterRegistry event adapters for shell, terminal, toolchain, hosted, language-service, debug-adapter, and agent producers, RuntimeOutputProducerBindingController multi-producer live binding, RuntimeOutputLiveBuffer stream binding, ShellManagerRuntimeExecutionAdapter streams, ToolchainManagerRuntimeExecutionAdapter, ToolchainInstallRuntimeExecutionAdapter streams, HostedRuntimeExecutionAdapter streams, WorkspaceDiagnosticsRuntimeOutputBinding streams, DebugLaunchRuntimeOutputBinding streams, StyioServiceRuntimeOutputBinding streams, TerminalRuntimeOutputBinding streams, and persisted output history.',
          todo:
              'TODO: wire native OS PTY signal delivery telemetry and production stream cancellation telemetry.',
          runtimeMaturityBlocking: false,
          references: <String>[
            'VS Code Output panel',
            'IntelliJ Run and Event Log tool windows',
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------