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
