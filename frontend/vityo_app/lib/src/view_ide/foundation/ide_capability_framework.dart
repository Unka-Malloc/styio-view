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
  final List<String> references;
  final List<String> dependencies;

  bool get needsFollowUp =>
      status == IdeCapabilityStatus.todo || todo.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'layer': layer.wireValue,
      'title': title,
      'status': status.wireValue,
      'ownerPath': ownerPath,
      if (summary.isNotEmpty) 'summary': summary,
      if (todo.isNotEmpty) 'todo': todo,
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
          todo:
              'TODO: connect every system-specific manager to capability health signals.',
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
              'Credential references, redacted metadata, injection results, batch injection, persisted FoundationDataStore credentials, credential storage health facts, and storage policy decisions are wired.',
          todo:
              'TODO: replace persisted FoundationDataStore secrets with platform-specific secure storage adapters.',
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
              'Styio-first parser, diagnostics, semantic facts, grammar-version facts, and extension language route consumption.',
          references: <String>['Language Server Protocol'],
        ),
        IdeCapabilityDescriptor(
          id: 'service.semantic-snapshot',
          layer: IdeCapabilityLayer.service,
          title: 'Semantic snapshot and resolved symbols',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/language/service',
          summary:
              'SemanticSnapshotProvider converts StyioService analysis into resolved elements/references and only falls back to local snapshots when service semantic facts are missing.',
          todo:
              'TODO: make StyioService the complete source for rename safety, references, and code action semantic facts.',
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
              'Caches StyioService results with protocol, parser engine, and grammar version metadata.',
        ),
        IdeCapabilityDescriptor(
          id: 'service.remote-service',
          layer: IdeCapabilityLayer.service,
          title: 'Remote service connector',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/agent',
          summary:
              'Agent provider route selection, credential readiness, endpoint probing, fallback selection, remote service health reports, and Foundation DataStore-backed health history are wired for OpenAI-compatible providers.',
          todo:
              'TODO: add retry policy execution and hosted backend connector parity.',
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
              'Registered commands for persistence, language refresh, navigation, refactor, tools, settings, debug, and extension command contribution route consumption.',
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
              'Diagnostics interaction can consume workspace diagnostics provider snapshots, serializable diagnostics filters, reusable diagnostics view models, and focused problem actions.',
          todo: 'TODO: add richer source grouping and fix confirmation flows.',
          dependencies: <String>['workspace.diagnostics'],
        ),
        IdeCapabilityDescriptor(
          id: 'interaction.search',
          layer: IdeCapabilityLayer.interaction,
          title: 'Search, symbols, and quick open',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/workspace',
          summary:
              'Workspace text search service, symbol search service, file quick open service, replace preview contract, search history persistence, agent search command, user search surface, and match-level navigation callback are wired.',
          todo:
              'TODO: add indexed workspace search, replace apply confirmation, and richer diff UI.',
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
              'Source Control surface is wired to dirty editor documents, Git porcelain status parsing, diff preview, staging action contracts, persisted commit drafts, action planning and confirmation, Git stage/unstage/discard/commit action provider, Git branch/history provider contracts, file open, and save-all handoff.',
          todo:
              'TODO: bind commit drafts into a dialog UI, add branch picker, history view, richer diff UI, and non-Git provider adapters.',
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
              'Testing surface is wired to runTests, native tool testResult records, TestRunProvider registry, TestDiscoveryProvider registry, test run configurations, test tree model, persisted test run history, runtime task lifecycle snapshots, persisted runtime task history, failed-test rerun planning, failed-test interaction, rerun-failed handoff, and CTest result parsing.',
          todo:
              'TODO: connect persisted run configuration UI, debug-test launch UI, test task output streams, and richer failure navigation contracts.',
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
              'Command Palette surface is wired to StyioCommandRegistry, category contribution manifests, shell command execution, reusable query scoring, typed input draft contracts, keyboard shortcuts, and blocked command availability reasons.',
          todo:
              'TODO: promote this panel to an overlay palette with typed command input UI, persisted recent command ranking, and richer command categories.',
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
              'Editor surface renders document, tabs, selection, token/semantic/diagnostic layers, folding, hover, completion, code-action facts, and serializable EditorRenderSnapshot contracts for UI and Agent consumers.',
          todo:
              'TODO: finish virtualized editor row rendering, semantic highlighting theme mapping, hover widgets, completion widgets, and code action widgets.',
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
              'WorkspaceDiagnosticsSnapshot and WorkspaceDiagnosticsProviderRegistry provide shared workspace problem facts for Problems, Agent, and code actions, including document grouping, source grouping, persisted filters, and workspace quick-fix confirmation plans.',
          todo:
              'TODO: bind project Styio diagnostics, native tool diagnostics, and quick-fix confirmation UI into one workspace diagnostics stream.',
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
              'WorkspaceFileOperationService provides create, rename, delete, and reveal contracts backed by WorkspaceDocumentStore and WorkspaceController synchronization. WorkspaceFileExplorerController exposes a file tree snapshot, unified explorer actions, restored expanded/selected/revealed state, sort preferences, and Foundation DataStore-backed explorer state persistence.',
          todo:
              'TODO: connect command palette actions, confirmation dialogs, richer file tree UI, and File System Manager-backed project file discovery.',
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
              'WorkspaceEditPlan, WorkspaceEditPreview, and WorkspaceEditApplier provide a shared preview and text-edit application path for agent patches, code actions, rename, and formatting.',
          todo:
              'TODO: add rollback, file create/delete operations, richer diff UI, and explicit confirmation flows.',
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
              'ExecutionSession, runtime events, native tool results, runtime execution plans, dependency readiness checks, runtime task lifecycle snapshots, persisted runtime task history, and extension task contribution definitions expose stable serializable execution contracts for UI and Agent consumers.',
          todo:
              'TODO: hand ready plans to shell/toolchain execution managers, normalize hosted/toolchain-specific metadata fields, and attach task output streams.',
          references: <String>['VS Code tasks', 'Theia task service'],
        ),
        IdeCapabilityDescriptor(
          id: 'runtime.terminal',
          layer: IdeCapabilityLayer.runtime,
          title: 'Terminal, PTY, and task runner',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/shell_runtime',
          summary:
              'Terminal surface is wired to shell/runtime output, run handoff, PTY session snapshots, TerminalInteractionController input/resize/close contracts, shared runtime task lifecycle snapshots on start/close, and persisted terminal task history.',
          todo:
              'TODO: connect real UI session lifecycle controls, shell manager process execution, and persisted task history into one terminal/runtime contract.',
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
              'DAP launch contracts, breakpoint serialization, persisted workspace breakpoint sets, launch profiles, workspace launch configuration sets, Foundation DataStore persistence, runtime task projection, DAP snapshot task-history binding, live ShellRuntime DAP history appends, and extension debugger route consumption are wired.',
          todo:
              'TODO: wire breakpoint UI editing, non-C++ debug adapters, launch UI editing, and test debug handoff.',
          references: <String>['Debug Adapter Protocol'],
        ),
        IdeCapabilityDescriptor(
          id: 'toolchain.manager',
          layer: IdeCapabilityLayer.toolchain,
          title: 'Toolchain manager',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/toolchain',
          summary:
              'Toolchain catalog, resolver, install policy, health checks, configuration persistence, managed downloads, Styio-first toolchain lifecycle reports, and extension toolchain route consumption are wired.',
          todo:
              'TODO: connect Styio toolchain lifecycle reports to settings UI, installer UX, and project bootstrap.',
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
              'OpenAI-compatible providers, credential-backed routes, fallback readiness, provider execution context, and extension agent provider contribution manifests.',
        ),
        IdeCapabilityDescriptor(
          id: 'agent.coding-loop',
          layer: IdeCapabilityLayer.agent,
          title: 'Agent coding loop',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/agent',
          summary:
              'Structured plan, diagnostics, code patch, IDE command, command result, WorkspaceEdit bridge, patch application loop, persisted coding session history, and embeddable activity history surface.',
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
              'Module manifests can be projected into stable extension manifests with activation events, contribution points, capability flags, registry lookup, Foundation DataStore persistence, extension activation sessions, persisted activation history, lifecycle snapshots, lifecycle hook catalogs/runners, host isolation plans, trust-policy gating, theme/view contribution catalogs, and contribution route manifests for target registries.',
          todo:
              'TODO: connect extension host isolation plans to a concrete process/service supervisor and activation telemetry UI.',
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
              'Extensions surface is wired to visible and mounted module manifests, lifecycle state, enable/disable/trust actions, update flags, refreshModules handoff, marketplace index search, install planning, and Foundation DataStore-backed marketplace cache.',
          todo:
              'TODO: add install execution, update download, signature verification, extension host isolation, and persisted lifecycle policy.',
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
              'Shell model, bottom tab routing, and serializable shell layout plans define top bar, activity rail, editor, bottom panel, and status bar contracts for desktop and compact viewports.',
          todo:
              'TODO: bind layout plans directly into scaffold rendering, persisted layout preferences, and mature panels for diagnostics, search, settings, extensions, debug, and agent activity.',
          references: <String>['VS Code workbench', 'IntelliJ tool windows'],
        ),
        IdeCapabilityDescriptor(
          id: 'presentation.problems-panel',
          layer: IdeCapabilityLayer.presentation,
          title: 'Problems panel',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_render',
          summary:
              'Active document diagnostics panel is wired into the IDE shell and has workspace diagnostics grouping, source grouping, severity filter, provider contract, quick-fix confirmation planning, preview, and navigation available.',
          todo:
              'TODO: bind quick-fix confirmation plans into an explicit diff/apply UI flow.',
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
              'Runtime Surface exposes Output Channels for runtime events, stdout, stderr, native tool activity, serializable output channel filters, reusable output channel snapshots, and persisted output history.',
          todo:
              'TODO: add agent activity, language-service logs, and debug event streams.',
          references: <String>[
            'VS Code Output panel',
            'IntelliJ Run and Event Log tool windows',
          ],
        ),
      ],
    );
  }
}
