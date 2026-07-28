import 'dart:collection';

import 'workspace_change_set.dart';
import 'workspace_transaction_service.dart';

final class WorkspaceDocumentSnapshot {
  const WorkspaceDocumentSnapshot({
    required this.resourceId,
    required this.text,
    required this.revision,
    required this.workspaceRevision,
  });

  final String resourceId;
  final String text;
  final int revision;
  final int workspaceRevision;

  int get documentRevision => revision;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceDocumentSnapshot &&
      resourceId == other.resourceId &&
      text == other.text &&
      revision == other.revision &&
      workspaceRevision == other.workspaceRevision;

  @override
  int get hashCode => Object.hash(
        resourceId,
        text,
        revision,
        workspaceRevision,
      );
}

final class WorkspaceSnapshot {
  WorkspaceSnapshot({
    required this.workspaceRevision,
    required Map<String, WorkspaceDocumentSnapshot> documents,
  }) : documents = UnmodifiableMapView<String, WorkspaceDocumentSnapshot>(
          Map<String, WorkspaceDocumentSnapshot>.of(documents),
        );

  final int workspaceRevision;
  final Map<String, WorkspaceDocumentSnapshot> documents;

  WorkspaceDocumentSnapshot document(String resourceId) {
    final result = documents[resourceId];
    if (result == null) {
      throw StateError('Workspace resource is unavailable.');
    }
    return result;
  }

  @override
  bool operator ==(Object other) {
    if (other is! WorkspaceSnapshot ||
        workspaceRevision != other.workspaceRevision ||
        documents.length != other.documents.length) {
      return false;
    }
    for (final entry in documents.entries) {
      if (other.documents[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode {
    var result = workspaceRevision;
    final keys = documents.keys.toList(growable: false)..sort();
    for (final key in keys) {
      result = Object.hash(result, key, documents[key]);
    }
    return result;
  }
}

final class WorkspaceAtomicCommit {
  WorkspaceAtomicCommit({
    required this.expectedWorkspaceRevision,
    required Map<String, int> expectedDocumentRevisions,
    required Map<String, String> replacements,
  })  : expectedDocumentRevisions = Map<String, int>.unmodifiable(
          expectedDocumentRevisions,
        ),
        replacements = Map<String, String>.unmodifiable(replacements);

  final int expectedWorkspaceRevision;
  final Map<String, int> expectedDocumentRevisions;
  final Map<String, String> replacements;
}

final class WorkspaceRevisionConflict implements Exception {
  const WorkspaceRevisionConflict(this.kind);

  final WorkspaceConflictKind kind;
}

final class WorkspaceCommitFailure implements Exception {
  const WorkspaceCommitFailure();
}

/// Authoritative in-memory revision store.
///
/// The complete next state is built before the sole map swap. Fault injection
/// therefore cannot expose a partially changed workspace.
final class InMemoryWorkspaceRevisionService {
  InMemoryWorkspaceRevisionService({
    Map<String, String> initialDocuments = const <String, String>{},
  }) {
    initialize(initialDocuments);
  }

  var _workspaceRevision = 0;
  Map<String, WorkspaceDocumentSnapshot> _documents =
      <String, WorkspaceDocumentSnapshot>{};
  var _failNextCommit = false;

  WorkspaceSnapshot snapshot() => WorkspaceSnapshot(
        workspaceRevision: _workspaceRevision,
        documents: _documents,
      );

  void initialize(Map<String, String> documents) {
    if (_documents.isNotEmpty) {
      throw StateError('Workspace has already been initialized.');
    }
    final next = <String, WorkspaceDocumentSnapshot>{};
    for (final entry in documents.entries) {
      next[entry.key] = WorkspaceDocumentSnapshot(
        resourceId: entry.key,
        text: entry.value,
        revision: 0,
        workspaceRevision: 0,
      );
    }
    _documents = Map<String, WorkspaceDocumentSnapshot>.unmodifiable(next);
  }

  void failNextCommit() {
    _failNextCommit = true;
  }

  WorkspaceSnapshot compareAndSwap(WorkspaceAtomicCommit commit) {
    if (commit.expectedWorkspaceRevision != _workspaceRevision) {
      throw const WorkspaceRevisionConflict(
        WorkspaceConflictKind.staleWorkspaceRevision,
      );
    }
    for (final entry in commit.expectedDocumentRevisions.entries) {
      final document = _documents[entry.key];
      if (document == null) {
        throw const WorkspaceRevisionConflict(
          WorkspaceConflictKind.resourceUnavailable,
        );
      }
      if (document.revision != entry.value) {
        throw const WorkspaceRevisionConflict(
          WorkspaceConflictKind.staleDocumentRevision,
        );
      }
    }
    if (_failNextCommit) {
      _failNextCommit = false;
      throw const WorkspaceCommitFailure();
    }

    final nextWorkspaceRevision = _workspaceRevision + 1;
    final next = Map<String, WorkspaceDocumentSnapshot>.of(_documents);
    for (final entry in commit.replacements.entries) {
      final current = _documents[entry.key];
      if (current == null) {
        throw const WorkspaceRevisionConflict(
          WorkspaceConflictKind.resourceUnavailable,
        );
      }
      next[entry.key] = WorkspaceDocumentSnapshot(
        resourceId: entry.key,
        text: entry.value,
        revision: current.revision + 1,
        workspaceRevision: nextWorkspaceRevision,
      );
    }

    _documents = Map<String, WorkspaceDocumentSnapshot>.unmodifiable(next);
    _workspaceRevision = nextWorkspaceRevision;
    return snapshot();
  }
}

final class StandaloneWorkspaceSearchMatch {
  const StandaloneWorkspaceSearchMatch({
    required this.resourceId,
    required this.start,
    required this.end,
    required this.workspaceRevision,
  });

  final String resourceId;
  final int start;
  final int end;
  final int workspaceRevision;
}

/// Minimal standalone workspace composition with no Agent dependency.
final class StandaloneIdeWorkspace {
  StandaloneIdeWorkspace({
    required this.revisions,
    required this.transactions,
  });

  final InMemoryWorkspaceRevisionService revisions;
  final WorkspaceTransactionService transactions;
  final Map<String, String> _persisted = <String, String>{};
  var _isOpen = false;

  Future<void> open(Map<String, String> documents) async {
    if (_isOpen) {
      throw StateError('Workspace is already open.');
    }
    revisions.initialize(documents);
    _persisted
      ..clear()
      ..addAll(documents);
    _isOpen = true;
  }

  WorkspaceDocumentSnapshot openDocument(String resourceId) {
    _ensureOpen();
    return revisions.snapshot().document(resourceId);
  }

  Future<WorkspaceTransactionPreview> edit(WorkspaceChangeSet changeSet) {
    _ensureOpen();
    return transactions.preview(changeSet);
  }

  Future<void> save(String resourceId) async {
    _ensureOpen();
    _persisted[resourceId] = revisions.snapshot().document(resourceId).text;
  }

  String? persistedText(String resourceId) {
    _ensureOpen();
    return _persisted[resourceId];
  }

  List<StandaloneWorkspaceSearchMatch> search(String query) {
    _ensureOpen();
    if (query.isEmpty) {
      return const <StandaloneWorkspaceSearchMatch>[];
    }
    final snapshot = revisions.snapshot();
    final matches = <StandaloneWorkspaceSearchMatch>[];
    final resourceIds = snapshot.documents.keys.toList(growable: false)..sort();
    for (final resourceId in resourceIds) {
      final text = snapshot.document(resourceId).text;
      var offset = 0;
      while (offset <= text.length - query.length) {
        final found = text.indexOf(query, offset);
        if (found < 0) {
          break;
        }
        matches.add(
          StandaloneWorkspaceSearchMatch(
            resourceId: resourceId,
            start: found,
            end: found + query.length,
            workspaceRevision: snapshot.workspaceRevision,
          ),
        );
        offset = found + query.length;
      }
    }
    return List<StandaloneWorkspaceSearchMatch>.unmodifiable(matches);
  }

  void close() {
    _ensureOpen();
    _isOpen = false;
  }

  void _ensureOpen() {
    if (!_isOpen) {
      throw StateError('Workspace is closed.');
    }
  }
}
