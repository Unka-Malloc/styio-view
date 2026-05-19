import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/agent/agent_provider_adapter.dart';
import 'package:vityo_app/src/agent/agent_provider_network_transport.dart';
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
