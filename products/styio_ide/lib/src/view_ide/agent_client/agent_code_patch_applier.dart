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

/// Retained type for synchronous call sites, but intentionally fail-closed.
///
/// Agent edits require the asynchronous workspace preview/commit lifecycle.
final class AgentCodePatchApplier {
  const AgentCodePatchApplier();

  AgentCodePatchApplicationResult apply(AgentCodePatch patch) {
    return AgentCodePatchApplicationResult(
      applied: false,
      message:
          'Agent patch ${patch.patchId} requires workspace transaction preview.',
    );
  }
}

/// Converts an Agent DTO into the IDE's sole revisioned mutation authority.
final class AgentWorkspaceCodePatchApplier {
  const AgentWorkspaceCodePatchApplier({
    required this.transactionService,
    required this.revisionService,
  });

  final WorkspaceTransactionService transactionService;
  final InMemoryWorkspaceRevisionService revisionService;

  Future<AgentCodePatchApplicationResult> apply(AgentCodePatch patch) async {
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

    final snapshot = revisionService.snapshot();
    final grouped = <String, List<AgentCodePatchEdit>>{};
    for (final edit in patch.edits) {
      grouped
          .putIfAbsent(edit.documentId, () => <AgentCodePatchEdit>[])
          .add(edit);
    }
    final resources = <WorkspaceResourceChange>[];
    for (final entry in grouped.entries) {
      final document = snapshot.documents[entry.key];
      if (document == null) {
        return AgentCodePatchApplicationResult(
          applied: false,
          message: 'Agent patch ${patch.patchId} targets an unavailable resource.',
        );
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

    final documentIds = grouped.keys.toList(growable: false)..sort();
    return AgentCodePatchApplicationResult(
      applied: true,
      message: 'Applied Agent patch ${patch.patchId} atomically.',
      appliedEditCount: patch.edits.length,
      appliedOperationCounts: <String, int>{
        AgentCodePatchEditOperation.replace.wireValue: patch.edits.length,
      },
      appliedDocumentIds: List<String>.unmodifiable(documentIds),
    );
  }
}
