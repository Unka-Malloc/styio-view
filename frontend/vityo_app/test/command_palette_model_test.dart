import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';

void main() {
  test('command palette model ranks query matches and recent commands', () {
    const commands = <AppCommandDescriptor>[
      AppCommandDescriptor(
        id: AppCommandId.searchWorkspace,
        label: 'Search Workspace',
        shortcutHint: 'Route',
        description: 'Search files.',
      ),
      AppCommandDescriptor(
        id: AppCommandId.save,
        label: 'Save',
        shortcutHint: 'Cmd/Ctrl+S',
        description: 'Persist file.',
      ),
      AppCommandDescriptor(
        id: AppCommandId.renameSymbol,
        label: 'Rename Symbol',
        shortcutHint: 'Route',
        description: 'Change symbol name.',
      ),
    ];

    final entries = const CommandPaletteModel(commands: commands).entriesFor(
      const CommandPaletteQueryState(
        query: 's',
        recentCommandIds: <AppCommandId>[
          AppCommandId.searchWorkspace,
          AppCommandId.save,
        ],
      ),
    );

    expect(entries.map((entry) => entry.command.id), <AppCommandId>[
      AppCommandId.searchWorkspace,
      AppCommandId.save,
      AppCommandId.renameSymbol,
    ]);
    expect(entries.first.recent, isTrue);
    expect(entries.first.score, greaterThan(entries.last.score));
    expect(entries.first.toJson()['recentRank'], 0);
  });

  test('command palette model filters by category and builds input draft', () {
    const command = AppCommandDescriptor(
      id: AppCommandId.renameSymbol,
      label: 'Rename Symbol',
      shortcutHint: 'Route',
      description: 'Rename selected symbol.',
      requiresInput: true,
      inputLabel: 'New symbol name',
    );
    final entries =
        const CommandPaletteModel(
          commands: <AppCommandDescriptor>[command],
        ).entriesFor(
          const CommandPaletteQueryState(category: AppCommandCategory.refactor),
        );
    const emptyDraft = CommandPaletteInputDraft(command: command);
    const readyDraft = CommandPaletteInputDraft(
      command: command,
      input: 'renamed',
    );

    expect(entries.single.command.id, AppCommandId.renameSymbol);
    expect(emptyDraft.ready, isFalse);
    expect(readyDraft.ready, isTrue);
    expect(readyDraft.toJson()['input'], 'renamed');
  });

  test('command palette overlay state tracks selection and input draft', () {
    const commands = <AppCommandDescriptor>[
      AppCommandDescriptor(
        id: AppCommandId.save,
        label: 'Save',
        shortcutHint: 'Cmd/Ctrl+S',
        description: 'Persist file.',
      ),
      AppCommandDescriptor(
        id: AppCommandId.renameSymbol,
        label: 'Rename Symbol',
        shortcutHint: 'Route',
        description: 'Rename selected symbol.',
        requiresInput: true,
        inputLabel: 'New symbol name',
      ),
    ];
    const model = CommandPaletteModel(commands: commands);

    final state = model.overlayStateFor(
      const CommandPaletteQueryState(query: 'rename'),
      selectedIndex: 99,
    );
    final moved = state.moveSelection(-1);
    final json = state.toJson();

    expect(state.visible, isTrue);
    expect(state.visibleCount, 1);
    expect(state.selectedEntry?.command.id, AppCommandId.renameSymbol);
    expect(state.selectedInputDraft?.ready, isFalse);
    expect(moved.selectedIndex, 0);
    expect(json['selectedIndex'], 0);
    expect(
      (json['selectedInputDraft']! as Map<String, Object?>)['inputLabel'],
      'New symbol name',
    );
  });
}
