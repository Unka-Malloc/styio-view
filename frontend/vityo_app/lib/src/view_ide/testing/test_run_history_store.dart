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
