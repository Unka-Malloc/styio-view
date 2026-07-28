import '../../agent_client/agent.dart';
import '../../commands/commands.dart';
import '../../../ide/workspace/workspace.dart';
import 'agent_controller.dart';
import 'workspace_replace_controller.dart';

/// Owns the preview-before-apply contract for agent workspace replacement.
final class AgentWorkspaceReplaceCommandController {
  const AgentWorkspaceReplaceCommandController({
    required this.workspaceReplaceController,
    required this.agentController,
    required this.log,
  });

  final WorkspaceReplaceController workspaceReplaceController;
  final AgentController agentController;
  final void Function(String message) log;

  Future<bool> apply(AgentIdeCommandSuggestion suggestion) {
    return switch (suggestion.commandId) {
      'previewWorkspaceReplace' => _preview(suggestion),
      'applyWorkspaceReplace' => _applyPreview(suggestion),
      _ => throw ArgumentError.value(
        suggestion.commandId,
        'suggestion.commandId',
        'Unsupported workspace replace command.',
      ),
    };
  }

  Future<bool> _preview(AgentIdeCommandSuggestion suggestion) async {
    final input = _parseInput(suggestion.input);
    if (input == null) {
      const message =
          'Agent command previewWorkspaceReplace skipped: expected "search query -> replacement" input.';
      _record(
        suggestion,
        applied: false,
        message: message,
        metadata: _inputMetadata(),
      );
      log(message);
      return false;
    }
    final preview = await workspaceReplaceController.preview(
      query: input.query,
      replacement: input.replacement,
    );
    _record(
      suggestion,
      applied: preview != null,
      message: preview == null
          ? 'Agent command previewWorkspaceReplace skipped.'
          : 'Agent command previewWorkspaceReplace collected ${preview.replacementCount} replacement(s).',
      metadata: <String, Object?>{
        'query': input.query,
        'replacement': input.replacement,
        if (preview != null)
          'workspaceReplacePreview': _previewMetadata(preview),
      },
    );
    return preview != null;
  }

  Future<bool> _applyPreview(AgentIdeCommandSuggestion suggestion) async {
    final preview = workspaceReplaceController.lastPreview;
    if (preview == null) {
      const message =
          'Agent command applyWorkspaceReplace skipped: no workspace replace preview is available.';
      _record(
        suggestion,
        applied: false,
        message: message,
        metadata: const <String, Object?>{
          'requiredCommand': 'previewWorkspaceReplace',
        },
      );
      log(message);
      return false;
    }
    final result = await workspaceReplaceController.apply(preview);
    if (result == null) {
      _record(
        suggestion,
        applied: false,
        message:
            'Agent command applyWorkspaceReplace skipped: no preview changes.',
        metadata: <String, Object?>{
          'workspaceReplacePreview': _previewMetadata(preview),
        },
      );
      return false;
    }
    final applied = result.documents.isNotEmpty && result.failures.isEmpty;
    _record(
      suggestion,
      applied: applied,
      message:
          'Agent command applyWorkspaceReplace changed ${result.replacementCount} replacement(s).',
      metadata: <String, Object?>{
        'workspaceReplaceResult': _resultMetadata(result),
      },
    );
    return applied;
  }

  _WorkspaceReplaceInput? _parseInput(String? rawInput) {
    final input = rawInput?.trim() ?? '';
    final arrowIndex = input.indexOf('->');
    if (arrowIndex <= 0) {
      return null;
    }
    final query = input.substring(0, arrowIndex).trim();
    if (query.isEmpty) {
      return null;
    }
    return _WorkspaceReplaceInput(
      query: query,
      replacement: input.substring(arrowIndex + 2).trim(),
    );
  }

  Map<String, Object?> _inputMetadata() {
    final descriptor = StyioCommandRegistry.descriptorFor(
      AppCommandId.previewWorkspaceReplace,
    );
    return <String, Object?>{
      'reason': 'missing-input',
      'requiredInput': descriptor.inputLabel,
      'inputLabel': descriptor.inputLabel,
      'inputContract': descriptor.inputContract,
      'inputExamples': descriptor.inputExamples,
    };
  }

  Map<String, Object?> _previewMetadata(WorkspaceReplacePreview preview) =>
      <String, Object?>{
        'replacementCount': preview.replacementCount,
        'documentCount': preview.documents.length,
        'failureCount': preview.failures.length,
        'truncated': preview.truncated,
        'documents': preview.documents
            .map(
              (document) => <String, Object?>{
                'documentId': document.documentId,
                'replacementCount': document.replacementCount,
                'revision': document.revision,
              },
            )
            .toList(growable: false),
        if (preview.failures.isNotEmpty)
          'failures': preview.failures
              .map((failure) => failure.toJson())
              .toList(growable: false),
      };

  Map<String, Object?> _resultMetadata(WorkspaceReplaceResult result) =>
      <String, Object?>{
        'replacementCount': result.replacementCount,
        'documentCount': result.documents.length,
        'failureCount': result.failures.length,
        'truncated': result.truncated,
        'documents': result.documents
            .map(
              (document) => <String, Object?>{
                'documentId': document.documentId,
                'replacementCount': document.replacementCount,
                'revision': document.revision,
              },
            )
            .toList(growable: false),
        if (result.failures.isNotEmpty)
          'failures': result.failures
              .map((failure) => failure.toJson())
              .toList(growable: false),
      };

  void _record(
    AgentIdeCommandSuggestion suggestion, {
    required bool applied,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final effectiveMetadata = <String, Object?>{...metadata};
    final prerequisite = suggestion.prerequisiteForCommandId;
    if (prerequisite != null && prerequisite.isNotEmpty) {
      effectiveMetadata['completedRequiredCommandFor'] = prerequisite;
    }
    agentController.recordCommandResult(
      AgentCommandResultContext(
        commandId: suggestion.commandId,
        input: suggestion.input,
        applied: applied,
        message: message,
        metadata: effectiveMetadata,
        completedAt: DateTime.now().toUtc(),
      ),
    );
  }
}

final class _WorkspaceReplaceInput {
  const _WorkspaceReplaceInput({
    required this.query,
    required this.replacement,
  });

  final String query;
  final String replacement;
}
