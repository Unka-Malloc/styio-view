import '../editor/document_state.dart';
import '../language/language_contract.dart';
import 'workspace_document_store_types.dart';
import 'workspace_file_operations.dart';

enum WorkspaceEditSource { agent, codeAction, rename, formatting, manual }

extension WorkspaceEditSourceWire on WorkspaceEditSource {
  String get wireValue {
    return switch (this) {
      WorkspaceEditSource.agent => 'agent',
      WorkspaceEditSource.codeAction => 'code-action',
      WorkspaceEditSource.rename => 'rename',
      WorkspaceEditSource.formatting => 'formatting',
      WorkspaceEditSource.manual => 'manual',
    };
  }
}

class WorkspaceFileOperation {
  const WorkspaceFileOperation({
    required this.kind,
    required this.documentId,
    this.text = '',
    this.overwrite = false,
  });

  const WorkspaceFileOperation.create({
    required String documentId,
    required String text,
    bool overwrite = false,
  }) : this(
         kind: WorkspaceFileOperationKind.create,
         documentId: documentId,
         text: text,
         overwrite: overwrite,
       );

  const WorkspaceFileOperation.delete({required String documentId})
    : this(kind: WorkspaceFileOperationKind.delete, documentId: documentId);

  final WorkspaceFileOperationKind kind;
  final String documentId;
  final String text;
  final bool overwrite;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'kind': kind.wireValue,
      'documentId': documentId,
      if (kind == WorkspaceFileOperationKind.create) 'textLength': text.length,
      if (overwrite) 'overwrite': overwrite,
    };
  }
}

class WorkspaceEditPlan {
  const WorkspaceEditPlan({
    required this.id,
    required this.summary,
    required this.source,
    required this.editsByDocument,
    this.fileOperations = const <WorkspaceFileOperation>[],
  });

  factory WorkspaceEditPlan.singleDocument({
    required String id,
    required String summary,
    required WorkspaceEditSource source,
    required String documentId,
    required List<FormattingEdit> edits,
  }) {
    return WorkspaceEditPlan(
      id: id,
      summary: summary,
      source: source,
      editsByDocument: <String, List<FormattingEdit>>{
        documentId: List<FormattingEdit>.unmodifiable(edits),
      },
    );
  }

  factory WorkspaceEditPlan.fromQuickFix({
    required String id,
    required String documentId,
    required DiagnosticQuickFix quickFix,
  }) {
    return WorkspaceEditPlan.singleDocument(
      id: id,
      summary: quickFix.label,
      source: WorkspaceEditSource.codeAction,
      documentId: documentId,
      edits: quickFix.edits,
    );
  }

  factory WorkspaceEditPlan.fromRenamePlan({
    required String id,
    required String documentId,
    required RenamePlan renamePlan,
  }) {
    return WorkspaceEditPlan.singleDocument(
      id: id,
      summary: 'Rename ${renamePlan.target.name} to ${renamePlan.newName}.',
      source: WorkspaceEditSource.rename,
      documentId: documentId,
      edits: renamePlan.edits,
    );
  }

  final String id;
  final String summary;
  final WorkspaceEditSource source;
  final Map<String, List<FormattingEdit>> editsByDocument;
  final List<WorkspaceFileOperation> fileOperations;

  int get editCount {
    return editsByDocument.values.fold<int>(
      0,
      (total, edits) => total + edits.length,
    );
  }

  int get changeCount => editCount + fileOperations.length;

  List<String> get documentIds {
    final ids = <String>{
      ...editsByDocument.keys,
      for (final operation in fileOperations) operation.documentId,
    }.toList(growable: false);
    ids.sort();
    return ids;
  }

  WorkspaceEditPreview preview(List<DocumentState> documents) {
    final documentsById = {
      for (final document in documents) document.documentId: document,
    };
    final previews = <WorkspaceEditDocumentPreview>[];
    final fileOperationPreviews = <WorkspaceFileOperationPreview>[];
    final missingDocumentIds = <String>[];
    for (final operation in fileOperations) {
      final documentIdFailure = _validateDocumentId(operation.documentId);
      if (documentIdFailure != null) {
        fileOperationPreviews.add(
          WorkspaceFileOperationPreview(
            operation: operation,
            status: WorkspaceFileOperationPreviewStatus.blockedUnsafeDocumentId,
            message: documentIdFailure,
          ),
        );
        continue;
      }
      final existing = documentsById[operation.documentId];
      if (operation.kind == WorkspaceFileOperationKind.create) {
        fileOperationPreviews.add(
          WorkspaceFileOperationPreview(
            operation: operation,
            status: existing != null && !operation.overwrite
                ? WorkspaceFileOperationPreviewStatus.blockedAlreadyExists
                : WorkspaceFileOperationPreviewStatus.ready,
            beforeText: existing?.text,
            afterText: operation.text,
            message: existing != null && !operation.overwrite
                ? 'Document ${operation.documentId} already exists.'
                : 'Document ${operation.documentId} will be created.',
          ),
        );
      } else {
        fileOperationPreviews.add(
          WorkspaceFileOperationPreview(
            operation: operation,
            status: existing == null
                ? WorkspaceFileOperationPreviewStatus.blockedMissingDocument
                : WorkspaceFileOperationPreviewStatus.ready,
            beforeText: existing?.text,
            afterText: '',
            message: existing == null
                ? 'Document ${operation.documentId} is missing.'
                : 'Document ${operation.documentId} will be deleted.',
          ),
        );
      }
    }
    for (final entry in editsByDocument.entries) {
      final document = documentsById[entry.key];
      if (document == null) {
        missingDocumentIds.add(entry.key);
        continue;
      }
      final normalizedEdits = normalizeFormattingEditsForDocument(
        documentLength: document.length,
        edits: entry.value,
      );
      if (normalizedEdits.isEmpty) {
        continue;
      }
      final nextDocument = _applyEditsToDocument(document, normalizedEdits);
      previews.add(
        WorkspaceEditDocumentPreview(
          documentId: document.documentId,
          revision: document.revision,
          beforeText: document.text,
          afterText: nextDocument.text,
          edits: normalizedEdits,
        ),
      );
    }
    return WorkspaceEditPreview(
      planId: id,
      summary: summary,
      source: source,
      documents: List<WorkspaceEditDocumentPreview>.unmodifiable(previews),
      fileOperations: List<WorkspaceFileOperationPreview>.unmodifiable(
        fileOperationPreviews,
      ),
      missingDocumentIds: List<String>.unmodifiable(missingDocumentIds),
    );
  }
}

class WorkspaceEditPreview {
  const WorkspaceEditPreview({
    required this.planId,
    required this.summary,
    required this.source,
    required this.documents,
    this.fileOperations = const <WorkspaceFileOperationPreview>[],
    this.missingDocumentIds = const <String>[],
  });

  final String planId;
  final String summary;
  final WorkspaceEditSource source;
  final List<WorkspaceEditDocumentPreview> documents;
  final List<WorkspaceFileOperationPreview> fileOperations;
  final List<String> missingDocumentIds;

  bool get hasChanges =>
      documents.any((document) => document.changed) ||
      fileOperations.any((operation) => operation.changed);

  bool get hasMissingDocuments => missingDocumentIds.isNotEmpty;

  bool get hasBlockedFileOperations {
    return fileOperations.any((operation) => operation.blocked);
  }

  bool get canApply =>
      hasChanges && !hasMissingDocuments && !hasBlockedFileOperations;

  int get editCount {
    return documents.fold<int>(
      0,
      (total, document) => total + document.edits.length,
    );
  }

  int get changeCount => editCount + fileOperations.length;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'planId': planId,
      'summary': summary,
      'source': source.wireValue,
      'documentCount': documents.length,
      'missingDocumentCount': missingDocumentIds.length,
      if (missingDocumentIds.isNotEmpty)
        'missingDocumentIds': missingDocumentIds,
      'editCount': editCount,
      'fileOperationCount': fileOperations.length,
      'changeCount': changeCount,
      'hasChanges': hasChanges,
      'hasMissingDocuments': hasMissingDocuments,
      'hasBlockedFileOperations': hasBlockedFileOperations,
      'canApply': canApply,
      'documents': documents
          .map((document) => document.toJson())
          .toList(growable: false),
      'fileOperations': fileOperations
          .map((operation) => operation.toJson())
          .toList(growable: false),
    };
  }
}

enum WorkspaceEditConfirmationStatus {
  ready,
  blockedNoChanges,
  blockedMissingDocuments,
  blockedTooManyEdits,
  blockedFileOperations,
}

extension WorkspaceEditConfirmationStatusX on WorkspaceEditConfirmationStatus {
  String get wireValue => switch (this) {
    WorkspaceEditConfirmationStatus.ready => 'ready',
    WorkspaceEditConfirmationStatus.blockedNoChanges => 'blocked-no-changes',
    WorkspaceEditConfirmationStatus.blockedMissingDocuments =>
      'blocked-missing-documents',
    WorkspaceEditConfirmationStatus.blockedTooManyEdits =>
      'blocked-too-many-edits',
    WorkspaceEditConfirmationStatus.blockedFileOperations =>
      'blocked-file-operations',
  };
}

class WorkspaceEditConfirmationPlan {
  const WorkspaceEditConfirmationPlan({
    required this.planId,
    required this.status,
    required this.message,
    this.summary = '',
    this.source = WorkspaceEditSource.manual,
    this.documentIds = const <String>[],
    this.missingDocumentIds = const <String>[],
    this.editCount = 0,
    this.fileOperationCount = 0,
    this.requiresUserConfirmation = true,
    this.todo = '',
  });

  factory WorkspaceEditConfirmationPlan.fromPreview(
    WorkspaceEditPreview preview, {
    int maxEditCount = 500,
  }) {
    final documentIds = <String>{
      ...preview.documents.map((document) => document.documentId),
      ...preview.fileOperations.map(
        (operation) => operation.operation.documentId,
      ),
    }.toList(growable: false)..sort();
    final missingDocumentIds =
        preview.missingDocumentIds
            .map((documentId) => documentId.trim())
            .where((documentId) => documentId.isNotEmpty)
            .toSet()
            .toList(growable: false)
          ..sort();
    if (preview.hasBlockedFileOperations) {
      return WorkspaceEditConfirmationPlan(
        planId: preview.planId,
        status: WorkspaceEditConfirmationStatus.blockedFileOperations,
        summary: preview.summary,
        source: preview.source,
        documentIds: documentIds,
        missingDocumentIds: missingDocumentIds,
        editCount: preview.editCount,
        fileOperationCount: preview.fileOperations.length,
        message:
            'Workspace edit preview contains blocked file create/delete operation(s).',
      );
    }
    if (!preview.hasChanges) {
      return WorkspaceEditConfirmationPlan(
        planId: preview.planId,
        status: WorkspaceEditConfirmationStatus.blockedNoChanges,
        summary: preview.summary,
        source: preview.source,
        documentIds: documentIds,
        missingDocumentIds: missingDocumentIds,
        editCount: preview.editCount,
        fileOperationCount: preview.fileOperations.length,
        requiresUserConfirmation: false,
        message: 'Workspace edit preview has no text changes.',
      );
    }
    if (missingDocumentIds.isNotEmpty) {
      return WorkspaceEditConfirmationPlan(
        planId: preview.planId,
        status: WorkspaceEditConfirmationStatus.blockedMissingDocuments,
        summary: preview.summary,
        source: preview.source,
        documentIds: documentIds,
        missingDocumentIds: missingDocumentIds,
        editCount: preview.editCount,
        fileOperationCount: preview.fileOperations.length,
        message:
            'Workspace edit preview is blocked until missing documents are loaded.',
      );
    }
    if (preview.editCount > maxEditCount) {
      return WorkspaceEditConfirmationPlan(
        planId: preview.planId,
        status: WorkspaceEditConfirmationStatus.blockedTooManyEdits,
        summary: preview.summary,
        source: preview.source,
        documentIds: documentIds,
        editCount: preview.editCount,
        fileOperationCount: preview.fileOperations.length,
        message:
            'Workspace edit preview contains too many edits: ${preview.editCount} exceeds $maxEditCount.',
      );
    }
    return WorkspaceEditConfirmationPlan(
      planId: preview.planId,
      status: WorkspaceEditConfirmationStatus.ready,
      summary: preview.summary,
      source: preview.source,
      documentIds: documentIds,
      editCount: preview.editCount,
      fileOperationCount: preview.fileOperations.length,
      message: 'Workspace edit preview is ready for confirmation.',
      todo:
          'TODO: bind this confirmation plan to the diff UI, file operation preview, and apply/cancel controls.',
    );
  }

  final String planId;
  final WorkspaceEditConfirmationStatus status;
  final String message;
  final String summary;
  final WorkspaceEditSource source;
  final List<String> documentIds;
  final List<String> missingDocumentIds;
  final int editCount;
  final int fileOperationCount;
  final bool requiresUserConfirmation;
  final String todo;

  bool get ready => status == WorkspaceEditConfirmationStatus.ready;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'planId': planId,
      'status': status.wireValue,
      'ready': ready,
      'summary': summary,
      'source': source.wireValue,
      'documentIds': documentIds,
      'missingDocumentIds': missingDocumentIds,
      'editCount': editCount,
      'fileOperationCount': fileOperationCount,
      'changeCount': editCount + fileOperationCount,
      'requiresUserConfirmation': requiresUserConfirmation,
      'message': message,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

enum WorkspaceFileOperationPreviewStatus {
  ready,
  blockedAlreadyExists,
  blockedMissingDocument,
  blockedUnsafeDocumentId,
}

extension WorkspaceFileOperationPreviewStatusX
    on WorkspaceFileOperationPreviewStatus {
  String get wireValue => switch (this) {
    WorkspaceFileOperationPreviewStatus.ready => 'ready',
    WorkspaceFileOperationPreviewStatus.blockedAlreadyExists =>
      'blocked-already-exists',
    WorkspaceFileOperationPreviewStatus.blockedMissingDocument =>
      'blocked-missing-document',
    WorkspaceFileOperationPreviewStatus.blockedUnsafeDocumentId =>
      'blocked-unsafe-document-id',
  };
}

class WorkspaceFileOperationPreview {
  const WorkspaceFileOperationPreview({
    required this.operation,
    required this.status,
    required this.message,
    this.beforeText,
    this.afterText,
  });

  final WorkspaceFileOperation operation;
  final WorkspaceFileOperationPreviewStatus status;
  final String message;
  final String? beforeText;
  final String? afterText;

  bool get blocked => status != WorkspaceFileOperationPreviewStatus.ready;
  bool get changed => !blocked && beforeText != afterText;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'operation': operation.toJson(),
      'status': status.wireValue,
      'blocked': blocked,
      'changed': changed,
      'message': message,
      if (beforeText != null) 'beforeTextSample': _sampleText(beforeText!),
      if (afterText != null) 'afterTextSample': _sampleText(afterText!),
    };
  }
}

class WorkspaceEditDocumentPreview {
  const WorkspaceEditDocumentPreview({
    required this.documentId,
    required this.revision,
    required this.beforeText,
    required this.afterText,
    required this.edits,
  });

  final String documentId;
  final int revision;
  final String beforeText;
  final String afterText;
  final List<FormattingEdit> edits;

  bool get changed => beforeText != afterText;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'documentId': documentId,
      'revision': revision,
      'changed': changed,
      'editCount': edits.length,
      'edits': edits
          .map((edit) => _workspaceEditPreviewEditToJson(edit, beforeText))
          .toList(growable: false),
      'beforeTextSample': _sampleText(beforeText),
      'afterTextSample': _sampleText(afterText),
    };
  }
}

Map<String, Object?> _workspaceEditPreviewEditToJson(
  FormattingEdit edit,
  String documentText,
) {
  return <String, Object?>{
    'start': edit.range.start,
    'end': edit.range.end,
    'range': _workspaceEditPreviewRangeToJson(edit.range, documentText),
    'newText': edit.newText,
  };
}

Map<String, Object?> _workspaceEditPreviewRangeToJson(
  SourceRange range,
  String documentText,
) {
  final start = _workspaceEditPreviewPositionForOffset(
    documentText,
    range.start,
  );
  final end = _workspaceEditPreviewPositionForOffset(documentText, range.end);
  return <String, Object?>{
    'start': range.start,
    'end': range.end,
    'startLine': start.line,
    'startColumn': start.column,
    'endLine': end.line,
    'endColumn': end.column,
  };
}

_WorkspaceEditPreviewPosition _workspaceEditPreviewPositionForOffset(
  String text,
  int offset,
) {
  final clampedOffset = offset.clamp(0, text.length);
  var line = 0;
  var column = 0;
  for (var index = 0; index < clampedOffset; index += 1) {
    if (text.codeUnitAt(index) == 10) {
      line += 1;
      column = 0;
    } else {
      column += 1;
    }
  }
  return _WorkspaceEditPreviewPosition(line: line, column: column);
}

class _WorkspaceEditPreviewPosition {
  const _WorkspaceEditPreviewPosition({
    required this.line,
    required this.column,
  });

  final int line;
  final int column;
}

class WorkspaceEditApplicationResult {
  const WorkspaceEditApplicationResult({
    required this.applied,
    required this.message,
    this.appliedEditCount = 0,
    this.appliedDocumentIds = const <String>[],
    this.createdDocumentIds = const <String>[],
    this.deletedDocumentIds = const <String>[],
    this.skippedNoOpDocumentIds = const <String>[],
  });

  final bool applied;
  final String message;
  final int appliedEditCount;
  final List<String> appliedDocumentIds;
  final List<String> createdDocumentIds;
  final List<String> deletedDocumentIds;
  final List<String> skippedNoOpDocumentIds;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'applied': applied,
      'message': message,
      'appliedEditCount': appliedEditCount,
      'appliedDocumentIds': appliedDocumentIds,
      'createdDocumentIds': createdDocumentIds,
      'deletedDocumentIds': deletedDocumentIds,
      'skippedNoOpDocumentIds': skippedNoOpDocumentIds,
    };
  }
}

class WorkspaceEditApplier {
  const WorkspaceEditApplier({
    required this.workspaceDocumentStore,
    this.maxEditCount = 500,
  });

  final WorkspaceDocumentStore workspaceDocumentStore;
  final int maxEditCount;

  Future<WorkspaceEditApplicationResult> apply(WorkspaceEditPlan plan) async {
    if (plan.id.trim().isEmpty) {
      return const WorkspaceEditApplicationResult(
        applied: false,
        message: 'Workspace edit plan is missing an id.',
      );
    }
    if (plan.changeCount == 0) {
      return WorkspaceEditApplicationResult(
        applied: false,
        message: 'Workspace edit plan ${plan.id} has no changes.',
      );
    }
    if (plan.editCount > maxEditCount) {
      return WorkspaceEditApplicationResult(
        applied: false,
        message:
            'Workspace edit plan ${plan.id} contains too many edits: ${plan.editCount} exceeds $maxEditCount.',
      );
    }

    for (final operation in plan.fileOperations) {
      final documentIdFailure = _validateDocumentId(operation.documentId);
      if (documentIdFailure != null) {
        return WorkspaceEditApplicationResult(
          applied: false,
          message: 'Workspace edit plan ${plan.id} $documentIdFailure',
        );
      }
      if (operation.kind == WorkspaceFileOperationKind.delete &&
          plan.editsByDocument.containsKey(operation.documentId)) {
        return WorkspaceEditApplicationResult(
          applied: false,
          message:
              'Workspace edit plan ${plan.id} cannot delete and edit ${operation.documentId} in the same application.',
        );
      }
    }

    final createdDocumentIds = <String>[];
    final deletedDocumentIds = <String>[];
    for (final operation in plan.fileOperations) {
      if (operation.kind == WorkspaceFileOperationKind.create) {
        final exists = await workspaceDocumentStore.documentExists(
          operation.documentId,
        );
        if (exists && !operation.overwrite) {
          return WorkspaceEditApplicationResult(
            applied: false,
            message:
                'Workspace edit plan ${plan.id} cannot create ${operation.documentId} because it already exists.',
            createdDocumentIds: List<String>.unmodifiable(createdDocumentIds),
            deletedDocumentIds: List<String>.unmodifiable(deletedDocumentIds),
          );
        }
        await workspaceDocumentStore.saveDocument(
          DocumentState(
            documentId: operation.documentId,
            text: operation.text,
            revision: 0,
          ),
        );
        createdDocumentIds.add(operation.documentId);
      } else {
        final removed = await workspaceDocumentStore.deleteDocument(
          operation.documentId,
        );
        if (!removed) {
          return WorkspaceEditApplicationResult(
            applied: false,
            message:
                'Workspace edit plan ${plan.id} cannot delete missing document ${operation.documentId}.',
            createdDocumentIds: List<String>.unmodifiable(createdDocumentIds),
            deletedDocumentIds: List<String>.unmodifiable(deletedDocumentIds),
          );
        }
        deletedDocumentIds.add(operation.documentId);
      }
    }

    final loadedDocuments = <String, DocumentState>{};
    final normalizedEditsByDocument = <String, List<FormattingEdit>>{};
    for (final entry in plan.editsByDocument.entries) {
      final documentId = entry.key;
      final documentIdFailure = _validateDocumentId(documentId);
      if (documentIdFailure != null) {
        return WorkspaceEditApplicationResult(
          applied: false,
          message: 'Workspace edit plan ${plan.id} $documentIdFailure',
        );
      }
      late final DocumentState document;
      try {
        document = await workspaceDocumentStore.loadDocument(documentId);
      } on Object catch (error) {
        return WorkspaceEditApplicationResult(
          applied: false,
          message:
              'Workspace edit plan ${plan.id} failed to load $documentId: $error',
        );
      }
      final normalizedEdits = normalizeFormattingEditsForDocument(
        documentLength: document.length,
        edits: entry.value,
      );
      if (normalizedEdits.length != entry.value.length) {
        return WorkspaceEditApplicationResult(
          applied: false,
          message:
              'Workspace edit plan ${plan.id} has invalid or overlapping edit(s) for $documentId.',
        );
      }
      loadedDocuments[documentId] = document;
      normalizedEditsByDocument[documentId] = normalizedEdits;
    }

    final appliedDocumentIds = <String>[];
    final skippedNoOpDocumentIds = <String>[];
    var appliedEditCount = 0;
    for (final entry in normalizedEditsByDocument.entries) {
      final document = loadedDocuments[entry.key]!;
      final nextDocument = _applyEditsToDocument(document, entry.value);
      if (nextDocument.text == document.text) {
        skippedNoOpDocumentIds.add(entry.key);
        continue;
      }
      try {
        await workspaceDocumentStore.saveDocument(nextDocument);
      } on Object catch (error) {
        return WorkspaceEditApplicationResult(
          applied: false,
          message:
              'Workspace edit plan ${plan.id} failed to save ${entry.key}: $error',
          appliedEditCount: appliedEditCount,
          appliedDocumentIds: List<String>.unmodifiable(appliedDocumentIds),
          createdDocumentIds: List<String>.unmodifiable(createdDocumentIds),
          deletedDocumentIds: List<String>.unmodifiable(deletedDocumentIds),
          skippedNoOpDocumentIds: List<String>.unmodifiable(
            skippedNoOpDocumentIds,
          ),
        );
      }
      appliedDocumentIds.add(entry.key);
      appliedEditCount += entry.value.length;
    }

    if (appliedEditCount == 0) {
      createdDocumentIds.sort();
      deletedDocumentIds.sort();
      if (createdDocumentIds.isNotEmpty || deletedDocumentIds.isNotEmpty) {
        return WorkspaceEditApplicationResult(
          applied: true,
          message:
              'Applied ${createdDocumentIds.length + deletedDocumentIds.length} file operation(s) from ${plan.source.wireValue} plan ${plan.id}.',
          createdDocumentIds: List<String>.unmodifiable(createdDocumentIds),
          deletedDocumentIds: List<String>.unmodifiable(deletedDocumentIds),
          skippedNoOpDocumentIds: List<String>.unmodifiable(
            skippedNoOpDocumentIds,
          ),
        );
      }
      return WorkspaceEditApplicationResult(
        applied: false,
        message: 'Workspace edit plan ${plan.id} produced no text changes.',
        appliedDocumentIds: const <String>[],
        skippedNoOpDocumentIds: List<String>.unmodifiable(
          skippedNoOpDocumentIds,
        ),
      );
    }

    appliedDocumentIds.sort();
    createdDocumentIds.sort();
    deletedDocumentIds.sort();
    skippedNoOpDocumentIds.sort();
    return WorkspaceEditApplicationResult(
      applied: true,
      appliedEditCount: appliedEditCount,
      appliedDocumentIds: List<String>.unmodifiable(appliedDocumentIds),
      createdDocumentIds: List<String>.unmodifiable(createdDocumentIds),
      deletedDocumentIds: List<String>.unmodifiable(deletedDocumentIds),
      skippedNoOpDocumentIds: List<String>.unmodifiable(skippedNoOpDocumentIds),
      message:
          'Applied $appliedEditCount workspace edit(s) and ${createdDocumentIds.length + deletedDocumentIds.length} file operation(s) from ${plan.source.wireValue} plan ${plan.id}.',
    );
  }
}

DocumentState _applyEditsToDocument(
  DocumentState document,
  List<FormattingEdit> edits,
) {
  var nextText = document.text;
  for (final edit in edits.reversed) {
    nextText = nextText.replaceRange(
      edit.range.start,
      edit.range.end,
      edit.newText,
    );
  }
  return DocumentState(
    documentId: document.documentId,
    text: nextText,
    revision: document.revision + 1,
  );
}

String? _validateDocumentId(String documentId) {
  if (documentId.trim().isEmpty) {
    return 'contains an edit without documentId.';
  }
  if (documentId.contains('..') || documentId.contains('\\')) {
    return 'contains unsafe documentId $documentId.';
  }
  return null;
}

String _sampleText(String text, {int maxLength = 240}) {
  if (text.length <= maxLength) {
    return text;
  }
  return '${text.substring(0, maxLength)}...';
}
