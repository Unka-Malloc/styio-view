import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/app/commands/app_commands.dart';

void main() {
  test('command registry exposes primary command strip in mainline order', () {
    expect(
      StyioCommandRegistry.primaryCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.run,
        AppCommandId.quickOpen,
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
      final search = StyioCommandRegistry.descriptorFor(
        AppCommandId.searchWorkspace,
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

      expect(search.label, 'Find in Files');
      expect(search.shortcutHint, 'Cmd/Ctrl+Shift+F');
      expect(search.primary, isTrue);
      expect(search.shortcuts, hasLength(2));

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
      <AppCommandId>[AppCommandId.searchWorkspace],
    );
    expect(
      StyioCommandRegistry.navigationCommands.map((command) => command.id),
      <AppCommandId>[AppCommandId.quickOpen],
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
        AppCommandId.quickOpen,
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
    expect(intents, contains(AppCommandId.quickOpen));
    expect(intents, contains(AppCommandId.searchWorkspace));
    expect(intents, contains(AppCommandId.save));
    expect(intents, contains(AppCommandId.refreshModules));
  });
}
