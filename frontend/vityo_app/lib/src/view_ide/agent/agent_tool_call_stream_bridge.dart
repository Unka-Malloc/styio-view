import 'agent_provider_adapter.dart';
import 'agent_tool_call_lifecycle.dart';

class AgentProviderToolCallStreamBridge {
  const AgentProviderToolCallStreamBridge();

  AgentToolCallEvent? eventFor(AgentProviderStreamEvent event) {
    final kind = _metadataString(event.metadata, const <String>[
      'toolCallEventKind',
      'tool_call_event_kind',
      'toolEventKind',
      'tool_event_kind',
      'type',
    ]);
    if (kind.isEmpty) {
      return null;
    }
    final callId = _metadataString(event.metadata, const <String>[
      'toolCallId',
      'tool_call_id',
      'callId',
      'call_id',
    ]);
    if (callId.isEmpty) {
      return null;
    }
    final toolId = _metadataString(event.metadata, const <String>[
      'toolId',
      'tool_id',
      'toolName',
      'tool_name',
    ]);
    final emittedAt = event.emittedAt;
    final normalizedKind = _normalizeKind(kind);

    switch (normalizedKind) {
      case 'tool-input-start':
        return AgentToolCallEvent.inputStart(
          callId: callId,
          toolId: toolId,
          emittedAt: emittedAt,
          metadata: event.metadata,
        );
      case 'tool-input-delta':
        return AgentToolCallEvent.inputDelta(
          callId: callId,
          toolId: toolId,
          inputDelta:
              _metadataString(event.metadata, const <String>[
                'toolInputDelta',
                'tool_input_delta',
                'inputDelta',
                'input_delta',
              ]).isNotEmpty
              ? _metadataString(event.metadata, const <String>[
                  'toolInputDelta',
                  'tool_input_delta',
                  'inputDelta',
                  'input_delta',
                ])
              : event.deltaText,
          emittedAt: emittedAt,
          metadata: event.metadata,
        );
      case 'tool-input-end':
        return AgentToolCallEvent.inputEnd(
          callId: callId,
          toolId: toolId,
          input: _metadataString(event.metadata, const <String>[
            'toolInput',
            'tool_input',
            'input',
          ]),
          emittedAt: emittedAt,
          metadata: event.metadata,
        );
      case 'tool-call':
        return AgentToolCallEvent.callStarted(
          callId: callId,
          toolId: toolId,
          input: _metadataString(event.metadata, const <String>[
            'toolInput',
            'tool_input',
            'input',
          ]),
          emittedAt: emittedAt,
          metadata: event.metadata,
        );
      case 'permission-blocked':
        return AgentToolCallEvent.permissionBlocked(
          callId: callId,
          toolId: toolId,
          permissionReason: _metadataString(event.metadata, const <String>[
            'permissionReason',
            'permission_reason',
            'reason',
          ]),
          emittedAt: emittedAt,
          metadata: event.metadata,
        );
      case 'tool-result':
        return AgentToolCallEvent.result(
          callId: callId,
          toolId: toolId,
          result: _metadataString(event.metadata, const <String>[
            'toolResult',
            'tool_result',
            'result',
          ]),
          emittedAt: emittedAt,
          metadata: event.metadata,
        );
      case 'tool-error':
        return AgentToolCallEvent.error(
          callId: callId,
          toolId: toolId,
          errorMessage: _metadataString(event.metadata, const <String>[
            'toolError',
            'tool_error',
            'errorMessage',
            'error_message',
            'message',
          ]),
          emittedAt: emittedAt,
          metadata: event.metadata,
        );
    }
    return null;
  }

  List<AgentToolCallEvent> eventsFor(
    Iterable<AgentProviderStreamEvent> events,
  ) {
    return events
        .map(eventFor)
        .whereType<AgentToolCallEvent>()
        .toList(growable: false);
  }
}

String _metadataString(Map<String, Object?> metadata, List<String> keys) {
  for (final key in keys) {
    final value = metadata[key];
    if (value is String && value.trim().isNotEmpty) {
      return value.trim();
    }
  }
  return '';
}

String _normalizeKind(String kind) {
  final normalized = kind.trim().toLowerCase().replaceAll('_', '-');
  return switch (normalized) {
    'input-start' => 'tool-input-start',
    'toolinputstart' => 'tool-input-start',
    'tool-input-start' => 'tool-input-start',
    'input-delta' => 'tool-input-delta',
    'toolinputdelta' => 'tool-input-delta',
    'tool-input-delta' => 'tool-input-delta',
    'input-end' => 'tool-input-end',
    'toolinputend' => 'tool-input-end',
    'tool-input-end' => 'tool-input-end',
    'call-started' => 'tool-call',
    'tool-call-started' => 'tool-call',
    'tool-call' => 'tool-call',
    'permission-blocked' => 'permission-blocked',
    'tool-permission-blocked' => 'permission-blocked',
    'result' => 'tool-result',
    'tool-result' => 'tool-result',
    'error' => 'tool-error',
    'tool-error' => 'tool-error',
    _ => normalized,
  };
}
