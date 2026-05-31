enum AppCommandId {
  save,
  run,
  commandPalette,
  quickOpen,
  goToWorkspaceDefinition,
  renameWorkspaceSymbol,
  searchWorkspaceSymbols,
  findWorkspaceReferences,
  showWorkspaceCallHierarchy,
  searchWorkspace,
  showWorkspaceProblems,
  showWorkspaceCodeActions,
  fetchDependencies,
  vendorDependencies,
  useActiveCompiler,
  pinActiveCompiler,
  clearPinnedCompiler,
  packProject,
  preparePublish,
  showRuntime,
  showAgent,
  showDebug,
  refreshModules,
  openSettings,
}

class AppCommandShortcutSpec {
  const AppCommandShortcutSpec(
    this.key, {
    this.control = false,
    this.meta = false,
    this.alt = false,
    this.shift = false,
  });

  final String key;
  final bool control;
  final bool meta;
  final bool alt;
  final bool shift;
}

class AppCommandDescriptor {
  const AppCommandDescriptor({
    required this.id,
    required this.label,
    required this.shortcutHint,
    required this.description,
    this.primary = false,
    this.shortcuts = const <AppCommandShortcutSpec>[],
  });

  final AppCommandId id;
  final String label;
  final String shortcutHint;
  final String description;
  final bool primary;
  final List<AppCommandShortcutSpec> shortcuts;
}

class StyioCommandRegistry {
  static const List<AppCommandDescriptor> commands = [
    AppCommandDescriptor(
      id: AppCommandId.save,
      label: 'Save',
      shortcutHint: 'Cmd/Ctrl+S',
      description: 'Persist the current workspace target.',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyS', control: true),
        AppCommandShortcutSpec('keyS', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.run,
      label: 'Run',
      shortcutHint: 'Cmd/Ctrl+Enter',
      description: 'Run the active minimal compilable unit.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('enter', control: true),
        AppCommandShortcutSpec('enter', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.commandPalette,
      label: 'Command Palette',
      shortcutHint: 'Cmd/Ctrl+Shift+P',
      description: 'Search and run registered shell commands.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyP', control: true, shift: true),
        AppCommandShortcutSpec('keyP', meta: true, shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.quickOpen,
      label: 'Quick Open',
      shortcutHint: 'Cmd/Ctrl+P',
      description: 'Open a workspace file by fuzzy name or path.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyP', control: true),
        AppCommandShortcutSpec('keyP', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.goToWorkspaceDefinition,
      label: 'Go to Definition',
      shortcutHint: 'F12',
      description: 'Open matching workspace definitions for a symbol.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('f12'),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.renameWorkspaceSymbol,
      label: 'Rename Symbol',
      shortcutHint: 'F2',
      description: 'Preview and apply a workspace symbol rename.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('f2'),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.searchWorkspaceSymbols,
      label: 'Symbols',
      shortcutHint: 'Cmd/Ctrl+T',
      description: 'Search symbols across workspace files.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyT', control: true),
        AppCommandShortcutSpec('keyT', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.findWorkspaceReferences,
      label: 'Find Usages',
      shortcutHint: 'Shift+F12',
      description: 'Find project-wide usages of a workspace symbol.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('f12', shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceCallHierarchy,
      label: 'Call Hierarchy',
      shortcutHint: 'Ctrl+Alt+H',
      description: 'Browse incoming and outgoing calls for a workspace symbol.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyH', control: true, alt: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.searchWorkspace,
      label: 'Find in Files',
      shortcutHint: 'Cmd/Ctrl+Shift+F',
      description: 'Search text across the current workspace files.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyF', control: true, shift: true),
        AppCommandShortcutSpec('keyF', meta: true, shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceProblems,
      label: 'Problems',
      shortcutHint: 'Route',
      description: 'Show workspace diagnostics across project files.',
      primary: true,
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceCodeActions,
      label: 'Code Actions',
      shortcutHint: 'Cmd/Ctrl+.',
      description:
          'Preview and apply workspace quick fixes and source actions.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('period', control: true),
        AppCommandShortcutSpec('period', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.fetchDependencies,
      label: 'Fetch',
      shortcutHint: 'Route',
      description: 'Materialize dependency sources into the local spio cache.',
      primary: true,
    ),
    AppCommandDescriptor(
      id: AppCommandId.vendorDependencies,
      label: 'Vendor',
      shortcutHint: 'Cmd/Ctrl+Shift+V',
      description: 'Materialize project-local vendored dependency snapshots.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyV', control: true, shift: true),
        AppCommandShortcutSpec('keyV', meta: true, shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.useActiveCompiler,
      label: 'Use Compiler',
      shortcutHint: 'Route',
      description:
          'Use the currently resolved compiler version as the managed spio compiler.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.pinActiveCompiler,
      label: 'Pin Compiler',
      shortcutHint: 'Route',
      description:
          'Pin the currently resolved compiler version into spio-toolchain.toml.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.clearPinnedCompiler,
      label: 'Clear Pin',
      shortcutHint: 'Route',
      description: 'Clear the current project toolchain pin.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.packProject,
      label: 'Pack',
      shortcutHint: 'Route',
      description: 'Create a package archive for the active project.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.preparePublish,
      label: 'Preflight',
      shortcutHint: 'Route',
      description: 'Run publish preflight for the active project.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.showRuntime,
      label: 'Runtime',
      shortcutHint: 'Shift+1',
      description: 'Focus the runtime surface.',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('digit1', shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showAgent,
      label: 'Agent',
      shortcutHint: 'Shift+2',
      description: 'Focus the agent surface.',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('digit2', shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showDebug,
      label: 'Debug',
      shortcutHint: 'Shift+3',
      description: 'Focus the debug console.',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('digit3', shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.refreshModules,
      label: 'Refresh',
      shortcutHint: 'Cmd/Ctrl+R',
      description:
          'Refresh module host state, project graph, and toolchain contracts.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyR', control: true),
        AppCommandShortcutSpec('keyR', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.openSettings,
      label: 'Settings',
      shortcutHint: 'Cmd/Ctrl+,',
      description: 'Open settings and profile routes.',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('comma', control: true),
        AppCommandShortcutSpec('comma', meta: true),
      ],
    ),
  ];

  static Iterable<AppCommandDescriptor> get primaryCommands =>
      commands.where((command) => command.primary);

  static Iterable<AppCommandDescriptor> get executionCommands => commands.where(
    (command) => switch (command.id) {
      AppCommandId.run => true,
      _ => false,
    },
  );

  static Iterable<AppCommandDescriptor> get searchCommands => commands.where(
    (command) => switch (command.id) {
      AppCommandId.searchWorkspace ||
      AppCommandId.showWorkspaceCallHierarchy ||
      AppCommandId.goToWorkspaceDefinition ||
      AppCommandId.findWorkspaceReferences ||
      AppCommandId.searchWorkspaceSymbols => true,
      _ => false,
    },
  );

  static Iterable<AppCommandDescriptor> get navigationCommands =>
      commands.where(
        (command) => switch (command.id) {
          AppCommandId.commandPalette ||
          AppCommandId.quickOpen ||
          AppCommandId.goToWorkspaceDefinition ||
          AppCommandId.renameWorkspaceSymbol ||
          AppCommandId.findWorkspaceReferences ||
          AppCommandId.showWorkspaceCallHierarchy ||
          AppCommandId.showWorkspaceProblems ||
          AppCommandId.showWorkspaceCodeActions ||
          AppCommandId.searchWorkspaceSymbols => true,
          _ => false,
        },
      );

  static Iterable<AppCommandDescriptor> get dependencyCommands =>
      commands.where(
        (command) => switch (command.id) {
          AppCommandId.fetchDependencies ||
          AppCommandId.vendorDependencies => true,
          _ => false,
        },
      );

  static Iterable<AppCommandDescriptor> get toolchainCommands => commands.where(
    (command) => switch (command.id) {
      AppCommandId.useActiveCompiler ||
      AppCommandId.pinActiveCompiler ||
      AppCommandId.clearPinnedCompiler => true,
      _ => false,
    },
  );

  static Iterable<AppCommandDescriptor> get workflowCommands => commands.where(
    (command) => switch (command.id) {
      AppCommandId.run ||
      AppCommandId.commandPalette ||
      AppCommandId.quickOpen ||
      AppCommandId.goToWorkspaceDefinition ||
      AppCommandId.renameWorkspaceSymbol ||
      AppCommandId.searchWorkspaceSymbols ||
      AppCommandId.findWorkspaceReferences ||
      AppCommandId.showWorkspaceCallHierarchy ||
      AppCommandId.searchWorkspace ||
      AppCommandId.showWorkspaceProblems ||
      AppCommandId.showWorkspaceCodeActions ||
      AppCommandId.fetchDependencies ||
      AppCommandId.vendorDependencies ||
      AppCommandId.useActiveCompiler ||
      AppCommandId.pinActiveCompiler ||
      AppCommandId.clearPinnedCompiler ||
      AppCommandId.packProject ||
      AppCommandId.preparePublish => true,
      _ => false,
    },
  );

  static Iterable<AppCommandDescriptor> get deploymentCommands =>
      commands.where(
        (command) => switch (command.id) {
          AppCommandId.packProject || AppCommandId.preparePublish => true,
          _ => false,
        },
      );

  static AppCommandDescriptor descriptorFor(AppCommandId id) =>
      commands.firstWhere((command) => command.id == id);
}
