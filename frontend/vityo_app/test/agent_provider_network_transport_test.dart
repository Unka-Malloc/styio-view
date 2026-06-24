import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_network_transport.dart';
import 'package:vityo_app/src/agent/agent_tool_call_lifecycle.dart';
import 'package:vityo_app/src/agent/agent_tool_call_stream_bridge.dart';
import 'package:vityo_app/src/view_ide/environment/system_compatibility/network/network.dart';

void main() {
  test(
    'network agent provider transport decodes JSON response object',
    () async {
      final network = _AgentNetworkManager(
        response: NetworkTextResponse(
          status: NetworkRequestStatus.succeeded,
          uri: _endpoint,
          statusCode: 200,
          body: '{"id":"chatcmpl-test","choices":[]}',
        ),
      );
      final transport = NetworkAgentProviderTransport(
        networkManager: network,
        timeout: const Duration(seconds: 7),
      );

      final decoded = await transport.postJson(
        endpoint: _endpoint,
        headers: const <String, String>{'Content-Type': 'application/json'},
        body: const <String, Object?>{'model': 'gpt-test'},
      );

      expect(decoded['id'], 'chatcmpl-test');
      expect(network.lastBody['model'], 'gpt-test');
      expect(network.lastTimeout, const Duration(seconds: 7));
    },
  );

  test(
    'network agent provider transport surfaces structured HTTP failure',
    () async {
      final network = _AgentNetworkManager(
        response: NetworkTextResponse(
          status: NetworkRequestStatus.failed,
          uri: _endpoint,
          statusCode: 500,
          body: '',
          message: 'provider failed',
        ),
      );
      final transport = NetworkAgentProviderTransport(networkManager: network);

      expect(
        () => transport.postJson(
          endpoint: _endpoint,
          headers: const <String, String>{},
          body: const <String, Object?>{},
        ),
        throwsA(
          isA<AgentProviderTransportException>()
              .having(
                (error) => error.kind,
                'kind',
                AgentProviderTransportFailureKind.httpStatus,
              )
              .having((error) => error.statusCode, 'statusCode', 500)
              .having(
                (error) => error.recoveryHint,
                'recoveryHint',
                contains('endpoint'),
              ),
        ),
      );
    },
  );

  test(
    'network agent provider transport surfaces structured timeout',
    () async {
      final network = _AgentNetworkManager(
        response: NetworkTextResponse(
          status: NetworkRequestStatus.timedOut,
          uri: _endpoint,
          statusCode: null,
          body: '',
          message: 'provider timed out',
        ),
      );
      final transport = NetworkAgentProviderTransport(networkManager: network);

      expect(
        () => transport.postJson(
          endpoint: _endpoint,
          headers: const <String, String>{},
          body: const <String, Object?>{},
        ),
        throwsA(
          isA<AgentProviderTransportException>().having(
            (error) => error.kind,
            'kind',
            AgentProviderTransportFailureKind.timeout,
          ),
        ),
      );
    },
  );

  test(
    'network agent provider transport rejects invalid JSON response',
    () async {
      final network = _AgentNetworkManager(
        response: NetworkTextResponse(
          status: NetworkRequestStatus.succeeded,
          uri: _endpoint,
          statusCode: 200,
          body: 'not json',
        ),
      );
      final transport = NetworkAgentProviderTransport(networkManager: network);

      expect(
        () => transport.postJson(
          endpoint: _endpoint,
          headers: const <String, String>{},
          body: const <String, Object?>{},
        ),
        throwsA(
          isA<AgentProviderTransportException>().having(
            (error) => error.kind,
            'kind',
            AgentProviderTransportFailureKind.invalidResponse,
          ),
        ),
      );
    },
  );

  test(
    'network agent provider transport rejects non-object JSON response',
    () async {
      final network = _AgentNetworkManager(
        response: NetworkTextResponse(
          status: NetworkRequestStatus.succeeded,
          uri: _endpoint,
          statusCode: 200,
          body: '[]',
        ),
      );
      final transport = NetworkAgentProviderTransport(networkManager: network);

      expect(
        () => transport.postJson(
          endpoint: _endpoint,
          headers: const <String, String>{},
          body: const <String, Object?>{},
        ),
        throwsA(
          isA<AgentProviderTransportException>().having(
            (error) => error.kind,
            'kind',
            AgentProviderTransportFailureKind.invalidResponse,
          ),
        ),
      );
    },
  );

  test(
    'network agent provider transport cancels active request token',
    () async {
      final network = _CancellableAgentNetworkManager();
      final transport = NetworkAgentProviderTransport(networkManager: network);

      final pending = transport.postJsonCancellable(
        requestId: 'agent-request-cancel',
        endpoint: _endpoint,
        headers: const <String, String>{},
        body: const <String, Object?>{},
      );
      expect(network.lastCancellationToken, isNotNull);

      transport.cancelRequest('agent-request-cancel');

      await expectLater(
        pending,
        throwsA(
          isA<AgentProviderTransportException>().having(
            (error) => error.kind,
            'kind',
            AgentProviderTransportFailureKind.cancelled,
          ),
        ),
      );
    },
  );

  test(
    'network agent provider transport streams OpenAI-compatible SSE chunks',
    () async {
      final network = _StreamingAgentNetworkManager(
        chunks: const <String>[
          'data: {"choices":[{"delta":{"content":"Plan "}}]}\n\n',
          'data: {"choices":[{"delta":{"content":"ready."},"finish_reason":"stop"}]}\n\n',
          'data: [DONE]\n\n',
        ],
      );
      final transport = createNetworkAgentProviderTransport(
        networkManager: network,
        timeout: const Duration(seconds: 9),
      );

      final events = await (transport as StreamingAgentProviderTransport)
          .postJsonStream(
            requestId: 'agent-stream-network',
            endpoint: _endpoint,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: const <String, Object?>{'model': 'gpt-test', 'stream': true},
          )
          .toList();

      expect(transport, isA<StreamingNetworkAgentProviderTransport>());
      expect(events.map((event) => event.kind), <AgentProviderStreamEventKind>[
        AgentProviderStreamEventKind.contentDelta,
        AgentProviderStreamEventKind.contentDelta,
        AgentProviderStreamEventKind.completed,
      ]);
      expect(events[0].deltaText, 'Plan ');
      expect(events[1].deltaText, 'ready.');
      expect(events.last.metadata['finishReason'], 'stop');
      expect(events.last.metadata['streamTransport'], 'network_sse');
      expect(network.lastBody['stream'], isTrue);
      expect(network.lastTimeout, const Duration(seconds: 9));
    },
  );

  test(
    'network agent provider transport streams Chat Completions tool calls',
    () async {
      final network = _StreamingAgentNetworkManager(
        chunks: const <String>[
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call-read","function":{"name":"readWorkspaceFile","arguments":"{\\"path\\""}}]}}]}\n\n',
          'data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":":\\"main.styio\\"}"}}]},"finish_reason":"tool_calls"}]}\n\n',
        ],
      );
      final transport = createNetworkAgentProviderTransport(
        networkManager: network,
      );

      final events = await (transport as StreamingAgentProviderTransport)
          .postJsonStream(
            requestId: 'agent-stream-chat-tool',
            endpoint: _endpoint,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: const <String, Object?>{'model': 'gpt-test', 'stream': true},
          )
          .toList();
      final toolEvents = const AgentProviderToolCallStreamBridge().eventsFor(
        events,
      );

      expect(toolEvents.map((event) => event.kind), <AgentToolCallEventKind>[
        AgentToolCallEventKind.inputStart,
        AgentToolCallEventKind.inputDelta,
        AgentToolCallEventKind.inputDelta,
        AgentToolCallEventKind.inputEnd,
        AgentToolCallEventKind.callStarted,
      ]);
      expect(toolEvents.last.callId, 'call-read');
      expect(toolEvents.last.toolId, 'readWorkspaceFile');
      expect(toolEvents.last.input, '{"path":"main.styio"}');
      expect(events.last.kind, AgentProviderStreamEventKind.completed);
      expect(events.last.metadata['finishReason'], 'tool_calls');
    },
  );

  test(
    'network agent provider transport streams OpenAI Responses deltas',
    () async {
      final network = _StreamingAgentNetworkManager(
        chunks: const <String>[
          'data: {"type":"response.output_text.delta","delta":"Patch "}\n\n',
          'data: {"type":"response.output_text.delta","delta":"done."}\n\n',
          'data: {"type":"response.completed","response":{"usage":{"outputTokens":2}}}\n\n',
        ],
      );
      final transport = createNetworkAgentProviderTransport(
        networkManager: network,
      );

      final events = await (transport as StreamingAgentProviderTransport)
          .postJsonStream(
            requestId: 'agent-stream-responses-network',
            endpoint: _endpoint,
            headers: const <String, String>{'Content-Type': 'application/json'},
            body: const <String, Object?>{'model': 'gpt-5.3-codex-spark'},
          )
          .toList();

      expect(events.map((event) => event.deltaText).join(), 'Patch done.');
      expect(events.last.kind, AgentProviderStreamEventKind.completed);
      expect(events.last.metadata['usage'], <String, Object?>{
        'outputTokens': 2,
      });
    },
  );

  test('network agent provider transport streams Responses function calls', () async {
    final network = _StreamingAgentNetworkManager(
      chunks: const <String>[
        'data: {"type":"response.output_item.added","output_index":0,"item":{"id":"fc-1","type":"function_call","call_id":"call-write","name":"writeWorkspaceFile","arguments":""}}\n\n',
        'data: {"type":"response.function_call_arguments.delta","item_id":"fc-1","output_index":0,"delta":"{\\"path\\":\\"main.styio\\""}\n\n',
        'data: {"type":"response.function_call_arguments.delta","item_id":"fc-1","output_index":0,"delta":",\\"text\\":\\"value := 2\\"}"}\n\n',
        'data: {"type":"response.function_call_arguments.done","item_id":"fc-1","output_index":0,"arguments":"{\\"path\\":\\"main.styio\\",\\"text\\":\\"value := 2\\"}"}\n\n',
        'data: {"type":"response.completed","response":{"usage":{"outputTokens":2}}}\n\n',
      ],
    );
    final transport = createNetworkAgentProviderTransport(
      networkManager: network,
    );

    final events = await (transport as StreamingAgentProviderTransport)
        .postJsonStream(
          requestId: 'agent-stream-responses-tool',
          endpoint: _endpoint,
          headers: const <String, String>{'Content-Type': 'application/json'},
          body: const <String, Object?>{'model': 'gpt-5.3-codex-spark'},
        )
        .toList();
    final toolEvents = const AgentProviderToolCallStreamBridge().eventsFor(
      events,
    );

    expect(toolEvents.map((event) => event.kind), <AgentToolCallEventKind>[
      AgentToolCallEventKind.inputStart,
      AgentToolCallEventKind.inputDelta,
      AgentToolCallEventKind.inputDelta,
      AgentToolCallEventKind.inputEnd,
      AgentToolCallEventKind.callStarted,
    ]);
    expect(toolEvents.last.callId, 'call-write');
    expect(toolEvents.last.toolId, 'writeWorkspaceFile');
    expect(toolEvents.last.input, '{"path":"main.styio","text":"value := 2"}');
    expect(events.last.kind, AgentProviderStreamEventKind.completed);
  });
}

final _endpoint = Uri.parse('https://agent.example.test/chat/completions');

class _AgentNetworkManager implements NetworkManager {
  _AgentNetworkManager({required this.response});

  final NetworkTextResponse response;
  Map<String, Object?> lastBody = const <String, Object?>{};
  Duration? lastTimeout;

  @override
  NetworkFacts get facts => NetworkFacts.linuxDebianArm();

  @override
  NetworkCompatibility get compatibility => NetworkAdapter(facts).adapt();

  @override
  Future<NetworkTextResponse> getText(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return NetworkTextResponse(
      status: NetworkRequestStatus.blocked,
      uri: _endpoint,
      statusCode: null,
      body: '',
    );
  }

  @override
  Future<NetworkTextResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    lastBody = body;
    lastTimeout = timeout;
    return response;
  }

  @override
  Future<NetworkBinaryResponse> getBytes(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return NetworkBinaryResponse(
      status: NetworkRequestStatus.blocked,
      uri: _endpoint,
      statusCode: null,
      bytes: <int>[],
    );
  }

  @override
  NetworkOperationFailure? failureForText(
    NetworkTextResponse response, {
    String operation = 'network.getText',
    String? recoveryHint,
  }) {
    return const NetworkFailureClassifier(sourceManager: 'test').classify(
      status: response.status,
      uri: response.uri,
      statusCode: response.statusCode,
      message: response.message,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }

  @override
  NetworkOperationFailure? failureForBytes(
    NetworkBinaryResponse response, {
    String operation = 'network.getBytes',
    String? recoveryHint,
  }) {
    return const NetworkFailureClassifier(sourceManager: 'test').classify(
      status: response.status,
      uri: response.uri,
      statusCode: response.statusCode,
      message: response.message,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }
}

class _StreamingAgentNetworkManager extends _AgentNetworkManager
    implements StreamingNetworkManager {
  _StreamingAgentNetworkManager({required this.chunks})
    : super(
        response: NetworkTextResponse(
          status: NetworkRequestStatus.succeeded,
          uri: _endpoint,
          statusCode: 200,
          body: '{}',
        ),
      );

  final List<String> chunks;

  @override
  Stream<NetworkTextStreamChunk> postJsonStream(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    NetworkRequestCancellationToken? cancellationToken,
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    lastBody = body;
    lastTimeout = timeout;
    for (final chunk in chunks) {
      yield NetworkTextStreamChunk(
        status: NetworkRequestStatus.succeeded,
        uri: uri,
        statusCode: 200,
        text: chunk,
      );
    }
  }
}

class _CancellableAgentNetworkManager
    implements NetworkManager, CancellableNetworkManager {
  NetworkRequestCancellationToken? lastCancellationToken;

  @override
  NetworkFacts get facts => NetworkFacts.linuxDebianArm();

  @override
  NetworkCompatibility get compatibility => NetworkAdapter(facts).adapt();

  @override
  Future<NetworkTextResponse> getText(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return NetworkTextResponse(
      status: NetworkRequestStatus.blocked,
      uri: uri,
      statusCode: null,
      body: '',
    );
  }

  @override
  Future<NetworkTextResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return NetworkTextResponse(
      status: NetworkRequestStatus.succeeded,
      uri: uri,
      statusCode: 200,
      body: '{"id":"unused","choices":[]}',
    );
  }

  @override
  Future<NetworkTextResponse> postJsonCancellable(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    required NetworkRequestCancellationToken cancellationToken,
    Duration timeout = const Duration(seconds: 10),
  }) {
    lastCancellationToken = cancellationToken;
    final completer = Completer<NetworkTextResponse>();
    cancellationToken.listen(() {
      if (!completer.isCompleted) {
        completer.complete(
          NetworkTextResponse(
            status: NetworkRequestStatus.cancelled,
            uri: uri,
            statusCode: null,
            body: '',
            message: 'Network request cancelled.',
          ),
        );
      }
    });
    return completer.future;
  }

  @override
  Future<NetworkBinaryResponse> getBytes(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return NetworkBinaryResponse(
      status: NetworkRequestStatus.blocked,
      uri: uri,
      statusCode: null,
      bytes: const <int>[],
    );
  }

  @override
  NetworkOperationFailure? failureForText(
    NetworkTextResponse response, {
    String operation = 'network.getText',
    String? recoveryHint,
  }) {
    return const NetworkFailureClassifier(
      sourceManager: 'test-cancellable',
    ).classify(
      status: response.status,
      uri: response.uri,
      statusCode: response.statusCode,
      message: response.message,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }

  @override
  NetworkOperationFailure? failureForBytes(
    NetworkBinaryResponse response, {
    String operation = 'network.getBytes',
    String? recoveryHint,
  }) {
    return const NetworkFailureClassifier(
      sourceManager: 'test-cancellable',
    ).classify(
      status: response.status,
      uri: response.uri,
      statusCode: response.statusCode,
      message: response.message,
      operation: operation,
      recoveryHint: recoveryHint,
    );
  }
}
