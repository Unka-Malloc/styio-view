import 'dart:async';
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
  final adapter = platformContext == null ? null : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.network ?? await (prober ?? const LocalNetworkProber()).probe();
  return LocalNetworkManager(facts: facts, adapter: adapter?.networkAdapter);
}

class LocalNetworkManager implements NetworkManager {
  LocalNetworkManager({required this.facts, NetworkAdapter? adapter}) : compatibility = (adapter ?? NetworkAdapter(facts)).adapt();
  factory LocalNetworkManager.linuxDebianArmForTest() => LocalNetworkManager(facts: NetworkFacts.linuxDebianArm());
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
  Future<NetworkTextResponse> getText(Uri uri, {Duration timeout = const Duration(seconds: 10)}) async {
    final response = await getBytes(uri, timeout: timeout);
    return NetworkTextResponse(status: response.status, uri: response.uri, statusCode: response.statusCode, body: response.succeeded ? const SystemEncoding().decode(response.bytes) : '', message: response.message);
  }

  @override
  Future<NetworkBinaryResponse> getBytes(Uri uri, {Duration timeout = const Duration(seconds: 10)}) async {
    if (!compatibility.supportsHttpClient) return NetworkBinaryResponse(status: NetworkRequestStatus.blocked, uri: uri, statusCode: null, bytes: const <int>[], message: 'HTTP client is not available.');
    final client = HttpClient();
    try {
      final request = await client.getUrl(uri).timeout(timeout);
      final response = await request.close().timeout(timeout);
      final bytes = await response.fold<List<int>>(<int>[], (buffer, chunk) {
        buffer.addAll(chunk);
        return buffer;
      }).timeout(timeout);
      return NetworkBinaryResponse(status: response.statusCode >= 200 && response.statusCode < 400 ? NetworkRequestStatus.succeeded : NetworkRequestStatus.failed, uri: uri, statusCode: response.statusCode, bytes: bytes);
    } on TimeoutException {
      return NetworkBinaryResponse(status: NetworkRequestStatus.timedOut, uri: uri, statusCode: null, bytes: const <int>[], message: 'Network request timed out.');
    } on Object catch (error) {
      return NetworkBinaryResponse(status: NetworkRequestStatus.failed, uri: uri, statusCode: null, bytes: const <int>[], message: error.toString());
    } finally {
      client.close(force: true);
    }
  }
}
