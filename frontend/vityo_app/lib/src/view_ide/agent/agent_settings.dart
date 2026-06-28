/// Vityo Settings Schema and Profile Snapshot.
///
/// Key invariants:
/// - Settings are schema-owned, migratable, and serializable.
/// - Profile is local-first; sync is optional.
/// - Secret fields are redacted in display projections and Agent context.
/// - Settings/profile snapshot can be safely consumed by Agent context.
library;

// ── Settings Schema ───────────────────────────────────────────────

/// Schema version for settings migration tracking.
class VityoSettingsSchema {
  const VityoSettingsSchema({
    this.schemaVersion = 1,
    this.migrationsApplied = const <String>[],
  });

  /// Current schema version.
  final int schemaVersion;

  /// Names of migrations that have been applied.
  final List<String> migrationsApplied;

  static const int currentSchemaVersion = 1;

  Map<String, Object?> toJson() => <String, Object?>{
        'schemaVersion': schemaVersion,
        'migrationsApplied': migrationsApplied,
      };

  factory VityoSettingsSchema.fromJson(Map<String, Object?> json) {
    return VityoSettingsSchema(
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      migrationsApplied:
          (json['migrationsApplied'] as List?)
              ?.whereType<String>()
              .toList(growable: false) ??
              const <String>[],
    );
  }

  /// Whether a migration from [fromVersion] to [currentSchemaVersion]
  /// is needed.
  bool needsMigration(int fromVersion) =>
      fromVersion < currentSchemaVersion;

  static const VityoSettingsSchema defaults = VityoSettingsSchema();
}

// ── IDE Settings ──────────────────────────────────────────────────

/// Editor settings.
class EditorSettings {
  const EditorSettings({
    this.fontSize = 14,
    this.lineHeight = 1.5,
    this.tabSize = 2,
    this.insertSpaces = true,
    this.wordWrap = false,
    this.rulers = const <int>[],
    this.minimapEnabled = false,
    this.visualSubstitutionEnabled = true,
  });

  final int fontSize;
  final double lineHeight;
  final int tabSize;
  final bool insertSpaces;
  final bool wordWrap;
  final List<int> rulers;
  final bool minimapEnabled;

  /// Toggle for Styio visual substitution glyphs.
  /// Does NOT modify the Source Buffer.
  final bool visualSubstitutionEnabled;

  EditorSettings copyWith({
    int? fontSize,
    double? lineHeight,
    int? tabSize,
    bool? insertSpaces,
    bool? wordWrap,
    List<int>? rulers,
    bool? minimapEnabled,
    bool? visualSubstitutionEnabled,
  }) {
    return EditorSettings(
      fontSize: fontSize ?? this.fontSize,
      lineHeight: lineHeight ?? this.lineHeight,
      tabSize: tabSize ?? this.tabSize,
      insertSpaces: insertSpaces ?? this.insertSpaces,
      wordWrap: wordWrap ?? this.wordWrap,
      rulers: rulers ?? this.rulers,
      minimapEnabled: minimapEnabled ?? this.minimapEnabled,
      visualSubstitutionEnabled:
          visualSubstitutionEnabled ?? this.visualSubstitutionEnabled,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
        'fontSize': fontSize,
        'lineHeight': lineHeight,
        'tabSize': tabSize,
        'insertSpaces': insertSpaces,
        'wordWrap': wordWrap,
        'rulers': rulers,
        'minimapEnabled': minimapEnabled,
        'visualSubstitutionEnabled': visualSubstitutionEnabled,
      };

  factory EditorSettings.fromJson(Map<String, Object?> json) {
    return EditorSettings(
      fontSize: json['fontSize'] as int? ?? 14,
      lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.5,
      tabSize: json['tabSize'] as int? ?? 2,
      insertSpaces: json['insertSpaces'] as bool? ?? true,
      wordWrap: json['wordWrap'] as bool? ?? false,
      rulers: (json['rulers'] as List?)
              ?.whereType<int>()
              .toList(growable: false) ??
          const <int>[],
      minimapEnabled: json['minimapEnabled'] as bool? ?? false,
      visualSubstitutionEnabled:
          json['visualSubstitutionEnabled'] as bool? ?? true,
    );
  }

  static const EditorSettings defaults = EditorSettings();
}

/// Theme settings.
class ThemeSettings {
  const ThemeSettings({
    this.themeId = 'graphite',
    this.contrastMode = 'normal',
    this.accentColor = '#F4C76A',
    this.editorFontFamily = '',
    this.uiFontFamily = '',
  });

  final String themeId;
  final String contrastMode;
  final String accentColor;
  final String editorFontFamily;
  final String uiFontFamily;

  Map<String, Object?> toJson() => <String, Object?>{
        'themeId': themeId,
        'contrastMode': contrastMode,
        'accentColor': accentColor,
        'editorFontFamily': editorFontFamily,
        'uiFontFamily': uiFontFamily,
      };

  factory ThemeSettings.fromJson(Map<String, Object?> json) {
    return ThemeSettings(
      themeId: json['themeId'] as String? ?? 'graphite',
      contrastMode: json['contrastMode'] as String? ?? 'normal',
      accentColor: json['accentColor'] as String? ?? '#F4C76A',
      editorFontFamily: json['editorFontFamily'] as String? ?? '',
      uiFontFamily: json['uiFontFamily'] as String? ?? '',
    );
  }

  static const ThemeSettings defaults = ThemeSettings();
}

/// Agent provider settings (keys are NEVER stored in plain config).
class AgentSettings {
  const AgentSettings({
    this.providerMode = 'local-only',
    this.endpointBaseUrl = '',
    this.endpointModel = '',
    this.apiKeyEnvironmentName = 'OPENAI_API_KEY',
    this.providerProtocol = 'openai-compatible',
  });

  /// One of: 'local-only', 'provider-missing', 'openai-compatible'.
  final String providerMode;

  /// Base URL for the OpenAI-compatible endpoint (no key).
  final String endpointBaseUrl;

  /// Model name for the provider endpoint.
  final String endpointModel;

  /// Environment variable name that holds the API key.
  /// The actual key value is NEVER stored in settings.
  final String apiKeyEnvironmentName;

  /// Protocol identifier.
  final String providerProtocol;

  /// Whether a real provider is configured.
  bool get hasProvider =>
      providerMode == 'openai-compatible' && endpointBaseUrl.isNotEmpty;

  /// Whether in local-only mode.
  bool get isLocalOnly => providerMode == 'local-only';

  /// Whether a provider is configured but missing/offline.
  bool get isProviderMissing => providerMode == 'provider-missing';

  /// Display-safe projection — redacts secret references.
  Map<String, Object?> toDisplayJson() => <String, Object?>{
        'providerMode': providerMode,
        'endpointBaseUrl': endpointBaseUrl,
        'endpointModel': endpointModel,
        'apiKeySource': apiKeyEnvironmentName,
        'apiKeyValue': '[REDACTED — read from $apiKeyEnvironmentName]',
        'providerProtocol': providerProtocol,
        'hasProvider': hasProvider,
        'isLocalOnly': isLocalOnly,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'providerMode': providerMode,
        'endpointBaseUrl': endpointBaseUrl,
        'endpointModel': endpointModel,
        'apiKeyEnvironmentName': apiKeyEnvironmentName,
        'providerProtocol': providerProtocol,
      };

  factory AgentSettings.fromJson(Map<String, Object?> json) {
    return AgentSettings(
      providerMode: json['providerMode'] as String? ?? 'local-only',
      endpointBaseUrl: json['endpointBaseUrl'] as String? ?? '',
      endpointModel: json['endpointModel'] as String? ?? '',
      apiKeyEnvironmentName:
          json['apiKeyEnvironmentName'] as String? ?? 'OPENAI_API_KEY',
      providerProtocol:
          json['providerProtocol'] as String? ?? 'openai-compatible',
    );
  }

  static const AgentSettings localOnly = AgentSettings();

  static const AgentSettings providerMissing = AgentSettings(
    providerMode: 'provider-missing',
  );
}

/// Complete Vityo settings snapshot.
class VityoSettingsSnapshot {
  const VityoSettingsSnapshot({
    this.schema = VityoSettingsSchema.defaults,
    this.editor = EditorSettings.defaults,
    this.theme = ThemeSettings.defaults,
    this.agent = AgentSettings.localOnly,
    this.lastModifiedIso8601 = '',
  });

  final VityoSettingsSchema schema;
  final EditorSettings editor;
  final ThemeSettings theme;
  final AgentSettings agent;
  final String lastModifiedIso8601;

  static const VityoSettingsSnapshot defaults = VityoSettingsSnapshot();

  VityoSettingsSnapshot copyWith({
    VityoSettingsSchema? schema,
    EditorSettings? editor,
    ThemeSettings? theme,
    AgentSettings? agent,
    String? lastModifiedIso8601,
  }) {
    return VityoSettingsSnapshot(
      schema: schema ?? this.schema,
      editor: editor ?? this.editor,
      theme: theme ?? this.theme,
      agent: agent ?? this.agent,
      lastModifiedIso8601: lastModifiedIso8601 ?? this.lastModifiedIso8601,
    );
  }

  /// Display-safe projection for Agent context.
  /// Secret fields are redacted.
  Map<String, Object?> toAgentSafeJson() => <String, Object?>{
        'schema': schema.toJson(),
        'editor': editor.toJson(),
        'theme': theme.toJson(),
        'agent': agent.toDisplayJson(),
        'lastModifiedIso8601': lastModifiedIso8601,
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': schema.toJson(),
        'editor': editor.toJson(),
        'theme': theme.toJson(),
        'agent': agent.toJson(),
        'lastModifiedIso8601': lastModifiedIso8601,
      };

  factory VityoSettingsSnapshot.fromJson(Map<String, Object?> json) {
    return VityoSettingsSnapshot(
      schema: json['schema'] != null
          ? VityoSettingsSchema.fromJson(
              Map<String, Object?>.from(json['schema'] as Map))
          : const VityoSettingsSchema(),
      editor: json['editor'] != null
          ? EditorSettings.fromJson(
              Map<String, Object?>.from(json['editor'] as Map))
          : EditorSettings.defaults,
      theme: json['theme'] != null
          ? ThemeSettings.fromJson(
              Map<String, Object?>.from(json['theme'] as Map))
          : ThemeSettings.defaults,
      agent: json['agent'] != null
          ? AgentSettings.fromJson(
              Map<String, Object?>.from(json['agent'] as Map))
          : AgentSettings.localOnly,
      lastModifiedIso8601: json['lastModifiedIso8601'] as String? ?? '',
    );
  }
}

// ── Profile Snapshot ───────────────────────────────────────────────

/// Local-first profile snapshot. Sync is optional.
class VityoProfileSnapshot {
  const VityoProfileSnapshot({
    this.profileId = 'default',
    this.displayName = 'Default',
    this.createdAtIso8601 = '',
    this.lastSyncedAtIso8601 = '',
    this.syncEnabled = false,
    this.syncProvider = '',
    this.settings = VityoSettingsSnapshot.defaults,
  });

  final String profileId;
  final String displayName;
  final String createdAtIso8601;
  final String lastSyncedAtIso8601;
  final bool syncEnabled;
  final String syncProvider;
  final VityoSettingsSnapshot settings;

  /// Whether the profile works in full local mode.
  bool get isLocalOnly => !syncEnabled;

  /// Whether sync is configured but not currently connected.
  bool get isSyncMissing => syncEnabled && syncProvider.isEmpty;

  VityoProfileSnapshot copyWith({
    String? profileId,
    String? displayName,
    String? lastSyncedAtIso8601,
    bool? syncEnabled,
    String? syncProvider,
    VityoSettingsSnapshot? settings,
  }) {
    return VityoProfileSnapshot(
      profileId: profileId ?? this.profileId,
      displayName: displayName ?? this.displayName,
      createdAtIso8601: createdAtIso8601,
      lastSyncedAtIso8601:
          lastSyncedAtIso8601 ?? this.lastSyncedAtIso8601,
      syncEnabled: syncEnabled ?? this.syncEnabled,
      syncProvider: syncProvider ?? this.syncProvider,
      settings: settings ?? this.settings,
    );
  }

  /// Agent-safe projection — redacts secrets.
  Map<String, Object?> toAgentSafeJson() => <String, Object?>{
        'profileId': profileId,
        'displayName': displayName,
        'syncEnabled': syncEnabled,
        'syncProvider': syncProvider,
        'isLocalOnly': isLocalOnly,
        'settings': settings.toAgentSafeJson(),
      };

  Map<String, Object?> toJson() => <String, Object?>{
        'profileId': profileId,
        'displayName': displayName,
        'createdAtIso8601': createdAtIso8601,
        'lastSyncedAtIso8601': lastSyncedAtIso8601,
        'syncEnabled': syncEnabled,
        'syncProvider': syncProvider,
        'settings': settings.toJson(),
      };

  factory VityoProfileSnapshot.fromJson(Map<String, Object?> json) {
    return VityoProfileSnapshot(
      profileId: json['profileId'] as String? ?? 'default',
      displayName: json['displayName'] as String? ?? 'Default',
      createdAtIso8601: json['createdAtIso8601'] as String? ?? '',
      lastSyncedAtIso8601: json['lastSyncedAtIso8601'] as String? ?? '',
      syncEnabled: json['syncEnabled'] as bool? ?? false,
      syncProvider: json['syncProvider'] as String? ?? '',
      settings: json['settings'] != null
          ? VityoSettingsSnapshot.fromJson(
              Map<String, Object?>.from(json['settings'] as Map))
          : VityoSettingsSnapshot.defaults,
    );
  }

  static const VityoProfileSnapshot defaultLocal = VityoProfileSnapshot();
}
