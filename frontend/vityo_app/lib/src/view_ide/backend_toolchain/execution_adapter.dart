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
