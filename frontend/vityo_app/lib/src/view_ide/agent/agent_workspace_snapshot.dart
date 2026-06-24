import '../editor/document_state.dart';
import '../editor/editor_controller.dart';
import '../workspace/workspace_document_store_types.dart';
import 'agent_provider_adapter.dart';

enum AgentWorkspaceSnapshotCaptureStatus { captured, partial, empty }

extension AgentWorkspaceSnapshotCaptureStatusX
    on AgentWorkspaceSnapshotCaptureStatus {
  String get wireValue => switch (this) {
    AgentWorkspaceSnapshotCaptureStatus.captured => 'captured',
    AgentWorkspaceSnapshotCaptureStatus.partial => 'partial',
    AgentWorkspaceSnapshotCaptureStatus.empty => 'empty',
  };
}

enum AgentWorkspaceRevertPlanStatus { ready, partial, blocked, empty }

extension AgentWorkspaceRevertPlanStatusX on AgentWorkspaceRevertPlanStatus {
  String get wireValue => switch (this) {
    AgentWorkspaceRevertPlanStatus.ready => 'ready',
    AgentWorkspaceRevertPlanStatus.partial => 'partial',
    AgentWorkspaceRevertPlanStatus.blocked => 'blocked',
    AgentWorkspaceRevertPlanStatus.empty => 'empty',
  };
}

class AgentWorkspaceSnapshotDocument {
  const AgentWorkspaceSnapshotDocument({
    required this.documentId,
    required this.existed,
    required this.text,
    required this.revision,
    this.filePath,
  });

  final String documentId;
  final bool existed;
  final String text;
  final int revision;
  final String? filePath;

  factory AgentWorkspaceSnapshotDocument.fromPersistedJson(
    Map<String, Object?> json,
  ) {
    return AgentWorkspaceSnapshotDocument(
      documentId: json['documentId'] as String? ?? '',
      existed: json['existed'] as bool? ?? false,
      text: json['text'] as String? ?? '',
      revision: json['revision'] as int? ?? 0,
      filePath: json['filePath'] as String?,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'existed': existed,
      'revision': revision,
      'textLength': text.length,
      if (filePath != null) 'filePath': filePath,
    };
  }

  Map<String, Object?> toPersistedJson() {
    return <String, Object?>{
      'documentId': documentId,
      'existed': existed,
      'revision': revision,
      'text': text,
      if (filePath != null) 'filePath': filePath,
    };
  }
}

class AgentWorkspaceSnapshotUnavailableDocument {
  const AgentWorkspaceSnapshotUnavailableDocument({
    required this.documentId,
    required this.reason,
  });

  final String documentId;
  final String reason;

  factory AgentWorkspaceSnapshotUnavailableDocument.fromJson(
    Map<String, Object?> json,
  ) {
    return AgentWorkspaceSnapshotUnavailableDocument(
      documentId: json['documentId'] as String? ?? '',
      reason: json['reason'] as String? ?? '',
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{'documentId': documentId, 'reason': reason};
  }
}

class AgentWorkspaceChangeSnapshot {
  const AgentWorkspaceChangeSnapshot({
    required this.snapshotId,
    required this.patchId,
    required this.activeDocumentId,
    required this.capturedAt,
    required this.documents,
    this.unavailableDocuments =
        const <AgentWorkspaceSnapshotUnavailableDocument>[],
    this.todoItems = const <String>[],
  });

  final String snapshotId;
  final String patchId;
  final String activeDocumentId;
  final DateTime capturedAt;
  final List<AgentWorkspaceSnapshotDocument> documents;
  final List<AgentWorkspaceSnapshotUnavailableDocument> unavailableDocuments;
  final List<String> todoItems;

  factory AgentWorkspaceChangeSnapshot.fromPersistedJson(
    Map<String, Object?> json,
  ) {
    return AgentWorkspaceChangeSnapshot(
      snapshotId: json['snapshotId'] as String? ?? '',
      patchId: json['patchId'] as String? ?? '',
      activeDocumentId: json['activeDocumentId'] as String? ?? '',
      capturedAt:
          DateTime.tryParse(json['capturedAt'] as String? ?? '')?.toUtc() ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      documents: _snapshotDocumentsFromJson(json['documents']),
      unavailableDocuments: _unavailableSnapshotDocumentsFromJson(
        json['unavailableDocuments'],
      ),
      todoItems: _jsonStringList(json['todoItems']),
    );
  }

  List<String> get documentIds {
    return documents
        .map((document) => document.documentId)
        .toList(growable: false);
  }

  List<String> get unavailableDocumentIds {
    return unavailableDocuments
        .map((document) => document.documentId)
        .toList(growable: false);
  }

  bool get complete => unavailableDocuments.isEmpty;

  AgentWorkspaceSnapshotDocument? documentFor(String documentId) {
    for (final document in documents) {
      if (document.documentId == documentId) {
        return document;
      }
    }
    return null;
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'snapshotId': snapshotId,
      'patchId': patchId,
      'activeDocumentId': activeDocumentId,
      'capturedAt': capturedAt.toIso8601String(),
      'complete': complete,
      'documentCount': documents.length,
      'documentIds': documentIds,
      'unavailableDocumentIds': unavailableDocumentIds,
      'documents': documents
          .map((document) => document.toJson())
          .toList(growable: false),
      'unavailableDocuments': unavailableDocuments
          .map((document) => document.toJson())
          .toList(growable: false),
      'todoItems': todoItems,
    };
  }

  Map<String, Object?> toPersistedJson() {
    return <String, Object?>{
      'snapshotId': snapshotId,
      'patchId': patchId,
      'activeDocumentId': activeDocumentId,
      'capturedAt': capturedAt.toIso8601String(),
      'documents': documents
          .map((document) => document.toPersistedJson())
          .toList(growable: false),
      'unavailableDocuments': unavailableDocuments
          .map((document) => document.toJson())
          .toList(growable: false),
      'todoItems': todoItems,
    };
  }
}

List<AgentWorkspaceSnapshotDocument> _snapshotDocumentsFromJson(Object? value) {
  if (value is! List) {
    return const <AgentWorkspaceSnapshotDocument>[];
  }
  return value
      .whereType<Map>()
      .map(
        (item) => AgentWorkspaceSnapshotDocument.fromPersistedJson(
          item.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          ),
        ),
      )
      .where((document) => document.documentId.trim().isNotEmpty)
      .toList(growable: false);
}

List<AgentWorkspaceSnapshotUnavailableDocument>
_unavailableSnapshotDocumentsFromJson(Object? value) {
  if (value is! List) {
    return const <AgentWorkspaceSnapshotUnavailableDocument>[];
  }
  return value
      .whereType<Map>()
      .map(
        (item) => AgentWorkspaceSnapshotUnavailableDocument.fromJson(
          item.map<String, Object?>(
            (key, value) => MapEntry(key.toString(), value),
          ),
        ),
      )
      .where((document) => document.documentId.trim().isNotEmpty)
      .toList(growable: false);
}

List<String> _jsonStringList(Object? value) {
  if (value is! List) {
    return const <String>[];
  }
  return value.whereType<String>().toList(growable: false);
}

class AgentWorkspaceSnapshotCaptureResult {
  const AgentWorkspaceSnapshotCaptureResult({
    required this.status,
    required this.message,
    this.restored = false,
    this.snapshot,
  });

  final AgentWorkspaceSnapshotCaptureStatus status;
  final String message;
  final bool restored;
  final AgentWorkspaceChangeSnapshot? snapshot;

  bool get captured =>
      status == AgentWorkspaceSnapshotCaptureStatus.captured ||
      status == AgentWorkspaceSnapshotCaptureStatus.partial;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'captured': captured,
      'message': message,
      'restored': restored,
      if (snapshot != null) 'snapshot': snapshot!.toJson(),
    };
  }
}

class AgentWorkspaceSnapshotDiffSummary {
  const AgentWorkspaceSnapshotDiffSummary({
    this.addedDocumentIds = const <String>[],
    this.deletedDocumentIds = const <String>[],
    this.modifiedDocumentIds = const <String>[],
    this.unchangedDocumentIds = const <String>[],
    this.unavailableDocumentIds = const <String>[],
  });

  final List<String> addedDocumentIds;
  final List<String> deletedDocumentIds;
  final List<String> modifiedDocumentIds;
  final List<String> unchangedDocumentIds;
  final List<String> unavailableDocumentIds;

  int get changedDocumentCount =>
      addedDocumentIds.length +
      deletedDocumentIds.length +
      modifiedDocumentIds.length;

  bool get hasChanges => changedDocumentCount > 0;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'changedDocumentCount': changedDocumentCount,
      'hasChanges': hasChanges,
      'addedDocumentIds': addedDocumentIds,
      'deletedDocumentIds': deletedDocumentIds,
      'modifiedDocumentIds': modifiedDocumentIds,
      'unchangedDocumentIds': unchangedDocumentIds,
      'unavailableDocumentIds': unavailableDocumentIds,
    };
  }
}

class AgentWorkspaceRevertPlan {
  const AgentWorkspaceRevertPlan({
    required this.status,
    required this.message,
    required this.snapshotId,
    required this.patch,
    required this.diffSummary,
    this.todoItems = const <String>[],
  });

  final AgentWorkspaceRevertPlanStatus status;
  final String message;
  final String snapshotId;
  final AgentCodePatch patch;
  final AgentWorkspaceSnapshotDiffSummary diffSummary;
  final List<String> todoItems;

  bool get ready =>
      status == AgentWorkspaceRevertPlanStatus.ready ||
      status == AgentWorkspaceRevertPlanStatus.partial;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'status': status.wireValue,
      'ready': ready,
      'message': message,
      'snapshotId': snapshotId,
      'patch': patch.toJson(),
      'diffSummary': diffSummary.toJson(),
      'todoItems': todoItems,
    };
  }
}

class AgentWorkspaceSnapshotService {
  const AgentWorkspaceSnapshotService({
    required this.editorController,
    this.workspaceDocumentStore,
  });

  final EditorSessionController editorController;
  final WorkspaceDocumentStore? workspaceDocumentStore;

  Future<AgentWorkspaceSnapshotCaptureResult> captureBeforePatch(
    AgentCodePatch patch, {
    DateTime? capturedAt,
    String? snapshotId,
  }) async {
    final documentIds = _documentIdsForPatch(patch);
    if (documentIds.isEmpty) {
      return AgentWorkspaceSnapshotCaptureResult(
        status: AgentWorkspaceSnapshotCaptureStatus.empty,
        message: 'Agent patch ${patch.patchId} has no documents to snapshot.',
      );
    }

    final documents = <AgentWorkspaceSnapshotDocument>[];
    final unavailable = <AgentWorkspaceSnapshotUnavailableDocument>[];
    for (final documentId in documentIds) {
      final capture = await _captureDocument(documentId);
      if (capture.document != null) {
        documents.add(capture.document!);
      } else {
        unavailable.add(
          AgentWorkspaceSnapshotUnavailableDocument(
            documentId: documentId,
            reason: capture.unavailableReason,
          ),
        );
      }
    }

    final effectiveCapturedAt = (capturedAt ?? DateTime.now()).toUtc();
    final snapshot = AgentWorkspaceChangeSnapshot(
      snapshotId:
          snapshotId ??
          'agent-snapshot-${patch.patchId}-${effectiveCapturedAt.microsecondsSinceEpoch}',
      patchId: patch.patchId,
      activeDocumentId: editorController.document.documentId,
      capturedAt: effectiveCapturedAt,
      documents: List<AgentWorkspaceSnapshotDocument>.unmodifiable(documents),
      unavailableDocuments:
          List<AgentWorkspaceSnapshotUnavailableDocument>.unmodifiable(
            unavailable,
          ),
    );

    final status = unavailable.isEmpty
        ? AgentWorkspaceSnapshotCaptureStatus.captured
        : AgentWorkspaceSnapshotCaptureStatus.partial;
    return AgentWorkspaceSnapshotCaptureResult(
      status: status,
      message: unavailable.isEmpty
          ? 'Captured ${documents.length} workspace document snapshot(s) for ${patch.patchId}.'
          : 'Captured ${documents.length} workspace document snapshot(s) for ${patch.patchId}; ${unavailable.length} document(s) were unavailable.',
      snapshot: snapshot,
    );
  }

  Future<AgentWorkspaceRevertPlan> buildRevertPlan(
    AgentWorkspaceChangeSnapshot snapshot,
  ) async {
    final edits = <AgentCodePatchEdit>[];
    final added = <String>[];
    final deleted = <String>[];
    final modified = <String>[];
    final unchanged = <String>[];
    final unavailable = <String>[...snapshot.unavailableDocumentIds];

    for (final before in snapshot.documents) {
      final current = await _loadCurrentDocument(before.documentId);
      if (current.unavailableReason.isNotEmpty) {
        unavailable.add(before.documentId);
        continue;
      }

      final currentDocument = current.document;
      if (before.existed) {
        if (currentDocument == null) {
          deleted.add(before.documentId);
          edits.add(
            AgentCodePatchEdit(
              documentId: before.documentId,
              operation: AgentCodePatchEditOperation.create,
              start: 0,
              end: 0,
              replacementText: before.text,
              baseRevision: before.revision,
            ),
          );
        } else if (currentDocument.text == before.text) {
          unchanged.add(before.documentId);
        } else {
          modified.add(before.documentId);
          edits.add(
            AgentCodePatchEdit(
              documentId: before.documentId,
              start: 0,
              end: currentDocument.text.length,
              replacementText: before.text,
              baseRevision: currentDocument.revision,
            ),
          );
        }
      } else {
        if (currentDocument == null) {
          unchanged.add(before.documentId);
        } else {
          added.add(before.documentId);
          edits.add(
            AgentCodePatchEdit(
              documentId: before.documentId,
              operation: AgentCodePatchEditOperation.delete,
              start: 0,
              end: currentDocument.text.length,
              replacementText: '',
              baseRevision: currentDocument.revision,
            ),
          );
        }
      }
    }

    final diffSummary = AgentWorkspaceSnapshotDiffSummary(
      addedDocumentIds: List<String>.unmodifiable(added),
      deletedDocumentIds: List<String>.unmodifiable(deleted),
      modifiedDocumentIds: List<String>.unmodifiable(modified),
      unchangedDocumentIds: List<String>.unmodifiable(unchanged),
      unavailableDocumentIds: List<String>.unmodifiable(unavailable),
    );
    final status = _revertPlanStatus(edits, unavailable);
    return AgentWorkspaceRevertPlan(
      status: status,
      message: _revertPlanMessage(snapshot, edits, unavailable),
      snapshotId: snapshot.snapshotId,
      patch: AgentCodePatch(
        patchId: 'revert-${snapshot.snapshotId}',
        summary: 'Revert workspace changes captured by ${snapshot.snapshotId}.',
        edits: List<AgentCodePatchEdit>.unmodifiable(edits),
      ),
      diffSummary: diffSummary,
    );
  }

  Future<_CapturedDocument> _captureDocument(String documentId) async {
    if (documentId == editorController.document.documentId) {
      final document = editorController.document;
      return _CapturedDocument(
        document: AgentWorkspaceSnapshotDocument(
          documentId: document.documentId,
          existed: true,
          text: document.text,
          revision: document.revision,
          filePath: workspaceDocumentStore?.filePathForDocumentId(documentId),
        ),
      );
    }

    final store = workspaceDocumentStore;
    if (store == null) {
      return const _CapturedDocument(
        unavailableReason:
            'No workspace document store is available for inactive documents.',
      );
    }

    try {
      final exists = await store.documentExists(documentId);
      if (!exists) {
        return _CapturedDocument(
          document: AgentWorkspaceSnapshotDocument(
            documentId: documentId,
            existed: false,
            text: '',
            revision: 0,
            filePath: store.filePathForDocumentId(documentId),
          ),
        );
      }
      final document = await store.loadDocument(documentId);
      return _CapturedDocument(
        document: AgentWorkspaceSnapshotDocument(
          documentId: document.documentId,
          existed: true,
          text: document.text,
          revision: document.revision,
          filePath: store.filePathForDocumentId(documentId),
        ),
      );
    } on Object catch (error) {
      return _CapturedDocument(
        unavailableReason: 'Failed to capture document: $error',
      );
    }
  }

  Future<_CurrentDocument> _loadCurrentDocument(String documentId) async {
    if (documentId == editorController.document.documentId) {
      return _CurrentDocument(document: editorController.document);
    }

    final store = workspaceDocumentStore;
    if (store == null) {
      return const _CurrentDocument(
        unavailableReason:
            'No workspace document store is available for inactive documents.',
      );
    }

    try {
      final exists = await store.documentExists(documentId);
      if (!exists) {
        return const _CurrentDocument();
      }
      return _CurrentDocument(document: await store.loadDocument(documentId));
    } on Object catch (error) {
      return _CurrentDocument(
        unavailableReason: 'Failed to load current document: $error',
      );
    }
  }
}

class _CapturedDocument {
  const _CapturedDocument({this.document, this.unavailableReason = ''});

  final AgentWorkspaceSnapshotDocument? document;
  final String unavailableReason;
}

class _CurrentDocument {
  const _CurrentDocument({this.document, this.unavailableReason = ''});

  final DocumentState? document;
  final String unavailableReason;
}

List<String> _documentIdsForPatch(AgentCodePatch patch) {
  return <String>{
    for (final edit in patch.edits)
      if (edit.documentId.trim().isNotEmpty) edit.documentId,
  }.toList(growable: false);
}

AgentWorkspaceRevertPlanStatus _revertPlanStatus(
  List<AgentCodePatchEdit> edits,
  List<String> unavailable,
) {
  if (edits.isEmpty && unavailable.isEmpty) {
    return AgentWorkspaceRevertPlanStatus.empty;
  }
  if (edits.isEmpty && unavailable.isNotEmpty) {
    return AgentWorkspaceRevertPlanStatus.blocked;
  }
  if (unavailable.isNotEmpty) {
    return AgentWorkspaceRevertPlanStatus.partial;
  }
  return AgentWorkspaceRevertPlanStatus.ready;
}

String _revertPlanMessage(
  AgentWorkspaceChangeSnapshot snapshot,
  List<AgentCodePatchEdit> edits,
  List<String> unavailable,
) {
  if (edits.isEmpty && unavailable.isEmpty) {
    return 'No workspace changes need revert for ${snapshot.snapshotId}.';
  }
  if (unavailable.isEmpty) {
    return 'Prepared ${edits.length} revert edit(s) for ${snapshot.snapshotId}.';
  }
  return 'Prepared ${edits.length} revert edit(s) for ${snapshot.snapshotId}; ${unavailable.length} document(s) are unavailable.';
}
