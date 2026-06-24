enum VityoThemePreset { parchment, graphite }

class VityoThemeOverride {
  const VityoThemeOverride({
    this.canvas,
    this.panel,
    this.ink,
    this.accent,
    this.muted,
  });

  final int? canvas;
  final int? panel;
  final int? ink;
  final int? accent;
  final int? muted;

  VityoThemeOverride copyWith({
    int? canvas,
    int? panel,
    int? ink,
    int? accent,
    int? muted,
  }) {
    return VityoThemeOverride(
      canvas: canvas ?? this.canvas,
      panel: panel ?? this.panel,
      ink: ink ?? this.ink,
      accent: accent ?? this.accent,
      muted: muted ?? this.muted,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (canvas != null) 'canvas': canvas,
      if (panel != null) 'panel': panel,
      if (ink != null) 'ink': ink,
      if (accent != null) 'accent': accent,
      if (muted != null) 'muted': muted,
    };
  }

  factory VityoThemeOverride.fromJson(Map<String, Object?> json) {
    return VityoThemeOverride(
      canvas: json['canvas'] as int?,
      panel: json['panel'] as int?,
      ink: json['ink'] as int?,
      accent: json['accent'] as int?,
      muted: json['muted'] as int?,
    );
  }
}
