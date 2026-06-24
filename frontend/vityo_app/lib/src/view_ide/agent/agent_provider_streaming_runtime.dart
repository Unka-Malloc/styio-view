import '../runtime/runtime.dart';
import 'agent_provider_adapter.dart';
import 'agent_provider_retry_policy.dart';

typedef AgentProviderStreamingEventSink =
    void Function(AgentProviderStreamEvent event);
typedef AgentProviderRuntimeOutputEventSink =
    void Function(RuntimeOutputEvent event);

enum AgentProviderStreamingRunStatus { succeeded, failed }

extension AgentProviderStreamingRunStatusX on AgentProviderStreamingRunStatus {
  String get wireValue {
    return switch (this) {
      AgentProviderStreamingRunStatus.succeeded => 'succeeded',
      AgentProviderStreamingRunStatus.failed => 'failed',
    };
  }
}

class AgentProviderStreamingRunResult {
  const AgentProviderStreamingRunResult({
    required this.status,
    required this.requestId,
    required this.providerEvents,
    required this.outputEvents,
    this.response,
    this.error,
    this.errorMessage,
  });

  final AgentProviderStreamingRunStatus status;
  final String requestId;
  final AgentProviderResponseEnvelope? response;
  final Object? error;
  final String? errorMessage;
  final List<AgentProviderStreamEvent> providerEvents;
  final List<RuntimeOutputEvent> outputEvents;

  bool get succeeded => status == AgentProviderStreamingRunStatus.succeeded;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'succeeded': succeeded,
      'requestId': requestId,
      if (response != null) 'response': response!.toJson(),
      if (errorMessage != null) 'errorMessage': errorMessage,
      'providerEventCount': providerEvents.length,
      'outputEventCount': outputEvents.length,
      'providerEvents': providerEvents
          .map((event) => event.toJson())
          .toList(growable: false),
    };
  }
}

class AgentProviderStreamingRuntime {
  const AgentProviderStreamingRuntime({
    this.collector = const AgentProviderStreamingResponseCollector(),
    this.binding = const AgentProviderStreamRuntimeOutputBinding(),
  });

  final AgentProviderStreamingResponseCollector collector;
  final AgentProviderStreamRuntimeOutputBinding binding;

  Future<AgentProviderStreamingRunResult> run({
    required AgentProviderAdapter adapter,
    required AgentProviderRequest request,
    AgentProviderStreamingEventSink? onProviderEvent,
    AgentProviderRuntimeOutputEventSink? onOutputEvent,
  }) async {
    final events = <AgentProviderStreamEvent>[];
    final outputEvents = <RuntimeOutputEvent>[];

    void record(AgentProviderStreamEvent event) {
      events.add(event);
      final outputEvent = binding.eventFor(event);
      outputEvents.add(outputEvent);
      onProviderEvent?.call(event);
      onOutputEvent?.call(outputEvent);
    }

    try {
      final response = adapter is StreamingAgentProviderAdapter
          ? await _runStreamingAdapter(adapter, request, record)
          : await _runSendAdapter(adapter, request, record);
      if (events.isEmpty || !events.last.terminal) {
        record(
          AgentProviderStreamEvent.completed(
            requestId: request.requestId,
            response: response,
            metadata: const <String, Object?>{'synthetic': true},
          ),
        );
      }
      return _result(
        status: AgentProviderStreamingRunStatus.succeeded,
        requestId: request.requestId,
        events: events,
        outputEvents: outputEvents,
        response: response,
      );
    } on Object catch (error) {
      final message = error is AgentProviderTransportException
          ? error.message
          : error.toString();
      if (events.isEmpty || !events.last.terminal) {
        record(
          AgentProviderStreamEvent.failed(
            requestId: request.requestId,
            message: message,
            metadata: <String, Object?>{
              'synthetic': true,
              'adapterId': adapter.adapterId,
            },
          ),
        );
      }
      return _result(
        status: AgentProviderStreamingRunStatus.failed,
        requestId: request.requestId,
        events: events,
        outputEvents: outputEvents,
        error: error,
        errorMessage: message,
      );
    }
  }

  Future<AgentProviderResponseEnvelope> _runStreamingAdapter(
    StreamingAgentProviderAdapter adapter,
    AgentProviderRequest request,
    void Function(AgentProviderStreamEvent event) record,
  ) {
    final stream = adapter.stream(request).map((event) {
      record(event);
      return event;
    });
    return collector.collect(requestId: request.requestId, events: stream);
  }

  Future<AgentProviderResponseEnvelope> _runSendAdapter(
    AgentProviderAdapter adapter,
    AgentProviderRequest request,
    void Function(AgentProviderStreamEvent event) record,
  ) async {
    record(
      AgentProviderStreamEvent.started(
        request.requestId,
        metadata: <String, Object?>{
          'synthetic': true,
          'adapterId': adapter.adapterId,
        },
      ),
    );
    final response = await adapter.send(request);
    for (final part in response.contentParts) {
      record(
        AgentProviderStreamEvent.part(
          requestId: request.requestId,
          contentPart: part,
          metadata: const <String, Object?>{'synthetic': true},
        ),
      );
    }
    record(
      AgentProviderStreamEvent.completed(
        requestId: request.requestId,
        response: response,
        metadata: const <String, Object?>{'synthetic': true},
      ),
    );
    return response;
  }

  AgentProviderStreamingRunResult _result({
    required AgentProviderStreamingRunStatus status,
    required String requestId,
    required List<AgentProviderStreamEvent> events,
    required List<RuntimeOutputEvent> outputEvents,
    AgentProviderResponseEnvelope? response,
    Object? error,
    String? errorMessage,
  }) {
    final providerEvents = List<AgentProviderStreamEvent>.unmodifiable(events);
    final runtimeEvents = List<RuntimeOutputEvent>.unmodifiable(outputEvents);
    return AgentProviderStreamingRunResult(
      status: status,
      requestId: requestId,
      response: response,
      error: error,
      errorMessage: errorMessage,
      providerEvents: providerEvents,
      outputEvents: runtimeEvents,
    );
  }
}

class AgentProviderStreamRuntimeOutputBinding {
  const AgentProviderStreamRuntimeOutputBinding({
    this.channelId = 'agent.activity',
    this.label = 'Agent Activity',
  });

  final String channelId;
  final String label;

  RuntimeOutputEvent eventFor(AgentProviderStreamEvent event) {
    return RuntimeOutputEvent(
      channelId: channelId,
      label: label,
      kind: RuntimeOutputChannelKind.agent,
      message: _messageFor(event),
      timestamp: event.emittedAt,
      metadata: <String, Object?>{
        'requestId': event.requestId,
        'streamEventKind': event.kind.name,
        'terminal': event.terminal,
        if (event.deltaText.isNotEmpty) 'deltaLength': event.deltaText.length,
        if (event.contentPart != null)
          'contentPartKind': event.contentPart!.kind.wireValue,
        if (event.errorMessage != null) 'errorMessage': event.errorMessage,
        ...event.metadata,
      },
    );
  }

  List<RuntimeOutputEvent> eventsFor(
    Iterable<AgentProviderStreamEvent> events,
  ) {
    return events.map(eventFor).toList(growable: false);
  }

  RuntimeOutputEvent retryEventFor(
    AgentProviderRetryExecution<AgentProviderResponseEnvelope> execution, {
    required String requestId,
    DateTime? timestamp,
  }) {
    return RuntimeOutputEvent(
      channelId: channelId,
      label: label,
      kind: RuntimeOutputChannelKind.agent,
      message: execution.succeeded
          ? 'Agent provider retry succeeded after ${execution.attemptCount} attempt(s).'
          : 'Agent provider retry failed after ${execution.attemptCount} attempt(s).',
      timestamp: timestamp ?? DateTime.now().toUtc(),
      metadata: <String, Object?>{
        'requestId': requestId,
        'retrySucceeded': execution.succeeded,
        'retryAttemptCount': execution.attemptCount,
        'retryAttempts': execution.attempts
            .map((attempt) => attempt.toJson())
            .toList(growable: false),
        if (execution.error != null) 'retryError': execution.error.toString(),
      },
    );
  }

  String _messageFor(AgentProviderStreamEvent event) {
    return switch (event.kind) {
      AgentProviderStreamEventKind.started => 'Agent provider stream started.',
      AgentProviderStreamEventKind.contentDelta =>
        event.deltaText.trim().isEmpty
            ? 'Agent provider stream emitted text.'
            : event.deltaText.trim(),
      AgentProviderStreamEventKind.contentPart =>
        'Agent provider stream emitted ${event.contentPart?.kind.wireValue ?? 'content'} part.',
      AgentProviderStreamEventKind.completed =>
        'Agent provider stream completed.',
      AgentProviderStreamEventKind.failed =>
        event.errorMessage ?? 'Agent provider stream failed.',
    };
  }
}
