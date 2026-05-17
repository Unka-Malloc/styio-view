import '../../foundation/foundation.dart';

enum CredentialKind {
  token,
  registryCredential,
  remoteServiceCredential,
  genericSecret,
}

enum CredentialScope {
  user,
  workspace,
  toolchain,
  service,
}

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
                (key, value) => MapEntry<String, Object?>(
                  key.toString(),
                  value,
                ),
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
                (key, value) => MapEntry<String, Object?>(
                  key.toString(),
                  value,
                ),
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

abstract class CredentialDataStore {
  Future<void> write(CredentialSecretRecord record);

  Future<CredentialSecretRecord?> read(CredentialDataStoreKey key);

  Future<bool> delete(CredentialDataStoreKey key);

  Future<List<CredentialMetadata>> list({CredentialScope? scope});

  Future<CredentialDataStoreSnapshot> snapshot() async {
    return CredentialDataStoreSnapshot(credentials: await list());
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
    final records = _records.values.where((record) {
      return scope == null || record.key.scope == scope;
    }).toList(growable: false);
    records.sort((left, right) => left.key.stableId.compareTo(right.key.stableId));
    return records.map((record) => record.toMetadata()).toList(growable: false);
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
    final records = (await _loadRecords()).values.where((record) {
      return scope == null || record.key.scope == scope;
    }).toList(growable: false);
    records.sort((left, right) => left.key.stableId.compareTo(right.key.stableId));
    return records.map((record) => record.toMetadata()).toList(growable: false);
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
