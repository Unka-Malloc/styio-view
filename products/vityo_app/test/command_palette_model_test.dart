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
      inputContract: 'New symbol name valid for the active language.',
      inputExamples: <String>['renamed'],
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
    expect(emptyDraft.toJson()['inputContract'], contains('active language'));
    expect(emptyDraft.toJson()['inputExamples'], contains('renamed'));
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
        inputContract: 'New symbol name valid for the active language.',
        inputExamples: <String>['renamed'],
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
    expect(
      (json['selectedInputDraft']! as Map<String, Object?>)['inputContract'],
      contains('active language'),
    );
  });

  test(
    'command palette live preference controller streams revisions',
    () async {
      final controller = CommandPaletteLivePreferenceController(
        initialPreferences: const CommandPaletteDisplayPreferences(
          workspaceId: 'demo',
        ),
      );
      addTearDown(controller.dispose);
      final updates = <CommandPaletteLivePreferenceState>[];
      final subscription = controller.stream.listen(updates.add);
      addTearDown(subscription.cancel);

      controller.updatePreferences(
        const CommandPaletteDisplayPreferences(
          workspaceId: 'demo',
          defaultCategory: AppCommandCategory.navigation,
          showCategoryFilters: false,
          showRecentCommands: false,
        ),
      );

      await Future<void>.delayed(Duration.zero);

      expect(controller.state.revision, 1);
      expect(
        controller.state.preferences.defaultCategory,
        AppCommandCategory.navigation,
      );
      expect(controller.state.preferences.showCategoryFilters, isFalse);
      expect(updates.single.revision, 1);
      expect(
        (updates.single.toJson()['preferences']!
            as Map<String, Object?>)['showRecentCommands'],
        isFalse,
      );
    },
  );

  test('command keybinding conflicts include rich command previews', () {
    final profile = CommandKeybindingProfile(
      workspaceId: 'demo',
      overrides: <AppCommandId, CommandKeybindingOverride>{
        AppCommandId.save: const CommandKeybindingOverride(
          commandId: AppCommandId.save,
          shortcuts: <AppCommandShortcutSpec>[
            AppCommandShortcutSpec('keyR', control: true),
          ],
        ),
        AppCommandId.renameSymbol: const CommandKeybindingOverride(
          commandId: AppCommandId.renameSymbol,
          shortcuts: <AppCommandShortcutSpec>[
            AppCommandShortcutSpec('keyR', control: true),
          ],
        ),
      },
    );
    final review = CommandKeybindingResolver.reviewConflicts(
      profile: profile,
      descriptors: const <AppCommandDescriptor>[
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
          description: 'Rename symbol.',
        ),
      ],
    );
    final conflict = review.conflicts.single;
    final json = conflict.toJson();

    expect(conflict.shortcutLabel, 'Ctrl+keyR');
    expect(conflict.commandPreviews.map((preview) => preview.label), <String>[
      'Save',
      'Rename Symbol',
    ]);
    expect(conflict.commandPreviews.map((preview) => preview.category), <
        AppCommandCategory>[
      AppCommandCategory.persistence,
      AppCommandCategory.refactor,
    ]);
    expect(
      (json['commandPreviews']! as List<Object?>).first,
      isA<Map<String, Object?>>()
          .having((value) => value['source'], 'source', 'override'),
    );
  });
}
