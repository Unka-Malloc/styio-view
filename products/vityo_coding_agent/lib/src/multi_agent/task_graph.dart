library;

import 'dart:collection';

final class WorkerScope {
  WorkerScope({
    required Set<String> contextEvidenceIds,
    required Set<String> toolIds,
    required this.maxOperations,
  }) : contextEvidenceIds = Set<String>.unmodifiable(contextEvidenceIds),
       toolIds = Set<String>.unmodifiable(toolIds) {
    if (this.contextEvidenceIds.any((id) => id.trim().isEmpty) ||
        this.toolIds.any((id) => id.trim().isEmpty) ||
        maxOperations <= 0) {
      throw ArgumentError('Worker scope is invalid.');
    }
  }

  final Set<String> contextEvidenceIds;
  final Set<String> toolIds;
  final int maxOperations;
}

final class DelegatedTask {
  DelegatedTask({
    required this.id,
    required this.title,
    required Set<String> prerequisites,
    required Set<String> ownedResources,
    required this.scope,
  }) : prerequisites = Set<String>.unmodifiable(prerequisites),
       ownedResources = Set<String>.unmodifiable(ownedResources) {
    if (id.trim().isEmpty ||
        title.trim().isEmpty ||
        this.ownedResources.isEmpty ||
        this.ownedResources.any(
          (resource) => !isNormalizedOwnership(resource),
        )) {
      throw ArgumentError('Delegated task is invalid.');
    }
  }

  final String id;
  final String title;
  final Set<String> prerequisites;
  final Set<String> ownedResources;
  final WorkerScope scope;
}

final class TaskGraph {
  TaskGraph({required List<DelegatedTask> tasks})
    : tasks = List<DelegatedTask>.unmodifiable(tasks),
      _byId = <String, DelegatedTask>{for (final task in tasks) task.id: task},
      _indegrees = <String, int>{
        for (final task in tasks) task.id: task.prerequisites.length,
      },
      _dependents = <String, List<String>>{
        for (final task in tasks) task.id: <String>[],
      } {
    if (this.tasks.isEmpty || _byId.length != this.tasks.length) {
      throw ArgumentError('Task graph IDs must be non-empty and unique.');
    }
    for (final task in this.tasks) {
      if (task.prerequisites.contains(task.id) ||
          task.prerequisites.any((id) => !_byId.containsKey(id))) {
        throw ArgumentError('Task graph contains an invalid prerequisite.');
      }
      for (final prerequisite in task.prerequisites) {
        _dependents[prerequisite]!.add(task.id);
      }
    }
    for (final dependents in _dependents.values) {
      dependents.sort();
    }
    if (_topologicalCount() != this.tasks.length) {
      throw ArgumentError('Task graph contains a cycle.');
    }
  }

  final List<DelegatedTask> tasks;
  final Map<String, DelegatedTask> _byId;
  final Map<String, int> _indegrees;
  final Map<String, List<String>> _dependents;

  DelegatedTask? find(String id) => _byId[id];

  TaskGraphSchedule createSchedule() => TaskGraphSchedule._(this);

  List<DelegatedTask> ready({
    required Set<String> completed,
    required Set<String> started,
  }) {
    final result =
        tasks
            .where(
              (task) =>
                  !started.contains(task.id) &&
                  task.prerequisites.every(completed.contains),
            )
            .toList(growable: false)
          ..sort((left, right) => left.id.compareTo(right.id));
    return List<DelegatedTask>.unmodifiable(result);
  }

  int _topologicalCount() {
    final remaining = Map<String, int>.of(_indegrees);
    final ready = SplayTreeSet<String>()
      ..addAll(
        remaining.entries
            .where((entry) => entry.value == 0)
            .map((entry) => entry.key),
      );
    var count = 0;
    while (ready.isNotEmpty) {
      final id = ready.first;
      ready.remove(id);
      count += 1;
      for (final dependent in _dependents[id]!) {
        final next = remaining[dependent]! - 1;
        remaining[dependent] = next;
        if (next == 0) ready.add(dependent);
      }
    }
    return count;
  }
}

final class TaskGraphSchedule {
  TaskGraphSchedule._(this._graph)
    : _remainingPrerequisites = Map<String, int>.of(_graph._indegrees) {
    _ready.addAll(
      _remainingPrerequisites.entries
          .where((entry) => entry.value == 0)
          .map((entry) => entry.key),
    );
  }

  final TaskGraph _graph;
  final Map<String, int> _remainingPrerequisites;
  final SplayTreeSet<String> _ready = SplayTreeSet<String>();
  final Set<String> _started = <String>{};
  final Set<String> _completed = <String>{};

  Iterable<DelegatedTask> get ready sync* {
    for (final id in _ready) {
      yield _graph._byId[id]!;
    }
  }

  bool get hasReady => _ready.isNotEmpty;

  void markStarted(String taskId) {
    if (!_ready.remove(taskId) || !_started.add(taskId)) {
      throw StateError('Task is not ready to start.');
    }
  }

  void markCompleted(String taskId) {
    if (!_started.contains(taskId) || !_completed.add(taskId)) {
      throw StateError('Task was not started or was already completed.');
    }
    for (final dependent in _graph._dependents[taskId]!) {
      final next = _remainingPrerequisites[dependent]! - 1;
      _remainingPrerequisites[dependent] = next;
      if (next == 0 && !_started.contains(dependent)) {
        _ready.add(dependent);
      }
    }
  }
}

bool isNormalizedOwnership(String resource) {
  if (resource.isEmpty ||
      resource != resource.trim() ||
      resource.startsWith('/') ||
      resource.contains(r'\') ||
      resource.contains(':') ||
      resource.contains('*') ||
      resource.contains('?')) {
    return false;
  }
  return resource
      .split('/')
      .every(
        (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
      );
}

bool ownershipScopesOverlap(String left, String right) =>
    left == right || left.startsWith('$right/') || right.startsWith('$left/');

bool ownershipScopeContains(String owner, String resource) =>
    owner == resource || resource.startsWith('$owner/');
