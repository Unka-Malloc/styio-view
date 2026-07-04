import '../workbench/context_key_service.dart';

enum AppCommandId {
  save,
  saveAll,
  openFile,
  reloadFile,
  acceptExternalChange,

  run,
  runSelectedTarget,
  runMinimalCompilableUnit,

  commandPalette,
  quickOpen,
  navigateBack,
  navigateForward,
  showRecentLocations,
  showWorkspaceDocumentLinks,
  showWorkspaceDocumentHighlights,
  showWorkspaceCodeLenses,
  goToWorkspaceDeclaration,
  goToWorkspaceDefinition,
  goToWorkspaceTypeDefinition,
  goToWorkspaceImplementation,
  showWorkspaceTypeHierarchy,
  showWorkspaceOutline,
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
  bootstrapStyioToolchain,
  executeToolchainInstallPlan,
  toggleVisualSubstitution,

  packProject,
  preparePublish,
  environmentPreflight,
  deployPreflight,

  showRuntime,
  showAgent,
  showDebug,

  openAgentPanelWithContext,
  previewAgentPatch,
  applyAgentPatch,
  rollbackLastWorkspaceEdit,

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
  applyFormattingEdit,
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

enum AppCommandPermissionRequirement {
  none,
  readOnly,
  workspaceWrite,
  toolchainManaged,
  network,
  destructive,
  openWorld,
  externalResource,
  fullAccess,
}

extension AppCommandPermissionRequirementX on AppCommandPermissionRequirement {
  String get wireValue {
    return switch (this) {
      AppCommandPermissionRequirement.none => 'none',
      AppCommandPermissionRequirement.readOnly => 'read-only',
      AppCommandPermissionRequirement.workspaceWrite => 'workspace-write',
      AppCommandPermissionRequirement.toolchainManaged => 'toolchain-managed',
      AppCommandPermissionRequirement.network => 'network',
      AppCommandPermissionRequirement.destructive => 'destructive',
      AppCommandPermissionRequirement.openWorld => 'open-world',
      AppCommandPermissionRequirement.externalResource => 'external-resource',
      AppCommandPermissionRequirement.fullAccess => 'full-access',
    };
  }
}

enum CommandPermissionDecision { allowed, requiresApproval, denied }

enum AppCommandSideEffect {
  none,
  readExternal,
  documentEdit,
  workspaceEdit,
  toolchainExecution,
  externalMutation,
}

extension AppCommandSideEffectX on AppCommandSideEffect {
  String get wireValue {
    return switch (this) {
      AppCommandSideEffect.none => 'none',
      AppCommandSideEffect.readExternal => 'read-external',
      AppCommandSideEffect.documentEdit => 'document-edit',
      AppCommandSideEffect.workspaceEdit => 'workspace-edit',
      AppCommandSideEffect.toolchainExecution => 'toolchain-execution',
      AppCommandSideEffect.externalMutation => 'external-mutation',
    };
  }
}

enum AppCommandTargetSurface {
  editor,
  commandOverlay,
  workspaceSidebar,
  bottomPanel,
  settingsPanel,
  statusBar,
  modalDialog,
  background,
}

extension AppCommandTargetSurfaceX on AppCommandTargetSurface {
  String get wireValue {
    return switch (this) {
      AppCommandTargetSurface.editor => 'editor',
      AppCommandTargetSurface.commandOverlay => 'command-overlay',
      AppCommandTargetSurface.workspaceSidebar => 'workspace-sidebar',
      AppCommandTargetSurface.bottomPanel => 'bottom-panel',
      AppCommandTargetSurface.settingsPanel => 'settings-panel',
      AppCommandTargetSurface.statusBar => 'status-bar',
      AppCommandTargetSurface.modalDialog => 'modal-dialog',
      AppCommandTargetSurface.background => 'background',
    };
  }
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
      AppCommandId.saveAll ||
      AppCommandId.openFile ||
      AppCommandId.reloadFile ||
      AppCommandId.acceptExternalChange => AppCommandCategory.persistence,
      AppCommandId.run ||
      AppCommandId.runSelectedTarget ||
      AppCommandId.runMinimalCompilableUnit => AppCommandCategory.execution,
      AppCommandId.fetchDependencies ||
      AppCommandId.vendorDependencies => AppCommandCategory.dependency,
      AppCommandId.useActiveCompiler ||
      AppCommandId.pinActiveCompiler ||
      AppCommandId.clearPinnedCompiler ||
      AppCommandId.bootstrapStyioToolchain ||
      AppCommandId.executeToolchainInstallPlan ||
      AppCommandId.selectClangCppVersion => AppCommandCategory.toolchain,
      AppCommandId.packProject ||
      AppCommandId.preparePublish ||
      AppCommandId.environmentPreflight ||
      AppCommandId.deployPreflight => AppCommandCategory.deployment,
      AppCommandId.showRuntime ||
      AppCommandId.showAgent ||
      AppCommandId.showDebug ||
      AppCommandId.commandPalette ||
      AppCommandId.quickOpen ||
      AppCommandId.navigateBack ||
      AppCommandId.navigateForward ||
      AppCommandId.showRecentLocations ||
      AppCommandId.showWorkspaceDocumentLinks ||
      AppCommandId.toggleVisualSubstitution => AppCommandCategory.surface,
      AppCommandId.nextDiagnostic ||
      AppCommandId.previousDiagnostic ||
      AppCommandId.applyQuickFix ||
      AppCommandId.applyFormattingEdit ||
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
      AppCommandId.replayAgentPrompt ||
      AppCommandId.openAgentPanelWithContext ||
      AppCommandId.previewAgentPatch ||
      AppCommandId.applyAgentPatch ||
      AppCommandId.rollbackLastWorkspaceEdit => AppCommandCategory.agentCoding,
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
      _ => AppCommandCategory.surface,
    };
  }
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key,
      'control': control,
      'meta': meta,
      'alt': alt,
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
    this.enablement = const <ContextKeyExpression>[],
    this.permissionRequirement = AppCommandPermissionRequirement.none,
    this.sideEffect,
    this.targetSurface,
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
  final List<ContextKeyExpression> enablement;
  final AppCommandPermissionRequirement permissionRequirement;
  final AppCommandSideEffect? sideEffect;
  final AppCommandTargetSurface? targetSurface;

  AppCommandCategory get category => id.category;

  AppCommandSideEffect get telemetrySideEffect {
    return sideEffect ?? _defaultSideEffectFor(permissionRequirement);
  }

  AppCommandTargetSurface get telemetryTargetSurface {
    return targetSurface ?? _defaultTargetSurfaceFor(category);
  }

  bool enabledIn(ContextKeyService contextKeys) {
    return contextKeys.matchesAll(enablement);
  }

  Map<String, Object?> toContributionJson() {
    return <String, Object?>{
      'id': id.name,
      'category': category.wireValue,
      'title': label,
      'label': label,
      'description': description,
      'shortcutHint': shortcutHint,
      'primary': primary,
      'requiresInput': requiresInput,
      'enablement': enablement
          .map((expression) => expression.toJson())
          .toList(growable: false),
      'permissionRequirement': permissionRequirement.wireValue,
      'telemetryClassification': <String, Object?>{
        'sideEffect': telemetrySideEffect.wireValue,
        'targetSurface': telemetryTargetSurface.wireValue,
        'permissionRequirement': permissionRequirement.wireValue,
      },
      if (inputLabel.isNotEmpty) 'inputLabel': inputLabel,
      if (inputContract.isNotEmpty) 'inputContract': inputContract,
      if (inputExamples.isNotEmpty) 'inputExamples': inputExamples,
      'keybindings': shortcuts
          .map((shortcut) => shortcut.toJson())
          .toList(growable: false),
      if (shortcuts.isNotEmpty)
        'shortcuts': shortcuts.map((shortcut) => shortcut.toJson()).toList(),
    };
  }
}

class IdeCommandRegistry {
  IdeCommandRegistry({Iterable<AppCommandDescriptor> descriptors = const []}) {
    for (final descriptor in descriptors) {
      register(descriptor);
    }
  }

  final Map<AppCommandId, AppCommandDescriptor> _descriptors =
      <AppCommandId, AppCommandDescriptor>{};

  List<AppCommandDescriptor> get commands =>
      List<AppCommandDescriptor>.unmodifiable(_descriptors.values);

  bool contains(AppCommandId id) => _descriptors.containsKey(id);

  AppCommandDescriptor descriptorFor(AppCommandId id) {
    final descriptor = _descriptors[id];
    if (descriptor == null) {
      throw StateError('Command `$id` is not registered.');
    }
    return descriptor;
  }

  void register(AppCommandDescriptor descriptor) {
    if (_descriptors.containsKey(descriptor.id)) {
      throw StateError('Command `${descriptor.id}` is already registered.');
    }
    _descriptors[descriptor.id] = descriptor;
  }

  bool unregister(AppCommandId id) {
    return _descriptors.remove(id) != null;
  }

  Iterable<AppCommandDescriptor> where(
    bool Function(AppCommandDescriptor command) test,
  ) {
    return _descriptors.values.where(test);
  }
}

class CommandPermissionPolicy {
  const CommandPermissionPolicy({
    this.allowedWithoutApproval = const <AppCommandPermissionRequirement>{
      AppCommandPermissionRequirement.none,
      AppCommandPermissionRequirement.readOnly,
    },
    this.denied = const <AppCommandPermissionRequirement>{
      AppCommandPermissionRequirement.fullAccess,
    },
  });

  final Set<AppCommandPermissionRequirement> allowedWithoutApproval;
  final Set<AppCommandPermissionRequirement> denied;
}

class CommandPermissionEvaluation {
  const CommandPermissionEvaluation({
    required this.decision,
    required this.reason,
  });

  final CommandPermissionDecision decision;
  final String reason;

  bool get isAllowed => decision == CommandPermissionDecision.allowed;
}

class CommandPermissionService {
  const CommandPermissionService({
    this.policy = const CommandPermissionPolicy(),
  });

  final CommandPermissionPolicy policy;

  CommandPermissionEvaluation evaluate(AppCommandDescriptor descriptor) {
    final requirement = descriptor.permissionRequirement;
    if (policy.denied.contains(requirement)) {
      return CommandPermissionEvaluation(
        decision: CommandPermissionDecision.denied,
        reason:
            '`${descriptor.label}` requires ${requirement.name}, which is disabled by policy.',
      );
    }
    if (policy.allowedWithoutApproval.contains(requirement)) {
      return CommandPermissionEvaluation(
        decision: CommandPermissionDecision.allowed,
        reason: '`${descriptor.label}` is allowed by command policy.',
      );
    }
    return CommandPermissionEvaluation(
      decision: CommandPermissionDecision.requiresApproval,
      reason:
          '`${descriptor.label}` requires ${requirement.name} approval before execution.',
    );
  }
}

AppCommandSideEffect _defaultSideEffectFor(
  AppCommandPermissionRequirement requirement,
) {
  return switch (requirement) {
    AppCommandPermissionRequirement.none => AppCommandSideEffect.none,
    AppCommandPermissionRequirement.readOnly =>
      AppCommandSideEffect.readExternal,
    AppCommandPermissionRequirement.workspaceWrite ||
    AppCommandPermissionRequirement.destructive =>
      AppCommandSideEffect.workspaceEdit,
    AppCommandPermissionRequirement.toolchainManaged =>
      AppCommandSideEffect.toolchainExecution,
    AppCommandPermissionRequirement.network ||
    AppCommandPermissionRequirement.openWorld ||
    AppCommandPermissionRequirement.externalResource ||
    AppCommandPermissionRequirement.fullAccess =>
      AppCommandSideEffect.externalMutation,
  };
}

AppCommandTargetSurface _defaultTargetSurfaceFor(AppCommandCategory category) {
  return switch (category) {
    AppCommandCategory.persistence => AppCommandTargetSurface.editor,
    AppCommandCategory.execution ||
    AppCommandCategory.testing ||
    AppCommandCategory.dependency ||
    AppCommandCategory.toolchain ||
    AppCommandCategory.deployment ||
    AppCommandCategory.diagnostics ||
    AppCommandCategory.languageService ||
    AppCommandCategory.sourceControl ||
    AppCommandCategory.debug ||
    AppCommandCategory.module => AppCommandTargetSurface.bottomPanel,
    AppCommandCategory.surface => AppCommandTargetSurface.commandOverlay,
    AppCommandCategory.agentCoding ||
    AppCommandCategory.workspace => AppCommandTargetSurface.workspaceSidebar,
    AppCommandCategory.navigation ||
    AppCommandCategory.refactor => AppCommandTargetSurface.editor,
    AppCommandCategory.settings => AppCommandTargetSurface.settingsPanel,
  };
}

class StyioCommandRegistry {
  static final IdeCommandRegistry defaultRegistry = IdeCommandRegistry(
    descriptors: commands,
  );

  static const List<AppCommandDescriptor> commands = [
    AppCommandDescriptor(
      id: AppCommandId.save,
      label: 'Save',
      shortcutHint: 'Cmd/Ctrl+S',
      description: 'Persist the current workspace target.',
      permissionRequirement: AppCommandPermissionRequirement.workspaceWrite,
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
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
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
      id: AppCommandId.navigateBack,
      label: 'Go Back',
      shortcutHint: 'Alt+Left',
      description: 'Return to the previous workspace navigation location.',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('arrowLeft', alt: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.navigateForward,
      label: 'Go Forward',
      shortcutHint: 'Alt+Right',
      description: 'Advance to the next workspace navigation location.',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('arrowRight', alt: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showRecentLocations,
      label: 'Recent Locations',
      shortcutHint: 'Cmd/Ctrl+Shift+E',
      description: 'Show recent workspace files, symbols, and cursor ranges.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyE', control: true, shift: true),
        AppCommandShortcutSpec('keyE', meta: true, shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceDocumentLinks,
      label: 'Document Links',
      shortcutHint: 'Route',
      description: 'Show navigable links in the active workspace document.',
      primary: true,
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceDocumentHighlights,
      label: 'Document Highlights',
      shortcutHint: 'Route',
      description: 'Show current-file highlights for the active symbol.',
      primary: true,
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceCodeLenses,
      label: 'Code Lens',
      shortcutHint: 'Route',
      description: 'Show symbol lenses for the active workspace document.',
      primary: true,
    ),
    AppCommandDescriptor(
      id: AppCommandId.goToWorkspaceDeclaration,
      label: 'Go to Declaration',
      shortcutHint: 'Ctrl+B',
      description: 'Open matching workspace declarations for a symbol.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyB', control: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.goToWorkspaceDefinition,
      label: 'Go to Definition',
      shortcutHint: 'F12',
      description: 'Open matching workspace definitions for a symbol.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[AppCommandShortcutSpec('f12')],
    ),
    AppCommandDescriptor(
      id: AppCommandId.goToWorkspaceTypeDefinition,
      label: 'Go to Type Definition',
      shortcutHint: 'Ctrl+Shift+B',
      description: 'Open matching workspace schema and state definitions.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyB', control: true, shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.goToWorkspaceImplementation,
      label: 'Go to Implementation',
      shortcutHint: 'Ctrl+F12',
      description: 'Open workspace schema and state implementors.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('f12', control: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceTypeHierarchy,
      label: 'Type Hierarchy',
      shortcutHint: 'Ctrl+H',
      description: 'Browse workspace schema and state type relationships.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyH', control: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceOutline,
      label: 'Outline',
      shortcutHint: 'Cmd/Ctrl+Shift+O',
      description: 'Show symbols and structure for the active workspace file.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyO', control: true, shift: true),
        AppCommandShortcutSpec('keyO', meta: true, shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.renameWorkspaceSymbol,
      label: 'Rename Symbol',
      shortcutHint: 'F2',
      description: 'Preview and apply a workspace symbol rename.',
      primary: true,
      shortcuts: <AppCommandShortcutSpec>[AppCommandShortcutSpec('f2')],
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
      description: 'Materialize dependency sources into the local pafio cache.',
      primary: true,
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
    ),
    AppCommandDescriptor(
      id: AppCommandId.vendorDependencies,
      label: 'Vendor',
      shortcutHint: 'Cmd/Ctrl+Shift+V',
      description: 'Materialize project-local vendored dependency snapshots.',
      primary: true,
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
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
          'Use the currently resolved compiler version as the managed pafio compiler.',
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
    ),
    AppCommandDescriptor(
      id: AppCommandId.pinActiveCompiler,
      label: 'Pin Compiler',
      shortcutHint: 'Route',
      description:
          'Pin the currently resolved compiler version into pafio-toolchain.toml.',
      permissionRequirement: AppCommandPermissionRequirement.workspaceWrite,
    ),
    AppCommandDescriptor(
      id: AppCommandId.clearPinnedCompiler,
      label: 'Clear Pin',
      shortcutHint: 'Route',
      description: 'Clear the current project toolchain pin.',
      permissionRequirement: AppCommandPermissionRequirement.workspaceWrite,
    ),
    AppCommandDescriptor(
      id: AppCommandId.bootstrapStyioToolchain,
      label: 'Bootstrap Styio',
      shortcutHint: 'Route',
      description:
          'Refresh and route the Styio toolchain bootstrap plan for this workspace.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.executeToolchainInstallPlan,
      label: 'Execute Toolchain Install',
      shortcutHint: 'Route',
      description:
          'Execute the last prepared IDE-managed toolchain installation plan.',
    ),
    AppCommandDescriptor(
      id: AppCommandId.selectClangCppVersion,
      label: 'Select Clang/C++',
      shortcutHint: 'Route',
      description:
          'Select the IDE-managed Clang/C++ compiler version and optional C++ standard.',
      requiresInput: true,
      inputLabel: 'Clang/C++ version id and optional C++ standard',
      inputContract: 'Use "versionId" or "versionId c++23".',
      inputExamples: <String>['native-clang-cpp-compiler', 'clang-18 c++23'],
    ),
    AppCommandDescriptor(
      id: AppCommandId.packProject,
      label: 'Pack',
      shortcutHint: 'Route',
      description: 'Create a package archive for the active project.',
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
    ),
    AppCommandDescriptor(
      id: AppCommandId.preparePublish,
      label: 'Preflight',
      shortcutHint: 'Route',
      description: 'Run publish preflight for the active project.',
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
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
      inputContract: 'Use an existing id from debug.threads.',
      inputExamples: <String>['1'],
    ),
    AppCommandDescriptor(
      id: AppCommandId.selectDebugStackFrame,
      label: 'Select Debug Stack Frame',
      shortcutHint: 'Route',
      description:
          'Select a paused DAP stack frame and refresh its local variables.',
      requiresInput: true,
      inputLabel: 'DAP stack frame id',
      inputContract: 'Use an existing id from debug.stackFrames.',
      inputExamples: <String>['frame-0'],
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
      inputContract: 'Workspace-relative changed file path.',
      inputExamples: <String>['src/main.styio'],
    ),
    AppCommandDescriptor(
      id: AppCommandId.stageSourceControl,
      label: 'Stage Source Control Paths',
      shortcutHint: 'Route',
      description:
          'Stage one or more changed workspace paths through the source-control action contract.',
      requiresInput: true,
      inputLabel: 'Changed file path(s)',
      inputContract:
          'One or more workspace-relative changed paths, separated by comma or newline.',
      inputExamples: <String>['src/main.styio', 'src/a.styio, src/b.styio'],
    ),
    AppCommandDescriptor(
      id: AppCommandId.unstageSourceControl,
      label: 'Unstage Source Control Paths',
      shortcutHint: 'Route',
      description:
          'Unstage one or more changed workspace paths through the source-control action contract.',
      requiresInput: true,
      inputLabel: 'Changed file path(s)',
      inputContract:
          'One or more staged workspace-relative paths, separated by comma or newline.',
      inputExamples: <String>['src/main.styio', 'src/a.styio, src/b.styio'],
    ),
    AppCommandDescriptor(
      id: AppCommandId.planSourceControlBranchSwitch,
      label: 'Plan Source Control Branch Switch',
      shortcutHint: 'Route',
      description:
          'Load branch facts and prepare a source-control branch switch plan without switching branches.',
      requiresInput: true,
      inputLabel: 'Target branch',
      inputContract:
          'Existing or candidate branch name from source-control facts.',
      inputExamples: <String>['ai-dev', 'nightly'],
    ),
    AppCommandDescriptor(
      id: AppCommandId.planSourceControlCommitDraft,
      label: 'Plan Source Control Commit Draft',
      shortcutHint: 'Route',
      description:
          'Prepare a source-control commit draft without creating a revision.',
      requiresInput: true,
      inputLabel: 'Commit message or message -> path(s)',
      inputContract:
          'Use "commit message" for all staged paths or "message -> path1, path2".',
      inputExamples: <String>[
        'Add Styio quick fix routing',
        'Add tests -> src/main.styio, test/main_test.dart',
      ],
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
      inputContract: 'Use a key from agent.savedProviderProfiles.',
      inputExamples: <String>['codex-spark', 'local-fallback'],
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
      inputContract:
          'Workspace-relative file path. Must not contain .. path segments.',
      inputExamples: <String>['src/main.styio'],
    ),
    AppCommandDescriptor(
      id: AppCommandId.createWorkspaceFile,
      label: 'Create Workspace File',
      shortcutHint: 'Route',
      description:
          'Create a workspace file through the File Explorer operation contract.',
      requiresInput: true,
      inputLabel: 'New workspace file path',
      inputContract:
          'Workspace-relative new file path. Must not contain .. path segments.',
      inputExamples: <String>['src/new_file.styio'],
    ),
    AppCommandDescriptor(
      id: AppCommandId.renameWorkspaceFile,
      label: 'Rename Workspace File',
      shortcutHint: 'Route',
      description:
          'Rename a workspace file through the File Explorer operation contract.',
      requiresInput: true,
      inputLabel: 'Current path -> next path',
      inputContract:
          'Use "current/path -> next/path" with workspace-relative paths.',
      inputExamples: <String>['src/old.styio -> src/new.styio'],
    ),
    AppCommandDescriptor(
      id: AppCommandId.deleteWorkspaceFile,
      label: 'Delete Workspace File',
      shortcutHint: 'Route',
      description:
          'Delete a workspace file through the File Explorer operation contract.',
      requiresInput: true,
      inputLabel: 'Workspace file path',
      inputContract:
          'Workspace-relative file path. Must not be the active document.',
      inputExamples: <String>['src/unused.styio'],
    ),
    AppCommandDescriptor(
      id: AppCommandId.revealWorkspaceFile,
      label: 'Reveal Workspace File',
      shortcutHint: 'Route',
      description:
          'Reveal a workspace file in the File Explorer operation contract.',
      requiresInput: true,
      inputLabel: 'Workspace file path',
      inputContract: 'Workspace-relative file path to reveal in the file tree.',
      inputExamples: <String>['src/main.styio'],
    ),
    AppCommandDescriptor(
      id: AppCommandId.previewWorkspaceReplace,
      label: 'Preview Workspace Replace',
      shortcutHint: 'Route',
      description:
          'Preview a workspace-wide replacement without modifying documents.',
      requiresInput: true,
      inputLabel: 'Search query -> replacement',
      inputContract: 'Use "search text -> replacement text".',
      inputExamples: <String>['oldName -> newName'],
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
      inputContract: 'Use an id from testing.configurationSet.configurations.',
      inputExamples: <String>['unit'],
    ),
    AppCommandDescriptor(
      id: AppCommandId.debugTestConfiguration,
      label: 'Debug Test Configuration',
      shortcutHint: 'Route',
      description: 'Start the debug route for an IDE test configuration by id.',
      requiresInput: true,
      inputLabel: 'Test configuration id',
      inputContract: 'Use an id from testing.configurationSet.configurations.',
      inputExamples: <String>['unit'],
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
      inputContract:
          'New symbol name valid for the active language syntax contract.',
      inputExamples: <String>['newName'],
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

  static Iterable<AppCommandDescriptor> get searchCommands => commands.where(
    (command) => switch (command.id) {
      AppCommandId.searchWorkspace ||
      AppCommandId.showRecentLocations ||
      AppCommandId.showWorkspaceCallHierarchy ||
      AppCommandId.showWorkspaceDocumentLinks ||
      AppCommandId.showWorkspaceDocumentHighlights ||
      AppCommandId.showWorkspaceCodeLenses ||
      AppCommandId.goToWorkspaceDeclaration ||
      AppCommandId.goToWorkspaceDefinition ||
      AppCommandId.goToWorkspaceTypeDefinition ||
      AppCommandId.goToWorkspaceImplementation ||
      AppCommandId.showWorkspaceTypeHierarchy ||
      AppCommandId.showWorkspaceOutline ||
      AppCommandId.findWorkspaceReferences ||
      AppCommandId.searchWorkspaceSymbols => true,
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
      AppCommandId.commandPalette ||
      AppCommandId.quickOpen ||
      AppCommandId.navigateBack ||
      AppCommandId.navigateForward ||
      AppCommandId.showRecentLocations ||
      AppCommandId.showWorkspaceDocumentLinks ||
      AppCommandId.showWorkspaceDocumentHighlights ||
      AppCommandId.showWorkspaceCodeLenses ||
      AppCommandId.goToWorkspaceDeclaration ||
      AppCommandId.goToWorkspaceDefinition ||
      AppCommandId.goToWorkspaceTypeDefinition ||
      AppCommandId.goToWorkspaceImplementation ||
      AppCommandId.showWorkspaceTypeHierarchy ||
      AppCommandId.showWorkspaceOutline ||
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
      AppCommandId.bootstrapStyioToolchain ||
      AppCommandId.executeToolchainInstallPlan ||
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

  static AppCommandDescriptor? descriptorForName(String name) {
    final normalized = name.trim();
    if (normalized.isEmpty) {
      return null;
    }
    for (final command in commands) {
      if (command.id.name == normalized) {
        return command;
      }
    }
    return null;
  }

  static bool isRegisteredName(String name) => descriptorForName(name) != null;

  static AppCommandDescriptor descriptorFor(AppCommandId id) =>
      defaultRegistry.descriptorFor(id);
}
