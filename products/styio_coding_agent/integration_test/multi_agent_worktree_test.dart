import 'dart:io';

import 'package:styio_coding_agent/styio_coding_agent.dart';

Future<void> main() async {
  final root = Directory.systemTemp.createTempSync('styio-worktrees-');
  try {
    final worktrees = _DirectoryWorktrees(root);
    final outcome =
        await AgentScheduler(
          worker: _FileWorker(worktrees),
          worktrees: worktrees,
          leases: ResourceLeaseRegistry(),
        ).run(
          graph: TaskGraph(
            tasks: <DelegatedTask>[
              _task('first', 'lib/first.dart'),
              _task('second', 'lib/second.dart'),
            ],
          ),
          budget: const DelegationBudget(
            maxTasks: 2,
            maxConcurrency: 2,
            maxOperationsPerWorker: 1,
          ),
          baseRevision: 'base',
          cancellation: AgentCancellationController().token,
        );

    if (outcome.status != DelegationStatus.completed ||
        outcome.maxObservedConcurrency != 2 ||
        outcome.cleanupReceipts.any((receipt) => !receipt.cleaned) ||
        root.listSync().isNotEmpty ||
        outcome.integrationPlan.candidates.any(
          (candidate) => !candidate.requiresReview,
        )) {
      throw StateError('isolated worktree lifecycle did not close');
    }
  } finally {
    root.deleteSync(recursive: true);
  }
}

DelegatedTask _task(String id, String resource) => DelegatedTask(
  id: id,
  title: id,
  prerequisites: const <String>{},
  ownedResources: <String>{resource},
  scope: WorkerScope(
    contextEvidenceIds: <String>{'context-$id'},
    toolIds: <String>{'tool-$id'},
    maxOperations: 1,
  ),
);

final class _DirectoryWorktrees implements WorktreeProvider {
  _DirectoryWorktrees(this.root);

  final Directory root;
  final Map<String, Directory> _active = <String, Directory>{};
  int _sequence = 0;

  Directory directoryFor(WorktreeHandle handle) => _active[handle.id]!;

  @override
  Future<WorktreeHandle> create({
    required String taskId,
    required String baseRevision,
    required Set<String> ownedResources,
    required AgentCancellationToken cancellation,
  }) async {
    final id = 'worker-${++_sequence}';
    final directory = Directory('${root.path}${Platform.pathSeparator}$id')
      ..createSync();
    _active[id] = directory;
    return WorktreeHandle(
      id: id,
      taskId: taskId,
      baseRevision: baseRevision,
      ownedResources: ownedResources,
    );
  }

  @override
  Future<WorktreeCleanupReceipt> dispose(WorktreeHandle handle) async {
    final directory = _active.remove(handle.id);
    if (directory == null) {
      return WorktreeCleanupReceipt(worktreeId: handle.id, cleaned: false);
    }
    directory.deleteSync(recursive: true);
    return WorktreeCleanupReceipt(
      worktreeId: handle.id,
      cleaned: !directory.existsSync(),
    );
  }
}

final class _FileWorker implements DelegatedWorker {
  const _FileWorker(this.worktrees);

  final _DirectoryWorktrees worktrees;

  @override
  Future<WorkerResult> run(WorkerRequest request) async {
    final directory = worktrees.directoryFor(request.worktree);
    final marker = File('${directory.path}${Platform.pathSeparator}change.txt');
    marker.writeAsStringSync(request.task.id, flush: true);
    await Future<void>.delayed(const Duration(milliseconds: 10));
    if (!marker.existsSync() || marker.readAsStringSync() != request.task.id) {
      return WorkerResult.failed(
        taskId: request.task.id,
        failure: 'worktreeIsolationFailed',
      );
    }
    return WorkerResult.completed(
      taskId: request.task.id,
      changeSet: WorkerChangeSet(
        id: 'change-${request.task.id}',
        baseRevision: request.worktree.baseRevision,
        resources: request.task.ownedResources,
      ),
      evidenceReceipts: <String>['marker-${request.task.id}'],
    );
  }
}
