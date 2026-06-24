enum AppCommandId {
  // File operations
  save,
  openFile,
  reloadFile,
  acceptExternalChange,

  // Execution
  run,
  runSelectedTarget,
  runMinimalCompilableUnit,

  // Navigation & search
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

  // Diagnostics & code actions
  showWorkspaceProblems,
  showWorkspaceCodeActions,
  applyQuickFix,
  applyFormattingEdit,

  // Visual substitution
  toggleVisualSubstitution,

  // Dependencies & toolchain
  fetchDependencies,
  vendorDependencies,
  useActiveCompiler,
  pinActiveCompiler,
  clearPinnedCompiler,

  // Workflow
  packProject,
  preparePublish,
  environmentPreflight,
  deployPreflight,

  // Panels
  showRuntime,
  showAgent,
  showDebug,

  // Agent
  openAgentPanelWithContext,
  previewAgentPatch,
  applyAgentPatch,
  rollbackLastWorkspaceEdit,

  // Module & settings
  refreshModules,
  openSettings,
}

/// Side-effect level of a command.
enum AppCommandSideEffect {
  /// No side effects (e.g., navigation, search).
  none,

  /// Read-only access to external resources.
  readExternal,

  /// Modifies the in-memory document model (undoable).
  documentEdit,

  /// Modifies workspace files through transactions.
  workspaceEdit,

  /// Executes toolchain processes (compile, run, fetch, etc.).
  toolchainExecution,

  /// Modifies external resources (network, deployment).
  externalMutation,
}

/// The product surface a command targets.
enum AppCommandTargetSurface {
  /// Editor text area.
  editor,

  /// Command palette / overlay.
  commandOverlay,

  /// Sidebar / workspace explorer.
  workspaceSidebar,

  /// Bottom panels (runtime, agent, debug).
  bottomPanel,

  /// Settings / profile dialog.
  settingsPanel,

  /// Status bar.
  statusBar,

  /// Modal dialog.
  modalDialog,

  /// No specific surface — background operation.
  background,
}

enum AppCommandPermissionRequirement {
  none,
  readOnly,
  workspaceWrite,
  toolchainManaged,
  externalResource,
  fullAccess,
}

enum CommandPermissionDecision { allowed, requiresApproval, denied }

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
    this.category = 'General',
    this.primary = false,
    this.shortcuts = const <AppCommandShortcutSpec>[],
    this.permissionRequirement = AppCommandPermissionRequirement.none,
    this.sideEffect = AppCommandSideEffect.none,
    this.undoable = false,
    this.agentVisible = true,
    this.targetSurface = AppCommandTargetSurface.editor,
    this.auditLabel = '',
    this.capabilityRequirement,
  });

  /// Stable command identifier.
  final AppCommandId id;

  /// Human-readable label.
  final String label;

  /// Category for grouping (e.g., 'File', 'Navigation', 'Execution').
  final String category;

  /// Human-readable shortcut hint (e.g., 'Cmd/Ctrl+S').
  final String shortcutHint;

  /// One-line description of what the command does.
  final String description;

  /// Whether this is a primary (frequently-used) command.
  final bool primary;

  /// Platform-aware shortcut specifications.
  final List<AppCommandShortcutSpec> shortcuts;

  /// Minimum permission required to execute.
  final AppCommandPermissionRequirement permissionRequirement;

  /// The side-effect level of executing this command.
  final AppCommandSideEffect sideEffect;

  /// Whether the command's effects can be undone via the undo model.
  final bool undoable;

  /// Whether the command is visible to and executable by the Agent.
  /// Dangerous or agent-inappropriate commands should set this false.
  final bool agentVisible;

  /// The product surface this command primarily targets.
  final AppCommandTargetSurface targetSurface;

  /// Telemetry-free audit label — describes what is audited locally.
  /// Must not contain PII, paths, or runtime values.
  final String auditLabel;

  /// If non-null, the capability that must be present for this command
  /// to be enabled. When the capability is missing, the command is
  /// blocked with a structured reason.
  final String? capabilityRequirement;

  /// Returns a structured blocked reason if this command cannot currently
  /// execute due to a missing capability, or null if it can.
  String? blockedReasonForCapability(Iterable<String> missingCapabilities) {
    if (capabilityRequirement == null) {
      return null;
    }
    if (missingCapabilities.contains(capabilityRequirement)) {
      return 'Capability `$capabilityRequirement` is unavailable. '
          'Required for `${label}`.';
    }
    return null;
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

class CommandCapabilityState {
  const CommandCapabilityState({
    this.missingCapabilities = const <String>[],
    this.capabilityWarnings = const <String>[],
  });

  /// Capabilities that are confirmed missing — blocks commands that require them.
  final List<String> missingCapabilities;

  /// Capabilities with degraded status — warns but does not block.
  final List<String> capabilityWarnings;

  bool get hasBlockers => missingCapabilities.isNotEmpty;

  String? blockedReasonFor(AppCommandDescriptor descriptor) {
    return descriptor.blockedReasonForCapability(missingCapabilities);
  }

  /// Returns only commands that are not blocked by missing capabilities.
  List<AppCommandDescriptor> filterEnabled(
    Iterable<AppCommandDescriptor> commands,
  ) {
    return commands
        .where((c) => blockedReasonFor(c) == null)
        .toList(growable: false);
  }

  /// Returns commands that are safe for agent use:
  /// agent-visible, not blocked, and not fullAccess permission.
  List<AppCommandDescriptor> filterAgentVisible(
    Iterable<AppCommandDescriptor> commands,
  ) {
    return commands
        .where((c) =>
            c.agentVisible &&
            blockedReasonFor(c) == null &&
            c.permissionRequirement != AppCommandPermissionRequirement.fullAccess)
        .toList(growable: false);
  }
}

class StyioCommandRegistry {
  static final IdeCommandRegistry defaultRegistry = IdeCommandRegistry(
    descriptors: commands,
  );

  static const List<AppCommandDescriptor> commands = [
    // ── File ──────────────────────────────────────────────────────
    AppCommandDescriptor(
      id: AppCommandId.save,
      label: 'Save',
      category: 'File',
      shortcutHint: 'Cmd/Ctrl+S',
      description: 'Persist the current workspace target.',
      permissionRequirement: AppCommandPermissionRequirement.workspaceWrite,
      sideEffect: AppCommandSideEffect.workspaceEdit,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'save-document',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyS', control: true),
        AppCommandShortcutSpec('keyS', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.openFile,
      label: 'Open File',
      category: 'File',
      shortcutHint: 'Cmd/Ctrl+O',
      description: 'Open a workspace file.',
      sideEffect: AppCommandSideEffect.readExternal,
      undoable: false,
      agentVisible: false,
      targetSurface: AppCommandTargetSurface.commandOverlay,
      auditLabel: 'open-file',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyO', control: true),
        AppCommandShortcutSpec('keyO', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.reloadFile,
      label: 'Reload File',
      category: 'File',
      shortcutHint: 'Route',
      description: 'Reload the active file from disk.',
      sideEffect: AppCommandSideEffect.readExternal,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'reload-file',
    ),
    AppCommandDescriptor(
      id: AppCommandId.acceptExternalChange,
      label: 'Accept External Change',
      category: 'File',
      shortcutHint: 'Route',
      description: 'Accept an externally-modified file revision.',
      sideEffect: AppCommandSideEffect.documentEdit,
      undoable: true,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'accept-external-change',
    ),

    // ── Execution ─────────────────────────────────────────────────
    AppCommandDescriptor(
      id: AppCommandId.run,
      label: 'Run',
      category: 'Execution',
      shortcutHint: 'Cmd/Ctrl+Enter',
      description: 'Run the active minimal compilable unit.',
      primary: true,
      sideEffect: AppCommandSideEffect.toolchainExecution,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'run-compilable-unit',
      capabilityRequirement: 'execution.run',
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('enter', control: true),
        AppCommandShortcutSpec('enter', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.runSelectedTarget,
      label: 'Run Selected Target',
      category: 'Execution',
      shortcutHint: 'Route',
      description: 'Run the selected project target.',
      sideEffect: AppCommandSideEffect.toolchainExecution,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.workspaceSidebar,
      auditLabel: 'run-selected-target',
      capabilityRequirement: 'execution.run',
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
    ),
    AppCommandDescriptor(
      id: AppCommandId.runMinimalCompilableUnit,
      label: 'Run Minimal Compilable Unit',
      category: 'Execution',
      shortcutHint: 'Route',
      description: 'Identify and run the minimal compilable unit at cursor.',
      sideEffect: AppCommandSideEffect.toolchainExecution,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'run-mcu',
      capabilityRequirement: 'execution.run',
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
    ),

    // ── Navigation ────────────────────────────────────────────────
    AppCommandDescriptor(
      id: AppCommandId.commandPalette,
      label: 'Command Palette',
      category: 'Navigation',
      shortcutHint: 'Cmd/Ctrl+Shift+P',
      description: 'Search and run registered shell commands.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: false,
      targetSurface: AppCommandTargetSurface.commandOverlay,
      auditLabel: 'open-command-palette',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyP', control: true, shift: true),
        AppCommandShortcutSpec('keyP', meta: true, shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.quickOpen,
      label: 'Quick Open',
      category: 'Navigation',
      shortcutHint: 'Cmd/Ctrl+P',
      description: 'Open a workspace file by fuzzy name or path.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: false,
      targetSurface: AppCommandTargetSurface.commandOverlay,
      auditLabel: 'quick-open',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyP', control: true),
        AppCommandShortcutSpec('keyP', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.navigateBack,
      label: 'Go Back',
      category: 'Navigation',
      shortcutHint: 'Alt+Left',
      description: 'Return to the previous workspace navigation location.',
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: false,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'navigate-back',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('arrowLeft', alt: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.navigateForward,
      label: 'Go Forward',
      category: 'Navigation',
      shortcutHint: 'Alt+Right',
      description: 'Advance to the next workspace navigation location.',
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: false,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'navigate-forward',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('arrowRight', alt: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showRecentLocations,
      label: 'Recent Locations',
      category: 'Navigation',
      shortcutHint: 'Cmd/Ctrl+Shift+E',
      description: 'Show recent workspace files, symbols, and cursor ranges.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: false,
      targetSurface: AppCommandTargetSurface.commandOverlay,
      auditLabel: 'recent-locations',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyE', control: true, shift: true),
        AppCommandShortcutSpec('keyE', meta: true, shift: true),
      ],
    ),

    // ── Go-to ─────────────────────────────────────────────────────
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceDocumentLinks,
      label: 'Document Links',
      category: 'Navigation',
      shortcutHint: 'Route',
      description: 'Show navigable links in the active workspace document.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'document-links',
      capabilityRequirement: 'language.documentLinks',
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceDocumentHighlights,
      label: 'Document Highlights',
      category: 'Navigation',
      shortcutHint: 'Route',
      description: 'Show current-file highlights for the active symbol.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'document-highlights',
      capabilityRequirement: 'language.documentHighlights',
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceCodeLenses,
      label: 'Code Lens',
      category: 'Navigation',
      shortcutHint: 'Route',
      description: 'Show symbol lenses for the active workspace document.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'code-lens',
      capabilityRequirement: 'language.codeLens',
    ),
    AppCommandDescriptor(
      id: AppCommandId.goToWorkspaceDeclaration,
      label: 'Go to Declaration',
      category: 'Navigation',
      shortcutHint: 'Ctrl+B',
      description: 'Open matching workspace declarations for a symbol.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'go-to-declaration',
      capabilityRequirement: 'language.declaration',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyB', control: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.goToWorkspaceDefinition,
      label: 'Go to Definition',
      category: 'Navigation',
      shortcutHint: 'F12',
      description: 'Open matching workspace definitions for a symbol.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'go-to-definition',
      capabilityRequirement: 'language.definition',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('f12'),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.goToWorkspaceTypeDefinition,
      label: 'Go to Type Definition',
      category: 'Navigation',
      shortcutHint: 'Ctrl+Shift+B',
      description: 'Open matching workspace schema and state definitions.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'go-to-type-definition',
      capabilityRequirement: 'language.typeDefinition',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyB', control: true, shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.goToWorkspaceImplementation,
      label: 'Go to Implementation',
      category: 'Navigation',
      shortcutHint: 'Ctrl+F12',
      description: 'Open workspace schema and state implementors.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'go-to-implementation',
      capabilityRequirement: 'language.implementation',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('f12', control: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceTypeHierarchy,
      label: 'Type Hierarchy',
      category: 'Navigation',
      shortcutHint: 'Ctrl+H',
      description: 'Browse workspace schema and state type relationships.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.workspaceSidebar,
      auditLabel: 'type-hierarchy',
      capabilityRequirement: 'language.typeHierarchy',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyH', control: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceOutline,
      label: 'Outline',
      category: 'Navigation',
      shortcutHint: 'Cmd/Ctrl+Shift+O',
      description: 'Show symbols and structure for the active workspace file.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.workspaceSidebar,
      auditLabel: 'outline',
      capabilityRequirement: 'language.documentSymbols',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyO', control: true, shift: true),
        AppCommandShortcutSpec('keyO', meta: true, shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.renameWorkspaceSymbol,
      label: 'Rename Symbol',
      category: 'Refactor',
      shortcutHint: 'F2',
      description: 'Preview and apply a workspace symbol rename.',
      primary: true,
      sideEffect: AppCommandSideEffect.workspaceEdit,
      undoable: true,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'rename-symbol',
      capabilityRequirement: 'language.rename',
      permissionRequirement: AppCommandPermissionRequirement.workspaceWrite,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('f2'),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.searchWorkspaceSymbols,
      label: 'Symbols',
      category: 'Navigation',
      shortcutHint: 'Cmd/Ctrl+T',
      description: 'Search symbols across workspace files.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.commandOverlay,
      auditLabel: 'search-symbols',
      capabilityRequirement: 'language.workspaceSymbols',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyT', control: true),
        AppCommandShortcutSpec('keyT', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.findWorkspaceReferences,
      label: 'Find Usages',
      category: 'Navigation',
      shortcutHint: 'Shift+F12',
      description: 'Find project-wide usages of a workspace symbol.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.workspaceSidebar,
      auditLabel: 'find-usages',
      capabilityRequirement: 'language.references',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('f12', shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceCallHierarchy,
      label: 'Call Hierarchy',
      category: 'Navigation',
      shortcutHint: 'Ctrl+Alt+H',
      description:
          'Browse incoming and outgoing calls for a workspace symbol.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.workspaceSidebar,
      auditLabel: 'call-hierarchy',
      capabilityRequirement: 'language.callHierarchy',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyH', control: true, alt: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.searchWorkspace,
      label: 'Find in Files',
      category: 'Navigation',
      shortcutHint: 'Cmd/Ctrl+Shift+F',
      description: 'Search text across the current workspace files.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.workspaceSidebar,
      auditLabel: 'find-in-files',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyF', control: true, shift: true),
        AppCommandShortcutSpec('keyF', meta: true, shift: true),
      ],
    ),

    // ── Diagnostics ───────────────────────────────────────────────
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceProblems,
      label: 'Problems',
      category: 'Diagnostics',
      shortcutHint: 'Route',
      description: 'Show workspace diagnostics across project files.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.bottomPanel,
      auditLabel: 'show-problems',
    ),
    AppCommandDescriptor(
      id: AppCommandId.showWorkspaceCodeActions,
      label: 'Code Actions',
      category: 'Diagnostics',
      shortcutHint: 'Cmd/Ctrl+.',
      description:
          'Preview and apply workspace quick fixes and source actions.',
      primary: true,
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'code-actions',
      capabilityRequirement: 'language.codeActions',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('period', control: true),
        AppCommandShortcutSpec('period', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.applyQuickFix,
      label: 'Apply Quick Fix',
      category: 'Diagnostics',
      shortcutHint: 'Route',
      description: 'Apply the selected quick fix via workspace edit transaction.',
      sideEffect: AppCommandSideEffect.workspaceEdit,
      undoable: true,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'apply-quick-fix',
      capabilityRequirement: 'language.codeActions',
      permissionRequirement: AppCommandPermissionRequirement.workspaceWrite,
    ),
    AppCommandDescriptor(
      id: AppCommandId.applyFormattingEdit,
      label: 'Apply Formatting',
      category: 'Diagnostics',
      shortcutHint: 'Route',
      description:
          'Apply formatting edits via workspace edit transaction.',
      sideEffect: AppCommandSideEffect.workspaceEdit,
      undoable: true,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'apply-formatting',
      capabilityRequirement: 'language.formatting',
      permissionRequirement: AppCommandPermissionRequirement.workspaceWrite,
    ),

    // ── Visual Substitution ───────────────────────────────────────
    AppCommandDescriptor(
      id: AppCommandId.toggleVisualSubstitution,
      label: 'Toggle Visual Substitution',
      category: 'View',
      shortcutHint: 'Route',
      description:
          'Toggle Styio visual substitution glyphs on or off. '
          'Does not modify the Source Buffer.',
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.editor,
      auditLabel: 'toggle-visual-substitution',
    ),

    // ── Dependencies ─────────────────────────────────────────────
    AppCommandDescriptor(
      id: AppCommandId.fetchDependencies,
      label: 'Fetch',
      category: 'Dependencies',
      shortcutHint: 'Route',
      description:
          'Materialize dependency sources into the local spio cache.',
      primary: true,
      sideEffect: AppCommandSideEffect.toolchainExecution,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.background,
      auditLabel: 'fetch-dependencies',
      capabilityRequirement: 'dependency.fetch',
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
    ),
    AppCommandDescriptor(
      id: AppCommandId.vendorDependencies,
      label: 'Vendor',
      category: 'Dependencies',
      shortcutHint: 'Cmd/Ctrl+Shift+V',
      description:
          'Materialize project-local vendored dependency snapshots.',
      primary: true,
      sideEffect: AppCommandSideEffect.workspaceEdit,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.background,
      auditLabel: 'vendor-dependencies',
      capabilityRequirement: 'dependency.vendor',
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyV', control: true, shift: true),
        AppCommandShortcutSpec('keyV', meta: true, shift: true),
      ],
    ),

    // ── Toolchain ─────────────────────────────────────────────────
    AppCommandDescriptor(
      id: AppCommandId.useActiveCompiler,
      label: 'Use Compiler',
      category: 'Toolchain',
      shortcutHint: 'Route',
      description:
          'Use the currently resolved compiler as the managed spio compiler.',
      sideEffect: AppCommandSideEffect.toolchainExecution,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.background,
      auditLabel: 'use-compiler',
      capabilityRequirement: 'toolchain.select',
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
    ),
    AppCommandDescriptor(
      id: AppCommandId.pinActiveCompiler,
      label: 'Pin Compiler',
      category: 'Toolchain',
      shortcutHint: 'Route',
      description:
          'Pin the currently resolved compiler version into spio-toolchain.toml.',
      sideEffect: AppCommandSideEffect.workspaceEdit,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.background,
      auditLabel: 'pin-compiler',
      capabilityRequirement: 'toolchain.pin',
      permissionRequirement: AppCommandPermissionRequirement.workspaceWrite,
    ),
    AppCommandDescriptor(
      id: AppCommandId.clearPinnedCompiler,
      label: 'Clear Pin',
      category: 'Toolchain',
      shortcutHint: 'Route',
      description: 'Clear the current project toolchain pin.',
      sideEffect: AppCommandSideEffect.workspaceEdit,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.background,
      auditLabel: 'clear-pin',
      permissionRequirement: AppCommandPermissionRequirement.workspaceWrite,
    ),

    // ── Workflow ──────────────────────────────────────────────────
    AppCommandDescriptor(
      id: AppCommandId.packProject,
      label: 'Pack',
      category: 'Workflow',
      shortcutHint: 'Route',
      description: 'Create a package archive for the active project.',
      sideEffect: AppCommandSideEffect.toolchainExecution,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.background,
      auditLabel: 'pack-project',
      capabilityRequirement: 'deployment.pack',
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
    ),
    AppCommandDescriptor(
      id: AppCommandId.preparePublish,
      label: 'Preflight',
      category: 'Workflow',
      shortcutHint: 'Route',
      description: 'Run publish preflight for the active project.',
      sideEffect: AppCommandSideEffect.toolchainExecution,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.background,
      auditLabel: 'publish-preflight',
      capabilityRequirement: 'deployment.publish',
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
    ),
    AppCommandDescriptor(
      id: AppCommandId.environmentPreflight,
      label: 'Environment Preflight',
      category: 'Workflow',
      shortcutHint: 'Route',
      description:
          'Validate the local environment for Styio development '
          '(toolchain, paths, permissions).',
      sideEffect: AppCommandSideEffect.readExternal,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.background,
      auditLabel: 'environment-preflight',
      capabilityRequirement: 'environment.preflight',
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
    ),
    AppCommandDescriptor(
      id: AppCommandId.deployPreflight,
      label: 'Deploy Preflight',
      category: 'Workflow',
      shortcutHint: 'Route',
      description: 'Validate deployment readiness for the active project.',
      sideEffect: AppCommandSideEffect.readExternal,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.background,
      auditLabel: 'deploy-preflight',
      capabilityRequirement: 'deployment.preflight',
      permissionRequirement: AppCommandPermissionRequirement.toolchainManaged,
    ),

    // ── Panels ────────────────────────────────────────────────────
    AppCommandDescriptor(
      id: AppCommandId.showRuntime,
      label: 'Runtime',
      category: 'View',
      shortcutHint: 'Shift+1',
      description: 'Focus the runtime surface.',
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.bottomPanel,
      auditLabel: 'show-runtime',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('digit1', shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showAgent,
      label: 'Agent',
      category: 'View',
      shortcutHint: 'Shift+2',
      description: 'Focus the agent surface.',
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: false,
      targetSurface: AppCommandTargetSurface.bottomPanel,
      auditLabel: 'show-agent',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('digit2', shift: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.showDebug,
      label: 'Debug',
      category: 'View',
      shortcutHint: 'Shift+3',
      description: 'Focus the debug console.',
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.bottomPanel,
      auditLabel: 'show-debug',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('digit3', shift: true),
      ],
    ),

    // ── Agent ─────────────────────────────────────────────────────
    AppCommandDescriptor(
      id: AppCommandId.openAgentPanelWithContext,
      label: 'Open Agent Panel with Context',
      category: 'Agent',
      shortcutHint: 'Route',
      description:
          'Open the agent panel pre-loaded with current workspace, '
          'document, selection, diagnostics, project graph, and '
          'runtime event context.',
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: false,
      targetSurface: AppCommandTargetSurface.bottomPanel,
      auditLabel: 'open-agent-with-context',
    ),
    AppCommandDescriptor(
      id: AppCommandId.previewAgentPatch,
      label: 'Preview Agent Patch',
      category: 'Agent',
      shortcutHint: 'Route',
      description:
          'Preview file changes proposed by the agent. '
          'Does not modify any documents.',
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.modalDialog,
      auditLabel: 'preview-agent-patch',
      permissionRequirement: AppCommandPermissionRequirement.readOnly,
    ),
    AppCommandDescriptor(
      id: AppCommandId.applyAgentPatch,
      label: 'Apply Agent Patch',
      category: 'Agent',
      shortcutHint: 'Route',
      description:
          'Apply the previewed agent patch via workspace edit transaction. '
          'Can be undone with Rollback.',
      sideEffect: AppCommandSideEffect.workspaceEdit,
      undoable: true,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.background,
      auditLabel: 'apply-agent-patch',
      permissionRequirement: AppCommandPermissionRequirement.workspaceWrite,
    ),
    AppCommandDescriptor(
      id: AppCommandId.rollbackLastWorkspaceEdit,
      label: 'Rollback Last Workspace Edit',
      category: 'Agent',
      shortcutHint: 'Route',
      description:
          'Rollback the most recent workspace edit applied by the agent.',
      sideEffect: AppCommandSideEffect.workspaceEdit,
      undoable: true,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.background,
      auditLabel: 'rollback-workspace-edit',
      permissionRequirement: AppCommandPermissionRequirement.workspaceWrite,
    ),

    // ── Module & Settings ─────────────────────────────────────────
    AppCommandDescriptor(
      id: AppCommandId.refreshModules,
      label: 'Refresh',
      category: 'Module',
      shortcutHint: 'Cmd/Ctrl+R',
      description:
          'Refresh module host state, project graph, and toolchain contracts.',
      primary: true,
      sideEffect: AppCommandSideEffect.readExternal,
      undoable: false,
      agentVisible: true,
      targetSurface: AppCommandTargetSurface.background,
      auditLabel: 'refresh-modules',
      shortcuts: <AppCommandShortcutSpec>[
        AppCommandShortcutSpec('keyR', control: true),
        AppCommandShortcutSpec('keyR', meta: true),
      ],
    ),
    AppCommandDescriptor(
      id: AppCommandId.openSettings,
      label: 'Settings',
      category: 'Settings',
      shortcutHint: 'Cmd/Ctrl+,',
      description: 'Open settings and profile routes.',
      sideEffect: AppCommandSideEffect.none,
      undoable: false,
      agentVisible: false,
      targetSurface: AppCommandTargetSurface.settingsPanel,
      auditLabel: 'open-settings',
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
      commands.where(
        (command) => switch (command.id) {
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
      defaultRegistry.descriptorFor(id);
}
