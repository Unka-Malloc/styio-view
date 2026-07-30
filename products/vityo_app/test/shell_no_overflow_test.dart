import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_render/view_render.dart';

void main() {
  group('Shell no-overflow verification', () {
    test(
      'desktop layout plan defines fixed-width regions with no overflow risk',
      () {
        final plan = ShellLayoutPlan.forViewport(
          activeBottomTab: BottomSurfaceTab.runtime,
          compact: false,
        );

        expect(plan.mode, ShellLayoutMode.desktop);
        final editorPanel = plan.panelById('editor');
        expect(editorPanel, isNotNull);
        expect(editorPanel!.visible, isTrue);
      },
    );

    test('compact layout removes activity rail to prevent narrow overflow', () {
      final plan = ShellLayoutPlan.forViewport(
        activeBottomTab: BottomSurfaceTab.debug,
        compact: true,
      );

      expect(plan.mode, ShellLayoutMode.compact);
      expect(plan.panelById('activity-rail')?.visible, isFalse);
      expect(
        plan.panelById('activity-rail')?.todo,
        contains('compact activity'),
      );
      expect(plan.renderBinding().compactActivityFallback, isTrue);
      expect(plan.renderBinding().viewportKey, 'shell-viewport-mobile');
    });

    test('all core bottom panels have bounded height within layout', () {
      for (final tab in BottomSurfaceTab.values) {
        final plan = ShellLayoutPlan.forViewport(
          activeBottomTab: tab,
          compact: false,
        );
        final binding = plan.renderBinding();
        expect(
          binding.activeBottomPanelId,
          isNotEmpty,
          reason: 'Each bottom tab must map to a panel ID',
        );
        expect(binding.bottomPanelExpanded, isA<bool>());
      }
    });

    test('core IDE panels define bounded capabilities through registry', () {
      final registry = ShellPanelContributionRegistry.defaultIdePanels();
      // Use the static const directly
      for (final panelId in ShellPanelContributionRegistry.coreIdePanelIds) {
        final contribution = registry.panelById(panelId);
        expect(
          contribution,
          isNotNull,
          reason: 'Core panel $panelId must have a registry entry',
        );
        expect(
          contribution!.capabilities.isNotEmpty,
          isTrue,
          reason:
              'Core panel $panelId must define finite rendering capabilities',
        );
      }
    });

    test(
      'screen-reader semantics keys are stable across plan serialization',
      () {
        final plan = ShellLayoutPlan.forViewport(
          activeBottomTab: BottomSurfaceTab.problems,
          compact: false,
        );
        final json = plan.toJson();
        final restored = ShellLayoutPlan.fromJson(json);

        expect(restored.activeBottomTab, BottomSurfaceTab.problems);
        expect(restored.renderBinding().visiblePanelIds, isNotEmpty);
        expect(restored.renderBinding().activeBottomPanelId, 'bottom.problems');

        // Verify viewport key is deterministic
        expect(plan.renderBinding().viewportKey, 'shell-viewport-desktop');
        expect(restored.renderBinding().viewportKey, 'shell-viewport-desktop');
      },
    );

    test('compact render binding uses mobile key consistently', () {
      for (final tab in BottomSurfaceTab.values) {
        final plan = ShellLayoutPlan.forViewport(
          activeBottomTab: tab,
          compact: true,
        );
        expect(
          plan.renderBinding().viewportKey,
          'shell-viewport-mobile',
          reason:
              'Compact mode must use mobile viewport key for tab ${tab.name}',
        );
      }
    });
  });
}
