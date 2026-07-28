import 'dart:convert';

import '../environment/configuration/environment_variable_configuration.dart';
import '../environment/system_compatibility/process/process_manager.dart';
import '../environment/system_compatibility/pty/pty_manager.dart';
import 'runtime_task_lifecycle.dart';

enum TaskExecutionStreamKind { stdout, stderr }

extension TaskExecutionStreamKindX on TaskExecutionStreamKind {
  String get wireValue => switch (this) {
    TaskExecutionStreamKind.stdout => 'stdout',
    TaskExecutionStreamKind.stderr => 'stderr',
  };
}

enum TaskExecutionEventKind {
  started,
  stdoutDelta,
  stderrDelta,
  diagnostic,
  runtimeEvent,
  exit,
  cancelled,
  cleanup,
}

extension TaskExecutionEventKindX on TaskExecutionEventKind {
  String get wireValue => switch (this) {
    TaskExecutionEventKind.started => 'started',
    TaskExecutionEventKind.stdoutDelta => 'stdout-delta',
    TaskExecutionEventKind.stderrDelta => 'stderr-delta',
    TaskExecutionEventKind.diagnostic => 'diagnostic',
    TaskExecutionEventKind.runtimeEvent => 'runtime-event',
    TaskExecutionEventKind.exit => 'exit',
    TaskExecutionEventKind.cancelled => 'cancelled',
    TaskExecutionEventKind.cleanup => 'cleanup',
  };
}

enum TaskExecutionDiagnosticSeverity { info, warning, error }

extension TaskExecutionDiagnosticSeverityX on TaskExecutionDiagnosticSeverity {
  String get wireValue => switch (this) {
    TaskExecutionDiagnosticSeverity.info => 'info',
    TaskExecutionDiagnosticSeverity.warning => 'warning',
    TaskExecutionDiagnosticSeverity.error => 'error',
  };
}

enum TaskExecutionStatus { running, exited, cancelled, cleanedUp }

extension TaskExecutionStatusX on TaskExecutionStatus {
  String get wireValue => switch (this) {
    TaskExecutionStatus.running => 'running',
    TaskExecutionStatus.exited => 'exited',
    TaskExecutionStatus.cancelled => 'cancelled',
    TaskExecutionStatus.cleanedUp => 'cleaned-up',
  };
}

class TaskExecutionOutputDelta {
  const TaskExecutionOutputDelta({
    required this.sequence,
    required this.stream,
    required this.timestamp,
    required this.text,
    required this.byteCount,
    this.truncated = false,
  });

  factory TaskExecutionOutputDelta.fromJson(Map<String, Object?> json) {
    return TaskExecutionOutputDelta(
      sequence: json['sequence'] as int? ?? 0,
      stream:
          _taskExecutionStreamKindFromWire(json['stream'] as String? ?? '') ??
          TaskExecutionStreamKind.stdout,
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      text: json['text'] as String? ?? '',
      byteCount: json['byteCount'] as int? ?? 0,
      truncated: json['truncated'] as bool? ?? false,
    );
  }

  final int sequence;
  final TaskExecutionStreamKind stream;
  final DateTime timestamp;
  final String text;
  final int byteCount;
  final bool truncated;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sequence': sequence,
      'stream': stream.wireValue,
      'timestamp': timestamp.toIso8601String(),
      'text': text,
      'byteCount': byteCount,
      'truncated': truncated,
    };
  }
}

class TaskExecutionDiagnostic {
  const TaskExecutionDiagnostic({
    required this.sequence,
    required this.severity,
    required this.code,
    required this.message,
    required this.timestamp,
    this.source = '',
    this.metadata = const <String, Object?>{},
  });

  factory TaskExecutionDiagnostic.fromJson(Map<String, Object?> json) {
    return TaskExecutionDiagnostic(
      sequence: json['sequence'] as int? ?? 0,
      severity:
          _taskExecutionDiagnosticSeverityFromWire(
            json['severity'] as String? ?? '',
          ) ??
          TaskExecutionDiagnosticSeverity.info,
      code: json['code'] as String? ?? '',
      message: json['message'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      source: json['source'] as String? ?? '',
      metadata: _jsonObjectMap(json['metadata']),
    );
  }

  final int sequence;
  final TaskExecutionDiagnosticSeverity severity;
  final String code;
  final String message;
  final DateTime timestamp;
  final String source;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sequence': sequence,
      'severity': severity.wireValue,
      'code': code,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      if (source.isNotEmpty) 'source': source,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class TaskExecutionRuntimeEvent {
  const TaskExecutionRuntimeEvent({
    required this.sequence,
    required this.kind,
    required this.message,
    required this.timestamp,
    this.metadata = const <String, Object?>{},
  });

  factory TaskExecutionRuntimeEvent.fromJson(Map<String, Object?> json) {
    return TaskExecutionRuntimeEvent(
      sequence: json['sequence'] as int? ?? 0,
      kind:
          _taskExecutionEventKindFromWire(json['kind'] as String? ?? '') ??
          TaskExecutionEventKind.runtimeEvent,
      message: json['message'] as String? ?? '',
      timestamp:
          DateTime.tryParse(json['timestamp'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      metadata: _jsonObjectMap(json['metadata']),
    );
  }

  final int sequence;
  final TaskExecutionEventKind kind;
  final String message;
  final DateTime timestamp;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sequence': sequence,
      'kind': kind.wireValue,
      'message': message,
      'timestamp': timestamp.toIso8601String(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class TaskExecutionCancellation {
  const TaskExecutionCancellation({
    required this.reason,
    required this.requestedAt,
    this.forced = false,
    this.metadata = const <String, Object?>{},
  });

  factory TaskExecutionCancellation.fromJson(Map<String, Object?> json) {
    return TaskExecutionCancellation(
      reason: json['reason'] as String? ?? '',
      requestedAt:
          DateTime.tryParse(json['requestedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      forced: json['forced'] as bool? ?? false,
      metadata: _jsonObjectMap(json['metadata']),
    );
  }

  final String reason;
  final DateTime requestedAt;
  final bool forced;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'reason': reason,
      'requestedAt': requestedAt.toIso8601String(),
      'forced': forced,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class TaskExecutionCleanup {
  const TaskExecutionCleanup({
    required this.completedAt,
    this.message = '',
    this.succeeded = true,
    this.metadata = const <String, Object?>{},
  });

  factory TaskExecutionCleanup.fromJson(Map<String, Object?> json) {
    return TaskExecutionCleanup(
      completedAt:
          DateTime.tryParse(json['completedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      message: json['message'] as String? ?? '',
      succeeded: json['succeeded'] as bool? ?? true,
      metadata: _jsonObjectMap(json['metadata']),
    );
  }

  final DateTime completedAt;
  final String message;
  final bool succeeded;
  final Map<String, Object?> metadata;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'completedAt': completedAt.toIso8601String(),
      'succeeded': succeeded,
      if (message.isNotEmpty) 'message': message,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

class TaskExecutionRuntimeRecord {
  const TaskExecutionRuntimeRecord({
    required this.operationId,
    required this.argv,
    required this.cwd,
    required this.redactedEnvironment,
    required this.startedAt,
    this.stdoutDeltas = const <TaskExecutionOutputDelta>[],
    this.stderrDeltas = const <TaskExecutionOutputDelta>[],
    this.diagnostics = const <TaskExecutionDiagnostic>[],
    this.runtimeEvents = const <TaskExecutionRuntimeEvent>[],
    this.exitCode,
    this.cancellation,
    this.cleanup,
    this.maxStdoutBytes = 64 * 1024,
    this.maxStderrBytes = 64 * 1024,
    this.maxStdoutDeltas = 128,
    this.maxStderrDeltas = 128,
    this.stdoutTruncated = false,
    this.stderrTruncated = false,
    this.schemaVersion = 1,
  });

  factory TaskExecutionRuntimeRecord.fromProcessRequest({
    required String operationId,
    required ProcessCommandRequest request,
    EnvironmentVariableRedactionPolicy redactionPolicy =
        const EnvironmentVariableRedactionPolicy(),
    DateTime? startedAt,
    int maxStdoutBytes = 64 * 1024,
    int maxStderrBytes = 64 * 1024,
    int maxStdoutDeltas = 128,
    int maxStderrDeltas = 128,
  }) {
    final startTimestamp = startedAt ?? DateTime.now().toUtc();
    return TaskExecutionRuntimeRecord(
      operationId: operationId,
      argv: <String>[request.executablePath, ...request.arguments],
      cwd: request.workingDirectory ?? '.',
      redactedEnvironment: redactionPolicy.redactEnvironment(
        request.environment,
      ),
      startedAt: startTimestamp,
      maxStdoutBytes: maxStdoutBytes,
      maxStderrBytes: maxStderrBytes,
      maxStdoutDeltas: maxStdoutDeltas,
      maxStderrDeltas: maxStderrDeltas,
      runtimeEvents: <TaskExecutionRuntimeEvent>[
        TaskExecutionRuntimeEvent(
          sequence: 1,
          kind: TaskExecutionEventKind.started,
          message: 'Task execution started.',
          timestamp: startTimestamp,
          metadata: <String, Object?>{
            'operationId': operationId,
            'argv': <String>[request.executablePath, ...request.arguments],
            'cwd': request.workingDirectory ?? '.',
          },
        ),
      ],
    );
  }

  factory TaskExecutionRuntimeRecord.fromPtyRequest({
    required String operationId,
    required PtySessionRequest request,
    EnvironmentVariableRedactionPolicy redactionPolicy =
        const EnvironmentVariableRedactionPolicy(),
    DateTime? startedAt,
    int maxStdoutBytes = 64 * 1024,
    int maxStderrBytes = 64 * 1024,
    int maxStdoutDeltas = 128,
    int maxStderrDeltas = 128,
  }) {
    final startTimestamp = startedAt ?? DateTime.now().toUtc();
    return TaskExecutionRuntimeRecord(
      operationId: operationId,
      argv: <String>[request.executablePath, ...request.arguments],
      cwd: request.workingDirectory ?? '.',
      redactedEnvironment: redactionPolicy.redactEnvironment(
        request.environment,
      ),
      startedAt: startTimestamp,
      maxStdoutBytes: maxStdoutBytes,
      maxStderrBytes: maxStderrBytes,
      maxStdoutDeltas: maxStdoutDeltas,
      maxStderrDeltas: maxStderrDeltas,
      runtimeEvents: <TaskExecutionRuntimeEvent>[
        TaskExecutionRuntimeEvent(
          sequence: 1,
          kind: TaskExecutionEventKind.started,
          message: 'Task execution started.',
          timestamp: startTimestamp,
          metadata: <String, Object?>{
            'operationId': operationId,
            'argv': <String>[request.executablePath, ...request.arguments],
            'cwd': request.workingDirectory ?? '.',
          },
        ),
      ],
    );
  }

  factory TaskExecutionRuntimeRecord.fromJson(Map<String, Object?> json) {
    return TaskExecutionRuntimeRecord(
      operationId: json['operationId'] as String? ?? '',
      argv: _jsonStringList(json['argv']),
      cwd: json['cwd'] as String? ?? '.',
      redactedEnvironment: _jsonStringMap(json['redactedEnvironment']),
      startedAt:
          DateTime.tryParse(json['startedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      stdoutDeltas: _jsonOutputDeltas(json['stdoutDeltas']),
      stderrDeltas: _jsonOutputDeltas(json['stderrDeltas']),
      diagnostics: _jsonDiagnostics(json['diagnostics']),
      runtimeEvents: _jsonRuntimeEvents(json['runtimeEvents']),
      exitCode: json['exitCode'] as int?,
      cancellation: json['cancellation'] is Map
          ? TaskExecutionCancellation.fromJson(
              (json['cancellation']! as Map).map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : null,
      cleanup: json['cleanup'] is Map
          ? TaskExecutionCleanup.fromJson(
              (json['cleanup']! as Map).map(
                (key, value) =>
                    MapEntry<String, Object?>(key.toString(), value),
              ),
            )
          : null,
      maxStdoutBytes: json['maxStdoutBytes'] as int? ?? 64 * 1024,
      maxStderrBytes: json['maxStderrBytes'] as int? ?? 64 * 1024,
      maxStdoutDeltas: json['maxStdoutDeltas'] as int? ?? 128,
      maxStderrDeltas: json['maxStderrDeltas'] as int? ?? 128,
      stdoutTruncated: json['stdoutTruncated'] as bool? ?? false,
      stderrTruncated: json['stderrTruncated'] as bool? ?? false,
      schemaVersion: json['schemaVersion'] as int? ?? 1,
    );
  }

  final String operationId;
  final List<String> argv;
  final String cwd;
  final Map<String, String> redactedEnvironment;
  final DateTime startedAt;
  final List<TaskExecutionOutputDelta> stdoutDeltas;
  final List<TaskExecutionOutputDelta> stderrDeltas;
  final List<TaskExecutionDiagnostic> diagnostics;
  final List<TaskExecutionRuntimeEvent> runtimeEvents;
  final int? exitCode;
  final TaskExecutionCancellation? cancellation;
  final TaskExecutionCleanup? cleanup;
  final int maxStdoutBytes;
  final int maxStderrBytes;
  final int maxStdoutDeltas;
  final int maxStderrDeltas;
  final bool stdoutTruncated;
  final bool stderrTruncated;
  final int schemaVersion;

  bool get active =>
      exitCode == null && cancellation == null && cleanup == null;

  bool get completed => exitCode != null || cancellation != null;

  bool get cleanedUp => cleanup != null;

  TaskExecutionStatus get status {
    if (cleanup != null) {
      return TaskExecutionStatus.cleanedUp;
    }
    if (cancellation != null) {
      return TaskExecutionStatus.cancelled;
    }
    if (exitCode != null) {
      return TaskExecutionStatus.exited;
    }
    return TaskExecutionStatus.running;
  }

  TaskExecutionRuntimeRecord copyWith({
    List<String>? argv,
    String? cwd,
    Map<String, String>? redactedEnvironment,
    DateTime? startedAt,
    List<TaskExecutionOutputDelta>? stdoutDeltas,
    List<TaskExecutionOutputDelta>? stderrDeltas,
    List<TaskExecutionDiagnostic>? diagnostics,
    List<TaskExecutionRuntimeEvent>? runtimeEvents,
    int? exitCode,
    bool clearExitCode = false,
    TaskExecutionCancellation? cancellation,
    bool clearCancellation = false,
    TaskExecutionCleanup? cleanup,
    bool clearCleanup = false,
    int? maxStdoutBytes,
    int? maxStderrBytes,
    int? maxStdoutDeltas,
    int? maxStderrDeltas,
    bool? stdoutTruncated,
    bool? stderrTruncated,
    int? schemaVersion,
  }) {
    return TaskExecutionRuntimeRecord(
      operationId: operationId,
      argv: argv ?? this.argv,
      cwd: cwd ?? this.cwd,
      redactedEnvironment: redactedEnvironment ?? this.redactedEnvironment,
      startedAt: startedAt ?? this.startedAt,
      stdoutDeltas: stdoutDeltas ?? this.stdoutDeltas,
      stderrDeltas: stderrDeltas ?? this.stderrDeltas,
      diagnostics: diagnostics ?? this.diagnostics,
      runtimeEvents: runtimeEvents ?? this.runtimeEvents,
      exitCode: clearExitCode ? null : exitCode ?? this.exitCode,
      cancellation: clearCancellation
          ? null
          : cancellation ?? this.cancellation,
      cleanup: clearCleanup ? null : cleanup ?? this.cleanup,
      maxStdoutBytes: maxStdoutBytes ?? this.maxStdoutBytes,
      maxStderrBytes: maxStderrBytes ?? this.maxStderrBytes,
      maxStdoutDeltas: maxStdoutDeltas ?? this.maxStdoutDeltas,
      maxStderrDeltas: maxStderrDeltas ?? this.maxStderrDeltas,
      stdoutTruncated: stdoutTruncated ?? this.stdoutTruncated,
      stderrTruncated: stderrTruncated ?? this.stderrTruncated,
      schemaVersion: schemaVersion ?? this.schemaVersion,
    );
  }

  TaskExecutionRuntimeRecord recordStdout(
    String chunk, {
    DateTime? timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _recordOutput(
      stream: TaskExecutionStreamKind.stdout,
      chunk: chunk,
      timestamp: timestamp ?? DateTime.now().toUtc(),
      metadata: metadata,
    );
  }

  TaskExecutionRuntimeRecord recordStderr(
    String chunk, {
    DateTime? timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _recordOutput(
      stream: TaskExecutionStreamKind.stderr,
      chunk: chunk,
      timestamp: timestamp ?? DateTime.now().toUtc(),
      metadata: metadata,
    );
  }

  TaskExecutionRuntimeRecord recordDiagnostic(
    TaskExecutionDiagnostic diagnostic,
  ) {
    return copyWith(
      diagnostics: <TaskExecutionDiagnostic>[...diagnostics, diagnostic],
      runtimeEvents: <TaskExecutionRuntimeEvent>[
        ...runtimeEvents,
        TaskExecutionRuntimeEvent(
          sequence: runtimeEvents.length + 1,
          kind: TaskExecutionEventKind.diagnostic,
          message: diagnostic.message,
          timestamp: diagnostic.timestamp,
          metadata: <String, Object?>{
            'severity': diagnostic.severity.wireValue,
            'code': diagnostic.code,
            if (diagnostic.source.isNotEmpty) 'source': diagnostic.source,
            ...diagnostic.metadata,
          },
        ),
      ],
    );
  }

  TaskExecutionRuntimeRecord recordRuntimeEvent(
    TaskExecutionRuntimeEvent event,
  ) {
    return copyWith(
      runtimeEvents: <TaskExecutionRuntimeEvent>[...runtimeEvents, event],
    );
  }

  TaskExecutionRuntimeRecord recordExit({
    required int exitCode,
    DateTime? timestamp,
    String message = '',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final exitTimestamp = timestamp ?? DateTime.now().toUtc();
    return copyWith(
      exitCode: exitCode,
      runtimeEvents: <TaskExecutionRuntimeEvent>[
        ...runtimeEvents,
        TaskExecutionRuntimeEvent(
          sequence: runtimeEvents.length + 1,
          kind: TaskExecutionEventKind.exit,
          message: message.isEmpty
              ? 'Task $operationId exited with code $exitCode.'
              : message,
          timestamp: exitTimestamp,
          metadata: <String, Object?>{'exitCode': exitCode, ...metadata},
        ),
      ],
    );
  }

  TaskExecutionRuntimeRecord recordCancellation({
    required String reason,
    DateTime? timestamp,
    bool forced = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final cancellationTimestamp = timestamp ?? DateTime.now().toUtc();
    final nextCancellation = TaskExecutionCancellation(
      reason: reason,
      requestedAt: cancellationTimestamp,
      forced: forced,
      metadata: metadata,
    );
    return copyWith(
      cancellation: nextCancellation,
      runtimeEvents: <TaskExecutionRuntimeEvent>[
        ...runtimeEvents,
        TaskExecutionRuntimeEvent(
          sequence: runtimeEvents.length + 1,
          kind: TaskExecutionEventKind.cancelled,
          message: reason,
          timestamp: cancellationTimestamp,
          metadata: <String, Object?>{'forced': forced, ...metadata},
        ),
      ],
    );
  }

  TaskExecutionRuntimeRecord recordCleanup({
    required String message,
    DateTime? timestamp,
    bool succeeded = true,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final cleanupTimestamp = timestamp ?? DateTime.now().toUtc();
    final nextCleanup = TaskExecutionCleanup(
      completedAt: cleanupTimestamp,
      message: message,
      succeeded: succeeded,
      metadata: metadata,
    );
    return copyWith(
      cleanup: nextCleanup,
      runtimeEvents: <TaskExecutionRuntimeEvent>[
        ...runtimeEvents,
        TaskExecutionRuntimeEvent(
          sequence: runtimeEvents.length + 1,
          kind: TaskExecutionEventKind.cleanup,
          message: message,
          timestamp: cleanupTimestamp,
          metadata: <String, Object?>{'succeeded': succeeded, ...metadata},
        ),
      ],
    );
  }

  RuntimeTaskSnapshot toRuntimeTaskSnapshot({
    String taskId = '',
    String label = '',
    RuntimeTaskKind kind = RuntimeTaskKind.shell,
  }) {
    final effectiveTaskId = taskId.isNotEmpty ? taskId : operationId;
    return RuntimeTaskSnapshot(
      definition: RuntimeTaskDefinition(
        id: effectiveTaskId,
        label: label.isNotEmpty ? label : effectiveTaskId,
        kind: kind,
        command: argv.isEmpty ? '' : argv.first,
        arguments: argv.length > 1 ? argv.sublist(1) : const <String>[],
        workingDirectory: cwd == '.' ? null : cwd,
        environment: redactedEnvironment,
        metadata: <String, Object?>{
          'operationId': operationId,
          'stdoutTruncated': stdoutTruncated,
          'stderrTruncated': stderrTruncated,
          'runtimeEventCount': runtimeEvents.length,
        },
      ),
      status: _runtimeTaskStatusForRecord(this),
      statusMessage: _statusMessage,
      startedAt: startedAt,
      finishedAt:
          cleanup?.completedAt ?? cancellation?.requestedAt ?? _exitTimestamp,
      exitCode: exitCode,
      events: _runtimeTaskEvents(),
    );
  }

  DateTime? get _exitTimestamp {
    if (runtimeEvents.isEmpty) {
      return null;
    }
    for (var index = runtimeEvents.length - 1; index >= 0; index -= 1) {
      final event = runtimeEvents[index];
      if (event.kind == TaskExecutionEventKind.exit ||
          event.kind == TaskExecutionEventKind.cancelled ||
          event.kind == TaskExecutionEventKind.cleanup) {
        return event.timestamp;
      }
    }
    return null;
  }

  String get _statusMessage {
    if (cleanup != null) {
      return cleanup!.message;
    }
    if (cancellation != null) {
      return cancellation!.reason;
    }
    if (exitCode != null) {
      return 'Task $operationId exited with code $exitCode.';
    }
    return 'Task $operationId is running.';
  }

  List<RuntimeTaskLifecycleEvent> _runtimeTaskEvents() {
    return <RuntimeTaskLifecycleEvent>[
      for (final event in runtimeEvents)
        RuntimeTaskLifecycleEvent(
          taskId: operationId,
          sequence: event.sequence,
          status: _runtimeTaskStatusForEvent(event),
          timestamp: event.timestamp,
          message: event.message,
          metadata: event.metadata,
          exitCode: event.kind == TaskExecutionEventKind.exit
              ? event.metadata['exitCode'] as int?
              : null,
        ),
    ];
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'operationId': operationId,
      'argv': argv,
      'cwd': cwd,
      'redactedEnvironment': redactedEnvironment,
      'startedAt': startedAt.toIso8601String(),
      'status': status.wireValue,
      'stdoutDeltaCount': stdoutDeltas.length,
      'stderrDeltaCount': stderrDeltas.length,
      'diagnosticCount': diagnostics.length,
      'runtimeEventCount': runtimeEvents.length,
      'stdoutTruncated': stdoutTruncated,
      'stderrTruncated': stderrTruncated,
      'maxStdoutBytes': maxStdoutBytes,
      'maxStderrBytes': maxStderrBytes,
      'maxStdoutDeltas': maxStdoutDeltas,
      'maxStderrDeltas': maxStderrDeltas,
      if (stdoutDeltas.isNotEmpty)
        'stdoutDeltas': stdoutDeltas
            .map((delta) => delta.toJson())
            .toList(growable: false),
      if (stderrDeltas.isNotEmpty)
        'stderrDeltas': stderrDeltas
            .map((delta) => delta.toJson())
            .toList(growable: false),
      if (diagnostics.isNotEmpty)
        'diagnostics': diagnostics
            .map((diagnostic) => diagnostic.toJson())
            .toList(growable: false),
      if (runtimeEvents.isNotEmpty)
        'runtimeEvents': runtimeEvents
            .map((event) => event.toJson())
            .toList(growable: false),
      if (exitCode != null) 'exitCode': exitCode,
      if (cancellation != null) 'cancellation': cancellation!.toJson(),
      if (cleanup != null) 'cleanup': cleanup!.toJson(),
    };
  }

  TaskExecutionRuntimeRecord _recordOutput({
    required TaskExecutionStreamKind stream,
    required String chunk,
    required DateTime timestamp,
    required Map<String, Object?> metadata,
  }) {
    final normalizedChunk = chunk
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n');
    final capped = _capChunk(
      normalizedChunk,
      maxBytes: stream == TaskExecutionStreamKind.stdout
          ? maxStdoutBytes
          : maxStderrBytes,
    );
    final nextDelta = TaskExecutionOutputDelta(
      sequence: runtimeEvents.length + 1,
      stream: stream,
      timestamp: timestamp,
      text: capped.value,
      byteCount: capped.byteCount,
      truncated: capped.truncated,
    );
    final nextDeltas = <TaskExecutionOutputDelta>[
      ...(stream == TaskExecutionStreamKind.stdout
          ? stdoutDeltas
          : stderrDeltas),
      nextDelta,
    ];
    final cappedDeltas = _capDeltas(
      nextDeltas,
      maxDeltas: stream == TaskExecutionStreamKind.stdout
          ? maxStdoutDeltas
          : maxStderrDeltas,
    );
    final runtimeEvent = TaskExecutionRuntimeEvent(
      sequence: nextDelta.sequence,
      kind: stream == TaskExecutionStreamKind.stdout
          ? TaskExecutionEventKind.stdoutDelta
          : TaskExecutionEventKind.stderrDelta,
      message: capped.value,
      timestamp: timestamp,
      metadata: <String, Object?>{
        'stream': stream.wireValue,
        'byteCount': capped.byteCount,
        'truncated': capped.truncated,
        ...metadata,
      },
    );
    return copyWith(
      stdoutDeltas: stream == TaskExecutionStreamKind.stdout
          ? cappedDeltas
          : stdoutDeltas,
      stderrDeltas: stream == TaskExecutionStreamKind.stderr
          ? cappedDeltas
          : stderrDeltas,
      stdoutTruncated: stream == TaskExecutionStreamKind.stdout
          ? stdoutTruncated ||
                capped.truncated ||
                cappedDeltas.length < nextDeltas.length
          : stdoutTruncated,
      stderrTruncated: stream == TaskExecutionStreamKind.stderr
          ? stderrTruncated ||
                capped.truncated ||
                cappedDeltas.length < nextDeltas.length
          : stderrTruncated,
      runtimeEvents: <TaskExecutionRuntimeEvent>[
        ...runtimeEvents,
        runtimeEvent,
      ],
    );
  }
}

class TaskExecutionRuntime {
  TaskExecutionRuntime({
    this.redactionPolicy = const EnvironmentVariableRedactionPolicy(),
    this.stdoutCapBytes = 64 * 1024,
    this.stderrCapBytes = 64 * 1024,
    this.stdoutCapDeltas = 128,
    this.stderrCapDeltas = 128,
    RuntimeTaskClock? clock,
  }) : _clock = clock ?? DateTime.now().toUtc;

  final EnvironmentVariableRedactionPolicy redactionPolicy;
  final int stdoutCapBytes;
  final int stderrCapBytes;
  final int stdoutCapDeltas;
  final int stderrCapDeltas;
  final RuntimeTaskClock _clock;
  TaskExecutionRuntimeRecord? _record;

  TaskExecutionRuntimeRecord? get record => _record;

  bool get active => _record?.active ?? false;

  TaskExecutionRuntimeRecord startFromProcessRequest({
    required String operationId,
    required ProcessCommandRequest request,
  }) {
    return start(
      TaskExecutionRuntimeRecord.fromProcessRequest(
        operationId: operationId,
        request: request,
        redactionPolicy: redactionPolicy,
        startedAt: _clock(),
        maxStdoutBytes: stdoutCapBytes,
        maxStderrBytes: stderrCapBytes,
        maxStdoutDeltas: stdoutCapDeltas,
        maxStderrDeltas: stderrCapDeltas,
      ),
    );
  }

  TaskExecutionRuntimeRecord startFromPtyRequest({
    required String operationId,
    required PtySessionRequest request,
  }) {
    return start(
      TaskExecutionRuntimeRecord.fromPtyRequest(
        operationId: operationId,
        request: request,
        redactionPolicy: redactionPolicy,
        startedAt: _clock(),
        maxStdoutBytes: stdoutCapBytes,
        maxStderrBytes: stderrCapBytes,
        maxStdoutDeltas: stdoutCapDeltas,
        maxStderrDeltas: stderrCapDeltas,
      ),
    );
  }

  TaskExecutionRuntimeRecord start(TaskExecutionRuntimeRecord record) {
    _record = record;
    return record;
  }

  TaskExecutionRuntimeRecord stdout(
    String chunk, {
    DateTime? timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _apply(
      (record) => record.recordStdout(
        chunk,
        timestamp: timestamp ?? _clock(),
        metadata: metadata,
      ),
    );
  }

  TaskExecutionRuntimeRecord stderr(
    String chunk, {
    DateTime? timestamp,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _apply(
      (record) => record.recordStderr(
        chunk,
        timestamp: timestamp ?? _clock(),
        metadata: metadata,
      ),
    );
  }

  TaskExecutionRuntimeRecord diagnostic(
    String code,
    String message, {
    TaskExecutionDiagnosticSeverity severity =
        TaskExecutionDiagnosticSeverity.info,
    String source = '',
    Map<String, Object?> metadata = const <String, Object?>{},
    DateTime? timestamp,
  }) {
    return _apply(
      (record) => record.recordDiagnostic(
        TaskExecutionDiagnostic(
          sequence: record.runtimeEvents.length + 1,
          severity: severity,
          code: code,
          message: message,
          timestamp: timestamp ?? _clock(),
          source: source,
          metadata: metadata,
        ),
      ),
    );
  }

  TaskExecutionRuntimeRecord runtimeEvent(
    String message, {
    TaskExecutionEventKind kind = TaskExecutionEventKind.runtimeEvent,
    Map<String, Object?> metadata = const <String, Object?>{},
    DateTime? timestamp,
  }) {
    return _apply(
      (record) => record.recordRuntimeEvent(
        TaskExecutionRuntimeEvent(
          sequence: record.runtimeEvents.length + 1,
          kind: kind,
          message: message,
          timestamp: timestamp ?? _clock(),
          metadata: metadata,
        ),
      ),
    );
  }

  TaskExecutionRuntimeRecord complete({int exitCode = 0, String? message}) {
    return _apply(
      (record) => record.recordExit(
        exitCode: exitCode,
        timestamp: _clock(),
        message: message ?? '',
      ),
    );
  }

  TaskExecutionRuntimeRecord cancel({
    required String reason,
    bool forced = false,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _apply(
      (record) => record.recordCancellation(
        reason: reason,
        timestamp: _clock(),
        forced: forced,
        metadata: metadata,
      ),
    );
  }

  TaskExecutionRuntimeRecord cleanup({
    required String message,
    bool succeeded = true,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return _apply(
      (record) => record.recordCleanup(
        message: message,
        timestamp: _clock(),
        succeeded: succeeded,
        metadata: metadata,
      ),
    );
  }

  TaskExecutionRuntimeRecord snapshot() {
    final record = _record;
    if (record == null) {
      throw StateError('Task execution runtime has not been started.');
    }
    return record;
  }

  TaskExecutionRuntimeRecord _apply(
    TaskExecutionRuntimeRecord Function(TaskExecutionRuntimeRecord record)
    transform,
  ) {
    final current = _record;
    if (current == null) {
      throw StateError('Task execution runtime has not been started.');
    }
    final next = transform(current);
    _record = next;
    return next;
  }
}

TaskExecutionStreamKind? _taskExecutionStreamKindFromWire(String value) {
  return switch (value) {
    'stdout' => TaskExecutionStreamKind.stdout,
    'stderr' => TaskExecutionStreamKind.stderr,
    _ => null,
  };
}

TaskExecutionEventKind? _taskExecutionEventKindFromWire(String value) {
  return switch (value) {
    'started' => TaskExecutionEventKind.started,
    'stdout-delta' => TaskExecutionEventKind.stdoutDelta,
    'stderr-delta' => TaskExecutionEventKind.stderrDelta,
    'diagnostic' => TaskExecutionEventKind.diagnostic,
    'runtime-event' => TaskExecutionEventKind.runtimeEvent,
    'exit' => TaskExecutionEventKind.exit,
    'cancelled' => TaskExecutionEventKind.cancelled,
    'cleanup' => TaskExecutionEventKind.cleanup,
    _ => null,
  };
}

TaskExecutionDiagnosticSeverity? _taskExecutionDiagnosticSeverityFromWire(
  String value,
) {
  return switch (value) {
    'info' => TaskExecutionDiagnosticSeverity.info,
    'warning' => TaskExecutionDiagnosticSeverity.warning,
    'error' => TaskExecutionDiagnosticSeverity.error,
    _ => null,
  };
}

RuntimeTaskStatus _runtimeTaskStatusForRecord(
  TaskExecutionRuntimeRecord record,
) {
  if (record.cancellation != null) {
    return RuntimeTaskStatus.cancelled;
  }
  final exitCode = record.exitCode;
  if (exitCode != null) {
    return exitCode == 0
        ? RuntimeTaskStatus.succeeded
        : RuntimeTaskStatus.failed;
  }
  return RuntimeTaskStatus.running;
}

RuntimeTaskStatus _runtimeTaskStatusForEvent(TaskExecutionRuntimeEvent event) {
  return switch (event.kind) {
    TaskExecutionEventKind.started ||
    TaskExecutionEventKind.stdoutDelta ||
    TaskExecutionEventKind.stderrDelta ||
    TaskExecutionEventKind.diagnostic ||
    TaskExecutionEventKind.runtimeEvent => RuntimeTaskStatus.running,
    TaskExecutionEventKind.exit =>
      event.metadata['exitCode'] == 0
          ? RuntimeTaskStatus.succeeded
          : RuntimeTaskStatus.failed,
    TaskExecutionEventKind.cancelled => RuntimeTaskStatus.cancelled,
    TaskExecutionEventKind.cleanup => RuntimeTaskStatus.succeeded,
  };
}

_CappedChunk _capChunk(String text, {required int maxBytes}) {
  final bytes = utf8.encode(text);
  if (bytes.length <= maxBytes) {
    return _CappedChunk(value: text, byteCount: bytes.length, truncated: false);
  }
  return _CappedChunk(
    value: utf8.decode(bytes.take(maxBytes).toList(), allowMalformed: true),
    byteCount: maxBytes,
    truncated: true,
  );
}

List<TaskExecutionOutputDelta> _capDeltas(
  List<TaskExecutionOutputDelta> deltas, {
  required int maxDeltas,
}) {
  if (maxDeltas <= 0 || deltas.length <= maxDeltas) {
    return List<TaskExecutionOutputDelta>.unmodifiable(deltas);
  }
  return List<TaskExecutionOutputDelta>.unmodifiable(
    deltas.sublist(deltas.length - maxDeltas),
  );
}

class _CappedChunk {
  const _CappedChunk({
    required this.value,
    required this.byteCount,
    required this.truncated,
  });

  final String value;
  final int byteCount;
  final bool truncated;
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

List<TaskExecutionOutputDelta> _jsonOutputDeltas(Object? value) {
  if (value is! List) {
    return const <TaskExecutionOutputDelta>[];
  }
  return value
      .whereType<Map>()
      .map(
        (delta) => TaskExecutionOutputDelta.fromJson(
          delta.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}

List<TaskExecutionDiagnostic> _jsonDiagnostics(Object? value) {
  if (value is! List) {
    return const <TaskExecutionDiagnostic>[];
  }
  return value
      .whereType<Map>()
      .map(
        (diagnostic) => TaskExecutionDiagnostic.fromJson(
          diagnostic.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}

List<TaskExecutionRuntimeEvent> _jsonRuntimeEvents(Object? value) {
  if (value is! List) {
    return const <TaskExecutionRuntimeEvent>[];
  }
  return value
      .whereType<Map>()
      .map(
        (event) => TaskExecutionRuntimeEvent.fromJson(
          event.map(
            (key, value) => MapEntry<String, Object?>(key.toString(), value),
          ),
        ),
      )
      .toList(growable: false);
}
