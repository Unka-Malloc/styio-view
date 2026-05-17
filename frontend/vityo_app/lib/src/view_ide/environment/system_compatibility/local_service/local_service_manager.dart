import 'local_service_adapter.dart';
import 'local_service_facts.dart';

enum LocalServiceFailureKind {
  unsupported,
  permissionDenied,
  portUnavailable,
  bindFailed,
  unknownFailure,
}

class LocalServiceOperationFailure {
  const LocalServiceOperationFailure({
    required this.kind,
    required this.operation,
    required this.target,
    required this.sourceManager,
    required this.message,
    this.recoveryHint,
  });

  final LocalServiceFailureKind kind;
  final String operation;
  final String target;
  final String sourceManager;
  final String message;
  final String? recoveryHint;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.name,
      'operation': operation,
      'target': target,
      'sourceManager': sourceManager,
      'message': message,
      if (recoveryHint != null) 'recoveryHint': recoveryHint,
    };
  }
}

typedef LocalServicePlatformFailureKindResolver =
    LocalServiceFailureKind? Function(Object error);

class LocalServiceFailureClassifier {
  const LocalServiceFailureClassifier({
    required this.sourceManager,
    this.platformFailureKindResolver,
  });

  final String sourceManager;
  final LocalServicePlatformFailureKindResolver? platformFailureKindResolver;

  LocalServiceOperationFailure classify(
    Object error, {
    required String operation,
    required String target,
    String? recoveryHint,
  }) {
    return LocalServiceOperationFailure(
      kind: _kindFor(error),
      operation: operation,
      target: target,
      sourceManager: sourceManager,
      message: error.toString(),
      recoveryHint: recoveryHint,
    );
  }

  LocalServiceFailureKind _kindFor(Object error) {
    if (error is UnsupportedError) {
      return LocalServiceFailureKind.unsupported;
    }
    final platformKind = platformFailureKindResolver?.call(error);
    if (platformKind != null) {
      return platformKind;
    }
    return LocalServiceFailureKind.unknownFailure;
  }
}

class LocalHttpServiceRequest {
  const LocalHttpServiceRequest({required this.responseText, this.path = '/'});
  final String responseText;
  final String path;
}

abstract class LocalServiceHandle {
  Uri get uri;
  Future<void> close();
}

abstract class LocalServiceManager {
  LocalServiceFacts get facts;
  LocalServiceCompatibility get compatibility;
  Future<LocalServiceHandle> startHttpTextService(
    LocalHttpServiceRequest request,
  );
  LocalServiceOperationFailure classifyFailure(
    Object error, {
    required String operation,
    required String target,
    String? recoveryHint,
  });
}

class UnsupportedLocalServiceManager implements LocalServiceManager {
  UnsupportedLocalServiceManager({required this.facts})
    : compatibility = LocalServiceAdapter(facts).adapt();
  @override
  final LocalServiceFacts facts;
  @override
  final LocalServiceCompatibility compatibility;
  @override
  Future<LocalServiceHandle> startHttpTextService(
    LocalHttpServiceRequest request,
  ) async => throw UnsupportedError('Local services are not available.');
  @override
  LocalServiceOperationFailure classifyFailure(
    Object error, {
    required String operation,
    required String target,
    String? recoveryHint,
  }) {
    return const LocalServiceFailureClassifier(
      sourceManager: 'UnsupportedLocalServiceManager',
    ).classify(
      error,
      operation: operation,
      target: target,
      recoveryHint: recoveryHint,
    );
  }
}
