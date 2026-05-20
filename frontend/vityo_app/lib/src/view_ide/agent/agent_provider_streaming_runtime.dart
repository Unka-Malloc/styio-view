import '../runtime/runtime.dart';
import 'agent_provider_adapter.dart';

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
