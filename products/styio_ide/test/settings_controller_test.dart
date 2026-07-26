import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/commands/commands.dart';
import 'package:styio_ide/src/view_ide/environment/configuration/configuration.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/settings_controller.dart';

void main() {
  test('settings controller owns theme and command palette state', () async {
    final messages = <String>[];
    final controller = SettingsController(
      workspaceId: () => 'workspace-a',
      defaultWorkspaceId: 'workspace-a',
      log: messages.add,
    );
    addTearDown(controller.dispose);

    var notifications = 0;
    controller.addListener(() => notifications += 1);

    const theme = VityoThemeOverride(canvas: 0xFF101820);
    await controller.saveThemeOverride(theme);
    await controller.saveCommandPalettePreferences(
      const CommandPaletteDisplayPreferences(
        workspaceId: 'workspace-a',
        defaultCategory: AppCommandCategory.navigation,
        showRecentCommands: false,
      ),
    );
    await pumpEventQueue();

    expect(controller.themeOverride, theme);
    expect(
      controller.commandPalettePreferences.defaultCategory,
      AppCommandCategory.navigation,
    );
    expect(controller.commandPalettePreferences.showRecentCommands, isFalse);
    expect(notifications, greaterThanOrEqualTo(2));
    expect(
      messages,
      containsAll(<String>[
        'Theme override applied without persistence.',
        'Command palette preferences saved for workspace-a.',
      ]),
    );
  });
}
