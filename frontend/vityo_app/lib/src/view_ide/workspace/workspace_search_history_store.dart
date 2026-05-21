import '../foundation/foundation.dart';
import 'workspace_search_service.dart';

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

class WorkspaceSearchFilterState {
  const WorkspaceSearchFilterState({
    required this.workspaceId,
    this.caseSensitive = false,
    this.wholeWord = false,
    this.useRegex = false,
    this.includeGlob = '',
    this.excludeGlob = '',
    this.updatedAt,
  });

  factory WorkspaceSearchFilterState.fromJson(Map<String, Object?> json) {
    return WorkspaceSearchFilterState(
      workspaceId: json['workspaceId'] as String? ?? '',
      caseSensitive: json['caseSensitive'] as bool? ?? false,
      wholeWord: json['wholeWord'] as bool? ?? false,
      useRegex: json['useRegex'] as bool? ?? false,
      includeGlob: json['includeGlob'] as String? ?? '',
      excludeGlob: json['excludeGlob'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final bool caseSensitive;
  final bool wholeWord;
  final bool useRegex;
  final String includeGlob;
  final String excludeGlob;
  final DateTime? updatedAt;

  bool get active {
    return caseSensitive ||
        wholeWord ||
        useRegex ||
        includeGlob.trim().isNotEmpty ||
        excludeGlob.trim().isNotEmpty;
  }

  WorkspaceSearchFilterState copyWith({
    String? workspaceId,
    bool? caseSensitive,
    bool? wholeWord,
    bool? useRegex,
    String? includeGlob,
    String? excludeGlob,
    DateTime? updatedAt,
  }) {
    return WorkspaceSearchFilterState(
      workspaceId: workspaceId ?? this.workspaceId,
      caseSensitive: caseSensitive ?? this.caseSensitive,
      wholeWord: wholeWord ?? this.wholeWord,
      useRegex: useRegex ?? this.useRegex,
      includeGlob: includeGlob ?? this.includeGlob,
      excludeGlob: excludeGlob ?? this.excludeGlob,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'caseSensitive': caseSensitive,
      'wholeWord': wholeWord,
      'useRegex': useRegex,
      if (includeGlob.isNotEmpty) 'includeGlob': includeGlob,
      if (excludeGlob.isNotEmpty) 'excludeGlob': excludeGlob,
      'active': active,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class WorkspaceSearchFilterStore {
  WorkspaceSearchFilterStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'workspace.search-filters',
             layer: 'interaction',
             stateFamily: 'search-filters',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const WorkspaceSearchFilterStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'workspace.search-filters';
  static const String _key = 'result-filter-state';

  final FoundationDataStoreOwner _owner;

  Future<WorkspaceSearchFilterState> readFilters({
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
      return WorkspaceSearchFilterState(workspaceId: workspaceId);
    }
    final filters = WorkspaceSearchFilterState.fromJson(value);
    return filters.workspaceId.isEmpty
        ? filters.copyWith(workspaceId: workspaceId)
        : filters;
  }

  Future<WorkspaceSearchFilterState> saveFilters(
    WorkspaceSearchFilterState filters,
  ) async {
    final next = filters.copyWith(updatedAt: DateTime.now().toUtc());
    await _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: next.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: next.workspaceId,
    );
    return next;
  }

  Future<bool> deleteFilters({required String workspaceId}) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  Stream<FoundationDataStoreChange> watchFilters({
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

class WorkspaceReplacePreviewExpansionState {
  const WorkspaceReplacePreviewExpansionState({
    required this.workspaceId,
    this.expandedDocumentIds = const <String>[],
    this.updatedAt,
  });

  factory WorkspaceReplacePreviewExpansionState.fromJson(
    Map<String, Object?> json,
  ) {
    return WorkspaceReplacePreviewExpansionState(
      workspaceId: json['workspaceId'] as String? ?? '',
      expandedDocumentIds: _jsonStringList(json['expandedDocumentIds']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final List<String> expandedDocumentIds;
  final DateTime? updatedAt;

  bool isExpanded(String documentId) {
    return expandedDocumentIds.contains(documentId.trim());
  }

  WorkspaceReplacePreviewExpansionState toggleDocument(String documentId) {
    final normalized = documentId.trim();
    if (normalized.isEmpty) {
      return this;
    }
    final nextExpanded = isExpanded(normalized)
        ? expandedDocumentIds
              .where((expandedId) => expandedId != normalized)
              .toList(growable: false)
        : _sortedStrings(<String>[...expandedDocumentIds, normalized]);
    return copyWith(
      expandedDocumentIds: nextExpanded,
      updatedAt: DateTime.now().toUtc(),
    );
  }

  WorkspaceReplacePreviewExpansionState copyWith({
    String? workspaceId,
    List<String>? expandedDocumentIds,
    DateTime? updatedAt,
  }) {
    return WorkspaceReplacePreviewExpansionState(
      workspaceId: workspaceId ?? this.workspaceId,
      expandedDocumentIds: expandedDocumentIds == null
          ? this.expandedDocumentIds
          : _sortedStrings(expandedDocumentIds),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'expandedCount': expandedDocumentIds.length,
      'expandedDocumentIds': expandedDocumentIds,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class WorkspaceReplacePreviewExpansionStore {
  WorkspaceReplacePreviewExpansionStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'workspace.replace-preview-expansion',
             layer: 'interaction',
             stateFamily: 'replace-preview-expansion',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const WorkspaceReplacePreviewExpansionStore({required this.owner});

  static const int schemaVersion = 1;
  static const String _namespaceName = 'workspace.replace-preview-expansion';
  static const String _key = 'expanded-documents';

  final FoundationDataStoreOwner owner;

  Future<WorkspaceReplacePreviewExpansionState> readState({
    required String workspaceId,
  }) async {
    final value = await owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return WorkspaceReplacePreviewExpansionState(workspaceId: workspaceId);
    }
    final state = WorkspaceReplacePreviewExpansionState.fromJson(value);
    return state.workspaceId.isEmpty
        ? state.copyWith(workspaceId: workspaceId)
        : state;
  }

  Future<WorkspaceReplacePreviewExpansionState> saveState({
    required WorkspaceReplacePreviewExpansionState state,
  }) async {
    final next = state.copyWith(updatedAt: DateTime.now().toUtc());
    await owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: next.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: next.workspaceId,
    );
    return next;
  }

  Future<WorkspaceReplacePreviewExpansionState> toggleDocument({
    required String workspaceId,
    required String documentId,
  }) async {
    final current = await readState(workspaceId: workspaceId);
    final next = current.toggleDocument(documentId);
    await saveState(state: next);
    return next;
  }

  Future<bool> deleteState({required String workspaceId}) {
    return owner.delete(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }
}

class WorkspaceSearchWatcherRecoveryState {
  const WorkspaceSearchWatcherRecoveryState({
    required this.workspaceId,
    this.failureCount = 0,
    this.lastPlan,
    this.updatedAt,
  });

  factory WorkspaceSearchWatcherRecoveryState.fromJson(
    Map<String, Object?> json,
  ) {
    return WorkspaceSearchWatcherRecoveryState(
      workspaceId: json['workspaceId'] as String? ?? '',
      failureCount: json['failureCount'] as int? ?? 0,
      lastPlan: _workspaceSearchWatcherRecoveryPlanFromJson(json['lastPlan']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final int failureCount;
  final WorkspaceSearchWatcherRecoveryPlan? lastPlan;
  final DateTime? updatedAt;

  bool get recoveryDisabled {
    return lastPlan?.action ==
        WorkspaceSearchWatcherRecoveryAction.disableWatcher;
  }

  WorkspaceSearchWatcherRecoveryState recordPlan(
    WorkspaceSearchWatcherRecoveryPlan plan, {
    DateTime? updatedAt,
  }) {
    return WorkspaceSearchWatcherRecoveryState(
      workspaceId: workspaceId,
      failureCount: plan.action == WorkspaceSearchWatcherRecoveryAction.none
          ? 0
          : failureCount + 1,
      lastPlan: plan,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  WorkspaceSearchWatcherRecoveryState copyWith({
    String? workspaceId,
    int? failureCount,
    WorkspaceSearchWatcherRecoveryPlan? lastPlan,
    DateTime? updatedAt,
  }) {
    return WorkspaceSearchWatcherRecoveryState(
      workspaceId: workspaceId ?? this.workspaceId,
      failureCount: failureCount ?? this.failureCount,
      lastPlan: lastPlan ?? this.lastPlan,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'failureCount': failureCount,
      'recoveryDisabled': recoveryDisabled,
      if (lastPlan != null) 'lastPlan': lastPlan!.toJson(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class WorkspaceSearchWatcherRecoveryStore {
  WorkspaceSearchWatcherRecoveryStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'workspace.search-watcher-recovery',
             layer: 'interaction',
             stateFamily: 'search-watcher-recovery',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const WorkspaceSearchWatcherRecoveryStore({required this.owner});

  static const int schemaVersion = 1;
  static const String _namespaceName = 'workspace.search-watcher-recovery';
  static const String _key = 'recovery-state';

  final FoundationDataStoreOwner owner;

  Future<WorkspaceSearchWatcherRecoveryState> readState({
    required String workspaceId,
  }) async {
    final value = await owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return WorkspaceSearchWatcherRecoveryState(workspaceId: workspaceId);
    }
    final state = WorkspaceSearchWatcherRecoveryState.fromJson(value);
    return state.workspaceId.isEmpty
        ? state.copyWith(workspaceId: workspaceId)
        : state;
  }

  Future<WorkspaceSearchWatcherRecoveryState> saveState(
    WorkspaceSearchWatcherRecoveryState state,
  ) async {
    final next = state.copyWith(updatedAt: DateTime.now().toUtc());
    await owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: next.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: next.workspaceId,
    );
    return next;
  }

  Future<WorkspaceSearchWatcherRecoveryState> recordPlan({
    required String workspaceId,
    required WorkspaceSearchWatcherRecoveryPlan plan,
  }) async {
    final current = await readState(workspaceId: workspaceId);
    final next = current.recordPlan(plan);
    await saveState(next);
    return next;
  }

  Future<bool> deleteState({required String workspaceId}) {
    return owner.delete(
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

WorkspaceSearchWatcherRecoveryPlan? _workspaceSearchWatcherRecoveryPlanFromJson(
  Object? value,
) {
  if (value is! Map) {
    return null;
  }
  final json = value.map(
    (key, value) => MapEntry<String, Object?>(key.toString(), value),
  );
  final actionName = json['action'] as String? ?? '';
  final action = WorkspaceSearchWatcherRecoveryAction.values.firstWhere(
    (candidate) => candidate.name == actionName,
    orElse: () => WorkspaceSearchWatcherRecoveryAction.none,
  );
  return WorkspaceSearchWatcherRecoveryPlan(
    action: action,
    workspaceRoot: json['workspaceRoot'] as String? ?? '',
    persistenceKey:
        json['persistenceKey'] as String? ?? 'workspace-search-watcher',
    canRetry:
        json['canRetry'] as bool? ??
        (action == WorkspaceSearchWatcherRecoveryAction.restartWatcher ||
            action == WorkspaceSearchWatcherRecoveryAction.rebuildIndex),
    message: json['message'] as String? ?? '',
  );
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

List<String> _jsonStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return _sortedStrings(value.map((entry) => entry.toString()));
}

List<String> _sortedStrings(Iterable<String> values) {
  final normalized = values
      .map((value) => value.trim())
      .where((value) => value.isNotEmpty)
      .toSet()
      .toList(growable: false);
  normalized.sort();
  return normalized;
}
