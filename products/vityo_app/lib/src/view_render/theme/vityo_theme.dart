import 'package:flutter/material.dart';

import '../../view_ide/environment/configuration/vityo_theme_override.dart';

extension VityoThemeOverrideColorX on VityoThemeOverride {
  Color? get canvasColor => canvas != null ? Color(canvas!) : null;
  Color? get panelColor => panel != null ? Color(panel!) : null;
  Color? get inkColor => ink != null ? Color(ink!) : null;
  Color? get accentColor => accent != null ? Color(accent!) : null;
  Color? get mutedColor => muted != null ? Color(muted!) : null;
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
    final baseTextTheme = ThemeData.light().textTheme;

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
      textTheme: baseTextTheme
          .apply(bodyColor: ink, displayColor: ink)
          .copyWith(bodySmall: baseTextTheme.bodySmall?.copyWith(color: muted)),
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
      extensions: <ThemeExtension<dynamic>>[
        VityoWorkbenchTokens.light(
          canvas: canvas,
          region: panel,
          ink: ink,
          accent: accent,
          muted: muted,
        ),
      ],
    );
  }

  static ThemeData dark({
    VityoThemeOverride overrides = const VityoThemeOverride(),
  }) {
    final canvas = overrides.canvasColor ?? const Color(0xFF171A1D);
    final panel = overrides.panelColor ?? const Color(0xFF1E2226);
    final ink = overrides.inkColor ?? const Color(0xFFE7EAED);
    final accent = overrides.accentColor ?? const Color(0xFF75B7B1);
    final muted = overrides.mutedColor ?? const Color(0xFF9AA5AD);
    final colorScheme = ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(primary: accent, surface: panel, onSurface: ink);
    final baseTextTheme = ThemeData.dark().textTheme;

    return ThemeData(
      useMaterial3: false,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: canvas,
      cardColor: panel,
      dividerColor: const Color(0xFF353B40),
      textTheme: baseTextTheme
          .apply(bodyColor: ink, displayColor: ink)
          .copyWith(bodySmall: baseTextTheme.bodySmall?.copyWith(color: muted)),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF14171A),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: const BorderSide(color: Color(0xFF434B52)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(4),
          borderSide: BorderSide(color: accent, width: 2),
        ),
      ),
      extensions: <ThemeExtension<dynamic>>[
        VityoWorkbenchTokens.dark(
          canvas: canvas,
          region: panel,
          ink: ink,
          accent: accent,
          muted: muted,
        ),
      ],
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
        canvas: Color(0xFFEDEFF2),
        panel: Color(0xFFFFFFFF),
        ink: Color(0xFF1E252B),
        accent: Color(0xFF2F6F73),
        muted: Color(0xFF62717C),
      ),
    };
  }
}

@immutable
final class VityoWorkbenchTokens extends ThemeExtension<VityoWorkbenchTokens> {
  const VityoWorkbenchTokens({
    required this.canvas,
    required this.region,
    required this.editor,
    required this.hover,
    required this.selection,
    required this.divider,
    required this.focus,
    required this.ink,
    required this.muted,
    required this.success,
    required this.warning,
    required this.error,
    required this.blocked,
  });

  factory VityoWorkbenchTokens.light({
    required Color canvas,
    required Color region,
    required Color ink,
    required Color accent,
    required Color muted,
  }) => VityoWorkbenchTokens(
    canvas: canvas,
    region: region,
    editor: const Color(0xFFFFFEFA),
    hover: ink.withValues(alpha: 0.06),
    selection: accent.withValues(alpha: 0.18),
    divider: ink.withValues(alpha: 0.18),
    focus: accent,
    ink: ink,
    muted: muted,
    success: const Color(0xFF277447),
    warning: const Color(0xFFA35A12),
    error: const Color(0xFFB3261E),
    blocked: const Color(0xFF7A5269),
  );

  factory VityoWorkbenchTokens.dark({
    required Color canvas,
    required Color region,
    required Color ink,
    required Color accent,
    required Color muted,
  }) => VityoWorkbenchTokens(
    canvas: canvas,
    region: region,
    editor: const Color(0xFF15181B),
    hover: Colors.white.withValues(alpha: 0.07),
    selection: accent.withValues(alpha: 0.22),
    divider: const Color(0xFF353B40),
    focus: accent,
    ink: ink,
    muted: muted,
    success: const Color(0xFF69C58C),
    warning: const Color(0xFFF1B56B),
    error: const Color(0xFFFF8B84),
    blocked: const Color(0xFFD5A0C0),
  );

  final Color canvas;
  final Color region;
  final Color editor;
  final Color hover;
  final Color selection;
  final Color divider;
  final Color focus;
  final Color ink;
  final Color muted;
  final Color success;
  final Color warning;
  final Color error;
  final Color blocked;

  static VityoWorkbenchTokens of(BuildContext context) =>
      Theme.of(context).extension<VityoWorkbenchTokens>()!;

  @override
  VityoWorkbenchTokens copyWith({
    Color? canvas,
    Color? region,
    Color? editor,
    Color? hover,
    Color? selection,
    Color? divider,
    Color? focus,
    Color? ink,
    Color? muted,
    Color? success,
    Color? warning,
    Color? error,
    Color? blocked,
  }) => VityoWorkbenchTokens(
    canvas: canvas ?? this.canvas,
    region: region ?? this.region,
    editor: editor ?? this.editor,
    hover: hover ?? this.hover,
    selection: selection ?? this.selection,
    divider: divider ?? this.divider,
    focus: focus ?? this.focus,
    ink: ink ?? this.ink,
    muted: muted ?? this.muted,
    success: success ?? this.success,
    warning: warning ?? this.warning,
    error: error ?? this.error,
    blocked: blocked ?? this.blocked,
  );

  @override
  VityoWorkbenchTokens lerp(covariant VityoWorkbenchTokens? other, double t) {
    if (other == null) return this;
    return VityoWorkbenchTokens(
      canvas: Color.lerp(canvas, other.canvas, t)!,
      region: Color.lerp(region, other.region, t)!,
      editor: Color.lerp(editor, other.editor, t)!,
      hover: Color.lerp(hover, other.hover, t)!,
      selection: Color.lerp(selection, other.selection, t)!,
      divider: Color.lerp(divider, other.divider, t)!,
      focus: Color.lerp(focus, other.focus, t)!,
      ink: Color.lerp(ink, other.ink, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      blocked: Color.lerp(blocked, other.blocked, t)!,
    );
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
