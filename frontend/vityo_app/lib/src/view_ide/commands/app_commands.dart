enum AppCommandId {
  save,
  saveAll,
  run,
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
  toggleBreakpoint,
  startDebugging,
  stopDebugging,
  continueDebugging,
  stepOver,
  selectDebugThread,
  selectDebugStackFrame,
  nextDiagnostic,
  previousDiagnostic,
  applyQuickFix,
  refreshLanguageService,
  refreshWorkspaceDiagnostics,
  refreshSourceControl,
  previewSourceControlDiff,
  openWorkspaceFile,
  searchWorkspace,
  runBuild,
  formatActiveDocument,
  runStaticAnalysis,
  runTests,
  goToDefinition,
  nextReference,
  previousReference,
  renameSymbol,
  safeDelete,
  inlineVariable,
  refreshModules,
  selectClangCppVersion,
  openSettings,
}

class AppCommandShortcutSpec {
  const AppCommandShortcutSpec(
    this.key, {
    this.control = false,
    this.meta = false,
    this.shift = false,
  });

  final String key;
  final bool control;
  final bool meta;
  final bool shift;
}

class AppCommandDescriptor {
  const AppCommandDescriptor({
    required this.id,
    required this.label,
    required this.shortcutHint,
    required this.description,
    this.primary = false,
    this.requiresInput = false,
    this.inputLabel = '',
    this.shortcuts = const <AppCommandShortcutSpec>[],
  });

  final AppCommandId id;
  final String label;
  final String shortcutHint;
  final String description;
  final bool primary;
  final bool requiresInput;
  final String inputLabel;
  final List<AppCommandShortcutSpec> shortcuts;
}

class StyioCommandRegistry {
  static const List<AppCommandDescriptor> commands = [
    AppCommandDescriptor(
      id: AppCommandId.save,
      label: 'Save',
      shortcutHint: 'Cmd/Ctrl+S',
      description: 'Persist the current workspace target.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyS', control: true),
        AppCommandShortcutSpec('keyS', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.saveAll,
      label: 'Save All',
      shortcutHint: 'Cmd/Ctrl+Shift+S',
      description: 'Persist every dirty open workspace document.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyS', control: true, shift: true),
        AppCommandShortcutSpec('keyS', meta: true, shift: true),
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
      id: AppCommandId.fetchDependencies,
      label: 'Fetch',
      shortcutHint: 'Cmd/Ctrl+Shift+F',
      description: 'Materialize dependency sources into the local spio cache.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyF', control: true, shift: true),
        AppCommandShortcutSpec('keyF', meta: true, shift: true),
      ],
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
      id: AppCommandId.selectClangCppVersion,
      label: 'Select Clang/C++',
      shortcutHint: 'Route',
      description:
          'Select the IDE-managed Clang/C++ compiler version and optional C++ standard.',
      requiresInput: true,
      inputLabel: 'Clang/C++ version id and optional C++ standard',
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
      id: AppCommandId.toggleBreakpoint,
      label: 'Toggle Breakpoint',
      shortcutHint: 'F9',
      description: 'Toggle a line breakpoint at the editor selection.',
      shortcuts: <AppCommandShortcutSpec>[AppCommandShortcutSpec('f9')],
    ),
    AppCommandDescriptor(
      id: AppCommandId.startDebugging,
      label: 'Start Debugging',
      shortcutHint: 'F5',
      description: 'Prepare or start the active native debug session.',
      shortcuts: <AppCommandShortcutSpec>[AppCommandShortcutSpec('f5')],
    ),
    AppCommandDescriptor(
      id: AppCommandId.stopDebugging,
      label: 'Stop Debugging',
      shortcutHint: 'Shift+F5',
      description: 'Stop the active native debug session.',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('f5', shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.continueDebugging,
      label: 'Continue Debugging',
      shortcutHint: 'Route',
      description: 'Continue the paused native debug session.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.stepOver,
      label: 'Step Over',
      shortcutHint: 'F10',
      description: 'Step over the current debug frame.',
      shortcuts: <AppCommandShortcutSpec>[AppCommandShortcutSpec('f10')],
    ),
    AppCommandDescriptor(
      id: AppCommandId.selectDebugThread,
      label: 'Select Debug Thread',
      shortcutHint: 'Route',
      description: 'Select a paused DAP thread and refresh its call stack.',
      requiresInput: true,
      inputLabel: 'DAP thread id',
    ),
    AppCommandDescriptor(
      id: AppCommandId.selectDebugStackFrame,
      label: 'Select Debug Stack Frame',
      shortcutHint: 'Route',
      description:
          'Select a paused DAP stack frame and refresh its local variables.',
      requiresInput: true,
      inputLabel: 'DAP stack frame id',
    ),
    AppCommandDescriptor(
      id: AppCommandId.nextDiagnostic,
      label: 'Next Diagnostic',
      shortcutHint: 'F8',
      description: 'Move editor focus to the next diagnostic.',
      shortcuts: <AppCommandShortcutSpec>[AppCommandShortcutSpec('f8')],
    ),
    AppCommandDescriptor(
      id: AppCommandId.previousDiagnostic,
      label: 'Previous Diagnostic',
      shortcutHint: 'Shift+F8',
      description: 'Move editor focus to the previous diagnostic.',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('f8', shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.applyQuickFix,
      label: 'Quick Fix',
      shortcutHint: 'Cmd/Ctrl+.',
      description: 'Apply the first available quick fix or code action.',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('period', control: true),
        AppCommandShortcutSpec('period', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.refreshLanguageService,
      label: 'Refresh Language Service',
      shortcutHint: 'Route',
      description: 'Refresh StyioService facts for the active editor document.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.refreshWorkspaceDiagnostics,
      label: 'Refresh Workspace Diagnostics',
      shortcutHint: 'Route',
      description:
          'Refresh cached workspace diagnostics for Agent, Problems, and code actions.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.refreshSourceControl,
      label: 'Refresh Source Control',
      shortcutHint: 'Route',
      description: 'Refresh source-control status for the active workspace.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.previewSourceControlDiff,
      label: 'Preview Source Control Diff',
      shortcutHint: 'Route',
      description:
          'Preview the current unified diff for a changed workspace file.',
      requiresInput: true,
      inputLabel: 'Changed file path',
    ),
    AppCommandDescriptor(
      id: AppCommandId.goToDefinition,
      label: 'Go to Definition',
      shortcutHint: 'F12',
      description: 'Move editor focus to the resolved definition.',
      shortcuts: <AppCommandShortcutSpec>[AppCommandShortcutSpec('f12')],
    ),
    AppCommandDescriptor(
      id: AppCommandId.openWorkspaceFile,
      label: 'Open Workspace File',
      shortcutHint: 'Route',
      description:
          'Open a workspace file so the editor and Agent can sample it.',
      requiresInput: true,
      inputLabel: 'Workspace file path',
    ),
    AppCommandDescriptor(
      id: AppCommandId.searchWorkspace,
      label: 'Search Workspace',
      shortcutHint: 'Route',
      description:
          'Search workspace documents and expose capped results to the next Agent context.',
      requiresInput: true,
      inputLabel: 'Search query',
    ),
    AppCommandDescriptor(
      id: AppCommandId.runBuild,
      label: 'Run Build',
      shortcutHint: 'Route',
      description:
          'Run the registered native build tool for the active workspace.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.formatActiveDocument,
      label: 'Format Active Document',
      shortcutHint: 'Route',
      description:
          'Format the active document through the registered native formatter.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.runStaticAnalysis,
      label: 'Run Static Analysis',
      shortcutHint: 'Route',
      description:
          'Run the registered native static-analysis tool for the active document.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.runTests,
      label: 'Run Tests',
      shortcutHint: 'Route',
      description: 'Run the registered native test runner for the workspace.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.nextReference,
      label: 'Next Reference',
      shortcutHint: 'Shift+F12',
      description: 'Move editor focus to the next resolved reference.',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('f12', shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.previousReference,
      label: 'Previous Reference',
      shortcutHint: 'Cmd/Ctrl+Shift+F12',
      description: 'Move editor focus to the previous resolved reference.',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('f12', control: true, shift: true),
        AppCommandShortcutSpec('f12', meta: true, shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.renameSymbol,
      label: 'Rename Symbol',
      shortcutHint: 'Route',
      description: 'Rename the resolved symbol and its safe references.',
      requiresInput: true,
      inputLabel: 'New symbol name',
    ),
    AppCommandDescriptor(
      id: AppCommandId.safeDelete,
      label: 'Safe Delete',
      shortcutHint: 'Route',
      description:
          'Delete the resolved symbol only when no unsafe usages remain.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.inlineVariable,
      label: 'Inline Variable',
      shortcutHint: 'Route',
      description: 'Replace references with the resolved variable initializer.',
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

  static Iterable<AppCommandDescriptor> get persistenceCommands =>
      commands.where(
        (command) => switch (command.id) {
          AppCommandId.save || AppCommandId.saveAll => true,
          _ => false,
        },
      );

  static Iterable<AppCommandDescriptor> get diagnosticCommands =>
      commands.where(
        (command) => switch (command.id) {
          AppCommandId.nextDiagnostic ||
          AppCommandId.previousDiagnostic ||
          AppCommandId.applyQuickFix ||
          AppCommandId.refreshWorkspaceDiagnostics => true,
          _ => false,
        },
      );

  static Iterable<AppCommandDescriptor> get languageServiceCommands =>
      commands.where(
        (command) => switch (command.id) {
          AppCommandId.refreshLanguageService => true,
          _ => false,
        },
      );

  static Iterable<AppCommandDescriptor> get sourceControlCommands =>
      commands.where(
        (command) => switch (command.id) {
          AppCommandId.refreshSourceControl ||
          AppCommandId.previewSourceControlDiff => true,
          _ => false,
        },
      );

  static Iterable<AppCommandDescriptor> get debugCommands => commands.where(
    (command) => switch (command.id) {
      AppCommandId.toggleBreakpoint ||
      AppCommandId.startDebugging ||
      AppCommandId.stopDebugging ||
      AppCommandId.continueDebugging ||
      AppCommandId.stepOver ||
      AppCommandId.selectDebugThread ||
      AppCommandId.selectDebugStackFrame => true,
      _ => false,
    },
  );

  static Iterable<AppCommandDescriptor> get navigationCommands =>
      commands.where(
        (command) => switch (command.id) {
          AppCommandId.goToDefinition ||
          AppCommandId.openWorkspaceFile ||
          AppCommandId.searchWorkspace ||
          AppCommandId.nextReference ||
          AppCommandId.previousReference => true,
          _ => false,
        },
      );

  static Iterable<AppCommandDescriptor> get refactorCommands => commands.where(
    (command) => switch (command.id) {
      AppCommandId.renameSymbol ||
      AppCommandId.safeDelete ||
      AppCommandId.inlineVariable => true,
      _ => false,
    },
  );

  static Iterable<AppCommandDescriptor> get nativeToolCommands =>
      commands.where(
        (command) => switch (command.id) {
          AppCommandId.runBuild ||
          AppCommandId.formatActiveDocument ||
          AppCommandId.runStaticAnalysis ||
          AppCommandId.runTests => true,
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
      AppCommandId.clearPinnedCompiler ||
      AppCommandId.selectClangCppVersion => true,
      _ => false,
    },
  );

  static Iterable<AppCommandDescriptor> get settingsCommands => commands.where(
    (command) => switch (command.id) {
      AppCommandId.openSettings => true,
      _ => false,
    },
  );

  static Iterable<AppCommandDescriptor> get workflowCommands => commands.where(
    (command) => switch (command.id) {
      AppCommandId.run ||
      AppCommandId.fetchDependencies ||
      AppCommandId.vendorDependencies ||
      AppCommandId.useActiveCompiler ||
      AppCommandId.pinActiveCompiler ||
      AppCommandId.clearPinnedCompiler ||
      AppCommandId.selectClangCppVersion ||
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
