library;

import '../cancellation.dart';
import 'integration_plan.dart';
import 'task_graph.dart';

final class WorktreeHandle {
  WorktreeHandle({
    required this.id,
    required this.taskId,
    required this.baseRevision,
    required Set<String> ownedResources,
  }) : ownedResources = Set<String>.unmodifiable(ownedResources);

  final String id;
  final String taskId;
  final String baseRevision;
  final Set<String> ownedResources;
}

final class WorktreeCleanupReceipt {
  const WorktreeCleanupReceipt({
    required this.worktreeId,
    required this.cleaned,
  });

  final String worktreeId;
  final bool cleaned;
}

abstract interface class WorktreeProvider {
  Future<WorktreeHandle> create({
    required String taskId,
    required String baseRevision,
    required Set<String> ownedResources,
    required AgentCancellationToken cancellation,
  });

  Future<WorktreeCleanupReceipt> dispose(WorktreeHandle handle);
}

final class WorkerRequest {
  const WorkerRequest({
    required this.task,
    required this.scope,
    required this.worktree,
    required this.sessionId,
    required this.cancellation,
  });

  final DelegatedTask task;
  final WorkerScope scope;
  final WorktreeHandle worktree;
  final String sessionId;
  final AgentCancellationToken cancellation;
}

enum WorkerResultStatus { completed, failed, cancelled }

final class WorkerResult {
  WorkerResult._({
    required this.taskId,
    required this.status,
    required List<String> evidenceReceipts,
    this.changeSet,
    this.failure = '',
  }) : evidenceReceipts = List<String>.unmodifiable(evidenceReceipts);

  factory WorkerResult.completed({
    required String taskId,
    required WorkerChangeSet changeSet,
    required List<String> evidenceReceipts,
  }) => WorkerResult._(
    taskId: taskId,
    status: WorkerResultStatus.completed,
    changeSet: changeSet,
    evidenceReceipts: evidenceReceipts,
  );

  factory WorkerResult.failed({
    required String taskId,
    required String failure,
  }) => WorkerResult._(
    taskId: taskId,
    status: WorkerResultStatus.failed,
    failure: failure,
    evidenceReceipts: const <String>[],
  );

  factory WorkerResult.cancelled({required String taskId}) => WorkerResult._(
    taskId: taskId,
    status: WorkerResultStatus.cancelled,
    evidenceReceipts: const <String>[],
  );

  final String taskId;
  final WorkerResultStatus status;
  final WorkerChangeSet? changeSet;
  final List<String> evidenceReceipts;
  final String failure;
}

abstract interface class DelegatedWorker {
  Future<WorkerResult> run(WorkerRequest request);
}
