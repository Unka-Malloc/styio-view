import 'dart:async';
import 'dart:collection';

import 'package:vityo_agent_protocol/vityo_agent_protocol.dart';

import '../../agent_client/agent_client.dart';
import '../../workspace/workspace_change_set.dart';
import '../../workspace/workspace_transaction_service.dart';

enum CollaborationTaskStatus {
  active,
  waitingForUser,
  blocked,
  completed,
  failed,
  cancelled,
}

enum CollaborationTimelineKind {
  turn,
  plan,
  step,
  tool,
  artifact,
  diagnostic,
  receipt,
  terminal,
  other,
}

enum AgentChangeReviewDecision { commit, reject, revert }

final class CollaborationFailure implements Exception {
  const CollaborationFailure(this.code, this.message);

  final String code;
  final String message;

  @override
  String toString() => 'CollaborationFailure($code, $message)';
}

abstract interface class AgentWorkbenchCommandPort {
  Future<void> steer(String sessionId, String prompt);

  Future<void> cancel(String sessionId);

  Future<void> retry(String sessionId);

  Future<void> reconnect(String sessionId);

  Future<void> resolvePermission({
    required String sessionId,
    required String permissionId,
    required AgentPermissionDecision decision,
  });
}

final class CollaborationTimelineEntry {
  CollaborationTimelineEntry({
    required this.id,
    required this.sessionId,
    required this.kind,
    required this.label,
    required Map<String, Object?> payload,
  }) : payload = UnmodifiableMapView<String, Object?>(
         Map<String, Object?>.of(payload),
       );

  final String id;
  final String sessionId;
  final CollaborationTimelineKind kind;
  final String label;
  final Map<String, Object?> payload;
}

final class CollaborationPermissionProjection {
  CollaborationPermissionProjection._({
    required this.id,
    required this.sessionId,
    required Set<String> options,
    required Future<void> Function(AgentPermissionDecision decision) resolve,
  }) : options = Set<String>.unmodifiable(options),
       _resolve = resolve;

  final String id;
  final String sessionId;
  final Set<String> options;
  final Future<void> Function(AgentPermissionDecision decision) _resolve;

  Future<void> resolve(AgentPermissionDecision decision) => _resolve(decision);
}

final class AgentChangeReviewProjection {
  AgentChangeReviewProjection({
    required this.sessionId,
    required this.changeSet,
    required this.previewId,
    required this.outcome,
    required List<WorkspaceConflict> conflicts,
    this.transactionId,
  }) : conflicts = List<WorkspaceConflict>.unmodifiable(conflicts);

  final String sessionId;
  final WorkspaceChangeSet changeSet;
  final String previewId;
  final WorkspaceTransactionOutcome outcome;
  final List<WorkspaceConflict> conflicts;
  final String? transactionId;

  int get fileCount => changeSet.resources.length;

  int get hunkCount => changeSet.resources.fold<int>(
    0,
    (total, resource) => total + resource.edits.length,
  );

  AgentChangeReviewProjection withReceipt(
    WorkspaceTransactionReceipt receipt,
  ) => AgentChangeReviewProjection(
    sessionId: sessionId,
    changeSet: changeSet,
    previewId: previewId,
    outcome: receipt.outcome,
    conflicts: conflicts,
    transactionId: switch (receipt.outcome) {
      WorkspaceTransactionOutcome.committed => receipt.id,
      WorkspaceTransactionOutcome.failed => transactionId,
      _ => null,
    },
  );
}

final class CollaborationSessionProjection {
  CollaborationSessionProjection({
    required this.sessionId,
    required this.snapshotRevision,
    required this.title,
    required this.status,
    required List<CollaborationTimelineEntry> timeline,
    required this.droppedTimelineCount,
    required Map<String, CollaborationPermissionProjection> pendingPermissions,
    required Map<String, AgentChangeReviewProjection> changeReviews,
  }) : timeline = List<CollaborationTimelineEntry>.unmodifiable(timeline),
       pendingPermissions =
           UnmodifiableMapView<String, CollaborationPermissionProjection>(
             Map<String, CollaborationPermissionProjection>.of(
               pendingPermissions,
             ),
           ),
       changeReviews = UnmodifiableMapView<String, AgentChangeReviewProjection>(
         Map<String, AgentChangeReviewProjection>.of(changeReviews),
       );

  final String sessionId;
  final int snapshotRevision;
  final String title;
  final CollaborationTaskStatus status;
  final List<CollaborationTimelineEntry> timeline;
  final int droppedTimelineCount;
  final Map<String, CollaborationPermissionProjection> pendingPermissions;
  final Map<String, AgentChangeReviewProjection> changeReviews;

  bool get attentionRequired =>
      pendingPermissions.isNotEmpty ||
      changeReviews.values.any(
        (review) => review.outcome == WorkspaceTransactionOutcome.ready,
      );
}

final class CollaborationProjection {
  CollaborationProjection({
    required this.revision,
    required Map<String, CollaborationSessionProjection> sessions,
    required List<String> orderedSessionIds,
  }) : sessions = UnmodifiableMapView<String, CollaborationSessionProjection>(
         Map<String, CollaborationSessionProjection>.of(sessions),
       ),
       orderedSessionIds = List<String>.unmodifiable(orderedSessionIds);

  final int revision;
  final Map<String, CollaborationSessionProjection> sessions;
  final List<String> orderedSessionIds;

  int get attentionCount =>
      sessions.values.where((session) => session.attentionRequired).length;

  CollaborationSessionProjection session(String sessionId) {
    final result = sessions[sessionId];
    if (result == null) {
      throw CollaborationFailure(
        'unknown_session',
        'Session $sessionId is not available',
      );
    }
    return result;
  }
}

final class AgentCollaborationStore {
  AgentCollaborationStore({
    required AgentWorkbenchCommandPort commands,
    required WorkspaceTransactionService transactions,
    required this.maxTimelineEntriesPerSession,
    this.maxSessions = 32,
    this.maxResolvedPermissionIdsPerSession = 256,
    this.maxPendingPermissionsPerSession = 128,
    this.maxChangeReviewsPerSession = 64,
    this.maxResourcesPerChangeSet = 64,
    this.maxEditsPerChangeSet = 500,
    this.maxReplacementCharactersPerChangeSet = 200000,
  }) : _commands = commands,
       _transactions = transactions {
    if (maxTimelineEntriesPerSession <= 0 ||
        maxSessions <= 0 ||
        maxResolvedPermissionIdsPerSession <= 0 ||
        maxPendingPermissionsPerSession <= 0 ||
        maxChangeReviewsPerSession <= 0 ||
        maxResourcesPerChangeSet <= 0 ||
        maxEditsPerChangeSet <= 0 ||
        maxReplacementCharactersPerChangeSet <= 0) {
      throw ArgumentError.value(
        maxTimelineEntriesPerSession,
        'collaboration limits',
        'must all be positive',
      );
    }
  }

  final AgentWorkbenchCommandPort _commands;
  final WorkspaceTransactionService _transactions;
  final int maxTimelineEntriesPerSession;
  final int maxSessions;
  final int maxResolvedPermissionIdsPerSession;
  final int maxPendingPermissionsPerSession;
  final int maxChangeReviewsPerSession;
  final int maxResourcesPerChangeSet;
  final int maxEditsPerChangeSet;
  final int maxReplacementCharactersPerChangeSet;
  final Map<String, _SessionState> _sessions = <String, _SessionState>{};
  final List<String> _orderedSessionIds = <String>[];
  final Map<String, Future<void>> _lanes = <String, Future<void>>{};
  final StreamController<CollaborationProjection> _changes =
      StreamController<CollaborationProjection>.broadcast(sync: true);
  int _revision = 0;
  bool _closed = false;

  Stream<CollaborationProjection> get changes => _changes.stream;

  CollaborationProjection get projection => _project();

  Future<CollaborationProjection> apply(AgentSessionSnapshot snapshot) =>
      _serialize(snapshot.sessionId, () async {
        var state = _sessions[snapshot.sessionId];
        if (state == null) {
          if (_sessions.length >= maxSessions) {
            throw const CollaborationFailure(
              'session_limit_exceeded',
              'Agent collaboration session limit was reached',
            );
          }
          state = _SessionState(snapshot.sessionId);
          _sessions[snapshot.sessionId] = state;
          _orderedSessionIds.add(snapshot.sessionId);
        }
        if (snapshot.revision < state.snapshotRevision) {
          throw const CollaborationFailure(
            'stale_snapshot',
            'Session snapshot revision moved backwards',
          );
        }
        if (snapshot.revision == state.snapshotRevision) {
          return _project();
        }

        final timelineById = <String, CollaborationTimelineEntry>{};
        final orderedIds = <String>[];
        var title = state.title;
        var status = state.status;
        for (var index = 0; index < snapshot.updates.length; index += 1) {
          final update = snapshot.updates[index];
          if (update.sessionId != snapshot.sessionId) {
            throw const CollaborationFailure(
              'session_mismatch',
              'Snapshot contains an update for another session',
            );
          }
          if (update.kind == 'session_state') {
            final titleCandidate =
                update.payload['title'] ?? update.text ?? state.title;
            if (titleCandidate is! String || titleCandidate.length > 256) {
              throw const CollaborationFailure(
                'invalid_session_state',
                'Agent session title must be a bounded string',
              );
            }
            title = titleCandidate;
            status = _decodeStatus(update.payload['status']);
            continue;
          }
          if (update.kind == VityoCapability.workspaceChangeProposal) {
            continue;
          }
          final sourceId = update.payload['id']?.toString() ?? '$index';
          final id = '${snapshot.sessionId}:${update.kind}:$sourceId';
          if (!timelineById.containsKey(id)) {
            orderedIds.add(id);
          }
          timelineById[id] = CollaborationTimelineEntry(
            id: id,
            sessionId: snapshot.sessionId,
            kind: _decodeTimelineKind(update.kind),
            label:
                update.text ??
                update.payload['label']?.toString() ??
                update.kind,
            payload: update.payload,
          );
        }
        final locallyDropped = orderedIds.length > maxTimelineEntriesPerSession
            ? orderedIds.length - maxTimelineEntriesPerSession
            : 0;
        final visibleIds = locallyDropped == 0
            ? orderedIds
            : orderedIds.sublist(locallyDropped);
        if (_isTerminalStatus(status)) {
          state.permissions.clear();
        }
        state
          ..snapshotRevision = snapshot.revision
          ..title = title.isEmpty ? snapshot.sessionId : title
          ..status = status
          ..timeline = <CollaborationTimelineEntry>[
            for (final id in visibleIds) timelineById[id]!,
          ]
          ..droppedTimelineCount = snapshot.droppedUpdateCount + locallyDropped;
        _emit();
        return _project();
      });

  Future<CollaborationProjection> addPermission(
    AgentPermissionRequest request,
  ) => _serialize(request.sessionId, () async {
    final state = _requireSession(request.sessionId);
    if (_isTerminalStatus(state.status)) {
      return _project();
    }
    if (state.resolvedPermissionIds.contains(request.id)) {
      return _project();
    }
    final existing = state.permissions[request.id];
    if (existing != null) {
      if (existing.sessionId != request.sessionId) {
        throw const CollaborationFailure(
          'permission_session_mismatch',
          'Permission belongs to another session',
        );
      }
      return _project();
    }
    if (state.permissions.length >= maxPendingPermissionsPerSession) {
      throw const CollaborationFailure(
        'permission_limit_exceeded',
        'Agent permission projection limit was reached',
      );
    }
    state.permissions[request.id] = request;
    _emit();
    return _project();
  });

  Future<void> resolvePermission({
    required String sessionId,
    required String permissionId,
    required AgentPermissionDecision decision,
  }) => _serialize<void>(sessionId, () async {
    final state = _requireSession(sessionId);
    final request = state.permissions[permissionId];
    if (request == null) {
      if (state.resolvedPermissionIds.contains(permissionId)) {
        throw const CollaborationFailure(
          'permission_already_resolved',
          'Permission has already been resolved',
        );
      }
      final owner = _sessions.values
          .where((candidate) => candidate.permissions.containsKey(permissionId))
          .firstOrNull;
      if (owner != null) {
        throw const CollaborationFailure(
          'permission_session_mismatch',
          'Permission belongs to another session',
        );
      }
      throw const CollaborationFailure(
        'unknown_permission',
        'Permission request is not available',
      );
    }
    if (!_decisionOffered(request, decision)) {
      throw const CollaborationFailure(
        'permission_option_unavailable',
        'Permission decision was not offered',
      );
    }
    await _commands.resolvePermission(
      sessionId: sessionId,
      permissionId: permissionId,
      decision: decision,
    );
    state.permissions.remove(permissionId);
    state.resolvedPermissionIds.add(permissionId);
    while (state.resolvedPermissionIds.length >
        maxResolvedPermissionIdsPerSession) {
      state.resolvedPermissionIds.remove(state.resolvedPermissionIds.first);
    }
    _emit();
  });

  Future<AgentChangeReviewProjection> proposeChange({
    required String sessionId,
    required WorkspaceChangeSet changeSet,
  }) => _serialize(sessionId, () async {
    final state = _requireSession(sessionId);
    final existing = state.changeReviews[changeSet.id];
    if (existing != null) {
      if (!_sameChangeSet(existing.changeSet, changeSet)) {
        throw const CollaborationFailure(
          'change_set_id_collision',
          'Agent reused a change set identifier with different content',
        );
      }
      return existing;
    }
    _validateChangeSet(changeSet);
    if (state.changeReviews.length >= maxChangeReviewsPerSession) {
      throw const CollaborationFailure(
        'change_review_limit_exceeded',
        'Agent change review limit was reached',
      );
    }
    final preview = await _transactions.preview(changeSet);
    final review = AgentChangeReviewProjection(
      sessionId: sessionId,
      changeSet: changeSet,
      previewId: preview.id,
      outcome: preview.outcome,
      conflicts: preview.conflicts,
    );
    state.changeReviews[changeSet.id] = review;
    _emit();
    return review;
  });

  Future<AgentChangeReviewProjection> resolveChange({
    required String sessionId,
    required String changeSetId,
    required AgentChangeReviewDecision decision,
  }) => _serialize(sessionId, () async {
    final state = _requireSession(sessionId);
    final review = state.changeReviews[changeSetId];
    if (review == null) {
      throw const CollaborationFailure(
        'unknown_change',
        'Change review is not available',
      );
    }
    final WorkspaceTransactionReceipt receipt;
    switch (decision) {
      case AgentChangeReviewDecision.commit:
        if (review.outcome != WorkspaceTransactionOutcome.ready) {
          throw const CollaborationFailure(
            'change_not_ready',
            'Only a ready preview can be committed',
          );
        }
        receipt = await _transactions.commit(review.previewId);
      case AgentChangeReviewDecision.reject:
        if (review.outcome != WorkspaceTransactionOutcome.ready) {
          throw const CollaborationFailure(
            'change_not_ready',
            'Only a ready preview can be rejected',
          );
        }
        receipt = await _transactions.reject(review.previewId);
      case AgentChangeReviewDecision.revert:
        if (review.outcome != WorkspaceTransactionOutcome.committed &&
                review.outcome != WorkspaceTransactionOutcome.failed ||
            review.transactionId == null) {
          throw const CollaborationFailure(
            'change_not_committed',
            'Only a committed change can be reverted',
          );
        }
        receipt = await _transactions.rollback(review.transactionId!);
    }
    final updated = review.withReceipt(receipt);
    state.changeReviews[changeSetId] = updated;
    _emit();
    return updated;
  });

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await Future.wait<void>(_lanes.values.toList(growable: false));
    _lanes.clear();
    _sessions.clear();
    _orderedSessionIds.clear();
    await _changes.close();
  }

  Future<T> _serialize<T>(String sessionId, Future<T> Function() operation) {
    if (_closed) {
      return Future<T>.error(StateError('Agent collaboration store is closed'));
    }
    if (sessionId.trim().isEmpty || sessionId.length > 256) {
      return Future<T>.error(
        const CollaborationFailure(
          'invalid_session',
          'Agent collaboration session identifier must be bounded',
        ),
      );
    }
    if (!_sessions.containsKey(sessionId) &&
        !_lanes.containsKey(sessionId) &&
        <String>{..._sessions.keys, ..._lanes.keys}.length >= maxSessions) {
      return Future<T>.error(
        const CollaborationFailure(
          'session_limit_exceeded',
          'Agent collaboration session limit was reached',
        ),
      );
    }
    final completer = Completer<T>();
    final prior = _lanes[sessionId] ?? Future<void>.value();
    final next = prior.then((_) async {
      try {
        completer.complete(await operation());
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    final lane = next.then<void>((_) {}, onError: (_, __) {});
    _lanes[sessionId] = lane;
    unawaited(
      lane.then((_) {
        if (identical(_lanes[sessionId], lane)) {
          _lanes.remove(sessionId);
        }
      }),
    );
    return completer.future;
  }

  void _validateChangeSet(WorkspaceChangeSet changeSet) {
    if (changeSet.id.length > 256 ||
        changeSet.resources.isEmpty ||
        changeSet.resources.length > maxResourcesPerChangeSet) {
      throw const CollaborationFailure(
        'invalid_change_set',
        'Agent change set is empty or exceeds its resource limit',
      );
    }
    var editCount = 0;
    var replacementCharacters = 0;
    for (final resource in changeSet.resources) {
      if (resource.resourceId.length > 4096 ||
          resource.baseDocumentRevision < 0 ||
          resource.edits.isEmpty) {
        throw const CollaborationFailure(
          'invalid_change_set',
          'Agent change set contains an invalid resource',
        );
      }
      editCount += resource.edits.length;
      for (final edit in resource.edits) {
        replacementCharacters += edit.replacement.length;
      }
    }
    if (editCount > maxEditsPerChangeSet ||
        replacementCharacters > maxReplacementCharactersPerChangeSet) {
      throw const CollaborationFailure(
        'change_set_limit_exceeded',
        'Agent change set exceeds its edit or replacement limit',
      );
    }
  }

  _SessionState _requireSession(String sessionId) {
    final state = _sessions[sessionId];
    if (state == null) {
      throw CollaborationFailure(
        'unknown_session',
        'Session $sessionId is not available',
      );
    }
    return state;
  }

  void _emit() {
    _revision += 1;
    _changes.add(_project());
  }

  CollaborationProjection _project() => CollaborationProjection(
    revision: _revision,
    sessions: <String, CollaborationSessionProjection>{
      for (final entry in _sessions.entries)
        entry.key: entry.value.project(
          resolvePermission:
              ({
                required String permissionId,
                required AgentPermissionDecision decision,
              }) => resolvePermission(
                sessionId: entry.key,
                permissionId: permissionId,
                decision: decision,
              ),
        ),
    },
    orderedSessionIds: _orderedSessionIds,
  );
}

final class _SessionState {
  _SessionState(this.sessionId);

  final String sessionId;
  int snapshotRevision = -1;
  String title = '';
  CollaborationTaskStatus status = CollaborationTaskStatus.active;
  List<CollaborationTimelineEntry> timeline =
      const <CollaborationTimelineEntry>[];
  int droppedTimelineCount = 0;
  final Map<String, AgentPermissionRequest> permissions =
      <String, AgentPermissionRequest>{};
  final Set<String> resolvedPermissionIds = <String>{};
  final Map<String, AgentChangeReviewProjection> changeReviews =
      <String, AgentChangeReviewProjection>{};

  CollaborationSessionProjection project({
    required Future<void> Function({
      required String permissionId,
      required AgentPermissionDecision decision,
    })
    resolvePermission,
  }) => CollaborationSessionProjection(
    sessionId: sessionId,
    snapshotRevision: snapshotRevision,
    title: title.isEmpty ? sessionId : title,
    status: status,
    timeline: timeline,
    droppedTimelineCount: droppedTimelineCount,
    pendingPermissions: <String, CollaborationPermissionProjection>{
      for (final request in permissions.values)
        request.id: CollaborationPermissionProjection._(
          id: request.id,
          sessionId: sessionId,
          options: request.options,
          resolve: (decision) =>
              resolvePermission(permissionId: request.id, decision: decision),
        ),
    },
    changeReviews: changeReviews,
  );
}

CollaborationTaskStatus _decodeStatus(Object? value) => switch (value) {
  'waiting_for_user' => CollaborationTaskStatus.waitingForUser,
  'blocked' => CollaborationTaskStatus.blocked,
  'completed' => CollaborationTaskStatus.completed,
  'failed' => CollaborationTaskStatus.failed,
  'cancelled' => CollaborationTaskStatus.cancelled,
  _ => CollaborationTaskStatus.active,
};

bool _isTerminalStatus(CollaborationTaskStatus status) =>
    status == CollaborationTaskStatus.completed ||
    status == CollaborationTaskStatus.failed ||
    status == CollaborationTaskStatus.cancelled;

CollaborationTimelineKind _decodeTimelineKind(String value) => switch (value) {
  'turn' || 'message' || 'chunk' => CollaborationTimelineKind.turn,
  'plan' => CollaborationTimelineKind.plan,
  'step' => CollaborationTimelineKind.step,
  'tool' || 'tool_call' => CollaborationTimelineKind.tool,
  'artifact' => CollaborationTimelineKind.artifact,
  'diagnostic' => CollaborationTimelineKind.diagnostic,
  'receipt' || 'validation' => CollaborationTimelineKind.receipt,
  'terminal' || 'terminal_output' => CollaborationTimelineKind.terminal,
  _ => CollaborationTimelineKind.other,
};

bool _decisionOffered(
  AgentPermissionRequest request,
  AgentPermissionDecision decision,
) => switch (decision) {
  AgentPermissionDecision.allowOnce => request.options.contains('allow_once'),
  AgentPermissionDecision.rejectOnce => request.options.contains('reject_once'),
};

bool _sameChangeSet(WorkspaceChangeSet left, WorkspaceChangeSet right) {
  if (left.id != right.id ||
      left.baseWorkspaceRevision != right.baseWorkspaceRevision ||
      left.resources.length != right.resources.length) {
    return false;
  }
  for (
    var resourceIndex = 0;
    resourceIndex < left.resources.length;
    resourceIndex += 1
  ) {
    final leftResource = left.resources[resourceIndex];
    final rightResource = right.resources[resourceIndex];
    if (leftResource.resourceId != rightResource.resourceId ||
        leftResource.baseDocumentRevision !=
            rightResource.baseDocumentRevision ||
        leftResource.edits.length != rightResource.edits.length) {
      return false;
    }
    for (
      var editIndex = 0;
      editIndex < leftResource.edits.length;
      editIndex += 1
    ) {
      final leftEdit = leftResource.edits[editIndex];
      final rightEdit = rightResource.edits[editIndex];
      if (leftEdit.start != rightEdit.start ||
          leftEdit.end != rightEdit.end ||
          leftEdit.replacement != rightEdit.replacement) {
        return false;
      }
    }
  }
  return true;
}
