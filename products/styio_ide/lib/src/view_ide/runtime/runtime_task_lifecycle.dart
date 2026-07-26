typedef RuntimeTaskClock = DateTime Function();

DateTime _runtimeTaskNow() => DateTime.now().toUtc();

enum RuntimeTaskKind { shell, run, build, test, debug, agent, toolchain }

extension RuntimeTaskKindX on RuntimeTaskKind {
  String get wireValue => switch (this) {
    RuntimeTaskKind.shell => 'shell',
    RuntimeTaskKind.run => 'run',
    RuntimeTaskKind.build => 'build',
    RuntimeTaskKind.test => 'test',
    RuntimeTaskKind.debug => 'debug',
    RuntimeTaskKind.agent => 'agent',
    RuntimeTaskKind.toolchain => 'toolchain',
  };
}

enum RuntimeTaskStatus {
  queued,
  starting,
  running,
  succeeded,
  failed,
  cancelled,
  blocked,
}

extension RuntimeTaskStatusX on RuntimeTaskStatus {
  String get wireValue => switch (this) {
    RuntimeTaskStatus.queued => 'queued',
    RuntimeTaskStatus.starting => 'starting',
    RuntimeTaskStatus.running => 'running',
    RuntimeTaskStatus.succeeded => 'succeeded',
    RuntimeTaskStatus.failed => 'failed',
    RuntimeTaskStatus.cancelled => 'cancelled',
    RuntimeTaskStatus.blocked => 'blocked',
  };
}

class RuntimeTaskDefinition {
  const RuntimeTaskDefinition({
    required this.id,
    required this.label,
    required this.kind,
    required this.command,
    this.arguments = const <String>[],
    this.workingDirectory,
    this.environment = const <String, String>{},
    this.dependsOn = const <String>[],
    this.group,
    this.terminalProfileId,
    this.background = false,
    this.metadata = const <String, Object?>{},
  });

  factory RuntimeTaskDefinition.fromJson(Map<String, Object?> json) {
    return RuntimeTaskDefinition(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      kind: _runtimeTaskKindFromWire(json['kind']),
      command: json['command'] as String? ?? '',
      arguments: _jsonStringList(json['arguments']),
      workingDirectory: _jsonNullableString(json['workingDirectory']),
      environment: _jsonStringMap(json['environment']),
      dependsOn: _jsonStringList(json['dependsOn']),
      group: _jsonNullableString(json['group']),
      terminalProfileId: _jsonNullableString(json['terminalProfileId']),
      background: json['background'] as bool? ?? false,
      metadata: _jsonObjectMap(json['metadata']),
    );
  }

  final String id;
  final String label;
  final RuntimeTaskKind kind;
  final String command;
  final List<String> arguments;
  final String? workingDirectory;
  final Map<String, String> environment;
  final List<String> dependsOn;
  final String? group;
  final String? terminalProfileId;
  final bool background;
  final Map<String, Object?> metadata;

  bool get runnable => id.trim().isNotEmpty && command.trim().isNotEmpty;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'kind': kind.wireValue,
      'command': command,
      'arguments': arguments,
      if (workingDirectory != null) 'workingDirectory': workingDirectory,
      'environment': environment,
      'dependsOn': dependsOn,
      if (group != null) 'group': group,
      if (terminalProfileId != null) 'terminalProfileId': terminalProfileId,
      'background': background,
      'runnable': runnable,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class RuntimeTaskLifecycleEvent {
  const RuntimeTaskLifecycleEvent({
    required this.taskId,
    required this.sequence,
    required this.status,
    required this.timestamp,
    required this.message,
    this.source = 'runtime-task-controller',
    this.exitCode,
    this.metadata = const <String, Object?>{},
  });

  factory RuntimeTaskLifecycleEvent.fromJson(Map<String, Object?> json) {
    return RuntimeTaskLifecycleEvent(
      taskId: json['taskId'] as String? ?? '',
      sequence: json['sequence'] as int? ?? 0,
      status: _runtimeTaskStatusFromWire(json['status']),
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      message: json['message'] as String? ?? '',
      source: json['source'] as String? ?? 'runtime-task-controller',
      exitCode: json['exitCode'] as int?,
      metadata: _jsonObjectMap(json['metadata']),
    );
  }

  final String taskId;
  final int sequence;
  final RuntimeTaskStatus status;
  final DateTime timestamp;
  final String message;
  final String source;
  final int? exitCode;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'taskId': taskId,
      'sequence': sequence,
      'status': status.wireValue,
      'timestamp': timestamp.toIso8601String(),
      'message': message,
      'source': source,
      if (exitCode != null) 'exitCode': exitCode,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class RuntimeTaskSnapshot {
  const RuntimeTaskSnapshot({
    required this.definition,
    required this.status,
    required this.statusMessage,
    this.startedAt,
    this.finishedAt,
    this.exitCode,
    this.events = const <RuntimeTaskLifecycleEvent>[],
  });

  factory RuntimeTaskSnapshot.fromJson(Map<String, Object?> json) {
    final definition = json['definition'];
    return RuntimeTaskSnapshot(
      definition: definition is Map<String, Object?>
          ? RuntimeTaskDefinition.fromJson(definition)
          : definition is Map
          ? RuntimeTaskDefinition.fromJson(
              definition.map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : const RuntimeTaskDefinition(
              id: '',
              label: '',
              kind: RuntimeTaskKind.shell,
              command: '',
            ),
      status: _runtimeTaskStatusFromWire(json['status']),
      statusMessage: json['statusMessage'] as String? ?? '',
      startedAt: DateTime.tryParse(json['startedAt'] as String? ?? '')?.toUtc(),
      finishedAt: DateTime.tryParse(
        json['finishedAt'] as String? ?? '',
      )?.toUtc(),
      exitCode: json['exitCode'] as int?,
      events: _jsonLifecycleEvents(json['events']),
    );
  }

  final RuntimeTaskDefinition definition;
  final RuntimeTaskStatus status;
  final String statusMessage;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int? exitCode;
  final List<RuntimeTaskLifecycleEvent> events;

  bool get active {
    return switch (status) {
      RuntimeTaskStatus.queued ||
      RuntimeTaskStatus.starting ||
      RuntimeTaskStatus.running => true,
      RuntimeTaskStatus.succeeded ||
      RuntimeTaskStatus.failed ||
      RuntimeTaskStatus.cancelled ||
      RuntimeTaskStatus.blocked => false,
    };
  }

  bool get terminal => !active;

  int? get durationMs {
    final start = startedAt;
    final finish = finishedAt;
    if (start == null || finish == null) {
      return null;
    }
    return finish.difference(start).inMilliseconds;
  }

  RuntimeTaskLifecycleEvent? get lastEvent {
    return events.isEmpty ? null : events.last;
  }

  RuntimeTaskSnapshot copyWith({
    RuntimeTaskDefinition? definition,
    RuntimeTaskStatus? status,
    String? statusMessage,
    DateTime? startedAt,
    bool clearStartedAt = false,
    DateTime? finishedAt,
    bool clearFinishedAt = false,
    int? exitCode,
    bool clearExitCode = false,
    List<RuntimeTaskLifecycleEvent>? events,
  }) {
    return RuntimeTaskSnapshot(
      definition: definition ?? this.definition,
      status: status ?? this.status,
      statusMessage: statusMessage ?? this.statusMessage,
      startedAt: clearStartedAt ? null : startedAt ?? this.startedAt,
      finishedAt: clearFinishedAt ? null : finishedAt ?? this.finishedAt,
      exitCode: clearExitCode ? null : exitCode ?? this.exitCode,
      events: events ?? this.events,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'definition': definition.toJson(),
      'status': status.wireValue,
      'statusMessage': statusMessage,
      'active': active,
      'terminal': terminal,
      if (startedAt != null) 'startedAt': startedAt!.toIso8601String(),
      if (finishedAt != null) 'finishedAt': finishedAt!.toIso8601String(),
      if (durationMs != null) 'durationMs': durationMs,
      if (exitCode != null) 'exitCode': exitCode,
      'eventCount': events.length,
      'events': events.map((event) => event.toJson()).toList(growable: false),
    };
  }
}

class RuntimeTaskLifecycleController {
  RuntimeTaskLifecycleController({
    Iterable<RuntimeTaskDefinition> definitions =
        const <RuntimeTaskDefinition>[],
    RuntimeTaskClock? clock,
  }) : _clock = clock ?? _runtimeTaskNow {
    for (final definition in definitions) {
      register(definition);
    }
  }

  final RuntimeTaskClock _clock;
  final Map<String, RuntimeTaskSnapshot> _snapshots =
      <String, RuntimeTaskSnapshot>{};
  int _sequence = 0;

  List<RuntimeTaskSnapshot> get snapshots {
    return List<RuntimeTaskSnapshot>.unmodifiable(_snapshots.values);
  }

  RuntimeTaskSnapshot? snapshotFor(String taskId) => _snapshots[taskId];

  RuntimeTaskSnapshot register(RuntimeTaskDefinition definition) {
    final existing = _snapshots[definition.id];
    if (existing != null) {
      final updated = existing.copyWith(definition: definition);
      _snapshots[definition.id] = updated;
      return updated;
    }
    final event = _event(
      taskId: definition.id,
      status: RuntimeTaskStatus.queued,
      message: definition.runnable
          ? 'Task ${definition.id} registered.'
          : 'Task ${definition.id} registered but is not runnable.',
    );
    final snapshot = RuntimeTaskSnapshot(
      definition: definition,
      status: RuntimeTaskStatus.queued,
      statusMessage: event.message,
      events: <RuntimeTaskLifecycleEvent>[event],
    );
    _snapshots[definition.id] = snapshot;
    return snapshot;
  }

  RuntimeTaskSnapshot queue(String taskId, {String? message}) {
    return _transition(
      taskId,
      RuntimeTaskStatus.queued,
      message: message ?? 'Task $taskId queued.',
      clearFinishedAt: true,
      clearExitCode: true,
    );
  }

  RuntimeTaskSnapshot start(String taskId, {String? message}) {
    final now = _clock();
    return _transition(
      taskId,
      RuntimeTaskStatus.running,
      message: message ?? 'Task $taskId started.',
      startedAt: now,
      clearFinishedAt: true,
      clearExitCode: true,
    );
  }

  RuntimeTaskSnapshot complete(
    String taskId, {
    int exitCode = 0,
    String? message,
  }) {
    return _transition(
      taskId,
      exitCode == 0 ? RuntimeTaskStatus.succeeded : RuntimeTaskStatus.failed,
      message:
          message ??
          (exitCode == 0
              ? 'Task $taskId completed.'
              : 'Task $taskId failed with exit code $exitCode.'),
      finishedAt: _clock(),
      exitCode: exitCode,
    );
  }

  RuntimeTaskSnapshot fail(
    String taskId, {
    String? message,
    int? exitCode,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _transition(
      taskId,
      RuntimeTaskStatus.failed,
      message: message ?? 'Task $taskId failed.',
      finishedAt: _clock(),
      exitCode: exitCode,
      metadata: metadata,
    );
  }

  RuntimeTaskSnapshot cancel(
    String taskId, {
    String? message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _transition(
      taskId,
      RuntimeTaskStatus.cancelled,
      message: message ?? 'Task $taskId cancelled.',
      finishedAt: _clock(),
      metadata: metadata,
    );
  }

  RuntimeTaskSnapshot block(
    String taskId, {
    String? message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _transition(
      taskId,
      RuntimeTaskStatus.blocked,
      message: message ?? 'Task $taskId blocked.',
      finishedAt: _clock(),
      metadata: metadata,
    );
  }

  RuntimeTaskSnapshot _transition(
    String taskId,
    RuntimeTaskStatus status, {
    required String message,
    DateTime? startedAt,
    bool clearStartedAt = false,
    DateTime? finishedAt,
    bool clearFinishedAt = false,
    int? exitCode,
    bool clearExitCode = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final current = _snapshots[taskId];
    if (current == null) {
      throw StateError('Runtime task $taskId is not registered.');
    }
    final event = _event(
      taskId: taskId,
      status: status,
      message: message,
      exitCode: exitCode,
      metadata: metadata,
    );
    final next = current.copyWith(
      status: status,
      statusMessage: message,
      startedAt: startedAt,
      clearStartedAt: clearStartedAt,
      finishedAt: finishedAt,
      clearFinishedAt: clearFinishedAt,
      exitCode: exitCode,
      clearExitCode: clearExitCode,
      events: <RuntimeTaskLifecycleEvent>[...current.events, event],
    );
    _snapshots[taskId] = next;
    return next;
  }

  RuntimeTaskLifecycleEvent _event({
    required String taskId,
    required RuntimeTaskStatus status,
    required String message,
    int? exitCode,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    _sequence += 1;
    return RuntimeTaskLifecycleEvent(
      taskId: taskId,
      sequence: _sequence,
      status: status,
      timestamp: _clock(),
      message: message,
      exitCode: exitCode,
      metadata: metadata,
    );
  }
}

RuntimeTaskKind _runtimeTaskKindFromWire(Object? value) {
  return switch (value) {
    'shell' => RuntimeTaskKind.shell,
    'run' => RuntimeTaskKind.run,
    'build' => RuntimeTaskKind.build,
    'test' => RuntimeTaskKind.test,
    'debug' => RuntimeTaskKind.debug,
    'agent' => RuntimeTaskKind.agent,
    'toolchain' => RuntimeTaskKind.toolchain,
    _ => RuntimeTaskKind.shell,
  };
}

RuntimeTaskStatus _runtimeTaskStatusFromWire(Object? value) {
  return switch (value) {
    'queued' => RuntimeTaskStatus.queued,
    'starting' => RuntimeTaskStatus.starting,
    'running' => RuntimeTaskStatus.running,
    'succeeded' => RuntimeTaskStatus.succeeded,
    'failed' => RuntimeTaskStatus.failed,
    'cancelled' => RuntimeTaskStatus.cancelled,
    'blocked' => RuntimeTaskStatus.blocked,
    _ => RuntimeTaskStatus.blocked,
  };
}

String? _jsonNullableString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

List<String> _jsonStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value
      .map((item) => '$item'.trim())
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

Map<String, String> _jsonStringMap(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }
  final result = <String, String>{};
  for (final entry in value.entries) {
    final key = entry.key.toString().trim();
    if (key.isNotEmpty) {
      result[key] = entry.value.toString();
    }
  }
  return Map<String, String>.unmodifiable(result);
}

Map<String, Object?> _jsonObjectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiable(
    value.map((key, value) => MapEntry<String, Object?>(key.toString(), value)),
  );
}

List<RuntimeTaskLifecycleEvent> _jsonLifecycleEvents(Object? value) {
  if (value is! List) {
    return const <RuntimeTaskLifecycleEvent>[];
  }
  return value
      .whereType<Map>()
      .map(
        (event) => RuntimeTaskLifecycleEvent.fromJson(
          event.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}
