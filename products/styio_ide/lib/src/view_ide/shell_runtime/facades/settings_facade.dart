part of '../shell_runtime_model.dart';

/// Public settings facade backed by the settings domain controller.
mixin ShellRuntimeSettingsFacade on ShellRuntimeFacadeHost {
  VityoThemeOverride get themeOverride => _settingsController.themeOverride;
  CommandPaletteLivePreferenceController
  get commandPalettePreferenceController =>
      _settingsController.commandPalettePreferenceController;

  Future<void> loadThemeOverride({String key = 'default'}) =>
      _settingsController.loadThemeOverride(key: key);

  Future<void> saveThemeOverride(
    VityoThemeOverride override, {
    String key = 'default',
  }) => _settingsController.saveThemeOverride(override, key: key);

  CommandPaletteDisplayPreferences get commandPalettePreferences =>
      _settingsController.commandPalettePreferences;

  Future<CommandPaletteDisplayPreferences> loadCommandPalettePreferences({
    String? workspaceId,
  }) => _settingsController.loadCommandPalettePreferences(
    workspaceId: workspaceId,
  );

  Future<void> saveCommandPalettePreferences(
    CommandPaletteDisplayPreferences preferences,
  ) => _settingsController.saveCommandPalettePreferences(preferences);
}
