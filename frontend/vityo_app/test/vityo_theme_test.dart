import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/theme/vityo_theme.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test('theme override round-trips user layer colors', () {
    const override = VityoThemeOverride(
      canvas: 0xFF101820,
      panel: 0xFFFAFAFA,
      accent: 0xFF00A878,
    );

    final decoded = VityoThemeOverride.fromJson(override.toJson());
    final theme = VityoTheme.light(overrides: decoded);

    expect(decoded.canvas, 0xFF101820);
    expect(decoded.panel, 0xFFFAFAFA);
    expect(decoded.accent, 0xFF00A878);
    expect(theme.scaffoldBackgroundColor, const Color(0xFF101820));
    expect(theme.cardColor, const Color(0xFFFAFAFA));
    expect(theme.colorScheme.primary, const Color(0xFF00A878));
  });

  test('theme override copyWith updates persisted accent only', () {
    const base = VityoThemeOverride(canvas: 0xFF101820, accent: 0xFF5668A6);

    final updated = base.copyWith(accent: 0xFF00A878);

    expect(updated.canvas, 0xFF101820);
    expect(updated.accent, 0xFF00A878);
  });

  test('theme override accepts hash colors for persisted JSON payloads', () {
    final override = VityoThemeOverride.fromJson(<String, Object?>{
      'canvas': '#202124',
      'ink': '#F8F9FA',
    });
    final theme = VityoTheme.light(overrides: override);

    expect(theme.scaffoldBackgroundColor, const Color(0xFF202124));
    expect(theme.textTheme.bodyMedium?.color, const Color(0xFFF8F9FA));
  });

  test('theme presets preserve editor layer colors', () {
    final parchment = VityoTheme.light();
    final graphite = VityoTheme.light(preset: VityoThemePreset.graphite);

    expect(parchment.scaffoldBackgroundColor, const Color(0xFFF7F4EB));
    expect(graphite.scaffoldBackgroundColor, const Color(0xFFEDEFF2));
    expect(graphite.cardColor, const Color(0xFFFFFFFF));
    expect(graphite.textTheme.bodyMedium?.color, const Color(0xFF1E252B));
    expect(graphite.textTheme.bodySmall?.color, const Color(0xFF62717C));
    expect(graphite.colorScheme.primary, const Color(0xFF2F6F73));
  });

  test('theme override persists through configuration DataStore', () async {
    final tempRoot = await Directory.systemTemp.createTemp(
      'vityo_theme_override_store_test_',
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
    final store = VityoThemeOverrideStore.fromDataStore(dataStore: dataStore);
    const override = VityoThemeOverride(canvas: 0xFF101820, accent: 0xFF00A878);

    await store.saveOverride(workspaceId: 'demo', override: override);
    final restored = await store.readOverride(workspaceId: 'demo');

    expect(restored?.canvas, 0xFF101820);
    expect(restored?.accent, 0xFF00A878);
    expect(await store.deleteOverride(workspaceId: 'demo'), isTrue);
    expect(await store.readOverride(workspaceId: 'demo'), isNull);
  });
}
