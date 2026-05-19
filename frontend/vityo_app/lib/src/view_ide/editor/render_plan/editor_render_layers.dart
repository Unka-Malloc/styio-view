enum EditorRenderLayer {
  text,
  decoration,
  overlay,
}

class EditorRenderPlan {
  const EditorRenderPlan({
    required this.activeLayers,
    this.glyphSubstitutionEnabled = true,
  });

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
}
