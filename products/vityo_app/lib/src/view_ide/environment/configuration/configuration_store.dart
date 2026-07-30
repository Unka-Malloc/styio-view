import 'dart:async';

import '../../foundation/foundation.dart';
import 'credential_data_store.dart';

class ConfigurationSettingKey {
  const ConfigurationSettingKey({
    required this.namespace,
    required this.name,
    this.workspaceId,
  });

  final String namespace;
  final String name;
  final String? workspaceId;

  String get stableKey {
    return <String>[
      namespace,
      if (workspaceId != null && workspaceId!.isNotEmpty) workspaceId!,
      name,
    ].join(':');
  }
}

class ConfigurationSettingRecord {
  const ConfigurationSettingRecord({
    required this.key,
    required this.value,
    this.credentialReferences = const <CredentialReference>[],
  });

  final ConfigurationSettingKey key;
  final Map<String, Object?> value;
  final List<CredentialReference> credentialReferences;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'namespace': key.namespace,
      'name': key.name,
      if (key.workspaceId != null) 'workspaceId': key.workspaceId,
      'value': value,
      'credentialReferences': credentialReferences
          .map((reference) => reference.toJson())
          .toList(growable: false),
    };
  }

  factory ConfigurationSettingRecord.fromJson(Map<String, Object?> json) {
    final value = json['value'];
    final credentialReferences = json['credentialReferences'];
    return ConfigurationSettingRecord(
      key: ConfigurationSettingKey(
        namespace: json['namespace'] as String? ?? 'default',
        name: json['name'] as String? ?? 'setting',
        workspaceId: json['workspaceId'] as String?,
      ),
      value: value is Map<String, Object?>
          ? value
          : value is Map
          ? value.map(
              (key, value) => MapEntry<String, Object?>(key.toString(), value),
            )
          : const <String, Object?>{},
      credentialReferences: credentialReferences is List
          ? credentialReferences
              .map(_credentialReferenceFromJson)
              .whereType<CredentialReference>()
              .toList(growable: false)
          : const <CredentialReference>[],
    );
  }
}

enum ConfigurationSettingChangeKind {
  written,
  updated,
  deleted,
  migrated,
}

class ConfigurationSettingChange {
  ConfigurationSettingChange({
    required this.kind,
    required this.key,
    required this.record,
    DateTime? emittedAt,
  }) : emittedAt = emittedAt ?? DateTime.now().toUtc();

  final ConfigurationSettingChangeKind kind;
  final ConfigurationSettingKey key;
  final ConfigurationSettingRecord? record;
  final DateTime emittedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'namespace': key.namespace,
      'name': key.name,
      if (key.workspaceId != null) 'workspaceId': key.workspaceId,
      if (record != null) 'record': record!.toJson(),
      'emittedAt': emittedAt.toIso8601String(),
    };
  }
}

typedef ConfigurationSettingUpdater =
    FutureOr<ConfigurationSettingRecord?> Function(
  ConfigurationSettingRecord? current,
);

typedef ConfigurationSettingEditor =
    FutureOr<ConfigurationSettingEditDecision> Function(
  ConfigurationSettingRecord? current,
);

enum ConfigurationSettingEditAction {
  write,
  delete,
  keep,
}

class ConfigurationSettingEditDecision {
  const ConfigurationSettingEditDecision._({
    required this.action,
    this.record,
  });

  factory ConfigurationSettingEditDecision.write(
    ConfigurationSettingRecord record,
  ) {
    return ConfigurationSettingEditDecision._(
      action: ConfigurationSettingEditAction.write,
      record: record,
    );
  }

  static const ConfigurationSettingEditDecision delete =
      ConfigurationSettingEditDecision._(
    action: ConfigurationSettingEditAction.delete,
  );

  static const ConfigurationSettingEditDecision keep =
      ConfigurationSettingEditDecision._(
    action: ConfigurationSettingEditAction.keep,
  );

  final ConfigurationSettingEditAction action;
  final ConfigurationSettingRecord? record;
}

CredentialReference? _credentialReferenceFromJson(Object? value) {
  if (value is Map<String, Object?>) {
    return CredentialReference.fromJson(value);
  }
  if (value is Map) {
    return CredentialReference.fromJson(
      value.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      ),
    );
  }
  return null;
}

class ConfigurationStore {
  ConfigurationStore({
    required FoundationDataStore dataStore,
    required CredentialDataStore credentialDataStore,
  }) : _dataStoreOwner = FoundationDataStoreOwner(
         descriptor: const FoundationDataStoreOwnerDescriptor(
           ownerId: 'environment.configuration',
           layer: 'environment',
           stateFamily: 'configuration',
           allowedNamespacePrefixes: <String>{'configuration.'},
         ),
         dataStore: dataStore,
       ),
       _credentialDataStore = credentialDataStore;

  const ConfigurationStore.withOwner({
    required FoundationDataStoreOwner dataStoreOwner,
    required CredentialDataStore credentialDataStore,
  }) : _dataStoreOwner = dataStoreOwner,
       _credentialDataStore = credentialDataStore;

  final FoundationDataStoreOwner _dataStoreOwner;
  final CredentialDataStore _credentialDataStore;

  Future<void> write(ConfigurationSettingRecord record) async {
    _assertNoSecretLikeValues(record.value);
    final namespace = _namespaceFor(record.key);
    await _dataStoreOwner.writeJson(
      namespaceName: namespace.name,
      key: record.key.stableKey,
      value: record.toJson(),
      schemaVersion: namespace.schemaVersion,
      scope: namespace.scope,
      workspaceId: namespace.workspaceId,
    );
  }

  Future<ConfigurationSettingRecord?> read(ConfigurationSettingKey key) async {
    final namespace = _namespaceFor(key);
    final value = await _dataStoreOwner.readJson(
      namespaceName: namespace.name,
      key: key.stableKey,
      schemaVersion: namespace.schemaVersion,
      scope: namespace.scope,
      workspaceId: namespace.workspaceId,
    );
    if (value == null) {
      return null;
    }
    return ConfigurationSettingRecord.fromJson(value);
  }

  Future<bool> delete(ConfigurationSettingKey key) {
    final namespace = _namespaceFor(key);
    return _dataStoreOwner.delete(
      namespaceName: namespace.name,
      key: key.stableKey,
      schemaVersion: namespace.schemaVersion,
      scope: namespace.scope,
      workspaceId: namespace.workspaceId,
    );
  }

  Future<ConfigurationSettingRecord?> update(
    ConfigurationSettingKey key,
    ConfigurationSettingUpdater update,
  ) async {
    final namespace = _namespaceFor(key);
    final next = await _dataStoreOwner.updateJson(
      namespaceName: namespace.name,
      key: key.stableKey,
      schemaVersion: namespace.schemaVersion,
      scope: namespace.scope,
      workspaceId: namespace.workspaceId,
      update: (current) async {
        final currentRecord = current == null
            ? null
            : ConfigurationSettingRecord.fromJson(current);
        final nextRecord = await update(currentRecord);
        if (nextRecord == null) {
          return null;
        }
        _assertNoSecretLikeValues(nextRecord.value);
        return nextRecord.toJson();
      },
    );
    return next == null ? null : ConfigurationSettingRecord.fromJson(next);
  }

  Future<ConfigurationSettingEditDecision> edit(
    ConfigurationSettingKey key,
    ConfigurationSettingEditor edit,
  ) async {
    final namespace = _namespaceFor(key);
    final decision = await _dataStoreOwner.editJson(
      namespaceName: namespace.name,
      key: key.stableKey,
      schemaVersion: namespace.schemaVersion,
      scope: namespace.scope,
      workspaceId: namespace.workspaceId,
      edit: (current) async {
        final currentRecord = current == null
            ? null
            : ConfigurationSettingRecord.fromJson(current);
        final decision = await edit(currentRecord);
        switch (decision.action) {
          case ConfigurationSettingEditAction.keep:
            return FoundationDataStoreEditDecision.keep;
          case ConfigurationSettingEditAction.delete:
            return FoundationDataStoreEditDecision.delete;
          case ConfigurationSettingEditAction.write:
            final record = decision.record;
            if (record == null) {
              return FoundationDataStoreEditDecision.keep;
            }
            _assertNoSecretLikeValues(record.value);
            return FoundationDataStoreEditDecision.write(record.toJson());
        }
      },
    );
    return switch (decision.action) {
      FoundationDataStoreEditAction.keep => ConfigurationSettingEditDecision.keep,
      FoundationDataStoreEditAction.delete =>
        ConfigurationSettingEditDecision.delete,
      FoundationDataStoreEditAction.write => ConfigurationSettingEditDecision.write(
        ConfigurationSettingRecord.fromJson(
          decision.value ?? const <String, Object?>{},
        ),
      ),
    };
  }

  Stream<ConfigurationSettingChange> watch(ConfigurationSettingKey key) {
    final namespace = _namespaceFor(key);
    return _dataStoreOwner
        .watchJson(
          namespaceName: namespace.name,
          key: key.stableKey,
          schemaVersion: namespace.schemaVersion,
          scope: namespace.scope,
          workspaceId: namespace.workspaceId,
        )
        .map(_changeFromFoundation);
  }

  Future<CredentialSecretRecord?> resolveCredential(
    CredentialReference reference,
  ) {
    return _credentialDataStore.read(reference.key);
  }

  Future<CredentialInjectionResult> injectCredential(
    CredentialInjectionBinding binding,
  ) {
    return CredentialSecretInjector(
      credentialDataStore: _credentialDataStore,
    ).inject(binding);
  }

  Future<CredentialInjectionBatch> injectCredentials(
    Iterable<CredentialInjectionBinding> bindings,
  ) {
    return CredentialSecretInjector(
      credentialDataStore: _credentialDataStore,
    ).injectAll(bindings);
  }

  FoundationDataStoreNamespace _namespaceFor(ConfigurationSettingKey key) {
    return FoundationDataStoreNamespace(
      name: 'configuration.${key.namespace}',
      schemaVersion: 1,
      scope: key.workspaceId == null
          ? FoundationResourceScope.user
          : FoundationResourceScope.workspace,
      workspaceId: key.workspaceId,
    );
  }

  void _assertNoSecretLikeValues(Object? value, {String path = 'value'}) {
    if (value is Map) {
      for (final entry in value.entries) {
        final key = entry.key.toString();
        final nestedPath = '$path.$key';
        if (_isSecretLikeConfigurationKey(key)) {
          throw ArgumentError.value(
            key,
            nestedPath,
            'Configuration values must store CredentialReference instead of raw secrets.',
          );
        }
        _assertNoSecretLikeValues(entry.value, path: nestedPath);
      }
      return;
    }
    if (value is Iterable) {
      var index = 0;
      for (final entry in value) {
        _assertNoSecretLikeValues(entry, path: '$path[$index]');
        index += 1;
      }
      return;
    }
    if (value is String && _containsSecretLikeString(value)) {
      throw ArgumentError.value(
        '<redacted>',
        path,
        'Configuration values must store CredentialReference instead of raw secrets.',
      );
    }
  }

  bool _isSecretLikeConfigurationKey(String key) {
    final normalized = key.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
    if (normalized.startsWith('credentialreference') ||
        normalized == 'credentialref' ||
        normalized.endsWith('environmentname') ||
        normalized == 'focustoken' ||
        normalized == 'semantictoken') {
      return false;
    }
    return normalized == 'authorization' ||
        normalized == 'apikey' ||
        normalized.endsWith('apikey') ||
        normalized == 'token' ||
        normalized.endsWith('bearertoken') ||
        normalized.endsWith('accesstoken') ||
        normalized.endsWith('refreshtoken') ||
        normalized.endsWith('idtoken') ||
        normalized.endsWith('authtoken') ||
        normalized.endsWith('githubtoken') ||
        normalized.endsWith('registrytoken') ||
        normalized.endsWith('secret') ||
        normalized.endsWith('password') ||
        normalized.endsWith('privatekey') ||
        normalized.endsWith('cloudsessionid') ||
        normalized.endsWith('hostedsessionid');
  }

  bool _containsSecretLikeString(String value) {
    return _secretLikeStringPatterns.any((pattern) => pattern.hasMatch(value));
  }

  static final List<RegExp> _secretLikeStringPatterns = <RegExp>[
    RegExp(
      r'\bAuthorization\s*[:=]\s*(?:Bearer|Basic)?\s*[A-Za-z0-9._~+/=-]{8,}',
      caseSensitive: false,
    ),
    RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]{8,}', caseSensitive: false),
    RegExp(
      r'[?&][a-z0-9_.-]*(?:api[_-]?key|apikey|access[_-]?token|'
      r'refresh[_-]?token|token|secret|password|session[_-]?id)=[^&\s]+',
      caseSensitive: false,
    ),
    RegExp(
      r'''["']?[a-z0-9_.-]*(?:api[_-]?key|apikey|access[_-]?key|'''
      r'''secret[_-]?key|private[_-]?key|access[_-]?token|'''
      r'''refresh[_-]?token|id[_-]?token|bearer[_-]?token|'''
      r'''github[_-]?token|registry[_-]?token|auth[_-]?token|'''
      r'''session[_-]?token|token|secret|password|passwd|pwd|'''
      r'''cloud[_-]?session[_-]?id|hosted[_-]?session[_-]?id)'''
      r'''["']?\s*[:=]\s*["']?[^"'\s,;}&]+''',
      caseSensitive: false,
    ),
    RegExp(r'\bsk-(?:proj-)?[A-Za-z0-9_-]{8,}\b'),
    RegExp(r'\bgithub_pat_[A-Za-z0-9_]{20,}\b'),
    RegExp(r'\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9_]{20,}\b'),
  ];

  ConfigurationSettingChange _changeFromFoundation(
    FoundationDataStoreChange change,
  ) {
    final record = change.value == null
        ? null
        : ConfigurationSettingRecord.fromJson(change.value!);
    return ConfigurationSettingChange(
      kind: _changeKindFromFoundation(change.kind),
      key: record?.key ??
          ConfigurationSettingKey(
            namespace: change.namespace.replaceFirst('configuration.', ''),
            name: change.key.split(':').last,
            workspaceId: change.workspaceId,
          ),
      record: record,
      emittedAt: change.emittedAt,
    );
  }

  ConfigurationSettingChangeKind _changeKindFromFoundation(
    FoundationDataStoreChangeKind kind,
  ) {
    return switch (kind) {
      FoundationDataStoreChangeKind.written =>
        ConfigurationSettingChangeKind.written,
      FoundationDataStoreChangeKind.updated =>
        ConfigurationSettingChangeKind.updated,
      FoundationDataStoreChangeKind.deleted =>
        ConfigurationSettingChangeKind.deleted,
      FoundationDataStoreChangeKind.migrated =>
        ConfigurationSettingChangeKind.migrated,
    };
  }
}
