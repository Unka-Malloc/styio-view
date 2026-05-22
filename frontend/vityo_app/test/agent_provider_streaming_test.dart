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

  test(
    'agent provider stream collector preserves streamed tool calls',
    () async {
      const requestId = 'agent-stream-tool-call';

      final response = await const AgentProviderStreamingResponseCollector()
          .collect(
            requestId: requestId,
            events: Stream<AgentProviderStreamEvent>.fromIterable(
              <AgentProviderStreamEvent>[
                AgentProviderStreamEvent.delta(
                  requestId: requestId,
                  text: '',
                  metadata: const <String, Object?>{
                    'toolCallEventKind': 'tool-input-start',
                    'toolCallId': 'call-read',
                    'toolId': 'readWorkspaceFile',
                  },
                ),
                AgentProviderStreamEvent.delta(
                  requestId: requestId,
                  text: '',
                  metadata: const <String, Object?>{
                    'toolCallEventKind': 'tool-input-delta',
                    'toolCallId': 'call-read',
                    'toolId': 'readWorkspaceFile',
                    'toolInputDelta': '{"path":"main.styio"}',
                  },
                ),
                AgentProviderStreamEvent.completed(
                  requestId: requestId,
                  metadata: const <String, Object?>{
                    'finishReason': 'tool_calls',
                  },
                ),
              ],
            ),
          );

      expect(response.finishReason, 'tool_calls');
      expect(
        response.toolCallEvents.map((event) => event.kind),
        <AgentToolCallEventKind>[
          AgentToolCallEventKind.inputStart,
          AgentToolCallEventKind.inputDelta,
        ],
      );
      expect(response.toolCallEvents.last.inputDelta, '{"path":"main.styio"}');
    },
  );

  test('streaming adapter can reuse collector for send contract', () async {
    final adapter = _FakeStreamingAgentProviderAdapter();
    final request = _agentRequest('agent-stream-adapter');

    final response = await adapter.send(request);

    expect(adapter.supportsCodePatch, isTrue);
    expect(response.contentParts.single.text, 'streamed response');
    expect(adapter.streamedRequestIds, <String>[request.requestId]);
  });

  test(
    'OpenAI-compatible adapter delegates stream requests to transport',
    () async {
      final request = _agentRequest('agent-stream-openai-compatible');
      final transport = _RecordingStreamingAgentProviderTransport();
      final adapter = OpenAICompatibleAgentProviderAdapter(
        transport: transport,
        endpoint: request.profile.endpoint,
        authorizationToken: '  test-token  ',
      );

      final events = await adapter.stream(request).toList();

      expect(events.map((event) => event.kind), <AgentProviderStreamEventKind>[
        AgentProviderStreamEventKind.started,
        AgentProviderStreamEventKind.contentDelta,
        AgentProviderStreamEventKind.completed,
      ]);
      expect(
        transport.endpoint.toString(),
        '/api/styio-agent/v1/chat/completions',
      );
      expect(transport.headers['Authorization'], 'Bearer test-token');
      expect(transport.body['model'], request.profile.endpoint.model);
      expect(transport.body['stream'], isTrue);
    },
  );

  test(
    'OpenAI Responses adapter delegates stream requests to transport',
    () async {
      final profile = AgentPromptProfile.openAICodexSparkForPlatform(
        PlatformTarget.web,
      );
      final request = _agentRequest(
        'agent-stream-openai-responses',
        profile: profile,
      );
      final transport = _RecordingStreamingAgentProviderTransport();
      final adapter = OpenAIResponsesAgentProviderAdapter(
        transport: transport,
        endpoint: profile.endpoint,
        authorizationToken: 'test-token',
      );

      final events = await adapter.stream(request).toList();

      expect(events.first.kind, AgentProviderStreamEventKind.started);
      expect(events.last.kind, AgentProviderStreamEventKind.completed);
      expect(
        transport.endpoint.toString(),
        'https://api.openai.com/v1/responses',
      );
      expect(transport.body['model'], 'gpt-5.3-codex-spark');
      expect(transport.body['stream'], isTrue);
      expect(transport.body['input'], isA<List<Object?>>());
    },
  );

  test('streaming adapter falls back to single response transport', () async {
    final request = _agentRequest('agent-stream-fallback');
    final adapter = OpenAICompatibleAgentProviderAdapter(
      transport: const _SingleResponseAgentProviderTransport(),
      endpoint: request.profile.endpoint,
    );

    final events = await adapter.stream(request).toList();

    expect(events.first.kind, AgentProviderStreamEventKind.started);
    expect(events.last.kind, AgentProviderStreamEventKind.completed);
    expect(events.last.metadata['streamFallback'], isTrue);
    expect(
      events.last.metadata['streamFallbackReason'],
      'transportDoesNotSupportStreaming',
    );
    expect(events.last.metadata.containsKey('TODO'), isFalse);
    expect(
      events.last.response?.contentParts.single.text,
      'Fallback response.',
    );
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

AgentProviderRequest _agentRequest(
  String requestId, {
  AgentPromptProfile? profile,
}) {
  final promptProfile =
      profile ?? AgentPromptProfile.defaultForPlatform(PlatformTarget.web);
  return AgentProviderRequest(
    requestId: requestId,
    profile: promptProfile,
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

class _RecordingStreamingAgentProviderTransport
    implements StreamingAgentProviderTransport {
  late Uri endpoint;
  late Map<String, String> headers;
  late Map<String, Object?> body;

  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) {
    throw StateError('streaming transport postJson should not be used');
  }

  @override
  Stream<AgentProviderStreamEvent> postJsonStream({
    required String requestId,
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async* {
    this.endpoint = endpoint;
    this.headers = headers;
    this.body = body;
    yield AgentProviderStreamEvent.delta(
      requestId: requestId,
      text: 'stream delta',
    );
    yield AgentProviderStreamEvent.completed(
      requestId: requestId,
      metadata: const <String, Object?>{'finishReason': 'stop'},
    );
  }
}

class _SingleResponseAgentProviderTransport implements AgentProviderTransport {
  const _SingleResponseAgentProviderTransport();

  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return <String, Object?>{
      'id': 'chatcmpl-stream-fallback',
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'role': 'assistant',
            'content': 'Fallback response.',
          },
        },
      ],
    };
  }
}
