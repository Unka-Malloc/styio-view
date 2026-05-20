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
    final retrying = RetryingAgentProviderAdapter(
      inner: adapter,
      retryExecutor: const AgentProviderRetryExecutor(
        policy: AgentProviderRetryPolicy(maxAttempts: 2),
      ),
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
  });
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
