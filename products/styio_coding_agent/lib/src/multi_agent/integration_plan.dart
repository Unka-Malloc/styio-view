library;

final class WorkerChangeSet {
  WorkerChangeSet({
    required this.id,
    required this.baseRevision,
    required Set<String> resources,
  }) : resources = Set<String>.unmodifiable(resources) {
    if (id.trim().isEmpty ||
        baseRevision.trim().isEmpty ||
        this.resources.isEmpty) {
      throw ArgumentError('Worker change set is invalid.');
    }
  }

  final String id;
  final String baseRevision;
  final Set<String> resources;
}

enum IntegrationCandidateStatus { ready, conflict }

final class IntegrationCandidate {
  const IntegrationCandidate({
    required this.taskId,
    required this.changeSet,
    required this.status,
    required this.requiresReview,
    required this.reason,
  });

  final String taskId;
  final WorkerChangeSet changeSet;
  final IntegrationCandidateStatus status;
  final bool requiresReview;
  final String reason;
}

enum IntegrationReviewDecision { approve, reject }

enum IntegrationReviewOutcome { approved, rejected, conflict }

final class IntegrationReviewReceipt {
  const IntegrationReviewReceipt({
    required this.taskId,
    required this.changeSetId,
    required this.outcome,
    required this.reason,
  });

  final String taskId;
  final String changeSetId;
  final IntegrationReviewOutcome outcome;
  final String reason;
}

final class IntegrationPlan {
  IntegrationPlan({required List<IntegrationCandidate> candidates})
    : candidates = List<IntegrationCandidate>.unmodifiable(
        List<IntegrationCandidate>.of(candidates)
          ..sort((left, right) => left.taskId.compareTo(right.taskId)),
      ),
      _byTaskId = <String, IntegrationCandidate>{
        for (final candidate in candidates) candidate.taskId: candidate,
      };

  factory IntegrationPlan.fromChanges({
    required String targetRevision,
    required Map<String, WorkerChangeSet> changes,
  }) {
    final acceptedScopes = <String>{};
    final candidates = <IntegrationCandidate>[];
    final ids = changes.keys.toList(growable: false)..sort();
    for (final taskId in ids) {
      final change = changes[taskId]!;
      final stale = change.baseRevision != targetRevision;
      final overlaps = change.resources.any(
        (resource) => acceptedScopes.any(
          (accepted) =>
              resource == accepted ||
              resource.startsWith('$accepted/') ||
              accepted.startsWith('$resource/'),
        ),
      );
      final conflict = stale || overlaps;
      candidates.add(
        IntegrationCandidate(
          taskId: taskId,
          changeSet: change,
          status: conflict
              ? IntegrationCandidateStatus.conflict
              : IntegrationCandidateStatus.ready,
          requiresReview: true,
          reason: stale
              ? 'Worker base revision differs from the integration target.'
              : overlaps
              ? 'Worker change overlaps an earlier integration candidate.'
              : '',
        ),
      );
      if (!conflict) acceptedScopes.addAll(change.resources);
    }
    return IntegrationPlan(candidates: candidates);
  }

  final List<IntegrationCandidate> candidates;
  final Map<String, IntegrationCandidate> _byTaskId;

  IntegrationReviewReceipt review({
    required String taskId,
    required IntegrationReviewDecision decision,
  }) {
    final candidate = _byTaskId[taskId];
    if (candidate == null) {
      return IntegrationReviewReceipt(
        taskId: taskId,
        changeSetId: '',
        outcome: IntegrationReviewOutcome.conflict,
        reason: 'Integration candidate is unavailable.',
      );
    }
    if (candidate.status == IntegrationCandidateStatus.conflict) {
      return IntegrationReviewReceipt(
        taskId: taskId,
        changeSetId: candidate.changeSet.id,
        outcome: IntegrationReviewOutcome.conflict,
        reason: candidate.reason,
      );
    }
    return IntegrationReviewReceipt(
      taskId: taskId,
      changeSetId: candidate.changeSet.id,
      outcome: decision == IntegrationReviewDecision.approve
          ? IntegrationReviewOutcome.approved
          : IntegrationReviewOutcome.rejected,
      reason: decision == IntegrationReviewDecision.approve
          ? 'Approved for an outer integration adapter.'
          : 'Reviewer rejected the candidate.',
    );
  }
}
