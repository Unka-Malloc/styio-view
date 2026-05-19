import 'dart:async';

import '../environment/configuration/configuration.dart';
import 'clang_cpp_version_configuration.dart';
import 'toolchain_catalog_change.dart';
import 'toolchain_catalog.dart';

typedef ToolchainCatalogUpdater =
    FutureOr<ToolchainCatalog?> Function(ToolchainCatalog current);

typedef ToolchainCatalogEditor =
    FutureOr<ToolchainCatalogEditDecision> Function(ToolchainCatalog current);

enum ToolchainCatalogEditAction { write, delete, keep }

class ToolchainCatalogEditDecision {
  const ToolchainCatalogEditDecision._({required this.action, this.catalog});

  factory ToolchainCatalogEditDecision.write(ToolchainCatalog catalog) {
    return ToolchainCatalogEditDecision._(
      action: ToolchainCatalogEditAction.write,
      catalog: catalog,
    );
  }

  static const ToolchainCatalogEditDecision delete =
      ToolchainCatalogEditDecision._(action: ToolchainCatalogEditAction.delete);

  static const ToolchainCatalogEditDecision keep =
      ToolchainCatalogEditDecision._(action: ToolchainCatalogEditAction.keep);

  final ToolchainCatalogEditAction action;
  final ToolchainCatalog? catalog;
}

class ToolchainInstallHistoryEntry {
  const ToolchainInstallHistoryEntry({
    required this.id,
    required this.status,
    required this.mode,
    required this.kind,
    required this.succeeded,
    required this.recordedAt,
    this.message,
  });

  factory ToolchainInstallHistoryEntry.fromJson(Map<String, Object?> json) {
    return ToolchainInstallHistoryEntry(
      id: json['id'] as String? ?? '',
      status: json['status'] as String? ?? 'unknown',
      mode: json['mode'] as String? ?? 'unknown',
      kind: json['kind'] as String? ?? 'unknown',
      succeeded: json['succeeded'] == true,
      recordedAt:
          DateTime.tryParse(json['recordedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      message: json['message'] as String?,
    );
  }

  final String id;
  final String status;
  final String mode;
  final String kind;
  final bool succeeded;
  final DateTime recordedAt;
  final String? message;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'status': status,
      'mode': mode,
      'kind': kind,
      'succeeded': succeeded,
      'recordedAt': recordedAt.toUtc().toIso8601String(),
      if (message != null) 'message': message,
    };
  }
}

class ToolchainInstallHistorySnapshot {
  const ToolchainInstallHistorySnapshot({
    this.entries = const <ToolchainInstallHistoryEntry>[],
  });

  factory ToolchainInstallHistorySnapshot.fromJson(Map<String, Object?> json) {
    final entries = json['entries'];
    return ToolchainInstallHistorySnapshot(
      entries: entries is List
          ? entries
                .map(_entryFromJson)
                .whereType<ToolchainInstallHistoryEntry>()
                .where((entry) => entry.id.isNotEmpty)
                .toList(growable: false)
          : const <ToolchainInstallHistoryEntry>[],
    );
  }

  final List<ToolchainInstallHistoryEntry> entries;

  ToolchainInstallHistorySnapshot prepend(
    ToolchainInstallHistoryEntry entry, {
    int limit = 20,
  }) {
    final next = <ToolchainInstallHistoryEntry>[entry, ...entries];
    return ToolchainInstallHistorySnapshot(
      entries: next.take(limit).toList(growable: false),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
    };
  }

  static ToolchainInstallHistoryEntry? _entryFromJson(Object? value) {
    if (value is Map<String, Object?>) {
      return ToolchainInstallHistoryEntry.fromJson(value);
    }
    if (value is Map) {
      return ToolchainInstallHistoryEntry.fromJson(
        value.map(
          (key, value) => MapEntry<String, Object?>(key.toString(), value),
        ),
      );
    }
    return null;
  }
}

class ToolchainConfigurationStore {
  const ToolchainConfigurationStore({
    required ConfigurationStore configurationStore,
  }) : _configurationStore = configurationStore;

  final ConfigurationStore _configurationStore;

  Future<void> saveCatalog(
    ToolchainCatalog catalog, {
    String? workspaceId,
    String? targetId,
  }) async {
    await _configurationStore.write(
      ConfigurationSettingRecord(
        key: _catalogKey(workspaceId: workspaceId, targetId: targetId),
        value: catalog.snapshot().toJson(),
      ),
    );
  }

  Future<ToolchainCatalog> loadCatalog({
    String? workspaceId,
    String? targetId,
  }) async {
    final record = await _configurationStore.read(
      _catalogKey(workspaceId: workspaceId, targetId: targetId),
    );
    final catalog = ToolchainCatalog();
    if (record == null) {
      return catalog;
    }
    catalog.restore(ToolchainCatalogSnapshot.fromJson(record.value));
    return catalog;
  }

  Future<bool> deleteCatalog({String? workspaceId, String? targetId}) {
    return _configurationStore.delete(
      _catalogKey(workspaceId: workspaceId, targetId: targetId),
    );
  }

  Future<void> saveClangCppVersionPreference(
    ClangCppVersionPreference preference, {
    String? workspaceId,
    String? targetId,
  }) async {
    await _configurationStore.write(
      ConfigurationSettingRecord(
        key: _clangCppVersionPreferenceKey(
          workspaceId: workspaceId,
          targetId: targetId,
        ),
        value: preference.toJson(),
      ),
    );
  }

  Future<ClangCppVersionPreference?> loadClangCppVersionPreference({
    String? workspaceId,
    String? targetId,
  }) async {
    final record = await _configurationStore.read(
      _clangCppVersionPreferenceKey(
        workspaceId: workspaceId,
        targetId: targetId,
      ),
    );
    if (record == null) {
      return null;
    }
    return ClangCppVersionPreference.fromJson(record.value);
  }

  Future<bool> deleteClangCppVersionPreference({
    String? workspaceId,
    String? targetId,
  }) {
    return _configurationStore.delete(
      _clangCppVersionPreferenceKey(
        workspaceId: workspaceId,
        targetId: targetId,
      ),
    );
  }

  Future<ToolchainCatalog?> updateCatalog(
    ToolchainCatalogUpdater update, {
    String? workspaceId,
    String? targetId,
  }) async {
    final key = _catalogKey(workspaceId: workspaceId, targetId: targetId);
    final record = await _configurationStore.update(key, (current) async {
      final catalog = ToolchainCatalog();
      if (current != null) {
        catalog.restore(ToolchainCatalogSnapshot.fromJson(current.value));
      }
      final next = await update(catalog);
      if (next == null) {
        return null;
      }
      return ConfigurationSettingRecord(
        key: key,
        value: next.snapshot().toJson(),
      );
    });
    if (record == null) {
      return null;
    }
    final catalog = ToolchainCatalog();
    catalog.restore(ToolchainCatalogSnapshot.fromJson(record.value));
    return catalog;
  }

  Future<ToolchainCatalogEditDecision> editCatalog(
    ToolchainCatalogEditor edit, {
    String? workspaceId,
    String? targetId,
  }) async {
    final key = _catalogKey(workspaceId: workspaceId, targetId: targetId);
    ToolchainCatalogEditDecision toolchainDecision =
        ToolchainCatalogEditDecision.keep;
    await _configurationStore.edit(key, (current) async {
      final catalog = ToolchainCatalog();
      if (current != null) {
        catalog.restore(ToolchainCatalogSnapshot.fromJson(current.value));
      }
      toolchainDecision = await edit(catalog);
      switch (toolchainDecision.action) {
        case ToolchainCatalogEditAction.keep:
          return ConfigurationSettingEditDecision.keep;
        case ToolchainCatalogEditAction.delete:
          return ConfigurationSettingEditDecision.delete;
        case ToolchainCatalogEditAction.write:
          final next = toolchainDecision.catalog ?? catalog;
          return ConfigurationSettingEditDecision.write(
            ConfigurationSettingRecord(
              key: key,
              value: next.snapshot().toJson(),
            ),
          );
      }
    });
    return toolchainDecision;
  }

  Stream<ToolchainCatalogConfigurationChange> watchCatalog({
    String? workspaceId,
    String? targetId,
  }) {
    return _configurationStore
        .watch(_catalogKey(workspaceId: workspaceId, targetId: targetId))
        .map((change) {
          final catalog = ToolchainCatalog();
          if (change.record != null) {
            catalog.restore(
              ToolchainCatalogSnapshot.fromJson(change.record!.value),
            );
          }
          return ToolchainCatalogConfigurationChange(
            kind: change.kind,
            workspaceId: workspaceId,
            targetId: targetId,
            catalog: change.record == null ? null : catalog,
            emittedAt: change.emittedAt,
          );
        });
  }

  Future<ToolchainInstallHistorySnapshot> loadInstallHistory({
    String? workspaceId,
    String? targetId,
  }) async {
    final record = await _configurationStore.read(
      _installHistoryKey(workspaceId: workspaceId, targetId: targetId),
    );
    if (record == null) {
      return const ToolchainInstallHistorySnapshot();
    }
    return ToolchainInstallHistorySnapshot.fromJson(record.value);
  }

  Future<ToolchainInstallHistorySnapshot> appendInstallHistory(
    ToolchainInstallHistoryEntry entry, {
    String? workspaceId,
    String? targetId,
    int limit = 20,
  }) async {
    final key = _installHistoryKey(
      workspaceId: workspaceId,
      targetId: targetId,
    );
    var written = const ToolchainInstallHistorySnapshot();
    await _configurationStore.edit(key, (current) {
      final currentSnapshot = current == null
          ? const ToolchainInstallHistorySnapshot()
          : ToolchainInstallHistorySnapshot.fromJson(current.value);
      written = currentSnapshot.prepend(entry, limit: limit);
      return ConfigurationSettingEditDecision.write(
        ConfigurationSettingRecord(key: key, value: written.toJson()),
      );
    });
    return written;
  }

  ConfigurationSettingKey _catalogKey({String? workspaceId, String? targetId}) {
    return ConfigurationSettingKey(
      namespace: 'toolchain',
      name: _targetScopedName('catalog', targetId),
      workspaceId: workspaceId,
    );
  }

  ConfigurationSettingKey _installHistoryKey({
    String? workspaceId,
    String? targetId,
  }) {
    return ConfigurationSettingKey(
      namespace: 'toolchain',
      name: _targetScopedName('install-history', targetId),
      workspaceId: workspaceId,
    );
  }

  ConfigurationSettingKey _clangCppVersionPreferenceKey({
    String? workspaceId,
    String? targetId,
  }) {
    return ConfigurationSettingKey(
      namespace: 'toolchain',
      name: _targetScopedName('clang-cpp-version-preference', targetId),
      workspaceId: workspaceId,
    );
  }

  String _targetScopedName(String baseName, String? targetId) {
    if (targetId == null || targetId.isEmpty) {
      return baseName;
    }
    return '$baseName.$targetId';
  }
}

class ToolchainCatalogConfigurationChange implements ToolchainCatalogChange {
  const ToolchainCatalogConfigurationChange({
    required this.kind,
    required this.workspaceId,
    required this.catalog,
    required this.emittedAt,
    this.targetId,
  });

  final ConfigurationSettingChangeKind kind;
  final String? workspaceId;
  final String? targetId;
  @override
  final ToolchainCatalog? catalog;
  final DateTime emittedAt;

  @override
  bool get deleted => kind == ConfigurationSettingChangeKind.deleted;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      if (workspaceId != null) 'workspaceId': workspaceId,
      if (targetId != null) 'targetId': targetId,
      if (catalog != null) 'catalog': catalog!.snapshot().toJson(),
      'deleted': deleted,
      'emittedAt': emittedAt.toIso8601String(),
    };
  }
}
