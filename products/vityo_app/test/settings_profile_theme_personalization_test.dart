import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/theme/vityo_theme.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test(
    'theme override store roundtrips through Foundation DataStore',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_settings_profile_theme_test_',
      );
      addTearDown(() async {
        if (await tempRoot.exists()) {
          await tempRoot.delete(recursive: true);
        }
      });

      final dataStore = _createFoundationDataStore(tempRoot.path);
      final store = VityoThemeOverrideStore.fromDataStore(dataStore: dataStore);
      const override = VityoThemeOverride(
        canvas: 0xFF101820,
        accent: 0xFF00A878,
      );

      await store.saveOverride(workspaceId: 'demo', override: override);

      final restored = await store.readOverride(workspaceId: 'demo');
      final previewTheme = VityoTheme.light(
        preset: VityoThemePreset.graphite,
        overrides: restored!,
      );

      expect(restored.canvas, 0xFF101820);
      expect(restored.panel, isNull);
      expect(restored.accent, 0xFF00A878);
      expect(previewTheme.scaffoldBackgroundColor, const Color(0xFF101820));
      expect(previewTheme.cardColor, const Color(0xFFFFFFFF));
      expect(previewTheme.colorScheme.primary, const Color(0xFF00A878));
      expect(await store.deleteOverride(workspaceId: 'demo'), isTrue);
      expect(await store.readOverride(workspaceId: 'demo'), isNull);
    },
  );

  test('theme override preview keeps unedited preset colors intact', () {
    const preview = VityoThemeOverride(canvas: 0xFF101820, accent: 0xFF00A878);
    final derived = preview.copyWith(accent: 0xFF112233);
    final theme = VityoTheme.light(
      preset: VityoThemePreset.graphite,
      overrides: derived,
    );

    expect(preview.accent, 0xFF00A878);
    expect(derived.canvas, 0xFF101820);
    expect(derived.accent, 0xFF112233);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF101820));
    expect(theme.cardColor, const Color(0xFFFFFFFF));
    expect(theme.colorScheme.primary, const Color(0xFF112233));
  });
}

FoundationDataStore _createFoundationDataStore(String systemTempPath) {
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: systemTempPath,
      homePath: systemTempPath,
    ),
  );
  return FoundationDataStore(
    resourceCoordinator: FoundationResourceCoordinator(
      resourceManager: resourceManager,
      fileSystemManager: fileSystemManager,
    ),
    fileSystemManager: fileSystemManager,
  );
}
