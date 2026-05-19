import 'package:flutter/material.dart';
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
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Rename Symbol'), findsOneWidget);
    expect(find.text(AppCommandCategory.persistence.wireValue), findsOneWidget);
    expect(find.text(AppCommandCategory.refactor.wireValue), findsOneWidget);
    expect(find.textContaining('Blocked: Needs input'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('command-palette-query-input')),
      'save',
    );
    await tester.pump();

    expect(find.text('visible 1'), findsOneWidget);
    expect(find.text('Save'), findsOneWidget);
    expect(find.text('Rename Symbol'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('command-palette-save')));
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

    await tester.enterText(
      find.byKey(const ValueKey('command-palette-query-input')),
      AppCommandCategory.navigation.wireValue,
    );
    await tester.pump();

    expect(find.text('Search Workspace'), findsOneWidget);
    expect(find.text('Rename Symbol'), findsNothing);
    expect(find.text('visible 1'), findsOneWidget);
  });
}
