import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

Future<ConfigurationStore> _configurationStore(Directory root) async {
  final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
  final resourceManager = LocalResourceManager(
    facts: ResourceFacts.linuxDebianArm(
      systemTempPath: root.path,
      homePath: root.path,
    ),
  );
  final coordinator = FoundationResourceCoordinator(
    resourceManager: resourceManager,
    fileSystemManager: fileSystemManager,
  );
  return ConfigurationStore(
    dataStore: FoundationDataStore(
      resourceCoordinator: coordinator,
      fileSystemManager: fileSystemManager,
    ),
    credentialDataStore: InMemoryCredentialDataStore(),
  );
}

void main() {
  group('LogRedactor', () {
    test('redacts common log and prompt secret shapes', () {
      final redactor = LogRedactor();
      final redacted = redactor.redact(
        'Authorization: Bearer bearer-token-123456\n'
        'OPENAI_API_KEY=sk-proj-secretvalue123456\n'
        'https://example.test/callback?token=query-token-123&safe=1\n'
        'email ada@example.com\n'
        'path /home/alice/project/.env\n'
        r'windows C:\Users\Alice\.codex\auth.json'
        '\n'
        'hosted-session-id-abcdef123456\n',
      );

      expect(redacted, contains('Authorization: Bearer <redacted>'));
      expect(redacted, contains('OPENAI_API_KEY=<redacted>'));
      expect(redacted, contains('?token=<redacted>&safe=1'));
      expect(redacted, contains('<redacted-email>'));
      expect(redacted, contains('<redacted-path>'));
      expect(redacted, contains('<redacted-session-id>'));
      expect(redacted, isNot(contains('bearer-token-123456')));
      expect(redacted, isNot(contains('sk-proj-secretvalue123456')));
      expect(redacted, isNot(contains('query-token-123')));
      expect(redacted, isNot(contains('ada@example.com')));
      expect(redacted, isNot(contains('/home/alice')));
      expect(redacted, isNot(contains(r'C:\Users\Alice')));
      expect(redacted, isNot(contains('hosted-session-id-abcdef123456')));
    });

    test('redacts nested structured payloads by value and sensitive field name', () {
      final redacted = LogRedactor().redactJson(<String, Object?>{
        'headers': <String, Object?>{
          'Authorization': 'Bearer json-token-123456',
        },
        'apiKey': 'plain-json-api-key',
        'userEmail': 'ada@example.com',
        'path': '/Users/ada/project/secrets.env',
        'safe': 'plain setting',
      });

      expect(
        (redacted['headers']! as Map<String, Object?>)['Authorization'],
        '<redacted>',
      );
      expect(redacted['apiKey'], '<redacted>');
      expect(redacted['userEmail'], '<redacted-email>');
      expect(redacted['path'], '<redacted-path>');
      expect(redacted['safe'], 'plain setting');
    });
  });

  group('SecretStore', () {
    test('keeps values readable only through secret APIs and lists metadata', () async {
      final store = InMemorySecretStore();
      const key = CredentialDataStoreKey(
        namespace: 'agent.provider',
        name: 'openai',
        scope: CredentialScope.user,
      );

      await store.write(
        CredentialSecretRecord(
          key: key,
          kind: CredentialKind.token,
          secretValue: 'secret-token-value',
          displayName: 'OpenAI token',
        ),
      );

      expect(await store.read(key), 'secret-token-value');
      expect((await store.readRecord(key))!.secretValue, 'secret-token-value');
      final metadata = await store.listMetadata();
      final metadataJson = metadata.single.toJson().toString();
      expect(metadata.single.displayName, 'OpenAI token');
      expect(metadata.single.redactedValue, startsWith('se****'));
      expect(metadataJson, isNot(contains('secret-token-value')));
      expect(store.health.toJson()['backendKind'], 'volatile-memory');
      expect(await store.delete(key), isTrue);
      expect(await store.read(key), isNull);
    });

    test('write policy blocks long-lived web fallback secrets by default', () {
      const policy = SecretStoreWritePolicy();
      final decision = policy.evaluate(
        record: CredentialSecretRecord(
          key: const CredentialDataStoreKey(
            namespace: 'agent.provider',
            name: 'hosted',
            scope: CredentialScope.user,
          ),
          kind: CredentialKind.token,
          secretValue: 'hosted-token',
        ),
        health: const SecretStoreHealth(
          backendKind: SecretStoreBackendKind.webUserConfirmed,
          persistent: true,
          safeForLongLivedSecrets: false,
          requiresUserConfirmation: true,
          message: 'web fallback',
        ),
        now: DateTime.utc(2026, 6, 25),
      );

      expect(decision.kind, CredentialStoragePolicyDecisionKind.blocked);
    });
  });

  group('ConfigurationStore privacy', () {
    test('persists ordinary settings and rejects raw secret strings', () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_secret_redaction_configuration_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final store = await _configurationStore(tempRoot);
      const key = ConfigurationSettingKey(
        namespace: 'agent',
        name: 'privacy',
      );

      await store.write(
        const ConfigurationSettingRecord(
          key: key,
          value: <String, Object?>{
            'shareDiagnostics': false,
            'credentialReferenceIds': <String>['agent.provider:user:openai'],
          },
        ),
      );

      expect((await store.read(key))!.value['shareDiagnostics'], isFalse);
      expect(
        () => store.write(
          const ConfigurationSettingRecord(
            key: key,
            value: <String, Object?>{
              'headers': <String, Object?>{
                'Authorization': 'Bearer raw-token-123456',
              },
            },
          ),
        ),
        throwsArgumentError,
      );
      expect(
        () => store.write(
          const ConfigurationSettingRecord(
            key: key,
            value: <String, Object?>{
              'endpoint': 'https://example.test?token=query-token-123',
            },
          ),
        ),
        throwsArgumentError,
      );
    });
  });

}
