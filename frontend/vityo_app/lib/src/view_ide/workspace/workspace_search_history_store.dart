import '../foundation/foundation.dart';

enum WorkspaceSearchHistoryMode { text, symbol, quickOpen, replacePreview }

extension WorkspaceSearchHistoryModeX on WorkspaceSearchHistoryMode {
  String get wireValue {
    return switch (this) {
      WorkspaceSearchHistoryMode.text => 'text',
      WorkspaceSearchHistoryMode.symbol => 'symbol',
      WorkspaceSearchHistoryMode.quickOpen => 'quick-open',
      WorkspaceSearchHistoryMode.replacePreview => 'replace-preview',
    };
  }
}

class WorkspaceSearchHistoryRecord {
  const WorkspaceSearchHistoryRecord({
    required this.query,
    required this.mode,
    required this.createdAt,
    this.replacement = '',
    this.caseSensitive = false,
    this.wholeWord = false,
    this.useRegex = false,
  });

  factory WorkspaceSearchHistoryRecord.fromJson(Map<String, Object?> json) {
    return WorkspaceSearchHistoryRecord(
      query: json['query'] as String? ?? '',
      mode: _workspaceSearchHistoryModeFromWireValue(
        json['mode'] as String? ?? '',
      ),
      replacement: json['replacement'] as String? ?? '',
      caseSensitive: json['caseSensitive'] as bool? ?? false,
      wholeWord: json['wholeWord'] as bool? ?? false,
      useRegex: json['useRegex'] as bool? ?? false,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  final String query;
  final WorkspaceSearchHistoryMode mode;
  final DateTime createdAt;
  final String replacement;
  final bool caseSensitive;
  final bool wholeWord;
  final bool useRegex;

  String get identity {
    return <String>[
      mode.wireValue,
      query.trim(),
      replacement,
      '$caseSensitive',
      '$wholeWord',
      '$useRegex',
    ].join('\u0000');
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'query': query,
      'mode': mode.wireValue,
      'createdAt': createdAt.toIso8601String(),
      if (replacement.isNotEmpty) 'replacement': replacement,
      'caseSensitive': caseSensitive,
      'wholeWord': wholeWord,
      'useRegex': useRegex,
    };
  }
}

class WorkspaceSearchHistory {
  const WorkspaceSearchHistory({
    required this.workspaceId,
    this.records = const <WorkspaceSearchHistoryRecord>[],
    this.updatedAt,
  });

  factory WorkspaceSearchHistory.fromJson(Map<String, Object?> json) {
    return WorkspaceSearchHistory(
      workspaceId: json['workspaceId'] as String? ?? '',
      records: _jsonSearchHistoryRecords(json['records']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final List<WorkspaceSearchHistoryRecord> records;
  final DateTime? updatedAt;

  WorkspaceSearchHistory append(
    WorkspaceSearchHistoryRecord record, {
    int maxEntries = 30,
    DateTime? updatedAt,
  }) {
    final nextRecords = <WorkspaceSearchHistoryRecord>[
      record,
      ...records.where((existing) => existing.identity != record.identity),
    ];
    return WorkspaceSearchHistory(
      workspaceId: workspaceId,
      records: nextRecords.take(maxEntries).toList(growable: false),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  WorkspaceSearchHistory copyWith({
    String? workspaceId,
    List<WorkspaceSearchHistoryRecord>? records,
    DateTime? updatedAt,
  }) {
    return WorkspaceSearchHistory(
      workspaceId: workspaceId ?? this.workspaceId,
      records: records ?? this.records,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  List<WorkspaceSearchHistoryRecord> recordsForMode(
    WorkspaceSearchHistoryMode mode,
  ) {
    return records
        .where((record) => record.mode == mode)
        .toList(growable: false);
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'recordCount': records.length,
      'records': records
          .map((record) => record.toJson())
          .toList(growable: false),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class WorkspaceSearchHistoryStore {
  WorkspaceSearchHistoryStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'workspace.search-history',
             layer: 'interaction',
             stateFamily: 'search-history',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const WorkspaceSearchHistoryStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'workspace.search-history';
  static const String _key = 'queries';

  final FoundationDataStoreOwner _owner;

  Future<void> saveHistory(WorkspaceSearchHistory history) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: history.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: history.workspaceId,
    );
  }

  Future<WorkspaceSearchHistory> readHistory({
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
      return WorkspaceSearchHistory(workspaceId: workspaceId);
    }
    final history = WorkspaceSearchHistory.fromJson(value);
    return history.workspaceId.isEmpty
        ? history.copyWith(workspaceId: workspaceId)
        : history;
  }

  Future<WorkspaceSearchHistory> appendRecord({
    required String workspaceId,
    required WorkspaceSearchHistoryRecord record,
    int maxEntries = 30,
  }) async {
    final current = await readHistory(workspaceId: workspaceId);
    final next = current.append(record, maxEntries: maxEntries);
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

WorkspaceSearchHistoryMode _workspaceSearchHistoryModeFromWireValue(
  String value,
) {
  for (final mode in WorkspaceSearchHistoryMode.values) {
    if (mode.wireValue == value) {
      return mode;
    }
  }
  return WorkspaceSearchHistoryMode.text;
}

List<WorkspaceSearchHistoryRecord> _jsonSearchHistoryRecords(Object? value) {
  if (value is! List) {
    return const <WorkspaceSearchHistoryRecord>[];
  }
  return value
      .whereType<Map>()
      .map(
        (record) => WorkspaceSearchHistoryRecord.fromJson(
          record.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}
