import 'package:styio_coding_agent/styio_coding_agent.dart';
import 'package:test/test.dart';

void main() {
  test('task graph produces deterministic prerequisite-ready tasks', () {
    final graph = TaskGraph(
      tasks: <DelegatedTask>[
        _task('20-independent', const <String>{'lib/b.dart'}),
        _task('10-first', const <String>{'lib/a.dart'}),
        _task(
          '30-after',
          const <String>{'lib/c.dart'},
          prerequisites: const <String>{'10-first'},
        ),
      ],
    );

    expect(
      graph
          .ready(completed: const <String>{}, started: const <String>{})
          .map((task) => task.id),
      <String>['10-first', '20-independent'],
    );
    expect(
      graph
          .ready(
            completed: const <String>{'10-first'},
            started: const <String>{'10-first'},
          )
          .map((task) => task.id),
      <String>['20-independent', '30-after'],
    );
  });

  test('task graph rejects cycles and escaped ownership', () {
    expect(
      () => TaskGraph(
        tasks: <DelegatedTask>[
          _task(
            'one',
            const <String>{'lib/a.dart'},
            prerequisites: const <String>{'two'},
          ),
          _task(
            'two',
            const <String>{'lib/b.dart'},
            prerequisites: const <String>{'one'},
          ),
        ],
      ),
      throwsArgumentError,
    );
    expect(
      () => _task('escape', const <String>{'../outside'}),
      throwsArgumentError,
    );
  });

  test('resource leases detect hierarchical overlap and release exactly', () {
    final registry = ResourceLeaseRegistry();
    final parent = registry.acquire('parent', const <String>{'lib/feature'});
    final child = registry.acquire('child', const <String>{
      'lib/feature/main.dart',
    });
    final independent = registry.acquire('other', const <String>{
      'lib/other.dart',
    });

    expect(parent.kind, LeaseDecisionKind.granted);
    expect(child.kind, LeaseDecisionKind.contended);
    expect(child.conflictingTaskIds, <String>{'parent'});
    expect(independent.kind, LeaseDecisionKind.granted);
    expect(registry.release(parent.token!), isTrue);
    expect(
      registry.acquire('child', const <String>{'lib/feature/main.dart'}).kind,
      LeaseDecisionKind.granted,
    );
  });

  test('integration candidates require review and preserve conflicts', () {
    final plan = IntegrationPlan.fromChanges(
      targetRevision: 'base',
      changes: <String, WorkerChangeSet>{
        'clean': WorkerChangeSet(
          id: 'clean-change',
          baseRevision: 'base',
          resources: const <String>{'lib/a.dart'},
        ),
        'stale': WorkerChangeSet(
          id: 'stale-change',
          baseRevision: 'old',
          resources: const <String>{'lib/b.dart'},
        ),
      },
    );

    expect(
      plan.candidates.every((candidate) => candidate.requiresReview),
      isTrue,
    );
    expect(
      plan
          .review(taskId: 'clean', decision: IntegrationReviewDecision.approve)
          .outcome,
      IntegrationReviewOutcome.approved,
    );
    expect(
      plan
          .review(taskId: 'stale', decision: IntegrationReviewDecision.approve)
          .outcome,
      IntegrationReviewOutcome.conflict,
    );
  });

  test('delegation budgets fail closed without relying on asserts', () {
    expect(
      () => DelegationBudget(
        maxTasks: 0,
        maxConcurrency: 1,
        maxOperationsPerWorker: 1,
      ),
      throwsA(anything),
    );
  });

  test('directory ownership authorizes descendants but not ancestors', () {
    expect(
      ownershipScopeContains('lib/feature', 'lib/feature/main.dart'),
      isTrue,
    );
    expect(
      ownershipScopeContains('lib/feature/main.dart', 'lib/feature'),
      isFalse,
    );
  });

  test('worker session is isolated, journaled, and cleaned', () async {
    final worker = _CompletingWorker();
    final worktrees = _UnitWorktreeProvider();
    final leases = ResourceLeaseRegistry();
    final sessions = InMemorySessionEventStore();
    final outcome =
        await AgentScheduler(
          worker: worker,
          worktrees: worktrees,
          leases: leases,
          sessionEvents: sessions,
        ).run(
          graph: TaskGraph(
            tasks: <DelegatedTask>[
              _task('hung', const <String>{'lib/feature'}),
            ],
          ),
          budget: const DelegationBudget(
            maxTasks: 1,
            maxConcurrency: 1,
            maxOperationsPerWorker: 1,
          ),
          baseRevision: 'base',
          cancellation: AgentCancellationController().token,
        );

    final request = worker.request!;
    final journal = await sessions.load(
      sessionId: request.sessionId,
      afterSequence: 0,
    );

    expect(outcome.status, DelegationStatus.completed);
    expect(outcome.cleanupReceipts.single.cleaned, isTrue);
    expect(worktrees.activeIds, isEmpty);
    expect(leases.activeLeaseCount, 0);
    expect(journal.events.map((event) => event.kind), <SessionEventKind>[
      SessionEventKind.goalRecorded,
      SessionEventKind.terminalRecorded,
    ]);
  });
}

DelegatedTask _task(
  String id,
  Set<String> resources, {
  Set<String> prerequisites = const <String>{},
}) => DelegatedTask(
  id: id,
  title: id,
  prerequisites: prerequisites,
  ownedResources: resources,
  scope: WorkerScope(
    contextEvidenceIds: <String>{'context-$id'},
    toolIds: <String>{'tool-$id'},
    maxOperations: 1,
  ),
);

final class _CompletingWorker implements DelegatedWorker {
  WorkerRequest? request;

  @override
  Future<WorkerResult> run(WorkerRequest request) async {
    this.request = request;
    return WorkerResult.completed(
      taskId: request.task.id,
      changeSet: WorkerChangeSet(
        id: 'unit-change',
        baseRevision: request.worktree.baseRevision,
        resources: const <String>{'lib/feature/main.dart'},
      ),
      evidenceReceipts: const <String>['unit-evidence'],
    );
  }
}

final class _UnitWorktreeProvider implements WorktreeProvider {
  final Set<String> activeIds = <String>{};

  @override
  Future<WorktreeHandle> create({
    required String taskId,
    required String baseRevision,
    required Set<String> ownedResources,
    required AgentCancellationToken cancellation,
  }) async {
    final id = 'unit-$taskId';
    activeIds.add(id);
    return WorktreeHandle(
      id: id,
      taskId: taskId,
      baseRevision: baseRevision,
      ownedResources: ownedResources,
    );
  }

  @override
  Future<WorktreeCleanupReceipt> dispose(WorktreeHandle handle) async =>
      WorktreeCleanupReceipt(
        worktreeId: handle.id,
        cleaned: activeIds.remove(handle.id),
      );
}
