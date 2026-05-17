enum EditorRenderLayer {
  text,
  decoration,
  overlay,
}

class EditorRenderPlan {
  const EditorRenderPlan({
    required this.activeLayers,
  });

  final Set<EditorRenderLayer> activeLayers;

  factory EditorRenderPlan.foundation() {
    return const EditorRenderPlan(
      activeLayers: {
        EditorRenderLayer.text,
        EditorRenderLayer.decoration,
        EditorRenderLayer.overlay,
      },
    );
  }
}
