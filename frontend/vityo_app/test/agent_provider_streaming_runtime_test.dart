import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
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
}
