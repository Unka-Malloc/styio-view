library;

enum HostFailureCode {
  capabilityUnavailable,
  rootRejected,
  cancelled,
  deadlineExceeded,
  invalidRequest,
}

final class HostFailure {
  const HostFailure({required this.code, required this.message});

  final HostFailureCode code;
  final String message;

  Map<String, Object?> toJson() => <String, Object?>{
    'code': code.name,
    'message': message,
  };
}

sealed class HostResult<T> {
  const HostResult();
}

final class HostSuccess<T> extends HostResult<T> {
  const HostSuccess(this.value);

  final T value;
}

final class HostRejected<T> extends HostResult<T> {
  const HostRejected(this.failure);

  final HostFailure failure;
}

final class HostRoot {
  const HostRoot({required this.id, required this.uri})
    : assert(id != ''),
      assert(uri != '');

  final String id;
  final String uri;
}

abstract interface class HostCancellationSignal {
  bool get isCancelled;

  Future<void> get whenCancelled;
}

final class HostRequestContext {
  const HostRequestContext({
    required this.sessionId,
    required this.observedAt,
    required this.cancellation,
    this.deadline,
  });

  final String sessionId;
  final DateTime observedAt;
  final DateTime? deadline;
  final HostCancellationSignal cancellation;
}

final class HostWorkspaceRequest {
  const HostWorkspaceRequest({
    required this.context,
    required this.goal,
    required this.rootId,
  });

  final HostRequestContext context;
  final String goal;
  final String rootId;
}

final class HostWorkspaceSnapshot {
  HostWorkspaceSnapshot({
    required this.rootId,
    required this.revision,
    required Map<String, Object?> facts,
  }) : facts = Map<String, Object?>.unmodifiable(facts);

  final String rootId;
  final int revision;
  final Map<String, Object?> facts;
}

abstract interface class HostWorkspace {
  List<HostRoot> get roots;

  Future<HostResult<HostWorkspaceSnapshot>> inspect(
    HostWorkspaceRequest request,
  );
}
