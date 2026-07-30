import 'dart:io';

import '../platform_adapter/platform_adapter.dart';
import '../platform_context/platform_context.dart';
import 'local_service_adapter.dart';
import 'local_service_facts.dart';
import 'local_service_manager.dart';
import 'local_service_prober.dart';
import 'local_service_prober_io.dart';

Future<LocalServiceManager> createPlatformLocalServiceManager({
  LocalServiceProber? prober,
  PlatformContextSnapshot? platformContext,
}) async {
  final adapter = platformContext == null
      ? null
      : PlatformAdapter(platformContext);
  final facts =
      adapter?.context.localService ??
      await (prober ?? const LocalLoopbackServiceProber()).probe();
  return LoopbackLocalServiceManager(
    facts: facts,
    adapter: adapter?.localServiceAdapter,
  );
}

class LoopbackLocalServiceManager implements LocalServiceManager {
  LoopbackLocalServiceManager({
    required this.facts,
    LocalServiceAdapter? adapter,
  }) : compatibility = (adapter ?? LocalServiceAdapter(facts)).adapt();
  factory LoopbackLocalServiceManager.linuxDebianArmForTest() =>
      LoopbackLocalServiceManager(facts: LocalServiceFacts.linuxDebianArm());
  @override
  final LocalServiceFacts facts;
  @override
  final LocalServiceCompatibility compatibility;
  @override
  LocalServiceOperationFailure classifyFailure(
    Object error, {
    required String operation,
    required String target,
    String? recoveryHint,
  }) {
    return const LocalServiceFailureClassifier(
      sourceManager: 'LoopbackLocalServiceManager',
      platformFailureKindResolver: _loopbackLocalServiceFailureKind,
    ).classify(
      error,
      operation: operation,
      target: target,
      recoveryHint: recoveryHint,
    );
  }

  @override
  Future<LocalServiceHandle> startHttpTextService(
    LocalHttpServiceRequest request,
  ) async {
    if (!compatibility.supportsLoopbackHttpServer) {
      throw UnsupportedError('Loopback HTTP services are not available.');
    }
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((httpRequest) {
      if (httpRequest.uri.path != request.path) {
        httpRequest.response.statusCode = HttpStatus.notFound;
        httpRequest.response.write('not found');
      } else {
        httpRequest.response.statusCode = HttpStatus.ok;
        httpRequest.response.write(request.responseText);
      }
      httpRequest.response.close();
    });
    return _LoopbackLocalServiceHandle(
      server,
      Uri.parse('http://${server.address.host}:${server.port}${request.path}'),
    );
  }
}

LocalServiceFailureKind? _loopbackLocalServiceFailureKind(Object error) {
  if (error is! SocketException) {
    return null;
  }
  return switch (error.osError?.errorCode) {
    13 => LocalServiceFailureKind.permissionDenied,
    48 || 98 => LocalServiceFailureKind.portUnavailable,
    _ => LocalServiceFailureKind.bindFailed,
  };
}

class _LoopbackLocalServiceHandle implements LocalServiceHandle {
  const _LoopbackLocalServiceHandle(this._server, this.uri);
  final HttpServer _server;
  @override
  final Uri uri;
  @override
  Future<void> close() => _server.close(force: true);
}
