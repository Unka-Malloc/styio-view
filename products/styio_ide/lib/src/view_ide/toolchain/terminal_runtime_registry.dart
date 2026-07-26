import 'dart:async';

import '../environment/configuration/environment_variable_configuration.dart';
import '../environment/system_compatibility/pty/pty_manager.dart';
import '../runtime/runtime_task_lifecycle.dart';
import '../runtime/task_execution_runtime.dart';

enum TerminalRuntimeRestoreMode { resume, replay, blocked }

extension TerminalRuntimeRestoreModeX on TerminalRuntimeRestoreMode {
  String get wireValue => switch (this) {
    TerminalRuntimeRestoreMode.resume => 'resume',
    TerminalRuntimeRestoreMode.replay => 'replay',
    TerminalRuntimeRestoreMode.blocked => 'blocked',
  };
}

class TerminalRuntimeRestorePlan {
  const TerminalRuntimeRestorePlan({
    required this.sessionId,
    required this.mode,
    required this.safeToRestore,
    required this.requiresConfirmation,
    required this.message,
    required this.outputTruncated,
    required this.record,
  });

  final String sessionId;
  final TerminalRuntimeRestoreMode mode;
  final bool safeToRestore;
  final bool requiresConfirmation;
  final String message;
  final bool outputTruncated;
  final TaskExecutionRuntimeRecord record;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sessionId': sessionId,
      'mode': mode.wireValue,
      'safeToRestore': safeToRestore,
      'requiresConfirmation': requiresConfirmation,
      'message': message,
      'outputTruncated': outputTruncated,
      'record': record.toJson(),
    };
  }
}

class TerminalRuntimeRegistrySessionSnapshot {
  const TerminalRuntimeRegistrySessionSnapshot({
    required this.sessionId,
    required this.operationId,
    required this.request,
    required this.state,
    required this.record,
    required this.startedAt,
    this.updatedAt,
    this.lastResize,
    this.lastSignal,
    this.cleanedUp = false,
    this.exitCode,
  });

  final String sessionId;
  final String operationId;
  final PtySessionRequest request;
  final PtySessionState state;
  final TaskExecutionRuntimeRecord record;
  final DateTime startedAt;
  final DateTime? updatedAt;
  final PtyResizeResult? lastResize;
  final PtySignalResult? lastSignal;
  final bool cleanedUp;
  final int? exitCode;

  bool get active =>
      state == PtySessionState.starting || state == PtySessionState.running;

  bool get outputTruncated => record.stdoutTruncated || record.stderrTruncated;

  TerminalRuntimeRestorePlan restorePlan() {
    if (state == PtySessionState.running || state == PtySessionState.starting) {
      final requiresConfirmation =
          outputTruncated ||
          record.cancellation != null ||
          state == PtySessionState.failed ||
          state == PtySessionState.unsupported;
      return TerminalRuntimeRestorePlan(
        sessionId: sessionId,
        mode: requiresConfirmation
            ? TerminalRuntimeRestoreMode.blocked
            : TerminalRuntimeRestoreMode.resume,
        safeToRestore: !requiresConfirmation,
        requiresConfirmation: requiresConfirmation,
        message: requiresConfirmation
            ? 'Terminal session is active but restore needs review.'
            : 'Terminal session can be resumed safely.',
        outputTruncated: outputTruncated,
        record: record,
      );
    }
    final requiresConfirmation =
        outputTruncated ||
        record.cancellation != null ||
        state == PtySessionState.failed ||
        state == PtySessionState.unsupported;
    if (requiresConfirmation) {
      return TerminalRuntimeRestorePlan(
        sessionId: sessionId,
        mode: TerminalRuntimeRestoreMode.blocked,
        safeToRestore: false,
        requiresConfirmation: true,
        message: record.cancellation != null
            ? 'Terminal session was cancelled and should not be restored automatically.'
            : 'Terminal session output was truncated or the backend failed; restore needs review.',
        outputTruncated: outputTruncated,
        record: record,
      );
    }
    return TerminalRuntimeRestorePlan(
      sessionId: sessionId,
      mode: TerminalRuntimeRestoreMode.replay,
      safeToRestore: true,
      requiresConfirmation: false,
      message: cleanedUp
          ? 'Terminal session was cleaned up and can be replayed from history.'
          : 'Terminal session can be replayed from history.',
      outputTruncated: outputTruncated,
      record: record,
    );
  }

  Map<String, Object?> toJson() {
    final restorePlan = this.restorePlan();
    return <String, Object?>{
      'sessionId': sessionId,
      'operationId': operationId,
      'state': state.name,
      'startedAt': startedAt.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
      'cleanedUp': cleanedUp,
      'outputTruncated': outputTruncated,
      'record': record.toJson(),
      if (lastResize != null)
        'lastResize': <String, Object?>{
          'status': lastResize!.status.name,
          'rows': lastResize!.rows,
          'cols': lastResize!.cols,
          if (lastResize!.message != null) 'message': lastResize!.message,
        },
      if (lastSignal != null)
        'lastSignal': <String, Object?>{
          'signal': lastSignal!.signal.name,
          'status': lastSignal!.status.name,
          if (lastSignal!.message != null) 'message': lastSignal!.message,
        },
      'restorePlan': restorePlan.toJson(),
    };
  }
}

class TerminalRuntimeRegistry {
  TerminalRuntimeRegistry({
    required PtyManager ptyManager,
    EnvironmentVariableRedactionPolicy redactionPolicy =
        const EnvironmentVariableRedactionPolicy(),
    RuntimeTaskClock? clock,
    this.stdoutCapBytes = 64 * 1024,
    this.stdoutCapDeltas = 128,
  }) : _ptyManager = ptyManager,
       _clock = clock ?? DateTime.now().toUtc,
       _redactionPolicy = redactionPolicy;

  final PtyManager _ptyManager;
  final EnvironmentVariableRedactionPolicy _redactionPolicy;
  final RuntimeTaskClock _clock;
  final int stdoutCapBytes;
  final int stdoutCapDeltas;
  final Map<String, _TerminalRuntimeRegistryEntry> _entries =
      <String, _TerminalRuntimeRegistryEntry>{};

  List<TerminalRuntimeRegistrySessionSnapshot> list() {
    final snapshots = _entries.values.map((entry) => entry.snapshot()).toList();
    snapshots.sort((left, right) {
      final comparison = right.startedAt.compareTo(left.startedAt);
      if (comparison != 0) {
        return comparison;
      }
      return left.sessionId.compareTo(right.sessionId);
    });
    return snapshots;
  }

  TerminalRuntimeRegistrySessionSnapshot? snapshotFor(String sessionId) {
    final entry = _entries[sessionId];
    return entry?.snapshot();
  }

  Future<TerminalRuntimeRegistrySessionSnapshot> start({
    required String operationId,
    required PtySessionRequest request,
    String? sessionId,
  }) async {
    final effectiveSessionId =
        sessionId ?? 'terminal.$operationId.${_clock().microsecondsSinceEpoch}';
    if (_entries.containsKey(effectiveSessionId)) {
      throw StateError('Terminal session $effectiveSessionId already exists.');
    }
    final runtime = TaskExecutionRuntime(
      redactionPolicy: _redactionPolicy,
      stdoutCapBytes: stdoutCapBytes,
      stdoutCapDeltas: stdoutCapDeltas,
      stderrCapBytes: 0,
      stderrCapDeltas: 0,
      clock: _clock,
    );
    runtime.startFromPtyRequest(operationId: operationId, request: request);
    final session = await _ptyManager.start(request);
    final entry = _TerminalRuntimeRegistryEntry(
      sessionId: effectiveSessionId,
      operationId: operationId,
      request: request,
      runtime: runtime,
      session: session,
      startedAt: _clock(),
    );
    _entries[effectiveSessionId] = entry;
    entry.attach(
      onChunk: (chunk) {
        runtime.stdout(
          chunk,
          timestamp: _clock(),
          metadata: <String, Object?>{
            'sessionId': effectiveSessionId,
            'operationId': operationId,
          },
        );
        entry.touch();
      },
      onExit: (exitCode) {
        if (runtime.record?.cancellation != null ||
            runtime.record?.exitCode != null) {
          return;
        }
        if (exitCode != null) {
          runtime.complete(exitCode: exitCode);
        }
        entry.exitCode = exitCode;
        entry.state = exitCode == null
            ? entry.state
            : exitCode == 0
            ? PtySessionState.exited
            : PtySessionState.failed;
        entry.touch();
      },
    );
    runtime.runtimeEvent(
      'Terminal session started.',
      metadata: <String, Object?>{
        'sessionId': effectiveSessionId,
        'executablePath': request.executablePath,
        'rows': request.rows,
        'cols': request.cols,
      },
    );
    return entry.snapshot();
  }

  Future<TerminalRuntimeRegistrySessionSnapshot?> write({
    required String sessionId,
    required String input,
  }) async {
    final entry = _entries[sessionId];
    if (entry == null) {
      return null;
    }
    final session = entry.session;
    if (session == null || entry.cleanedUp) {
      entry.runtime.runtimeEvent(
        'Terminal input ignored because the session is closed.',
        metadata: <String, Object?>{
          'sessionId': sessionId,
          'inputLength': input.length,
          'blocked': true,
        },
      );
      entry.touch();
      return entry.snapshot();
    }
    if (input.isNotEmpty) {
      await session.write(input);
      entry.runtime.runtimeEvent(
        'Terminal input written.',
        metadata: <String, Object?>{
          'sessionId': sessionId,
          'inputLength': input.length,
        },
      );
      entry.touch();
    }
    return entry.snapshot();
  }

  Future<PtyResizeResult?> resize({
    required String sessionId,
    required int rows,
    required int cols,
  }) async {
    final entry = _entries[sessionId];
    if (entry == null) {
      return null;
    }
    final session = entry.session;
    if (session == null || entry.cleanedUp) {
      entry.runtime.runtimeEvent(
        'Terminal resize ignored because the session is closed.',
        metadata: <String, Object?>{
          'sessionId': sessionId,
          'rows': rows,
          'cols': cols,
          'blocked': true,
        },
      );
      entry.touch();
      return entry.lastResize;
    }
    final result = await session.resize(rows: rows, cols: cols);
    entry.lastResize = result;
    entry.runtime.runtimeEvent(
      'Terminal resize ${result.status.name}.',
      metadata: <String, Object?>{
        'sessionId': sessionId,
        'rows': rows,
        'cols': cols,
        'status': result.status.name,
        if (result.message != null) 'message': result.message,
      },
    );
    entry.touch();
    return result;
  }

  Future<int?> kill({
    required String sessionId,
    String reason = 'Terminal session killed.',
  }) async {
    final entry = _entries[sessionId];
    if (entry == null) {
      return null;
    }
    final session = entry.session;
    if (session == null) {
      entry.runtime.cancel(reason: reason, forced: true);
      entry.touch();
      return entry.exitCode;
    }
    final signalResult = await session.sendSignal(PtySignal.kill);
    entry.lastSignal = signalResult;
    entry.runtime.cancel(
      reason: reason,
      forced: true,
      metadata: <String, Object?>{
        'signal': signalResult.signal.name,
        'signalStatus': signalResult.status.name,
        if (signalResult.message != null) 'message': signalResult.message,
      },
    );
    final exitCode = await session.close(force: true);
    entry.exitCode = exitCode;
    entry.state = exitCode == null
        ? PtySessionState.closed
        : exitCode == 0
        ? PtySessionState.exited
        : PtySessionState.failed;
    entry.session = null;
    await entry.outputSubscription?.cancel();
    entry.outputSubscription = null;
    entry.cleanedUp = true;
    entry.runtime.cleanup(message: reason, succeeded: exitCode == 0);
    entry.touch();
    return exitCode;
  }

  Future<TerminalRuntimeRegistrySessionSnapshot?> cleanup({
    required String sessionId,
    bool force = false,
    String message = 'Terminal session cleaned up.',
  }) async {
    final entry = _entries[sessionId];
    if (entry == null) {
      return null;
    }
    if (entry.cleanedUp) {
      return entry.snapshot();
    }
    final session = entry.session;
    if (session != null) {
      final exitCode = await session.close(force: force);
      entry.exitCode = exitCode;
      entry.state = exitCode == null
          ? PtySessionState.closed
          : exitCode == 0
          ? PtySessionState.exited
          : PtySessionState.failed;
    }
    entry.session = null;
    await entry.outputSubscription?.cancel();
    entry.outputSubscription = null;
    entry.cleanedUp = true;
    entry.runtime.cleanup(
      message: message,
      succeeded: entry.exitCode == null || entry.exitCode == 0,
    );
    entry.runtime.runtimeEvent(
      message,
      metadata: <String, Object?>{'sessionId': sessionId, 'force': force},
    );
    entry.touch();
    return entry.snapshot();
  }

  TerminalRuntimeRestorePlan restorePlan(String sessionId) {
    final snapshot = snapshotFor(sessionId);
    if (snapshot == null) {
      return TerminalRuntimeRestorePlan(
        sessionId: sessionId,
        mode: TerminalRuntimeRestoreMode.blocked,
        safeToRestore: false,
        requiresConfirmation: true,
        message: 'Terminal session $sessionId is unknown.',
        outputTruncated: false,
        record: TaskExecutionRuntimeRecord(
          operationId: sessionId,
          argv: const <String>[],
          cwd: '.',
          redactedEnvironment: const <String, String>{},
          startedAt: _clock(),
        ),
      );
    }
    return snapshot.restorePlan();
  }

  Future<void> dispose() async {
    final snapshots = list();
    for (final snapshot in snapshots) {
      await cleanup(sessionId: snapshot.sessionId, force: true);
    }
  }
}

class _TerminalRuntimeRegistryEntry {
  _TerminalRuntimeRegistryEntry({
    required this.sessionId,
    required this.operationId,
    required this.request,
    required this.runtime,
    required this.session,
    required this.startedAt,
  });

  final String sessionId;
  final String operationId;
  final PtySessionRequest request;
  final TaskExecutionRuntime runtime;
  PtySession? session;
  StreamSubscription<String>? outputSubscription;
  PtyResizeResult? lastResize;
  PtySignalResult? lastSignal;
  int? exitCode;
  bool cleanedUp = false;
  PtySessionState state = PtySessionState.starting;
  final DateTime startedAt;
  DateTime? updatedAt;

  void attach({
    required void Function(String chunk) onChunk,
    required void Function(int? exitCode) onExit,
  }) {
    state = PtySessionState.running;
    outputSubscription = session?.output.listen(
      onChunk,
      onError: (Object error, StackTrace stackTrace) {
        runtime.runtimeEvent(
          'Terminal output stream failed.',
          metadata: <String, Object?>{
            'sessionId': sessionId,
            'error': error.toString(),
          },
        );
      },
      onDone: () {
        runtime.runtimeEvent(
          'Terminal output stream closed.',
          metadata: <String, Object?>{'sessionId': sessionId},
        );
      },
    );
    unawaited(
      session?.exitCode.then((value) {
        onExit(value);
      }),
    );
  }

  void touch() {
    updatedAt = DateTime.now().toUtc();
  }

  TerminalRuntimeRegistrySessionSnapshot snapshot() {
    return TerminalRuntimeRegistrySessionSnapshot(
      sessionId: sessionId,
      operationId: operationId,
      request: request,
      state: state,
      record: runtime.snapshot(),
      startedAt: startedAt,
      updatedAt: updatedAt,
      lastResize: lastResize,
      lastSignal: lastSignal,
      cleanedUp: cleanedUp,
      exitCode: exitCode,
    );
  }
}
