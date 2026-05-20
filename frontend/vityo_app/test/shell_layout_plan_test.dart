import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';
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

  test(
    'shell layout preferences apply and persist through DataStore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_shell_layout_preferences_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final dataStore = FoundationDataStore(
        resourceCoordinator: FoundationResourceCoordinator(
          resourceManager: resourceManager,
          fileSystemManager: fileSystemManager,
        ),
        fileSystemManager: fileSystemManager,
      );
      final store = ShellLayoutPreferencesStore.fromDataStore(
        dataStore: dataStore,
      );
      const preferences = ShellLayoutPreferences(
        workspaceId: 'demo',
        activeBottomTab: BottomSurfaceTab.problems,
        hiddenPanelIds: <String>{'bottom.runtime'},
        pinnedPanelIds: <String>{'bottom.problems'},
        bottomPanelExpanded: false,
      );
      final plan = ShellLayoutPlan.forViewport(
        activeBottomTab: BottomSurfaceTab.runtime,
        compact: false,
      );

      await store.savePreferences(preferences);
      final restored = await store.readPreferences(workspaceId: 'demo');
      final applied = restored.applyTo(plan);

      expect(restored.activeBottomTab, BottomSurfaceTab.problems);
      expect(applied.activeBottomTab, BottomSurfaceTab.problems);
      expect(applied.panelById('bottom.runtime')?.visible, isFalse);
      expect(applied.panelById('bottom.problems')?.active, isTrue);
      expect(applied.panelById('bottom.problems')?.metadata['pinned'], isTrue);
      expect(
        applied.panelById('bottom.problems')?.metadata['bottomPanelExpanded'],
        isFalse,
      );
      expect(await store.deletePreferences(workspaceId: 'demo'), isTrue);
      expect(
        (await store.readPreferences(workspaceId: 'demo')).activeBottomTab,
        BottomSurfaceTab.runtime,
      );
    },
  );
}
