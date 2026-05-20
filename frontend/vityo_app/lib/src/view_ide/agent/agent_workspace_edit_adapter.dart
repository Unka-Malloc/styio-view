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

    final editsByDocument = <String, List<FormattingEdit>>{};
    final fileOperations = <WorkspaceFileOperation>[];
    final editsByOperationDocument = <String, List<AgentCodePatchEdit>>{};
    for (final edit in patch.edits) {
      editsByOperationDocument
          .putIfAbsent(edit.documentId, () => <AgentCodePatchEdit>[])
          .add(edit);
    }

    for (final entry in editsByOperationDocument.entries) {
      final edits = entry.value;
      final fileOperationEdits = edits
          .where(
            (edit) => edit.operation != AgentCodePatchEditOperation.replace,
          )
          .toList(growable: false);
      if (fileOperationEdits.isNotEmpty && edits.length > 1) {
        return AgentWorkspaceEditPlanConversion(
          converted: false,
          skippedFileOperationCount: fileOperationEdits.length,
          message:
              'Agent patch ${patch.patchId} mixes file operation and text edits for ${entry.key}.',
        );
      }

      for (final edit in edits) {
        switch (edit.operation) {
          case AgentCodePatchEditOperation.replace:
            editsByDocument
                .putIfAbsent(edit.documentId, () => <FormattingEdit>[])
                .add(
                  FormattingEdit(
                    range: SourceRange(start: edit.start, end: edit.end),
                    newText: edit.replacementText,
                  ),
                );
            break;
          case AgentCodePatchEditOperation.create:
            fileOperations.add(
              WorkspaceFileOperation.create(
                documentId: edit.documentId,
                text: edit.replacementText,
              ),
            );
            break;
          case AgentCodePatchEditOperation.delete:
            fileOperations.add(
              WorkspaceFileOperation.delete(documentId: edit.documentId),
            );
            break;
        }
      }
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
        fileOperations: List<WorkspaceFileOperation>.unmodifiable(
          fileOperations,
        ),
      ),
    );
  }
}
