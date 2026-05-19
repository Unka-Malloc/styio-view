import '../editor/document_state.dart';
import '../language/language_contract.dart';
import '../platform/platform_target.dart';
import 'adapter_contracts.dart';
import 'execution_adapter_web.dart'
    if (dart.library.io) 'execution_adapter_io.dart'
    as platform_adapter;
import 'project_graph_contract.dart';

enum ExecutionSessionStatus { blocked, running, succeeded, failed }

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
  });

  final String sessionId;
  final String kind;
  final ExecutionSessionStatus status;
  final String statusMessage;
  final SourceRange? unitRange;
  final List<Diagnostic> diagnostics;
  final List<ExecutionLogEvent> stdoutEvents;
  final List<ExecutionLogEvent> stderrEvents;

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
      metadata: metadata,
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

typedef ExecutionAdapterFactory =
    Future<ExecutionAdapter> Function(ProjectGraphSnapshot projectGraph);

Future<ExecutionAdapter> createExecutionAdapter({
  required PlatformTarget platformTarget,
  required ProjectGraphSnapshot projectGraph,
}) {
  return platform_adapter.createPlatformExecutionAdapter(
    platformTarget: platformTarget,
    projectGraph: projectGraph,
  );
}
