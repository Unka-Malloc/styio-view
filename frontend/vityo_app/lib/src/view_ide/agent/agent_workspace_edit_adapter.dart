import '../language/language_contract.dart';
import '../workspace/workspace.dart';
import 'agent_provider_adapter.dart';

class AgentWorkspaceEditPlanConversion {
  const AgentWorkspaceEditPlanConversion({
    required this.converted,
    required this.message,
    this.plan,
    this.skippedFileOperationCount = 0,
  });

  final bool converted;
  final String message;
  final WorkspaceEditPlan? plan;
  final int skippedFileOperationCount;
}

class AgentWorkspaceEditPlanAdapter {
  const AgentWorkspaceEditPlanAdapter();

  AgentWorkspaceEditPlanConversion convert(AgentCodePatch patch) {
    if (patch.edits.isEmpty) {
      return AgentWorkspaceEditPlanConversion(
        converted: false,
        message: 'Agent patch ${patch.patchId} has no edits.',
      );
    }

    final fileOperationCount = patch.edits
        .where((edit) => edit.operation != AgentCodePatchEditOperation.replace)
        .length;
    if (fileOperationCount > 0) {
      return AgentWorkspaceEditPlanConversion(
        converted: false,
        skippedFileOperationCount: fileOperationCount,
        message:
            'Agent patch ${patch.patchId} contains $fileOperationCount file operation edit(s); use AgentWorkspaceCodePatchApplier for create/delete.',
      );
    }

    final editsByDocument = <String, List<FormattingEdit>>{};
    for (final edit in patch.edits) {
      editsByDocument
          .putIfAbsent(edit.documentId, () => <FormattingEdit>[])
          .add(
            FormattingEdit(
              range: SourceRange(start: edit.start, end: edit.end),
              newText: edit.replacementText,
            ),
          );
    }

    return AgentWorkspaceEditPlanConversion(
      converted: true,
      message: 'Converted agent patch ${patch.patchId} to workspace edit plan.',
      plan: WorkspaceEditPlan(
        id: patch.patchId,
        summary: patch.summary,
        source: WorkspaceEditSource.agent,
        editsByDocument: Map<String, List<FormattingEdit>>.unmodifiable(
          editsByDocument.map(
            (documentId, edits) => MapEntry<String, List<FormattingEdit>>(
              documentId,
              List<FormattingEdit>.unmodifiable(edits),
            ),
          ),
        ),
      ),
    );
  }
}
