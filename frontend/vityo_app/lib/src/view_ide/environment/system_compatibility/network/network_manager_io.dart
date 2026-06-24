import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../platform_adapter/platform_adapter.dart';
import '../platform_context/platform_context.dart';
import 'network_adapter.dart';
import 'network_facts.dart';
import 'network_manager.dart';
import 'network_prober.dart';
import 'network_prober_io.dart';

Future<NetworkManager> createPlatformNetworkManager({
  NetworkProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  final adapter = platformContext == null
      ? null
      : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.network ??
      await (prober ?? const LocalNetworkProber()).probe();
  return LocalNetworkManager(facts: facts, adapter: adapter?.networkAdapter);
}

class LocalNetworkManager
    implements CancellableNetworkManager, StreamingNetworkManager {
  LocalNetworkManager({required this.facts, NetworkAdapter? adapter})
    : compatibility = (adapter ?? NetworkAdapter(facts)).adapt();
  factory LocalNetworkManager.linuxDebianArmForTest() =>
      LocalNetworkManager(facts: NetworkFacts.linuxDebianArm());
  @override
  final NetworkFacts facts;
  @override
  final NetworkCompatibility compatibility;
  @override
  NetworkOperationFailure? failureForText(
    NetworkTextResponse response, {
    String operation = 'network.getText',
    String? recoveryHint,
  }) {
    return const NetworkFailureClassifier(
      sourceManager: 'LocalNetworkManager',
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
      sourceManager: 'LocalNetworkManager',
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
  Future<NetworkTextResponse> getText(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final response = await getBytes(uri, timeout: timeout);
    return NetworkTextResponse(
      status: response.status,
      uri: response.uri,
      statusCode: response.statusCode,
      body: response.succeeded
          ? const SystemEncoding().decode(response.bytes)
          : '',
      message: response.message,
    );
  }

  @override
  Future<NetworkTextResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return _postJson(uri, headers: headers, body: body, timeout: timeout);
  }

  @override
  Future<NetworkTextResponse> postJsonCancellable(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    required NetworkRequestCancellationToken cancellationToken,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    return _postJson(
      uri,
      headers: headers,
      body: body,
      timeout: timeout,
      cancellationToken: cancellationToken,
    );
  }

  Future<NetworkTextResponse> _postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    required Duration timeout,
    NetworkRequestCancellationToken? cancellationToken,
  }) async {
    if (!compatibility.supportsHttpClient) {
      return NetworkTextResponse(
        status: NetworkRequestStatus.blocked,
        uri: uri,
        statusCode: null,
        body: '',
        message: 'HTTP client is not available.',
      );
    }
    if (cancellationToken?.isCancelled ?? false) {
      return NetworkTextResponse(
        status: NetworkRequestStatus.cancelled,
        uri: uri,
        statusCode: null,
        body: '',
        message: 'Network request cancelled.',
      );
    }
    final client = HttpClient();
    NetworkRequestCancellationSubscription? cancellationSubscription;
    try {
      cancellationSubscription = cancellationToken?.listen(() {
        client.close(force: true);
      });
      cancellationToken?.throwIfCancelled();
      final request = await client.postUrl(uri).timeout(timeout);
      cancellationToken?.throwIfCancelled();
      headers.forEach(request.headers.set);
      final encoded = utf8.encode(jsonEncode(body));
      request.headers.contentLength = encoded.length;
      request.add(encoded);
      final response = await request.close().timeout(timeout);
      cancellationToken?.throwIfCancelled();
      final bytes = await response
          .fold<List<int>>(<int>[], (buffer, chunk) {
            buffer.addAll(chunk);
            return buffer;
          })
          .timeout(timeout);
      cancellationToken?.throwIfCancelled();
      final status = response.statusCode >= 200 && response.statusCode < 400
          ? NetworkRequestStatus.succeeded
          : NetworkRequestStatus.failed;
      return NetworkTextResponse(
        status: status,
        uri: uri,
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
      );
    } on NetworkRequestCancelledException {
      return NetworkTextResponse(
        status: NetworkRequestStatus.cancelled,
        uri: uri,
        statusCode: null,
        body: '',
        message: 'Network request cancelled.',
      );
    } on TimeoutException {
      return NetworkTextResponse(
        status: NetworkRequestStatus.timedOut,
        uri: uri,
        statusCode: null,
        body: '',
        message: 'Network request timed out.',
      );
    } on Object catch (error) {
      if (cancellationToken?.isCancelled ?? false) {
        return NetworkTextResponse(
          status: NetworkRequestStatus.cancelled,
          uri: uri,
          statusCode: null,
          body: '',
          message: 'Network request cancelled.',
        );
      }
      return NetworkTextResponse(
        status: NetworkRequestStatus.failed,
        uri: uri,
        statusCode: null,
        body: '',
        message: error.toString(),
      );
    } finally {
      cancellationSubscription?.cancel();
      client.close(force: true);
    }
  }

  @override
  Stream<NetworkTextStreamChunk> postJsonStream(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    NetworkRequestCancellationToken? cancellationToken,
    Duration timeout = const Duration(seconds: 10),
  }) async* {
    if (!compatibility.supportsHttpClient) {
      yield NetworkTextStreamChunk(
        status: NetworkRequestStatus.blocked,
        uri: uri,
        statusCode: null,
        text: '',
        message: 'HTTP client is not available.',
      );
      return;
    }
    if (cancellationToken?.isCancelled ?? false) {
      yield NetworkTextStreamChunk(
        status: NetworkRequestStatus.cancelled,
        uri: uri,
        statusCode: null,
        text: '',
        message: 'Network request cancelled.',
      );
      return;
    }
    final client = HttpClient();
    NetworkRequestCancellationSubscription? cancellationSubscription;
    try {
      cancellationSubscription = cancellationToken?.listen(() {
        client.close(force: true);
      });
      cancellationToken?.throwIfCancelled();
      final request = await client.postUrl(uri).timeout(timeout);
      cancellationToken?.throwIfCancelled();
      headers.forEach(request.headers.set);
      final encoded = utf8.encode(jsonEncode(body));
      request.headers.contentLength = encoded.length;
      request.add(encoded);
      final response = await request.close().timeout(timeout);
      cancellationToken?.throwIfCancelled();
      final succeeded = response.statusCode >= 200 && response.statusCode < 400;
      if (!succeeded) {
        final bytes = await response
            .fold<List<int>>(<int>[], (buffer, chunk) {
              buffer.addAll(chunk);
              return buffer;
            })
            .timeout(timeout);
        yield NetworkTextStreamChunk(
          status: NetworkRequestStatus.failed,
          uri: uri,
          statusCode: response.statusCode,
          text: utf8.decode(bytes),
          message: '${response.statusCode} ${response.reasonPhrase}',
        );
        return;
      }
      await for (final chunk
          in response.transform(utf8.decoder).timeout(timeout)) {
        cancellationToken?.throwIfCancelled();
        if (chunk.isEmpty) {
          continue;
        }
        yield NetworkTextStreamChunk(
          status: NetworkRequestStatus.succeeded,
          uri: uri,
          statusCode: response.statusCode,
          text: chunk,
        );
      }
      cancellationToken?.throwIfCancelled();
    } on NetworkRequestCancelledException {
      yield NetworkTextStreamChunk(
        status: NetworkRequestStatus.cancelled,
        uri: uri,
        statusCode: null,
        text: '',
        message: 'Network request cancelled.',
      );
    } on TimeoutException {
      yield NetworkTextStreamChunk(
        status: NetworkRequestStatus.timedOut,
        uri: uri,
        statusCode: null,
        text: '',
        message: 'Network request timed out.',
      );
    } on Object catch (error) {
      final cancelled = cancellationToken?.isCancelled ?? false;
      yield NetworkTextStreamChunk(
        status: cancelled
            ? NetworkRequestStatus.cancelled
            : NetworkRequestStatus.failed,
        uri: uri,
        statusCode: null,
        text: '',
        message: cancelled ? 'Network request cancelled.' : error.toString(),
      );
    } finally {
      cancellationSubscription?.cancel();
      client.close(force: true);
    }
  }

  @override
  Future<NetworkBinaryResponse> getBytes(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (!compatibility.supportsHttpClient) {
      return NetworkBinaryResponse(
        status: NetworkRequestStatus.blocked,
        uri: uri,
        statusCode: null,
        bytes: const <int>[],
        message: 'HTTP client is not available.',
      );
    }
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final bytes = await response
          .fold<List<int>>(<int>[], (buffer, chunk) {
            buffer.addAll(chunk);
            return buffer;
          })
          .timeout(timeout);
      return NetworkBinaryResponse(
        status: response.statusCode >= 200 && response.statusCode < 400
            ? NetworkRequestStatus.succeeded
            : NetworkRequestStatus.failed,
        uri: uri,
        statusCode: response.statusCode,
        bytes: bytes,
      );
    } on TimeoutException {
      return NetworkBinaryResponse(
        status: NetworkRequestStatus.timedOut,
        uri: uri,
        statusCode: null,
        bytes: const <int>[],
        message: 'Network request timed out.',
      );
    } on Object catch (error) {
      return NetworkBinaryResponse(
        status: NetworkRequestStatus.failed,
        uri: uri,
        statusCode: null,
        bytes: const <int>[],
        message: error.toString(),
      );
    } finally {
      client.close(force: true);
    }
  }
}
