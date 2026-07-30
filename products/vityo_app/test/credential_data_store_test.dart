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

  test('credential models parse loose JSON and scoped metadata', () async {
    final reference = CredentialReference.fromJson(<String, Object?>{
      'key': <Object, Object?>{
        'namespace': 'registry',
        'name': 'nightly',
        'scope': 'workspace',
        'targetId': 'demo',
      },
      'kind': 'remote-service-credential',
      'displayName': 'Nightly',
    });
    final fallbackReference = CredentialReference.fromJson(<String, Object?>{
      'namespace': 'fallback',
      'name': 'secret',
      'scope': 'service',
      'kind': 'unknown',
    });
    final expired = CredentialSecretRecord.fromJson(<String, Object?>{
      'namespace': 'registry',
      'name': 'expired',
      'scope': 'toolchain',
      'kind': 'registry-credential',
      'secretValue': 'tok',
      'createdAt': '2026-06-01T00:00:00Z',
      'updatedAt': '2026-06-01T00:00:01Z',
      'expiresAt': '2000-01-01T00:00:00Z',
      'attributes': <Object, Object?>{1: 2},
    });
    final tinySecret = CredentialSecretRecord(
      key: const CredentialDataStoreKey(
        namespace: 'user',
        name: 'tiny',
        scope: CredentialScope.user,
      ),
      kind: CredentialKind.token,
      secretValue: 'abc',
    );
    final store = InMemoryCredentialDataStore();

    await store.write(expired);
    await store.write(tinySecret);

    expect(
      CredentialKind.values.map((kind) => kind.wireValue),
      <String>[
        'token',
        'registry-credential',
        'remote-service-credential',
        'generic-secret',
      ],
    );
    expect(
      CredentialScope.values.map((scope) => scope.wireValue),
      <String>['user', 'workspace', 'toolchain', 'service'],
    );
    expect(reference.key.stableId, 'workspace:registry:demo:nightly');
    expect(reference.kind, CredentialKind.remoteServiceCredential);
    expect(fallbackReference.key.scope, CredentialScope.service);
    expect(fallbackReference.kind, CredentialKind.genericSecret);
    expect(expired.attributes, <String, String>{'1': '2'});
    expect(expired.toMetadata().redactedValue, '****');
    expect(await store.read(expired.key), isNull);
    expect(await store.list(scope: CredentialScope.toolchain), hasLength(1));
    expect(await store.delete(expired.key), isTrue);
    expect(await store.delete(expired.key), isFalse);
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
