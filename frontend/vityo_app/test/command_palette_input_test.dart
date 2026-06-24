import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  testWidgets('command palette captures physical keybinding overrides', (
    tester,
  ) async {
    CommandKeybindingOverride? savedOverride;

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
            ],
            keybindingProfile: CommandKeybindingProfile(workspaceId: 'demo'),
            onSaveKeybindingOverride: (override) async {
              savedOverride = override;
            },
          ),
        ),
      ),
    );

    final shortcutInput = find.byKey(
      const ValueKey('command-palette-keybinding-shortcut-input'),
    );
    await tester.ensureVisible(shortcutInput);
    await tester.pump();
    await tester.tap(shortcutInput);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const ValueKey('command-palette-keybinding-save')),
    );
    await tester.tap(
      find.byKey(const ValueKey('command-palette-keybinding-save')),
    );
    await tester.pump();

    final shortcut = savedOverride?.shortcuts.single;
    expect(savedOverride?.commandId, AppCommandId.save);
    expect(shortcut?.control, isTrue);
    expect(shortcut?.key, 'keyK');
    expect(shortcut?.shift, isFalse);
  });

  testWidgets('command palette blocks reserved keybinding capture', (
    tester,
  ) async {
    CommandKeybindingOverride? savedOverride;

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
            ],
            keybindingProfile: CommandKeybindingProfile(workspaceId: 'demo'),
            onSaveKeybindingOverride: (override) async {
              savedOverride = override;
            },
          ),
        ),
      ),
    );

    final shortcutInput = find.byKey(
      const ValueKey('command-palette-keybinding-shortcut-input'),
    );
    await tester.ensureVisible(shortcutInput);
    await tester.pump();
    await tester.tap(shortcutInput);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.metaLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.metaLeft);
    await tester.pump();

    expect(find.textContaining('reserved'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('command-palette-keybinding-save')),
          )
          .onPressed,
      isNull,
    );
    expect(savedOverride, isNull);
  });

  testWidgets('command palette applies web host shortcut policy', (
    tester,
  ) async {
    CommandKeybindingOverride? savedOverride;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CommandPaletteSurface(
            viewportProfile: resolveViewportProfile(
              platformTarget: PlatformTarget.web,
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
            ],
            keybindingProfile: CommandKeybindingProfile(workspaceId: 'demo'),
            onSaveKeybindingOverride: (override) async {
              savedOverride = override;
            },
          ),
        ),
      ),
    );

    final shortcutInput = find.byKey(
      const ValueKey('command-palette-keybinding-shortcut-input'),
    );
    await tester.ensureVisible(shortcutInput);
    await tester.pump();
    await tester.tap(shortcutInput);
    await tester.pump();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();

    expect(find.textContaining('web-browser'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('command-palette-keybinding-save')),
          )
          .onPressed,
      isNull,
    );
    expect(savedOverride, isNull);
  });
}
