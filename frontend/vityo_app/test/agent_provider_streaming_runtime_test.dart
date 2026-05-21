import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';
import 'package:vityo_app/src/view_ide/agent/agent_profile.dart';
import 'package:vityo_app/src/view_ide/agent/agent_provider_retry_policy.dart';
import 'package:vityo_app/src/view_ide/agent/agent_provider_streaming_runtime.dart';
import 'package:vityo_app/src/view_ide/agent/agent_session_context.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';

void main() {
  test('agent streaming runtime collects streaming provider events', () async {
    final result = await const AgentProviderStreamingRuntime().run(
      adapter: const _StreamingAdapter(),
      request: _request('streaming-runtime-request'),
    );

    expect(result.succeeded, isTrue);
    expect(result.response?.contentParts.single.text, 'streamed reply');
    expect(result.providerEvents.map((event) => event.kind), <Object>[
      AgentProviderStreamEventKind.started,
      AgentProviderStreamEventKind.contentDelta,
      AgentProviderStreamEventKind.completed,
    ]);
    expect(result.outputEvents, hasLength(3));
    expect(result.outputEvents.first.channelId, 'agent.activity');
    expect(result.toJson()['providerEventCount'], 3);
  });

  test('agent streaming runtime publishes live event callbacks', () async {
    final providerKinds = <AgentProviderStreamEventKind>[];
    final outputKinds = <String>[];
    final result = await const AgentProviderStreamingRuntime().run(
      adapter: const _StreamingAdapter(),
      request: _request('streaming-runtime-live-request'),
      onProviderEvent: (event) {
        providerKinds.add(event.kind);
      },
      onOutputEvent: (event) {
        outputKinds.add(event.metadata['streamEventKind']! as String);
      },
    );

    expect(result.succeeded, isTrue);
    expect(providerKinds, <AgentProviderStreamEventKind>[
      AgentProviderStreamEventKind.started,
      AgentProviderStreamEventKind.contentDelta,
      AgentProviderStreamEventKind.completed,
    ]);
    expect(outputKinds, <String>['started', 'contentDelta', 'completed']);
    expect(
      result.outputEvents.map((event) => event.metadata['streamEventKind']),
      outputKinds,
    );
  });

  test('agent streaming runtime synthesizes events for send adapters', () async {
    final result = await const AgentProviderStreamingRuntime().run(
      adapter: const _StaticAdapter(),
      request: _request('send-runtime-request'),
    );

    expect(result.succeeded, isTrue);
    expect(result.response?.contentParts.single.text, 'send reply');
    expect(result.providerEvents.map((event) => event.kind), <Object>[
      AgentProviderStreamEventKind.started,
      AgentProviderStreamEventKind.contentPart,
      AgentProviderStreamEventKind.completed,
    ]);
    expect(result.providerEvents.first.metadata['synthetic'], isTrue);
    expect(result.outputEvents[1].metadata['contentPartKind'], 'text');
  });

  test('agent streaming runtime captures provider failures', () async {
    final result = await const AgentProviderStreamingRuntime().run(
      adapter: const _FailingAdapter(),
      request: _request('failed-runtime-request'),
    );

    expect(result.succeeded, isFalse);
    expect(result.errorMessage, 'provider unavailable');
    expect(result.providerEvents.map((event) => event.kind), <Object>[
      AgentProviderStreamEventKind.started,
      AgentProviderStreamEventKind.failed,
    ]);
    expect(result.outputEvents.last.metadata['terminal'], isTrue);
    expect(result.outputEvents.last.metadata['errorMessage'], isNotNull);
  });

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

AgentProviderRequest _request(String requestId) {
  return AgentProviderRequest(
    requestId: requestId,
    profile: _profile(),
    context: _emptyContext(),
    userPrompt: 'Run agent streaming runtime.',
  );
}

AgentPromptProfile _profile() {
  return const AgentPromptProfile(
    profileId: 'stream-runtime-test',
    displayName: 'Stream Runtime Test',
    systemPrompt: 'Use IDE context.',
    endpoint: AgentProviderEndpoint(
      route: AgentProviderRoute.webHosted,
      baseUrl: 'https://agent.example.test/v1',
      model: 'gpt-stream-runtime-test',
    ),
  );
}

AgentSessionContext _emptyContext() {
  return AgentSessionContext.fromEditorState(
    document: const DocumentState(
      documentId: '/workspace/demo/src/main.styio',
      text: '',
      revision: 0,
    ),
    selection: const SelectionState.collapsed(0),
    diagnostics: const [],
  );
}

class _StreamingAdapter implements StreamingAgentProviderAdapter {
  const _StreamingAdapter();

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  String get adapterId => 'streaming-test';

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
    yield AgentProviderStreamEvent.started(request.requestId);
    yield AgentProviderStreamEvent.delta(
      requestId: request.requestId,
      text: 'streamed reply',
    );
    yield AgentProviderStreamEvent.completed(requestId: request.requestId);
  }
}

class _StaticAdapter implements AgentProviderAdapter {
  const _StaticAdapter();

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  String get adapterId => 'static-test';

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      finishReason: 'stop',
      contentParts: const <AgentContentPart>[
        AgentContentPart(kind: AgentContentPartKind.text, text: 'send reply'),
      ],
    );
  }
}

class _FailingAdapter implements AgentProviderAdapter {
  const _FailingAdapter();

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  String get adapterId => 'failing-test';

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(AgentProviderRequest request) {
    throw const AgentProviderTransportException(
      kind: AgentProviderTransportFailureKind.hostUnreachable,
      message: 'provider unavailable',
    );
  }
}
