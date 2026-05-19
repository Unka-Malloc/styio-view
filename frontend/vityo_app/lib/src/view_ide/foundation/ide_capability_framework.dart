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
              'Credential references, redacted metadata, injection results, batch injection, persisted FoundationDataStore credentials, and credential storage health facts are wired.',
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
              'Styio-first parser, diagnostics, semantic facts, and grammar-version facts.',
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
              'Agent provider route selection, credential readiness, endpoint probing, fallback selection, and remote service health reports are wired for OpenAI-compatible providers.',
          todo:
              'TODO: add retry policy execution, hosted backend connector parity, and persisted health history.',
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
              'Registered commands for persistence, language refresh, navigation, refactor, tools, settings, and debug.',
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
              'Diagnostics interaction can consume workspace diagnostics provider snapshots before rendering focused problem actions.',
          todo:
              'TODO: add workspace-wide diagnostics grouping, filtering, and quick-fix preview UI.',
          dependencies: <String>['workspace.diagnostics'],
        ),
        IdeCapabilityDescriptor(
          id: 'interaction.search',
          layer: IdeCapabilityLayer.interaction,
          title: 'Search, symbols, and quick open',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/workspace',
          summary:
              'Workspace text search service, symbol search service, file quick open service, replace preview contract, agent search command, user search surface, and match-level navigation callback are wired.',
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
              'Source Control surface is wired to dirty editor documents, Git porcelain status parsing, diff preview, Git stage/unstage/discard/commit action provider, Git branch/history provider contracts, file open, and save-all handoff.',
          todo:
              'TODO: add commit message dialog, branch picker, history view, richer diff UI, and non-Git provider adapters.',
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
              'Testing surface is wired to runTests, native tool testResult records, TestRunProvider registry, TestDiscoveryProvider registry, test run configurations, test tree model, run history, failed-test rerun planning, failed-test interaction, rerun-failed handoff, and CTest result parsing.',
          todo:
              'TODO: connect persisted run configuration UI, debug-test launch UI, and richer failure navigation contracts.',
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
              'Command Palette surface is wired to StyioCommandRegistry, category contribution manifests, shell command execution, search filtering, keyboard shortcuts, and blocked command availability reasons.',
          todo:
              'TODO: promote this panel to an overlay palette with typed command inputs, recent command ranking, and richer command categories.',
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
          todo:
              'TODO: finish virtualized editor rendering, semantic highlighting, hover, completion, and code action widgets.',
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
              'WorkspaceDiagnosticsSnapshot and WorkspaceDiagnosticsProviderRegistry provide shared workspace problem facts for Problems, Agent, and code actions.',
          todo:
              'TODO: bind project Styio diagnostics, native tool diagnostics, and quick-fix previews into one workspace diagnostics stream.',
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
              'WorkspaceFileOperationService provides create, rename, delete, and reveal contracts backed by WorkspaceDocumentStore and WorkspaceController synchronization. WorkspaceFileExplorerController exposes a file tree snapshot and unified explorer actions.',
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
          todo:
              'TODO: align run/test/build execution result contracts across hosted, local, and toolchain-backed routes.',
          references: <String>['VS Code tasks', 'Theia task service'],
        ),
        IdeCapabilityDescriptor(
          id: 'runtime.terminal',
          layer: IdeCapabilityLayer.runtime,
          title: 'Terminal, PTY, and task runner',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/shell_runtime',
          summary:
              'Terminal surface is wired to shell/runtime output, run handoff, PTY session snapshots, and TerminalInteractionController input/resize/close contracts.',
          todo:
              'TODO: connect real UI session lifecycle controls, shell manager process execution, and task lifecycle into one terminal/runtime contract.',
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
          todo:
              'TODO: wire non-C++ debug adapters and persisted launch configurations.',
          references: <String>['Debug Adapter Protocol'],
        ),
        IdeCapabilityDescriptor(
          id: 'toolchain.manager',
          layer: IdeCapabilityLayer.toolchain,
          title: 'Toolchain manager',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_ide/toolchain',
          todo:
              'TODO: prioritize Styio toolchain lifecycle and keep native C/C++ support conditional.',
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
              'OpenAI-compatible providers, credential-backed routes, fallback readiness, and provider execution context.',
        ),
        IdeCapabilityDescriptor(
          id: 'agent.coding-loop',
          layer: IdeCapabilityLayer.agent,
          title: 'Agent coding loop',
          status: IdeCapabilityStatus.wired,
          ownerPath: 'lib/src/view_ide/agent',
          summary:
              'Structured plan, diagnostics, code patch, IDE command, command result, WorkspaceEdit bridge, and patch application loop.',
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
          todo:
              'TODO: turn module manifest into a stable extension contribution contract.',
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
              'Extensions surface is wired to visible and mounted module manifests, lifecycle state, enable/disable/trust actions, update flags, and refreshModules handoff.',
          todo:
              'TODO: add install, update download, marketplace index, extension host isolation, and persisted lifecycle policy.',
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
          todo:
              'TODO: finish mature IDE panels for diagnostics, search, settings, extensions, debug, and agent activity.',
          references: <String>['VS Code workbench', 'IntelliJ tool windows'],
        ),
        IdeCapabilityDescriptor(
          id: 'presentation.problems-panel',
          layer: IdeCapabilityLayer.presentation,
          title: 'Problems panel',
          status: IdeCapabilityStatus.scaffolded,
          ownerPath: 'lib/src/view_render',
          summary:
              'Active document diagnostics panel is wired into the IDE shell and has workspace diagnostics grouping, severity filter, provider contract, quick-fix preview, and navigation available.',
          todo:
              'TODO: add persisted problem filters, richer source grouping, and fix confirmation flows.',
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
              'Runtime Surface exposes Output Channels for runtime events, stdout, stderr, and native tool activity.',
          todo:
              'TODO: add user-selectable filters, agent activity, language-service logs, debug events, and persisted output history.',
          references: <String>[
            'VS Code Output panel',
            'IntelliJ Run and Event Log tool windows',
          ],
        ),
      ],
    );
  }
}
