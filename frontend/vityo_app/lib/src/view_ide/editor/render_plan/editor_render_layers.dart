import '../../language/language_contract.dart';

enum EditorRenderLayer { text, decoration, overlay }

extension EditorRenderLayerX on EditorRenderLayer {
  String get wireValue => switch (this) {
    EditorRenderLayer.text => 'text',
    EditorRenderLayer.decoration => 'decoration',
    EditorRenderLayer.overlay => 'overlay',
  };
}

class EditorRenderPlan {
  const EditorRenderPlan({
    required this.activeLayers,
    this.glyphSubstitutionEnabled = true,
  });

  factory EditorRenderPlan.fromJson(Map<String, Object?> json) {
    return EditorRenderPlan(
      activeLayers: _jsonRenderLayers(json['activeLayers']),
      glyphSubstitutionEnabled:
          json['glyphSubstitutionEnabled'] as bool? ?? true,
    );
  }

  final Set<EditorRenderLayer> activeLayers;
  final bool glyphSubstitutionEnabled;

  factory EditorRenderPlan.foundation() {
    return const EditorRenderPlan(
      activeLayers: {
        EditorRenderLayer.text,
        EditorRenderLayer.decoration,
        EditorRenderLayer.overlay,
      },
    );
  }

  EditorRenderPlan copyWith({
    Set<EditorRenderLayer>? activeLayers,
    bool? glyphSubstitutionEnabled,
  }) {
    return EditorRenderPlan(
      activeLayers: activeLayers ?? this.activeLayers,
      glyphSubstitutionEnabled:
          glyphSubstitutionEnabled ?? this.glyphSubstitutionEnabled,
    );
  }

  Map<String, Object?> toJson() {
    final layers = activeLayers.toList(growable: false)
      ..sort((left, right) => left.index.compareTo(right.index));
    return <String, Object?>{
      'activeLayers': layers.map((layer) => layer.wireValue).toList(),
      'glyphSubstitutionEnabled': glyphSubstitutionEnabled,
    };
  }
}

Set<EditorRenderLayer> _jsonRenderLayers(Object? value) {
  if (value is! List) {
    return EditorRenderPlan.foundation().activeLayers;
  }
  final layers = value.map(_renderLayerFromWire).toSet();
  return layers.isEmpty ? EditorRenderPlan.foundation().activeLayers : layers;
}

EditorRenderLayer _renderLayerFromWire(Object? value) {
  return switch (value) {
    'text' => EditorRenderLayer.text,
    'decoration' => EditorRenderLayer.decoration,
    'overlay' => EditorRenderLayer.overlay,
    _ => EditorRenderLayer.text,
  };
}

class EditorSemanticTheme {
  const EditorSemanticTheme({
    required this.themeId,
    required this.semanticColors,
    required this.diagnosticUnderlineColors,
  });

  factory EditorSemanticTheme.foundation() {
    return const EditorSemanticTheme(
      themeId: 'vityo.foundation.semantic',
      semanticColors: <String, int>{
        'function': 0xFFAA4D7D,
        'pipeline': 0xFF25637A,
        'state': 0xFF847A22,
        'resource': 0xFF8B5E28,
        'variable': 0xFF6A4C33,
        'parameter': 0xFF355E97,
        'typeName': 0xFF4D6D2A,
      },
      diagnosticUnderlineColors: <String, int>{
        'error': 0xFFCB4D45,
        'warning': 0xFFD5962A,
        'hint': 0xFF6980B5,
      },
    );
  }

  factory EditorSemanticTheme.fromJson(Map<String, Object?> json) {
    return EditorSemanticTheme(
      themeId: json['themeId'] as String? ?? 'vityo.foundation.semantic',
      semanticColors: _intMapFromJson(json['semanticColors']),
      diagnosticUnderlineColors: _intMapFromJson(
        json['diagnosticUnderlineColors'],
      ),
    );
  }

  final String themeId;
  final Map<String, int> semanticColors;
  final Map<String, int> diagnosticUnderlineColors;

  int? colorForSemanticKind(SemanticKind kind) {
    return semanticColors[kind.name];
  }

  int? underlineColorForSeverity(DiagnosticSeverity severity) {
    return diagnosticUnderlineColors[severity.name];
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'themeId': themeId,
      'semanticColors': semanticColors,
      'diagnosticUnderlineColors': diagnosticUnderlineColors,
    };
  }
}

class EditorSemanticRenderStyle {
  const EditorSemanticRenderStyle({
    required this.styleId,
    required this.foregroundColor,
    this.fontWeight = 'normal',
    this.decoration = '',
    this.decorationColor,
  });

  final String styleId;
  final int foregroundColor;
  final String fontWeight;
  final String decoration;
  final int? decorationColor;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'styleId': styleId,
      'foregroundColor': foregroundColor,
      'fontWeight': fontWeight,
      if (decoration.isNotEmpty) 'decoration': decoration,
      if (decorationColor != null) 'decorationColor': decorationColor,
    };
  }
}

class EditorSemanticThemeBinding {
  const EditorSemanticThemeBinding({
    required this.themeId,
    required this.semanticStyles,
    required this.diagnosticStyles,
    this.todo = '',
  });

  factory EditorSemanticThemeBinding.fromTheme(EditorSemanticTheme theme) {
    return EditorSemanticThemeBinding(
      themeId: theme.themeId,
      semanticStyles: <String, EditorSemanticRenderStyle>{
        for (final entry in theme.semanticColors.entries)
          entry.key: EditorSemanticRenderStyle(
            styleId: 'semantic.${entry.key}',
            foregroundColor: entry.value,
            fontWeight: _semanticFontWeight(entry.key),
          ),
      },
      diagnosticStyles: <String, EditorSemanticRenderStyle>{
        for (final entry in theme.diagnosticUnderlineColors.entries)
          entry.key: EditorSemanticRenderStyle(
            styleId: 'diagnostic.${entry.key}',
            foregroundColor: entry.value,
            decoration: 'underline',
            decorationColor: entry.value,
          ),
      },
      todo: 'TODO: persist user-editable semantic theme choices.',
    );
  }

  final String themeId;
  final Map<String, EditorSemanticRenderStyle> semanticStyles;
  final Map<String, EditorSemanticRenderStyle> diagnosticStyles;
  final String todo;

  EditorSemanticRenderStyle? styleForSemanticKind(SemanticKind kind) {
    return semanticStyles[kind.name];
  }

  EditorSemanticRenderStyle? styleForDiagnosticSeverity(
    DiagnosticSeverity severity,
  ) {
    return diagnosticStyles[severity.name];
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'themeId': themeId,
      'semanticStyles': semanticStyles.map(
        (key, value) => MapEntry<String, Object?>(key, value.toJson()),
      ),
      'diagnosticStyles': diagnosticStyles.map(
        (key, value) => MapEntry<String, Object?>(key, value.toJson()),
      ),
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

Map<String, int> _intMapFromJson(Object? value) {
  if (value is! Map) {
    return const <String, int>{};
  }
  return value.map((key, value) {
    final parsedValue = value is int ? value : int.tryParse('$value') ?? 0;
    return MapEntry<String, int>(key.toString(), parsedValue);
  });
}

String _semanticFontWeight(String semanticKind) {
  return switch (semanticKind) {
    'function' || 'typeName' => '600',
    'state' || 'resource' => '500',
    _ => 'normal',
  };
}
