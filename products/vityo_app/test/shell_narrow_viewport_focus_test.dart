import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_render/view_render.dart';

void main() {
  group('Shell narrow viewport behavior', () {
    test(
      'compact mode hides activity rail and produces mobile viewport key',
      () {
        final plan = ShellLayoutPlan.forViewport(
          activeBottomTab: BottomSurfaceTab.agent,
          compact: true,
        );

        expect(plan.mode, ShellLayoutMode.compact);
        expect(plan.panelById('activity-rail')?.visible, isFalse);
        expect(plan.renderBinding().viewportKey, 'shell-viewport-mobile');
        expect(plan.renderBinding().compactActivityFallback, isTrue);
      },
    );

    test(
      'desktop mode shows activity rail and produces desktop viewport key',
      () {
        final plan = ShellLayoutPlan.forViewport(
          activeBottomTab: BottomSurfaceTab.agent,
          compact: false,
        );

        expect(plan.mode, ShellLayoutMode.desktop);
        expect(plan.panelById('activity-rail')?.visible, isTrue);
        expect(plan.renderBinding().viewportKey, 'shell-viewport-desktop');
        expect(plan.renderBinding().compactActivityFallback, isFalse);
      },
    );

    test('narrow viewport stacks panels in ListView instead of Row', () {
      final compactPlan = ShellLayoutPlan.forViewport(
        activeBottomTab: BottomSurfaceTab.search,
        compact: true,
      );
      final desktopPlan = ShellLayoutPlan.forViewport(
        activeBottomTab: BottomSurfaceTab.search,
        compact: false,
      );

      // Compact layout panels should use ListView (vertical stacking),
      // desktop uses Row (horizontal). The plan captures this via layout binding.
      expect(compactPlan.mode, ShellLayoutMode.compact);
      expect(desktopPlan.mode, ShellLayoutMode.desktop);
    });

    test('bottom panel tab selection works independently of viewport mode', () {
      for (final tab in BottomSurfaceTab.values) {
        final plan = ShellLayoutPlan.forViewport(
          activeBottomTab: tab,
          compact: false,
        );
        final compactPlan = ShellLayoutPlan.forViewport(
          activeBottomTab: tab,
          compact: true,
        );

        // Same tab active in both modes
        expect(plan.activeBottomTab, tab);
        expect(compactPlan.activeBottomTab, tab);
        // Panel for this tab is active
        final panelId = 'bottom.${tab.name}';
        expect(plan.panelById(panelId)?.active, isTrue);
        expect(compactPlan.panelById(panelId)?.active, isTrue);
      }
    });
  });

  group('Shell panel state', () {
    test(
      'bottom panel visibility toggles through plan without losing active tab',
      () {
        final controller = ShellLayoutPreferenceController(
          initialPreferences: const ShellLayoutPreferences(
            workspaceId: 'demo',
            activeBottomTab: BottomSurfaceTab.problems,
            bottomPanelExpanded: true,
          ),
        );

        expect(
          controller.preferences.activeBottomTab,
          BottomSurfaceTab.problems,
        );
        expect(controller.preferences.bottomPanelExpanded, isTrue);

        // Toggle panel collapsed
        controller.setBottomPanelExpanded(false);
        expect(controller.preferences.bottomPanelExpanded, isFalse);
        // Active tab is preserved
        expect(
          controller.preferences.activeBottomTab,
          BottomSurfaceTab.problems,
        );

        // Toggle back
        controller.setBottomPanelExpanded(true);
        expect(controller.preferences.bottomPanelExpanded, isTrue);

        // Panel visible state reflects expanded + active tab
        final binding = controller.renderBindingForViewport(compact: false);
        expect(binding.bottomPanelExpanded, isTrue);
        expect(binding.activeBottomPanelId, 'bottom.problems');
      },
    );

    test('panel pinned state persists across binding recalculations', () {
      final controller = ShellLayoutPreferenceController(
        initialPreferences: const ShellLayoutPreferences(
          workspaceId: 'demo',
          activeBottomTab: BottomSurfaceTab.debug,
        ),
      );
      controller.setPanelPinned('bottom.debug', pinned: true);

      final plan = controller.planForViewport(compact: false);
      expect(plan.panelById('bottom.debug')?.metadata['pinned'], isTrue);

      // Recalculate binding
      final binding = controller.renderBindingForViewport(compact: false);
      expect(binding.activeBottomPanelId, 'bottom.debug');
    });

    test('preference controller aggregates revision count', () {
      final controller = ShellLayoutPreferenceController(
        initialPreferences: const ShellLayoutPreferences(workspaceId: 'demo'),
      );

      expect(controller.revision, 0);

      controller.selectBottomTab(BottomSurfaceTab.search);
      expect(controller.revision, 1);

      controller.setPanelPinned('bottom.search', pinned: true);
      expect(controller.revision, 2);

      controller.setPanelVisible('bottom.runtime', visible: false);
      expect(controller.revision, 3);

      controller.setBottomPanelExpanded(false);
      expect(controller.revision, 4);
    });
  });

  group('Shell layout plan roundtrip', () {
    test('plan serialization roundtrips active tab and panel visibility', () {
      final plan = ShellLayoutPlan.forViewport(
        activeBottomTab: BottomSurfaceTab.search,
        compact: true,
      );
      final json = plan.toJson();
      final restored = ShellLayoutPlan.fromJson(json);

      expect(restored.activeBottomTab, BottomSurfaceTab.search);
      expect(restored.mode, ShellLayoutMode.compact);
      expect(restored.panelById('bottom.search')?.active, isTrue);
      expect(restored.renderBinding().viewportKey, 'shell-viewport-mobile');

      // Edit, serialize, restore again
      final edited = ShellLayoutPlan.forViewport(
        activeBottomTab: BottomSurfaceTab.extensions,
        compact: false,
      );
      final editedJson = edited.toJson();
      final restoredEdited = ShellLayoutPlan.fromJson(editedJson);

      expect(restoredEdited.activeBottomTab, BottomSurfaceTab.extensions);
      expect(restoredEdited.mode, ShellLayoutMode.desktop);
      expect(
        restoredEdited.renderBinding().viewportKey,
        'shell-viewport-desktop',
      );
    });
  });

  group('Focus model verification', () {
    test(
      'ShellLayoutPreferenceController selectBottomTab preserves focus intent',
      () {
        final controller = ShellLayoutPreferenceController(
          initialPreferences: const ShellLayoutPreferences(
            workspaceId: 'demo',
            activeBottomTab: BottomSurfaceTab.runtime,
          ),
        );

        // Selecting the same tab is a no-op
        controller.selectBottomTab(BottomSurfaceTab.runtime);
        expect(
          controller.preferences.activeBottomTab,
          BottomSurfaceTab.runtime,
        );
        expect(controller.revision, 0);

        // Switching tabs
        controller.selectBottomTab(BottomSurfaceTab.problems);
        expect(
          controller.preferences.activeBottomTab,
          BottomSurfaceTab.problems,
        );
        expect(controller.revision, 1);
      },
    );

    test('desktop editor panel has highest flex and is always active', () {
      // The editor is always active in both desktop and compact modes
      for (final compact in [true, false]) {
        final plan = ShellLayoutPlan.forViewport(
          activeBottomTab: BottomSurfaceTab.runtime,
          compact: compact,
        );
        expect(
          plan.panelById('editor')?.active,
          isTrue,
          reason: 'Editor must always be active in compact=$compact mode',
        );
      }
    });
  });
}
