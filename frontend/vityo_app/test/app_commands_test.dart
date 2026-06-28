import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/app/commands/app_commands.dart';

void main() {
  test('command registry exposes primary command strip in mainline order', () {
    expect(
      StyioCommandRegistry.primaryCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.save,
        AppCommandId.saveAll,
        AppCommandId.run,
        AppCommandId.commandPalette,
        AppCommandId.quickOpen,
        AppCommandId.showRecentLocations,
        AppCommandId.showWorkspaceDocumentLinks,
        AppCommandId.showWorkspaceDocumentHighlights,
        AppCommandId.showWorkspaceCodeLenses,
        AppCommandId.goToWorkspaceDeclaration,
        AppCommandId.goToWorkspaceDefinition,
        AppCommandId.goToWorkspaceTypeDefinition,
        AppCommandId.goToWorkspaceImplementation,
        AppCommandId.showWorkspaceTypeHierarchy,
        AppCommandId.showWorkspaceOutline,
        AppCommandId.renameWorkspaceSymbol,
        AppCommandId.searchWorkspaceSymbols,
        AppCommandId.findWorkspaceReferences,
        AppCommandId.showWorkspaceCallHierarchy,
        AppCommandId.searchWorkspace,
        AppCommandId.showWorkspaceProblems,
        AppCommandId.showWorkspaceCodeActions,
        AppCommandId.fetchDependencies,
        AppCommandId.vendorDependencies,
        AppCommandId.refreshModules,
      ],
    );
  });

  test(
    'command registry resolves descriptors and shortcuts for navigation and source ops',
    () {
      final quickOpen = StyioCommandRegistry.descriptorFor(
        AppCommandId.quickOpen,
      );
      final commandPalette = StyioCommandRegistry.descriptorFor(
        AppCommandId.commandPalette,
      );
      final search = StyioCommandRegistry.descriptorFor(
        AppCommandId.searchWorkspace,
      );
      final recentLocations = StyioCommandRegistry.descriptorFor(
        AppCommandId.showRecentLocations,
      );
      final documentLinks = StyioCommandRegistry.descriptorFor(
        AppCommandId.showWorkspaceDocumentLinks,
      );
      final documentHighlights = StyioCommandRegistry.descriptorFor(
        AppCommandId.showWorkspaceDocumentHighlights,
      );
      final codeLens = StyioCommandRegistry.descriptorFor(
        AppCommandId.showWorkspaceCodeLenses,
      );
      final declaration = StyioCommandRegistry.descriptorFor(
        AppCommandId.goToWorkspaceDeclaration,
      );
      final navigateBack = StyioCommandRegistry.descriptorFor(
        AppCommandId.navigateBack,
      );
      final navigateForward = StyioCommandRegistry.descriptorFor(
        AppCommandId.navigateForward,
      );
      final definition = StyioCommandRegistry.descriptorFor(
        AppCommandId.goToWorkspaceDefinition,
      );
      final typeDefinition = StyioCommandRegistry.descriptorFor(
        AppCommandId.goToWorkspaceTypeDefinition,
      );
      final implementation = StyioCommandRegistry.descriptorFor(
        AppCommandId.goToWorkspaceImplementation,
      );
      final typeHierarchy = StyioCommandRegistry.descriptorFor(
        AppCommandId.showWorkspaceTypeHierarchy,
      );
      final outline = StyioCommandRegistry.descriptorFor(
        AppCommandId.showWorkspaceOutline,
      );
      final rename = StyioCommandRegistry.descriptorFor(
        AppCommandId.renameWorkspaceSymbol,
      );
      final problems = StyioCommandRegistry.descriptorFor(
        AppCommandId.showWorkspaceProblems,
      );
      final codeActions = StyioCommandRegistry.descriptorFor(
        AppCommandId.showWorkspaceCodeActions,
      );
      final symbols = StyioCommandRegistry.descriptorFor(
        AppCommandId.searchWorkspaceSymbols,
      );
      final references = StyioCommandRegistry.descriptorFor(
        AppCommandId.findWorkspaceReferences,
      );
      final callHierarchy = StyioCommandRegistry.descriptorFor(
        AppCommandId.showWorkspaceCallHierarchy,
      );
      final fetch = StyioCommandRegistry.descriptorFor(
        AppCommandId.fetchDependencies,
      );
      final vendor = StyioCommandRegistry.descriptorFor(
        AppCommandId.vendorDependencies,
      );

      expect(quickOpen.label, 'Quick Open');
      expect(quickOpen.shortcutHint, 'Cmd/Ctrl+P');
      expect(quickOpen.primary, isTrue);
      expect(quickOpen.shortcuts, hasLength(2));

      expect(commandPalette.label, 'Command Palette');
      expect(commandPalette.shortcutHint, 'Cmd/Ctrl+Shift+P');
      expect(commandPalette.primary, isTrue);
      expect(commandPalette.shortcuts, hasLength(2));

      expect(search.label, 'Find in Files');
      expect(search.shortcutHint, 'Cmd/Ctrl+Shift+F');
      expect(search.primary, isTrue);
      expect(search.shortcuts, hasLength(2));

      expect(recentLocations.label, 'Recent Locations');
      expect(recentLocations.shortcutHint, 'Cmd/Ctrl+Shift+E');
      expect(recentLocations.primary, isTrue);
      expect(recentLocations.shortcuts, hasLength(2));

      expect(documentLinks.label, 'Document Links');
      expect(documentLinks.shortcutHint, 'Route');
      expect(documentLinks.primary, isTrue);
      expect(documentLinks.shortcuts, isEmpty);

      expect(documentHighlights.label, 'Document Highlights');
      expect(documentHighlights.shortcutHint, 'Route');
      expect(documentHighlights.primary, isTrue);
      expect(documentHighlights.shortcuts, isEmpty);

      expect(codeLens.label, 'Code Lens');
      expect(codeLens.shortcutHint, 'Route');
      expect(codeLens.primary, isTrue);
      expect(codeLens.shortcuts, isEmpty);

      expect(declaration.label, 'Go to Declaration');
      expect(declaration.shortcutHint, 'Ctrl+B');
      expect(declaration.primary, isTrue);
      expect(declaration.shortcuts, hasLength(1));

      expect(navigateBack.label, 'Go Back');
      expect(navigateBack.shortcutHint, 'Alt+Left');
      expect(navigateBack.primary, isFalse);
      expect(navigateBack.shortcuts, hasLength(1));

      expect(navigateForward.label, 'Go Forward');
      expect(navigateForward.shortcutHint, 'Alt+Right');
      expect(navigateForward.primary, isFalse);
      expect(navigateForward.shortcuts, hasLength(1));

      expect(definition.label, 'Go to Definition');
      expect(definition.shortcutHint, 'F12');
      expect(definition.primary, isTrue);
      expect(definition.shortcuts, hasLength(1));

      expect(typeDefinition.label, 'Go to Type Definition');
      expect(typeDefinition.shortcutHint, 'Ctrl+Shift+B');
      expect(typeDefinition.primary, isTrue);
      expect(typeDefinition.shortcuts, hasLength(1));

      expect(implementation.label, 'Go to Implementation');
      expect(implementation.shortcutHint, 'Ctrl+F12');
      expect(implementation.primary, isTrue);
      expect(implementation.shortcuts, hasLength(1));

      expect(typeHierarchy.label, 'Type Hierarchy');
      expect(typeHierarchy.shortcutHint, 'Ctrl+H');
      expect(typeHierarchy.primary, isTrue);
      expect(typeHierarchy.shortcuts, hasLength(1));

      expect(outline.label, 'Outline');
      expect(outline.shortcutHint, 'Cmd/Ctrl+Shift+O');
      expect(outline.primary, isTrue);
      expect(outline.shortcuts, hasLength(2));

      expect(rename.label, 'Rename Symbol');
      expect(rename.shortcutHint, 'F2');
      expect(rename.primary, isTrue);
      expect(rename.shortcuts, hasLength(1));

      expect(problems.label, 'Problems');
      expect(problems.shortcutHint, 'Route');
      expect(problems.primary, isTrue);
      expect(problems.shortcuts, isEmpty);

      expect(codeActions.label, 'Code Actions');
      expect(codeActions.shortcutHint, 'Cmd/Ctrl+.');
      expect(codeActions.primary, isTrue);
      expect(codeActions.shortcuts, hasLength(2));

      expect(symbols.label, 'Symbols');
      expect(symbols.shortcutHint, 'Cmd/Ctrl+T');
      expect(symbols.primary, isTrue);
      expect(symbols.shortcuts, hasLength(2));

      expect(references.label, 'Find Usages');
      expect(references.shortcutHint, 'Shift+F12');
      expect(references.primary, isTrue);
      expect(references.shortcuts, hasLength(1));

      expect(callHierarchy.label, 'Call Hierarchy');
      expect(callHierarchy.shortcutHint, 'Ctrl+Alt+H');
      expect(callHierarchy.primary, isTrue);
      expect(callHierarchy.shortcuts, hasLength(1));

      expect(fetch.label, 'Fetch');
      expect(fetch.shortcutHint, 'Route');
      expect(fetch.primary, isTrue);
      expect(fetch.shortcuts, isEmpty);

      expect(vendor.label, 'Vendor');
      expect(vendor.shortcutHint, 'Cmd/Ctrl+Shift+V');
      expect(vendor.primary, isTrue);
      expect(vendor.shortcuts, hasLength(2));
    },
  );

  test('command registry exposes toolchain and deployment route commands', () {
    expect(
      StyioCommandRegistry.executionCommands.map((command) => command.id),
      <AppCommandId>[AppCommandId.run],
    );
    expect(
      StyioCommandRegistry.searchCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.showRecentLocations,
        AppCommandId.showWorkspaceDocumentLinks,
        AppCommandId.showWorkspaceDocumentHighlights,
        AppCommandId.showWorkspaceCodeLenses,
        AppCommandId.goToWorkspaceDeclaration,
        AppCommandId.goToWorkspaceDefinition,
        AppCommandId.goToWorkspaceTypeDefinition,
        AppCommandId.goToWorkspaceImplementation,
        AppCommandId.showWorkspaceTypeHierarchy,
        AppCommandId.showWorkspaceOutline,
        AppCommandId.searchWorkspaceSymbols,
        AppCommandId.findWorkspaceReferences,
        AppCommandId.showWorkspaceCallHierarchy,
        AppCommandId.searchWorkspace,
      ],
    );
    expect(
      StyioCommandRegistry.navigationCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.searchWorkspace,
        AppCommandId.goToDefinition,
        AppCommandId.openWorkspaceFile,
        AppCommandId.previewWorkspaceReplace,
        AppCommandId.applyWorkspaceReplace,
        AppCommandId.nextReference,
        AppCommandId.previousReference,
      ],
    );
    expect(
      StyioCommandRegistry.dependencyCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.fetchDependencies,
        AppCommandId.vendorDependencies,
      ],
    );
    expect(
      StyioCommandRegistry.toolchainCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.useActiveCompiler,
        AppCommandId.pinActiveCompiler,
        AppCommandId.clearPinnedCompiler,
        AppCommandId.bootstrapStyioToolchain,
        AppCommandId.executeToolchainInstallPlan,
        AppCommandId.selectClangCppVersion,
      ],
    );
    expect(
      StyioCommandRegistry.deploymentCommands.map((command) => command.id),
      <AppCommandId>[AppCommandId.packProject, AppCommandId.preparePublish],
    );
    expect(
      StyioCommandRegistry.workflowCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.run,
        AppCommandId.commandPalette,
        AppCommandId.quickOpen,
        AppCommandId.navigateBack,
        AppCommandId.navigateForward,
        AppCommandId.showRecentLocations,
        AppCommandId.showWorkspaceDocumentLinks,
        AppCommandId.showWorkspaceDocumentHighlights,
        AppCommandId.showWorkspaceCodeLenses,
        AppCommandId.goToWorkspaceDeclaration,
        AppCommandId.goToWorkspaceDefinition,
        AppCommandId.goToWorkspaceTypeDefinition,
        AppCommandId.goToWorkspaceImplementation,
        AppCommandId.showWorkspaceTypeHierarchy,
        AppCommandId.showWorkspaceOutline,
        AppCommandId.renameWorkspaceSymbol,
        AppCommandId.searchWorkspaceSymbols,
        AppCommandId.findWorkspaceReferences,
        AppCommandId.showWorkspaceCallHierarchy,
        AppCommandId.searchWorkspace,
        AppCommandId.showWorkspaceProblems,
        AppCommandId.showWorkspaceCodeActions,
        AppCommandId.fetchDependencies,
        AppCommandId.vendorDependencies,
        AppCommandId.useActiveCompiler,
        AppCommandId.pinActiveCompiler,
        AppCommandId.clearPinnedCompiler,
        AppCommandId.bootstrapStyioToolchain,
        AppCommandId.executeToolchainInstallPlan,
        AppCommandId.selectClangCppVersion,
        AppCommandId.packProject,
        AppCommandId.preparePublish,
      ],
    );

    expect(
      StyioCommandRegistry.descriptorFor(AppCommandId.useActiveCompiler).label,
      'Use Compiler',
    );
    expect(
      StyioCommandRegistry.descriptorFor(AppCommandId.preparePublish).label,
      'Preflight',
    );
  });

  test('render shortcut adapter exposes command intents', () {
    final intents = AppCommandShortcutRegistry.shortcutIntents.values
        .whereType<AppCommandIntent>()
        .map((intent) => intent.commandId)
        .toSet();

    expect(intents, contains(AppCommandId.run));
    expect(intents, contains(AppCommandId.commandPalette));
    expect(intents, contains(AppCommandId.quickOpen));
    expect(intents, contains(AppCommandId.navigateBack));
    expect(intents, contains(AppCommandId.navigateForward));
    expect(intents, contains(AppCommandId.showRecentLocations));
    expect(intents, contains(AppCommandId.goToWorkspaceDeclaration));
    expect(intents, contains(AppCommandId.goToWorkspaceDefinition));
    expect(intents, contains(AppCommandId.goToWorkspaceTypeDefinition));
    expect(intents, contains(AppCommandId.goToWorkspaceImplementation));
    expect(intents, contains(AppCommandId.showWorkspaceTypeHierarchy));
    expect(intents, contains(AppCommandId.showWorkspaceOutline));
    expect(intents, contains(AppCommandId.renameWorkspaceSymbol));
    expect(intents, contains(AppCommandId.searchWorkspaceSymbols));
    expect(intents, contains(AppCommandId.findWorkspaceReferences));
    expect(intents, contains(AppCommandId.showWorkspaceCallHierarchy));
    expect(intents, contains(AppCommandId.searchWorkspace));
    expect(intents, contains(AppCommandId.showWorkspaceCodeActions));
    expect(intents, contains(AppCommandId.save));
    expect(intents, contains(AppCommandId.refreshModules));
  });

  test('ide command registry supports dynamic registration boundaries', () {
    final registry = IdeCommandRegistry();
    const descriptor = AppCommandDescriptor(
      id: AppCommandId.showRuntime,
      label: 'Runtime',
      shortcutHint: 'Route',
      description: 'Focus runtime.',
    );

    registry.register(descriptor);

    expect(registry.contains(AppCommandId.showRuntime), isTrue);
    expect(registry.descriptorFor(AppCommandId.showRuntime).label, 'Runtime');
    expect(() => registry.register(descriptor), throwsStateError);
    expect(registry.unregister(AppCommandId.showRuntime), isTrue);
    expect(registry.contains(AppCommandId.showRuntime), isFalse);
  });

  test('command permission service separates allowed, approval, and denied', () {
    const service = CommandPermissionService();
    final quickOpen = StyioCommandRegistry.descriptorFor(
      AppCommandId.quickOpen,
    );
    final run = StyioCommandRegistry.descriptorFor(AppCommandId.run);
    const fullAccessCommand = AppCommandDescriptor(
      id: AppCommandId.openSettings,
      label: 'Full Access',
      shortcutHint: 'Route',
      description: 'Exercise policy denial.',
      permissionRequirement: AppCommandPermissionRequirement.fullAccess,
    );

    expect(
      service.evaluate(quickOpen).decision,
      CommandPermissionDecision.allowed,
    );
    expect(
      service.evaluate(run).decision,
      CommandPermissionDecision.requiresApproval,
    );
    expect(
      service.evaluate(fullAccessCommand).decision,
      CommandPermissionDecision.denied,
    );
  });
}
