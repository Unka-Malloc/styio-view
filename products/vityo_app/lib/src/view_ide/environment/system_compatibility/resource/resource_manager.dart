import 'resource_adapter.dart';
import 'resource_facts.dart';

enum ResourceFailureKind {
  unsupported,
  permissionDenied,
  resourceLimit,
  unavailable,
  unknownFailure,
}

class ResourceOperationFailure {
  const ResourceOperationFailure({
    required this.kind,
    required this.operation,
    required this.target,
    required this.sourceManager,
    required this.message,
    this.recoveryHint,
  });

  final ResourceFailureKind kind;
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

typedef ResourcePlatformFailureKindResolver =
    ResourceFailureKind? Function(Object error);

class ResourceFailureClassifier {
  const ResourceFailureClassifier({
    required this.sourceManager,
    this.platformFailureKindResolver,
  });

  final String sourceManager;
  final ResourcePlatformFailureKindResolver? platformFailureKindResolver;

  ResourceOperationFailure classify(
    Object error, {
    required String operation,
    required String target,
    String? recoveryHint,
  }) {
    return ResourceOperationFailure(
      kind: _kindFor(error),
      operation: operation,
      target: target,
      sourceManager: sourceManager,
      message: error.toString(),
      recoveryHint: recoveryHint,
    );
  }

  ResourceFailureKind _kindFor(Object error) {
    if (error is UnsupportedError) {
      return ResourceFailureKind.unsupported;
    }
    final platformKind = platformFailureKindResolver?.call(error);
    if (platformKind != null) {
      return platformKind;
    }
    return ResourceFailureKind.unknownFailure;
  }
}

class ResourceSnapshot {
  const ResourceSnapshot({
    required this.processorCount,
    required this.systemTempPath,
    required this.homePath,
  });
  final int processorCount;
  final String systemTempPath;
  final String? homePath;
}

abstract class ResourceManager {
  ResourceFacts get facts;
  ResourceCompatibility get compatibility;
  ResourceSnapshot snapshot();
  Future<String> createTempDirectory(String prefix);
  ResourceOperationFailure classifyFailure(
    Object error, {
    required String operation,
    required String target,
    String? recoveryHint,
  });
}

class UnsupportedResourceManager implements ResourceManager {
  UnsupportedResourceManager({required this.facts})
    : compatibility = ResourceAdapter(facts).adapt();
  @override
  final ResourceFacts facts;
  @override
  final ResourceCompatibility compatibility;
  @override
  ResourceSnapshot snapshot() => ResourceSnapshot(
    processorCount: compatibility.processorCount,
    systemTempPath: compatibility.systemTempPath,
    homePath: compatibility.homePath,
  );
  @override
  Future<String> createTempDirectory(String prefix) async =>
      throw UnsupportedError('Temporary directories are not available.');
  @override
  ResourceOperationFailure classifyFailure(
    Object error, {
    required String operation,
    required String target,
    String? recoveryHint,
  }) {
    return const ResourceFailureClassifier(
      sourceManager: 'UnsupportedResourceManager',
    ).classify(
      error,
      operation: operation,
      target: target,
      recoveryHint: recoveryHint,
    );
  }
}
