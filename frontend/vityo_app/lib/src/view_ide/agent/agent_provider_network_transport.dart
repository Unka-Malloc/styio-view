import 'dart:convert';

import '../environment/system_compatibility/network/network.dart';
import 'agent_provider_adapter.dart';

class NetworkAgentProviderTransport
    implements AgentProviderTransport, CancellableAgentProviderTransport {
  NetworkAgentProviderTransport({
    required this.networkManager,
    this.timeout = const Duration(seconds: 30),
  });

  final NetworkManager networkManager;
  final Duration timeout;
  final Map<String, NetworkRequestCancellationToken> _activeCancellations =
      <String, NetworkRequestCancellationToken>{};

  @override
  Future<Map<String, Object?>> postJson({
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return _postJson(endpoint: endpoint, headers: headers, body: body);
  }

  @override
  Future<Map<String, Object?>> postJsonCancellable({
    required String requestId,
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    return _postJson(
      requestId: requestId,
      endpoint: endpoint,
      headers: headers,
      body: body,
    );
  }

  @override
  void cancelRequest(String requestId) {
    _activeCancellations[requestId]?.cancel();
  }

  Future<Map<String, Object?>> _postJson({
    String? requestId,
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async {
    final cancellationToken = requestId == null
        ? null
        : NetworkRequestCancellationToken();
    if (requestId != null && cancellationToken != null) {
      _activeCancellations[requestId] = cancellationToken;
    }
    final response = await _postJsonResponse(
      endpoint,
      headers: headers,
      body: body,
      cancellationToken: cancellationToken,
    );
    if (requestId != null) {
      _activeCancellations.remove(requestId);
    }
    if (!response.succeeded) {
      final failure = networkManager.failureForText(
        response,
        operation: 'agent.provider.postJson',
        recoveryHint:
            'Check the configured agent provider endpoint, network access, and credential reference.',
      );
      throw AgentProviderTransportException(
        kind: _providerFailureKindForNetwork(failure?.kind),
        message:
            failure?.message ??
            response.message ??
            'Agent provider request failed.',
        statusCode: failure?.statusCode ?? response.statusCode,
        target: failure?.target ?? endpoint.toString(),
        operation: failure?.operation ?? 'agent.provider.postJson',
        recoveryHint:
            failure?.recoveryHint ??
            'Check the configured agent provider endpoint, network access, and credential reference.',
      );
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } on FormatException catch (error) {
      throw AgentProviderTransportException(
        kind: AgentProviderTransportFailureKind.invalidResponse,
        message: 'Agent provider response was not valid JSON: ${error.message}',
        statusCode: response.statusCode,
        target: endpoint.toString(),
        operation: 'agent.provider.postJson',
        recoveryHint:
            'Check that the configured agent provider returns an OpenAI-compatible JSON object.',
        cause: error,
      );
    }
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry<String, Object?>(key.toString(), value),
      );
    }
    throw AgentProviderTransportException(
      kind: AgentProviderTransportFailureKind.invalidResponse,
      message: 'Agent provider response must be a JSON object.',
      statusCode: response.statusCode,
      target: endpoint.toString(),
      operation: 'agent.provider.postJson',
      recoveryHint:
          'Check that the configured agent provider returns an OpenAI-compatible JSON object.',
    );
  }

  Future<NetworkTextResponse> _postJsonResponse(
    Uri endpoint, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    NetworkRequestCancellationToken? cancellationToken,
  }) {
    final cancellableNetworkManager =
        networkManager is CancellableNetworkManager
        ? networkManager as CancellableNetworkManager
        : null;
    if (cancellationToken != null && cancellableNetworkManager != null) {
      return cancellableNetworkManager.postJsonCancellable(
        endpoint,
        headers: headers,
        body: body,
        cancellationToken: cancellationToken,
        timeout: timeout,
      );
    }
    return networkManager.postJson(
      endpoint,
      headers: headers,
      body: body,
      timeout: timeout,
    );
  }
}

AgentProviderTransportFailureKind _providerFailureKindForNetwork(
  NetworkFailureKind? kind,
) {
  return switch (kind) {
    NetworkFailureKind.unsupported =>
      AgentProviderTransportFailureKind.unsupported,
    NetworkFailureKind.timeout => AgentProviderTransportFailureKind.timeout,
    NetworkFailureKind.cancelled => AgentProviderTransportFailureKind.cancelled,
    NetworkFailureKind.httpStatus =>
      AgentProviderTransportFailureKind.httpStatus,
    NetworkFailureKind.tlsFailure =>
      AgentProviderTransportFailureKind.tlsFailure,
    NetworkFailureKind.hostUnreachable =>
      AgentProviderTransportFailureKind.hostUnreachable,
    NetworkFailureKind.invalidUri =>
      AgentProviderTransportFailureKind.invalidResponse,
    NetworkFailureKind.unknownFailure ||
    null => AgentProviderTransportFailureKind.unknown,
  };
}
