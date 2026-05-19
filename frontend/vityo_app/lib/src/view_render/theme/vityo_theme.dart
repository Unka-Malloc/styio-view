import 'package:flutter/material.dart';

enum VityoThemePreset { parchment, graphite }

class VityoThemeOverride {
  const VityoThemeOverride({
    this.canvas,
    this.panel,
    this.ink,
    this.accent,
    this.muted,
  });

  final Color? canvas;
  final Color? panel;
  final Color? ink;
  final Color? accent;
  final Color? muted;

  VityoThemeOverride copyWith({
    Color? canvas,
    Color? panel,
    Color? ink,
    Color? accent,
    Color? muted,
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
      if (canvas != null) 'canvas': canvas!.toARGB32(),
      if (panel != null) 'panel': panel!.toARGB32(),
      if (ink != null) 'ink': ink!.toARGB32(),
      if (accent != null) 'accent': accent!.toARGB32(),
      if (muted != null) 'muted': muted!.toARGB32(),
    };
  }

  factory VityoThemeOverride.fromJson(Map<String, Object?> json) {
    return VityoThemeOverride(
      canvas: _colorFromJson(json['canvas']),
      panel: _colorFromJson(json['panel']),
      ink: _colorFromJson(json['ink']),
      accent: _colorFromJson(json['accent']),
      muted: _colorFromJson(json['muted']),
    );
  }
}

class VityoTheme {
  static ThemeData light({
    VityoThemePreset preset = VityoThemePreset.parchment,
    VityoThemeOverride overrides = const VityoThemeOverride(),
  }) {
    final palette = _paletteForPreset(preset);
    final canvas = overrides.canvas ?? palette.canvas;
    final panel = overrides.panel ?? palette.panel;
    final ink = overrides.ink ?? palette.ink;
    final accent = overrides.accent ?? palette.accent;
    final muted = overrides.muted ?? palette.muted;

    final colorScheme =
        ColorScheme.fromSeed(
          seedColor: accent,
          brightness: Brightness.light,
        ).copyWith(
          primary: accent,
          surface: panel,
          onSurface: ink,
          secondary: const Color(0xFFD4CDC1),
        );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvas,
      cardColor: panel,
      dividerColor: const Color(0xFFE1D9CA),
      textTheme: TextTheme(
        headlineMedium: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w700,
          color: ink,
        ),
        titleMedium: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
        bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: ink),
        bodySmall: TextStyle(fontSize: 12, height: 1.4, color: muted),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide.none,
        selectedColor: const Color(0xFFE6E1D7),
        backgroundColor: const Color(0xFFF1ECE3),
        labelStyle: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.68),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }
}

class _VityoThemePalette {
  const _VityoThemePalette({
    required this.canvas,
    required this.panel,
    required this.ink,
    required this.accent,
    required this.muted,
  });

  final Color canvas;
  final Color panel;
  final Color ink;
  final Color accent;
  final Color muted;
}

_VityoThemePalette _paletteForPreset(VityoThemePreset preset) {
  switch (preset) {
    case VityoThemePreset.parchment:
      return const _VityoThemePalette(
        canvas: Color(0xFFF4F1EA),
        panel: Color(0xFFF9F6EF),
        ink: Color(0xFF2B2624),
        accent: Color(0xFF5668A6),
        muted: Color(0xFF8B847B),
      );
    case VityoThemePreset.graphite:
      return const _VityoThemePalette(
        canvas: Color(0xFFEDEFF2),
        panel: Color(0xFFFFFFFF),
        ink: Color(0xFF1E252B),
        accent: Color(0xFF2F6F73),
        muted: Color(0xFF62717C),
      );
  }
}

Color? _colorFromJson(Object? raw) {
  if (raw is int) {
    return Color(raw);
  }
  if (raw is String) {
    final normalized = raw.startsWith('#') ? raw.substring(1) : raw;
    final parsed = int.tryParse(normalized, radix: 16);
    if (parsed == null) {
      return null;
    }
    return Color(normalized.length <= 6 ? (0xFF000000 | parsed) : parsed);
  }
  return null;
}
