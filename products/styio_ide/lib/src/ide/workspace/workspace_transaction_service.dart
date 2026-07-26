import 'dart:async';
import 'dart:collection';

import 'workspace_change_set.dart';
import 'workspace_revision_service.dart';

enum WorkspaceTransactionOutcome {
  ready,
  committed,
  rejected,
  conflict,
  failed,
  rolledBack,
}

enum WorkspaceConflictKind {
  staleWorkspaceRevision,
  staleDocumentRevision,
  overlappingEdits,
  invalidRange,
  resourceUnavailable,
}

final class WorkspaceConflict {
  const WorkspaceConflict({
    required this.kind,
    required this.resourceId,
  });

  final WorkspaceConflictKind kind;
  final String? resourceId;
}

final class WorkspaceTransactionPreview {
  WorkspaceTransactionPreview({
    required this.id,
    required this.changeSetId,
    required this.outcome,
    required Iterable<WorkspaceConflict> conflicts,
  }) : conflicts = UnmodifiableListView<WorkspaceConflict>(
          List<WorkspaceConflict>.of(conflicts),
        );

  final String id;
  final String changeSetId;
  final WorkspaceTransactionOutcome outcome;
  final List<WorkspaceConflict> conflicts;
}

final class WorkspaceTransactionReceipt {
  const WorkspaceTransactionReceipt({
    required this.id,
    required this.outcome,
    required this.workspaceRevision,
  });

  final String id;
  final WorkspaceTransactionOutcome outcome;
  final int workspaceRevision;
}

abstract interface class WorkspaceTransactionService {
  Future<WorkspaceTransactionPreview> preview(WorkspaceChangeSet changeSet);

  Future<WorkspaceTransactionReceipt> commit(String previewId);

  Future<WorkspaceTransactionReceipt> reject(String previewId);

  Future<WorkspaceTransactionReceipt> rollback(String transactionId);
}

final class _PreparedPreview {
  const _PreparedPreview({
    required this.preview,
    required this.before,
    required this.replacements,
  });

  final WorkspaceTransactionPreview preview;
  final WorkspaceSnapshot before;
  final Map<String, String> replacements;
}

final class _CommittedTransaction {
  const _CommittedTransaction({
    required this.receipt,
    required this.before,
    required this.after,
  });

  final WorkspaceTransactionReceipt receipt;
  final WorkspaceSnapshot before;
  final WorkspaceSnapshot after;
}

/// Revision-bound transaction authority for user and Agent edits.
final class RevisionedWorkspaceTransactionService
    implements WorkspaceTransactionService {
  RevisionedWorkspaceTransactionService(this._revisions);

  final InMemoryWorkspaceRevisionService _revisions;
  final Map<String, _PreparedPreview> _previews = <String, _PreparedPreview>{};
  final Map<String, _CommittedTransaction> _committed =
      <String, _CommittedTransaction>{};
  Future<void> _commitLane = Future<void>.value();
  var _previewSequence = 0;
  var _receiptSequence = 0;

  @override
  Future<WorkspaceTransactionPreview> preview(
    WorkspaceChangeSet changeSet,
  ) async {
    final before = _revisions.snapshot();
    final conflicts = <WorkspaceConflict>[];
    final replacements = <String, String>{};

    if (changeSet.baseWorkspaceRevision != before.workspaceRevision) {
      conflicts.add(
        const WorkspaceConflict(
          kind: WorkspaceConflictKind.staleWorkspaceRevision,
          resourceId: null,
        ),
      );
    } else {
      for (final resource in changeSet.resources) {
        final document = before.documents[resource.resourceId];
        if (document == null) {
          conflicts.add(
            WorkspaceConflict(
              kind: WorkspaceConflictKind.resourceUnavailable,
              resourceId: resource.resourceId,
            ),
          );
          continue;
        }
        if (resource.baseDocumentRevision != document.revision) {
          conflicts.add(
            WorkspaceConflict(
              kind: WorkspaceConflictKind.staleDocumentRevision,
              resourceId: resource.resourceId,
            ),
          );
          continue;
        }
        final prepared = _prepareResource(document.text, resource);
        if (prepared.conflict != null) {
          conflicts.add(
            WorkspaceConflict(
              kind: prepared.conflict!,
              resourceId: resource.resourceId,
            ),
          );
        } else {
          replacements[resource.resourceId] = prepared.text!;
        }
      }
    }

    final preview = WorkspaceTransactionPreview(
      id: 'preview-${++_previewSequence}',
      changeSetId: changeSet.id,
      outcome: conflicts.isEmpty
          ? WorkspaceTransactionOutcome.ready
          : WorkspaceTransactionOutcome.conflict,
      conflicts: conflicts,
    );
    _previews[preview.id] = _PreparedPreview(
      preview: preview,
      before: before,
      replacements: Map<String, String>.unmodifiable(replacements),
    );
    return preview;
  }

  @override
  Future<WorkspaceTransactionReceipt> commit(String previewId) {
    return _serialize(() async {
      final prepared = _previews.remove(previewId);
      if (prepared == null) {
        return _receipt(WorkspaceTransactionOutcome.failed);
      }
      if (prepared.preview.outcome != WorkspaceTransactionOutcome.ready) {
        return _receipt(WorkspaceTransactionOutcome.conflict);
      }

      try {
        final after = _revisions.compareAndSwap(
          WorkspaceAtomicCommit(
            expectedWorkspaceRevision: prepared.before.workspaceRevision,
            expectedDocumentRevisions: <String, int>{
              for (final resourceId in prepared.replacements.keys)
                resourceId: prepared.before.document(resourceId).revision,
            },
            replacements: prepared.replacements,
          ),
        );
        final receipt = _receipt(
          WorkspaceTransactionOutcome.committed,
          workspaceRevision: after.workspaceRevision,
        );
        _committed[receipt.id] = _CommittedTransaction(
          receipt: receipt,
          before: prepared.before,
          after: after,
        );
        return receipt;
      } on WorkspaceRevisionConflict {
        return _receipt(WorkspaceTransactionOutcome.conflict);
      } on WorkspaceCommitFailure {
        return _receipt(WorkspaceTransactionOutcome.failed);
      }
    });
  }

  @override
  Future<WorkspaceTransactionReceipt> reject(String previewId) {
    return _serialize(() async {
      final removed = _previews.remove(previewId);
      return _receipt(
        removed == null
            ? WorkspaceTransactionOutcome.failed
            : WorkspaceTransactionOutcome.rejected,
      );
    });
  }

  @override
  Future<WorkspaceTransactionReceipt> rollback(String transactionId) {
    return _serialize(() async {
      final transaction = _committed.remove(transactionId);
      if (transaction == null) {
        return _receipt(WorkspaceTransactionOutcome.failed);
      }
      final replacements = <String, String>{
        for (final resourceId in transaction.after.documents.keys)
          if (transaction.before.documents.containsKey(resourceId) &&
              transaction.before.document(resourceId).text !=
                  transaction.after.document(resourceId).text)
            resourceId: transaction.before.document(resourceId).text,
      };
      try {
        final afterRollback = _revisions.compareAndSwap(
          WorkspaceAtomicCommit(
            expectedWorkspaceRevision: transaction.after.workspaceRevision,
            expectedDocumentRevisions: <String, int>{
              for (final resourceId in replacements.keys)
                resourceId: transaction.after.document(resourceId).revision,
            },
            replacements: replacements,
          ),
        );
        return _receipt(
          WorkspaceTransactionOutcome.rolledBack,
          workspaceRevision: afterRollback.workspaceRevision,
        );
      } on WorkspaceRevisionConflict {
        return _receipt(WorkspaceTransactionOutcome.conflict);
      } on WorkspaceCommitFailure {
        return _receipt(WorkspaceTransactionOutcome.failed);
      }
    });
  }

  _PreparedResource _prepareResource(
    String text,
    WorkspaceResourceChange resource,
  ) {
    final edits = List<WorkspaceTextChange>.of(resource.edits)
      ..sort((left, right) {
        final byStart = left.start.compareTo(right.start);
        return byStart == 0 ? left.end.compareTo(right.end) : byStart;
      });
    var previousEnd = -1;
    for (final edit in edits) {
      if (edit.start < 0 || edit.end < edit.start || edit.end > text.length) {
        return const _PreparedResource.conflict(
          WorkspaceConflictKind.invalidRange,
        );
      }
      if (edit.start < previousEnd) {
        return const _PreparedResource.conflict(
          WorkspaceConflictKind.overlappingEdits,
        );
      }
      previousEnd = edit.end;
    }

    var result = text;
    for (final edit in edits.reversed) {
      result = result.replaceRange(edit.start, edit.end, edit.replacement);
    }
    return _PreparedResource.text(result);
  }

  WorkspaceTransactionReceipt _receipt(
    WorkspaceTransactionOutcome outcome, {
    int? workspaceRevision,
  }) {
    return WorkspaceTransactionReceipt(
      id: 'transaction-${++_receiptSequence}',
      outcome: outcome,
      workspaceRevision:
          workspaceRevision ?? _revisions.snapshot().workspaceRevision,
    );
  }

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _commitLane = _commitLane.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

final class _PreparedResource {
  const _PreparedResource.text(this.text) : conflict = null;

  const _PreparedResource.conflict(this.conflict) : text = null;

  final String? text;
  final WorkspaceConflictKind? conflict;
}
