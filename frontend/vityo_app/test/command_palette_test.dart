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
        AppCommandId.save,
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

    final declarationResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'declaration'),
    );
    expect(
      declarationResult.items.first.commandId,
      AppCommandId.goToWorkspaceDeclaration,
    );
    expect(declarationResult.items.first.category, 'Navigation');

    final definitionResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'definition'),
    );
    expect(
      definitionResult.items.first.commandId,
      AppCommandId.goToWorkspaceDefinition,
    );

    final typeDefinitionResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'type definition'),
    );
    expect(
      typeDefinitionResult.items.first.commandId,
      AppCommandId.goToWorkspaceTypeDefinition,
    );
    expect(typeDefinitionResult.items.first.category, 'Navigation');

    final implementationResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'implementation'),
    );
    expect(
      implementationResult.items.first.commandId,
      AppCommandId.goToWorkspaceImplementation,
    );
    expect(implementationResult.items.first.category, 'Navigation');

    final typeHierarchyResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'type hierarchy'),
    );
    expect(
      typeHierarchyResult.items.first.commandId,
      AppCommandId.showWorkspaceTypeHierarchy,
    );
    expect(typeHierarchyResult.items.first.category, 'Navigation');

    final outlineResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'outline'),
    );
    expect(
      outlineResult.items.first.commandId,
      AppCommandId.showWorkspaceOutline,
    );
    expect(outlineResult.items.first.category, 'Navigation');

    final recentLocationsResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'recent locations'),
    );
    expect(
      recentLocationsResult.items.first.commandId,
      AppCommandId.showRecentLocations,
    );
    expect(recentLocationsResult.items.first.category, 'Navigation');

    final documentLinksResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'document links'),
    );
    expect(
      documentLinksResult.items.first.commandId,
      AppCommandId.showWorkspaceDocumentLinks,
    );
    expect(documentLinksResult.items.first.category, 'Navigation');

    final documentHighlightsResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'document highlights'),
    );
    expect(
      documentHighlightsResult.items.first.commandId,
      AppCommandId.showWorkspaceDocumentHighlights,
    );
    expect(documentHighlightsResult.items.first.category, 'Navigation');

    final codeLensResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'code lens'),
    );
    expect(
      codeLensResult.items.first.commandId,
      AppCommandId.showWorkspaceCodeLenses,
    );
    expect(codeLensResult.items.first.category, 'Navigation');

    final renameResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'rename symbol'),
    );
    expect(
      renameResult.items.first.commandId,
      AppCommandId.renameWorkspaceSymbol,
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

    final codeActionsResult = service.findCommands(
      commands: StyioCommandRegistry.commands,
      query: const CommandPaletteQuery(pattern: 'code actions'),
    );
    expect(
      codeActionsResult.items.first.commandId,
      AppCommandId.showWorkspaceCodeActions,
    );
    expect(codeActionsResult.items.first.category, 'Refactor');
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
