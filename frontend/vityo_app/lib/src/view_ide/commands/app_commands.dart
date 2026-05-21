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
  previewQuickFix,
  refreshLanguageService,
  refreshWorkspaceDiagnostics,
  refreshSourceControl,
  previewSourceControlDiff,
  stageSourceControl,
  unstageSourceControl,
  planSourceControlBranchSwitch,
  planSourceControlCommitDraft,
  collectAgentCodingCheckpoint,
  collectProjectLanguageContext,
  retryAgentProvider,
  failoverAgentProvider,
  replayAgentPrompt,
  openWorkspaceFile,
  createWorkspaceFile,
  renameWorkspaceFile,
  deleteWorkspaceFile,
  revealWorkspaceFile,
  searchWorkspace,
  previewWorkspaceReplace,
  applyWorkspaceReplace,
  runBuild,
  formatActiveDocument,
  runStaticAnalysis,
  runTests,
  rerunFailedTests,
  debugFailedTests,
  runTestConfiguration,
  debugTestConfiguration,
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

enum AppCommandCategory {
  persistence,
  execution,
  testing,
  dependency,
  toolchain,
  deployment,
  surface,
  diagnostics,
  languageService,
  sourceControl,
  agentCoding,
  navigation,
  workspace,
  refactor,
  debug,
  module,
  settings,
}

extension AppCommandCategoryX on AppCommandCategory {
  String get wireValue {
    return switch (this) {
      AppCommandCategory.persistence => 'persistence',
      AppCommandCategory.execution => 'execution',
      AppCommandCategory.testing => 'testing',
      AppCommandCategory.dependency => 'dependency',
      AppCommandCategory.toolchain => 'toolchain',
      AppCommandCategory.deployment => 'deployment',
      AppCommandCategory.surface => 'surface',
      AppCommandCategory.diagnostics => 'diagnostics',
      AppCommandCategory.languageService => 'language-service',
      AppCommandCategory.sourceControl => 'source-control',
      AppCommandCategory.agentCoding => 'agent-coding',
      AppCommandCategory.navigation => 'navigation',
      AppCommandCategory.workspace => 'workspace',
      AppCommandCategory.refactor => 'refactor',
      AppCommandCategory.debug => 'debug',
      AppCommandCategory.module => 'module',
      AppCommandCategory.settings => 'settings',
    };
  }
}

extension AppCommandIdX on AppCommandId {
  AppCommandCategory get category {
    return switch (this) {
      AppCommandId.save ||
      AppCommandId.saveAll => AppCommandCategory.persistence,
      AppCommandId.run => AppCommandCategory.execution,
      AppCommandId.fetchDependencies ||
      AppCommandId.vendorDependencies => AppCommandCategory.dependency,
      AppCommandId.useActiveCompiler ||
      AppCommandId.pinActiveCompiler ||
      AppCommandId.clearPinnedCompiler ||
      AppCommandId.selectClangCppVersion => AppCommandCategory.toolchain,
      AppCommandId.packProject ||
      AppCommandId.preparePublish => AppCommandCategory.deployment,
      AppCommandId.showRuntime ||
      AppCommandId.showAgent ||
      AppCommandId.showDebug => AppCommandCategory.surface,
      AppCommandId.nextDiagnostic ||
      AppCommandId.previousDiagnostic ||
      AppCommandId.applyQuickFix ||
      AppCommandId.previewQuickFix ||
      AppCommandId.refreshWorkspaceDiagnostics =>
        AppCommandCategory.diagnostics,
      AppCommandId.refreshLanguageService => AppCommandCategory.languageService,
      AppCommandId.refreshSourceControl ||
      AppCommandId.previewSourceControlDiff ||
      AppCommandId.stageSourceControl ||
      AppCommandId.unstageSourceControl ||
      AppCommandId.planSourceControlBranchSwitch ||
      AppCommandId.planSourceControlCommitDraft =>
        AppCommandCategory.sourceControl,
      AppCommandId.collectAgentCodingCheckpoint ||
      AppCommandId.collectProjectLanguageContext ||
      AppCommandId.retryAgentProvider ||
      AppCommandId.failoverAgentProvider ||
      AppCommandId.replayAgentPrompt => AppCommandCategory.agentCoding,
      AppCommandId.openWorkspaceFile ||
      AppCommandId.searchWorkspace ||
      AppCommandId.previewWorkspaceReplace ||
      AppCommandId.applyWorkspaceReplace ||
      AppCommandId.goToDefinition ||
      AppCommandId.nextReference ||
      AppCommandId.previousReference => AppCommandCategory.navigation,
      AppCommandId.createWorkspaceFile ||
      AppCommandId.renameWorkspaceFile ||
      AppCommandId.deleteWorkspaceFile ||
      AppCommandId.revealWorkspaceFile => AppCommandCategory.workspace,
      AppCommandId.renameSymbol ||
      AppCommandId.safeDelete ||
      AppCommandId.inlineVariable => AppCommandCategory.refactor,
      AppCommandId.toggleBreakpoint ||
      AppCommandId.startDebugging ||
      AppCommandId.stopDebugging ||
      AppCommandId.continueDebugging ||
      AppCommandId.stepOver ||
      AppCommandId.selectDebugThread ||
      AppCommandId.selectDebugStackFrame => AppCommandCategory.debug,
      AppCommandId.runBuild ||
      AppCommandId.formatActiveDocument ||
      AppCommandId.runStaticAnalysis ||
      AppCommandId.runTests => AppCommandCategory.execution,
      AppCommandId.rerunFailedTests ||
      AppCommandId.debugFailedTests ||
      AppCommandId.runTestConfiguration ||
      AppCommandId.debugTestConfiguration => AppCommandCategory.testing,
      AppCommandId.refreshModules => AppCommandCategory.module,
      AppCommandId.openSettings => AppCommandCategory.settings,
    };
  }
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key,
      'control': control,
      'meta': meta,
      'shift': shift,
    };
  }
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
    this.inputContract = '',
    this.inputExamples = const <String>[],
    this.shortcuts = const <AppCommandShortcutSpec>[],
  });

  final AppCommandId id;
  final String label;
  final String shortcutHint;
  final String description;
  final bool primary;
  final bool requiresInput;
  final String inputLabel;
  final String inputContract;
  final List<String> inputExamples;
  final List<AppCommandShortcutSpec> shortcuts;

  AppCommandCategory get category => id.category;

  Map<String, Object?> toContributionJson() {
    return <String, Object?>{
      'id': id.name,
      'category': category.wireValue,
      'label': label,
      'description': description,
      'shortcutHint': shortcutHint,
      'primary': primary,
      'requiresInput': requiresInput,
      if (inputLabel.isNotEmpty) 'inputLabel': inputLabel,
      if (inputContract.isNotEmpty) 'inputContract': inputContract,
      if (inputExamples.isNotEmpty) 'inputExamples': inputExamples,
      if (shortcuts.isNotEmpty)
        'shortcuts': shortcuts.map((shortcut) => shortcut.toJson()).toList(),
    };
  }
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
      description:
          'Apply the first available quick fix/code action, or select one by 1-based index or label.',
      inputLabel: 'Optional quick fix index or label',
      inputContract:
          'Optional. Use a 1-based quick fix index, exact label, or label fragment from language.codeActions.',
      inputExamples: <String>['1', '2', 'Replace with second'],
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('period', control: true),
        AppCommandShortcutSpec('period', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.previewQuickFix,
      label: 'Preview Quick Fix',
      shortcutHint: 'Route',
      description:
          'Preview the first deterministic project quick fix without applying edits.',
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
      id: AppCommandId.stageSourceControl,
      label: 'Stage Source Control Paths',
      shortcutHint: 'Route',
      description:
          'Stage one or more changed workspace paths through the source-control action contract.',
      requiresInput: true,
      inputLabel: 'Changed file path(s)',
    ),
    AppCommandDescriptor(
      id: AppCommandId.unstageSourceControl,
      label: 'Unstage Source Control Paths',
      shortcutHint: 'Route',
      description:
          'Unstage one or more changed workspace paths through the source-control action contract.',
      requiresInput: true,
      inputLabel: 'Changed file path(s)',
    ),
    AppCommandDescriptor(
      id: AppCommandId.planSourceControlBranchSwitch,
      label: 'Plan Source Control Branch Switch',
      shortcutHint: 'Route',
      description:
          'Load branch facts and prepare a source-control branch switch plan without switching branches.',
      requiresInput: true,
      inputLabel: 'Target branch',
    ),
    AppCommandDescriptor(
      id: AppCommandId.planSourceControlCommitDraft,
      label: 'Plan Source Control Commit Draft',
      shortcutHint: 'Route',
      description:
          'Prepare a source-control commit draft without creating a revision.',
      requiresInput: true,
      inputLabel: 'Commit message or message -> path(s)',
    ),
    AppCommandDescriptor(
      id: AppCommandId.collectAgentCodingCheckpoint,
      label: 'Collect Coding Checkpoint',
      shortcutHint: 'Route',
      description:
          'Refresh diagnostics, source-control status, and first diff preview for the Agent coding loop.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.collectProjectLanguageContext,
      label: 'Collect Project Language Context',
      shortcutHint: 'Route',
      description:
          'Collect project-level Styio definitions, references, hover, and completion facts for the Agent coding loop.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.retryAgentProvider,
      label: 'Retry Agent Provider',
      shortcutHint: 'Route',
      description:
          'Retry the failed Agent coding request with the same provider profile.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.failoverAgentProvider,
      label: 'Fail Over Agent Provider',
      shortcutHint: 'Route',
      description:
          'Replay the failed Agent coding request through another configured provider profile key.',
      requiresInput: true,
      inputLabel: 'Agent provider profile key',
    ),
    AppCommandDescriptor(
      id: AppCommandId.replayAgentPrompt,
      label: 'Replay Agent Prompt',
      shortcutHint: 'Route',
      description:
          'Replay the last failed or cancelled Agent coding prompt after the user confirms the recovered context.',
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
      id: AppCommandId.createWorkspaceFile,
      label: 'Create Workspace File',
      shortcutHint: 'Route',
      description:
          'Create a workspace file through the File Explorer operation contract.',
      requiresInput: true,
      inputLabel: 'New workspace file path',
    ),
    AppCommandDescriptor(
      id: AppCommandId.renameWorkspaceFile,
      label: 'Rename Workspace File',
      shortcutHint: 'Route',
      description:
          'Rename a workspace file through the File Explorer operation contract.',
      requiresInput: true,
      inputLabel: 'Current path -> next path',
    ),
    AppCommandDescriptor(
      id: AppCommandId.deleteWorkspaceFile,
      label: 'Delete Workspace File',
      shortcutHint: 'Route',
      description:
          'Delete a workspace file through the File Explorer operation contract.',
      requiresInput: true,
      inputLabel: 'Workspace file path',
    ),
    AppCommandDescriptor(
      id: AppCommandId.revealWorkspaceFile,
      label: 'Reveal Workspace File',
      shortcutHint: 'Route',
      description:
          'Reveal a workspace file in the File Explorer operation contract.',
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
      id: AppCommandId.previewWorkspaceReplace,
      label: 'Preview Workspace Replace',
      shortcutHint: 'Route',
      description:
          'Preview a workspace-wide replacement without modifying documents.',
      requiresInput: true,
      inputLabel: 'Search query -> replacement',
    ),
    AppCommandDescriptor(
      id: AppCommandId.applyWorkspaceReplace,
      label: 'Apply Workspace Replace',
      shortcutHint: 'Route',
      description:
          'Apply the latest workspace replace preview after it has been reviewed.',
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
      id: AppCommandId.rerunFailedTests,
      label: 'Rerun Failed Tests',
      shortcutHint: 'Route',
      description:
          'Rerun only the failed tests from the latest IDE test session.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.debugFailedTests,
      label: 'Debug Failed Tests',
      shortcutHint: 'Route',
      description:
          'Start the debug test route for failed tests from the latest IDE test session.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.runTestConfiguration,
      label: 'Run Test Configuration',
      shortcutHint: 'Route',
      description: 'Run an IDE test configuration by id.',
      requiresInput: true,
      inputLabel: 'Test configuration id',
    ),
    AppCommandDescriptor(
      id: AppCommandId.debugTestConfiguration,
      label: 'Debug Test Configuration',
      shortcutHint: 'Route',
      description: 'Start the debug route for an IDE test configuration by id.',
      requiresInput: true,
      inputLabel: 'Test configuration id',
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

  static Iterable<AppCommandDescriptor> commandsForCategory(
    AppCommandCategory category,
  ) {
    return commands.where((command) => command.category == category);
  }

  static Map<String, Object?> get contributionManifest {
    return <String, Object?>{
      'schema': 'vityo.command-contributions.v1',
      'categories': AppCommandCategory.values
          .map((category) => category.wireValue)
          .toList(growable: false),
      'commands': commands
          .map((command) => command.toContributionJson())
          .toList(growable: false),
    };
  }

  static Iterable<AppCommandDescriptor> get executionCommands =>
      commands.where((command) => command.id == AppCommandId.run);

  static Iterable<AppCommandDescriptor> get persistenceCommands =>
      commandsForCategory(AppCommandCategory.persistence);

  static Iterable<AppCommandDescriptor> get diagnosticCommands =>
      commandsForCategory(AppCommandCategory.diagnostics);

  static Iterable<AppCommandDescriptor> get languageServiceCommands =>
      commandsForCategory(AppCommandCategory.languageService);

  static Iterable<AppCommandDescriptor> get sourceControlCommands =>
      commandsForCategory(AppCommandCategory.sourceControl);

  static Iterable<AppCommandDescriptor> get agentCodingCommands =>
      commands.where(
        (command) =>
            command.category == AppCommandCategory.agentCoding ||
            command.id == AppCommandId.previewQuickFix,
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
      commandsForCategory(AppCommandCategory.navigation);

  static Iterable<AppCommandDescriptor> get workspaceFileCommands =>
      commandsForCategory(AppCommandCategory.workspace);

  static Iterable<AppCommandDescriptor> get refactorCommands => commands.where(
    (command) => command.category == AppCommandCategory.refactor,
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

  static Iterable<AppCommandDescriptor> get testingCommands =>
      commandsForCategory(AppCommandCategory.testing);

  static Iterable<AppCommandDescriptor> get dependencyCommands =>
      commandsForCategory(AppCommandCategory.dependency);

  static Iterable<AppCommandDescriptor> get toolchainCommands => commands.where(
    (command) => command.category == AppCommandCategory.toolchain,
  );

  static Iterable<AppCommandDescriptor> get settingsCommands => commands.where(
    (command) => command.category == AppCommandCategory.settings,
  );

  static Iterable<AppCommandDescriptor> get surfaceCommands =>
      commandsForCategory(AppCommandCategory.surface);

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

  static Iterable<AppCommandDescriptor> get moduleCommands =>
      commandsForCategory(AppCommandCategory.module);

  static AppCommandDescriptor descriptorFor(AppCommandId id) =>
      commands.firstWhere((command) => command.id == id);
}
