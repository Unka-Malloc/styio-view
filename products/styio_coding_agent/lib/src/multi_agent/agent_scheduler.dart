library;

import '../cancellation.dart';
import '../sessions/session_event.dart';
import '../sessions/session_event_store.dart';
import 'integration_plan.dart';
import 'resource_lease_registry.dart';
import 'task_graph.dart';
import 'worktree_coordinator.dart';

final class DelegationBudget {
  const DelegationBudget({
    required this.maxTasks,
    required this.maxConcurrency,
    required this.maxOperationsPerWorker,
  }) : _validation =
           1 ~/
           ((maxTasks > 0 && maxConcurrency > 0 && maxOperationsPerWorker > 0)
               ? 1
               : 0);

  final int maxTasks;
  final int maxConcurrency;
  final int maxOperationsPerWorker;
  final int _validation;

  bool get isValid =>
      _validation == 1 &&
      maxTasks > 0 &&
      maxConcurrency > 0 &&
      maxOperationsPerWorker > 0;
}

enum DelegationStatus { completed, blocked, cancelled }

final class DelegationOutcome {
  DelegationOutcome({
    required this.status,
    required List<WorkerResult> orderedResults,
    required List<WorktreeCleanupReceipt> cleanupReceipts,
    required this.integrationPlan,
    required this.maxObservedConcurrency,
    required List<String> blockers,
  }) : orderedResults = List<WorkerResult>.unmodifiable(orderedResults),
       cleanupReceipts = List<WorktreeCleanupReceipt>.unmodifiable(
         cleanupReceipts,
       ),
       blockers = List<String>.unmodifiable(blockers);

  final DelegationStatus status;
  final List<WorkerResult> orderedResults;
  final List<WorktreeCleanupReceipt> cleanupReceipts;
  final IntegrationPlan integrationPlan;
  final int maxObservedConcurrency;
  final List<String> blockers;
}

final class AgentScheduler {
  AgentScheduler({
    required this.worker,
    required this.worktrees,
    required this.leases,
    SessionEventStore? sessionEvents,
    DateTime Function()? clock,
  }) : sessionEvents = sessionEvents ?? InMemorySessionEventStore(),
       _clock = clock ?? _utcNow;

  final DelegatedWorker worker;
  final WorktreeProvider worktrees;
  final ResourceLeaseRegistry leases;
  final SessionEventStore sessionEvents;
  final DateTime Function() _clock;

  Future<DelegationOutcome> run({
    required TaskGraph graph,
    required DelegationBudget budget,
    required String baseRevision,
    required AgentCancellationToken cancellation,
  }) async {
    if (!budget.isValid ||
        baseRevision.trim().isEmpty ||
        graph.tasks.length > budget.maxTasks ||
        graph.tasks.any(
          (task) => task.scope.maxOperations > budget.maxOperationsPerWorker,
        )) {
      return _outcome(
        status: DelegationStatus.blocked,
        results: const <String, WorkerResult>{},
        cleanups: const <WorktreeCleanupReceipt>[],
        baseRevision: baseRevision,
        maxObservedConcurrency: 0,
        blockers: const <String>['delegationBudgetExceeded'],
      );
    }

    final started = <String>{};
    final completed = <String>{};
    final results = <String, WorkerResult>{};
    final cleanups = <WorktreeCleanupReceipt>[];
    final running = <String, Future<_TaskExecution>>{};
    final blockers = <String>[];
    final issuedWorktreeIds = <String>{};
    final schedule = graph.createSchedule();
    var maxObservedConcurrency = 0;

    while (started.length < graph.tasks.length || running.isNotEmpty) {
      var scheduled = false;
      if (!cancellation.isCancelled) {
        for (final task in schedule.ready.toList(growable: false)) {
          if (running.length >= budget.maxConcurrency) break;
          final decision = leases.acquire(task.id, task.ownedResources);
          if (decision.kind == LeaseDecisionKind.contended) continue;
          if (decision.kind != LeaseDecisionKind.granted ||
              decision.token == null) {
            schedule.markStarted(task.id);
            started.add(task.id);
            results[task.id] = WorkerResult.failed(
              taskId: task.id,
              failure: 'resourceLeaseRejected',
            );
            blockers.add('resourceLeaseRejected:${task.id}');
            continue;
          }
          schedule.markStarted(task.id);
          started.add(task.id);
          running[task.id] = _execute(
            task: task,
            lease: decision.token!,
            baseRevision: baseRevision,
            cancellation: cancellation,
            issuedWorktreeIds: issuedWorktreeIds,
          );
          scheduled = true;
          if (running.length > maxObservedConcurrency) {
            maxObservedConcurrency = running.length;
          }
        }
      }

      if (running.isEmpty) {
        if (cancellation.isCancelled || started.length == graph.tasks.length) {
          break;
        }
        if (!schedule.hasReady || !scheduled) {
          blockers.add('dependencyBlocked');
          break;
        }
      }
      if (running.isEmpty) continue;

      final execution = await Future.any<_TaskExecution>(running.values);
      running.remove(execution.result.taskId);
      results[execution.result.taskId] = execution.result;
      if (execution.cleanup != null) cleanups.add(execution.cleanup!);
      if (execution.result.status == WorkerResultStatus.completed) {
        completed.add(execution.result.taskId);
        schedule.markCompleted(execution.result.taskId);
      } else if (execution.result.status == WorkerResultStatus.failed) {
        blockers.add('workerFailed:${execution.result.taskId}');
      }
    }

    for (final cleanup in cleanups) {
      if (!cleanup.cleaned) {
        blockers.add('worktreeCleanupIncomplete:${cleanup.worktreeId}');
      }
    }
    final status = cancellation.isCancelled
        ? DelegationStatus.cancelled
        : completed.length == graph.tasks.length && blockers.isEmpty
        ? DelegationStatus.completed
        : DelegationStatus.blocked;
    return _outcome(
      status: status,
      results: results,
      cleanups: cleanups,
      baseRevision: baseRevision,
      maxObservedConcurrency: maxObservedConcurrency,
      blockers: blockers,
    );
  }

  Future<_TaskExecution> _execute({
    required DelegatedTask task,
    required ResourceLeaseToken lease,
    required String baseRevision,
    required AgentCancellationToken cancellation,
    required Set<String> issuedWorktreeIds,
  }) async {
    WorktreeHandle? handle;
    WorktreeCleanupReceipt? cleanup;
    WorkerResult result;
    try {
      if (cancellation.isCancelled) {
        return _TaskExecution(result: WorkerResult.cancelled(taskId: task.id));
      }
      handle = await worktrees.create(
        taskId: task.id,
        baseRevision: baseRevision,
        ownedResources: task.ownedResources,
        cancellation: cancellation,
      );
      if (handle.id.trim().isEmpty ||
          handle.taskId != task.id ||
          handle.baseRevision != baseRevision ||
          handle.ownedResources.length != task.ownedResources.length ||
          !handle.ownedResources.containsAll(task.ownedResources) ||
          !issuedWorktreeIds.add(handle.id)) {
        result = WorkerResult.failed(
          taskId: task.id,
          failure: 'invalidWorktree',
        );
      } else if (cancellation.isCancelled) {
        result = WorkerResult.cancelled(taskId: task.id);
      } else {
        final sessionId = 'worker:$baseRevision:${task.id}:${handle.id}';
        final started = await _recordWorkerEvent(
          sessionId: sessionId,
          taskId: task.id,
          kind: SessionEventKind.goalRecorded,
          payload: const <String, Object?>{'state': 'delegated'},
        );
        if (!started) {
          result = WorkerResult.failed(
            taskId: task.id,
            failure: 'workerSessionUnavailable',
          );
        } else {
          final request = WorkerRequest(
            task: task,
            scope: task.scope,
            worktree: handle,
            sessionId: sessionId,
            cancellation: cancellation,
          );
          result = await worker.run(request);
          result = _validateWorkerResult(task, result);
          final terminalRecorded = await _recordWorkerEvent(
            sessionId: sessionId,
            taskId: task.id,
            kind: SessionEventKind.terminalRecorded,
            payload: <String, Object?>{'state': result.status.name},
          );
          if (!terminalRecorded) {
            result = WorkerResult.failed(
              taskId: task.id,
              failure: 'workerSessionUnavailable',
            );
          }
        }
      }
    } on Object {
      result = cancellation.isCancelled
          ? WorkerResult.cancelled(taskId: task.id)
          : WorkerResult.failed(
              taskId: task.id,
              failure: 'workerCapabilityUnavailable',
            );
    } finally {
      final created = handle;
      if (created != null) {
        try {
          final receipt = await worktrees.dispose(created);
          cleanup = receipt.worktreeId == created.id
              ? receipt
              : WorktreeCleanupReceipt(worktreeId: created.id, cleaned: false);
        } on Object {
          cleanup = WorktreeCleanupReceipt(
            worktreeId: created.id,
            cleaned: false,
          );
        }
      }
      leases.release(lease);
    }
    return _TaskExecution(result: result, cleanup: cleanup);
  }

  Future<bool> _recordWorkerEvent({
    required String sessionId,
    required String taskId,
    required SessionEventKind kind,
    required Map<String, Object?> payload,
  }) async {
    try {
      final current = await sessionEvents.load(
        sessionId: sessionId,
        afterSequence: 0,
        maxEvents: 1,
      );
      if (current.corruptedTail) return false;
      final appended = await sessionEvents.append(
        sessionId: sessionId,
        expectedSequence: current.currentSequence,
        events: <SessionEventDraft>[
          SessionEventDraft(
            kind: kind,
            correlation: SessionCorrelation(
              taskId: taskId,
              sessionId: sessionId,
            ),
            occurredAt: _clock().toUtc(),
            payload: payload,
          ),
        ],
      );
      return appended.outcome == SessionAppendOutcome.committed;
    } on Object {
      return false;
    }
  }

  static WorkerResult _validateWorkerResult(
    DelegatedTask task,
    WorkerResult result,
  ) {
    if (result.taskId != task.id) {
      return WorkerResult.failed(
        taskId: task.id,
        failure: 'workerCorrelationMismatch',
      );
    }
    if (result.status != WorkerResultStatus.completed) return result;
    final change = result.changeSet;
    if (change == null ||
        change.resources.length > task.scope.maxOperations ||
        change.resources.any(
          (resource) => !task.ownedResources.any(
            (owner) => ownershipScopeContains(owner, resource),
          ),
        ) ||
        result.evidenceReceipts.length > task.scope.maxOperations ||
        result.evidenceReceipts.any((receipt) => receipt.trim().isEmpty)) {
      return WorkerResult.failed(
        taskId: task.id,
        failure: 'workerScopeExceeded',
      );
    }
    return result;
  }

  static DelegationOutcome _outcome({
    required DelegationStatus status,
    required Map<String, WorkerResult> results,
    required List<WorktreeCleanupReceipt> cleanups,
    required String baseRevision,
    required int maxObservedConcurrency,
    required List<String> blockers,
  }) {
    final ids = results.keys.toList(growable: false)..sort();
    final ordered = <WorkerResult>[for (final id in ids) results[id]!];
    final changes = <String, WorkerChangeSet>{
      for (final result in ordered)
        if (result.status == WorkerResultStatus.completed &&
            result.changeSet != null)
          result.taskId: result.changeSet!,
    };
    final orderedCleanups = List<WorktreeCleanupReceipt>.of(cleanups)
      ..sort((left, right) => left.worktreeId.compareTo(right.worktreeId));
    return DelegationOutcome(
      status: status,
      orderedResults: ordered,
      cleanupReceipts: orderedCleanups,
      integrationPlan: IntegrationPlan.fromChanges(
        targetRevision: baseRevision,
        changes: changes,
      ),
      maxObservedConcurrency: maxObservedConcurrency,
      blockers: blockers,
    );
  }
}

DateTime _utcNow() => DateTime.now().toUtc();

final class _TaskExecution {
  const _TaskExecution({required this.result, this.cleanup});

  final WorkerResult result;
  final WorktreeCleanupReceipt? cleanup;
}
