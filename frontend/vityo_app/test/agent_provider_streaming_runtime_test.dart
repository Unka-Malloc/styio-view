import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/view_ide/agent/agent_provider_retry_policy.dart';
import 'package:vityo_app/src/view_ide/agent/agent_provider_streaming_runtime.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test(
    'agent stream runtime binding maps provider events to output events',
    () {
      const binding = AgentProviderStreamRuntimeOutputBinding();
      final events = binding.eventsFor(<AgentProviderStreamEvent>[
        AgentProviderStreamEvent.started('agent-stream-runtime'),
        AgentProviderStreamEvent.delta(
          requestId: 'agent-stream-runtime',
          text: 'partial response',
        ),
        AgentProviderStreamEvent.part(
          requestId: 'agent-stream-runtime',
          contentPart: const AgentContentPart(
            kind: AgentContentPartKind.ideCommand,
            text: 'Run tests',
            ideCommand: AgentIdeCommandSuggestion(commandId: 'runTests'),
          ),
        ),
        AgentProviderStreamEvent.failed(
          requestId: 'agent-stream-runtime',
          message: 'network unavailable',
        ),
      ]);

      expect(events, hasLength(4));
      expect(events.first.kind, RuntimeOutputChannelKind.agent);
      expect(events.first.channelId, 'agent.activity');
      expect(events[1].message, 'partial response');
      expect(events[2].metadata['contentPartKind'], 'ide_command');
      expect(events.last.metadata['terminal'], isTrue);
      expect(events.last.metadata['errorMessage'], 'network unavailable');
    },
  );

  test('agent runtime binding maps retry execution to output event', () {
    const binding = AgentProviderStreamRuntimeOutputBinding();
    final event = binding.retryEventFor(
      AgentProviderRetryExecution<AgentProviderResponseEnvelope>(
        value: const AgentProviderResponseEnvelope(
          requestId: 'retry-request',
          role: 'assistant',
          finishReason: 'stop',
          contentParts: <AgentContentPart>[],
        ),
        attempts: <AgentProviderRetryAttempt>[
          AgentProviderRetryAttempt(
            attempt: 1,
            status: AgentProviderRetryAttemptStatus.failed,
            startedAt: DateTime.utc(2026, 5, 20, 8),
            finishedAt: DateTime.utc(2026, 5, 20, 8, 0, 1),
            failureKind: AgentProviderTransportFailureKind.timeout,
            message: 'timeout',
            retryScheduled: true,
            delayBeforeNextAttempt: const Duration(milliseconds: 250),
          ),
          AgentProviderRetryAttempt(
            attempt: 2,
            status: AgentProviderRetryAttemptStatus.succeeded,
            startedAt: DateTime.utc(2026, 5, 20, 8, 0, 2),
            finishedAt: DateTime.utc(2026, 5, 20, 8, 0, 3),
          ),
        ],
      ),
      requestId: 'retry-request',
      timestamp: DateTime.utc(2026, 5, 20, 8, 0, 4),
    );

    expect(event.channelId, 'agent.activity');
    expect(event.kind, RuntimeOutputChannelKind.agent);
    expect(event.message, contains('succeeded after 2 attempt'));
    expect(event.metadata['retrySucceeded'], isTrue);
    expect(event.metadata['retryAttemptCount'], 2);
    expect(event.metadata['requestId'], 'retry-request');
    expect(event.metadata['retryAttempts'], hasLength(2));
  });
}
