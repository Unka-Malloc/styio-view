import '../foundation/foundation.dart';
import '../platform/platform_target.dart';
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

enum CommandShortcutCaptureDecision {
  allowed,
  empty,
  reserved,
  needsModifierHint,
}

extension CommandShortcutCaptureDecisionX on CommandShortcutCaptureDecision {
  String get wireValue {
    return switch (this) {
      CommandShortcutCaptureDecision.allowed => 'allowed',
      CommandShortcutCaptureDecision.empty => 'empty',
      CommandShortcutCaptureDecision.reserved => 'reserved',
      CommandShortcutCaptureDecision.needsModifierHint => 'needs-modifier-hint',
    };
  }
}

class CommandShortcutCapturePolicyResult {
  const CommandShortcutCapturePolicyResult({
    required this.decision,
    required this.message,
    this.shortcut,
    this.accessibilityHint = '',
  });

  final CommandShortcutCaptureDecision decision;
  final String message;
  final AppCommandShortcutSpec? shortcut;
  final String accessibilityHint;

  bool get allowed =>
      decision == CommandShortcutCaptureDecision.allowed ||
      decision == CommandShortcutCaptureDecision.needsModifierHint;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'decision': decision.wireValue,
      'allowed': allowed,
      'message': message,
      if (shortcut != null) 'shortcut': shortcut!.toJson(),
      if (accessibilityHint.isNotEmpty) 'accessibilityHint': accessibilityHint,
    };
  }
}

enum CommandShortcutHostPolicyKind {
  generic,
  macosDesktop,
  windowsLinuxDesktop,
  webBrowser,
  mobile,
}

extension CommandShortcutHostPolicyKindX on CommandShortcutHostPolicyKind {
  String get wireValue {
    return switch (this) {
      CommandShortcutHostPolicyKind.generic => 'generic',
      CommandShortcutHostPolicyKind.macosDesktop => 'macos-desktop',
      CommandShortcutHostPolicyKind.windowsLinuxDesktop =>
        'windows-linux-desktop',
      CommandShortcutHostPolicyKind.webBrowser => 'web-browser',
      CommandShortcutHostPolicyKind.mobile => 'mobile',
    };
  }
}

class CommandShortcutHostPolicy {
  const CommandShortcutHostPolicy({
    required this.kind,
    required this.reservedSignatures,
    required this.message,
  });

  factory CommandShortcutHostPolicy.forPlatform(PlatformTarget platformTarget) {
    return switch (platformTarget) {
      PlatformTarget.macos => CommandShortcutHostPolicy.macosDesktop,
      PlatformTarget.windows ||
      PlatformTarget.linux => CommandShortcutHostPolicy.windowsLinuxDesktop,
      PlatformTarget.web => CommandShortcutHostPolicy.webBrowser,
      PlatformTarget.android ||
      PlatformTarget.ios => CommandShortcutHostPolicy.mobile,
      PlatformTarget.unknown => CommandShortcutHostPolicy.generic,
    };
  }

  static const CommandShortcutHostPolicy generic = CommandShortcutHostPolicy(
    kind: CommandShortcutHostPolicyKind.generic,
    reservedSignatures: <String>{
      'ctrl+tab',
      'ctrl+shift+tab',
      'meta+tab',
      'meta+shift+tab',
      'meta+space',
      'meta+keyQ',
    },
    message: 'Generic host policy protects common system shortcuts.',
  );

  static const CommandShortcutHostPolicy macosDesktop =
      CommandShortcutHostPolicy(
        kind: CommandShortcutHostPolicyKind.macosDesktop,
        reservedSignatures: <String>{
          'meta+tab',
          'meta+shift+tab',
          'meta+space',
          'meta+keyQ',
          'meta+keyW',
        },
        message: 'macOS host policy protects application and system shortcuts.',
      );

  static const CommandShortcutHostPolicy
  windowsLinuxDesktop = CommandShortcutHostPolicy(
    kind: CommandShortcutHostPolicyKind.windowsLinuxDesktop,
    reservedSignatures: <String>{
      'ctrl+tab',
      'ctrl+shift+tab',
      'ctrl+keyW',
      'ctrl+keyL',
    },
    message:
        'Windows/Linux host policy protects tab navigation and shell/browser shortcuts.',
  );

  static const CommandShortcutHostPolicy webBrowser = CommandShortcutHostPolicy(
    kind: CommandShortcutHostPolicyKind.webBrowser,
    reservedSignatures: <String>{
      'ctrl+tab',
      'ctrl+shift+tab',
      'ctrl+keyL',
      'ctrl+keyR',
      'ctrl+keyW',
      'meta+tab',
      'meta+shift+tab',
      'meta+keyL',
      'meta+keyR',
      'meta+keyW',
    },
    message: 'Web browser host policy protects browser-owned shortcuts.',
  );

  static const CommandShortcutHostPolicy mobile = CommandShortcutHostPolicy(
    kind: CommandShortcutHostPolicyKind.mobile,
    reservedSignatures: <String>{'meta+space'},
    message:
        'Mobile host policy keeps external keyboard shortcuts conservative.',
  );

  final CommandShortcutHostPolicyKind kind;
  final Set<String> reservedSignatures;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'reservedSignatures': reservedSignatures.toList(growable: false),
      'message': message,
    };
  }
}

class CommandShortcutCapturePolicy {
  const CommandShortcutCapturePolicy({
    this.hostPolicy = CommandShortcutHostPolicy.generic,
  });

  factory CommandShortcutCapturePolicy.forPlatform(
    PlatformTarget platformTarget,
  ) {
    return CommandShortcutCapturePolicy(
      hostPolicy: CommandShortcutHostPolicy.forPlatform(platformTarget),
    );
  }

  final CommandShortcutHostPolicy hostPolicy;

  Set<String> get reservedSignatures => hostPolicy.reservedSignatures;

  CommandShortcutCapturePolicyResult evaluate(
    AppCommandShortcutSpec? shortcut,
  ) {
    if (shortcut == null || shortcut.key.trim().isEmpty) {
      return const CommandShortcutCapturePolicyResult(
        decision: CommandShortcutCaptureDecision.empty,
        message: 'Press a non-modifier key combination to capture a shortcut.',
        accessibilityHint:
            'Use Control or Command with a letter, function key, or punctuation key.',
      );
    }
    final signature = commandShortcutSignature(shortcut);
    if (reservedSignatures.contains(signature)) {
      return CommandShortcutCapturePolicyResult(
        decision: CommandShortcutCaptureDecision.reserved,
        shortcut: shortcut,
        message:
            '$signature is reserved by the ${hostPolicy.kind.wireValue} host policy.',
        accessibilityHint:
            '${hostPolicy.message} Choose a shortcut that does not override system navigation or application quit shortcuts.',
      );
    }
    if (!shortcut.control &&
        !shortcut.meta &&
        !shortcut.alt &&
        shortcut.key.toLowerCase().startsWith('key')) {
      return CommandShortcutCapturePolicyResult(
        decision: CommandShortcutCaptureDecision.needsModifierHint,
        shortcut: shortcut,
        message: '$signature can be saved, but a modifier is recommended.',
        accessibilityHint:
            'Letter-only shortcuts can conflict with text input. Prefer Control or Command plus the key.',
      );
    }
    return CommandShortcutCapturePolicyResult(
      decision: CommandShortcutCaptureDecision.allowed,
      shortcut: shortcut,
      message:
          '$signature is available for this ${hostPolicy.kind.wireValue} workspace profile.',
      accessibilityHint:
          'Shortcut capture uses physical key identity so the binding remains stable across keyboard layouts.',
    );
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
    final descriptorList = (descriptors ?? StyioCommandRegistry.commands)
        .toList(growable: false);
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
    if (shortcut.alt) 'alt',
    if (shortcut.shift) 'shift',
    shortcut.key.trim(),
  ];
  return parts.where((part) => part.isNotEmpty).join('+');
}

String commandShortcutDisplayLabel(AppCommandShortcutSpec shortcut) {
  final parts = <String>[
    if (shortcut.control) 'Ctrl',
    if (shortcut.meta) 'Cmd',
    if (shortcut.alt) 'Alt',
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
  var alt = false;
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
      case 'alt':
      case 'option':
        alt = true;
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
    alt: alt,
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
    alt: json['alt'] as bool? ?? false,
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
