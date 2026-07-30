import '../../ide/workspace/workspace_change_set.dart';
import '../../ide/workspace/workspace_revision_service.dart';
import '../../ide/workspace/workspace_transaction_service.dart';
import 'agent_provider_adapter.dart';

const int _maxAgentPatchEditCount = 500;
const int _maxAgentPatchReplacementTextLength = 200000;

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

/// Converts an Agent DTO into the IDE's sole revisioned mutation authority.
final class AgentCodePatchApplier {
  const AgentCodePatchApplier({
    required this.transactionService,
    required this.revisionService,
  });

  final WorkspaceTransactionService transactionService;
  final InMemoryWorkspaceRevisionService revisionService;

  Future<AgentCodePatchApplicationResult> apply(AgentCodePatch patch) async {
    if (patch.patchId.trim().isEmpty) {
      return const AgentCodePatchApplicationResult(
        applied: false,
        message: 'Agent patch id must not be empty.',
      );
    }
    if (patch.edits.isEmpty) {
      return AgentCodePatchApplicationResult(
        applied: false,
        message: 'Agent patch ${patch.patchId} has no edits.',
      );
    }
    if (patch.edits.length > _maxAgentPatchEditCount) {
      return AgentCodePatchApplicationResult(
        applied: false,
        message: 'Agent patch ${patch.patchId} exceeds the edit limit.',
      );
    }
    if (patch.edits.any(
      (edit) =>
          edit.operation != AgentCodePatchEditOperation.replace ||
          edit.replacementText.length > _maxAgentPatchReplacementTextLength,
    )) {
      return AgentCodePatchApplicationResult(
        applied: false,
        message:
            'Agent patch ${patch.patchId} contains an unsupported or oversized edit.',
      );
    }
    for (final edit in patch.edits) {
      if (edit.documentId.trim().isEmpty) {
        return AgentCodePatchApplicationResult(
          applied: false,
          message:
              'Agent patch ${patch.patchId} contains an edit without documentId.',
        );
      }
      if (_containsPathTraversalSegment(edit.documentId)) {
        return AgentCodePatchApplicationResult(
          applied: false,
          message:
              'Agent patch ${patch.patchId} contains an unsafe documentId ${edit.documentId}.',
        );
      }
    }

    final snapshot = revisionService.snapshot();
    final grouped = <String, List<AgentCodePatchEdit>>{};
    for (final edit in patch.edits) {
      grouped
          .putIfAbsent(edit.documentId, () => <AgentCodePatchEdit>[])
          .add(edit);
    }
    final resources = <WorkspaceResourceChange>[];
    final skippedNoOpDocumentIds = <String>[];
    for (final entry in grouped.entries) {
      final document = snapshot.documents[entry.key];
      if (document == null) {
        return AgentCodePatchApplicationResult(
          applied: false,
          message:
              'Agent patch ${patch.patchId} targets an unavailable resource.',
        );
      }
      final edits = List<AgentCodePatchEdit>.of(entry.value)
        ..sort((left, right) {
          final byStart = left.start.compareTo(right.start);
          return byStart == 0 ? left.end.compareTo(right.end) : byStart;
        });
      var previousEnd = -1;
      AgentCodePatchEdit? previous;
      for (final edit in edits) {
        if (edit.start < 0 ||
            edit.end < edit.start ||
            edit.end > document.text.length) {
          return AgentCodePatchApplicationResult(
            applied: false,
            message:
                'Agent patch ${patch.patchId} contains an invalid edit range.',
          );
        }
        if (edit.start < previousEnd) {
          return AgentCodePatchApplicationResult(
            applied: false,
            message: 'Agent patch ${patch.patchId} contains overlapping edits.',
          );
        }
        if (previous != null &&
            previous.start == previous.end &&
            edit.start == edit.end &&
            previous.start == edit.start) {
          return AgentCodePatchApplicationResult(
            applied: false,
            message:
                'Agent patch ${patch.patchId} contains ambiguous same-offset insert edits.',
          );
        }
        previousEnd = edit.end;
        previous = edit;
      }

      var nextText = document.text;
      for (final edit in edits.reversed) {
        nextText = nextText.replaceRange(
          edit.start,
          edit.end,
          edit.replacementText,
        );
      }
      if (nextText == document.text) {
        skippedNoOpDocumentIds.add(entry.key);
        continue;
      }
      final expectedRevision =
          entry.value.first.baseRevision ?? patch.baseRevision;
      resources.add(
        WorkspaceResourceChange(
          resourceId: entry.key,
          baseDocumentRevision: expectedRevision ?? document.revision,
          edits: <WorkspaceTextChange>[
            for (final edit in entry.value)
              WorkspaceTextChange(
                start: edit.start,
                end: edit.end,
                replacement: edit.replacementText,
              ),
          ],
        ),
      );
    }
    if (resources.isEmpty) {
      skippedNoOpDocumentIds.sort();
      return AgentCodePatchApplicationResult(
        applied: false,
        message: 'Agent patch ${patch.patchId} produced no text changes.',
        skippedNoOpDocumentIds: List<String>.unmodifiable(
          skippedNoOpDocumentIds,
        ),
      );
    }

    final preview = await transactionService.preview(
      WorkspaceChangeSet(
        id: patch.patchId,
        baseWorkspaceRevision: snapshot.workspaceRevision,
        resources: resources,
      ),
    );
    if (preview.outcome != WorkspaceTransactionOutcome.ready) {
      return AgentCodePatchApplicationResult(
        applied: false,
        message: 'Agent patch ${patch.patchId} conflicts with the workspace.',
      );
    }
    final receipt = await transactionService.commit(preview.id);
    if (receipt.outcome != WorkspaceTransactionOutcome.committed) {
      return AgentCodePatchApplicationResult(
        applied: false,
        message: 'Agent patch ${patch.patchId} was not committed.',
      );
    }

    final documentIds =
        resources.map((resource) => resource.resourceId).toList(growable: false)
          ..sort();
    skippedNoOpDocumentIds.sort();
    return AgentCodePatchApplicationResult(
      applied: true,
      message: 'Applied Agent patch ${patch.patchId} atomically.',
      appliedEditCount: patch.edits.length,
      appliedOperationCounts: <String, int>{
        AgentCodePatchEditOperation.replace.wireValue: patch.edits.length,
      },
      appliedDocumentIds: List<String>.unmodifiable(documentIds),
      skippedNoOpDocumentIds: List<String>.unmodifiable(skippedNoOpDocumentIds),
    );
  }
}

bool _containsPathTraversalSegment(String documentId) {
  return documentId
      .replaceAll('\\', '/')
      .split('/')
      .where((segment) => segment.isNotEmpty)
      .any((segment) => segment == '.' || segment == '..');
}
