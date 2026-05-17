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

  test('credential references can be stored in ordinary configuration safely', () {
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
  });

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

  test('foundation credential data store persists secret records separately', () async {
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
    expect(snapshot.toJson().toString(), isNot(contains('persisted-token-value')));
  });
}
