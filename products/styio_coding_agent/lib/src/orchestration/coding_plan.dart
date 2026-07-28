library;

import '../cancellation.dart';

enum CodingValidationKind { analyze, test, format, custom }

final class CodingLoopBudget {
  const CodingLoopBudget({
    required this.maxPlanSteps,
    required this.maxTransitions,
    required this.maxRepairsPerStep,
    required this.maxRepeatedFailures,
    required this.maxChangedResources,
  });

  final int maxPlanSteps;
  final int maxTransitions;
  final int maxRepairsPerStep;
  final int maxRepeatedFailures;
  final int maxChangedResources;

  bool get isValid =>
      maxPlanSteps > 0 &&
      maxTransitions > 0 &&
      maxRepairsPerStep >= 0 &&
      maxRepeatedFailures > 0 &&
      maxChangedResources > 0;
}

final class CodingTask {
  CodingTask({
    required this.id,
    required this.goal,
    required this.rootId,
    required Set<String> allowedResources,
    required this.budget,
  }) : allowedResources = Set<String>.unmodifiable(allowedResources) {
    if (id.trim().isEmpty ||
        goal.trim().isEmpty ||
        rootId.trim().isEmpty ||
        this.allowedResources.isEmpty ||
        this.allowedResources.any(
          (resource) => !_isNormalizedResource(resource),
        ) ||
        !budget.isValid) {
      throw ArgumentError('Coding task fields or budgets are invalid.');
    }
  }

  final String id;
  final String goal;
  final String rootId;
  final Set<String> allowedResources;
  final CodingLoopBudget budget;
}

bool _isNormalizedResource(String resource) {
  if (resource.isEmpty ||
      resource != resource.trim() ||
      resource.startsWith('/') ||
      resource.contains(r'\') ||
      resource.contains(':') ||
      resource.contains('*') ||
      resource.contains('?')) {
    return false;
  }
  final segments = resource.split('/');
  return segments.every(
    (segment) => segment.isNotEmpty && segment != '.' && segment != '..',
  );
}

final class CodingValidationTarget {
  const CodingValidationTarget({
    required this.id,
    required this.kind,
    required this.scope,
  });

  final String id;
  final CodingValidationKind kind;
  final String scope;
}

final class CodingStep {
  CodingStep({
    required this.id,
    required this.title,
    required Set<String> prerequisites,
    required Set<String> ownedResources,
    required Set<String> acceptanceCriteria,
    required List<CodingValidationTarget> validations,
  }) : prerequisites = Set<String>.unmodifiable(prerequisites),
       ownedResources = Set<String>.unmodifiable(ownedResources),
       acceptanceCriteria = Set<String>.unmodifiable(acceptanceCriteria),
       validations = List<CodingValidationTarget>.unmodifiable(validations) {
    if (id.trim().isEmpty ||
        title.trim().isEmpty ||
        this.ownedResources.isEmpty ||
        this.acceptanceCriteria.isEmpty ||
        this.validations.isEmpty ||
        this.validations.any(
          (target) => target.id.isEmpty || target.scope.trim().isEmpty,
        )) {
      throw ArgumentError('Coding step fields cannot be empty.');
    }
  }

  final String id;
  final String title;
  final Set<String> prerequisites;
  final Set<String> ownedResources;
  final Set<String> acceptanceCriteria;
  final List<CodingValidationTarget> validations;
}

final class CodingPlan {
  CodingPlan({required this.taskId, required List<CodingStep> steps})
    : steps = List<CodingStep>.unmodifiable(steps),
      _byId = <String, CodingStep>{for (final step in steps) step.id: step} {
    if (taskId.trim().isEmpty ||
        this.steps.isEmpty ||
        _byId.length != this.steps.length) {
      throw ArgumentError('Plan task and step IDs must be unique.');
    }
    for (final step in this.steps) {
      if (step.prerequisites.contains(step.id) ||
          step.prerequisites.any((id) => !_byId.containsKey(id))) {
        throw ArgumentError('Plan contains an invalid prerequisite.');
      }
    }
    if (_topologicalOrder().length != this.steps.length) {
      throw ArgumentError('Plan prerequisites contain a cycle.');
    }
    _validateOverlappingOwnership();
  }

  final String taskId;
  final List<CodingStep> steps;
  final Map<String, CodingStep> _byId;

  CodingStep? find(String id) => _byId[id];

  List<CodingStep> readySteps(Set<String> completedStepIds) {
    final ready =
        steps
            .where(
              (step) =>
                  !completedStepIds.contains(step.id) &&
                  step.prerequisites.every(completedStepIds.contains),
            )
            .toList(growable: false)
          ..sort((left, right) => left.id.compareTo(right.id));
    return List<CodingStep>.unmodifiable(ready);
  }

  List<String> _topologicalOrder() {
    final completed = <String>{};
    final order = <String>[];
    while (order.length < steps.length) {
      final ready = readySteps(completed);
      if (ready.isEmpty) break;
      for (final step in ready) {
        completed.add(step.id);
        order.add(step.id);
      }
    }
    return order;
  }

  void _validateOverlappingOwnership() {
    bool dependsOn(String stepId, String possibleAncestor) {
      final seen = <String>{};
      final pending = <String>[stepId];
      while (pending.isNotEmpty) {
        final current = pending.removeLast();
        if (!seen.add(current)) continue;
        for (final prerequisite in _byId[current]!.prerequisites) {
          if (prerequisite == possibleAncestor) return true;
          pending.add(prerequisite);
        }
      }
      return false;
    }

    for (var leftIndex = 0; leftIndex < steps.length; leftIndex += 1) {
      for (
        var rightIndex = leftIndex + 1;
        rightIndex < steps.length;
        rightIndex += 1
      ) {
        final left = steps[leftIndex];
        final right = steps[rightIndex];
        final overlaps = left.ownedResources.any(right.ownedResources.contains);
        if (overlaps &&
            !dependsOn(left.id, right.id) &&
            !dependsOn(right.id, left.id)) {
          throw ArgumentError(
            'Overlapping step ownership must be prerequisite-ordered.',
          );
        }
      }
    }
  }
}

final class CodingObservation {
  CodingObservation({
    required this.workspaceRevision,
    required Map<String, int> documentRevisions,
    required Map<String, Object?> facts,
    required this.provenance,
  }) : documentRevisions = Map<String, int>.unmodifiable(documentRevisions),
       facts = Map<String, Object?>.unmodifiable(
         facts.map(
           (key, value) => MapEntry<String, Object?>(key, _freezeFact(value)),
         ),
       ) {
    if (workspaceRevision < 0 || provenance.trim().isEmpty) {
      throw ArgumentError('Observation revision and provenance are invalid.');
    }
  }

  final int workspaceRevision;
  final Map<String, int> documentRevisions;
  final Map<String, Object?> facts;
  final String provenance;
}

Object? _freezeFact(Object? value) => switch (value) {
  Map<Object?, Object?> map => Map<Object?, Object?>.unmodifiable(
    map.map((key, item) => MapEntry(key, _freezeFact(item))),
  ),
  List<Object?> list => List<Object?>.unmodifiable(list.map(_freezeFact)),
  Set<Object?> set => Set<Object?>.unmodifiable(set.map(_freezeFact)),
  _ => value,
};

final class CodingResourceReplacement {
  const CodingResourceReplacement({
    required this.resource,
    required this.baseDocumentRevision,
    required this.replacement,
  });

  final String resource;
  final int baseDocumentRevision;
  final String replacement;
}

final class CodingChangeSet {
  CodingChangeSet({
    required this.id,
    required this.stepId,
    required this.baseWorkspaceRevision,
    required List<CodingResourceReplacement> resources,
  }) : resources = List<CodingResourceReplacement>.unmodifiable(resources) {
    if (id.trim().isEmpty ||
        stepId.trim().isEmpty ||
        baseWorkspaceRevision < 0 ||
        this.resources.isEmpty ||
        this.resources.map((item) => item.resource).toSet().length !=
            this.resources.length) {
      throw ArgumentError('Coding change set is invalid.');
    }
  }

  final String id;
  final String stepId;
  final int baseWorkspaceRevision;
  final List<CodingResourceReplacement> resources;
}

final class CodingStepAction {
  const CodingStepAction({required this.changeSet});

  final CodingChangeSet changeSet;
}

enum CodingTransactionOutcome {
  ready,
  committed,
  conflict,
  denied,
  capabilityUnavailable,
  failed,
}

final class CodingChangePreview {
  const CodingChangePreview({
    required this.id,
    required this.changeSet,
    required this.outcome,
  });

  final String id;
  final CodingChangeSet changeSet;
  final CodingTransactionOutcome outcome;
}

final class CodingTransactionReceipt {
  const CodingTransactionReceipt({
    required this.id,
    required this.outcome,
    required this.workspaceRevision,
    required this.effectId,
  });

  final String id;
  final CodingTransactionOutcome outcome;
  final int workspaceRevision;
  final String effectId;
}

final class CodingValidationRequest {
  const CodingValidationRequest({
    required this.id,
    required this.kind,
    required this.scope,
  });

  final String id;
  final CodingValidationKind kind;
  final String scope;
}

enum CodingValidationOutcome { passed, failed, unavailable }

final class CodingValidationReceipt {
  const CodingValidationReceipt({
    required this.id,
    required this.kind,
    required this.scope,
    required this.workspaceRevision,
    required this.outcome,
    required this.fingerprint,
    required this.provenance,
  });

  final String id;
  final CodingValidationKind kind;
  final String scope;
  final int workspaceRevision;
  final CodingValidationOutcome outcome;
  final String fingerprint;
  final String provenance;
}

abstract interface class CodingWorkspacePort {
  Future<CodingObservation> observe(
    CodingTask task,
    AgentCancellationToken cancellation,
  );

  Future<CodingChangePreview> preview(
    CodingChangeSet changeSet,
    AgentCancellationToken cancellation,
  );

  Future<CodingTransactionReceipt> commit(
    String previewId,
    AgentCancellationToken cancellation,
  );

  Future<CodingValidationReceipt> validate(
    CodingValidationRequest request,
    int expectedWorkspaceRevision,
    AgentCancellationToken cancellation,
  );
}

abstract interface class CodingApprovalPort {
  Future<bool> approve(
    CodingChangePreview preview,
    AgentCancellationToken cancellation,
  );
}

enum CodingSteeringKind { continueTask, block }

final class CodingSteeringDirective {
  const CodingSteeringDirective.continueTask()
    : kind = CodingSteeringKind.continueTask,
      reason = '';

  const CodingSteeringDirective.block(this.reason)
    : kind = CodingSteeringKind.block;

  final CodingSteeringKind kind;
  final String reason;
}

abstract interface class CodingSteeringPort {
  Future<CodingSteeringDirective> poll(String taskId);
}

final class RepairFeedback {
  RepairFeedback({
    required this.attempt,
    required List<CodingValidationReceipt> validationReceipts,
    required this.observation,
  }) : validationReceipts = List<CodingValidationReceipt>.unmodifiable(
         validationReceipts,
       );

  final int attempt;
  final List<CodingValidationReceipt> validationReceipts;
  final CodingObservation observation;
}

abstract interface class CodingPlanner {
  Future<CodingPlan> createPlan(
    CodingTask task,
    CodingObservation observation,
    AgentCancellationToken cancellation,
  );

  Future<CodingStepAction> propose(
    CodingTask task,
    CodingPlan plan,
    CodingStep step,
    CodingObservation observation,
    RepairFeedback? repair,
    AgentCancellationToken cancellation,
  );
}

final class CodingSessionContext {
  const CodingSessionContext({
    required this.sessionId,
    required this.cancellation,
    this.deadline,
  });

  final String sessionId;
  final AgentCancellationToken cancellation;
  final DateTime? deadline;
}
