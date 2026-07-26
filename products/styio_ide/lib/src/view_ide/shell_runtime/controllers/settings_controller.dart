import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../commands/commands.dart';
import '../../environment/configuration/configuration.dart';

/// Owns shell-level settings state and persistence while the shell remains the
/// composition root that relays changes to presentation listeners.
final class SettingsController extends ChangeNotifier {
  SettingsController({
    required this.workspaceId,
    required this.defaultWorkspaceId,
    required this.log,
    this.themeOverrideStore,
    this.commandPalettePreferencesStore,
    CommandPaletteDisplayPreferences? commandPalettePreferences,
    CommandPaletteLivePreferenceController? commandPalettePreferenceController,
  }) : _ownsCommandPalettePreferenceController =
           commandPalettePreferenceController == null,
       commandPalettePreferenceController =
           commandPalettePreferenceController ??
           CommandPaletteLivePreferenceController(
             initialPreferences:
                 commandPalettePreferences ??
                 CommandPaletteDisplayPreferences(
                   workspaceId: defaultWorkspaceId,
                 ),
           ) {
    _commandPalettePreferenceSubscription = this
        .commandPalettePreferenceController
        .stream
        .listen((_) => notifyListeners());
  }

  final String Function() workspaceId;
  final String defaultWorkspaceId;
  final void Function(String message) log;
  final VityoThemeOverrideStore? themeOverrideStore;
  final CommandPaletteDisplayPreferencesStore? commandPalettePreferencesStore;
  final CommandPaletteLivePreferenceController
  commandPalettePreferenceController;
  final bool _ownsCommandPalettePreferenceController;

  late final StreamSubscription<CommandPaletteLivePreferenceState>
  _commandPalettePreferenceSubscription;

  VityoThemeOverride _themeOverride = const VityoThemeOverride();

  VityoThemeOverride get themeOverride => _themeOverride;

  CommandPaletteDisplayPreferences get commandPalettePreferences =>
      commandPalettePreferenceController.state.preferences;

  Future<void> loadThemeOverride({String key = 'default'}) async {
    final store = themeOverrideStore;
    if (store == null) {
      log('Theme override restore unavailable: no DataStore is wired.');
      return;
    }
    final activeWorkspaceId = workspaceId();
    final override = await store.readOverride(
      workspaceId: activeWorkspaceId,
      key: key,
    );
    if (override == null) {
      return;
    }
    _themeOverride = override;
    log('Theme override restored for $activeWorkspaceId.');
    notifyListeners();
  }

  Future<void> saveThemeOverride(
    VityoThemeOverride override, {
    String key = 'default',
  }) async {
    _themeOverride = override;
    final store = themeOverrideStore;
    if (store == null) {
      log('Theme override applied without persistence.');
      notifyListeners();
      return;
    }
    final activeWorkspaceId = workspaceId();
    await store.saveOverride(
      workspaceId: activeWorkspaceId,
      key: key,
      override: override,
    );
    log('Theme override persisted for $activeWorkspaceId.');
    notifyListeners();
  }

  Future<CommandPaletteDisplayPreferences> loadCommandPalettePreferences({
    String? workspaceId,
  }) async {
    final store = commandPalettePreferencesStore;
    final targetWorkspaceId = workspaceId ?? defaultWorkspaceId;
    if (store == null) {
      final preferences = commandPalettePreferences.workspaceId.isEmpty
          ? CommandPaletteDisplayPreferences(workspaceId: targetWorkspaceId)
          : commandPalettePreferences;
      commandPalettePreferenceController.updatePreferences(preferences);
      log(
        'Command palette preferences loaded from live defaults for ${preferences.workspaceId}.',
      );
      notifyListeners();
      return preferences;
    }
    try {
      final preferences = await store.readPreferences(
        workspaceId: targetWorkspaceId,
      );
      commandPalettePreferenceController.updatePreferences(preferences);
      log('Command palette preferences loaded for ${preferences.workspaceId}.');
      notifyListeners();
      return preferences;
    } on Object catch (error) {
      log('Command palette preferences load failed: $error');
      notifyListeners();
      return commandPalettePreferences;
    }
  }

  Future<void> saveCommandPalettePreferences(
    CommandPaletteDisplayPreferences preferences,
  ) async {
    var next = preferences;
    final store = commandPalettePreferencesStore;
    if (store != null) {
      try {
        next = await store.savePreferences(preferences);
      } on Object catch (error) {
        log('Command palette preferences save failed: $error');
      }
    }
    commandPalettePreferenceController.updatePreferences(next);
    log('Command palette preferences saved for ${next.workspaceId}.');
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_commandPalettePreferenceSubscription.cancel());
    if (_ownsCommandPalettePreferenceController) {
      unawaited(commandPalettePreferenceController.dispose());
    }
    super.dispose();
  }
}
