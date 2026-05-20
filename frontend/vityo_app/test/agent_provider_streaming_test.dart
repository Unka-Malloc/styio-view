import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_context.dart';
import 'package:vityo_app/src/agent/agent_profile.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/platform/platform_target.dart';

void main() {
  test('agent provider stream collector builds response envelope', () async {
    const requestId = 'agent-stream-1';
    final response = await const AgentProviderStreamingResponseCollector()
        .collect(
          requestId: requestId,
          events: Stream<AgentProviderStreamEvent>.fromIterable(
            <AgentProviderStreamEvent>[
              AgentProviderStreamEvent.started(requestId),
              AgentProviderStreamEvent.delta(
                requestId: requestId,
                text: 'Plan ',
              ),
              AgentProviderStreamEvent.delta(
                requestId: requestId,
                text: 'ready.',
              ),
              AgentProviderStreamEvent.part(
                requestId: requestId,
                contentPart: const AgentContentPart(
                  kind: AgentContentPartKind.plan,
                  text: 'Structured plan.',
                  plan: AgentCodingPlan(
                    summary: 'Patch editor',
                    steps: <String>['Read context', 'Apply patch'],
                    acceptanceCriteria: <String>['Tests pass'],
                  ),
                ),
              ),
              AgentProviderStreamEvent.completed(
                requestId: requestId,
                metadata: const <String, Object?>{
                  'finishReason': 'stop',
                  'usage': <String, Object?>{'outputTokens': 12},
                },
              ),
            ],
          ),
        );

    expect(response.requestId, requestId);
    expect(response.finishReason, 'stop');
    expect(response.contentParts, hasLength(2));
    expect(response.contentParts.first.text, 'Plan ready.');
    expect(response.contentParts.last.kind, AgentContentPartKind.plan);
    expect(response.usage?['outputTokens'], 12);
  });

  test('agent provider stream collector returns completed envelope', () async {
    const completed = AgentProviderResponseEnvelope(
      requestId: 'agent-stream-completed',
      role: 'assistant',
      finishReason: 'tool_calls',
      contentParts: <AgentContentPart>[
        AgentContentPart(
          kind: AgentContentPartKind.text,
          text: 'Use the IDE command.',
        ),
      ],
    );

    final response = await const AgentProviderStreamingResponseCollector()
        .collect(
          requestId: completed.requestId,
          events: Stream<AgentProviderStreamEvent>.fromIterable(
            <AgentProviderStreamEvent>[
              AgentProviderStreamEvent.delta(
                requestId: 'other-request',
                text: 'ignored',
              ),
              AgentProviderStreamEvent.completed(
                requestId: completed.requestId,
                response: completed,
              ),
            ],
          ),
        );

    expect(response, same(completed));
    expect(response.contentParts.single.text, 'Use the IDE command.');
  });

  test('streaming adapter can reuse collector for send contract', () async {
    final adapter = _FakeStreamingAgentProviderAdapter();
    final request = AgentProviderRequest(
      requestId: 'agent-stream-adapter',
      profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
      context: AgentSessionContext.fromEditorState(
        document: const DocumentState(
          documentId: 'main.styio',
          text: 'value := 1\n',
          revision: 1,
        ),
        selection: const SelectionState.collapsed(0),
        diagnostics: const [],
      ),
      userPrompt: 'Plan this change.',
    );

    final response = await adapter.send(request);

    expect(adapter.supportsCodePatch, isTrue);
    expect(response.contentParts.single.text, 'streamed response');
    expect(adapter.streamedRequestIds, <String>[request.requestId]);
  });

  test('agent provider stream event serializes terminal state', () {
    final event = AgentProviderStreamEvent.failed(
      requestId: 'agent-stream-failed',
      message: 'network unavailable',
    );
    final json = event.toJson();

    expect(event.terminal, isTrue);
    expect(json['kind'], AgentProviderStreamEventKind.failed.name);
    expect(json['terminal'], isTrue);
    expect(json['errorMessage'], 'network unavailable');
  });
}

class _FakeStreamingAgentProviderAdapter
    implements StreamingAgentProviderAdapter {
  final List<String> streamedRequestIds = <String>[];

  @override
  String get adapterId => 'fake-streaming-agent';

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    return const AgentProviderStreamingResponseCollector().collect(
      requestId: request.requestId,
      events: stream(request),
    );
  }

  @override
  Stream<AgentProviderStreamEvent> stream(AgentProviderRequest request) async* {
    streamedRequestIds.add(request.requestId);
    yield AgentProviderStreamEvent.started(request.requestId);
    yield AgentProviderStreamEvent.delta(
      requestId: request.requestId,
      text: 'streamed response',
    );
    yield AgentProviderStreamEvent.completed(requestId: request.requestId);
  }
}
