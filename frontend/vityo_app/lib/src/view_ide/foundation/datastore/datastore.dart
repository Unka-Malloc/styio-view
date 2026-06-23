import 'dart:async';
import 'dart:convert';

import '../../environment/system_compatibility/file_system/file_system_manager.dart';
import '../lock_service/lock_service.dart';
import '../resource_coordinator/resource_coordinator.dart';

class FoundationDataStoreNamespace {
  const FoundationDataStoreNamespace({
    required this.name,
    this.schemaVersion = 1,
    this.scope = FoundationResourceScope.user,
    this.workspaceId,
  });

  final String name;
  final int schemaVersion;
  final FoundationResourceScope scope;
  final String? workspaceId;
}

class FoundationDataStoreOwnerDescriptor {
  const FoundationDataStoreOwnerDescriptor({
    required this.ownerId,
    required this.layer,
    required this.stateFamily,
    this.allowedNamespaces = const <String>{},
    this.allowedNamespacePrefixes = const <String>{},
  });

  final String ownerId;
  final String layer;
  final String stateFamily;
  final Set<String> allowedNamespaces;
  final Set<String> allowedNamespacePrefixes;
}

class FoundationDataStoreOwner {
  const FoundationDataStoreOwner({
    required this.descriptor,
    required FoundationDataStore dataStore,
  }) : _dataStore = dataStore;

  final FoundationDataStoreOwnerDescriptor descriptor;
  final FoundationDataStore _dataStore;

  FoundationDataStoreNamespace namespace({
    required String name,
    int schemaVersion = 1,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) {
    _assertNamespaceAllowed(name);
    return FoundationDataStoreNamespace(
      name: name,
      schemaVersion: schemaVersion,
      scope: scope,
      workspaceId: workspaceId,
    );
  }

  Future<void> writeJson({
    required String namespaceName,
    required String key,
    required Map<String, Object?> value,
    int schemaVersion = 1,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) {
    return _dataStore.writeJson(
      namespace: namespace(
        name: namespaceName,
        schemaVersion: schemaVersion,
        scope: scope,
        workspaceId: workspaceId,
      ),
      key: key,
      value: value,
    );
  }

  Future<Map<String, Object?>?> readJson({
    required String namespaceName,
    required String key,
    int schemaVersion = 1,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) {
    return _dataStore.readJson(
      namespace: namespace(
        name: namespaceName,
        schemaVersion: schemaVersion,
        scope: scope,
        workspaceId: workspaceId,
      ),
      key: key,
    );
  }

  Future<bool> delete({
    required String namespaceName,
    required String key,
    int schemaVersion = 1,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) {
    return _dataStore.delete(
      namespace: namespace(
        name: namespaceName,
        schemaVersion: schemaVersion,
        scope: scope,
        workspaceId: workspaceId,
      ),
      key: key,
    );
  }

  Future<Map<String, Object?>?> updateJson({
    required String namespaceName,
    required String key,
    required FoundationDataStoreUpdater update,
    int schemaVersion = 1,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) {
    return _dataStore.updateJson(
      namespace: namespace(
        name: namespaceName,
        schemaVersion: schemaVersion,
        scope: scope,
        workspaceId: workspaceId,
      ),
      key: key,
      update: update,
    );
  }

  Future<FoundationDataStoreEditDecision> editJson({
    required String namespaceName,
    required String key,
    required FoundationDataStoreEditor edit,
    int schemaVersion = 1,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
  }) {
    return _dataStore.editJson(
      namespace: namespace(
        name: namespaceName,
        schemaVersion: schemaVersion,
        scope: scope,
        workspaceId: workspaceId,
      ),
      key: key,
      edit: edit,
    );
  }

  Stream<FoundationDataStoreChange> watchJson({
    required String namespaceName,
    String? key,
    int schemaVersion = 1,
    FoundationResourceScope scope = FoundationResourceScope.user,
    String? workspaceId,
    FoundationDataStoreChangeKind? kind,
  }) {
    return _dataStore.watchJson(
      namespace: namespace(
        name: namespaceName,
        schemaVersion: schemaVersion,
        scope: scope,
        workspaceId: workspaceId,
      ),
      key: key,
      kind: kind,
    );
  }

  void _assertNamespaceAllowed(String namespaceName) {
    final allowed = descriptor.allowedNamespaces;
    final allowedPrefixes = descriptor.allowedNamespacePrefixes;
    final prefixAllowed = allowedPrefixes.any(namespaceName.startsWith);
    if (allowed.isNotEmpty && allowed.contains(namespaceName)) {
      return;
    }
    if (prefixAllowed) {
      return;
    }
    if (allowed.isNotEmpty || allowedPrefixes.isNotEmpty) {
      throw StateError(
        'DataStore owner ${descriptor.ownerId} cannot access namespace $namespaceName.',
      );
    }
  }
}

class FoundationDataRecord {
  const FoundationDataRecord({
    required this.namespace,
    required this.key,
    required this.schemaVersion,
    required this.value,
    required this.updatedAt,
  });

  final String namespace;
  final String key;
  final int schemaVersion;
  final Map<String, Object?> value;
  final DateTime updatedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'namespace': namespace,
      'key': key,
      'schemaVersion': schemaVersion,
      'updatedAt': updatedAt.toIso8601String(),
      'value': value,
    };
  }

  factory FoundationDataRecord.fromJson(Map<String, Object?> json) {
    final value = json['value'];
    return FoundationDataRecord(
      namespace: json['namespace'] as String? ?? '',
      key: json['key'] as String? ?? '',
      schemaVersion: json['schemaVersion'] as int? ?? 0,
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      value: value is Map<String, Object?>
          ? value
          : value is Map
          ? value.map(
              (key, value) => MapEntry<String, Object?>(key.toString(), value),
            )
          : const <String, Object?>{},
    );
  }
}

typedef FoundationDataMigration = Map<String, Object?> Function(
  Map<String, Object?> value,
);

class FoundationDataMigrationStep {
  const FoundationDataMigrationStep({
    required this.name,
    required this.namespace,
    required this.sourceSchemaState,
    required this.targetSchemaState,
    required this.migrate,
  });

  final String name;
  final String namespace;
  final int sourceSchemaState;
  final int targetSchemaState;
  final FoundationDataMigration migrate;

  bool appliesTo({
    required String namespace,
    required int schemaState,
    required int targetSchemaState,
  }) {
    return this.namespace == namespace &&
        sourceSchemaState == schemaState &&
        this.targetSchemaState > schemaState &&
        this.targetSchemaState <= targetSchemaState;
  }
}

typedef FoundationDataStoreUpdater = FutureOr<Map<String, Object?>?> Function(
  Map<String, Object?>? current,
);

typedef FoundationDataStoreEditor =
    FutureOr<FoundationDataStoreEditDecision> Function(
  Map<String, Object?>? current,
);

enum FoundationDataStoreChangeKind {
  written,
  updated,
  deleted,
  migrated,
}

class FoundationDataStoreChange {
  FoundationDataStoreChange({
    required this.kind,
    required this.namespace,
    required this.key,
    required this.schemaVersion,
    required this.scope,
    required this.workspaceId,
    this.value,
    DateTime? emittedAt,
  }) : emittedAt = emittedAt ?? DateTime.now().toUtc();

  final FoundationDataStoreChangeKind kind;
  final String namespace;
  final String key;
  final int schemaVersion;
  final FoundationResourceScope scope;
  final String? workspaceId;
  final Map<String, Object?>? value;
  final DateTime emittedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'namespace': namespace,
      'key': key,
      'schemaVersion': schemaVersion,
      'scope': scope.name,
      if (workspaceId != null) 'workspaceId': workspaceId,
      if (value != null) 'value': value,
      'emittedAt': emittedAt.toIso8601String(),
    };
  }
}

enum FoundationDataStoreEditAction {
  write,
  delete,
  keep,
}

class FoundationDataStoreEditDecision {
  const FoundationDataStoreEditDecision._({
    required this.action,
    this.value,
  });

  factory FoundationDataStoreEditDecision.write(
    Map<String, Object?> value,
  ) {
    return FoundationDataStoreEditDecision._(
      action: FoundationDataStoreEditAction.write,
      value: Map<String, Object?>.unmodifiable(value),
    );
  }

  static const FoundationDataStoreEditDecision delete =
      FoundationDataStoreEditDecision._(
    action: FoundationDataStoreEditAction.delete,
  );

  static const FoundationDataStoreEditDecision keep =
      FoundationDataStoreEditDecision._(
    action: FoundationDataStoreEditAction.keep,
  );

  final FoundationDataStoreEditAction action;
  final Map<String, Object?>? value;
}

class FoundationDataStore {
  FoundationDataStore({
    required FoundationResourceCoordinator resourceCoordinator,
    required FileSystemManager fileSystemManager,
    this.migrations = const <FoundationDataMigrationStep>[],
    FoundationLockService? lockService,
  }) : _resourceCoordinator = resourceCoordinator,
       _fileSystemManager = fileSystemManager,
       _lockService = lockService ?? FoundationLockService();

  final FoundationResourceCoordinator _resourceCoordinator;
  final FileSystemManager _fileSystemManager;
  final FoundationLockService _lockService;
  final StreamController<FoundationDataStoreChange> _changes =
      StreamController<FoundationDataStoreChange>.broadcast(sync: true);
  final List<FoundationDataMigrationStep> migrations;

  Future<void> writeJson({
    required FoundationDataStoreNamespace namespace,
    required String key,
    required Map<String, Object?> value,
  }) async {
    return _lockService.runExclusive(
      _lockKey(namespace, key),
      (_) async {
        await _writeJsonUnlocked(namespace: namespace, key: key, value: value);
        _emitChange(
          kind: FoundationDataStoreChangeKind.written,
          namespace: namespace,
          key: key,
          value: value,
        );
      },
    );
  }

  Future<void> _writeJsonUnlocked({
    required FoundationDataStoreNamespace namespace,
    required String key,
    required Map<String, Object?> value,
  }) async {
    final location = _namespaceLocation(namespace);
    await _fileSystemManager.createDirectory(location.path, recursive: true);
    final record = FoundationDataRecord(
      namespace: namespace.name,
      key: key,
      schemaVersion: namespace.schemaVersion,
      value: value,
      updatedAt: DateTime.now().toUtc(),
    );
    await _fileSystemManager.writeText(
      _recordPath(namespace, key),
      const JsonEncoder.withIndent('  ').convert(record.toJson()),
    );
  }

  Future<Map<String, Object?>?> readJson({
    required FoundationDataStoreNamespace namespace,
    required String key,
  }) async {
    return _lockService.runExclusive(
      _lockKey(namespace, key),
      (_) => _readJsonUnlocked(namespace: namespace, key: key),
    );
  }

  Future<Map<String, Object?>?> _readJsonUnlocked({
    required FoundationDataStoreNamespace namespace,
    required String key,
  }) async {
    final path = _recordPath(namespace, key);
    if (!await _fileSystemManager.exists(path)) {
      return null;
    }
    final decoded = jsonDecode(await _fileSystemManager.readText(path));
    if (decoded is! Map) {
      throw const FormatException('Invalid Foundation DataStore record.');
    }
    var record = FoundationDataRecord.fromJson(
      decoded.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      ),
    );
    final originalSchemaVersion = record.schemaVersion;
    while (record.schemaVersion < namespace.schemaVersion) {
      final migration = _migrationStepFor(
        namespace: namespace.name,
        schemaState: record.schemaVersion,
        targetSchemaState: namespace.schemaVersion,
      );
      record = FoundationDataRecord(
        namespace: record.namespace,
        key: record.key,
        schemaVersion: migration.targetSchemaState,
        value: migration.migrate(record.value),
        updatedAt: DateTime.now().toUtc(),
      );
    }
    if (record.schemaVersion != originalSchemaVersion) {
      await _fileSystemManager.writeText(
        path,
        const JsonEncoder.withIndent('  ').convert(record.toJson()),
      );
      _emitChange(
        kind: FoundationDataStoreChangeKind.migrated,
        namespace: namespace,
        key: key,
        value: record.value,
      );
    }
    return record.value;
  }

  FoundationDataMigrationStep _migrationStepFor({
    required String namespace,
    required int schemaState,
    required int targetSchemaState,
  }) {
    final matches = migrations
        .where(
          (migration) => migration.appliesTo(
            namespace: namespace,
            schemaState: schemaState,
            targetSchemaState: targetSchemaState,
          ),
        )
        .toList(growable: false);
    if (matches.length == 1) {
      return matches.single;
    }
    if (matches.isEmpty) {
      throw StateError(
        'Missing DataStore migration for `$namespace` from schema state '
        '$schemaState toward schema state $targetSchemaState.',
      );
    }
    throw StateError(
      'Ambiguous DataStore migrations for `$namespace` from schema state '
      '$schemaState: ${matches.map((migration) => migration.name).join(', ')}.',
    );
  }

  Future<bool> delete({
    required FoundationDataStoreNamespace namespace,
    required String key,
  }) async {
    return _lockService.runExclusive(
      _lockKey(namespace, key),
      (_) async {
        final deleted = await _deleteUnlocked(namespace: namespace, key: key);
        if (deleted) {
          _emitChange(
            kind: FoundationDataStoreChangeKind.deleted,
            namespace: namespace,
            key: key,
          );
        }
        return deleted;
      },
    );
  }

  Future<bool> _deleteUnlocked({
    required FoundationDataStoreNamespace namespace,
    required String key,
  }) async {
    final path = _recordPath(namespace, key);
    if (!await _fileSystemManager.exists(path)) {
      return false;
    }
    await _fileSystemManager.delete(path);
    return true;
  }

  Future<Map<String, Object?>?> updateJson({
    required FoundationDataStoreNamespace namespace,
    required String key,
    required FoundationDataStoreUpdater update,
  }) async {
    return _lockService.runExclusive(
      _lockKey(namespace, key),
      (_) => _updateJsonUnlocked(
        namespace: namespace,
        key: key,
        update: update,
      ),
    );
  }

  Future<Map<String, Object?>?> _updateJsonUnlocked({
    required FoundationDataStoreNamespace namespace,
    required String key,
    required FoundationDataStoreUpdater update,
  }) async {
    final current = await _readJsonUnlocked(namespace: namespace, key: key);
    final next = await update(current);
    if (next == null) {
      final deleted = await _deleteUnlocked(namespace: namespace, key: key);
      if (deleted) {
        _emitChange(
          kind: FoundationDataStoreChangeKind.deleted,
          namespace: namespace,
          key: key,
        );
      }
      return null;
    }
    await _writeJsonUnlocked(namespace: namespace, key: key, value: next);
    _emitChange(
      kind: FoundationDataStoreChangeKind.updated,
      namespace: namespace,
      key: key,
      value: next,
    );
    return next;
  }

  Future<FoundationDataStoreEditDecision> editJson({
    required FoundationDataStoreNamespace namespace,
    required String key,
    required FoundationDataStoreEditor edit,
  }) {
    return _lockService.runExclusive(
      _lockKey(namespace, key),
      (_) => _editJsonUnlocked(namespace: namespace, key: key, edit: edit),
    );
  }

  Future<FoundationDataStoreEditDecision> _editJsonUnlocked({
    required FoundationDataStoreNamespace namespace,
    required String key,
    required FoundationDataStoreEditor edit,
  }) async {
    final current = await _readJsonUnlocked(namespace: namespace, key: key);
    final decision = await edit(current);
    switch (decision.action) {
      case FoundationDataStoreEditAction.keep:
        return decision;
      case FoundationDataStoreEditAction.delete:
        final deleted = await _deleteUnlocked(namespace: namespace, key: key);
        if (deleted) {
          _emitChange(
            kind: FoundationDataStoreChangeKind.deleted,
            namespace: namespace,
            key: key,
          );
        }
        return decision;
      case FoundationDataStoreEditAction.write:
        final value = decision.value ?? const <String, Object?>{};
        await _writeJsonUnlocked(namespace: namespace, key: key, value: value);
        _emitChange(
          kind: current == null
              ? FoundationDataStoreChangeKind.written
              : FoundationDataStoreChangeKind.updated,
          namespace: namespace,
          key: key,
          value: value,
        );
        return decision;
    }
  }

  Stream<FoundationDataStoreChange> watchJson({
    FoundationDataStoreNamespace? namespace,
    String? key,
    FoundationDataStoreChangeKind? kind,
  }) {
    return _changes.stream.where((change) {
      final namespaceMatches = namespace == null ||
          (change.namespace == namespace.name &&
              change.scope == namespace.scope &&
              change.workspaceId == namespace.workspaceId);
      final keyMatches = key == null || change.key == key;
      final kindMatches = kind == null || change.kind == kind;
      return namespaceMatches && keyMatches && kindMatches;
    });
  }

  Future<void> close() {
    return _changes.close();
  }

  void _emitChange({
    required FoundationDataStoreChangeKind kind,
    required FoundationDataStoreNamespace namespace,
    required String key,
    Map<String, Object?>? value,
  }) {
    if (_changes.isClosed) {
      return;
    }
    _changes.add(
      FoundationDataStoreChange(
        kind: kind,
        namespace: namespace.name,
        key: key,
        schemaVersion: namespace.schemaVersion,
        scope: namespace.scope,
        workspaceId: namespace.workspaceId,
        value: value == null
            ? null
            : Map<String, Object?>.unmodifiable(value),
      ),
    );
  }

  FoundationResourceLocation _namespaceLocation(
    FoundationDataStoreNamespace namespace,
  ) {
    return _resourceCoordinator.location(
      kind: FoundationResourceKind.appData,
      namespace: namespace.name,
      scope: namespace.scope,
      workspaceId: namespace.workspaceId,
    );
  }

  String _recordPath(FoundationDataStoreNamespace namespace, String key) {
    return _fileSystemManager.joinPath(<String>[
      _namespaceLocation(namespace).path,
      '${_sanitize(key)}.json',
    ]);
  }

  String _sanitize(String value) {
    return value
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'_+'), '_');
  }

  String _lockKey(FoundationDataStoreNamespace namespace, String key) {
    return 'datastore:${namespace.name}:${namespace.scope.name}:${namespace.workspaceId ?? ""}:$key';
  }
}
