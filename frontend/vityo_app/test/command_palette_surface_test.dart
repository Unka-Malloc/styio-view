import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_render/commands/commands.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets('command palette filters and executes registered commands', (
    tester,
  ) async {
    AppCommandId? executedCommandId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandPaletteSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            commands: const <AppCommandDescriptor>[
              AppCommandDescriptor(
                id: AppCommandId.save,
                label: 'Save',
                shortcutHint: 'Cmd/Ctrl+S',
                description: 'Save current file.',
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
            ],
            blockedReasonForCommand: (commandId) {
              return commandId == AppCommandId.renameSymbol
                  ? 'Needs input'
                  : null;
            },
            onExecuteCommand: (commandId) async {
              executedCommandId = commandId;
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('command-palette-surface')),
      findsOneWidget,
    );
    expect(find.text('registered 2'), findsOneWidget);
    expect(find.text('selected Rename Symbol'), findsOneWidget);
    expect(
      find.text('New symbol name valid for the active language.'),
      findsOneWidget,
    );
    expect(find.text('Examples: renamed'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('command-palette-query-input')),
      'save',
    );
    await tester.pump();

    expect(find.text('visible 1'), findsOneWidget);
    expect(find.text('selected Save'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(executedCommandId, AppCommandId.save);

    await tester.enterText(
      find.byKey(const ValueKey('command-palette-query-input')),
      'missing',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('command-palette-empty-state')),
      findsOneWidget,
    );
    expect(find.text('No commands match "missing".'), findsOneWidget);
  });

  testWidgets('command palette can filter by command category', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandPaletteSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            commands: const <AppCommandDescriptor>[
              AppCommandDescriptor(
                id: AppCommandId.searchWorkspace,
                label: 'Search Workspace',
                shortcutHint: 'Route',
                description: 'Search workspace files.',
              ),
              AppCommandDescriptor(
                id: AppCommandId.renameSymbol,
                label: 'Rename Symbol',
                shortcutHint: 'Route',
                description: 'Rename selected symbol.',
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('command-palette-category-filters')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('command-palette-category-navigation')),
    );
    await tester.pump();

    expect(find.text('category navigation'), findsOneWidget);
    expect(find.text('Search Workspace'), findsOneWidget);
    expect(find.text('Rename Symbol'), findsNothing);

    await tester.tap(
      find.byKey(const ValueKey('command-palette-category-all')),
    );
    await tester.pump();

    expect(find.text('Search Workspace'), findsOneWidget);
    expect(find.text('Rename Symbol'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('command-palette-query-input')),
      AppCommandCategory.navigation.wireValue,
    );
    await tester.pump();

    expect(find.text('Search Workspace'), findsOneWidget);
    expect(find.text('Rename Symbol'), findsNothing);
    expect(find.text('visible 1'), findsOneWidget);
  });

  testWidgets('command palette applies display preferences', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandPaletteSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            recentHistory: const CommandPaletteRecentCommandHistory(
              workspaceId: 'demo',
              commandIds: <AppCommandId>[AppCommandId.save],
            ),
            displayPreferences: const CommandPaletteDisplayPreferences(
              workspaceId: 'demo',
              defaultCategory: AppCommandCategory.navigation,
              showCategoryFilters: false,
              showRecentCommands: false,
            ),
            commands: const <AppCommandDescriptor>[
              AppCommandDescriptor(
                id: AppCommandId.searchWorkspace,
                label: 'Search Workspace',
                shortcutHint: 'Route',
                description: 'Search workspace files.',
              ),
              AppCommandDescriptor(
                id: AppCommandId.save,
                label: 'Save',
                shortcutHint: 'Cmd/Ctrl+S',
                description: 'Save current file.',
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.text('category navigation'), findsOneWidget);
    expect(find.text('visible 1'), findsOneWidget);
    expect(find.text('selected Search Workspace'), findsOneWidget);
    expect(find.text('preferences workspace'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('command-palette-category-filters')),
      findsNothing,
    );
    expect(find.text('recent 1'), findsNothing);
  });

  testWidgets('command palette reacts to live preference updates', (
    tester,
  ) async {
    final controller = CommandPaletteLivePreferenceController(
      initialPreferences: const CommandPaletteDisplayPreferences(
        workspaceId: 'demo',
        showCategoryFilters: true,
        showRecentCommands: true,
      ),
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandPaletteSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            recentHistory: const CommandPaletteRecentCommandHistory(
              workspaceId: 'demo',
              commandIds: <AppCommandId>[AppCommandId.save],
            ),
            livePreferenceController: controller,
            commands: const <AppCommandDescriptor>[
              AppCommandDescriptor(
                id: AppCommandId.searchWorkspace,
                label: 'Search Workspace',
                shortcutHint: 'Route',
                description: 'Search workspace files.',
              ),
              AppCommandDescriptor(
                id: AppCommandId.save,
                label: 'Save',
                shortcutHint: 'Cmd/Ctrl+S',
                description: 'Save current file.',
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('command-palette-category-filters')),
      findsOneWidget,
    );
    expect(find.text('recent 1'), findsOneWidget);

    controller.updatePreferences(
      const CommandPaletteDisplayPreferences(
        workspaceId: 'demo',
        defaultCategory: AppCommandCategory.navigation,
        showCategoryFilters: false,
        showRecentCommands: false,
      ),
    );
    await tester.pump();

    expect(find.text('category navigation'), findsOneWidget);
    expect(find.text('visible 1'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('command-palette-category-filters')),
      findsNothing,
    );
    expect(find.text('recent 1'), findsNothing);
  });

  testWidgets('command palette uses recent history ranking', (tester) async {
    AppCommandId? executedCommandId;
    AppCommandId? recordedCommandId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandPaletteSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            recentHistory: const CommandPaletteRecentCommandHistory(
              workspaceId: 'demo',
              commandIds: <AppCommandId>[AppCommandId.save],
            ),
            commands: const <AppCommandDescriptor>[
              AppCommandDescriptor(
                id: AppCommandId.renameSymbol,
                label: 'Rename Symbol',
                shortcutHint: 'Route',
                description: 'Rename selected symbol.',
              ),
              AppCommandDescriptor(
                id: AppCommandId.save,
                label: 'Save',
                shortcutHint: 'Cmd/Ctrl+S',
                description: 'Save current file.',
              ),
            ],
            onRecordRecentCommand: (commandId) async {
              recordedCommandId = commandId;
            },
            onExecuteCommand: (commandId) async {
              executedCommandId = commandId;
            },
          ),
        ),
      ),
    );

    expect(find.text('recent 1'), findsOneWidget);
    expect(find.text('selected Save'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('command-palette-save')));
    await tester.pump();

    expect(recordedCommandId, AppCommandId.save);
    expect(executedCommandId, AppCommandId.save);
  });

  testWidgets('command palette keyboard navigation executes selection', (
    tester,
  ) async {
    AppCommandId? executedCommandId;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandPaletteSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 800,
            ),
            commands: const <AppCommandDescriptor>[
              AppCommandDescriptor(
                id: AppCommandId.renameSymbol,
                label: 'Rename Symbol',
                shortcutHint: 'Route',
                description: 'Rename selected symbol.',
              ),
              AppCommandDescriptor(
                id: AppCommandId.save,
                label: 'Save',
                shortcutHint: 'Cmd/Ctrl+S',
                description: 'Save current file.',
              ),
            ],
            onExecuteCommand: (commandId) async {
              executedCommandId = commandId;
            },
          ),
        ),
      ),
    );

    expect(find.text('selected Rename Symbol'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(find.text('selected Save'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(executedCommandId, AppCommandId.save);
  });

  testWidgets('command palette edits keybinding overrides and conflicts', (
    tester,
  ) async {
    CommandKeybindingOverride? savedOverride;
    AppCommandId? clearedCommandId;
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

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandPaletteSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.macos,
              width: 1200,
              height: 900,
            ),
            keybindingProfile: profile,
            commands: const <AppCommandDescriptor>[
              AppCommandDescriptor(
                id: AppCommandId.save,
                label: 'Save',
                shortcutHint: 'Cmd/Ctrl+S',
                description: 'Save current file.',
              ),
              AppCommandDescriptor(
                id: AppCommandId.renameSymbol,
                label: 'Rename Symbol',
                shortcutHint: 'Route',
                description: 'Rename selected symbol.',
              ),
            ],
            onSaveKeybindingOverride: (override) async {
              savedOverride = override;
            },
            onClearKeybindingOverride: (commandId) async {
              clearedCommandId = commandId;
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('command-palette-keybinding-editor')),
      findsOneWidget,
    );
    expect(find.text('conflicts 1'), findsOneWidget);
    expect(find.text('Ctrl+keyR'), findsWidgets);
    expect(find.text('shortcut Ctrl+keyR'), findsOneWidget);
    expect(find.text('Save · persistence · override'), findsOneWidget);
    expect(find.text('Rename Symbol · refactor · override'), findsOneWidget);
    expect(
      find.byKey(
        const ValueKey('command-palette-keybinding-selected-override'),
      ),
      findsOneWidget,
    );

    final shortcutInput = find.byKey(
      const ValueKey('command-palette-keybinding-shortcut-input'),
    );
    await tester.ensureVisible(shortcutInput);
    await tester.pump();
    final shortcutEditable = find.descendant(
      of: shortcutInput,
      matching: find.byType(EditableText),
    );
    tester.widget<EditableText>(shortcutEditable).focusNode.requestFocus();
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('command-palette-keybinding-save')),
        )
        .onPressed!();
    await tester.pump();

    expect(savedOverride?.commandId, AppCommandId.save);
    expect(savedOverride?.shortcuts.single.key, 'keyK');
    expect(savedOverride?.shortcuts.single.control, isTrue);
    expect(savedOverride?.shortcuts.single.shift, isTrue);

    tester
        .widget<OutlinedButton>(
          find.byKey(const ValueKey('command-palette-keybinding-clear')),
        )
        .onPressed!();
    await tester.pump();

    expect(clearedCommandId, AppCommandId.save);

    tester
        .widget<TextButton>(
          find.byKey(
            const ValueKey(
              'command-palette-keybinding-edit-conflict-renameSymbol',
            ),
          ),
        )
        .onPressed!();
    await tester.pump();

    expect(find.text('ctrl+keyR'), findsWidgets);
  });
}
