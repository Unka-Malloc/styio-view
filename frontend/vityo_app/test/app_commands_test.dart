import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/app/commands/app_commands.dart';

void main() {
  test('command registry exposes primary command strip in mainline order', () {
    expect(
      StyioCommandRegistry.primaryCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.run,
        AppCommandId.commandPalette,
        AppCommandId.quickOpen,
        AppCommandId.searchWorkspaceSymbols,
        AppCommandId.findWorkspaceReferences,
        AppCommandId.showWorkspaceCallHierarchy,
        AppCommandId.searchWorkspace,
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
        AppCommandId.searchWorkspaceSymbols,
        AppCommandId.findWorkspaceReferences,
        AppCommandId.showWorkspaceCallHierarchy,
        AppCommandId.searchWorkspace,
      ],
    );
    expect(
      StyioCommandRegistry.navigationCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.commandPalette,
        AppCommandId.quickOpen,
        AppCommandId.searchWorkspaceSymbols,
        AppCommandId.findWorkspaceReferences,
        AppCommandId.showWorkspaceCallHierarchy,
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
        AppCommandId.searchWorkspaceSymbols,
        AppCommandId.findWorkspaceReferences,
        AppCommandId.showWorkspaceCallHierarchy,
        AppCommandId.searchWorkspace,
        AppCommandId.fetchDependencies,
        AppCommandId.vendorDependencies,
        AppCommandId.useActiveCompiler,
        AppCommandId.pinActiveCompiler,
        AppCommandId.clearPinnedCompiler,
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
    expect(intents, contains(AppCommandId.searchWorkspaceSymbols));
    expect(intents, contains(AppCommandId.findWorkspaceReferences));
    expect(intents, contains(AppCommandId.showWorkspaceCallHierarchy));
    expect(intents, contains(AppCommandId.searchWorkspace));
    expect(intents, contains(AppCommandId.save));
    expect(intents, contains(AppCommandId.refreshModules));
  });
}
