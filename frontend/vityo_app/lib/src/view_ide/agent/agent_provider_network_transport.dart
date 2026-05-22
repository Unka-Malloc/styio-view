import 'dart:async';
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

AgentProviderTransport createNetworkAgentProviderTransport({
  required NetworkManager networkManager,
  Duration timeout = const Duration(seconds: 30),
}) {
  if (networkManager is StreamingNetworkManager) {
    return StreamingNetworkAgentProviderTransport(
      networkManager: networkManager,
      timeout: timeout,
    );
  }
  return NetworkAgentProviderTransport(
    networkManager: networkManager,
    timeout: timeout,
  );
}

class StreamingNetworkAgentProviderTransport
    extends NetworkAgentProviderTransport
    implements StreamingAgentProviderTransport {
  StreamingNetworkAgentProviderTransport({
    required StreamingNetworkManager super.networkManager,
    super.timeout,
  });

  @override
  Stream<AgentProviderStreamEvent> postJsonStream({
    required String requestId,
    required Uri endpoint,
    required Map<String, String> headers,
    required Map<String, Object?> body,
  }) async* {
    final streamingNetworkManager = networkManager as StreamingNetworkManager;
    final cancellationToken = NetworkRequestCancellationToken();
    _activeCancellations[requestId] = cancellationToken;
    final decoder = _OpenAICompatibleSseDecoder(requestId: requestId);
    try {
      await for (final chunk in streamingNetworkManager.postJsonStream(
        endpoint,
        headers: headers,
        body: body,
        cancellationToken: cancellationToken,
        timeout: timeout,
      )) {
        if (!chunk.succeeded) {
          final failure = networkManager.failureForText(
            chunk.toTextResponse(),
            operation: 'agent.provider.postJsonStream',
            recoveryHint:
                'Check the configured streaming agent provider endpoint, network access, and credential reference.',
          );
          throw AgentProviderTransportException(
            kind: _providerFailureKindForNetwork(failure?.kind),
            message:
                failure?.message ??
                chunk.message ??
                'Agent provider stream failed.',
            statusCode: failure?.statusCode ?? chunk.statusCode,
            target: failure?.target ?? endpoint.toString(),
            operation: failure?.operation ?? 'agent.provider.postJsonStream',
            recoveryHint:
                failure?.recoveryHint ??
                'Check the configured streaming agent provider endpoint, network access, and credential reference.',
          );
        }
        for (final event in decoder.add(chunk.text)) {
          yield event;
        }
      }
      for (final event in decoder.close()) {
        yield event;
      }
    } on AgentProviderTransportException catch (error) {
      yield AgentProviderStreamEvent.failed(
        requestId: requestId,
        message: error.message,
        metadata: <String, Object?>{'failure': error.toJson()},
      );
    } on Object catch (error) {
      yield AgentProviderStreamEvent.failed(
        requestId: requestId,
        message: 'Agent provider stream failed: $error',
        metadata: <String, Object?>{
          'kind': AgentProviderTransportFailureKind.unknown.name,
        },
      );
    } finally {
      _activeCancellations.remove(requestId);
    }
  }
}

class _OpenAICompatibleSseDecoder {
  _OpenAICompatibleSseDecoder({required this.requestId});

  final String requestId;
  final StringBuffer _buffer = StringBuffer();
  var _completed = false;

  Iterable<AgentProviderStreamEvent> add(String chunk) sync* {
    if (chunk.isEmpty || _completed) {
      return;
    }
    _buffer.write(chunk);
    final text = _buffer.toString();
    final frames = text.split(RegExp(r'\r?\n\r?\n'));
    _buffer.clear();
    if (!text.endsWith('\n\n') && !text.endsWith('\r\n\r\n')) {
      _buffer.write(frames.removeLast());
    }
    for (final frame in frames) {
      yield* _eventsForFrame(frame);
    }
  }

  Iterable<AgentProviderStreamEvent> close() sync* {
    if (_completed) {
      return;
    }
    final tail = _buffer.toString().trim();
    _buffer.clear();
    if (tail.isNotEmpty) {
      yield* _eventsForFrame(tail);
    }
    if (!_completed) {
      _completed = true;
      yield AgentProviderStreamEvent.completed(
        requestId: requestId,
        metadata: const <String, Object?>{
          'finishReason': 'stream_complete',
          'streamTransport': 'network_sse',
        },
      );
    }
  }

  Iterable<AgentProviderStreamEvent> _eventsForFrame(String frame) sync* {
    final data = frame
        .split(RegExp(r'\r?\n'))
        .where((line) => line.startsWith('data:'))
        .map((line) => line.substring(5).trim())
        .where((line) => line.isNotEmpty)
        .join('\n');
    if (data.isEmpty) {
      return;
    }
    if (data == '[DONE]') {
      final event = _complete(<String, Object?>{
        'finishReason': 'stop',
        'streamTransport': 'network_sse',
      });
      if (event != null) {
        yield event;
      }
      return;
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(data);
    } on FormatException {
      yield AgentProviderStreamEvent.failed(
        requestId: requestId,
        message: 'Agent provider stream emitted invalid JSON SSE data.',
        metadata: <String, Object?>{
          'kind': AgentProviderTransportFailureKind.invalidResponse.name,
        },
      );
      _completed = true;
      return;
    }
    if (decoded is! Map) {
      return;
    }
    yield* _eventsForPayload(_objectMap(decoded));
  }

  Iterable<AgentProviderStreamEvent> _eventsForPayload(
    Map<String, Object?> payload,
  ) sync* {
    final responseType = payload['type'] as String?;
    if (responseType == 'response.output_text.delta') {
      final delta = payload['delta'];
      if (delta is String && delta.isNotEmpty) {
        yield AgentProviderStreamEvent.delta(requestId: requestId, text: delta);
      }
      return;
    }
    if (responseType == 'response.completed') {
      final response = _objectMap(payload['response']);
      final event = _complete(<String, Object?>{
        'finishReason': 'stop',
        'streamTransport': 'network_sse',
        if (response['usage'] is Map) 'usage': _objectMap(response['usage']),
      });
      if (event != null) {
        yield event;
      }
      return;
    }
    if (responseType == 'response.failed') {
      final error = _objectMap(payload['error']);
      yield AgentProviderStreamEvent.failed(
        requestId: requestId,
        message:
            (error['message'] as String?) ??
            'Agent provider response stream failed.',
        metadata: <String, Object?>{
          'kind': AgentProviderTransportFailureKind.invalidResponse.name,
          if (error.isNotEmpty) 'error': error,
        },
      );
      _completed = true;
      return;
    }

    final choices = payload['choices'];
    if (choices is! List) {
      return;
    }
    for (final choiceValue in choices) {
      final choice = _objectMap(choiceValue);
      final delta = _objectMap(choice['delta']);
      final content = delta['content'];
      if (content is String && content.isNotEmpty) {
        yield AgentProviderStreamEvent.delta(
          requestId: requestId,
          text: content,
        );
      }
      final finishReason = choice['finish_reason'] ?? choice['finishReason'];
      if (finishReason is String && finishReason.trim().isNotEmpty) {
        final event = _complete(<String, Object?>{
          'finishReason': finishReason.trim(),
          'streamTransport': 'network_sse',
          if (payload['usage'] is Map) 'usage': _objectMap(payload['usage']),
        });
        if (event != null) {
          yield event;
        }
      }
    }
  }

  AgentProviderStreamEvent? _complete(Map<String, Object?> metadata) {
    if (_completed) {
      return null;
    }
    _completed = true;
    return AgentProviderStreamEvent.completed(
      requestId: requestId,
      metadata: metadata,
    );
  }
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    return value.map(
      (key, value) => MapEntry<String, Object?>(key.toString(), value),
    );
  }
  return const <String, Object?>{};
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
