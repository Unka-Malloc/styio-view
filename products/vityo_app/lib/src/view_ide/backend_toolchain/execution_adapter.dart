import '../../ide/editor/document_state.dart';
import '../language/language_contract.dart';
import '../platform/platform_target.dart';
import '../services/observable_topology/observable_runtime_model.dart';
import '../services/observable_topology/observable_snapshot_model.dart';
import 'adapter_contracts.dart';
import 'project_graph_contract.dart';

enum ExecutionSessionStatus { blocked, running, succeeded, failed }

class ExecutionReceiptSnapshot {
  const ExecutionReceiptSnapshot({
    required this.schemaVersion,
    required this.intent,
    required this.sessionId,
    required this.executed,
    this.phases = const <String>[],
    this.artifacts = const <String>[],
  });

  final int schemaVersion;
  final String intent;
  final String sessionId;
  final bool executed;
  final List<String> phases;
  final List<String> artifacts;

  static ExecutionReceiptSnapshot? decode(
    Object? payload, {
    required String fallbackSessionId,
  }) {
    if (payload is! Map) return null;
    final schemaValue = payload['schema_version'] ?? payload['schemaVersion'];
    final schemaVersion = schemaValue is int
        ? schemaValue
        : int.tryParse('$schemaValue');
    final intentValue = payload['intent'];
    final executedValue = payload['executed'];
    if (schemaVersion != 1 ||
        intentValue is! String ||
        intentValue.trim().isEmpty ||
        executedValue is! bool) {
      return null;
    }
    final sessionValue = payload['session_id'] ?? payload['sessionId'];
    List<String> strings(Object? value) => value is List
        ? value
              .whereType<String>()
              .map((item) => item.trim())
              .where((item) => item.isNotEmpty)
              .toList(growable: false)
        : const <String>[];
    return ExecutionReceiptSnapshot(
      schemaVersion: 1,
      intent: intentValue.trim(),
      sessionId: sessionValue is String && sessionValue.trim().isNotEmpty
          ? sessionValue.trim()
          : fallbackSessionId,
      executed: executedValue,
      phases: strings(payload['phases']),
      artifacts: strings(payload['artifacts']),
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'intent': intent,
    'sessionId': sessionId,
    'executed': executed,
    'phases': phases,
    'artifacts': artifacts,
  };
}

class ExecutionLogEvent {
  const ExecutionLogEvent({required this.message});

  final String message;

  Map<String, Object?> toJson() {
    return <String, Object?>{'message': message};
  }
}

class ExecutionSession {
  const ExecutionSession({
    required this.sessionId,
    required this.kind,
    required this.status,
    required this.statusMessage,
    required this.diagnostics,
    required this.stdoutEvents,
    required this.stderrEvents,
    this.unitRange,
    this.receipt,
  });

  final String sessionId;
  final String kind;
  final ExecutionSessionStatus status;
  final String statusMessage;
  final SourceRange? unitRange;
  final List<Diagnostic> diagnostics;
  final List<ExecutionLogEvent> stdoutEvents;
  final List<ExecutionLogEvent> stderrEvents;
  final ExecutionReceiptSnapshot? receipt;

  ExecutionResultContract toResultContract({
    String source = 'execution-session',
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    return ExecutionResultContract(
      source: source,
      id: sessionId,
      kind: kind,
      status: status.name,
      message: statusMessage,
      diagnosticCount: diagnostics.length,
      stdoutCount: stdoutEvents.length,
      stderrCount: stderrEvents.length,
      metadata: <String, Object?>{
        ...metadata,
        if (receipt != null) 'receipt': receipt!.toJson(),
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sessionId': sessionId,
      'kind': kind,
      'status': status.name,
      'statusMessage': statusMessage,
      if (unitRange != null)
        'unitRange': <String, int>{
          'start': unitRange!.start,
          'end': unitRange!.end,
        },
      'diagnosticCount': diagnostics.length,
      'stdoutCount': stdoutEvents.length,
      'stderrCount': stderrEvents.length,
      if (stdoutEvents.isNotEmpty)
        'stdout': stdoutEvents.map((event) => event.toJson()).toList(),
      if (stderrEvents.isNotEmpty)
        'stderr': stderrEvents.map((event) => event.toJson()).toList(),
      if (receipt != null) 'receipt': receipt!.toJson(),
    };
  }
}

class RuntimeEventEnvelope {
  const RuntimeEventEnvelope({
    required this.schemaVersion,
    required this.sessionId,
    required this.sequence,
    required this.timestamp,
    required this.eventKind,
    required this.origin,
    required this.payload,
  });

  final int schemaVersion;
  final String sessionId;
  final int sequence;
  final DateTime timestamp;
  final String eventKind;
  final String origin;
  final Map<String, Object?> payload;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'sessionId': sessionId,
      'sequence': sequence,
      'timestamp': timestamp.toIso8601String(),
      'eventKind': eventKind,
      'origin': origin,
      'payload': payload,
    };
  }
}

class ExecutionResultContract {
  const ExecutionResultContract({
    required this.source,
    required this.id,
    required this.kind,
    required this.status,
    required this.message,
    required this.diagnosticCount,
    required this.stdoutCount,
    required this.stderrCount,
    this.metadata = const <String, Object?>{},
  });

  final String source;
  final String id;
  final String kind;
  final String status;
  final String message;
  final int diagnosticCount;
  final int stdoutCount;
  final int stderrCount;
  final Map<String, Object?> metadata;

  bool get succeeded => status == ExecutionSessionStatus.succeeded.name;
  bool get failed => status == ExecutionSessionStatus.failed.name;
  bool get blocked => status == ExecutionSessionStatus.blocked.name;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'source': source,
      'id': id,
      'kind': kind,
      'status': status,
      'message': message,
      'succeeded': succeeded,
      'failed': failed,
      'blocked': blocked,
      'diagnosticCount': diagnosticCount,
      'stdoutCount': stdoutCount,
      'stderrCount': stderrCount,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

abstract class ExecutionAdapter {
  AdapterCapabilitySnapshot get capabilitySnapshot;

  Future<ExecutionSession> runActiveDocument({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
  });
}

class ObservedExecutionRun {
  ObservedExecutionRun({
    required this.session,
    this.runtimeEventsPath,
    this.unavailableReason,
    Future<void> Function()? release,
  }) : release = release ?? _noopRelease;

  final ExecutionSession session;
  final String? runtimeEventsPath;
  final ObservableReasonCode? unavailableReason;
  final Future<void> Function() release;

  static Future<void> _noopRelease() async {}
}

abstract class ObservedExecutionAdapter {
  Future<ObservedExecutionRun> runActiveDocumentObserved({
    required PlatformTarget platformTarget,
    required ProjectGraphSnapshot projectGraph,
    required DocumentState document,
    required String activeFilePath,
    required RuntimeObservationRequest observation,
  });
}

typedef ExecutionAdapterFactory =
    Future<ExecutionAdapter> Function(ProjectGraphSnapshot projectGraph);
