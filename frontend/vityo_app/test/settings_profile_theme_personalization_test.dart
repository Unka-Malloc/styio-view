import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent_context.dart';
import 'package:vityo_app/src/view_ide/agent/agent_settings.dart';
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

  test('settings and profile projections redact secret-shaped values', () {
    const settings = VityoSettingsSnapshot(
      theme: ThemeSettings(themeId: 'graphite', accentColor: '#00A878'),
      agent: AgentSettings(
        providerMode: 'openai-compatible',
        endpointBaseUrl: 'https://api.openai.com/v1',
        endpointModel: 'gpt-5.4',
        apiKeyEnvironmentName: 'OPENAI_API_KEY',
      ),
      lastModifiedIso8601: '2026-06-29T00:00:00Z',
    );
    const profile = VityoProfileSnapshot(
      profileId: 'dev-profile',
      displayName: 'Development',
      syncEnabled: true,
      syncProvider: 'cloud-sync',
      settings: settings,
    );
    const agentContext = AgentContextSnapshot(
      snapshotId: 'context-1',
      profileId: 'dev-profile',
      settingsSummary: <String, String>{
        'apiKeyValue': 'sk-proj-abcd1234efgh5678',
        'themeId': 'graphite',
      },
    );

    final settingsSafe = settings.toAgentSafeJson();
    final profileSafe = profile.toAgentSafeJson();
    final contextJson = agentContext.toJson();

    final settingsAgent = settingsSafe['agent'] as Map<String, Object?>;
    final profileSettings = profileSafe['settings'] as Map<String, Object?>;
    final profileAgent = profileSettings['agent'] as Map<String, Object?>;
    final settingsSummary =
        contextJson['settingsSummary'] as Map<String, Object?>;

    expect(settingsSafe['theme'], isA<Map<String, Object?>>());
    expect(settingsAgent['apiKeySource'], 'OPENAI_API_KEY');
    expect(settingsAgent['apiKeyValue'], contains('REDACTED'));
    expect(profileSafe['profileId'], 'dev-profile');
    expect(profileSafe['displayName'], 'Development');
    expect(profileAgent['apiKeySource'], 'OPENAI_API_KEY');
    expect(profileAgent['apiKeyValue'], contains('REDACTED'));
    expect(settingsSummary['apiKeyValue'], '<redacted-api-key>');
    expect(settingsSummary['themeId'], 'graphite');
  });

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
