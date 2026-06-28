import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent_settings.dart';

void main() {
  group('VityoSettingsSchema', () {
    test('needsMigration detects version gap', () {
      const schema = VityoSettingsSchema(schemaVersion: 1);
      expect(schema.needsMigration(0), isTrue);
      expect(schema.needsMigration(1), isFalse);
      expect(schema.needsMigration(2), isFalse); // downgrade: no migration
    });

    test('roundtrips through JSON', () {
      const schema = VityoSettingsSchema(
        schemaVersion: 1,
        migrationsApplied: ['migration-001'],
      );
      final json = schema.toJson();
      final restored = VityoSettingsSchema.fromJson(json);
      expect(restored.schemaVersion, 1);
      expect(restored.migrationsApplied, ['migration-001']);
    });

    test('defaults to version 1', () {
      const schema = VityoSettingsSchema();
      expect(schema.schemaVersion, 1);
      expect(schema.migrationsApplied, isEmpty);
    });
  });

  group('EditorSettings', () {
    test('defaults have visual substitution enabled', () {
      const settings = EditorSettings.defaults;
      expect(settings.visualSubstitutionEnabled, isTrue);
      expect(settings.fontSize, 14);
      expect(settings.tabSize, 2);
      expect(settings.insertSpaces, isTrue);
    });

    test('visualSubstitutionEnabled toggle preserves other settings', () {
      const original = EditorSettings(
        fontSize: 16,
        visualSubstitutionEnabled: true,
      );
      final toggled = original.copyWith(visualSubstitutionEnabled: false);
      expect(toggled.visualSubstitutionEnabled, isFalse);
      expect(toggled.fontSize, 16); // preserved
    });

    test('roundtrips through JSON', () {
      const settings = EditorSettings(
        fontSize: 15,
        lineHeight: 1.6,
        tabSize: 4,
        insertSpaces: false,
        wordWrap: true,
        rulers: [80, 120],
        minimapEnabled: true,
        visualSubstitutionEnabled: false,
      );
      final json = settings.toJson();
      final restored = EditorSettings.fromJson(json);
      expect(restored.fontSize, 15);
      expect(restored.lineHeight, 1.6);
      expect(restored.tabSize, 4);
      expect(restored.insertSpaces, false);
      expect(restored.wordWrap, true);
      expect(restored.rulers, [80, 120]);
      expect(restored.minimapEnabled, true);
      expect(restored.visualSubstitutionEnabled, false);
    });

    test('missing fields fallback to defaults', () {
      final restored = EditorSettings.fromJson({});
      expect(restored.fontSize, 14);
      expect(restored.visualSubstitutionEnabled, true);
      expect(restored.rulers, isEmpty);
    });
  });

  group('ThemeSettings', () {
    test('defaults to graphite with gold accent', () {
      const settings = ThemeSettings.defaults;
      expect(settings.themeId, 'graphite');
      expect(settings.accentColor, '#F4C76A');
    });

    test('roundtrips through JSON', () {
      const settings = ThemeSettings(
        themeId: 'dark',
        contrastMode: 'high',
        accentColor: '#FF0000',
        editorFontFamily: 'Fira Code',
        uiFontFamily: 'Inter',
      );
      final json = settings.toJson();
      final restored = ThemeSettings.fromJson(json);
      expect(restored.themeId, 'dark');
      expect(restored.contrastMode, 'high');
      expect(restored.accentColor, '#FF0000');
      expect(restored.editorFontFamily, 'Fira Code');
    });
  });

  group('AgentSettings', () {
    test('localOnly mode has no provider', () {
      const settings = AgentSettings.localOnly;
      expect(settings.isLocalOnly, isTrue);
      expect(settings.hasProvider, isFalse);
      expect(settings.isProviderMissing, isFalse);
    });

    test('providerMissing mode reports missing', () {
      const settings = AgentSettings.providerMissing;
      expect(settings.isProviderMissing, isTrue);
      expect(settings.hasProvider, isFalse);
      expect(settings.isLocalOnly, isFalse);
    });

    test('hasProvider true when configured', () {
      const settings = AgentSettings(
        providerMode: 'openai-compatible',
        endpointBaseUrl: 'https://api.openai.com/v1',
        endpointModel: 'gpt-5.4',
      );
      expect(settings.hasProvider, isTrue);
      expect(settings.isLocalOnly, isFalse);
    });

    test('toDisplayJson redacts API key value', () {
      const settings = AgentSettings(
        providerMode: 'openai-compatible',
        endpointBaseUrl: 'https://api.openai.com/v1',
        apiKeyEnvironmentName: 'OPENAI_API_KEY',
      );
      final display = settings.toDisplayJson();
      expect(display['apiKeySource'], 'OPENAI_API_KEY');
      expect(
        display['apiKeyValue'],
        contains('REDACTED'),
      );
      // Regular JSON does NOT contain the actual key
      final regularJson = settings.toJson();
      expect(
        regularJson['apiKeyEnvironmentName'],
        'OPENAI_API_KEY',
      );
      // The actual key value is never in the settings JSON
      expect(
        regularJson.toString(),
        isNot(contains('sk-')),
      );
    });

    test('roundtrips through JSON', () {
      const settings = AgentSettings(
        providerMode: 'openai-compatible',
        endpointBaseUrl: 'https://custom.api/v1',
        endpointModel: 'custom-model',
        apiKeyEnvironmentName: 'CUSTOM_KEY',
        providerProtocol: 'openai-compatible',
      );
      final json = settings.toJson();
      final restored = AgentSettings.fromJson(json);
      expect(restored.providerMode, 'openai-compatible');
      expect(restored.endpointBaseUrl, 'https://custom.api/v1');
      expect(restored.endpointModel, 'custom-model');
      expect(restored.apiKeyEnvironmentName, 'CUSTOM_KEY');
      expect(restored.hasProvider, isTrue);
    });

    test('missing fields default to local-only', () {
      final restored = AgentSettings.fromJson({});
      expect(restored.isLocalOnly, isTrue);
      expect(restored.hasProvider, isFalse);
    });
  });

  group('VityoSettingsSnapshot', () {
    test('full roundtrip through JSON', () {
      const snapshot = VityoSettingsSnapshot(
        schema: VityoSettingsSchema(schemaVersion: 1),
        editor: EditorSettings(
          fontSize: 16,
          visualSubstitutionEnabled: true,
        ),
        theme: ThemeSettings(themeId: 'dark'),
        agent: AgentSettings(providerMode: 'provider-missing'),
        lastModifiedIso8601: '2026-06-24T00:00:00Z',
      );

      final json = snapshot.toJson();
      final restored = VityoSettingsSnapshot.fromJson(json);

      expect(restored.editor.fontSize, 16);
      expect(restored.editor.visualSubstitutionEnabled, isTrue);
      expect(restored.theme.themeId, 'dark');
      expect(restored.agent.providerMode, 'provider-missing');
      expect(restored.lastModifiedIso8601, '2026-06-24T00:00:00Z');
    });

    test('toAgentSafeJson redacts secrets', () {
      const snapshot = VityoSettingsSnapshot(
        agent: AgentSettings(
          providerMode: 'openai-compatible',
          endpointBaseUrl: 'https://api.openai.com/v1',
          apiKeyEnvironmentName: 'OPENAI_API_KEY',
        ),
      );

      final safe = snapshot.toAgentSafeJson();
      final agentSafe = safe['agent'] as Map<String, Object?>;

      // Agent-safe JSON should not leak key names unredacted
      expect(agentSafe['apiKeyValue'], contains('REDACTED'));
      expect(agentSafe['isLocalOnly'], false);
    });

    test('default snapshot is local-only', () {
      const snapshot = VityoSettingsSnapshot.defaults;
      expect(snapshot.agent.isLocalOnly, isTrue);
      expect(snapshot.editor.visualSubstitutionEnabled, isTrue);
    });

    test('copyWith preserves unchanged fields', () {
      const original = VityoSettingsSnapshot(
        editor: EditorSettings(fontSize: 14),
        theme: ThemeSettings(themeId: 'graphite'),
      );
      final updated = original.copyWith(
        editor: const EditorSettings(fontSize: 18),
      );
      expect(updated.editor.fontSize, 18);
      expect(updated.theme.themeId, 'graphite'); // preserved
    });
  });

  group('VityoProfileSnapshot', () {
    test('default is local-only', () {
      const profile = VityoProfileSnapshot.defaultLocal;
      expect(profile.isLocalOnly, isTrue);
      expect(profile.syncEnabled, false);
      expect(profile.profileId, 'default');
    });

    test('syncMissing when sync enabled but no provider', () {
      const profile = VityoProfileSnapshot(
        syncEnabled: true,
        syncProvider: '',
      );
      expect(profile.isSyncMissing, isTrue);
      expect(profile.isLocalOnly, isFalse);
    });

    test('full roundtrip through JSON', () {
      const profile = VityoProfileSnapshot(
        profileId: 'dev-profile',
        displayName: 'Development',
        createdAtIso8601: '2026-01-01T00:00:00Z',
        syncEnabled: true,
        syncProvider: 'vityo-sync',
        settings: VityoSettingsSnapshot(
          editor: EditorSettings(fontSize: 16),
        ),
      );

      final json = profile.toJson();
      final restored = VityoProfileSnapshot.fromJson(json);

      expect(restored.profileId, 'dev-profile');
      expect(restored.displayName, 'Development');
      expect(restored.syncEnabled, true);
      expect(restored.syncProvider, 'vityo-sync');
      expect(restored.settings.editor.fontSize, 16);
    });

    test('toAgentSafeJson redacts secrets in settings', () {
      const profile = VityoProfileSnapshot(
        profileId: 'test',
        settings: VityoSettingsSnapshot(
          agent: AgentSettings(
            providerMode: 'openai-compatible',
            apiKeyEnvironmentName: 'MY_KEY',
          ),
        ),
      );

      final safe = profile.toAgentSafeJson();
      expect(safe['profileId'], 'test');

      final settings = safe['settings'] as Map<String, Object?>;
      final agent = settings['agent'] as Map<String, Object?>;
      expect(agent['apiKeyValue'], contains('REDACTED'));
    });

    test('missing sync does not affect local settings', () {
      const profile = VityoProfileSnapshot(
        syncEnabled: false,
        settings: VityoSettingsSnapshot(
          editor: EditorSettings(fontSize: 18),
        ),
      );
      // Local settings are fully available
      expect(profile.settings.editor.fontSize, 18);
      expect(profile.isLocalOnly, isTrue);
    });

    test('copyWith preserves original fields', () {
      const original = VityoProfileSnapshot(
        profileId: 'orig',
        displayName: 'Original',
      );
      final updated = original.copyWith(displayName: 'Updated');
      expect(updated.profileId, 'orig');
      expect(updated.displayName, 'Updated');
    });
  });
}
