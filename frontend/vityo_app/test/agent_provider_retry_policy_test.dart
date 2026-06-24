import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent.dart';
import 'package:vityo_app/src/editor/document_state.dart';
import 'package:vityo_app/src/editor/selection_state.dart';

void main() {
  test('agent provider retry executor retries transient failures', () async {
    final delays = <Duration>[];
    var attempts = 0;
    var tick = 0;
    final executor = AgentProviderRetryExecutor(
      policy: const AgentProviderRetryPolicy(
        maxAttempts: 3,
        initialDelay: Duration(milliseconds: 10),
      ),
      delay: (delay) async {
        delays.add(delay);
      },
      clock: () => DateTime.utc(2026, 5, 20, 8, 0, tick++),
    );

    final execution = await executor.execute<String>(
      operation: (attempt) async {
        attempts += 1;
        if (attempt == 1) {
          throw const AgentProviderTransportException(
            kind: AgentProviderTransportFailureKind.timeout,
            message: 'request timed out',
          );
        }
        return 'ok';
      },
    );

    expect(execution.succeeded, isTrue);
    expect(execution.value, 'ok');
    expect(attempts, 2);
    expect(delays, <Duration>[const Duration(milliseconds: 10)]);
    expect(execution.attempts.first.retryScheduled, isTrue);
    expect(
      execution.attempts.last.status,
      AgentProviderRetryAttemptStatus.succeeded,
    );
    expect(execution.toJson()['attemptCount'], 2);
  });

  test(
    'agent provider retry executor does not retry invalid responses',
    () async {
      final delays = <Duration>[];
      final executor = AgentProviderRetryExecutor(
        delay: (delay) async {
          delays.add(delay);
        },
      );

      final execution = await executor.execute<String>(
        operation: (_) async {
          throw const AgentProviderTransportException(
            kind: AgentProviderTransportFailureKind.invalidResponse,
            message: 'invalid JSON',
          );
        },
      );

      expect(execution.succeeded, isFalse);
      expect(execution.attemptCount, 1);
      expect(delays, isEmpty);
      expect(execution.attempts.single.retryScheduled, isFalse);
      expect(
        execution.attempts.single.failureKind,
        AgentProviderTransportFailureKind.invalidResponse,
      );
    },
  );

  test('retrying agent provider adapter wraps send attempts', () async {
    final adapter = _FlakyAgentProviderAdapter();
    final telemetry =
        <AgentProviderRetryExecution<AgentProviderResponseEnvelope>>[];
    final telemetryRequestIds = <String>[];
    final retrying = RetryingAgentProviderAdapter(
      inner: adapter,
      retryExecutor: const AgentProviderRetryExecutor(
        policy: AgentProviderRetryPolicy(maxAttempts: 2),
      ),
      telemetrySink: (request, execution) {
        telemetryRequestIds.add(request.requestId);
        telemetry.add(execution);
      },
    );

    final response = await retrying.send(
      AgentProviderRequest(
        requestId: 'retry-request',
        profile: _profile(),
        context: _emptyContext(),
        userPrompt: 'Retry once.',
      ),
    );

    expect(retrying.adapterId, 'flaky:retrying');
    expect(adapter.calls, 2);
    expect(response.contentParts.single.text, 'retry ok');
    expect(telemetryRequestIds.single, 'retry-request');
    expect(telemetry.single.succeeded, isTrue);
    expect(telemetry.single.attemptCount, 2);
    expect(telemetry.single.attempts.first.retryScheduled, isTrue);
  });

  test('retrying agent provider adapter preserves streaming adapters', () async {
    final adapter = _FlakyStreamingAgentProviderAdapter();
    final telemetry =
        <AgentProviderRetryExecution<AgentProviderResponseEnvelope>>[];
    final retrying = RetryingAgentProviderAdapter(
      inner: adapter,
      retryExecutor: const AgentProviderRetryExecutor(
        policy: AgentProviderRetryPolicy(maxAttempts: 2),
      ),
      telemetrySink: (_, execution) {
        telemetry.add(execution);
      },
    );

    final events = await retrying
        .stream(
          AgentProviderRequest(
            requestId: 'retry-stream-request',
            profile: _profile(),
            context: _emptyContext(),
            userPrompt: 'Retry stream once.',
          ),
        )
        .toList();

    expect(retrying, isA<StreamingAgentProviderAdapter>());
    expect(adapter.streamCalls, 2);
    expect(adapter.sendCalls, 0);
    expect(events.map((event) => event.kind), <Object>[
      AgentProviderStreamEventKind.started,
      AgentProviderStreamEventKind.contentDelta,
      AgentProviderStreamEventKind.completed,
    ]);
    expect(telemetry.single.succeeded, isTrue);
    expect(telemetry.single.attemptCount, 2);
  });

  test(
    'hosted backend retry endpoints include reopen export and settings',
    () async {
      final sentPlans = <HostedBackendRetryEndpointPlan>[];
      final executor = HostedBackendRetryActionExecutor(
        transport: (plan) async {
          sentPlans.add(plan);
          return HostedBackendRetryActionResult.accepted(
            statusCode: 202,
            metadata: <String, Object?>{'path': plan.path},
          );
        },
      );
      final endpoints =
          HostedBackendRetryEndpointPlan.defaultControlPlaneEndpoints();
      final reopen = endpoints.singleWhere(
        (endpoint) =>
            endpoint.kind == HostedBackendRetryEndpointKind.reopenWorkspace,
      );
      final export = endpoints.singleWhere(
        (endpoint) =>
            endpoint.kind == HostedBackendRetryEndpointKind.exportWorkspace,
      );
      final settings = endpoints.singleWhere(
        (endpoint) =>
            endpoint.kind == HostedBackendRetryEndpointKind.openSettings,
      );

      final dispatch = await executor.execute(export);
      final metadata = const HostedBackendRetryRuntimeOutputBinding()
          .metadataFor(dispatch);

      expect(endpoints.map((endpoint) => endpoint.kind), contains(reopen.kind));
      expect(reopen.requiresConfirmation, isTrue);
      expect(export.path, '/api/vityo/hosted/v1/workspaces/export');
      expect(settings.settingsSectionId, 'agent-provider');
      expect(dispatch.accepted, isTrue);
      expect(
        sentPlans.single.kind,
        HostedBackendRetryEndpointKind.exportWorkspace,
      );
      expect(metadata['endpointKind'], 'export-workspace');
      expect(metadata['settingsSectionId'], isNull);
      expect(dispatch.toJson()['result'], isA<Map<String, Object?>>());
    },
  );
}

AgentPromptProfile _profile() {
  return const AgentPromptProfile(
    profileId: 'retry-test',
    displayName: 'Retry Test',
    systemPrompt: 'Use IDE context.',
    endpoint: AgentProviderEndpoint(
      route: AgentProviderRoute.webHosted,
      baseUrl: 'https://agent.example.test/v1',
      model: 'gpt-retry-test',
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

class _FlakyAgentProviderAdapter implements AgentProviderAdapter {
  int calls = 0;

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  String get adapterId => 'flaky';

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    calls += 1;
    if (calls == 1) {
      throw const AgentProviderTransportException(
        kind: AgentProviderTransportFailureKind.httpStatus,
        message: 'too many requests',
        statusCode: 429,
      );
    }
    return AgentProviderResponseEnvelope(
      requestId: request.requestId,
      role: 'assistant',
      contentParts: const <AgentContentPart>[
        AgentContentPart(kind: AgentContentPartKind.text, text: 'retry ok'),
      ],
      finishReason: 'stop',
    );
  }
}

class _FlakyStreamingAgentProviderAdapter
    implements StreamingAgentProviderAdapter {
  int streamCalls = 0;
  int sendCalls = 0;

  @override
  AgentProviderKind get kind => AgentProviderKind.cloudOpenAICompatible;

  @override
  String get adapterId => 'flaky-streaming';

  @override
  bool get supportsCodePatch => true;

  @override
  Future<AgentProviderResponseEnvelope> send(
    AgentProviderRequest request,
  ) async {
    sendCalls += 1;
    throw StateError('streaming retry should use stream');
  }

  @override
  Stream<AgentProviderStreamEvent> stream(AgentProviderRequest request) async* {
    streamCalls += 1;
    yield AgentProviderStreamEvent.started(request.requestId);
    if (streamCalls == 1) {
      yield AgentProviderStreamEvent.failed(
        requestId: request.requestId,
        message: 'stream timeout',
      );
      return;
    }
    yield AgentProviderStreamEvent.delta(
      requestId: request.requestId,
      text: 'retry stream ok',
    );
    yield AgentProviderStreamEvent.completed(requestId: request.requestId);
  }
}
