import '../editor/editor_controller.dart';
import '../editor/document_state.dart';
import '../language/language_contract.dart';
import '../workspace/workspace_document_store_types.dart';
import 'agent_provider_adapter.dart';

const int _maxAgentPatchReplacementTextLength = 200000;
const int _maxAgentPatchEditCount = 500;

class AgentCodePatchApplicationResult {
  const AgentCodePatchApplicationResult({
    required this.applied,
    required this.message,
    this.appliedEditCount = 0,
    this.appliedOperationCounts = const <String, int>{},
    this.appliedDocumentIds = const <String>[],
    this.createdDocumentIds = const <String>[],
    this.deletedDocumentIds = const <String>[],
    this.skippedNoOpDocumentIds = const <String>[],
  });

  final bool applied;
  final String message;
  final int appliedEditCount;
  final Map<String, int> appliedOperationCounts;
  final List<String> appliedDocumentIds;
  final List<String> createdDocumentIds;
  final List<String> deletedDocumentIds;
  final List<String> skippedNoOpDocumentIds;
}

class AgentCodePatchApplier {
  const AgentCodePatchApplier({required this.editorController});

  final EditorSessionController editorController;

  AgentCodePatchApplicationResult apply(AgentCodePatch patch) {
    final activeDocumentId = editorController.document.documentId;
    final relevantEdits = patch.edits
        .where((edit) => edit.documentId == activeDocumentId)
        .toList(growable: false);
    final skippedEditCount = patch.edits.length - relevantEdits.length;

    if (relevantEdits.isEmpty) {
      return AgentCodePatchApplicationResult(
        applied: false,
        message:
            'Agent patch ${patch.patchId} has no edits for the active document.',
      );
    }
    if (_containsFileOperationEdit(relevantEdits)) {
      return AgentCodePatchApplicationResult(
        applied: false,
        message:
            'Agent patch ${patch.patchId} contains file operation edit(s); use workspace patch application for file creation or deletion.',
      );
    }
    if (relevantEdits.length > _maxAgentPatchEditCount) {
      return AgentCodePatchApplicationResult(
        applied: false,
        message:
            'Agent patch ${patch.patchId} contains too many edits: ${relevantEdits.length} exceeds $_maxAgentPatchEditCount.',
      );
    }

    final validationFailure = _validatePatchEditsForDocument(
      patch: patch,
      document: editorController.document,
      edits: relevantEdits,
    );
    if (validationFailure != null) {
      return AgentCodePatchApplicationResult(
        applied: false,
        message: validationFailure,
      );
    }
    final sortedEdits = _sortedEdits(relevantEdits);
    final nextDocument = _applyEditsToDocument(
      editorController.document,
      sortedEdits,
    );
    if (nextDocument.text == editorController.document.text) {
      return AgentCodePatchApplicationResult(
        applied: false,
        message:
            'Agent patch ${patch.patchId} produced no text changes for the active document.',
        skippedNoOpDocumentIds: <String>[activeDocumentId],
      );
    }

    final formattingEdits = sortedEdits
        .map(
          (edit) => FormattingEdit(
            range: SourceRange(start: edit.start, end: edit.end),
            newText: edit.replacementText,
          ),
        )
        .toList(growable: false);
    editorController.applyFormattingEdits(formattingEdits);
    final operationCounts = _operationCountsForEdits(relevantEdits);

    return AgentCodePatchApplicationResult(
      applied: true,
      appliedEditCount: relevantEdits.length,
      appliedOperationCounts: operationCounts,
      appliedDocumentIds: <String>[activeDocumentId],
      message: _withOperationCounts(
        skippedEditCount == 0
            ? 'Applied ${relevantEdits.length} agent patch edit(s).'
            : 'Applied ${relevantEdits.length} agent patch edit(s); skipped $skippedEditCount edit(s) for unopened documents.',
        operationCounts,
      ),
    );
  }
}

class AgentWorkspaceCodePatchApplier {
  AgentWorkspaceCodePatchApplier({
    required this.editorController,
    required this.workspaceDocumentStore,
    Iterable<String> dirtyDocumentIds = const <String>[],
    Iterable<String> sampledDocumentIds = const <String>[],
  }) : dirtyDocumentIds = Set<String>.unmodifiable(dirtyDocumentIds),
       sampledDocumentIds = Set<String>.unmodifiable(sampledDocumentIds);

  final EditorSessionController editorController;
  final WorkspaceDocumentStore workspaceDocumentStore;
  final Set<String> dirtyDocumentIds;
  final Set<String> sampledDocumentIds;

  Future<AgentCodePatchApplicationResult> apply(AgentCodePatch patch) async {
    if (patch.edits.length > _maxAgentPatchEditCount) {
      return AgentCodePatchApplicationResult(
        applied: false,
        message:
            'Agent patch ${patch.patchId} contains too many edits: ${patch.edits.length} exceeds $_maxAgentPatchEditCount.',
      );
    }
    final groupedEdits = <String, List<AgentCodePatchEdit>>{};
    for (final edit in patch.edits) {
      groupedEdits.putIfAbsent(edit.documentId, () => <AgentCodePatchEdit>[]).add(edit);
    }
    if (groupedEdits.isEmpty) {
      return AgentCodePatchApplicationResult(
        applied: false,
        message: 'Agent patch ${patch.patchId} has no edits.',
      );
    }

    final documents = <String, DocumentState>{};
    for (final entry in groupedEdits.entries) {
      final documentIdValidationFailure = _validatePatchDocumentId(
        patch: patch,
        documentId: entry.key,
      );
      if (documentIdValidationFailure != null) {
        return AgentCodePatchApplicationResult(
          applied: false,
          message: documentIdValidationFailure,
        );
      }
      final dirtyDocumentFailure = _validateInactiveDirtyDocument(
        patch: patch,
        documentId: entry.key,
        activeDocumentId: editorController.document.documentId,
        dirtyDocumentIds: dirtyDocumentIds,
      );
      if (dirtyDocumentFailure != null) {
        return AgentCodePatchApplicationResult(
          applied: false,
          message: dirtyDocumentFailure,
        );
      }
      final unsampledDocumentFailure = _validateUnsampledInactiveDocument(
        patch: patch,
        documentId: entry.key,
        activeDocumentId: editorController.document.documentId,
        sampledDocumentIds: sampledDocumentIds,
        createsDocument: _isSingleCreateDocumentEdit(entry.value),
      );
      if (unsampledDocumentFailure != null) {
        return AgentCodePatchApplicationResult(
          applied: false,
          message: unsampledDocumentFailure,
        );
      }
      late final DocumentState document;
      final createsDocument = _isSingleCreateDocumentEdit(entry.value);
      final deletesDocument = _isSingleDeleteDocumentEdit(entry.value);
      if (_containsFileOperationEdit(entry.value) &&
          !createsDocument &&
          !deletesDocument) {
        return AgentCodePatchApplicationResult(
          applied: false,
          message:
              'Agent patch ${patch.patchId} mixes file operation and replace edits for ${entry.key}.',
        );
      }
      if (createsDocument) {
        if (entry.key == editorController.document.documentId) {
          return AgentCodePatchApplicationResult(
            applied: false,
            message:
                'Agent patch ${patch.patchId} cannot create the active document ${entry.key}.',
          );
        }
        late final bool exists;
        try {
          exists = await workspaceDocumentStore.documentExists(entry.key);
        } on Object catch (error) {
          return AgentCodePatchApplicationResult(
            applied: false,
            message:
                'Agent patch ${patch.patchId} failed to check ${entry.key}: $error',
          );
        }
        if (exists) {
          return AgentCodePatchApplicationResult(
            applied: false,
            message:
                'Agent patch ${patch.patchId} cannot create ${entry.key} because it already exists.',
          );
        }
        document = DocumentState(documentId: entry.key, text: '', revision: 0);
      } else if (deletesDocument) {
        if (entry.key == editorController.document.documentId) {
          return AgentCodePatchApplicationResult(
            applied: false,
            message:
                'Agent patch ${patch.patchId} cannot delete the active document ${entry.key}.',
          );
        }
        late final bool exists;
        try {
          exists = await workspaceDocumentStore.documentExists(entry.key);
        } on Object catch (error) {
          return AgentCodePatchApplicationResult(
            applied: false,
            message:
                'Agent patch ${patch.patchId} failed to check ${entry.key}: $error',
          );
        }
        if (!exists) {
          return AgentCodePatchApplicationResult(
            applied: false,
            message:
                'Agent patch ${patch.patchId} cannot delete ${entry.key} because it does not exist.',
          );
        }
        try {
          document = await workspaceDocumentStore.loadDocument(entry.key);
        } on Object catch (error) {
          return AgentCodePatchApplicationResult(
            applied: false,
            message:
                'Agent patch ${patch.patchId} failed to load ${entry.key}: $error',
          );
        }
      } else if (entry.key == editorController.document.documentId) {
        document = editorController.document;
      } else {
        try {
          document = await workspaceDocumentStore.loadDocument(entry.key);
        } on Object catch (error) {
          return AgentCodePatchApplicationResult(
            applied: false,
            message:
                'Agent patch ${patch.patchId} failed to load ${entry.key}: $error',
          );
        }
      }
      final validationFailure = _validatePatchEditsForDocument(
        patch: patch,
        document: document,
        edits: entry.value,
      );
      if (validationFailure != null) {
        return AgentCodePatchApplicationResult(
          applied: false,
          message: validationFailure,
        );
      }
      documents[entry.key] = document;
    }

    var appliedEditCount = 0;
    final appliedOperationCounts = <String, int>{};
    final appliedDocumentIds = <String>{};
    final createdDocumentIds = <String>{};
    final deletedDocumentIds = <String>{};
    final skippedNoOpDocumentIds = <String>{};
    final rollbackEntries = <_WorkspacePatchRollbackEntry>[];
    final activeDocumentId = editorController.document.documentId;
    final activeEntry = groupedEdits[activeDocumentId];
    for (final entry in groupedEdits.entries) {
      if (entry.key == activeDocumentId) {
        continue;
      }

      final document = documents[entry.key]!;
      if (_isSingleDeleteDocumentEdit(entry.value)) {
        try {
          final deleted = await workspaceDocumentStore.deleteDocument(entry.key);
          if (!deleted) {
            return _failWithRollback(
              message:
                  'Agent patch ${patch.patchId} failed to delete ${entry.key}: document not found',
              rollbackEntries: rollbackEntries,
            );
          }
        } on Object catch (error) {
          return _failWithRollback(
            message:
                'Agent patch ${patch.patchId} failed to delete ${entry.key}: $error',
            rollbackEntries: rollbackEntries,
          );
        }
        rollbackEntries.add(
          _WorkspacePatchRollbackEntry(
            documentId: entry.key,
            previousDocument: document,
          ),
        );
        appliedEditCount += entry.value.length;
        _addOperationCounts(appliedOperationCounts, entry.value);
        appliedDocumentIds.add(entry.key);
        deletedDocumentIds.add(entry.key);
        continue;
      }

      final isCreateDocumentEdit = _isSingleCreateDocumentEdit(entry.value);
      final nextDocument = _applyEditsToDocument(document, entry.value);
      if (!isCreateDocumentEdit && nextDocument.text == document.text) {
        skippedNoOpDocumentIds.add(entry.key);
        continue;
      }
      try {
        await workspaceDocumentStore.saveDocument(nextDocument);
      } on Object catch (error) {
        return _failWithRollback(
          message:
              'Agent patch ${patch.patchId} failed to save ${entry.key}: $error',
          rollbackEntries: rollbackEntries,
        );
      }
      rollbackEntries.add(
        _WorkspacePatchRollbackEntry(
          documentId: entry.key,
          previousDocument: isCreateDocumentEdit ? null : document,
        ),
      );
      appliedEditCount += entry.value.length;
      _addOperationCounts(appliedOperationCounts, entry.value);
      appliedDocumentIds.add(entry.key);
      if (isCreateDocumentEdit) {
        createdDocumentIds.add(entry.key);
      }
    }

    if (activeEntry != null) {
      final result = AgentCodePatchApplier(editorController: editorController)
          .apply(
            AgentCodePatch(
              patchId: patch.patchId,
              summary: patch.summary,
              baseRevision: patch.baseRevision,
              edits: activeEntry,
            ),
          );
      if (!result.applied) {
        if (result.skippedNoOpDocumentIds.isNotEmpty) {
          skippedNoOpDocumentIds.addAll(result.skippedNoOpDocumentIds);
        } else {
          return _failWithRollback(
            message: result.message,
            rollbackEntries: rollbackEntries,
          );
        }
      } else {
        appliedEditCount += result.appliedEditCount;
        appliedDocumentIds.addAll(result.appliedDocumentIds);
        _mergeOperationCounts(
          appliedOperationCounts,
          result.appliedOperationCounts,
        );
      }
    }

    if (appliedEditCount == 0) {
      return AgentCodePatchApplicationResult(
        applied: false,
        message: 'Agent patch ${patch.patchId} produced no text changes.',
        skippedNoOpDocumentIds: List<String>.unmodifiable(
          skippedNoOpDocumentIds,
        ),
      );
    }

    final skippedNoOpIds = skippedNoOpDocumentIds.toList(growable: false)
      ..sort();
    final operationCounts = Map<String, int>.unmodifiable(
      appliedOperationCounts,
    );
    return AgentCodePatchApplicationResult(
      applied: true,
      appliedEditCount: appliedEditCount,
      appliedOperationCounts: operationCounts,
      appliedDocumentIds: List<String>.unmodifiable(appliedDocumentIds),
      createdDocumentIds: List<String>.unmodifiable(createdDocumentIds),
      deletedDocumentIds: List<String>.unmodifiable(deletedDocumentIds),
      skippedNoOpDocumentIds: List<String>.unmodifiable(skippedNoOpIds),
      message: _withOperationCounts(
        'Applied $appliedEditCount agent workspace patch edit(s).',
        operationCounts,
      ),
    );
  }

  Future<AgentCodePatchApplicationResult> _failWithRollback({
    required String message,
    required List<_WorkspacePatchRollbackEntry> rollbackEntries,
  }) async {
    final rollbackFailure = await _rollbackWorkspacePatch(rollbackEntries);
    return AgentCodePatchApplicationResult(
      applied: false,
      message: rollbackFailure == null
          ? message
          : '$message; rollback failed: $rollbackFailure',
    );
  }

  Future<String?> _rollbackWorkspacePatch(
    List<_WorkspacePatchRollbackEntry> rollbackEntries,
  ) async {
    for (final entry in rollbackEntries.reversed) {
      try {
        final previousDocument = entry.previousDocument;
        if (previousDocument == null) {
          await workspaceDocumentStore.deleteDocument(entry.documentId);
        } else {
          await workspaceDocumentStore.saveDocument(previousDocument);
        }
      } on Object catch (error) {
        return '${entry.documentId}: $error';
      }
    }
    return null;
  }
}

class _WorkspacePatchRollbackEntry {
  const _WorkspacePatchRollbackEntry({
    required this.documentId,
    required this.previousDocument,
  });

  final String documentId;
  final DocumentState? previousDocument;
}

Map<String, int> _operationCountsForEdits(Iterable<AgentCodePatchEdit> edits) {
  final counts = <String, int>{};
  _addOperationCounts(counts, edits);
  return Map<String, int>.unmodifiable(counts);
}

void _addOperationCounts(
  Map<String, int> counts,
  Iterable<AgentCodePatchEdit> edits,
) {
  for (final edit in edits) {
    final operation = edit.operation.wireValue;
    counts[operation] = (counts[operation] ?? 0) + 1;
  }
}

void _mergeOperationCounts(
  Map<String, int> counts,
  Map<String, int> incoming,
) {
  for (final entry in incoming.entries) {
    counts[entry.key] = (counts[entry.key] ?? 0) + entry.value;
  }
}

String _withOperationCounts(String message, Map<String, int> operationCounts) {
  final summary = _operationCountsSummary(operationCounts);
  if (summary.isEmpty) {
    return message;
  }
  return '$message Operations: $summary.';
}

String _operationCountsSummary(Map<String, int> operationCounts) {
  const order = <String>['replace', 'create', 'delete'];
  final parts = <String>[
    for (final operation in order)
      if ((operationCounts[operation] ?? 0) > 0)
        '$operation ${operationCounts[operation]}',
    for (final entry in operationCounts.entries)
      if (!order.contains(entry.key) && entry.value > 0)
        '${entry.key} ${entry.value}',
  ];
  return parts.join(', ');
}

String? _validatePatchEditsForDocument({
  required AgentCodePatch patch,
  required DocumentState document,
  required List<AgentCodePatchEdit> edits,
}) {
  for (final edit in edits) {
    final documentIdValidationFailure = _validatePatchDocumentId(
      patch: patch,
      documentId: edit.documentId,
    );
    if (documentIdValidationFailure != null) {
      return documentIdValidationFailure;
    }
    if (edit.replacementText.length > _maxAgentPatchReplacementTextLength) {
      return 'Agent patch ${patch.patchId} contains an edit replacement that is too large for ${edit.documentId}.';
    }
    final expectedRevision = _expectedRevisionForEdit(patch: patch, edit: edit);
    if (expectedRevision != null && expectedRevision != document.revision) {
      return 'Agent patch ${patch.patchId} was generated for revision $expectedRevision, but ${document.documentId} is revision ${document.revision}.';
    }
    if (edit.start < 0 || edit.end < edit.start || edit.end > document.length) {
      return 'Agent patch ${patch.patchId} contains an invalid edit range for ${document.documentId}.';
    }
    if (edit.operation == AgentCodePatchEditOperation.create &&
        (edit.start != 0 || edit.end != 0)) {
      return 'Agent patch ${patch.patchId} contains an invalid create edit range for ${document.documentId}.';
    }
    if (edit.operation == AgentCodePatchEditOperation.delete &&
        (edit.start != 0 || edit.end != 0 || edit.replacementText.isNotEmpty)) {
      return 'Agent patch ${patch.patchId} contains an invalid delete edit for ${document.documentId}.';
    }
  }
  final sortedEdits = _sortedEdits(edits);
  for (var index = 1; index < sortedEdits.length; index += 1) {
    if (sortedEdits[index].start < sortedEdits[index - 1].end) {
      return 'Agent patch ${patch.patchId} contains overlapping edits for ${document.documentId}.';
    }
    if (_sameInsertionOffset(sortedEdits[index - 1], sortedEdits[index])) {
      return 'Agent patch ${patch.patchId} contains ambiguous same-offset insert edits for ${document.documentId}.';
    }
  }
  return null;
}

int? _expectedRevisionForEdit({
  required AgentCodePatch patch,
  required AgentCodePatchEdit edit,
}) {
  if (edit.operation != AgentCodePatchEditOperation.replace) {
    return edit.baseRevision;
  }
  return edit.baseRevision ?? patch.baseRevision;
}

String? _validatePatchDocumentId({
  required AgentCodePatch patch,
  required String documentId,
}) {
  if (documentId.trim().isEmpty) {
    return 'Agent patch ${patch.patchId} contains an edit without documentId.';
  }
  if (_containsPathTraversalSegment(documentId)) {
    return 'Agent patch ${patch.patchId} contains an unsafe documentId $documentId.';
  }
  return null;
}

String? _validateInactiveDirtyDocument({
  required AgentCodePatch patch,
  required String documentId,
  required String activeDocumentId,
  required Set<String> dirtyDocumentIds,
}) {
  if (documentId == activeDocumentId || !dirtyDocumentIds.contains(documentId)) {
    return null;
  }
  return 'Agent patch ${patch.patchId} cannot modify inactive dirty document $documentId; switch to that file and save or discard local changes before applying the workspace patch.';
}

String? _validateUnsampledInactiveDocument({
  required AgentCodePatch patch,
  required String documentId,
  required String activeDocumentId,
  required Set<String> sampledDocumentIds,
  required bool createsDocument,
}) {
  if (sampledDocumentIds.isEmpty ||
      createsDocument ||
      documentId == activeDocumentId ||
      sampledDocumentIds.contains(documentId)) {
    return null;
  }
  return 'Agent patch ${patch.patchId} cannot modify unsampled inactive document $documentId; open or sample the file before applying the workspace patch.';
}

bool _containsFileOperationEdit(List<AgentCodePatchEdit> edits) {
  return edits.any(
    (edit) => edit.operation != AgentCodePatchEditOperation.replace,
  );
}

bool _isSingleCreateDocumentEdit(List<AgentCodePatchEdit> edits) {
  return edits.length == 1 &&
      edits.single.operation == AgentCodePatchEditOperation.create;
}

bool _isSingleDeleteDocumentEdit(List<AgentCodePatchEdit> edits) {
  return edits.length == 1 &&
      edits.single.operation == AgentCodePatchEditOperation.delete;
}

bool _containsPathTraversalSegment(String documentId) {
  return documentId
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .any((segment) => segment == '.' || segment == '..');
}

bool _sameInsertionOffset(AgentCodePatchEdit left, AgentCodePatchEdit right) {
  return left.start == left.end &&
      right.start == right.end &&
      left.start == right.start;
}

List<AgentCodePatchEdit> _sortedEdits(List<AgentCodePatchEdit> edits) {
  return [...edits]..sort((left, right) => left.start.compareTo(right.start));
}

DocumentState _applyEditsToDocument(
  DocumentState document,
  List<AgentCodePatchEdit> edits,
) {
  var nextText = document.text;
  for (final edit in _sortedEdits(edits).reversed) {
    nextText = nextText.replaceRange(
      edit.start,
      edit.end,
      edit.replacementText,
    );
  }
  return DocumentState(
    documentId: document.documentId,
    text: nextText,
    revision: document.revision + 1,
  );
}
