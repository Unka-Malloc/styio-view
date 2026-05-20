import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_render/view_render.dart';

void main() {
  test('shell layout plan marks active bottom panel', () {
    final plan = ShellLayoutPlan.forViewport(
      activeBottomTab: BottomSurfaceTab.agent,
      compact: false,
    );
    final restored = ShellLayoutPlan.fromJson(plan.toJson());

    expect(plan.mode, ShellLayoutMode.desktop);
    expect(plan.panelById('editor')?.active, isTrue);
    expect(plan.panelById('bottom.agent')?.active, isTrue);
    expect(plan.panelById('bottom.runtime')?.active, isFalse);
    expect(restored.activeBottomTab, BottomSurfaceTab.agent);
    expect(restored.visiblePanelIds, contains('activity-rail'));
    expect(plan.renderBinding().viewportKey, 'shell-viewport-desktop');
    expect(plan.renderBinding().activeBottomPanelId, 'bottom.agent');
  });

  test('shell layout plan records compact activity rail fallback', () {
    final plan = ShellLayoutPlan.forViewport(
      activeBottomTab: BottomSurfaceTab.search,
      compact: true,
    );

    expect(plan.mode, ShellLayoutMode.compact);
    expect(plan.panelById('activity-rail')?.visible, isFalse);
    expect(plan.panelById('activity-rail')?.todo, contains('compact activity'));
    expect(plan.panelById('bottom.search')?.active, isTrue);
    expect(plan.toJson()['todo'], contains('persisted layout preferences'));
    expect(plan.renderBinding().compactActivityFallback, isTrue);
    expect(
      plan.renderBinding().toJson()['visiblePanelIds'],
      isNot(contains('activity-rail')),
    );
  });
}
