import '../render_plan/editor_render_layers.dart';
import 'editor_owned_controller.dart';

class RenderPlanController extends EditorOwnedController {
  RenderPlanController(EditorRenderPlan renderPlan) : _renderPlan = renderPlan;

  EditorRenderPlan _renderPlan;

  EditorRenderPlan get renderPlan => _renderPlan;
  bool get glyphSubstitutionEnabled => _renderPlan.glyphSubstitutionEnabled;

  void setRenderPlan(EditorRenderPlan renderPlan) {
    ensureNotDisposed();
    _renderPlan = renderPlan;
    notifyControllerListeners();
  }

  void setGlyphSubstitutionEnabled(bool enabled) {
    ensureNotDisposed();
    if (_renderPlan.glyphSubstitutionEnabled == enabled) {
      return;
    }
    _renderPlan = _renderPlan.copyWith(glyphSubstitutionEnabled: enabled);
    notifyControllerListeners();
  }

  void toggleGlyphSubstitution() {
    setGlyphSubstitutionEnabled(!_renderPlan.glyphSubstitutionEnabled);
  }
}
