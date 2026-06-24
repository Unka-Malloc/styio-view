import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';

void main() {
  test('agent tool call stream bridge maps OpenCode-style metadata', () {
    const bridge = AgentProviderToolCallStreamBridge();
    final events = bridge.eventsFor(<AgentProviderStreamEvent>[
      AgentProviderStreamEvent.delta(
        requestId: 'request-1',
        text: '{"path"',
        metadata: const <String, Object?>{
          'toolCallEventKind': 'tool-input-start',
          'toolCallId': 'call-1',
          'toolId': 'readWorkspaceFile',
        },
      ),
      AgentProviderStreamEvent.delta(
        requestId: 'request-1',
        text: '{"path"',
        metadata: const <String, Object?>{
          'toolCallEventKind': 'tool-input-delta',
          'toolCallId': 'call-1',
          'toolId': 'readWorkspaceFile',
        },
      ),
      AgentProviderStreamEvent.completed(
        requestId: 'request-1',
        metadata: const <String, Object?>{
          'toolCallEventKind': 'tool-result',
          'toolCallId': 'call-1',
          'toolId': 'readWorkspaceFile',
          'toolResult': 'value = 1',
        },
      ),
    ]);

    expect(events.map((event) => event.kind), <AgentToolCallEventKind>[
      AgentToolCallEventKind.inputStart,
      AgentToolCallEventKind.inputDelta,
      AgentToolCallEventKind.result,
    ]);
    expect(events[1].inputDelta, '{"path"');
    expect(events[2].result, 'value = 1');
  });

  test('agent tool call stream bridge ignores incomplete metadata', () {
    const bridge = AgentProviderToolCallStreamBridge();
    final event = bridge.eventFor(
      AgentProviderStreamEvent.delta(
        requestId: 'request-1',
        text: 'ignored',
        metadata: const <String, Object?>{
          'toolCallEventKind': 'tool-call',
          'toolId': 'readWorkspaceFile',
        },
      ),
    );

    expect(event, isNull);
  });

  test('agent tool call stream bridge maps permission blocked metadata', () {
    const bridge = AgentProviderToolCallStreamBridge();
    final event = bridge.eventFor(
      AgentProviderStreamEvent.part(
        requestId: 'request-1',
        contentPart: const AgentContentPart(
          kind: AgentContentPartKind.text,
          text: 'blocked',
        ),
        metadata: const <String, Object?>{
          'tool_call_event_kind': 'permission-blocked',
          'tool_call_id': 'call-2',
          'tool_id': 'applyWorkspacePatch',
          'permission_reason': 'Review required.',
        },
      ),
    );

    expect(event?.kind, AgentToolCallEventKind.permissionBlocked);
    expect(event?.callId, 'call-2');
    expect(event?.toolId, 'applyWorkspacePatch');
    expect(event?.permissionReason, 'Review required.');
  });
}
