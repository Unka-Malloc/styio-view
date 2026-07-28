import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../platform_context/platform_context.dart';
import 'network_adapter.dart';
import 'network_facts.dart';
import 'network_manager.dart';
import 'network_prober.dart';
import 'network_prober_web.dart';

Future<NetworkManager> createPlatformNetworkManager({
  NetworkProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  final facts =
      platformContext?.network ??
      await (prober ?? const WebNetworkProber()).probe();
  return LocalNetworkManager(facts: facts);
}

class LocalNetworkManager implements NetworkManager {
  LocalNetworkManager({required this.facts, NetworkAdapter? adapter})
    : compatibility = (adapter ?? NetworkAdapter(facts)).adapt();

  factory LocalNetworkManager.linuxDebianArmForTest() {
    return LocalNetworkManager(facts: NetworkFacts.linuxDebianArm());
  }

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
    return const NetworkFailureClassifier(sourceManager: 'WebNetworkManager')
        .classify(
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
    return const NetworkFailureClassifier(sourceManager: 'WebNetworkManager')
        .classify(
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
  }) {
    return _requestText(uri, method: 'GET', timeout: timeout);
  }

  @override
  Future<NetworkTextResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 10),
  }) {
    return _requestText(
      uri,
      method: 'POST',
      headers: <String, String>{
        'Content-Type': 'application/json',
        ...headers,
      },
      body: jsonEncode(body),
      timeout: timeout,
    );
  }

  @override
  Future<NetworkBinaryResponse> getBytes(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final response = await getText(uri, timeout: timeout);
    return NetworkBinaryResponse(
      status: response.status,
      uri: response.uri,
      statusCode: response.statusCode,
      bytes: response.succeeded ? utf8.encode(response.body) : const <int>[],
      message: response.message,
    );
  }

  Future<NetworkTextResponse> _requestText(
    Uri uri, {
    required String method,
    Map<String, String> headers = const <String, String>{},
    String? body,
    required Duration timeout,
  }) async {
    if (!compatibility.supportsHttpClient) {
      return NetworkTextResponse(
        status: NetworkRequestStatus.blocked,
        uri: uri,
        statusCode: null,
        body: '',
        message: 'Browser fetch is not available.',
      );
    }
    try {
      final response = await web.window
          .fetch(
            uri.toString().toJS,
            web.RequestInit(
              method: method,
              headers: _headers(headers),
              body: body?.toJS,
            ),
          )
          .toDart
          .timeout(timeout);
      final responseText = (await response.text().toDart).toDart;
      return NetworkTextResponse(
        status: response.ok
            ? NetworkRequestStatus.succeeded
            : NetworkRequestStatus.failed,
        uri: uri,
        statusCode: response.status,
        body: responseText,
        message: response.ok
            ? null
            : '${response.status} ${response.statusText}',
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
      return NetworkTextResponse(
        status: NetworkRequestStatus.failed,
        uri: uri,
        statusCode: null,
        body: '',
        message: error.toString(),
      );
    }
  }

  web.Headers _headers(Map<String, String> headers) {
    final result = web.Headers();
    for (final entry in headers.entries) {
      result.set(entry.key, entry.value);
    }
    return result;
  }
}
