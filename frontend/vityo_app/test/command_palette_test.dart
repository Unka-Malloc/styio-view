import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/app/commands/app_commands.dart';

void main() {
  test('command palette returns recent commands first for an empty query', () {
    final result = const CommandPaletteService().findCommands(
      commands: StyioCommandRegistry.commands,
      recentCommandIds: const <AppCommandId>[
        AppCommandId.searchWorkspace,
        AppCommandId.run,
      ],
      query: const CommandPaletteQuery(maxResults: 3),
    );

    expect(result.status, CommandPaletteStatus.hitLimit);
    expect(result.hitLimit, isTrue);
    expect(
      result.items.map((item) => item.commandId),
      <AppCommandId>[
        AppCommandId.searchWorkspace,
        AppCommandId.run,
        AppCommandId.commandPalette,
      ],
    );
    expect(result.items.map((item) => item.recentRank), <int?>[0, 1, null]);
  });

  test('command palette scores label, command id, and shortcut matches', () {
    final service = const CommandPaletteService();

    final labelResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'palette'),
    );
    expect(labelResult.items.first.commandId, AppCommandId.commandPalette);
    expect(labelResult.items.first.matches, isNotEmpty);

    final idResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'search workspace'),
    );
    expect(idResult.items.first.commandId, AppCommandId.searchWorkspace);

    final shortcutResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'shift+p'),
    );
    expect(shortcutResult.items.first.commandId, AppCommandId.commandPalette);

    final symbolResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'symbols'),
    );
    expect(
      symbolResult.items.first.commandId,
      AppCommandId.searchWorkspaceSymbols,
    );

    final usageResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'find usages'),
    );
    expect(
      usageResult.items.first.commandId,
      AppCommandId.findWorkspaceReferences,
    );

    final callHierarchyResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'call hierarchy'),
    );
    expect(
      callHierarchyResult.items.first.commandId,
      AppCommandId.showWorkspaceCallHierarchy,
    );

    final problemsResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'problems'),
    );
    expect(
      problemsResult.items.first.commandId,
      AppCommandId.showWorkspaceProblems,
    );
  });

  test('command palette surfaces blocked commands and can exclude them', () {
    String? blockedReason(AppCommandId commandId) {
      return commandId == AppCommandId.fetchDependencies
          ? 'Dependencies are unavailable.'
          : null;
    }

    final included = const CommandPaletteService().findCommands(
      commands: StyioCommandRegistry.commands,
      blockedReasonForCommand: blockedReason,
      query: const CommandPaletteQuery(pattern: 'fetch'),
    );

    expect(included.items.single.commandId, AppCommandId.fetchDependencies);
    expect(included.items.single.enabled, isFalse);
    expect(included.blockedCount, 1);

    final excluded = const CommandPaletteService().findCommands(
      commands: StyioCommandRegistry.commands,
      blockedReasonForCommand: blockedReason,
      query: const CommandPaletteQuery(
        pattern: 'fetch',
        includeBlocked: false,
      ),
    );

    expect(excluded.items, isEmpty);
  });
}
