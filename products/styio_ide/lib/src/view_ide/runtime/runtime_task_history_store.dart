import '../foundation/foundation.dart';
import 'runtime_task_lifecycle.dart';

class RuntimeTaskHistorySnapshot {
  const RuntimeTaskHistorySnapshot({
    required this.workspaceId,
    this.tasks = const <RuntimeTaskSnapshot>[],
    this.updatedAt,
  });

  factory RuntimeTaskHistorySnapshot.fromJson(Map<String, Object?> json) {
    return RuntimeTaskHistorySnapshot(
      workspaceId: json['workspaceId'] as String? ?? '',
      tasks: _jsonTaskSnapshots(json['tasks']),
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final List<RuntimeTaskSnapshot> tasks;
  final DateTime? updatedAt;

  RuntimeTaskHistorySnapshot append(
    RuntimeTaskSnapshot task, {
    int maxEntries = 50,
    DateTime? updatedAt,
  }) {
    final nextTasks = <RuntimeTaskSnapshot>[
      task,
      ...tasks.where(
        (existing) => existing.definition.id != task.definition.id,
      ),
    ];
    return RuntimeTaskHistorySnapshot(
      workspaceId: workspaceId,
      tasks: nextTasks.take(maxEntries).toList(growable: false),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  RuntimeTaskHistorySnapshot copyWith({
    String? workspaceId,
    List<RuntimeTaskSnapshot>? tasks,
    DateTime? updatedAt,
  }) {
    return RuntimeTaskHistorySnapshot(
      workspaceId: workspaceId ?? this.workspaceId,
      tasks: tasks ?? this.tasks,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'taskCount': tasks.length,
      'tasks': tasks.map((task) => task.toJson()).toList(growable: false),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class RuntimeTaskHistoryStore {
  RuntimeTaskHistoryStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'runtime.task-history',
             layer: 'runtime',
             stateFamily: 'task-history',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const RuntimeTaskHistoryStore({required FoundationDataStoreOwner owner})
    : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName = 'runtime.task-history';
  static const String _key = 'tasks';

  final FoundationDataStoreOwner _owner;

  Future<void> saveHistory(RuntimeTaskHistorySnapshot history) {
    return _owner.writeJson(
      namespaceName: _namespaceName,
      key: _key,
      value: history.copyWith(updatedAt: DateTime.now().toUtc()).toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: history.workspaceId,
    );
  }

  Future<RuntimeTaskHistorySnapshot> readHistory({
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
      return RuntimeTaskHistorySnapshot(workspaceId: workspaceId);
    }
    final history = RuntimeTaskHistorySnapshot.fromJson(value);
    return history.workspaceId.isEmpty
        ? history.copyWith(workspaceId: workspaceId)
        : history;
  }

  Future<RuntimeTaskHistorySnapshot> appendTask({
    required String workspaceId,
    required RuntimeTaskSnapshot task,
    int maxEntries = 50,
  }) async {
    final current = await readHistory(workspaceId: workspaceId);
    final next = current.append(task, maxEntries: maxEntries);
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

List<RuntimeTaskSnapshot> _jsonTaskSnapshots(Object? value) {
  if (value is! List) {
    return const <RuntimeTaskSnapshot>[];
  }
  return value
      .whereType<Map>()
      .map(
        (task) => RuntimeTaskSnapshot.fromJson(
          task.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}
