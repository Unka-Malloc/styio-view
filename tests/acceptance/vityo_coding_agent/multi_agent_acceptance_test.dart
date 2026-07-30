import 'dart:async';

import 'package:vityo_coding_agent/vityo_coding_agent.dart';

Future<void> main() async {
  await _runsDependencyReadyTasksWithBoundedIsolatedWorkers();
  await _serializesOverlappingOwnershipAndRequiresReviewedIntegration();
  await _propagatesCancellationAndCleansEveryWorktree();
  _rejectsInvalidGraphsScopesAndBudgets();
}

Future<void> _runsDependencyReadyTasksWithBoundedIsolatedWorkers() async {
  final tasks = <DelegatedTask>[
    _task('01-model', resources: const <String>{'lib/model.dart'}),
    _task('02-view', resources: const <String>{'lib/view.dart'}),
    _task(
      '03-test',
      prerequisites: const <String>{'01-model', '02-view'},
      resources: const <String>{'test/feature_test.dart'},
    ),
  ];
  final graph = TaskGraph(tasks: tasks);
  final worker = _RecordingWorker(
    delays: const <String, Duration>{
      '01-model': Duration(milliseconds: 25),
      '02-view': Duration(milliseconds: 15),
      '03-test': Duration(milliseconds: 1),
    },
  );
  final worktrees = _FakeWorktreeProvider();
  final outcome = await AgentScheduler(
    worker: worker,
    worktrees: worktrees,
    leases: ResourceLeaseRegistry(),
  ).run(
    graph: graph,
    budget: const DelegationBudget(
      maxTasks: 4,
      maxConcurrency: 2,
      maxOperationsPerWorker: 3,
    ),
    baseRevision: 'base-1',
    cancellation: AgentCancellationController().token,
  );

  _expect(
    outcome.status == DelegationStatus.completed &&
        outcome.maxObservedConcurrency == 2 &&
        worker.maxActive == 2,
    'two independent ready tasks must execute concurrently within the configured bound',
  );
  _expect(
    worker.startedAt['03-test']! >= worker.finishedAt['01-model']! &&
        worker.startedAt['03-test']! >= worker.finishedAt['02-view']!,
    'a dependent task must not start before all prerequisites finish',
  );
  _expect(
    outcome.orderedResults.map((result) => result.taskId).join(',') ==
        '01-model,02-view,03-test',
    'result collection must use deterministic task ID order',
  );
  for (final task in tasks) {
    final request = worker.requests.singleWhere(
      (request) => request.task.id == task.id,
    );
    _expect(
      request.scope.contextEvidenceIds.length == 1 &&
          request.scope.contextEvidenceIds.single == 'context-${task.id}' &&
          request.scope.toolIds.length == 1 &&
          request.scope.toolIds.single == 'tool-${task.id}' &&
          request.scope.maxOperations == 2 &&
          request.scope.maxOperations <=
              const DelegationBudget(
                maxTasks: 4,
                maxConcurrency: 2,
                maxOperationsPerWorker: 3,
              ).maxOperationsPerWorker &&
          request.worktree.ownedResources.toSet().containsAll(
            task.ownedResources,
          ),
      'workers must receive only their declared context, tools, budget, and ownership',
    );
  }
  _expect(
    worktrees.createdIds.toSet().length == tasks.length &&
        outcome.cleanupReceipts.length == tasks.length &&
        outcome.cleanupReceipts.every((receipt) => receipt.cleaned),
    'every mutating worker must use a distinct worktree and produce cleanup evidence',
  );
  _expect(
    outcome.integrationPlan.candidates.length == tasks.length &&
        outcome.integrationPlan.candidates.every(
          (candidate) =>
              candidate.status == IntegrationCandidateStatus.ready &&
              candidate.requiresReview,
        ),
    'successful workers must produce reviewable integration candidates, not mutations',
  );
}

Future<void>
_serializesOverlappingOwnershipAndRequiresReviewedIntegration() async {
  final graph = TaskGraph(
    tasks: <DelegatedTask>[
      _task('01-parent', resources: const <String>{'lib/feature'}),
      _task('02-child', resources: const <String>{'lib/feature/main.dart'}),
      _task('03-stale', resources: const <String>{'lib/stale.dart'}),
    ],
  );
  final worker = _RecordingWorker(
    resultBaseOverrides: const <String, String>{'03-stale': 'older-base'},
    delays: const <String, Duration>{
      '01-parent': Duration(milliseconds: 15),
      '02-child': Duration(milliseconds: 15),
      '03-stale': Duration(milliseconds: 1),
    },
  );
  final outcome = await AgentScheduler(
    worker: worker,
    worktrees: _FakeWorktreeProvider(),
    leases: ResourceLeaseRegistry(),
  ).run(
    graph: graph,
    budget: const DelegationBudget(
      maxTasks: 4,
      maxConcurrency: 3,
      maxOperationsPerWorker: 3,
    ),
    baseRevision: 'base-1',
    cancellation: AgentCancellationController().token,
  );

  _expect(
    !worker.overlapViolation &&
        worker.finishedAt['01-parent']! <= worker.startedAt['02-child']!,
    'hierarchically overlapping resource scopes must never execute concurrently',
  );
  final readyReceipt = outcome.integrationPlan.review(
    taskId: '01-parent',
    decision: IntegrationReviewDecision.approve,
  );
  final conflictReceipt = outcome.integrationPlan.review(
    taskId: '03-stale',
    decision: IntegrationReviewDecision.approve,
  );
  _expect(
    readyReceipt.outcome == IntegrationReviewOutcome.approved &&
        readyReceipt.changeSetId.isNotEmpty &&
        conflictReceipt.outcome == IntegrationReviewOutcome.conflict &&
        conflictReceipt.reason.isNotEmpty,
    'clean and stale results must both produce truthful review receipts',
  );
  _expect(
    outcome.integrationPlan.candidates.singleWhere(
          (candidate) => candidate.taskId == '03-stale',
        ).status ==
        IntegrationCandidateStatus.conflict,
    'a stale worker base must remain an explicit conflict rather than merge',
  );
}

Future<void> _propagatesCancellationAndCleansEveryWorktree() async {
  final controller = AgentCancellationController();
  final worker = _RecordingWorker(waitForCancellation: true);
  final worktrees = _FakeWorktreeProvider();
  final running = AgentScheduler(
    worker: worker,
    worktrees: worktrees,
    leases: ResourceLeaseRegistry(),
  ).run(
    graph: TaskGraph(
      tasks: <DelegatedTask>[
        _task('01-running', resources: const <String>{'lib/a.dart'}),
        _task('02-running', resources: const <String>{'lib/b.dart'}),
        _task(
          '03-dependent',
          prerequisites: const <String>{'01-running'},
          resources: const <String>{'lib/c.dart'},
        ),
      ],
    ),
    budget: const DelegationBudget(
      maxTasks: 3,
      maxConcurrency: 2,
      maxOperationsPerWorker: 2,
    ),
    baseRevision: 'base-1',
    cancellation: controller.token,
  );
  await worker.twoWorkersStarted.future;
  controller.cancel();
  final outcome = await running;

  _expect(
    outcome.status == DelegationStatus.cancelled &&
        worker.cancelledTaskIds.length == 2 &&
        !worker.requests.any(
          (request) => request.task.id == '03-dependent',
        ),
    'parent cancellation must reach running workers and suppress dependents',
  );
  _expect(
    worktrees.activeIds.isEmpty &&
        outcome.cleanupReceipts.length == 2 &&
        outcome.cleanupReceipts.every((receipt) => receipt.cleaned),
    'cancellation must release leases and clean every created worktree',
  );
}

void _rejectsInvalidGraphsScopesAndBudgets() {
  _expectThrows(
    () => TaskGraph(
      tasks: <DelegatedTask>[
        _task(
          'one',
          prerequisites: const <String>{'two'},
          resources: const <String>{'lib/one.dart'},
        ),
        _task(
          'two',
          prerequisites: const <String>{'one'},
          resources: const <String>{'lib/two.dart'},
        ),
      ],
    ),
    'cycles must be rejected before scheduling',
  );
  _expectThrows(
    () => _task('escape', resources: const <String>{'../outside'}),
    'ownership scopes must be normalized and root-relative',
  );
  _expectThrows(
    () => DelegationBudget(
      maxTasks: 0,
      maxConcurrency: 0,
      maxOperationsPerWorker: 0,
    ),
    'unbounded or empty scheduling budgets must be rejected',
  );
}

DelegatedTask _task(
  String id, {
  Set<String> prerequisites = const <String>{},
  required Set<String> resources,
}) => DelegatedTask(
  id: id,
  title: 'Synthetic $id',
  prerequisites: prerequisites,
  ownedResources: resources,
  scope: WorkerScope(
    contextEvidenceIds: <String>{'context-$id'},
    toolIds: <String>{'tool-$id'},
    maxOperations: 2,
  ),
);

final class _RecordingWorker implements DelegatedWorker {
  _RecordingWorker({
    this.delays = const <String, Duration>{},
    this.resultBaseOverrides = const <String, String>{},
    this.waitForCancellation = false,
  });

  final Map<String, Duration> delays;
  final Map<String, String> resultBaseOverrides;
  final bool waitForCancellation;
  final List<WorkerRequest> requests = <WorkerRequest>[];
  final Map<String, int> startedAt = <String, int>{};
  final Map<String, int> finishedAt = <String, int>{};
  final Set<String> cancelledTaskIds = <String>{};
  final Set<String> _activeResources = <String>{};
  final Completer<void> twoWorkersStarted = Completer<void>();
  int active = 0;
  int maxActive = 0;
  int _tick = 0;
  bool overlapViolation = false;

  @override
  Future<WorkerResult> run(WorkerRequest request) async {
    requests.add(request);
    startedAt[request.task.id] = ++_tick;
    active += 1;
    if (active > maxActive) maxActive = active;
    if (request.worktree.ownedResources.any(
      (resource) => _activeResources.any(
        (activeResource) => _overlaps(activeResource, resource),
      ),
    )) {
      overlapViolation = true;
    }
    _activeResources.addAll(request.worktree.ownedResources);
    if (active == 2 && !twoWorkersStarted.isCompleted) {
      twoWorkersStarted.complete();
    }
    if (waitForCancellation) {
      await request.cancellation.whenCancelled;
      cancelledTaskIds.add(request.task.id);
    } else {
      await Future<void>.delayed(
        delays[request.task.id] ?? Duration.zero,
      );
    }
    _activeResources.removeAll(request.worktree.ownedResources);
    active -= 1;
    finishedAt[request.task.id] = ++_tick;
    if (request.cancellation.isCancelled) {
      return WorkerResult.cancelled(taskId: request.task.id);
    }
    return WorkerResult.completed(
      taskId: request.task.id,
      changeSet: WorkerChangeSet(
        id: 'change-${request.task.id}',
        baseRevision:
            resultBaseOverrides[request.task.id] ??
            request.worktree.baseRevision,
        resources: request.task.ownedResources,
      ),
      evidenceReceipts: <String>['evidence-${request.task.id}'],
    );
  }
}

final class _FakeWorktreeProvider implements WorktreeProvider {
  int _sequence = 0;
  final Set<String> activeIds = <String>{};
  final List<String> createdIds = <String>[];

  @override
  Future<WorktreeHandle> create({
    required String taskId,
    required String baseRevision,
    required Set<String> ownedResources,
    required AgentCancellationToken cancellation,
  }) async {
    final id = 'worktree-${++_sequence}-$taskId';
    activeIds.add(id);
    createdIds.add(id);
    return WorktreeHandle(
      id: id,
      taskId: taskId,
      baseRevision: baseRevision,
      ownedResources: ownedResources,
    );
  }

  @override
  Future<WorktreeCleanupReceipt> dispose(
    WorktreeHandle handle,
  ) async {
    final removed = activeIds.remove(handle.id);
    return WorktreeCleanupReceipt(
      worktreeId: handle.id,
      cleaned: removed,
    );
  }
}

bool _overlaps(String left, String right) =>
    left == right ||
    left.startsWith('$right/') ||
    right.startsWith('$left/');

void _expect(bool condition, String message) {
  if (!condition) throw StateError(message);
}

void _expectThrows(void Function() action, String message) {
  try {
    action();
  } on Object {
    return;
  }
  throw StateError(message);
}
