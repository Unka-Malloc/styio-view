import 'credential_data_store.dart';

enum SecretStoreBackendKind {
  macosKeychain,
  windowsCredentialManager,
  linuxSecretService,
  androidKeystore,
  iosKeychain,
  webUserConfirmed,
  volatileMemory,
}

extension SecretStoreBackendKindX on SecretStoreBackendKind {
  String get wireValue => switch (this) {
    SecretStoreBackendKind.macosKeychain => 'macos-keychain',
    SecretStoreBackendKind.windowsCredentialManager =>
      'windows-credential-manager',
    SecretStoreBackendKind.linuxSecretService => 'linux-secret-service',
    SecretStoreBackendKind.androidKeystore => 'android-keystore',
    SecretStoreBackendKind.iosKeychain => 'ios-keychain',
    SecretStoreBackendKind.webUserConfirmed => 'web-user-confirmed',
    SecretStoreBackendKind.volatileMemory => 'volatile-memory',
  };
}

class SecretStoreHealth {
  const SecretStoreHealth({
    required this.backendKind,
    required this.persistent,
    required this.safeForLongLivedSecrets,
    required this.requiresUserConfirmation,
    required this.message,
  });

  final SecretStoreBackendKind backendKind;
  final bool persistent;
  final bool safeForLongLivedSecrets;
  final bool requiresUserConfirmation;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'backendKind': backendKind.wireValue,
      'persistent': persistent,
      'safeForLongLivedSecrets': safeForLongLivedSecrets,
      'requiresUserConfirmation': requiresUserConfirmation,
      'message': message,
    };
  }
}

abstract class SecretStore {
  SecretStoreHealth get health;

  Future<void> write(CredentialSecretRecord record);
  Future<CredentialSecretRecord?> readRecord(CredentialDataStoreKey key);
  Future<String?> read(CredentialDataStoreKey key);
  Future<bool> delete(CredentialDataStoreKey key);
  Future<List<CredentialMetadata>> listMetadata();
}

class InMemorySecretStore implements SecretStore {
  InMemorySecretStore({
    this.health = const SecretStoreHealth(
      backendKind: SecretStoreBackendKind.volatileMemory,
      persistent: false,
      safeForLongLivedSecrets: false,
      requiresUserConfirmation: false,
      message: 'Volatile in-memory secret store for tests and previews.',
    ),
  });

  @override
  final SecretStoreHealth health;

  final Map<String, CredentialSecretRecord> _records =
      <String, CredentialSecretRecord>{};

  @override
  Future<void> write(CredentialSecretRecord record) async {
    _records[record.key.stableId] = record;
  }

  @override
  Future<CredentialSecretRecord?> readRecord(CredentialDataStoreKey key) async {
    final record = _records[key.stableId];
    if (record == null || record.isExpired) {
      return null;
    }
    return record;
  }

  @override
  Future<String?> read(CredentialDataStoreKey key) async {
    return (await readRecord(key))?.secretValue;
  }

  @override
  Future<bool> delete(CredentialDataStoreKey key) async {
    return _records.remove(key.stableId) != null;
  }

  @override
  Future<List<CredentialMetadata>> listMetadata() async {
    return _records.values
        .map((record) => record.toMetadata())
        .toList(growable: false);
  }
}

class SecretStoreWritePolicy {
  const SecretStoreWritePolicy({
    this.allowWebFallbackForLongLivedSecrets = false,
    this.longLivedThreshold = const Duration(days: 30),
  });

  final bool allowWebFallbackForLongLivedSecrets;
  final Duration longLivedThreshold;

  CredentialStoragePolicyDecision evaluate({
    required CredentialSecretRecord record,
    required SecretStoreHealth health,
    DateTime? now,
  }) {
    if (health.safeForLongLivedSecrets) {
      return CredentialStoragePolicyDecision(
        kind: CredentialStoragePolicyDecisionKind.allowed,
        reason: 'Secret store ${health.backendKind.wireValue} is secure.',
      );
    }
    final expiry = record.expiresAt;
    final reference = now ?? DateTime.now().toUtc();
    final longLived =
        expiry == null || expiry.difference(reference) > longLivedThreshold;
    if (longLived &&
        health.backendKind == SecretStoreBackendKind.webUserConfirmed &&
        !allowWebFallbackForLongLivedSecrets) {
      return const CredentialStoragePolicyDecision(
        kind: CredentialStoragePolicyDecisionKind.blocked,
        reason:
            'Web fallback storage cannot persist long-lived secrets without explicit user confirmation.',
      );
    }
    return CredentialStoragePolicyDecision(
      kind: CredentialStoragePolicyDecisionKind.warning,
      reason:
          'Secret store ${health.backendKind.wireValue} is not secure for long-lived production secrets.',
    );
  }
}
