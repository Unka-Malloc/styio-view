import '../foundation/foundation.dart';
import 'testing_provider.dart';

class TestRunHistory {
  const TestRunHistory({
    required this.workspaceId,
    this.runs = const <TestRunResult>[],
    this.updatedAt,
  });

  factory TestRunHistory.fromJson(Map<String, Object?> json) {
    return TestRunHistory(
      workspaceId: json['workspaceId'] as String? ?? '',
      runs: _jsonTestRuns(json['runs']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final List<TestRunResult> runs;
  final DateTime? updatedAt;

  TestRunHistory append(TestRunResult result, {int maxEntries = 30}) {
    return TestRunHistory(
      workspaceId: workspaceId,
      runs: <TestRunResult>[
        result,
        ...runs,
      ].take(maxEntries).toList(growable: false),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  TestRunHistory copyWith({
    String? workspaceId,
    List<TestRunResult>? runs,
    DateTime? updatedAt,
  }) {
    return TestRunHistory(
      workspaceId: workspaceId ?? this.workspaceId,
      runs: runs ?? this.runs,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'runCount': runs.length,
      'runs': runs.map((run) => run.toJson()).toList(growable: false),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class FailedTestRetryRecord {
  const FailedTestRetryRecord({
    required this.providerId,
    required this.status,
    this.runner = '',
    this.configurationId = '',
    this.filter = '',
    this.debug = false,
    this.failedCount = 0,
    this.message = '',
    this.attemptedAt,
  });

  factory FailedTestRetryRecord.fromJson(Map<String, Object?> json) {
    return FailedTestRetryRecord(
      providerId: json['providerId'] as String? ?? '',
      runner: json['runner'] as String? ?? '',
      configurationId: json['configurationId'] as String? ?? '',
      filter: json['filter'] as String? ?? '',
      debug: json['debug'] as bool? ?? false,
      failedCount: json['failedCount'] as int? ?? 0,
      status: testRunStatusFromWireValue(json['status'] as String?),
      message: json['message'] as String? ?? '',
      attemptedAt: DateTime.tryParse(
        json['attemptedAt'] as String? ?? '',
      )?.toUtc(),
    );
  }

  factory FailedTestRetryRecord.fromResult({
    required TestRunResult result,
    TestRunConfiguration? configuration,
    DateTime? attemptedAt,
  }) {
    return FailedTestRetryRecord(
      providerId: result.providerId,
      runner: result.runner,
      configurationId: configuration?.id ?? '',
      filter: configuration?.filter ?? '',
      debug: configuration?.debug ?? false,
      failedCount: result.failedCount,
      status: result.status,
      message: result.message,
      attemptedAt: attemptedAt,
    );
  }

  final String providerId;
  final String runner;
  final String configurationId;
  final String filter;
  final bool debug;
  final int failedCount;
  final TestRunStatus status;
  final String message;
  final DateTime? attemptedAt;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'providerId': providerId,
      if (runner.isNotEmpty) 'runner': runner,
      if (configurationId.isNotEmpty) 'configurationId': configurationId,
      if (filter.isNotEmpty) 'filter': filter,
      'debug': debug,
      'failedCount': failedCount,
      'status': status.wireValue,
      if (message.isNotEmpty) 'message': message,
      if (attemptedAt != null) 'attemptedAt': attemptedAt!.toIso8601String(),
    };
  }
}

class FailedTestRetryHistory {
  const FailedTestRetryHistory({
    required this.workspaceId,
    this.records = const <FailedTestRetryRecord>[],
    this.updatedAt,
  });

  factory FailedTestRetryHistory.fromJson(Map<String, Object?> json) {
    return FailedTestRetryHistory(
      workspaceId: json['workspaceId'] as String? ?? '',
      records: _jsonFailedRetryRecords(json['records']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final List<FailedTestRetryRecord> records;
  final DateTime? updatedAt;

  FailedTestRetryHistory append(
    FailedTestRetryRecord record, {
    int maxEntries = 30,
  }) {
    return FailedTestRetryHistory(
      workspaceId: workspaceId,
      records: <FailedTestRetryRecord>[
        record,
        ...records,
      ].take(maxEntries).toList(growable: false),
      updatedAt: DateTime.now().toUtc(),
    );
  }

  FailedTestRetryHistory copyWith({
    String? workspaceId,
    List<FailedTestRetryRecord>? records,
    DateTime? updatedAt,
  }) {
    return FailedTestRetryHistory(
      workspaceId: workspaceId ?? this.workspaceId,
      records: records ?? this.records,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'retryCount': records.length,
      'records': records.map((record) => record.toJson()).toList(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class TestRunHistoryStore {
  TestRunHistoryStore.fromDataStore({required FoundationDataStore dataStore})
    : this(
        owner: FoundationDataStoreOwner(
          descriptor: const FoundationDataStoreOwnerDescriptor(
            ownerId: 'interaction.testing.run-history',
            layer: 'interaction',
            stateFamily: 'test-run-history',
            allowedNamespaces: <String>{_namespaceName},
          ),
          dataStore: dataStore,
        ),
      );

  const TestRunHistoryStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'interaction.testing.run-history';
  static const String _key = 'runs';
  static const String _retryKey = 'failed-test-retries';

  final FoundationDataStoreOwner _owner;

  Future<void> saveHistory(TestRunHistory history) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: history.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: history.workspaceId,
    );
  }

  Future<TestRunHistory> readHistory({required String workspaceId}) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _key,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return TestRunHistory(workspaceId: workspaceId);
    }
    final history = TestRunHistory.fromJson(value);
    return history.workspaceId.isEmpty
        ? history.copyWith(workspaceId: workspaceId)
        : history;
  }

  Future<TestRunHistory> appendRun({
    required String workspaceId,
    required TestRunResult result,
    int maxEntries = 30,
  }) async {
    final current = await readHistory(workspaceId: workspaceId);
    final next = current.append(result, maxEntries: maxEntries);
    await saveHistory(next);
    return next;
  }

  Future<void> saveFailedRetryHistory(FailedTestRetryHistory history) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _retryKey,
      value: history.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: history.workspaceId,
    );
  }

  Future<FailedTestRetryHistory> readFailedRetryHistory({
    required String workspaceId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _retryKey,
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return FailedTestRetryHistory(workspaceId: workspaceId);
    }
    final history = FailedTestRetryHistory.fromJson(value);
    return history.workspaceId.isEmpty
        ? history.copyWith(workspaceId: workspaceId)
        : history;
  }

  Future<FailedTestRetryHistory> appendFailedRetry({
    required String workspaceId,
    required FailedTestRetryRecord record,
    int maxEntries = 30,
  }) async {
    final current = await readFailedRetryHistory(workspaceId: workspaceId);
    final next = current.append(record, maxEntries: maxEntries);
    await saveFailedRetryHistory(next);
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

List<FailedTestRetryRecord> _jsonFailedRetryRecords(Object? value) {
  if (value is! List) {
    return const <FailedTestRetryRecord>[];
  }
  return value
      .whereType<Map>()
      .map(
        (record) => FailedTestRetryRecord.fromJson(
          record.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}

List<TestRunResult> _jsonTestRuns(Object? value) {
  if (value is! List) {
    return const <TestRunResult>[];
  }
  return value
      .whereType<Map>()
      .map(
        (run) => TestRunResult.fromJson(
          run.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}
