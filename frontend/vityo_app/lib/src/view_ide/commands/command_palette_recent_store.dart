import 'dart:async';

import '../foundation/foundation.dart';
import 'app_commands.dart';
import 'command_palette_model.dart';

class CommandPaletteRecentCommandHistory {
  const CommandPaletteRecentCommandHistory({
    required this.workspaceId,
    this.commandIds = const <AppCommandId>[],
    this.updatedAt,
  });

  factory CommandPaletteRecentCommandHistory.fromJson(
    Map<String, Object?> json,
  ) {
    return CommandPaletteRecentCommandHistory(
      workspaceId: json['workspaceId'] as String? ?? '',
      commandIds: _commandIdsFromJson(json['commandIds']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final List<AppCommandId> commandIds;
  final DateTime? updatedAt;

  CommandPaletteRecentCommandHistory record(
    AppCommandId commandId, {
    int maxEntries = 20,
    DateTime? updatedAt,
  }) {
    return CommandPaletteRecentCommandHistory(
      workspaceId: workspaceId,
      commandIds: <AppCommandId>[
        commandId,
        ...commandIds.where((id) => id != commandId),
      ].take(maxEntries).toList(growable: false),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  CommandPaletteQueryState toQueryState({
    String query = '',
    AppCommandCategory? category,
  }) {
    return CommandPaletteQueryState(
      query: query,
      category: category,
      recentCommandIds: commandIds,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'commandIds': commandIds.map((id) => id.name).toList(growable: false),
      'count': commandIds.length,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class CommandPaletteDisplayPreferences {
  const CommandPaletteDisplayPreferences({
    required this.workspaceId,
    this.defaultCategory,
    this.showCategoryFilters = true,
    this.showRecentCommands = true,
    this.updatedAt,
  });

  factory CommandPaletteDisplayPreferences.fromJson(Map<String, Object?> json) {
    return CommandPaletteDisplayPreferences(
      workspaceId: json['workspaceId'] as String? ?? '',
      defaultCategory: _commandCategoryFromWireValue(
        json['defaultCategory'] as String? ?? '',
      ),
      showCategoryFilters: json['showCategoryFilters'] as bool? ?? true,
      showRecentCommands: json['showRecentCommands'] as bool? ?? true,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final AppCommandCategory? defaultCategory;
  final bool showCategoryFilters;
  final bool showRecentCommands;
  final DateTime? updatedAt;

  CommandPaletteDisplayPreferences copyWith({
    AppCommandCategory? defaultCategory,
    bool clearDefaultCategory = false,
    bool? showCategoryFilters,
    bool? showRecentCommands,
    DateTime? updatedAt,
  }) {
    return CommandPaletteDisplayPreferences(
      workspaceId: workspaceId,
      defaultCategory: clearDefaultCategory
          ? null
          : defaultCategory ?? this.defaultCategory,
      showCategoryFilters: showCategoryFilters ?? this.showCategoryFilters,
      showRecentCommands: showRecentCommands ?? this.showRecentCommands,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  CommandPaletteQueryState toQueryState({
    String query = '',
    List<AppCommandId> recentCommandIds = const <AppCommandId>[],
  }) {
    return CommandPaletteQueryState(
      query: query,
      category: defaultCategory,
      recentCommandIds: showRecentCommands
          ? recentCommandIds
          : const <AppCommandId>[],
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      if (defaultCategory != null)
        'defaultCategory': defaultCategory!.wireValue,
      'showCategoryFilters': showCategoryFilters,
      'showRecentCommands': showRecentCommands,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class CommandPaletteLivePreferenceState {
  const CommandPaletteLivePreferenceState({
    required this.preferences,
    this.revision = 0,
  });

  final CommandPaletteDisplayPreferences preferences;
  final int revision;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'revision': revision,
      'preferences': preferences.toJson(),
    };
  }
}

class CommandPaletteLivePreferenceController {
  CommandPaletteLivePreferenceController({
    required CommandPaletteDisplayPreferences initialPreferences,
  }) : _state = CommandPaletteLivePreferenceState(
         preferences: initialPreferences,
       );

  final StreamController<CommandPaletteLivePreferenceState> _updates =
      StreamController<CommandPaletteLivePreferenceState>.broadcast();

  CommandPaletteLivePreferenceState _state;

  CommandPaletteLivePreferenceState get state => _state;
  Stream<CommandPaletteLivePreferenceState> get stream => _updates.stream;

  void updatePreferences(CommandPaletteDisplayPreferences preferences) {
    _state = CommandPaletteLivePreferenceState(
      preferences: preferences,
      revision: _state.revision + 1,
    );
    _updates.add(_state);
  }

  Future<void> dispose() {
    return _updates.close();
  }
}

class CommandPaletteRecentCommandStore {
  CommandPaletteRecentCommandStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'interaction.command-palette.recent',
             layer: 'interaction',
             stateFamily: 'command-palette-recent',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const CommandPaletteRecentCommandStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'interaction.command-palette.recent';
  static const String _key = 'recent-commands';

  final FoundationDataStoreOwner _owner;

  Future<CommandPaletteRecentCommandHistory> readHistory({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return CommandPaletteRecentCommandHistory(workspaceId: workspaceId);
    }
    final history = CommandPaletteRecentCommandHistory.fromJson(value);
    return history.workspaceId.isEmpty
        ? CommandPaletteRecentCommandHistory(
            workspaceId: workspaceId,
            commandIds: history.commandIds,
            updatedAt: history.updatedAt,
          )
        : history;
  }

  Future<CommandPaletteRecentCommandHistory> recordCommand({
    required String workspaceId,
    required AppCommandId commandId,
    int maxEntries = 20,
    DateTime? updatedAt,
  }) async {
    final current = await readHistory(workspaceId: workspaceId);
    final next = current.record(
      commandId,
      maxEntries: maxEntries,
      updatedAt: updatedAt,
    );
    await _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: next.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    return next;
  }

  Future<bool> clearHistory({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

class CommandPaletteDisplayPreferencesStore {
  CommandPaletteDisplayPreferencesStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'interaction.command-palette.preferences',
             layer: 'interaction',
             stateFamily: 'command-palette-preferences',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const CommandPaletteDisplayPreferencesStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName =
      'interaction.command-palette.preferences';
  static const String _key = 'display-preferences';

  final FoundationDataStoreOwner _owner;

  Future<CommandPaletteDisplayPreferences> readPreferences({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return CommandPaletteDisplayPreferences(workspaceId: workspaceId);
    }
    final preferences = CommandPaletteDisplayPreferences.fromJson(value);
    return preferences.workspaceId.isEmpty
        ? CommandPaletteDisplayPreferences(
            workspaceId: workspaceId,
            defaultCategory: preferences.defaultCategory,
            showCategoryFilters: preferences.showCategoryFilters,
            showRecentCommands: preferences.showRecentCommands,
            updatedAt: preferences.updatedAt,
          )
        : preferences;
  }

  Future<CommandPaletteDisplayPreferences> savePreferences(
    CommandPaletteDisplayPreferences preferences,
  ) async {
    await _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: preferences.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: preferences.workspaceId,
    );
    return preferences;
  }

  Future<bool> clearPreferences({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

List<AppCommandId> _commandIdsFromJson(Object? value) {
  if (value is! List) {
    return const <AppCommandId>[];
  }
  final ids = <AppCommandId>[];
  for (final item in value) {
    final id = _commandIdFromName('$item');
    if (id != null && !ids.contains(id)) {
      ids.add(id);
    }
  }
  return List<AppCommandId>.unmodifiable(ids);
}

AppCommandId? _commandIdFromName(String name) {
  for (final id in AppCommandId.values) {
    if (id.name == name) {
      return id;
    }
  }
  return null;
}

AppCommandCategory? _commandCategoryFromWireValue(String value) {
  for (final category in AppCommandCategory.values) {
    if (category.wireValue == value) {
      return category;
    }
  }
  return null;
}
