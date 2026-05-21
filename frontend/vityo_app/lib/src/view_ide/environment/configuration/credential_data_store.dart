import '../../foundation/foundation.dart';

enum CredentialKind {
  token,
  registryCredential,
  remoteServiceCredential,
  genericSecret,
}

enum CredentialScope { user, workspace, toolchain, service }

extension CredentialKindX on CredentialKind {
  String get wireValue => switch (this) {
    CredentialKind.token => 'token',
    CredentialKind.registryCredential => 'registry-credential',
    CredentialKind.remoteServiceCredential => 'remote-service-credential',
    CredentialKind.genericSecret => 'generic-secret',
  };
}

extension CredentialScopeX on CredentialScope {
  String get wireValue => switch (this) {
    CredentialScope.user => 'user',
    CredentialScope.workspace => 'workspace',
    CredentialScope.toolchain => 'toolchain',
    CredentialScope.service => 'service',
  };
}

class CredentialDataStoreKey {
  const CredentialDataStoreKey({
    required this.namespace,
    required this.name,
    required this.scope,
    this.targetId,
  });

  final String namespace;
  final String name;
  final CredentialScope scope;
  final String? targetId;

  factory CredentialDataStoreKey.fromJson(Map<String, Object?> json) {
    return CredentialDataStoreKey(
      namespace: json['namespace'] as String? ?? 'default',
      name: json['name'] as String? ?? 'credential',
      scope: credentialScopeFromWireValue(json['scope'] as String?),
      targetId: json['targetId'] as String?,
    );
  }

  String get stableId {
    return <String>[
      scope.wireValue,
      namespace,
      if (targetId != null && targetId!.isNotEmpty) targetId!,
      name,
    ].join(':');
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'namespace': namespace,
      'name': name,
      'scope': scope.wireValue,
      if (targetId != null) 'targetId': targetId,
      'stableId': stableId,
    };
  }
}

class CredentialReference {
  const CredentialReference({
    required this.key,
    required this.kind,
    this.displayName,
  });

  final CredentialDataStoreKey key;
  final CredentialKind kind;
  final String? displayName;

  factory CredentialReference.fromJson(Map<String, Object?> json) {
    final keyJson = json['key'];
    return CredentialReference(
      key: keyJson is Map<String, Object?>
          ? CredentialDataStoreKey.fromJson(keyJson)
          : keyJson is Map
          ? CredentialDataStoreKey.fromJson(
              keyJson.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : CredentialDataStoreKey(
              namespace: json['namespace'] as String? ?? 'default',
              name: json['name'] as String? ?? 'credential',
              scope: credentialScopeFromWireValue(json['scope'] as String?),
              targetId: json['targetId'] as String?,
            ),
      kind: credentialKindFromWireValue(json['kind'] as String?),
      displayName: json['displayName'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key.toJson(),
      'kind': kind.wireValue,
      if (displayName != null) 'displayName': displayName,
    };
  }
}

CredentialKind credentialKindFromWireValue(String? value) {
  return switch (value) {
    'token' => CredentialKind.token,
    'registry-credential' => CredentialKind.registryCredential,
    'remote-service-credential' => CredentialKind.remoteServiceCredential,
    _ => CredentialKind.genericSecret,
  };
}

CredentialScope credentialScopeFromWireValue(String? value) {
  return switch (value) {
    'workspace' => CredentialScope.workspace,
    'toolchain' => CredentialScope.toolchain,
    'service' => CredentialScope.service,
    _ => CredentialScope.user,
  };
}

class CredentialSecretRecord {
  CredentialSecretRecord({
    required this.key,
    required this.kind,
    required this.secretValue,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.expiresAt,
    this.displayName,
    this.attributes = const <String, String>{},
  }) : createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  final CredentialDataStoreKey key;
  final CredentialKind kind;
  final String secretValue;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  final String? displayName;
  final Map<String, String> attributes;

  bool get isExpired {
    final expiry = expiresAt;
    return expiry != null && !expiry.isAfter(DateTime.now().toUtc());
  }

  CredentialMetadata toMetadata() {
    return CredentialMetadata(
      key: key,
      kind: kind,
      redactedValue: _redact(secretValue),
      createdAt: createdAt,
      updatedAt: updatedAt,
      expiresAt: expiresAt,
      displayName: displayName,
      attributes: Map<String, String>.unmodifiable(attributes),
      expired: isExpired,
    );
  }

  factory CredentialSecretRecord.fromJson(Map<String, Object?> json) {
    final keyJson = json['key'];
    return CredentialSecretRecord(
      key: keyJson is Map<String, Object?>
          ? CredentialDataStoreKey.fromJson(keyJson)
          : keyJson is Map
          ? CredentialDataStoreKey.fromJson(
              keyJson.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : CredentialDataStoreKey(
              namespace: json['namespace'] as String? ?? 'default',
              name: json['name'] as String? ?? 'credential',
              scope: credentialScopeFromWireValue(json['scope'] as String?),
              targetId: json['targetId'] as String?,
            ),
      kind: credentialKindFromWireValue(json['kind'] as String?),
      secretValue: json['secretValue'] as String? ?? '',
      createdAt: _dateTimeFromJson(json['createdAt']) ?? DateTime.now().toUtc(),
      updatedAt: _dateTimeFromJson(json['updatedAt']) ?? DateTime.now().toUtc(),
      expiresAt: _dateTimeFromJson(json['expiresAt']),
      displayName: json['displayName'] as String?,
      attributes: _stringMapFromJson(json['attributes']),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key.toJson(),
      'kind': kind.wireValue,
      'secretValue': secretValue,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      if (displayName != null) 'displayName': displayName,
      'attributes': attributes,
    };
  }

  static String _redact(String value) {
    if (value.isEmpty) {
      return '';
    }
    if (value.length <= 4) {
      return '****';
    }
    return '${value.substring(0, 2)}****${value.substring(value.length - 2)}';
  }
}

DateTime? _dateTimeFromJson(Object? value) {
  if (value is String) {
    return DateTime.tryParse(value)?.toUtc();
  }
  return null;
}

Map<String, String> _stringMapFromJson(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }
  return Map<String, String>.unmodifiable(
    value.map((key, value) => MapEntry(key.toString(), value.toString())),
  );
}

class CredentialMetadata {
  const CredentialMetadata({
    required this.key,
    required this.kind,
    required this.redactedValue,
    required this.createdAt,
    required this.updatedAt,
    required this.expired,
    this.expiresAt,
    this.displayName,
    this.attributes = const <String, String>{},
  });

  final CredentialDataStoreKey key;
  final CredentialKind kind;
  final String redactedValue;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? expiresAt;
  final String? displayName;
  final Map<String, String> attributes;
  final bool expired;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'key': key.toJson(),
      'kind': kind.wireValue,
      'redactedValue': redactedValue,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      if (expiresAt != null) 'expiresAt': expiresAt!.toIso8601String(),
      if (displayName != null) 'displayName': displayName,
      'attributes': attributes,
      'expired': expired,
    };
  }
}

class CredentialDataStoreSnapshot {
  const CredentialDataStoreSnapshot({required this.credentials});

  final List<CredentialMetadata> credentials;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'credentials': credentials
          .map((credential) => credential.toJson())
          .toList(growable: false),
    };
  }
}

enum CredentialInjectionStatus {
  injected,
  missingCredential,
  expiredCredential,
  kindMismatch,
  emptySecret,
}

CredentialInjectionStatus credentialInjectionStatusFromWireValue(
  String? value,
) {
  return switch (value) {
    'injected' => CredentialInjectionStatus.injected,
    'missingCredential' => CredentialInjectionStatus.missingCredential,
    'expiredCredential' => CredentialInjectionStatus.expiredCredential,
    'kindMismatch' => CredentialInjectionStatus.kindMismatch,
    'emptySecret' => CredentialInjectionStatus.emptySecret,
    _ => CredentialInjectionStatus.missingCredential,
  };
}

enum CredentialAccessPurpose {
  injection,
  providerConnection,
  toolchainRegistry,
  remoteService,
  unknown,
}

extension CredentialAccessPurposeX on CredentialAccessPurpose {
  String get wireValue => switch (this) {
    CredentialAccessPurpose.injection => 'injection',
    CredentialAccessPurpose.providerConnection => 'provider-connection',
    CredentialAccessPurpose.toolchainRegistry => 'toolchain-registry',
    CredentialAccessPurpose.remoteService => 'remote-service',
    CredentialAccessPurpose.unknown => 'unknown',
  };
}

CredentialAccessPurpose credentialAccessPurposeFromWireValue(String? value) {
  return switch (value) {
    'injection' => CredentialAccessPurpose.injection,
    'provider-connection' => CredentialAccessPurpose.providerConnection,
    'toolchain-registry' => CredentialAccessPurpose.toolchainRegistry,
    'remote-service' => CredentialAccessPurpose.remoteService,
    _ => CredentialAccessPurpose.unknown,
  };
}

enum CredentialStorageProtection {
  volatileMemory,
  foundationDataStore,
  platformSecureStorage,
  unknown,
}

extension CredentialStorageProtectionX on CredentialStorageProtection {
  String get wireValue => switch (this) {
    CredentialStorageProtection.volatileMemory => 'volatile-memory',
    CredentialStorageProtection.foundationDataStore => 'foundation-data-store',
    CredentialStorageProtection.platformSecureStorage =>
      'platform-secure-storage',
    CredentialStorageProtection.unknown => 'unknown',
  };
}

class CredentialAuditRetentionPolicy {
  const CredentialAuditRetentionPolicy({
    this.retention = const Duration(days: 90),
    this.maxEntries = 1000,
    this.redactSecretValues = true,
  });

  final Duration retention;
  final int maxEntries;
  final bool redactSecretValues;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'retentionDays': retention.inDays,
      'maxEntries': maxEntries,
      'redactSecretValues': redactSecretValues,
    };
  }
}

class CredentialDataStoreHealth {
  const CredentialDataStoreHealth({
    required this.protection,
    required this.persistent,
    required this.safeForLongLivedSecrets,
    required this.message,
    this.adapterId = '',
    this.backendId = '',
    this.productionReady = false,
    this.auditRetentionPolicy = const CredentialAuditRetentionPolicy(),
    this.todo = '',
  });

  final CredentialStorageProtection protection;
  final bool persistent;
  final bool safeForLongLivedSecrets;
  final String message;
  final String adapterId;
  final String backendId;
  final bool productionReady;
  final CredentialAuditRetentionPolicy auditRetentionPolicy;
  final String todo;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'protection': protection.wireValue,
      'persistent': persistent,
      'safeForLongLivedSecrets': safeForLongLivedSecrets,
      'productionReady': productionReady,
      'message': message,
      if (adapterId.isNotEmpty) 'adapterId': adapterId,
      if (backendId.isNotEmpty) 'backendId': backendId,
      'auditRetentionPolicy': auditRetentionPolicy.toJson(),
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

enum CredentialStoragePolicyDecisionKind { allowed, warning, blocked }

extension CredentialStoragePolicyDecisionKindX
    on CredentialStoragePolicyDecisionKind {
  String get wireValue => switch (this) {
    CredentialStoragePolicyDecisionKind.allowed => 'allowed',
    CredentialStoragePolicyDecisionKind.warning => 'warning',
    CredentialStoragePolicyDecisionKind.blocked => 'blocked',
  };
}

class CredentialStoragePolicyDecision {
  const CredentialStoragePolicyDecision({
    required this.kind,
    required this.reason,
    this.todo = '',
  });

  final CredentialStoragePolicyDecisionKind kind;
  final String reason;
  final String todo;

  bool get allowed => kind != CredentialStoragePolicyDecisionKind.blocked;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'allowed': allowed,
      'reason': reason,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class CredentialStoragePolicy {
  const CredentialStoragePolicy({
    this.allowUnsafePersistentLongLivedSecrets = false,
    this.longLivedSecretThreshold = const Duration(days: 30),
  });

  final bool allowUnsafePersistentLongLivedSecrets;
  final Duration longLivedSecretThreshold;

  CredentialStoragePolicyDecision evaluateWrite({
    required CredentialSecretRecord record,
    required CredentialDataStoreHealth health,
    DateTime? now,
  }) {
    if (health.safeForLongLivedSecrets) {
      return CredentialStoragePolicyDecision(
        kind: CredentialStoragePolicyDecisionKind.allowed,
        reason:
            'Credential store ${health.protection.wireValue} is safe for long-lived secrets.',
      );
    }

    final longLived = _isLongLived(record, now: now);
    if (health.persistent && longLived) {
      if (allowUnsafePersistentLongLivedSecrets) {
        return const CredentialStoragePolicyDecision(
          kind: CredentialStoragePolicyDecisionKind.warning,
          reason:
              'Long-lived credential is allowed by explicit unsafe policy override.',
          todo:
              'TODO: migrate this credential to a platform secure storage adapter.',
        );
      }
      return const CredentialStoragePolicyDecision(
        kind: CredentialStoragePolicyDecisionKind.blocked,
        reason:
            'Long-lived credential cannot be stored in persistent non-secure storage.',
        todo:
            'TODO: use platform secure storage before accepting long-lived provider tokens.',
      );
    }

    return CredentialStoragePolicyDecision(
      kind: CredentialStoragePolicyDecisionKind.warning,
      reason:
          'Credential store ${health.protection.wireValue} is not safe for long-lived secrets; only short-lived or test credentials should use it.',
      todo:
          'TODO: replace this storage route with a platform secure storage adapter for production secrets.',
    );
  }

  bool _isLongLived(CredentialSecretRecord record, {DateTime? now}) {
    final expiresAt = record.expiresAt;
    if (expiresAt == null) {
      return true;
    }
    final referenceTime = now ?? DateTime.now().toUtc();
    return expiresAt.difference(referenceTime) > longLivedSecretThreshold;
  }
}

class CredentialInjectionBinding {
  const CredentialInjectionBinding({
    required this.targetName,
    required this.reference,
    this.valuePrefix = '',
  });

  final String targetName;
  final CredentialReference reference;
  final String valuePrefix;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'targetName': targetName,
      'reference': reference.toJson(),
      if (valuePrefix.isNotEmpty) 'valuePrefix': valuePrefix,
    };
  }
}

class CredentialInjectedValue {
  const CredentialInjectedValue({
    required this.targetName,
    required this.reference,
    required this.value,
    required this.redactedValue,
  });

  final String targetName;
  final CredentialReference reference;
  final String value;
  final String redactedValue;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'targetName': targetName,
      'reference': reference.toJson(),
      'redactedValue': redactedValue,
    };
  }
}

class CredentialInjectionResult {
  const CredentialInjectionResult({
    required this.binding,
    required this.status,
    this.injectedValue,
    this.metadata,
  });

  final CredentialInjectionBinding binding;
  final CredentialInjectionStatus status;
  final CredentialInjectedValue? injectedValue;
  final CredentialMetadata? metadata;

  bool get injected => status == CredentialInjectionStatus.injected;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'binding': binding.toJson(),
      'status': status.name,
      if (injectedValue != null) 'injectedValue': injectedValue!.toJson(),
      if (metadata != null) 'metadata': metadata!.toJson(),
    };
  }
}

class CredentialInjectionBatch {
  const CredentialInjectionBatch({required this.results});

  final List<CredentialInjectionResult> results;

  bool get ready {
    return results.every((result) => result.injected);
  }

  Map<String, String> get injectedValues {
    return <String, String>{
      for (final result in results)
        if (result.injectedValue != null)
          result.injectedValue!.targetName: result.injectedValue!.value,
    };
  }

  Map<String, String> get redactedValues {
    return <String, String>{
      for (final result in results)
        if (result.injectedValue != null)
          result.injectedValue!.targetName: result.injectedValue!.redactedValue,
    };
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'ready': ready,
      'results': results
          .map((result) => result.toJson())
          .toList(growable: false),
    };
  }
}

class CredentialAccessAuditEntry {
  const CredentialAccessAuditEntry({
    required this.requestedAt,
    required this.requesterId,
    required this.purpose,
    required this.targetName,
    required this.reference,
    required this.status,
    this.redactedValue,
    this.message,
  });

  final DateTime requestedAt;
  final String requesterId;
  final CredentialAccessPurpose purpose;
  final String targetName;
  final CredentialReference reference;
  final CredentialInjectionStatus status;
  final String? redactedValue;
  final String? message;

  factory CredentialAccessAuditEntry.fromJson(Map<String, Object?> json) {
    final referenceJson = json['reference'];
    return CredentialAccessAuditEntry(
      requestedAt:
          _dateTimeFromJson(json['requestedAt']) ?? DateTime.now().toUtc(),
      requesterId: json['requesterId'] as String? ?? 'unknown',
      purpose: credentialAccessPurposeFromWireValue(json['purpose'] as String?),
      targetName: json['targetName'] as String? ?? 'credential',
      reference: referenceJson is Map<String, Object?>
          ? CredentialReference.fromJson(referenceJson)
          : referenceJson is Map
          ? CredentialReference.fromJson(
              referenceJson.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : CredentialReference(
              key: CredentialDataStoreKey(
                namespace: json['namespace'] as String? ?? 'default',
                name: json['name'] as String? ?? 'credential',
                scope: credentialScopeFromWireValue(json['scope'] as String?),
                targetId: json['targetId'] as String?,
              ),
              kind: credentialKindFromWireValue(json['kind'] as String?),
            ),
      status: credentialInjectionStatusFromWireValue(json['status'] as String?),
      redactedValue: json['redactedValue'] as String?,
      message: json['message'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'requestedAt': requestedAt.toIso8601String(),
      'requesterId': requesterId,
      'purpose': purpose.wireValue,
      'targetName': targetName,
      'reference': reference.toJson(),
      'status': status.name,
      if (redactedValue != null) 'redactedValue': redactedValue,
      if (message != null) 'message': message,
    };
  }
}

class CredentialAccessAuditSnapshot {
  const CredentialAccessAuditSnapshot({required this.entries});

  final List<CredentialAccessAuditEntry> entries;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }
}

abstract class CredentialAccessAuditStore {
  Future<void> append(CredentialAccessAuditEntry entry);

  Future<List<CredentialAccessAuditEntry>> list({
    CredentialAccessPurpose? purpose,
    String? requesterId,
  });

  Future<void> clear();

  Future<CredentialAccessAuditSnapshot> snapshot() async {
    return CredentialAccessAuditSnapshot(entries: await list());
  }
}

class InMemoryCredentialAccessAuditStore extends CredentialAccessAuditStore {
  final List<CredentialAccessAuditEntry> _entries =
      <CredentialAccessAuditEntry>[];

  @override
  Future<void> append(CredentialAccessAuditEntry entry) async {
    _entries.add(entry);
  }

  @override
  Future<List<CredentialAccessAuditEntry>> list({
    CredentialAccessPurpose? purpose,
    String? requesterId,
  }) async {
    return _entries
        .where((entry) {
          final purposeMatches = purpose == null || entry.purpose == purpose;
          final requesterMatches =
              requesterId == null || entry.requesterId == requesterId;
          return purposeMatches && requesterMatches;
        })
        .toList(growable: false);
  }

  @override
  Future<void> clear() async {
    _entries.clear();
  }
}

class FoundationCredentialAccessAuditStore extends CredentialAccessAuditStore {
  FoundationCredentialAccessAuditStore({
    required FoundationDataStore dataStore,
    this.namespaceName = 'configuration.credential-access-audit',
  }) : _dataStoreOwner = FoundationDataStoreOwner(
         descriptor: FoundationDataStoreOwnerDescriptor(
           ownerId: 'environment.configuration.credential-access-audit',
           layer: 'environment',
           stateFamily: 'credential-access-audit',
           allowedNamespaces: <String>{namespaceName},
         ),
         dataStore: dataStore,
       );

  FoundationCredentialAccessAuditStore.withOwner({
    required FoundationDataStoreOwner dataStoreOwner,
    this.namespaceName = 'configuration.credential-access-audit',
  }) : _dataStoreOwner = dataStoreOwner;

  static const String _recordKey = 'credential-access-audit-records';

  final FoundationDataStoreOwner _dataStoreOwner;
  final String namespaceName;

  @override
  Future<void> append(CredentialAccessAuditEntry entry) async {
    await _dataStoreOwner.editJson(
      namespaceName: namespaceName,
      key: _recordKey,
      schemaVersion: 1,
      scope: FoundationResourceScope.user,
      edit: (current) {
        final entries = _entriesFromValue(current);
        entries.add(entry);
        return FoundationDataStoreEditDecision.write(_entriesToValue(entries));
      },
    );
  }

  @override
  Future<List<CredentialAccessAuditEntry>> list({
    CredentialAccessPurpose? purpose,
    String? requesterId,
  }) async {
    final entries = _entriesFromValue(
      await _dataStoreOwner.readJson(
        namespaceName: namespaceName,
        key: _recordKey,
        schemaVersion: 1,
        scope: FoundationResourceScope.user,
      ),
    );
    return entries
        .where((entry) {
          final purposeMatches = purpose == null || entry.purpose == purpose;
          final requesterMatches =
              requesterId == null || entry.requesterId == requesterId;
          return purposeMatches && requesterMatches;
        })
        .toList(growable: false);
  }

  @override
  Future<void> clear() async {
    await _dataStoreOwner.editJson(
      namespaceName: namespaceName,
      key: _recordKey,
      schemaVersion: 1,
      scope: FoundationResourceScope.user,
      edit: (current) => FoundationDataStoreEditDecision.delete,
    );
  }

  List<CredentialAccessAuditEntry> _entriesFromValue(
    Map<String, Object?>? value,
  ) {
    final entriesJson = value?['entries'];
    if (entriesJson is! List) {
      return <CredentialAccessAuditEntry>[];
    }
    final entries = <CredentialAccessAuditEntry>[];
    for (final entryJson in entriesJson) {
      final json = _mapFromJson(entryJson);
      if (json == null) {
        continue;
      }
      entries.add(CredentialAccessAuditEntry.fromJson(json));
    }
    return entries;
  }

  Map<String, Object?> _entriesToValue(
    List<CredentialAccessAuditEntry> entries,
  ) {
    return <String, Object?>{
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  Map<String, Object?>? _mapFromJson(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      );
    }
    return null;
  }
}

class CredentialSecretInjector {
  const CredentialSecretInjector({
    required this.credentialDataStore,
    this.accessAuditStore,
    this.requesterId = 'credential-secret-injector',
    this.accessPurpose = CredentialAccessPurpose.injection,
  });

  final CredentialDataStore credentialDataStore;
  final CredentialAccessAuditStore? accessAuditStore;
  final String requesterId;
  final CredentialAccessPurpose accessPurpose;

  Future<CredentialInjectionResult> inject(
    CredentialInjectionBinding binding,
  ) async {
    final record = await credentialDataStore.read(binding.reference.key);
    final metadata = await _metadataFor(binding.reference.key);
    late final CredentialInjectionResult result;
    if (record == null) {
      result = CredentialInjectionResult(
        binding: binding,
        status: metadata?.expired == true
            ? CredentialInjectionStatus.expiredCredential
            : CredentialInjectionStatus.missingCredential,
        metadata: metadata,
      );
    } else if (record.kind != binding.reference.kind) {
      result = CredentialInjectionResult(
        binding: binding,
        status: CredentialInjectionStatus.kindMismatch,
        metadata: record.toMetadata(),
      );
    } else if (record.secretValue.trim().isEmpty) {
      result = CredentialInjectionResult(
        binding: binding,
        status: CredentialInjectionStatus.emptySecret,
        metadata: record.toMetadata(),
      );
    } else {
      final secret = record.secretValue.trim();
      final redacted = _redactSecret(secret);
      result = CredentialInjectionResult(
        binding: binding,
        status: CredentialInjectionStatus.injected,
        injectedValue: CredentialInjectedValue(
          targetName: binding.targetName,
          reference: binding.reference,
          value: '${binding.valuePrefix}$secret',
          redactedValue: '${binding.valuePrefix}$redacted',
        ),
        metadata: record.toMetadata(),
      );
    }
    await _recordAccess(result);
    return result;
  }

  String _redactSecret(String value) {
    if (value.length <= 4) {
      return '****';
    }
    return '${value.substring(0, 2)}****${value.substring(value.length - 2)}';
  }

  Future<CredentialInjectionBatch> injectAll(
    Iterable<CredentialInjectionBinding> bindings,
  ) async {
    final results = <CredentialInjectionResult>[];
    for (final binding in bindings) {
      results.add(await inject(binding));
    }
    return CredentialInjectionBatch(results: results);
  }

  Future<void> _recordAccess(CredentialInjectionResult result) async {
    final store = accessAuditStore;
    if (store == null) {
      return;
    }
    await store.append(
      CredentialAccessAuditEntry(
        requestedAt: DateTime.now().toUtc(),
        requesterId: requesterId,
        purpose: accessPurpose,
        targetName: result.binding.targetName,
        reference: result.binding.reference,
        status: result.status,
        redactedValue:
            result.injectedValue?.redactedValue ??
            result.metadata?.redactedValue,
      ),
    );
  }

  Future<CredentialMetadata?> _metadataFor(CredentialDataStoreKey key) async {
    final credentials = await credentialDataStore.list(scope: key.scope);
    for (final credential in credentials) {
      if (credential.key.stableId == key.stableId) {
        return credential;
      }
    }
    return null;
  }
}

abstract class CredentialDataStore {
  Future<void> write(CredentialSecretRecord record);

  Future<CredentialSecretRecord?> read(CredentialDataStoreKey key);

  Future<bool> delete(CredentialDataStoreKey key);

  Future<List<CredentialMetadata>> list({CredentialScope? scope});

  Future<CredentialDataStoreSnapshot> snapshot() async {
    return CredentialDataStoreSnapshot(credentials: await list());
  }

  Future<CredentialDataStoreHealth> health() async {
    return const CredentialDataStoreHealth(
      protection: CredentialStorageProtection.unknown,
      persistent: false,
      safeForLongLivedSecrets: false,
      message: 'Credential DataStore health is unknown.',
      todo:
          'TODO: implement a concrete credential storage health contract for this store.',
    );
  }
}

class InMemoryCredentialDataStore extends CredentialDataStore {
  final Map<String, CredentialSecretRecord> _records =
      <String, CredentialSecretRecord>{};

  @override
  Future<void> write(CredentialSecretRecord record) async {
    _records[record.key.stableId] = record;
  }

  @override
  Future<CredentialSecretRecord?> read(CredentialDataStoreKey key) async {
    final record = _records[key.stableId];
    if (record == null || record.isExpired) {
      return null;
    }
    return record;
  }

  @override
  Future<bool> delete(CredentialDataStoreKey key) async {
    return _records.remove(key.stableId) != null;
  }

  @override
  Future<List<CredentialMetadata>> list({CredentialScope? scope}) async {
    final records = _records.values
        .where((record) {
          return scope == null || record.key.scope == scope;
        })
        .toList(growable: false);
    records.sort(
      (left, right) => left.key.stableId.compareTo(right.key.stableId),
    );
    return records.map((record) => record.toMetadata()).toList(growable: false);
  }

  @override
  Future<CredentialDataStoreHealth> health() async {
    return const CredentialDataStoreHealth(
      protection: CredentialStorageProtection.volatileMemory,
      persistent: false,
      safeForLongLivedSecrets: false,
      message:
          'Credentials are kept in memory only and are suitable for tests or short-lived sessions.',
      todo:
          'TODO: use a platform secure storage adapter for persisted production tokens.',
    );
  }
}

abstract class PlatformSecureCredentialStorageAdapter {
  const PlatformSecureCredentialStorageAdapter();

  String get adapterId;

  Future<void> write(CredentialSecretRecord record);

  Future<CredentialSecretRecord?> read(CredentialDataStoreKey key);

  Future<bool> delete(CredentialDataStoreKey key);

  Future<List<CredentialSecretRecord>> list({CredentialScope? scope});

  Future<CredentialDataStoreHealth> health();
}

enum PlatformSecureCredentialBackendKind {
  vsCodeSecretStorage,
  macosKeychain,
  windowsCredentialManager,
  linuxLibsecret,
  memoryFixture,
  custom,
}

extension PlatformSecureCredentialBackendKindX
    on PlatformSecureCredentialBackendKind {
  String get wireValue {
    return switch (this) {
      PlatformSecureCredentialBackendKind.vsCodeSecretStorage =>
        'vscode-secret-storage',
      PlatformSecureCredentialBackendKind.macosKeychain => 'macos-keychain',
      PlatformSecureCredentialBackendKind.windowsCredentialManager =>
        'windows-credential-manager',
      PlatformSecureCredentialBackendKind.linuxLibsecret => 'linux-libsecret',
      PlatformSecureCredentialBackendKind.memoryFixture => 'memory-fixture',
      PlatformSecureCredentialBackendKind.custom => 'custom',
    };
  }
}

class PlatformSecureCredentialBackendDescriptor {
  const PlatformSecureCredentialBackendDescriptor({
    required this.backendId,
    required this.label,
    required this.kind,
    this.available = true,
    this.productionReady = false,
    this.platformId = '',
    this.message = '',
  });

  final String backendId;
  final String label;
  final PlatformSecureCredentialBackendKind kind;
  final bool available;
  final bool productionReady;
  final String platformId;
  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'backendId': backendId,
      'label': label,
      'kind': kind.wireValue,
      'available': available,
      'productionReady': productionReady,
      if (platformId.isNotEmpty) 'platformId': platformId,
      if (message.isNotEmpty) 'message': message,
    };
  }
}

class PlatformSecureCredentialStorageAdapterRegistration {
  const PlatformSecureCredentialStorageAdapterRegistration({
    required this.descriptor,
    required this.adapter,
  });

  final PlatformSecureCredentialBackendDescriptor descriptor;
  final PlatformSecureCredentialStorageAdapter adapter;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'descriptor': descriptor.toJson(),
      'adapterId': adapter.adapterId,
    };
  }
}

enum PlatformSecureCredentialStorageSelectionStatus {
  selected,
  missingBackend,
  missingProductionBackend,
}

extension PlatformSecureCredentialStorageSelectionStatusX
    on PlatformSecureCredentialStorageSelectionStatus {
  String get wireValue {
    return switch (this) {
      PlatformSecureCredentialStorageSelectionStatus.selected => 'selected',
      PlatformSecureCredentialStorageSelectionStatus.missingBackend =>
        'missing-backend',
      PlatformSecureCredentialStorageSelectionStatus.missingProductionBackend =>
        'missing-production-backend',
    };
  }
}

class PlatformSecureCredentialStorageSelection {
  const PlatformSecureCredentialStorageSelection({
    required this.status,
    required this.message,
    this.registration,
  });

  final PlatformSecureCredentialStorageSelectionStatus status;
  final String message;
  final PlatformSecureCredentialStorageAdapterRegistration? registration;

  bool get selected =>
      status == PlatformSecureCredentialStorageSelectionStatus.selected;

  PlatformSecureCredentialDataStore? toDataStore() {
    final adapter = registration?.adapter;
    if (adapter == null) {
      return null;
    }
    return PlatformSecureCredentialDataStore(adapter: adapter);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'selected': selected,
      'message': message,
      if (registration != null) 'registration': registration!.toJson(),
    };
  }
}

class PlatformSecureCredentialStorageAdapterRegistry {
  PlatformSecureCredentialStorageAdapterRegistry({
    Iterable<PlatformSecureCredentialStorageAdapterRegistration> registrations =
        const <PlatformSecureCredentialStorageAdapterRegistration>[],
  }) {
    for (final registration in registrations) {
      register(registration);
    }
  }

  final List<PlatformSecureCredentialStorageAdapterRegistration>
  _registrations = <PlatformSecureCredentialStorageAdapterRegistration>[];

  List<PlatformSecureCredentialStorageAdapterRegistration> get registrations =>
      List<PlatformSecureCredentialStorageAdapterRegistration>.unmodifiable(
        _registrations,
      );

  void register(
    PlatformSecureCredentialStorageAdapterRegistration registration,
  ) {
    _registrations.removeWhere(
      (candidate) =>
          candidate.descriptor.backendId == registration.descriptor.backendId,
    );
    _registrations.add(registration);
  }

  PlatformSecureCredentialStorageSelection select({
    bool requireProductionReady = true,
    String platformId = '',
  }) {
    final candidates = _registrations
        .where((registration) {
          final descriptor = registration.descriptor;
          final platformMatches =
              platformId.trim().isEmpty ||
              descriptor.platformId.isEmpty ||
              descriptor.platformId == platformId;
          return descriptor.available && platformMatches;
        })
        .toList(growable: false);
    if (candidates.isEmpty) {
      return const PlatformSecureCredentialStorageSelection(
        status: PlatformSecureCredentialStorageSelectionStatus.missingBackend,
        message: 'No platform secure credential storage backend is available.',
      );
    }
    final productionCandidates = candidates
        .where((registration) => registration.descriptor.productionReady)
        .toList(growable: false);
    if (requireProductionReady && productionCandidates.isEmpty) {
      return const PlatformSecureCredentialStorageSelection(
        status: PlatformSecureCredentialStorageSelectionStatus
            .missingProductionBackend,
        message:
            'No production-ready platform secure credential storage backend is available.',
      );
    }
    final selected = productionCandidates.isNotEmpty
        ? productionCandidates.first
        : candidates.first;
    return PlatformSecureCredentialStorageSelection(
      status: PlatformSecureCredentialStorageSelectionStatus.selected,
      registration: selected,
      message:
          'Selected platform secure credential storage backend ${selected.descriptor.backendId}.',
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'backendCount': _registrations.length,
      'productionReadyCount': _registrations
          .where((registration) => registration.descriptor.productionReady)
          .length,
      'registrations': _registrations
          .map((registration) => registration.toJson())
          .toList(growable: false),
    };
  }
}

class InMemoryPlatformSecureCredentialStorageAdapter
    extends PlatformSecureCredentialStorageAdapter {
  InMemoryPlatformSecureCredentialStorageAdapter({
    this.adapterId = 'in-memory-platform-secure-storage',
  });

  @override
  final String adapterId;

  final Map<String, CredentialSecretRecord> _records =
      <String, CredentialSecretRecord>{};

  @override
  Future<void> write(CredentialSecretRecord record) async {
    _records[record.key.stableId] = record;
  }

  @override
  Future<CredentialSecretRecord?> read(CredentialDataStoreKey key) async {
    final record = _records[key.stableId];
    if (record == null || record.isExpired) {
      return null;
    }
    return record;
  }

  @override
  Future<bool> delete(CredentialDataStoreKey key) async {
    return _records.remove(key.stableId) != null;
  }

  @override
  Future<List<CredentialSecretRecord>> list({CredentialScope? scope}) async {
    final records = _records.values
        .where((record) => scope == null || record.key.scope == scope)
        .toList(growable: false);
    records.sort(
      (left, right) => left.key.stableId.compareTo(right.key.stableId),
    );
    return records;
  }

  @override
  Future<CredentialDataStoreHealth> health() async {
    return CredentialDataStoreHealth(
      protection: CredentialStorageProtection.platformSecureStorage,
      persistent: true,
      safeForLongLivedSecrets: true,
      adapterId: adapterId,
      backendId: 'memory-secure-fixture',
      productionReady: false,
      message: 'Secure credential adapter $adapterId is available.',
      auditRetentionPolicy: const CredentialAuditRetentionPolicy(
        retention: Duration(days: 7),
        maxEntries: 200,
      ),
      todo:
          'TODO: replace in-memory secure adapter with OS-backed SecretStorage, Keychain, Credential Manager, or libsecret.',
    );
  }
}

class PlatformSecureCredentialDataStore extends CredentialDataStore {
  PlatformSecureCredentialDataStore({required this.adapter});

  final PlatformSecureCredentialStorageAdapter adapter;

  @override
  Future<void> write(CredentialSecretRecord record) {
    return adapter.write(record);
  }

  @override
  Future<CredentialSecretRecord?> read(CredentialDataStoreKey key) {
    return adapter.read(key);
  }

  @override
  Future<bool> delete(CredentialDataStoreKey key) {
    return adapter.delete(key);
  }

  @override
  Future<List<CredentialMetadata>> list({CredentialScope? scope}) async {
    final records = await adapter.list(scope: scope);
    return records.map((record) => record.toMetadata()).toList(growable: false);
  }

  @override
  Future<CredentialDataStoreHealth> health() {
    return adapter.health();
  }
}

class CredentialStoragePolicyEnforcingDataStore extends CredentialDataStore {
  CredentialStoragePolicyEnforcingDataStore({
    required this.delegate,
    this.policy = const CredentialStoragePolicy(),
    this.now,
  });

  final CredentialDataStore delegate;
  final CredentialStoragePolicy policy;
  final DateTime Function()? now;

  @override
  Future<void> write(CredentialSecretRecord record) async {
    final decision = policy.evaluateWrite(
      record: record,
      health: await delegate.health(),
      now: now?.call(),
    );
    if (!decision.allowed) {
      throw StateError(decision.reason);
    }
    await delegate.write(record);
  }

  @override
  Future<CredentialSecretRecord?> read(CredentialDataStoreKey key) {
    return delegate.read(key);
  }

  @override
  Future<bool> delete(CredentialDataStoreKey key) {
    return delegate.delete(key);
  }

  @override
  Future<List<CredentialMetadata>> list({CredentialScope? scope}) {
    return delegate.list(scope: scope);
  }

  @override
  Future<CredentialDataStoreSnapshot> snapshot() {
    return delegate.snapshot();
  }

  @override
  Future<CredentialDataStoreHealth> health() {
    return delegate.health();
  }
}

class FoundationCredentialDataStore extends CredentialDataStore {
  FoundationCredentialDataStore({
    required FoundationDataStore dataStore,
    this.namespaceName = 'configuration.credentials',
  }) : _dataStoreOwner = FoundationDataStoreOwner(
         descriptor: FoundationDataStoreOwnerDescriptor(
           ownerId: 'environment.configuration.credentials',
           layer: 'environment',
           stateFamily: 'credentials',
           allowedNamespaces: <String>{namespaceName},
         ),
         dataStore: dataStore,
       );

  FoundationCredentialDataStore.withOwner({
    required FoundationDataStoreOwner dataStoreOwner,
    this.namespaceName = 'configuration.credentials',
  }) : _dataStoreOwner = dataStoreOwner;

  static const String _recordKey = 'credential-records';

  final FoundationDataStoreOwner _dataStoreOwner;
  final String namespaceName;

  @override
  Future<void> write(CredentialSecretRecord record) async {
    await _dataStoreOwner.editJson(
      namespaceName: namespaceName,
      key: _recordKey,
      schemaVersion: 1,
      scope: FoundationResourceScope.user,
      edit: (current) {
        final records = _recordsFromValue(current);
        records[record.key.stableId] = record;
        return FoundationDataStoreEditDecision.write(_recordsToValue(records));
      },
    );
  }

  @override
  Future<CredentialSecretRecord?> read(CredentialDataStoreKey key) async {
    final record = (await _loadRecords())[key.stableId];
    if (record == null || record.isExpired) {
      return null;
    }
    return record;
  }

  @override
  Future<bool> delete(CredentialDataStoreKey key) async {
    var removed = false;
    await _dataStoreOwner.editJson(
      namespaceName: namespaceName,
      key: _recordKey,
      schemaVersion: 1,
      scope: FoundationResourceScope.user,
      edit: (current) {
        final records = _recordsFromValue(current);
        removed = records.remove(key.stableId) != null;
        if (!removed) {
          return FoundationDataStoreEditDecision.keep;
        }
        if (records.isEmpty) {
          return FoundationDataStoreEditDecision.delete;
        }
        return FoundationDataStoreEditDecision.write(_recordsToValue(records));
      },
    );
    return removed;
  }

  @override
  Future<List<CredentialMetadata>> list({CredentialScope? scope}) async {
    final records = (await _loadRecords()).values
        .where((record) {
          return scope == null || record.key.scope == scope;
        })
        .toList(growable: false);
    records.sort(
      (left, right) => left.key.stableId.compareTo(right.key.stableId),
    );
    return records.map((record) => record.toMetadata()).toList(growable: false);
  }

  @override
  Future<CredentialDataStoreHealth> health() async {
    return const CredentialDataStoreHealth(
      protection: CredentialStorageProtection.foundationDataStore,
      persistent: true,
      safeForLongLivedSecrets: false,
      message:
          'Credentials are persisted through FoundationDataStore, not a platform secure secret store.',
      todo:
          'TODO: replace persisted secrets with OS-backed secure storage such as SecretStorage, Keychain, Credential Manager, or libsecret.',
    );
  }

  Future<Map<String, CredentialSecretRecord>> _loadRecords() async {
    final value = await _dataStoreOwner.readJson(
      namespaceName: namespaceName,
      key: _recordKey,
      schemaVersion: 1,
      scope: FoundationResourceScope.user,
    );
    final recordsJson = value?['records'];
    if (recordsJson is! List) {
      return <String, CredentialSecretRecord>{};
    }
    final records = <String, CredentialSecretRecord>{};
    for (final recordJson in recordsJson) {
      final json = _mapFromJson(recordJson);
      if (json == null) {
        continue;
      }
      final record = CredentialSecretRecord.fromJson(json);
      records[record.key.stableId] = record;
    }
    return records;
  }

  Map<String, CredentialSecretRecord> _recordsFromValue(
    Map<String, Object?>? value,
  ) {
    final recordsJson = value?['records'];
    if (recordsJson is! List) {
      return <String, CredentialSecretRecord>{};
    }
    final records = <String, CredentialSecretRecord>{};
    for (final recordJson in recordsJson) {
      final json = _mapFromJson(recordJson);
      if (json == null) {
        continue;
      }
      final record = CredentialSecretRecord.fromJson(json);
      records[record.key.stableId] = record;
    }
    return records;
  }

  Map<String, Object?> _recordsToValue(
    Map<String, CredentialSecretRecord> records,
  ) {
    return <String, Object?>{
      'records': records.values
          .map((record) => record.toJson())
          .toList(growable: false),
    };
  }

  Map<String, Object?>? _mapFromJson(Object? value) {
    if (value is Map<String, Object?>) {
      return value;
    }
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      );
    }
    return null;
  }
}
