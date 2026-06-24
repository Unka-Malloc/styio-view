import 'package:flutter/material.dart';

import '../../view_ide/environment/configuration/vityo_theme_override.dart';

extension VityoThemeOverrideColorX on VityoThemeOverride {
  Color? get canvasColor => canvas != null ? Color(canvas!) : null;
  Color? get panelColor => panel != null ? Color(panel!) : null;
  Color? get inkColor => ink != null ? Color(ink!) : null;
  Color? get accentColor => accent != null ? Color(accent!) : null;
  Color? get mutedColor => muted != null ? Color(muted!) : null;
}

Color? _colorFromJson(Object? value) {
  if (value is int) return Color(value);
  return null;
}

class VityoTheme {
  static ThemeData light({
    VityoThemePreset preset = VityoThemePreset.parchment,
    VityoThemeOverride overrides = const VityoThemeOverride(),
  }) {
    final palette = _paletteForPreset(preset);
    final canvas = overrides.canvasColor ?? palette.canvas;
    final panel = overrides.panelColor ?? palette.panel;
    final ink = overrides.inkColor ?? palette.ink;
    final accent = overrides.accentColor ?? palette.accent;
    final muted = overrides.mutedColor ?? palette.muted;

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
      useMaterial3: false,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvas,
      cardColor: panel,
      appBarTheme: AppBarTheme(
        backgroundColor: panel,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: panel,
        selectedItemColor: accent,
        unselectedItemColor: muted,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: accent,
        unselectedLabelColor: muted,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: canvas,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: muted),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: accent),
        ),
      ),
    );
  }

  static _Palette _paletteForPreset(VityoThemePreset preset) {
    return switch (preset) {
      VityoThemePreset.parchment => const _Palette(
            canvas: Color(0xFFF7F4EB),
            panel: Color(0xFFFFFDF5),
            ink: Color(0xFF2D2416),
            accent: Color(0xFFC7522A),
            muted: Color(0xFFA09880),
          ),
      VityoThemePreset.graphite => const _Palette(
            canvas: Color(0xFF1E1E1E),
            panel: Color(0xFF2D2D2D),
            ink: Color(0xFFE0E0E0),
            accent: Color(0xFF569CD6),
            muted: Color(0xFF808080),
          ),
    };
  }
}

class _Palette {
  const _Palette({
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
