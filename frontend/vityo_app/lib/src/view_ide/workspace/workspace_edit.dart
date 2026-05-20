import '../editor/document_state.dart';
import '../foundation/foundation.dart';
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

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'summary': summary,
      'source': source.wireValue,
      'documentIds': documentIds,
      'editCount': editCount,
      'fileOperationCount': fileOperations.length,
      'changeCount': changeCount,
      'editsByDocument': editsByDocument.map(
        (documentId, edits) => MapEntry<String, Object?>(
          documentId,
          edits.map(_workspaceEditPlanEditToJson).toList(growable: false),
        ),
      ),
      'fileOperations': fileOperations
          .map((operation) => operation.toJson())
          .toList(growable: false),
    };
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

  WorkspaceEditDiffWindow diffWindow({
    int documentOffset = 0,
    int documentLimit = 20,
    int fileOperationOffset = 0,
    int fileOperationLimit = 20,
  }) {
    final normalizedDocumentOffset = documentOffset.clamp(0, documents.length);
    final normalizedDocumentLimit = documentLimit <= 0 ? 20 : documentLimit;
    final normalizedFileOperationOffset = fileOperationOffset.clamp(
      0,
      fileOperations.length,
    );
    final normalizedFileOperationLimit = fileOperationLimit <= 0
        ? 20
        : fileOperationLimit;
    final documentEnd = (normalizedDocumentOffset + normalizedDocumentLimit)
        .clamp(0, documents.length);
    final fileOperationEnd =
        (normalizedFileOperationOffset + normalizedFileOperationLimit).clamp(
          0,
          fileOperations.length,
        );

    return WorkspaceEditDiffWindow(
      planId: planId,
      summary: summary,
      source: source,
      documentOffset: normalizedDocumentOffset,
      documentLimit: normalizedDocumentLimit,
      fileOperationOffset: normalizedFileOperationOffset,
      fileOperationLimit: normalizedFileOperationLimit,
      totalDocumentCount: documents.length,
      totalFileOperationCount: fileOperations.length,
      documents: documents
          .sublist(normalizedDocumentOffset, documentEnd)
          .toList(growable: false),
      fileOperations: fileOperations
          .sublist(normalizedFileOperationOffset, fileOperationEnd)
          .toList(growable: false),
    );
  }

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
      'confirmationPlan': WorkspaceEditConfirmationPlan.fromPreview(
        this,
      ).toJson(),
      'documents': documents
          .map((document) => document.toJson())
          .toList(growable: false),
      'fileOperations': fileOperations
          .map((operation) => operation.toJson())
          .toList(growable: false),
    };
  }
}

class WorkspaceEditDiffWindow {
  const WorkspaceEditDiffWindow({
    required this.planId,
    required this.summary,
    required this.source,
    required this.documentOffset,
    required this.documentLimit,
    required this.fileOperationOffset,
    required this.fileOperationLimit,
    required this.totalDocumentCount,
    required this.totalFileOperationCount,
    required this.documents,
    required this.fileOperations,
  });

  final String planId;
  final String summary;
  final WorkspaceEditSource source;
  final int documentOffset;
  final int documentLimit;
  final int fileOperationOffset;
  final int fileOperationLimit;
  final int totalDocumentCount;
  final int totalFileOperationCount;
  final List<WorkspaceEditDocumentPreview> documents;
  final List<WorkspaceFileOperationPreview> fileOperations;

  bool get hasMoreDocuments =>
      documentOffset + documents.length < totalDocumentCount;

  bool get hasMoreFileOperations =>
      fileOperationOffset + fileOperations.length < totalFileOperationCount;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'planId': planId,
      'summary': summary,
      'source': source.wireValue,
      'documentOffset': documentOffset,
      'documentLimit': documentLimit,
      'fileOperationOffset': fileOperationOffset,
      'fileOperationLimit': fileOperationLimit,
      'totalDocumentCount': totalDocumentCount,
      'totalFileOperationCount': totalFileOperationCount,
      'windowDocumentCount': documents.length,
      'windowFileOperationCount': fileOperations.length,
      'hasMoreDocuments': hasMoreDocuments,
      'hasMoreFileOperations': hasMoreFileOperations,
      'documents': documents
          .map((document) => document.toJson())
          .toList(growable: false),
      'fileOperations': fileOperations
          .map((operation) => operation.toJson())
          .toList(growable: false),
      'todo': 'TODO: connect lazy expansion controls to persisted state.',
    };
  }
}

class WorkspaceEditDiffPaginationState {
  const WorkspaceEditDiffPaginationState({
    required this.workspaceId,
    required this.planId,
    this.source = WorkspaceEditSource.manual,
    this.documentOffset = 0,
    this.documentLimit = 20,
    this.fileOperationOffset = 0,
    this.fileOperationLimit = 20,
    this.updatedAt,
  });

  factory WorkspaceEditDiffPaginationState.fromWindow({
    required String workspaceId,
    required WorkspaceEditDiffWindow window,
    DateTime? updatedAt,
  }) {
    return WorkspaceEditDiffPaginationState(
      workspaceId: workspaceId,
      planId: window.planId,
      source: window.source,
      documentOffset: window.documentOffset,
      documentLimit: window.documentLimit,
      fileOperationOffset: window.fileOperationOffset,
      fileOperationLimit: window.fileOperationLimit,
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  factory WorkspaceEditDiffPaginationState.fromJson(Map<String, Object?> json) {
    return WorkspaceEditDiffPaginationState(
      workspaceId: json['workspaceId'] as String? ?? '',
      planId: json['planId'] as String? ?? '',
      source:
          _workspaceEditSourceFromWire(json['source']) ??
          WorkspaceEditSource.manual,
      documentOffset: json['documentOffset'] as int? ?? 0,
      documentLimit: json['documentLimit'] as int? ?? 20,
      fileOperationOffset: json['fileOperationOffset'] as int? ?? 0,
      fileOperationLimit: json['fileOperationLimit'] as int? ?? 20,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toUtc(),
    );
  }

  final String workspaceId;
  final String planId;
  final WorkspaceEditSource source;
  final int documentOffset;
  final int documentLimit;
  final int fileOperationOffset;
  final int fileOperationLimit;
  final DateTime? updatedAt;

  WorkspaceEditDiffWindow windowFor(WorkspaceEditPreview preview) {
    return preview.diffWindow(
      documentOffset: documentOffset,
      documentLimit: documentLimit,
      fileOperationOffset: fileOperationOffset,
      fileOperationLimit: fileOperationLimit,
    );
  }

  WorkspaceEditDiffPaginationState nextDocumentPage(
    WorkspaceEditPreview preview, {
    DateTime? updatedAt,
  }) {
    return copyWith(
      documentOffset: (documentOffset + documentLimit).clamp(
        0,
        preview.documents.length,
      ),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  WorkspaceEditDiffPaginationState nextFileOperationPage(
    WorkspaceEditPreview preview, {
    DateTime? updatedAt,
  }) {
    return copyWith(
      fileOperationOffset: (fileOperationOffset + fileOperationLimit).clamp(
        0,
        preview.fileOperations.length,
      ),
      updatedAt: updatedAt ?? DateTime.now().toUtc(),
    );
  }

  WorkspaceEditDiffPaginationState copyWith({
    int? documentOffset,
    int? documentLimit,
    int? fileOperationOffset,
    int? fileOperationLimit,
    DateTime? updatedAt,
  }) {
    return WorkspaceEditDiffPaginationState(
      workspaceId: workspaceId,
      planId: planId,
      source: source,
      documentOffset: documentOffset ?? this.documentOffset,
      documentLimit: documentLimit ?? this.documentLimit,
      fileOperationOffset: fileOperationOffset ?? this.fileOperationOffset,
      fileOperationLimit: fileOperationLimit ?? this.fileOperationLimit,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'workspaceId': workspaceId,
      'planId': planId,
      'source': source.wireValue,
      'documentOffset': documentOffset,
      'documentLimit': documentLimit,
      'fileOperationOffset': fileOperationOffset,
      'fileOperationLimit': fileOperationLimit,
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }
}

class WorkspaceEditDiffPaginationStore {
  WorkspaceEditDiffPaginationStore.fromDataStore({
    required FoundationDataStore dataStore,
  }) : this(
         owner: FoundationDataStoreOwner(
           descriptor: const FoundationDataStoreOwnerDescriptor(
             ownerId: 'workspace.edit-application.diff-pagination',
             layer: 'workspace',
             stateFamily: 'workspace-edit-diff-pagination',
             allowedNamespaces: <String>{_namespaceName},
           ),
           dataStore: dataStore,
         ),
       );

  const WorkspaceEditDiffPaginationStore({
    required FoundationDataStoreOwner owner,
  }) : _owner = owner;

  static const int schemaVersion = 1;
  static const String _namespaceName =
      'workspace.edit-application.diff-pagination';

  final FoundationDataStoreOwner _owner;

  Future<WorkspaceEditDiffPaginationState> readState({
    required String workspaceId,
    required String planId,
  }) async {
    final value = await _owner.readJson(
      namespaceName: _namespaceName,
      key: _keyFor(planId),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
    if (value == null) {
      return WorkspaceEditDiffPaginationState(
        workspaceId: workspaceId,
        planId: planId,
      );
    }
    final state = WorkspaceEditDiffPaginationState.fromJson(value);
    return state.workspaceId.isEmpty
        ? WorkspaceEditDiffPaginationState(
            workspaceId: workspaceId,
            planId: state.planId.isEmpty ? planId : state.planId,
            source: state.source,
            documentOffset: state.documentOffset,
            documentLimit: state.documentLimit,
            fileOperationOffset: state.fileOperationOffset,
            fileOperationLimit: state.fileOperationLimit,
            updatedAt: state.updatedAt,
          )
        : state;
  }

  Future<WorkspaceEditDiffPaginationState> recordWindow({
    required String workspaceId,
    required WorkspaceEditDiffWindow window,
    DateTime? updatedAt,
  }) {
    return saveState(
      state: WorkspaceEditDiffPaginationState.fromWindow(
        workspaceId: workspaceId,
        window: window,
        updatedAt: updatedAt,
      ),
    );
  }

  Future<WorkspaceEditDiffPaginationState> saveState({
    required WorkspaceEditDiffPaginationState state,
  }) async {
    await _owner.writeJson(
      namespaceName: _namespaceName,
      key: _keyFor(state.planId),
      value: state.toJson(),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: state.workspaceId,
    );
    return state;
  }

  Future<bool> clearState({
    required String workspaceId,
    required String planId,
  }) {
    return _owner.delete(
      namespaceName: _namespaceName,
      key: _keyFor(planId),
      schemaVersion: schemaVersion,
      scope: FoundationResourceScope.workspace,
      workspaceId: workspaceId,
    );
  }

  String _keyFor(String planId) {
    return 'diff-pagination-${Uri.encodeComponent(planId)}';
  }
}

enum WorkspaceEditConfirmationStatus {
  ready,
  blockedNoChanges,
  blockedMissingDocuments,
  blockedTooManyEdits,
  blockedFileOperations,
}

enum WorkspaceEditRiskLevel { none, low, medium, high }

extension WorkspaceEditRiskLevelX on WorkspaceEditRiskLevel {
  String get wireValue => switch (this) {
    WorkspaceEditRiskLevel.none => 'none',
    WorkspaceEditRiskLevel.low => 'low',
    WorkspaceEditRiskLevel.medium => 'medium',
    WorkspaceEditRiskLevel.high => 'high',
  };
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
    this.riskLevel = WorkspaceEditRiskLevel.low,
    this.blockingReasons = const <String>[],
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
        riskLevel: WorkspaceEditRiskLevel.high,
        blockingReasons: const <String>[
          'Blocked file create/delete operation.',
        ],
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
        riskLevel: WorkspaceEditRiskLevel.none,
        blockingReasons: const <String>['No text changes to apply.'],
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
        riskLevel: WorkspaceEditRiskLevel.high,
        blockingReasons: <String>[
          'Missing document(s): ${missingDocumentIds.join(', ')}.',
        ],
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
        riskLevel: WorkspaceEditRiskLevel.high,
        blockingReasons: <String>[
          'Edit count ${preview.editCount} exceeds limit $maxEditCount.',
        ],
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
      riskLevel: preview.fileOperations.isNotEmpty
          ? WorkspaceEditRiskLevel.medium
          : WorkspaceEditRiskLevel.low,
      message: 'Workspace edit preview is ready for confirmation.',
      todo:
          'TODO: bind persisted review pagination state to lazy expansion controls.',
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
  final WorkspaceEditRiskLevel riskLevel;
  final List<String> blockingReasons;
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
      'riskLevel': riskLevel.wireValue,
      'blockingReasons': blockingReasons,
      'message': message,
      if (todo.isNotEmpty) 'todo': todo,
    };
  }
}

class WorkspaceEditReviewAction {
  const WorkspaceEditReviewAction({
    required this.id,
    required this.label,
    required this.enabled,
    this.reason = '',
  });

  final String id;
  final String label;
  final bool enabled;
  final String reason;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'id': id,
      'label': label,
      'enabled': enabled,
      if (reason.isNotEmpty) 'reason': reason,
    };
  }
}

class WorkspaceEditReviewControls {
  const WorkspaceEditReviewControls({
    required this.confirmationPlan,
    required this.apply,
    required this.cancel,
  });

  factory WorkspaceEditReviewControls.fromPreview(
    WorkspaceEditPreview preview, {
    int maxEditCount = 500,
  }) {
    return WorkspaceEditReviewControls.fromConfirmationPlan(
      WorkspaceEditConfirmationPlan.fromPreview(
        preview,
        maxEditCount: maxEditCount,
      ),
    );
  }

  factory WorkspaceEditReviewControls.fromConfirmationPlan(
    WorkspaceEditConfirmationPlan plan,
  ) {
    return WorkspaceEditReviewControls(
      confirmationPlan: plan,
      apply: WorkspaceEditReviewAction(
        id: 'workspace-edit.apply.${plan.planId}',
        label: 'Apply workspace edit',
        enabled: plan.ready,
        reason: plan.ready ? '' : plan.message,
      ),
      cancel: WorkspaceEditReviewAction(
        id: 'workspace-edit.cancel.${plan.planId}',
        label: 'Cancel workspace edit',
        enabled: true,
        reason: plan.requiresUserConfirmation
            ? ''
            : 'No user confirmation is required for this plan.',
      ),
    );
  }

  final WorkspaceEditConfirmationPlan confirmationPlan;
  final WorkspaceEditReviewAction apply;
  final WorkspaceEditReviewAction cancel;

  bool get canApply => apply.enabled;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'planId': confirmationPlan.planId,
      'status': confirmationPlan.status.wireValue,
      'canApply': canApply,
      'confirmationPlan': confirmationPlan.toJson(),
      'apply': apply.toJson(),
      'cancel': cancel.toJson(),
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

Map<String, Object?> _workspaceEditPlanEditToJson(FormattingEdit edit) {
  return <String, Object?>{
    'start': edit.range.start,
    'end': edit.range.end,
    'newText': edit.newText,
  };
}

WorkspaceEditSource? _workspaceEditSourceFromWire(Object? value) {
  return switch (value) {
    'agent' => WorkspaceEditSource.agent,
    'code-action' => WorkspaceEditSource.codeAction,
    'rename' => WorkspaceEditSource.rename,
    'formatting' => WorkspaceEditSource.formatting,
    'manual' => WorkspaceEditSource.manual,
    _ => null,
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
    this.rollbackApplied = false,
    this.rollbackMessages = const <String>[],
  });

  final bool applied;
  final String message;
  final int appliedEditCount;
  final List<String> appliedDocumentIds;
  final List<String> createdDocumentIds;
  final List<String> deletedDocumentIds;
  final List<String> skippedNoOpDocumentIds;
  final bool rollbackApplied;
  final List<String> rollbackMessages;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'applied': applied,
      'message': message,
      'appliedEditCount': appliedEditCount,
      'appliedDocumentIds': appliedDocumentIds,
      'createdDocumentIds': createdDocumentIds,
      'deletedDocumentIds': deletedDocumentIds,
      'skippedNoOpDocumentIds': skippedNoOpDocumentIds,
      'rollbackApplied': rollbackApplied,
      'rollbackMessages': rollbackMessages,
    };
  }
}

enum WorkspaceEditReviewResultStatus { applied, canceled, blocked, failed }

extension WorkspaceEditReviewResultStatusX on WorkspaceEditReviewResultStatus {
  String get wireValue => switch (this) {
    WorkspaceEditReviewResultStatus.applied => 'applied',
    WorkspaceEditReviewResultStatus.canceled => 'canceled',
    WorkspaceEditReviewResultStatus.blocked => 'blocked',
    WorkspaceEditReviewResultStatus.failed => 'failed',
  };
}

class WorkspaceEditReviewResultTelemetry {
  const WorkspaceEditReviewResultTelemetry({
    required this.planId,
    required this.source,
    required this.status,
    required this.message,
    required this.recordedAt,
    this.appliedEditCount = 0,
    this.appliedDocumentIds = const <String>[],
    this.createdDocumentIds = const <String>[],
    this.deletedDocumentIds = const <String>[],
    this.rollbackApplied = false,
  });

  factory WorkspaceEditReviewResultTelemetry.fromApplicationResult({
    required WorkspaceEditConfirmationPlan confirmationPlan,
    required WorkspaceEditApplicationResult result,
    DateTime? recordedAt,
  }) {
    return WorkspaceEditReviewResultTelemetry(
      planId: confirmationPlan.planId,
      source: confirmationPlan.source,
      status: result.applied
          ? WorkspaceEditReviewResultStatus.applied
          : WorkspaceEditReviewResultStatus.failed,
      message: result.message,
      recordedAt: (recordedAt ?? DateTime.now()).toUtc(),
      appliedEditCount: result.appliedEditCount,
      appliedDocumentIds: result.appliedDocumentIds,
      createdDocumentIds: result.createdDocumentIds,
      deletedDocumentIds: result.deletedDocumentIds,
      rollbackApplied: result.rollbackApplied,
    );
  }

  factory WorkspaceEditReviewResultTelemetry.canceled({
    required WorkspaceEditConfirmationPlan confirmationPlan,
    String message = 'Workspace edit review was canceled by user.',
    DateTime? recordedAt,
  }) {
    return WorkspaceEditReviewResultTelemetry(
      planId: confirmationPlan.planId,
      source: confirmationPlan.source,
      status: WorkspaceEditReviewResultStatus.canceled,
      message: message,
      recordedAt: (recordedAt ?? DateTime.now()).toUtc(),
    );
  }

  factory WorkspaceEditReviewResultTelemetry.blocked({
    required WorkspaceEditConfirmationPlan confirmationPlan,
    DateTime? recordedAt,
  }) {
    return WorkspaceEditReviewResultTelemetry(
      planId: confirmationPlan.planId,
      source: confirmationPlan.source,
      status: WorkspaceEditReviewResultStatus.blocked,
      message: confirmationPlan.message,
      recordedAt: (recordedAt ?? DateTime.now()).toUtc(),
    );
  }

  final String planId;
  final WorkspaceEditSource source;
  final WorkspaceEditReviewResultStatus status;
  final String message;
  final DateTime recordedAt;
  final int appliedEditCount;
  final List<String> appliedDocumentIds;
  final List<String> createdDocumentIds;
  final List<String> deletedDocumentIds;
  final bool rollbackApplied;

  bool get successful => status == WorkspaceEditReviewResultStatus.applied;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'planId': planId,
      'source': source.wireValue,
      'status': status.wireValue,
      'successful': successful,
      'message': message,
      'recordedAt': recordedAt.toIso8601String(),
      'appliedEditCount': appliedEditCount,
      'appliedDocumentIds': appliedDocumentIds,
      'createdDocumentIds': createdDocumentIds,
      'deletedDocumentIds': deletedDocumentIds,
      'rollbackApplied': rollbackApplied,
    };
  }
}

class WorkspaceEditApplyResultViewModel {
  const WorkspaceEditApplyResultViewModel({
    required this.planId,
    required this.source,
    required this.status,
    required this.severity,
    required this.title,
    required this.message,
    required this.successful,
    required this.appliedEditCount,
    required this.appliedDocumentIds,
    required this.createdDocumentIds,
    required this.deletedDocumentIds,
    required this.rollbackApplied,
    this.diffWindow,
    this.paginationState,
  });

  factory WorkspaceEditApplyResultViewModel.fromTelemetry({
    required WorkspaceEditConfirmationPlan confirmationPlan,
    required WorkspaceEditReviewResultTelemetry telemetry,
    WorkspaceEditDiffWindow? diffWindow,
    WorkspaceEditDiffPaginationState? paginationState,
  }) {
    return WorkspaceEditApplyResultViewModel(
      planId: confirmationPlan.planId,
      source: confirmationPlan.source,
      status: telemetry.status,
      severity: _workspaceEditResultSeverity(telemetry.status),
      title: _workspaceEditResultTitle(telemetry.status),
      message: telemetry.message,
      successful: telemetry.successful,
      appliedEditCount: telemetry.appliedEditCount,
      appliedDocumentIds: telemetry.appliedDocumentIds,
      createdDocumentIds: telemetry.createdDocumentIds,
      deletedDocumentIds: telemetry.deletedDocumentIds,
      rollbackApplied: telemetry.rollbackApplied,
      diffWindow: diffWindow,
      paginationState: paginationState,
    );
  }

  final String planId;
  final WorkspaceEditSource source;
  final WorkspaceEditReviewResultStatus status;
  final String severity;
  final String title;
  final String message;
  final bool successful;
  final int appliedEditCount;
  final List<String> appliedDocumentIds;
  final List<String> createdDocumentIds;
  final List<String> deletedDocumentIds;
  final bool rollbackApplied;
  final WorkspaceEditDiffWindow? diffWindow;
  final WorkspaceEditDiffPaginationState? paginationState;

  int get affectedDocumentCount {
    return <String>{
      ...appliedDocumentIds,
      ...createdDocumentIds,
      ...deletedDocumentIds,
    }.length;
  }

  bool get hasDiffWindow => diffWindow != null;
  bool get hasPaginationState => paginationState != null;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'planId': planId,
      'source': source.wireValue,
      'status': status.wireValue,
      'severity': severity,
      'title': title,
      'message': message,
      'successful': successful,
      'appliedEditCount': appliedEditCount,
      'affectedDocumentCount': affectedDocumentCount,
      'appliedDocumentIds': appliedDocumentIds,
      'createdDocumentIds': createdDocumentIds,
      'deletedDocumentIds': deletedDocumentIds,
      'rollbackApplied': rollbackApplied,
      'hasDiffWindow': hasDiffWindow,
      'hasPaginationState': hasPaginationState,
      if (diffWindow != null) 'diffWindow': diffWindow!.toJson(),
      if (paginationState != null) 'paginationState': paginationState!.toJson(),
    };
  }
}

String _workspaceEditResultSeverity(WorkspaceEditReviewResultStatus status) {
  return switch (status) {
    WorkspaceEditReviewResultStatus.applied => 'success',
    WorkspaceEditReviewResultStatus.canceled => 'info',
    WorkspaceEditReviewResultStatus.blocked => 'warning',
    WorkspaceEditReviewResultStatus.failed => 'error',
  };
}

String _workspaceEditResultTitle(WorkspaceEditReviewResultStatus status) {
  return switch (status) {
    WorkspaceEditReviewResultStatus.applied => 'Workspace edit applied',
    WorkspaceEditReviewResultStatus.canceled => 'Workspace edit canceled',
    WorkspaceEditReviewResultStatus.blocked => 'Workspace edit blocked',
    WorkspaceEditReviewResultStatus.failed => 'Workspace edit failed',
  };
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

    final rollbackOriginals = <String, DocumentState>{};
    final rollbackCreatedDocumentIds = <String>{};
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

    Future<WorkspaceEditApplicationResult> failWithRollback(
      String message, {
      int appliedEditCount = 0,
      List<String> appliedDocumentIds = const <String>[],
      List<String> skippedNoOpDocumentIds = const <String>[],
    }) async {
      final rollbackMessages = await _rollbackWorkspaceEditApplication(
        workspaceDocumentStore,
        originals: rollbackOriginals,
        createdDocumentIds: rollbackCreatedDocumentIds,
      );
      return WorkspaceEditApplicationResult(
        applied: false,
        message: message,
        appliedEditCount: appliedEditCount,
        appliedDocumentIds: List<String>.unmodifiable(appliedDocumentIds),
        createdDocumentIds: List<String>.unmodifiable(createdDocumentIds),
        deletedDocumentIds: List<String>.unmodifiable(deletedDocumentIds),
        skippedNoOpDocumentIds: List<String>.unmodifiable(
          skippedNoOpDocumentIds,
        ),
        rollbackApplied: rollbackMessages.isNotEmpty,
        rollbackMessages: List<String>.unmodifiable(rollbackMessages),
      );
    }

    for (final operation in plan.fileOperations) {
      if (operation.kind == WorkspaceFileOperationKind.create) {
        final exists = await workspaceDocumentStore.documentExists(
          operation.documentId,
        );
        if (exists && !operation.overwrite) {
          return failWithRollback(
            'Workspace edit plan ${plan.id} cannot create ${operation.documentId} because it already exists.',
          );
        }
        if (exists) {
          rollbackOriginals[operation.documentId] = await workspaceDocumentStore
              .loadDocument(operation.documentId);
        } else {
          rollbackCreatedDocumentIds.add(operation.documentId);
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
        final exists = await workspaceDocumentStore.documentExists(
          operation.documentId,
        );
        if (!exists) {
          return failWithRollback(
            'Workspace edit plan ${plan.id} cannot delete missing document ${operation.documentId}.',
          );
        }
        rollbackOriginals[operation.documentId] = await workspaceDocumentStore
            .loadDocument(operation.documentId);
        final removed = await workspaceDocumentStore.deleteDocument(
          operation.documentId,
        );
        if (!removed) {
          return failWithRollback(
            'Workspace edit plan ${plan.id} cannot delete missing document ${operation.documentId}.',
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
      rollbackOriginals.putIfAbsent(documentId, () => document);
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
        return failWithRollback(
          'Workspace edit plan ${plan.id} failed to save ${entry.key}: $error',
          appliedEditCount: appliedEditCount,
          appliedDocumentIds: appliedDocumentIds,
          skippedNoOpDocumentIds: skippedNoOpDocumentIds,
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

Future<List<String>> _rollbackWorkspaceEditApplication(
  WorkspaceDocumentStore workspaceDocumentStore, {
  required Map<String, DocumentState> originals,
  required Set<String> createdDocumentIds,
}) async {
  final messages = <String>[];
  for (final documentId in createdDocumentIds) {
    if (originals.containsKey(documentId)) {
      continue;
    }
    try {
      await workspaceDocumentStore.deleteDocument(documentId);
      messages.add('Rolled back created document $documentId.');
    } on Object catch (error) {
      messages.add('Failed to roll back created document $documentId: $error');
    }
  }
  for (final entry in originals.entries) {
    try {
      await workspaceDocumentStore.saveDocument(entry.value);
      messages.add('Restored document ${entry.key}.');
    } on Object catch (error) {
      messages.add('Failed to restore document ${entry.key}: $error');
    }
  }
  return messages;
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
