import '../editor/document_state.dart';
import '../language/language_contract.dart';
import 'workspace_document_store_types.dart';

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

class WorkspaceEditPlan {
  const WorkspaceEditPlan({
    required this.id,
    required this.summary,
    required this.source,
    required this.editsByDocument,
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

  int get editCount {
    return editsByDocument.values.fold<int>(
      0,
      (total, edits) => total + edits.length,
    );
  }

  List<String> get documentIds {
    final ids = editsByDocument.keys.toList(growable: false);
    ids.sort();
    return ids;
  }

  WorkspaceEditPreview preview(List<DocumentState> documents) {
    final documentsById = {
      for (final document in documents) document.documentId: document,
    };
    final previews = <WorkspaceEditDocumentPreview>[];
    final missingDocumentIds = <String>[];
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
    this.missingDocumentIds = const <String>[],
  });

  final String planId;
  final String summary;
  final WorkspaceEditSource source;
  final List<WorkspaceEditDocumentPreview> documents;
  final List<String> missingDocumentIds;

  bool get hasChanges => documents.any((document) => document.changed);

  bool get hasMissingDocuments => missingDocumentIds.isNotEmpty;

  int get editCount {
    return documents.fold<int>(
      0,
      (total, document) => total + document.edits.length,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'planId': planId,
      'summary': summary,
      'source': source.wireValue,
      'documentCount': documents.length,
      'missingDocumentCount': missingDocumentIds.length,
      if (missingDocumentIds.isNotEmpty) 'missingDocumentIds': missingDocumentIds,
      'editCount': editCount,
      'hasChanges': hasChanges,
      'hasMissingDocuments': hasMissingDocuments,
      'documents': documents
          .map((document) => document.toJson())
          .toList(growable: false),
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
          .map(_workspaceEditPreviewEditToJson)
          .toList(growable: false),
      'beforeTextSample': _sampleText(beforeText),
      'afterTextSample': _sampleText(afterText),
    };
  }
}

Map<String, Object?> _workspaceEditPreviewEditToJson(FormattingEdit edit) {
  return <String, Object?>{
    'start': edit.range.start,
    'end': edit.range.end,
    'newText': edit.newText,
  };
}

class WorkspaceEditApplicationResult {
  const WorkspaceEditApplicationResult({
    required this.applied,
    required this.message,
    this.appliedEditCount = 0,
    this.appliedDocumentIds = const <String>[],
  });

  final bool applied;
  final String message;
  final int appliedEditCount;
  final List<String> appliedDocumentIds;
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
    if (plan.editCount == 0) {
      return WorkspaceEditApplicationResult(
        applied: false,
        message: 'Workspace edit plan ${plan.id} has no edits.',
      );
    }
    if (plan.editCount > maxEditCount) {
      return WorkspaceEditApplicationResult(
        applied: false,
        message:
            'Workspace edit plan ${plan.id} contains too many edits: ${plan.editCount} exceeds $maxEditCount.',
      );
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
    var appliedEditCount = 0;
    for (final entry in normalizedEditsByDocument.entries) {
      final document = loadedDocuments[entry.key]!;
      final nextDocument = _applyEditsToDocument(document, entry.value);
      try {
        await workspaceDocumentStore.saveDocument(nextDocument);
      } on Object catch (error) {
        return WorkspaceEditApplicationResult(
          applied: false,
          message:
              'Workspace edit plan ${plan.id} failed to save ${entry.key}: $error',
          appliedEditCount: appliedEditCount,
          appliedDocumentIds: List<String>.unmodifiable(appliedDocumentIds),
        );
      }
      appliedDocumentIds.add(entry.key);
      appliedEditCount += entry.value.length;
    }

    appliedDocumentIds.sort();
    return WorkspaceEditApplicationResult(
      applied: true,
      appliedEditCount: appliedEditCount,
      appliedDocumentIds: List<String>.unmodifiable(appliedDocumentIds),
      message:
          'Applied $appliedEditCount workspace edit(s) from ${plan.source.wireValue} plan ${plan.id}.',
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
