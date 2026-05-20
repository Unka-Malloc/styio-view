import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/platform/platform_target.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_render/commands/commands.dart';
import 'package:vityo_app/src/view_render/platform/platform.dart';

void main() {
  testWidgets('command palette dispatches typed input commands', (
    tester,
  ) async {
    AppCommandId? executedCommandId;
    String? executedInput;

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
                id: AppCommandId.createWorkspaceFile,
                label: 'Create Workspace File',
                shortcutHint: 'Route',
                description: 'Create a workspace file.',
                requiresInput: true,
                inputLabel: 'New workspace file path',
              ),
              AppCommandDescriptor(
                id: AppCommandId.save,
                label: 'Save',
                shortcutHint: 'Cmd/Ctrl+S',
                description: 'Save current file.',
              ),
            ],
            onExecuteCommandWithInput: (commandId, input) async {
              executedCommandId = commandId;
              executedInput = input;
            },
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('command-palette-command-input')),
      findsOneWidget,
    );
    await tester.enterText(
      find.byKey(const ValueKey('command-palette-command-input')),
      'src/new.styio',
    );
    await tester.tap(
      find.byKey(const ValueKey('command-palette-createWorkspaceFile')),
    );
    await tester.pump();

    expect(executedCommandId, AppCommandId.createWorkspaceFile);
    expect(executedInput, 'src/new.styio');
  });
}
