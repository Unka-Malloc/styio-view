import 'dart:convert';

enum ModuleKind {
  core,
  optional,
}

enum ModuleSlot {
  shell,
  editor,
  runtimeSurface,
  agentSurface,
  theme,
  localRuntime,
  cloudRuntime,
  debugTools,
}

extension ModuleKindX on ModuleKind {
  String get wireValue {
    switch (this) {
      case ModuleKind.core:
        return 'core';
      case ModuleKind.optional:
        return 'optional';
    }
  }
}

extension ModuleSlotX on ModuleSlot {
  String get wireValue {
    switch (this) {
      case ModuleSlot.shell:
        return 'shell';
      case ModuleSlot.editor:
        return 'editor';
      case ModuleSlot.runtimeSurface:
        return 'runtimeSurface';
      case ModuleSlot.agentSurface:
        return 'agentSurface';
      case ModuleSlot.theme:
        return 'theme';
      case ModuleSlot.localRuntime:
        return 'localRuntime';
      case ModuleSlot.cloudRuntime:
        return 'cloudRuntime';
      case ModuleSlot.debugTools:
        return 'debugTools';
    }
  }
}

ModuleKind moduleKindFromWireValue(String value) {
  for (final kind in ModuleKind.values) {
    if (kind.wireValue == value) {
      return kind;
    }
  }
  throw FormatException('Unknown module kind: $value');
}

ModuleSlot moduleSlotFromWireValue(String value) {
  for (final slot in ModuleSlot.values) {
    if (slot.wireValue == value) {
      return slot;
    }
  }
  throw FormatException('Unknown module slot: $value');
}

class ModuleManifest {
  const ModuleManifest({
    required this.moduleId,
    required this.displayName,
    required this.version,
    required this.kind,
    required this.slot,
    required this.description,
    required this.enabledByDefault,
    required this.entrypoint,
    required this.distributionPolicyRef,
    required this.capabilityFlags,
  });

  final String moduleId;
  final String displayName;
  final String version;
  final ModuleKind kind;
  final ModuleSlot slot;
  final String description;
  final bool enabledByDefault;
  final String entrypoint;
  final String distributionPolicyRef;
  final Map<String, bool> capabilityFlags;

  factory ModuleManifest.fromJson(Map<String, dynamic> json) {
    final flags = <String, bool>{};
    final rawFlags =
        Map<String, dynamic>.from(json['capabilityFlags'] as Map? ?? {});
    for (final entry in rawFlags.entries) {
      flags[entry.key] = entry.value == true;
    }

    return ModuleManifest(
      moduleId: json['moduleId'] as String,
      displayName: json['displayName'] as String,
      version: json['version'] as String,
      kind: moduleKindFromWireValue(json['kind'] as String),
      slot: moduleSlotFromWireValue(json['slot'] as String),
      description: json['description'] as String,
      enabledByDefault: json['enabledByDefault'] as bool? ?? false,
      entrypoint: json['entrypoint'] as String,
      distributionPolicyRef: json['distributionPolicyRef'] as String,
      capabilityFlags: flags,
    );
  }

  static ModuleManifest parse(String source) {
    return ModuleManifest.fromJson(
      Map<String, dynamic>.from(jsonDecode(source) as Map),
    );
  }
}
