import '../runtime/runtime.dart';
import 'agent_provider_adapter.dart';
import 'agent_provider_retry_policy.dart';

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
