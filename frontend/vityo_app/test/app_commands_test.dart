import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/app/commands/app_commands.dart';

void main() {
  test('command registry exposes primary command strip in mainline order', () {
    expect(
      StyioCommandRegistry.primaryCommands.map((command) => command.id),
      <AppCommandId>[
        AppCommandId.run,
        AppCommandId.fetchDependencies,
        AppCommandId.vendorDependencies,
        AppCommandId.refreshModules,
      ],
    );
  });

  test(
    'command registry resolves descriptors and shortcuts for source ops',
    () {
      final fetch = StyioCommandRegistry.descriptorFor(
        AppCommandId.fetchDependencies,
      );
      final vendor = StyioCommandRegistry.descriptorFor(
        AppCommandId.vendorDependencies,
      );

      expect(fetch.label, 'Fetch');
      expect(fetch.shortcutHint, 'Cmd/Ctrl+Shift+F');
      expect(fetch.primary, isTrue);
      expect(fetch.shortcuts, hasLength(2));

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
    expect(intents, contains(AppCommandId.save));
    expect(intents, contains(AppCommandId.refreshModules));
  });
}
