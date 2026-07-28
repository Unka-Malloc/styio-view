library;

import 'task_graph.dart';

enum LeaseDecisionKind { granted, contended, invalid }

final class ResourceLeaseToken {
  ResourceLeaseToken({
    required this.id,
    required this.taskId,
    required Set<String> scopes,
  }) : scopes = Set<String>.unmodifiable(scopes);

  final int id;
  final String taskId;
  final Set<String> scopes;
}

final class LeaseDecision {
  LeaseDecision({
    required this.kind,
    required Set<String> conflictingTaskIds,
    this.token,
  }) : conflictingTaskIds = Set<String>.unmodifiable(conflictingTaskIds);

  final LeaseDecisionKind kind;
  final ResourceLeaseToken? token;
  final Set<String> conflictingTaskIds;
}

final class ResourceLeaseRegistry {
  final Map<int, ResourceLeaseToken> _active = <int, ResourceLeaseToken>{};
  int _sequence = 0;

  int get activeLeaseCount => _active.length;

  LeaseDecision acquire(String taskId, Set<String> normalizedScopes) {
    if (taskId.trim().isEmpty ||
        normalizedScopes.isEmpty ||
        normalizedScopes.any((scope) => !isNormalizedOwnership(scope))) {
      return LeaseDecision(
        kind: LeaseDecisionKind.invalid,
        conflictingTaskIds: const <String>{},
      );
    }
    final conflicts = <String>{};
    for (final lease in _active.values) {
      if (lease.scopes.any(
        (active) => normalizedScopes.any(
          (requested) => ownershipScopesOverlap(active, requested),
        ),
      )) {
        conflicts.add(lease.taskId);
      }
    }
    if (conflicts.isNotEmpty) {
      return LeaseDecision(
        kind: LeaseDecisionKind.contended,
        conflictingTaskIds: conflicts,
      );
    }
    final token = ResourceLeaseToken(
      id: ++_sequence,
      taskId: taskId,
      scopes: normalizedScopes,
    );
    _active[token.id] = token;
    return LeaseDecision(
      kind: LeaseDecisionKind.granted,
      token: token,
      conflictingTaskIds: const <String>{},
    );
  }

  bool release(ResourceLeaseToken token) =>
      identical(_active[token.id], token) && _active.remove(token.id) != null;
}
