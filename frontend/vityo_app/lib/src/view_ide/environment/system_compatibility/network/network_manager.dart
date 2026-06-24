import 'network_adapter.dart';
import 'network_facts.dart';

enum NetworkRequestStatus { succeeded, failed, timedOut, blocked, cancelled }

enum NetworkFailureKind {
  unsupported,
  timeout,
  cancelled,
  httpStatus,
  tlsFailure,
  hostUnreachable,
  invalidUri,
  unknownFailure,
}

class NetworkOperationFailure {
  const NetworkOperationFailure({
    required this.kind,
    required this.operation,
    required this.target,
    required this.sourceManager,
    required this.message,
    this.statusCode,
    this.recoveryHint,
  });

  final NetworkFailureKind kind;
  final String operation;
  final String target;
  final String sourceManager;
  final String message;
  final int? statusCode;
  final String? recoveryHint;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'operation': operation,
      'target': target,
      'sourceManager': sourceManager,
      if (statusCode != null) 'statusCode': statusCode,
      'message': message,
      if (recoveryHint != null) 'recoveryHint': recoveryHint,
    };
  }
}

typedef NetworkCancellationCallback = void Function();

class NetworkRequestCancellationSubscription {
  NetworkRequestCancellationSubscription(this._cancel);

  final NetworkCancellationCallback _cancel;
  var _cancelled = false;

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    _cancel();
  }
}

class NetworkRequestCancellationToken {
  final List<NetworkCancellationCallback> _callbacks =
      <NetworkCancellationCallback>[];
  var _cancelled = false;

  bool get isCancelled => _cancelled;

  NetworkRequestCancellationSubscription listen(
    NetworkCancellationCallback callback,
  ) {
    if (_cancelled) {
      callback();
      return NetworkRequestCancellationSubscription(() {});
    }
    _callbacks.add(callback);
    return NetworkRequestCancellationSubscription(() {
      _callbacks.remove(callback);
    });
  }

  void cancel() {
    if (_cancelled) {
      return;
    }
    _cancelled = true;
    final callbacks = List<NetworkCancellationCallback>.of(_callbacks);
    _callbacks.clear();
    for (final callback in callbacks) {
      callback();
    }
  }

  void throwIfCancelled() {
    if (_cancelled) {
      throw const NetworkRequestCancelledException();
    }
  }
}

class NetworkRequestCancelledException implements Exception {
  const NetworkRequestCancelledException();

  @override
  String toString() => 'Network request cancelled.';
}

class NetworkTextResponse {
  const NetworkTextResponse({
    required this.status,
    required this.uri,
    required this.statusCode,
    required this.body,
    this.message,
  });
  final NetworkRequestStatus status;
  final Uri uri;
  final int? statusCode;
  final String body;
  final String? message;
  bool get succeeded => status == NetworkRequestStatus.succeeded;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'uri': uri.toString(),
      if (statusCode != null) 'statusCode': statusCode,
      'bodyLength': body.length,
      if (message != null) 'message': message,
      'succeeded': succeeded,
    };
  }
}

class NetworkTextStreamChunk {
  const NetworkTextStreamChunk({
    required this.status,
    required this.uri,
    required this.statusCode,
    required this.text,
    this.message,
  });

  final NetworkRequestStatus status;
  final Uri uri;
  final int? statusCode;
  final String text;
  final String? message;
  bool get succeeded => status == NetworkRequestStatus.succeeded;

  NetworkTextResponse toTextResponse() {
    return NetworkTextResponse(
      status: status,
      uri: uri,
      statusCode: statusCode,
      body: text,
      message: message,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'uri': uri.toString(),
      if (statusCode != null) 'statusCode': statusCode,
      'textLength': text.length,
      if (message != null) 'message': message,
      'succeeded': succeeded,
    };
  }
}

class NetworkBinaryResponse {
  const NetworkBinaryResponse({
    required this.status,
    required this.uri,
    required this.statusCode,
    required this.bytes,
    this.message,
  });

  final NetworkRequestStatus status;
  final Uri uri;
  final int? statusCode;
  final List<int> bytes;
  final String? message;
  bool get succeeded => status == NetworkRequestStatus.succeeded;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.name,
      'uri': uri.toString(),
      if (statusCode != null) 'statusCode': statusCode,
      'bodyLength': bytes.length,
      if (message != null) 'message': message,
      'succeeded': succeeded,
    };
  }
}

class NetworkFailureClassifier {
  const NetworkFailureClassifier({required this.sourceManager});

  final String sourceManager;

  NetworkOperationFailure? classify({
    required NetworkRequestStatus status,
    required Uri uri,
    required int? statusCode,
    required String? message,
    required String operation,
    String? recoveryHint,
  }) {
    if (status == NetworkRequestStatus.succeeded) {
      return null;
    }
    return NetworkOperationFailure(
      kind: _kindFor(status: status, statusCode: statusCode, message: message),
      operation: operation,
      target: uri.toString(),
      sourceManager: sourceManager,
      statusCode: statusCode,
      message: message ?? 'Network request failed.',
      recoveryHint: recoveryHint,
    );
  }

  NetworkFailureKind _kindFor({
    required NetworkRequestStatus status,
    required int? statusCode,
    required String? message,
  }) {
    if (status == NetworkRequestStatus.blocked) {
      return NetworkFailureKind.unsupported;
    }
    if (status == NetworkRequestStatus.timedOut) {
      return NetworkFailureKind.timeout;
    }
    if (status == NetworkRequestStatus.cancelled) {
      return NetworkFailureKind.cancelled;
    }
    if (statusCode != null) {
      return NetworkFailureKind.httpStatus;
    }
    final text = message?.toLowerCase() ?? '';
    if (text.contains('handshake') || text.contains('certificate')) {
      return NetworkFailureKind.tlsFailure;
    }
    if (text.contains('socket') || text.contains('host')) {
      return NetworkFailureKind.hostUnreachable;
    }
    if (text.contains('format')) {
      return NetworkFailureKind.invalidUri;
    }
    return NetworkFailureKind.unknownFailure;
  }
}

abstract class NetworkManager {
  NetworkFacts get facts;
  NetworkCompatibility get compatibility;
  Future<NetworkTextResponse> getText(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  });
  Future<NetworkTextResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 10),
  });
  Future<NetworkBinaryResponse> getBytes(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  });
  NetworkOperationFailure? failureForText(
    NetworkTextResponse response, {
    String operation = 'network.getText',
    String? recoveryHint,
  });
  NetworkOperationFailure? failureForBytes(
    NetworkBinaryResponse response, {
    String operation = 'network.getBytes',
    String? recoveryHint,
  });
}

abstract class CancellableNetworkManager implements NetworkManager {
  Future<NetworkTextResponse> postJsonCancellable(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    required NetworkRequestCancellationToken cancellationToken,
    Duration timeout = const Duration(seconds: 10),
  });
}

abstract class StreamingNetworkManager implements NetworkManager {
  Stream<NetworkTextStreamChunk> postJsonStream(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    NetworkRequestCancellationToken? cancellationToken,
    Duration timeout = const Duration(seconds: 10),
  });
}

class UnsupportedNetworkManager implements NetworkManager {
  UnsupportedNetworkManager({required this.facts})
    : compatibility = NetworkAdapter(facts).adapt();
  @override
  final NetworkFacts facts;
  @override
  final NetworkCompatibility compatibility;
  @override
  Future<NetworkTextResponse> getText(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async => NetworkTextResponse(
    status: NetworkRequestStatus.blocked,
    uri: uri,
    statusCode: null,
    body: '',
    message: 'Network access is not available.',
  );
  @override
  Future<NetworkTextResponse> postJson(
    Uri uri, {
    required Map<String, String> headers,
    required Map<String, Object?> body,
    Duration timeout = const Duration(seconds: 10),
  }) async => NetworkTextResponse(
    status: NetworkRequestStatus.blocked,
    uri: uri,
    statusCode: null,
    body: '',
    message: 'Network access is not available.',
  );
  @override
  Future<NetworkBinaryResponse> getBytes(
    Uri uri, {
    Duration timeout = const Duration(seconds: 10),
  }) async => NetworkBinaryResponse(
    status: NetworkRequestStatus.blocked,
    uri: uri,
    statusCode: null,
    bytes: const <int>[],
    message: 'Network access is not available.',
  );
  @override
  NetworkOperationFailure? failureForText(
    NetworkTextResponse response, {
    String operation = 'network.getText',
    String? recoveryHint,
  }) {
    return const NetworkFailureClassifier(
      sourceManager: 'UnsupportedNetworkManager',
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
      sourceManager: 'UnsupportedNetworkManager',
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
