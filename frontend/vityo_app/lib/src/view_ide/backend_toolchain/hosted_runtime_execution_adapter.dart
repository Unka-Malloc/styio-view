import '../runtime/runtime.dart';
import 'execution_adapter.dart';
import 'hosted_control_plane.dart';
import 'hosted_execution_codec.dart';
import 'runtime_event_adapter.dart';

enum HostedRuntimeExecutionStatus { executed, blocked, wrongRoute }

extension HostedRuntimeExecutionStatusX on HostedRuntimeExecutionStatus {
  String get wireValue => switch (this) {
    HostedRuntimeExecutionStatus.executed => 'executed',
    HostedRuntimeExecutionStatus.blocked => 'blocked',
    HostedRuntimeExecutionStatus.wrongRoute => 'wrong-route',
  };
}

class HostedRuntimeExecutionResult {
  const HostedRuntimeExecutionResult({
    required this.binding,
    required this.status,
    required this.outputEvents,
    this.session,
    this.runtimeEvents = const <RuntimeEventEnvelope>[],
  });

  final RuntimeExecutionHandoffBinding binding;
  final HostedRuntimeExecutionStatus status;
  final List<RuntimeOutputEvent> outputEvents;
  final ExecutionSession? session;
  final List<RuntimeEventEnvelope> runtimeEvents;

  bool get executed => status == HostedRuntimeExecutionStatus.executed;
  bool get succeeded => session?.status == ExecutionSessionStatus.succeeded;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'executed': executed,
      'succeeded': succeeded,
      'binding': binding.toJson(),
      if (session != null) 'session': session!.toJson(),
      'runtimeEvents': runtimeEvents
          .map((event) => event.toJson())
          .toList(growable: false),
      'outputEvents': outputEvents
          .map((event) => event.toJson())
          .toList(growable: false),
    };
  }
}

class HostedRuntimeExecutionAdapter {
  HostedRuntimeExecutionAdapter({
    required this.client,
    String? workspaceId,
    RuntimeTaskClock? clock,
  }) : workspaceId = workspaceId ?? client.config.workspaceId,
       _clock = clock ?? DateTime.now().toUtc;

  final HostedControlPlaneClient client;
  final String? workspaceId;
  final RuntimeTaskClock _clock;

  Future<HostedRuntimeExecutionResult> executeHandoff({
    required RuntimeExecutionHandoffBinding binding,
    required RuntimeOutputLiveBuffer buffer,
    required String activeFilePath,
    required String documentText,
    String? packageName,
    String? targetName,
    String? targetKind,
  }) async {
    if (binding.managerId != 'hosted-executor') {
      return _controlResult(
        binding: binding,
        buffer: buffer,
        status: HostedRuntimeExecutionStatus.wrongRoute,
        message:
            'Hosted execution ignored non-hosted route ${binding.managerId}.',
      );
    }
    if (!binding.ready) {
      return _controlResult(
        binding: binding,
        buffer: buffer,
        status: HostedRuntimeExecutionStatus.blocked,
        message: 'Hosted execution blocked before workflow dispatch.',
      );
    }
    final resolvedWorkspaceId = workspaceId;
    if (resolvedWorkspaceId == null || resolvedWorkspaceId.trim().isEmpty) {
      return _controlResult(
        binding: binding,
        buffer: buffer,
        status: HostedRuntimeExecutionStatus.blocked,
        message: 'Hosted execution blocked because workspaceId is missing.',
      );
    }

    final workflowKind = _workflowKindFor(binding);
    final response = await _runWorkflow(
      workflowKind: workflowKind,
      workspaceId: resolvedWorkspaceId,
      activeFilePath: activeFilePath,
      documentText: documentText,
      packageName: packageName,
      targetName: targetName,
      targetKind: targetKind,
    );
    final decoded = executionSessionFromHostedResponse(
      response: response,
      workflowKind: workflowKind,
      successMessage: 'Hosted $workflowKind completed.',
      documentText: documentText,
      activeFilePath: activeFilePath,
    );
    if (decoded.runtimeEvents.isNotEmpty) {
      recordRuntimeEventsForSession(
        decoded.session.sessionId,
        decoded.runtimeEvents,
      );
    }
    final outputEvents = _eventsForSession(
      binding: binding,
      session: decoded.session,
      runtimeEvents: decoded.runtimeEvents,
    );
    for (final event in outputEvents) {
      buffer.addEvent(event, now: event.timestamp);
    }
    return HostedRuntimeExecutionResult(
      binding: binding,
      status: HostedRuntimeExecutionStatus.executed,
      session: decoded.session,
      runtimeEvents: decoded.runtimeEvents,
      outputEvents: List<RuntimeOutputEvent>.unmodifiable(outputEvents),
    );
  }

  Future<Map<String, dynamic>> _runWorkflow({
    required String workflowKind,
    required String workspaceId,
    required String activeFilePath,
    required String documentText,
    String? packageName,
    String? targetName,
    String? targetKind,
  }) {
    return switch (workflowKind) {
      'build' => client.buildWorkflow(
        workspaceId: workspaceId,
        activeFilePath: activeFilePath,
        documentText: documentText,
        packageName: packageName,
        targetName: targetName,
        targetKind: targetKind,
      ),
      'test' => client.testWorkflow(
        workspaceId: workspaceId,
        activeFilePath: activeFilePath,
        documentText: documentText,
        packageName: packageName,
        targetName: targetName,
        targetKind: targetKind,
      ),
      _ => client.runWorkflow(
        workspaceId: workspaceId,
        activeFilePath: activeFilePath,
        documentText: documentText,
        packageName: packageName,
        targetName: targetName,
        targetKind: targetKind,
      ),
    };
  }

  HostedRuntimeExecutionResult _controlResult({
    required RuntimeExecutionHandoffBinding binding,
    required RuntimeOutputLiveBuffer buffer,
    required HostedRuntimeExecutionStatus status,
    required String message,
  }) {
    final outputEvent = binding.outputEvent(
      message: message,
      timestamp: _clock(),
      kind: RuntimeOutputChannelKind.runtimeEvents,
      metadata: <String, Object?>{
        'hostedRuntimeExecutionStatus': status.wireValue,
      },
    );
    buffer.addEvent(outputEvent, now: outputEvent.timestamp);
    return HostedRuntimeExecutionResult(
      binding: binding,
      status: status,
      outputEvents: <RuntimeOutputEvent>[outputEvent],
    );
  }

  List<RuntimeOutputEvent> _eventsForSession({
    required RuntimeExecutionHandoffBinding binding,
    required ExecutionSession session,
    required List<RuntimeEventEnvelope> runtimeEvents,
  }) {
    final timestamp = _clock();
    return <RuntimeOutputEvent>[
      binding.outputEvent(
        message: session.statusMessage,
        timestamp: timestamp,
        kind: RuntimeOutputChannelKind.runtimeEvents,
        metadata: <String, Object?>{
          'hostedRuntimeExecutionStatus':
              HostedRuntimeExecutionStatus.executed.wireValue,
          'executionSessionId': session.sessionId,
          'executionSessionStatus': session.status.name,
          'runtimeEventCount': runtimeEvents.length,
        },
      ),
      for (final event in session.stdoutEvents)
        RuntimeOutputEvent(
          channelId: '${binding.outputChannel.id}.stdout',
          label: '${binding.outputChannel.label} stdout',
          kind: RuntimeOutputChannelKind.stdout,
          message: event.message,
          timestamp: timestamp,
          metadata: <String, Object?>{
            'hostedRuntimeExecutionStatus':
                HostedRuntimeExecutionStatus.executed.wireValue,
            'executionSessionId': session.sessionId,
            'stream': 'stdout',
          },
        ),
      for (final event in session.stderrEvents)
        RuntimeOutputEvent(
          channelId: '${binding.outputChannel.id}.stderr',
          label: '${binding.outputChannel.label} stderr',
          kind: RuntimeOutputChannelKind.stderr,
          message: event.message,
          timestamp: timestamp,
          metadata: <String, Object?>{
            'hostedRuntimeExecutionStatus':
                HostedRuntimeExecutionStatus.executed.wireValue,
            'executionSessionId': session.sessionId,
            'stream': 'stderr',
          },
        ),
      for (final event in runtimeEvents)
        RuntimeOutputEvent(
          channelId: '${binding.outputChannel.id}.runtime',
          label: '${binding.outputChannel.label} runtime',
          kind: RuntimeOutputChannelKind.runtimeEvents,
          message: '${event.eventKind} from ${event.origin}',
          timestamp: event.timestamp,
          metadata: <String, Object?>{
            'hostedRuntimeExecutionStatus':
                HostedRuntimeExecutionStatus.executed.wireValue,
            'executionSessionId': session.sessionId,
            'runtimeEventKind': event.eventKind,
            'runtimeEventSequence': event.sequence,
          },
        ),
    ];
  }
}

String _workflowKindFor(RuntimeExecutionHandoffBinding binding) {
  final explicit = binding.handoff.plan.definition.metadata['workflowKind'];
  if (explicit is String && explicit.trim().isNotEmpty) {
    return explicit.trim();
  }
  return switch (binding.handoff.plan.definition.kind) {
    RuntimeTaskKind.build => 'build',
    RuntimeTaskKind.test => 'test',
    _ => 'run',
  };
}
