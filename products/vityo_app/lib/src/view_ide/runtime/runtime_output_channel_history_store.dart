import '../foundation/foundation.dart';
import 'runtime_output_channels.dart';

class RuntimeOutputChannelHistoryEntry {
  const RuntimeOutputChannelHistoryEntry({
    required this.snapshot,
    required this.capturedAt,
  });

  factory RuntimeOutputChannelHistoryEntry.fromJson(Map<String, Object?> json) {
    final snapshot = json['snapshot'];
    return RuntimeOutputChannelHistoryEntry(
      snapshot: snapshot is Map
          ? RuntimeOutputChannelSnapshot.fromJson(
              snapshot.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : const RuntimeOutputChannelSnapshot(
              channels: <RuntimeOutputChannelSummary>[],
            ),
      capturedAt:
          DateTime.tryParse(json['capturedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final RuntimeOutputChannelSnapshot snapshot;
  final DateTime capturedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'capturedAt': capturedAt.toIso8601String(),
      'snapshot': snapshot.toJson(),
    };
  }
}

class RuntimeOutputChannelHistory {
  const RuntimeOutputChannelHistory({
    required this.workspaceId,
    this.entries = const <RuntimeOutputChannelHistoryEntry>[],
    this.updatedAt,
  });

  factory RuntimeOutputChannelHistory.fromJson(Map<String, Object?> json) {
    return RuntimeOutputChannelHistory(
      workspaceId: json['workspaceId'] as String? ?? '',
      entries: _jsonHistoryEntries(json['entries']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final List<RuntimeOutputChannelHistoryEntry> entries;
  final DateTime? updatedAt;

  RuntimeOutputChannelHistory append(
    RuntimeOutputChannelSnapshot snapshot, {
    int maxEntries = 20,
    DateTime? capturedAt,
    DateTime? updatedAt,
  }) {
    final entry = RuntimeOutputChannelHistoryEntry(
      snapshot: snapshot,
      capturedAt: capturedAt ?? DateTime.now().toUtc(),
    );
    return RuntimeOutputChannelHistory(
      workspaceId: workspaceId,
      entries: <RuntimeOutputChannelHistoryEntry>[
        entry,
        ...entries,
      ].take(maxEntries).toList(growable: false),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  RuntimeOutputChannelHistory copyWith({
    String? workspaceId,
    List<RuntimeOutputChannelHistoryEntry>? entries,
    DateTime? updatedAt,
  }) {
    return RuntimeOutputChannelHistory(
      workspaceId: workspaceId ?? this.workspaceId,
      entries: entries ?? this.entries,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'entryCount': entries.length,
      'entries': entries.map((entry) => entry.toJson()).toList(growable: false),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class RuntimeOutputChannelHistoryStore {
  RuntimeOutputChannelHistoryStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'runtime.output-channel-history',
             layer: 'runtime',
             stateFamily: 'output-channel-history',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const RuntimeOutputChannelHistoryStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'runtime.output-channel-history';
  static const String _key = 'snapshots';

  final FoundationDataStoreOwner _owner;

  Future<void> saveHistory(RuntimeOutputChannelHistory history) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: history.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: history.workspaceId,
    );
  }

  Future<RuntimeOutputChannelHistory> readHistory({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return RuntimeOutputChannelHistory(workspaceId: workspaceId);
    }
    final history = RuntimeOutputChannelHistory.fromJson(value);
    return history.workspaceId.isEmpty
        ? history.copyWith(workspaceId: workspaceId)
        : history;
  }

  Future<RuntimeOutputChannelHistory> appendSnapshot({
    required String workspaceId,
    required RuntimeOutputChannelSnapshot snapshot,
    int maxEntries = 20,
    DateTime? capturedAt,
  }) async {
    final current = await readHistory(workspaceId: workspaceId);
    final next = current.append(
      snapshot,
      maxEntries: maxEntries,
      capturedAt: capturedAt,
    );
    await saveHistory(next);
    return next;
  }

  Future<bool> deleteHistory({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchHistory({
    required String workspaceId,
  }) {
    return _owner.watchJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

List<RuntimeOutputChannelHistoryEntry> _jsonHistoryEntries(Object? value) {
  if (value is! List) {
    return const <RuntimeOutputChannelHistoryEntry>[];
  }
  return value
      .whereType<Map>()
      .map(
        (entry) => RuntimeOutputChannelHistoryEntry.fromJson(
          entry.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}
