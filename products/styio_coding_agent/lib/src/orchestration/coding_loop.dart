library;

import 'dart:async';

import 'coding_plan.dart';
import 'loop_guard.dart';
import 'validation_planner.dart';

enum CodingTaskStatus { completed, blocked, cancelled }

enum CodingBlockerCode {
  acceptanceUnavailable,
  permissionDenied,
  capabilityDenied,
  staleRevision,
  validationFailed,
  repeatedFailure,
  budgetExceeded,
  steered,
  deadline,
}

final class CodingBlocker {
  const CodingBlocker({required this.code, required this.message});

  final CodingBlockerCode code;
  final String message;
}

final class CodingLoopEvent {
  const CodingLoopEvent({
    required this.transition,
    this.stepId,
    this.workspaceRevision,
  });

  final String transition;
  final String? stepId;
  final int? workspaceRevision;
}

final class CodingTaskOutcome {
  CodingTaskOutcome({
    required this.status,
    required List<String> completedStepIds,
    required List<CodingLoopEvent> events,
    required List<CodingTransactionReceipt> transactionReceipts,
    required List<CodingValidationReceipt> validationReceipts,
    required this.repairCount,
    this.plan,
    this.finalObservation,
    this.blocker,
  }) : completedStepIds = List<String>.unmodifiable(completedStepIds),
       events = List<CodingLoopEvent>.unmodifiable(events),
       transactionReceipts = List<CodingTransactionReceipt>.unmodifiable(
         transactionReceipts,
       ),
       validationReceipts = List<CodingValidationReceipt>.unmodifiable(
         validationReceipts,
       );

  final CodingTaskStatus status;
  final CodingPlan? plan;
  final List<String> completedStepIds;
  final List<CodingLoopEvent> events;
  final List<CodingTransactionReceipt> transactionReceipts;
  final List<CodingValidationReceipt> validationReceipts;
  final int repairCount;
  final CodingObservation? finalObservation;
  final CodingBlocker? blocker;
}

final class CodingLoop {
  const CodingLoop({
    required this.planner,
    required this.workspace,
    required this.approval,
    required this.steering,
    required this.validationPlanner,
  });

  final CodingPlanner planner;
  final CodingWorkspacePort workspace;
  final CodingApprovalPort approval;
  final CodingSteeringPort steering;
  final ValidationPlanner validationPlanner;

  Future<CodingTaskOutcome> run(
    CodingTask task,
    CodingSessionContext session,
  ) async {
    final guard = LoopGuard(task.budget);
    final events = <CodingLoopEvent>[];
    final transactions = <CodingTransactionReceipt>[];
    final validations = <CodingValidationReceipt>[];
    final completed = <String>{};
    var repairCount = 0;
    CodingPlan? plan;
    CodingObservation? observation;

    CodingTaskOutcome outcome(
      CodingTaskStatus status, {
      CodingBlocker? blocker,
    }) => CodingTaskOutcome(
      status: status,
      plan: plan,
      completedStepIds: completed.toList(growable: false),
      events: events,
      transactionReceipts: transactions,
      validationReceipts: validations,
      repairCount: repairCount,
      finalObservation: observation,
      blocker: blocker,
    );

    Future<void> checkpoint(String transition, {String? stepId}) async {
      _throwIfInterrupted(session);
      if (!guard.advance()) {
        throw const _LoopAbort(
          CodingBlockerCode.budgetExceeded,
          'Coding loop transition budget was exhausted.',
        );
      }
      CodingSteeringDirective directive;
      try {
        directive = await _bounded(session, () => steering.poll(task.id));
      } on _LoopAbort {
        rethrow;
      } on Object {
        throw const _LoopAbort(
          CodingBlockerCode.capabilityDenied,
          'Steering channel is unavailable.',
        );
      }
      if (directive.kind == CodingSteeringKind.block) {
        throw const _LoopAbort(
          CodingBlockerCode.steered,
          'User steering stopped the current task.',
        );
      }
      events.add(
        CodingLoopEvent(
          transition: transition,
          stepId: stepId,
          workspaceRevision: observation?.workspaceRevision,
        ),
      );
    }

    try {
      await checkpoint('observe');
      try {
        observation = await _bounded(
          session,
          () => workspace.observe(task, session.cancellation),
        );
      } on _LoopAbort {
        rethrow;
      } on Object {
        throw const _LoopAbort(
          CodingBlockerCode.capabilityDenied,
          'Workspace facts are unavailable.',
        );
      }

      await checkpoint('plan');
      try {
        plan = await _bounded(
          session,
          () => planner.createPlan(task, observation!, session.cancellation),
        );
      } on _LoopAbort {
        rethrow;
      } on Object {
        throw const _LoopAbort(
          CodingBlockerCode.acceptanceUnavailable,
          'A valid coding plan could not be produced.',
        );
      }
      _validatePlan(task, plan!);

      while (completed.length < plan.steps.length) {
        final ready = plan.readySteps(completed);
        if (ready.isEmpty) {
          throw const _LoopAbort(
            CodingBlockerCode.acceptanceUnavailable,
            'No prerequisite-ready plan step is available.',
          );
        }
        final step = ready.first;
        var repairsForStep = 0;
        RepairFeedback? repair;

        while (true) {
          await checkpoint('propose', stepId: step.id);
          CodingStepAction action;
          try {
            action = await _bounded(
              session,
              () => planner.propose(
                task,
                plan!,
                step,
                observation!,
                repair,
                session.cancellation,
              ),
            );
          } on _LoopAbort {
            rethrow;
          } on Object {
            throw const _LoopAbort(
              CodingBlockerCode.acceptanceUnavailable,
              'A valid step proposal could not be produced.',
            );
          }
          _validateAction(task, step, observation!, action);

          await checkpoint('preview', stepId: step.id);
          CodingChangePreview preview;
          try {
            preview = await _bounded(
              session,
              () => workspace.preview(action.changeSet, session.cancellation),
            );
          } on _LoopAbort {
            rethrow;
          } on Object {
            throw const _LoopAbort(
              CodingBlockerCode.capabilityDenied,
              'Workspace transaction preview is unavailable.',
            );
          }
          if (!_sameChangeSet(preview.changeSet, action.changeSet) ||
              preview.id.trim().isEmpty) {
            throw const _LoopAbort(
              CodingBlockerCode.capabilityDenied,
              'Workspace returned an invalid transaction preview.',
            );
          }
          if (preview.outcome != CodingTransactionOutcome.ready) {
            throw _transactionAbort(preview.outcome);
          }

          await checkpoint('approve', stepId: step.id);
          final approved = await _bounded(
            session,
            () => approval.approve(preview, session.cancellation),
          );
          if (!approved) {
            throw const _LoopAbort(
              CodingBlockerCode.permissionDenied,
              'The change proposal was not approved.',
            );
          }

          await checkpoint('commit', stepId: step.id);
          CodingTransactionReceipt receipt;
          try {
            receipt = await _bounded(
              session,
              () => workspace.commit(preview.id, session.cancellation),
            );
          } on _LoopAbort {
            rethrow;
          } on Object {
            throw const _LoopAbort(
              CodingBlockerCode.capabilityDenied,
              'Workspace transaction commit is unavailable.',
            );
          }
          if (receipt.outcome != CodingTransactionOutcome.committed) {
            throw _transactionAbort(receipt.outcome);
          }
          if (receipt.id.trim().isEmpty ||
              receipt.workspaceRevision <= observation.workspaceRevision ||
              receipt.effectId.trim().isEmpty) {
            throw const _LoopAbort(
              CodingBlockerCode.capabilityDenied,
              'Workspace returned an invalid effect receipt.',
            );
          }
          transactions.add(receipt);

          await checkpoint('refresh', stepId: step.id);
          try {
            observation = await _bounded(
              session,
              () => workspace.observe(task, session.cancellation),
            );
          } on _LoopAbort {
            rethrow;
          } on Object {
            throw const _LoopAbort(
              CodingBlockerCode.capabilityDenied,
              'Post-edit workspace facts are unavailable.',
            );
          }
          if (observation.workspaceRevision != receipt.workspaceRevision ||
              observation.provenance.trim().isEmpty) {
            throw const _LoopAbort(
              CodingBlockerCode.capabilityDenied,
              'Post-edit facts do not match the committed revision.',
            );
          }

          List<CodingValidationRequest> requests;
          try {
            requests = validationPlanner.plan(
              task: task,
              step: step,
              changeSet: action.changeSet,
            );
          } on Object {
            throw const _LoopAbort(
              CodingBlockerCode.acceptanceUnavailable,
              'Focused validation could not be planned.',
            );
          }
          await checkpoint('validate', stepId: step.id);
          List<CodingValidationReceipt> stepReceipts;
          try {
            stepReceipts = await Future.wait(
              requests.map(
                (request) => _bounded(
                  session,
                  () => workspace.validate(
                    request,
                    observation!.workspaceRevision,
                    session.cancellation,
                  ),
                ),
              ),
            );
          } on _LoopAbort {
            rethrow;
          } on Object {
            throw const _LoopAbort(
              CodingBlockerCode.capabilityDenied,
              'Focused validation is unavailable.',
            );
          }
          final receiptsMatchRequests =
              stepReceipts.length == requests.length &&
              List<bool>.generate(stepReceipts.length, (index) {
                final receipt = stepReceipts[index];
                final request = requests[index];
                return receipt.kind == request.kind &&
                    receipt.scope == request.scope &&
                    receipt.id.trim().isNotEmpty &&
                    receipt.workspaceRevision ==
                        observation!.workspaceRevision &&
                    receipt.fingerprint.trim().isNotEmpty &&
                    receipt.provenance.trim().isNotEmpty;
              }).every((matches) => matches);
          if (!receiptsMatchRequests) {
            throw const _LoopAbort(
              CodingBlockerCode.capabilityDenied,
              'Validation receipts are not revision-bound facts.',
            );
          }
          validations.addAll(stepReceipts);
          final failures = stepReceipts
              .where(
                (receipt) => receipt.outcome != CodingValidationOutcome.passed,
              )
              .toList(growable: false);
          if (failures.isEmpty) {
            completed.add(step.id);
            break;
          }
          if (failures.any(
            (receipt) => guard.recordFailure(step.id, receipt.fingerprint),
          )) {
            throw const _LoopAbort(
              CodingBlockerCode.repeatedFailure,
              'The same validation failure repeated without progress.',
            );
          }
          if (repairsForStep >= task.budget.maxRepairsPerStep) {
            throw const _LoopAbort(
              CodingBlockerCode.validationFailed,
              'Focused validation failed after bounded repairs.',
            );
          }
          repairsForStep += 1;
          repairCount += 1;
          repair = RepairFeedback(
            attempt: repairsForStep,
            validationReceipts: failures,
            observation: observation,
          );
        }
      }

      return outcome(CodingTaskStatus.completed);
    } on _LoopAbort catch (abort) {
      return outcome(
        abort.code == null
            ? CodingTaskStatus.cancelled
            : CodingTaskStatus.blocked,
        blocker: abort.code == null
            ? null
            : CodingBlocker(code: abort.code!, message: abort.message),
      );
    } on Object {
      return outcome(
        CodingTaskStatus.blocked,
        blocker: const CodingBlocker(
          code: CodingBlockerCode.capabilityDenied,
          message: 'Coding loop failed closed on an untyped dependency error.',
        ),
      );
    }
  }

  static void _validatePlan(CodingTask task, CodingPlan plan) {
    if (plan.taskId != task.id ||
        plan.steps.length > task.budget.maxPlanSteps ||
        plan.steps.any(
          (step) =>
              !task.allowedResources.containsAll(step.ownedResources) ||
              step.validations.any(
                (target) => !task.allowedResources.contains(target.scope),
              ),
        )) {
      throw const _LoopAbort(
        CodingBlockerCode.acceptanceUnavailable,
        'Coding plan exceeds task ownership or budget.',
      );
    }
  }

  static void _validateAction(
    CodingTask task,
    CodingStep step,
    CodingObservation observation,
    CodingStepAction action,
  ) {
    final changeSet = action.changeSet;
    if (changeSet.stepId != step.id ||
        changeSet.baseWorkspaceRevision != observation.workspaceRevision) {
      throw const _LoopAbort(
        CodingBlockerCode.staleRevision,
        'Step proposal is not based on current workspace facts.',
      );
    }
    if (changeSet.resources.length > task.budget.maxChangedResources ||
        changeSet.resources.any(
          (resource) =>
              !task.allowedResources.contains(resource.resource) ||
              !step.ownedResources.contains(resource.resource) ||
              observation.documentRevisions[resource.resource] !=
                  resource.baseDocumentRevision,
        )) {
      throw const _LoopAbort(
        CodingBlockerCode.acceptanceUnavailable,
        'Step proposal exceeds ownership or document revisions.',
      );
    }
  }

  static bool _sameChangeSet(
    CodingChangeSet previewed,
    CodingChangeSet proposed,
  ) {
    if (previewed.id != proposed.id ||
        previewed.stepId != proposed.stepId ||
        previewed.baseWorkspaceRevision != proposed.baseWorkspaceRevision ||
        previewed.resources.length != proposed.resources.length) {
      return false;
    }
    final proposedByResource = <String, CodingResourceReplacement>{
      for (final resource in proposed.resources) resource.resource: resource,
    };
    for (final resource in previewed.resources) {
      final expected = proposedByResource[resource.resource];
      if (expected == null ||
          resource.baseDocumentRevision != expected.baseDocumentRevision ||
          resource.replacement != expected.replacement) {
        return false;
      }
    }
    return true;
  }

  static _LoopAbort _transactionAbort(CodingTransactionOutcome outcome) =>
      switch (outcome) {
        CodingTransactionOutcome.conflict => const _LoopAbort(
          CodingBlockerCode.staleRevision,
          'Workspace transaction conflicted with a newer revision.',
        ),
        CodingTransactionOutcome.denied => const _LoopAbort(
          CodingBlockerCode.permissionDenied,
          'Workspace transaction was denied.',
        ),
        CodingTransactionOutcome.capabilityUnavailable => const _LoopAbort(
          CodingBlockerCode.capabilityDenied,
          'Workspace transaction capability is unavailable.',
        ),
        _ => const _LoopAbort(
          CodingBlockerCode.capabilityDenied,
          'Workspace transaction failed.',
        ),
      };

  static void _throwIfInterrupted(CodingSessionContext session) {
    if (session.cancellation.isCancelled) {
      throw const _LoopAbort.cancelled();
    }
    final deadline = session.deadline;
    if (deadline != null && !DateTime.now().isBefore(deadline)) {
      throw const _LoopAbort(
        CodingBlockerCode.deadline,
        'Coding loop deadline was reached.',
      );
    }
  }

  static Future<T> _bounded<T>(
    CodingSessionContext session,
    Future<T> Function() operation,
  ) async {
    _throwIfInterrupted(session);
    final abort = Completer<T>();
    final subscription = session.cancellation.cancellations.listen((_) {
      if (!abort.isCompleted) {
        abort.completeError(const _LoopAbort.cancelled());
      }
    });
    Timer? timer;
    final deadline = session.deadline;
    if (deadline != null) {
      timer = Timer(deadline.difference(DateTime.now()), () {
        if (!abort.isCompleted) {
          abort.completeError(
            const _LoopAbort(
              CodingBlockerCode.deadline,
              'Coding loop deadline was reached.',
            ),
          );
        }
      });
    }
    try {
      return await Future.any<T>(<Future<T>>[operation(), abort.future]);
    } finally {
      timer?.cancel();
      await subscription.cancel();
    }
  }
}

final class _LoopAbort implements Exception {
  const _LoopAbort(this.code, this.message);

  const _LoopAbort.cancelled()
    : code = null,
      message = 'Coding loop was cancelled.';

  final CodingBlockerCode? code;
  final String message;
}
