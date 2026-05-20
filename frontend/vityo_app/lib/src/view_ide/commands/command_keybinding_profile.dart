import '../foundation/foundation.dart';
import 'app_commands.dart';

class CommandKeybindingOverride {
  const CommandKeybindingOverride({
    required this.commandId,
    this.shortcuts = const <AppCommandShortcutSpec>[],
  });

  factory CommandKeybindingOverride.fromJson(Map<String, Object?> json) {
    final commandId =
        _commandIdFromName(json['commandId'] as String? ?? '') ??
        AppCommandId.openSettings;
    return CommandKeybindingOverride(
      commandId: commandId,
      shortcuts: _shortcutsFromJson(json['shortcuts']),
    );
  }

  final AppCommandId commandId;
  final List<AppCommandShortcutSpec> shortcuts;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'commandId': commandId.name,
      'shortcuts': shortcuts
          .map((shortcut) => shortcut.toJson())
          .toList(growable: false),
    };
  }
}

class CommandKeybindingProfile {
  CommandKeybindingProfile({
    required this.workspaceId,
    Map<AppCommandId, CommandKeybindingOverride> overrides =
        const <AppCommandId, CommandKeybindingOverride>{},
    this.updatedAt,
  }) : overrides = Map<AppCommandId, CommandKeybindingOverride>.unmodifiable(
         overrides,
       );

  factory CommandKeybindingProfile.fromJson(Map<String, Object?> json) {
    final overrides = <AppCommandId, CommandKeybindingOverride>{};
    final rawOverrides = json['overrides'];
    if (rawOverrides is List) {
      for (final rawOverride in rawOverrides) {
        if (rawOverride is! Map) {
          continue;
        }
        final overrideJson = Map<String, Object?>.from(rawOverride);
        final commandId = _commandIdFromName(
          overrideJson['commandId'] as String? ?? '',
        );
        if (commandId == null) {
          continue;
        }
        final override = CommandKeybindingOverride(
          commandId: commandId,
          shortcuts: _shortcutsFromJson(overrideJson['shortcuts']),
        );
        overrides[override.commandId] = override;
      }
    }
    return CommandKeybindingProfile(
      workspaceId: json['workspaceId'] as String? ?? '',
      overrides: overrides,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final Map<AppCommandId, CommandKeybindingOverride> overrides;
  final DateTime? updatedAt;

  bool hasOverrideFor(AppCommandId commandId) {
    return overrides.containsKey(commandId);
  }

  List<AppCommandShortcutSpec> effectiveShortcutsFor(
    AppCommandDescriptor descriptor,
  ) {
    return overrides[descriptor.id]?.shortcuts ?? descriptor.shortcuts;
  }

  CommandKeybindingProfile replaceOverride(
    CommandKeybindingOverride override, {
    DateTime? updatedAt,
  }) {
    return CommandKeybindingProfile(
      workspaceId: workspaceId,
      overrides: <AppCommandId, CommandKeybindingOverride>{
        ...overrides,
        override.commandId: override,
      },
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  CommandKeybindingProfile clearOverride(
    AppCommandId commandId, {
    DateTime? updatedAt,
  }) {
    final next = <AppCommandId, CommandKeybindingOverride>{...overrides}
      ..remove(commandId);
    return CommandKeybindingProfile(
      workspaceId: workspaceId,
      overrides: next,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  Map<String, Object?> toJson() {
    final sortedOverrides = overrides.values.toList(growable: false)
      ..sort((a, b) => a.commandId.name.compareTo(b.commandId.name));
    return <String, Object?>{
      'workspaceId': workspaceId,
      'overrides': sortedOverrides
          .map((override) => override.toJson())
          .toList(growable: false),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class CommandKeybindingConflict {
  const CommandKeybindingConflict({
    required this.signature,
    required this.commandIds,
    this.shortcutLabel = '',
    this.commandPreviews = const <CommandKeybindingConflictCommandPreview>[],
  });

  final String signature;
  final List<AppCommandId> commandIds;
  final String shortcutLabel;
  final List<CommandKeybindingConflictCommandPreview> commandPreviews;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'signature': signature,
      if (shortcutLabel.isNotEmpty) 'shortcutLabel': shortcutLabel,
      'commandIds': commandIds.map((commandId) => commandId.name).toList(),
      'commandPreviews': commandPreviews
          .map((preview) => preview.toJson())
          .toList(growable: false),
    };
  }
}

class CommandKeybindingConflictCommandPreview {
  const CommandKeybindingConflictCommandPreview({
    required this.commandId,
    required this.label,
    required this.category,
    required this.hasOverride,
  });

  final AppCommandId commandId;
  final String label;
  final AppCommandCategory category;
  final bool hasOverride;

  String get sourceLabel => hasOverride ? 'override' : 'default';

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'commandId': commandId.name,
      'label': label,
      'category': category.wireValue,
      'source': sourceLabel,
      'hasOverride': hasOverride,
    };
  }
}

class CommandKeybindingConflictReview {
  const CommandKeybindingConflictReview({
    this.conflicts = const <CommandKeybindingConflict>[],
  });

  final List<CommandKeybindingConflict> conflicts;

  bool get hasConflicts => conflicts.isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'hasConflicts': hasConflicts,
      'conflicts': conflicts
          .map((conflict) => conflict.toJson())
          .toList(growable: false),
    };
  }
}

class CommandKeybindingResolver {
  const CommandKeybindingResolver._();

  static List<AppCommandShortcutSpec> effectiveShortcutsFor({
    required AppCommandDescriptor descriptor,
    required CommandKeybindingProfile profile,
  }) {
    return profile.effectiveShortcutsFor(descriptor);
  }

  static CommandKeybindingConflictReview reviewConflicts({
    required CommandKeybindingProfile profile,
    Iterable<AppCommandDescriptor>? descriptors,
  }) {
    final commandsBySignature = <String, List<AppCommandId>>{};
    final descriptorList =
        (descriptors ?? StyioCommandRegistry.commands).toList(growable: false);
    final descriptorsById = <AppCommandId, AppCommandDescriptor>{
      for (final descriptor in descriptorList) descriptor.id: descriptor,
    };
    final shortcutLabelsBySignature = <String, String>{};
    for (final descriptor in descriptorList) {
      for (final shortcut in profile.effectiveShortcutsFor(descriptor)) {
        final signature = commandShortcutSignature(shortcut);
        if (signature.isEmpty) {
          continue;
        }
        shortcutLabelsBySignature.putIfAbsent(
          signature,
          () => commandShortcutDisplayLabel(shortcut),
        );
        commandsBySignature
            .putIfAbsent(signature, () => <AppCommandId>[])
            .add(descriptor.id);
      }
    }
    final conflicts = <CommandKeybindingConflict>[];
    for (final entry in commandsBySignature.entries) {
      final commandIds = entry.value.toSet().toList(growable: false);
      if (commandIds.length < 2) {
        continue;
      }
      conflicts.add(
        CommandKeybindingConflict(
          signature: entry.key,
          shortcutLabel: shortcutLabelsBySignature[entry.key] ?? entry.key,
          commandIds: commandIds,
          commandPreviews: <CommandKeybindingConflictCommandPreview>[
            for (final commandId in commandIds)
              if (descriptorsById[commandId] != null)
                CommandKeybindingConflictCommandPreview(
                  commandId: commandId,
                  label: descriptorsById[commandId]!.label,
                  category: descriptorsById[commandId]!.category,
                  hasOverride: profile.hasOverrideFor(commandId),
                ),
          ],
        ),
      );
    }
    conflicts.sort((a, b) => a.signature.compareTo(b.signature));
    return CommandKeybindingConflictReview(conflicts: conflicts);
  }
}

class CommandKeybindingProfileStore {
  CommandKeybindingProfileStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'interaction.command-palette.keybindings',
             layer: 'interaction',
             stateFamily: 'command-palette-keybindings',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const CommandKeybindingProfileStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName =
      'interaction.command-palette.keybindings';
  static const String _key = 'keybinding-profile';

  final FoundationDataStoreOwner _owner;

  Future<CommandKeybindingProfile> readProfile({
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
      return CommandKeybindingProfile(workspaceId: workspaceId);
    }
    final profile = CommandKeybindingProfile.fromJson(value);
    return profile.workspaceId.isEmpty
        ? CommandKeybindingProfile(
            workspaceId: workspaceId,
            overrides: profile.overrides,
            updatedAt: profile.updatedAt,
          )
        : profile;
  }

  Future<CommandKeybindingProfile> saveProfile(
    CommandKeybindingProfile profile,
  ) async {
    await _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: profile.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: profile.workspaceId,
    );
    return profile;
  }

  Future<bool> clearProfile({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

String commandShortcutSignature(AppCommandShortcutSpec shortcut) {
  final parts = <String>[
    if (shortcut.control) 'ctrl',
    if (shortcut.meta) 'meta',
    if (shortcut.shift) 'shift',
    shortcut.key.trim(),
  ];
  return parts.where((part) => part.isNotEmpty).join('+');
}

String commandShortcutDisplayLabel(AppCommandShortcutSpec shortcut) {
  final parts = <String>[
    if (shortcut.control) 'Ctrl',
    if (shortcut.meta) 'Cmd',
    if (shortcut.shift) 'Shift',
    shortcut.key.trim(),
  ];
  return parts.where((part) => part.isNotEmpty).join('+');
}

AppCommandShortcutSpec? parseCommandShortcutExpression(String expression) {
  final tokens = expression
      .split('+')
      .map((token) => token.trim())
      .where((token) => token.isNotEmpty)
      .toList(growable: false);
  var control = false;
  var meta = false;
  var shift = false;
  var key = '';
  for (final token in tokens) {
    switch (token.toLowerCase()) {
      case 'ctrl':
      case 'control':
        control = true;
      case 'cmd':
      case 'command':
      case 'meta':
        meta = true;
      case 'shift':
        shift = true;
      default:
        key = token;
    }
  }
  if (key.isEmpty) {
    return null;
  }
  return AppCommandShortcutSpec(
    key,
    control: control,
    meta: meta,
    shift: shift,
  );
}

List<AppCommandShortcutSpec> _shortcutsFromJson(Object? value) {
  if (value is! List) {
    return const <AppCommandShortcutSpec>[];
  }
  final shortcuts = <AppCommandShortcutSpec>[];
  for (final rawShortcut in value) {
    if (rawShortcut is! Map) {
      continue;
    }
    final shortcut = _shortcutFromJson(Map<String, Object?>.from(rawShortcut));
    if (shortcut.key.isNotEmpty) {
      shortcuts.add(shortcut);
    }
  }
  return List<AppCommandShortcutSpec>.unmodifiable(shortcuts);
}

AppCommandShortcutSpec _shortcutFromJson(Map<String, Object?> json) {
  return AppCommandShortcutSpec(
    json['key'] as String? ?? '',
    control: json['control'] as bool? ?? false,
    meta: json['meta'] as bool? ?? false,
    shift: json['shift'] as bool? ?? false,
  );
}

AppCommandId? _commandIdFromName(String name) {
  for (final commandId in AppCommandId.values) {
    if (commandId.name == name) {
      return commandId;
    }
  }
  return null;
}
