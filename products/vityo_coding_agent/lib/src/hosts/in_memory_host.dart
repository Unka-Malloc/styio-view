library;

import 'host_workspace.dart';

final class InMemoryHostWorkspace implements HostWorkspace {
  InMemoryHostWorkspace({
    required List<HostRoot> roots,
    Map<String, Object?> facts = const <String, Object?>{},
    this.failure,
    this.revision = 0,
  }) : roots = List<HostRoot>.unmodifiable(roots),
       _rootsById = Map<String, HostRoot>.unmodifiable(<String, HostRoot>{
         for (final root in roots) root.id: root,
       }),
       _facts = Map<String, Object?>.unmodifiable(facts) {
    if (_rootsById.length != roots.length) {
      throw ArgumentError.value(roots, 'roots', 'root ids must be unique');
    }
  }

  @override
  final List<HostRoot> roots;
  final Map<String, HostRoot> _rootsById;
  final Map<String, Object?> _facts;
  final HostFailure? failure;
  final int revision;

  int _inspectionCount = 0;

  int get inspectionCount => _inspectionCount;

  @override
  Future<HostResult<HostWorkspaceSnapshot>> inspect(
    HostWorkspaceRequest request,
  ) async {
    _inspectionCount += 1;
    if (request.context.cancellation.isCancelled) {
      return const HostRejected<HostWorkspaceSnapshot>(
        HostFailure(
          code: HostFailureCode.cancelled,
          message: 'host request cancelled',
        ),
      );
    }
    final deadline = request.context.deadline;
    if (deadline != null && !request.context.observedAt.isBefore(deadline)) {
      return const HostRejected<HostWorkspaceSnapshot>(
        HostFailure(
          code: HostFailureCode.deadlineExceeded,
          message: 'host request deadline exceeded',
        ),
      );
    }
    if (!_rootsById.containsKey(request.rootId)) {
      return HostRejected<HostWorkspaceSnapshot>(
        HostFailure(
          code: HostFailureCode.rootRejected,
          message: 'host root is not available: ${request.rootId}',
        ),
      );
    }
    final configuredFailure = failure;
    if (configuredFailure != null) {
      return HostRejected<HostWorkspaceSnapshot>(configuredFailure);
    }
    return HostSuccess<HostWorkspaceSnapshot>(
      HostWorkspaceSnapshot(
        rootId: request.rootId,
        revision: revision,
        facts: _facts,
      ),
    );
  }
}
