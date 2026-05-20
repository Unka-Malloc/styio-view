import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/environment/environment.dart';
import 'package:vityo_app/src/view_ide/foundation/foundation.dart';

void main() {
  test('credential data store writes and reads secret records', () async {
    final store = InMemoryCredentialDataStore();
    const key = CredentialDataStoreKey(
      namespace: 'registry',
      name: 'vityo-nightly',
      scope: CredentialScope.workspace,
      targetId: 'demo',
    );

    await store.write(
      CredentialSecretRecord(
        key: key,
        kind: CredentialKind.registryCredential,
        secretValue: 'secret-token-123',
        displayName: 'Nightly registry token',
      ),
    );

    final loaded = await store.read(key);

    expect(loaded, isNotNull);
    expect(loaded!.secretValue, 'secret-token-123');
    expect(loaded.kind, CredentialKind.registryCredential);
  });

  test('credential data store snapshot is redacted', () async {
    final store = InMemoryCredentialDataStore();
    const key = CredentialDataStoreKey(
      namespace: 'remote-service',
      name: 'styio-service',
      scope: CredentialScope.service,
    );

    await store.write(
      CredentialSecretRecord(
        key: key,
        kind: CredentialKind.remoteServiceCredential,
        secretValue: 'service-secret-value',
      ),
    );

    final snapshot = await store.snapshot();
    final jsonText = snapshot.toJson().toString();

    expect(snapshot.credentials.single.redactedValue, 'se****ue');
    expect(jsonText, isNot(contains('service-secret-value')));
    expect(jsonText, contains('redactedValue'));
  });

  test(
    'credential data store health reports storage protection level',
    () async {
      final memoryStore = InMemoryCredentialDataStore();
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_credential_health_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final foundationStore = FoundationCredentialDataStore(
        dataStore: FoundationDataStore(
          resourceCoordinator: FoundationResourceCoordinator(
            resourceManager: resourceManager,
            fileSystemManager: fileSystemManager,
          ),
          fileSystemManager: fileSystemManager,
        ),
      );

      final memoryHealth = await memoryStore.health();
      final foundationHealth = await foundationStore.health();

      expect(
        memoryHealth.protection,
        CredentialStorageProtection.volatileMemory,
      );
      expect(memoryHealth.persistent, isFalse);
      expect(memoryHealth.safeForLongLivedSecrets, isFalse);
      expect(
        foundationHealth.protection,
        CredentialStorageProtection.foundationDataStore,
      );
      expect(foundationHealth.persistent, isTrue);
      expect(foundationHealth.safeForLongLivedSecrets, isFalse);
      expect(foundationHealth.toJson()['todo'], startsWith('TODO:'));
    },
  );

  test('credential storage policy blocks long lived unsafe secrets', () {
    final policy = const CredentialStoragePolicy();
    final record = CredentialSecretRecord(
      key: const CredentialDataStoreKey(
        namespace: 'agent.provider',
        name: 'openai',
        scope: CredentialScope.user,
      ),
      kind: CredentialKind.token,
      secretValue: 'long-lived-token',
      createdAt: DateTime.utc(2026, 5, 20),
      updatedAt: DateTime.utc(2026, 5, 20),
    );
    const health = CredentialDataStoreHealth(
      protection: CredentialStorageProtection.foundationDataStore,
      persistent: true,
      safeForLongLivedSecrets: false,
      message: 'FoundationDataStore is persistent but not secure.',
    );

    final decision = policy.evaluateWrite(record: record, health: health);

    expect(decision.allowed, isFalse);
    expect(decision.kind, CredentialStoragePolicyDecisionKind.blocked);
    expect(decision.reason, contains('Long-lived credential'));
    expect(decision.toJson()['todo'], startsWith('TODO:'));
  });

  test('credential storage policy allows platform secure storage', () {
    final policy = const CredentialStoragePolicy();
    final record = CredentialSecretRecord(
      key: const CredentialDataStoreKey(
        namespace: 'agent.provider',
        name: 'openai',
        scope: CredentialScope.user,
      ),
      kind: CredentialKind.token,
      secretValue: 'secure-token',
      createdAt: DateTime.utc(2026, 5, 20),
      updatedAt: DateTime.utc(2026, 5, 20),
    );
    const health = CredentialDataStoreHealth(
      protection: CredentialStorageProtection.platformSecureStorage,
      persistent: true,
      safeForLongLivedSecrets: true,
      message: 'OS-backed secure storage is available.',
    );

    final decision = policy.evaluateWrite(record: record, health: health);

    expect(decision.allowed, isTrue);
    expect(decision.kind, CredentialStoragePolicyDecisionKind.allowed);
  });

  test(
    'credential references can be stored in ordinary configuration safely',
    () {
      const reference = CredentialReference(
        key: CredentialDataStoreKey(
          namespace: 'toolchain',
          name: 'styio-registry',
          scope: CredentialScope.toolchain,
        ),
        kind: CredentialKind.token,
        displayName: 'Styio registry token',
      );

      final jsonText = reference.toJson().toString();

      expect(jsonText, contains('styio-registry'));
      expect(jsonText, contains('token'));
      expect(jsonText, isNot(contains('secret')));
    },
  );

  test(
    'credential secret injector resolves values without serializing secrets',
    () async {
      final store = InMemoryCredentialDataStore();
      final auditStore = InMemoryCredentialAccessAuditStore();
      const key = CredentialDataStoreKey(
        namespace: 'agent.provider',
        name: 'openai',
        scope: CredentialScope.user,
      );
      const reference = CredentialReference(
        key: key,
        kind: CredentialKind.token,
        displayName: 'OpenAI token',
      );
      await store.write(
        CredentialSecretRecord(
          key: key,
          kind: CredentialKind.token,
          secretValue: '  live-token-value  ',
        ),
      );

      final batch =
          await CredentialSecretInjector(
            credentialDataStore: store,
            accessAuditStore: auditStore,
            requesterId: 'agent.provider.openai',
            accessPurpose: CredentialAccessPurpose.providerConnection,
          ).injectAll(const <CredentialInjectionBinding>[
            CredentialInjectionBinding(
              targetName: 'Authorization',
              reference: reference,
              valuePrefix: 'Bearer ',
            ),
          ]);
      final auditSnapshot = await auditStore.snapshot();
      final jsonText = batch.toJson().toString();
      final auditJsonText = auditSnapshot.toJson().toString();

      expect(batch.ready, isTrue);
      expect(batch.injectedValues['Authorization'], 'Bearer live-token-value');
      expect(batch.redactedValues['Authorization'], 'Bearer li****ue');
      expect(auditSnapshot.entries.single.requesterId, 'agent.provider.openai');
      expect(
        auditSnapshot.entries.single.purpose,
        CredentialAccessPurpose.providerConnection,
      );
      expect(
        auditSnapshot.entries.single.status,
        CredentialInjectionStatus.injected,
      );
      expect(auditSnapshot.entries.single.redactedValue, 'Bearer li****ue');
      expect(jsonText, contains('redactedValue'));
      expect(jsonText, isNot(contains('live-token-value')));
      expect(auditJsonText, contains('provider-connection'));
      expect(auditJsonText, isNot(contains('live-token-value')));
    },
  );

  test(
    'credential secret injector fails closed for unsafe references',
    () async {
      final store = InMemoryCredentialDataStore();
      final expiredAt = DateTime.now().toUtc().subtract(
        const Duration(minutes: 1),
      );
      const expiredKey = CredentialDataStoreKey(
        namespace: 'agent.provider',
        name: 'expired',
        scope: CredentialScope.user,
      );
      const emptyKey = CredentialDataStoreKey(
        namespace: 'agent.provider',
        name: 'empty',
        scope: CredentialScope.user,
      );
      const mismatchedKey = CredentialDataStoreKey(
        namespace: 'agent.provider',
        name: 'mismatched',
        scope: CredentialScope.user,
      );
      await store.write(
        CredentialSecretRecord(
          key: expiredKey,
          kind: CredentialKind.token,
          secretValue: 'expired-token',
          expiresAt: expiredAt,
        ),
      );
      await store.write(
        CredentialSecretRecord(
          key: emptyKey,
          kind: CredentialKind.token,
          secretValue: '   ',
        ),
      );
      await store.write(
        CredentialSecretRecord(
          key: mismatchedKey,
          kind: CredentialKind.remoteServiceCredential,
          secretValue: 'service-token',
        ),
      );

      final batch = await CredentialSecretInjector(credentialDataStore: store)
          .injectAll(const <CredentialInjectionBinding>[
            CredentialInjectionBinding(
              targetName: 'expired',
              reference: CredentialReference(
                key: expiredKey,
                kind: CredentialKind.token,
              ),
            ),
            CredentialInjectionBinding(
              targetName: 'missing',
              reference: CredentialReference(
                key: CredentialDataStoreKey(
                  namespace: 'agent.provider',
                  name: 'missing',
                  scope: CredentialScope.user,
                ),
                kind: CredentialKind.token,
              ),
            ),
            CredentialInjectionBinding(
              targetName: 'empty',
              reference: CredentialReference(
                key: emptyKey,
                kind: CredentialKind.token,
              ),
            ),
            CredentialInjectionBinding(
              targetName: 'mismatched',
              reference: CredentialReference(
                key: mismatchedKey,
                kind: CredentialKind.token,
              ),
            ),
          ]);
      final statuses = <String, CredentialInjectionStatus>{
        for (final result in batch.results)
          result.binding.targetName: result.status,
      };
      final jsonText = batch.toJson().toString();

      expect(batch.ready, isFalse);
      expect(batch.injectedValues, isEmpty);
      expect(statuses['expired'], CredentialInjectionStatus.expiredCredential);
      expect(statuses['missing'], CredentialInjectionStatus.missingCredential);
      expect(statuses['empty'], CredentialInjectionStatus.emptySecret);
      expect(statuses['mismatched'], CredentialInjectionStatus.kindMismatch);
      expect(jsonText, isNot(contains('expired-token')));
      expect(jsonText, isNot(contains('service-token')));
    },
  );

  test('credential data store deletes credentials by stable key', () async {
    final store = InMemoryCredentialDataStore();
    const key = CredentialDataStoreKey(
      namespace: 'user',
      name: 'github',
      scope: CredentialScope.user,
    );

    await store.write(
      CredentialSecretRecord(
        key: key,
        kind: CredentialKind.token,
        secretValue: 'ghp-example-token',
      ),
    );

    expect(await store.read(key), isNotNull);
    expect(await store.delete(key), isTrue);
    expect(await store.read(key), isNull);
  });

  test(
    'foundation credential data store persists secret records separately',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_foundation_credential_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final coordinator = FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      );
      final foundationDataStore = FoundationDataStore(
        resourceCoordinator: coordinator,
        fileSystemManager: fileSystemManager,
      );
      final store = FoundationCredentialDataStore(
        dataStore: foundationDataStore,
      );
      const key = CredentialDataStoreKey(
        namespace: 'toolchain',
        name: 'styio-registry',
        scope: CredentialScope.toolchain,
        targetId: 'nightly',
      );

      await store.write(
        CredentialSecretRecord(
          key: key,
          kind: CredentialKind.token,
          secretValue: 'persisted-token-value',
          displayName: 'Persisted token',
        ),
      );
      final reloaded = FoundationCredentialDataStore(
        dataStore: foundationDataStore,
      );
      final loaded = await reloaded.read(key);
      final snapshot = await reloaded.snapshot();

      expect(loaded, isNotNull);
      expect(loaded!.secretValue, 'persisted-token-value');
      expect(snapshot.credentials.single.redactedValue, 'pe****ue');
      expect(
        snapshot.toJson().toString(),
        isNot(contains('persisted-token-value')),
      );
    },
  );

  test(
    'foundation credential access audit store persists redacted entries only',
    () async {
      final tempRoot = await Directory.systemTemp.createTemp(
        'vityo_foundation_credential_audit_test_',
      );
      addTearDown(() => tempRoot.delete(recursive: true));
      final fileSystemManager = LocalFileSystemManager.linuxDebianArmForTest();
      final resourceManager = LocalResourceManager(
        facts: ResourceFacts.linuxDebianArm(
          systemTempPath: tempRoot.path,
          homePath: tempRoot.path,
        ),
      );
      final coordinator = FoundationResourceCoordinator(
        resourceManager: resourceManager,
        fileSystemManager: fileSystemManager,
      );
      final foundationDataStore = FoundationDataStore(
        resourceCoordinator: coordinator,
        fileSystemManager: fileSystemManager,
      );
      final store = FoundationCredentialAccessAuditStore(
        dataStore: foundationDataStore,
      );

      await store.append(
        CredentialAccessAuditEntry(
          requestedAt: DateTime.utc(2026, 5, 20, 8),
          requesterId: 'agent.provider.openai',
          purpose: CredentialAccessPurpose.remoteService,
          targetName: 'Authorization',
          reference: const CredentialReference(
            key: CredentialDataStoreKey(
              namespace: 'agent.provider',
              name: 'openai',
              scope: CredentialScope.user,
            ),
            kind: CredentialKind.token,
            displayName: 'OpenAI token',
          ),
          status: CredentialInjectionStatus.injected,
          redactedValue: 'Bearer li****ue',
        ),
      );
      final reloaded = FoundationCredentialAccessAuditStore(
        dataStore: foundationDataStore,
      );
      final entries = await reloaded.list(
        purpose: CredentialAccessPurpose.remoteService,
        requesterId: 'agent.provider.openai',
      );
      final jsonText = (await reloaded.snapshot()).toJson().toString();

      expect(entries, hasLength(1));
      expect(entries.single.targetName, 'Authorization');
      expect(entries.single.redactedValue, 'Bearer li****ue');
      expect(jsonText, contains('remote-service'));
      expect(jsonText, isNot(contains('live-token-value')));
      expect(jsonText, isNot(contains('secretValue')));
    },
  );
}
