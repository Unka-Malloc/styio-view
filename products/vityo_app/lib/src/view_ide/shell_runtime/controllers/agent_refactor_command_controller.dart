import '../../agent_client/agent.dart';
import '../../commands/commands.dart';
import '../../../ide/editor/editor.dart';
import 'agent_controller.dart';
import 'editor_workspace_state_controller.dart';

/// Owns agent-facing editor refactors that mutate the authoritative buffer.
final class AgentRefactorCommandController {
  const AgentRefactorCommandController({
    required this.editorController,
    required this.editorWorkspaceState,
    required this.agentController,
    required this.activeDocumentPath,
    required this.cacheDocument,
    required this.log,
    required this.notify,
  });

  final EditorSessionController editorController;
  final EditorWorkspaceStateController editorWorkspaceState;
  final AgentController agentController;
  final String Function() activeDocumentPath;
  final void Function(String documentId, DocumentState document) cacheDocument;
  final void Function(String message) log;
  final void Function() notify;

  bool apply(AgentIdeCommandSuggestion suggestion) {
    final applied = switch (suggestion.commandId) {
      'safeDelete' => editorController.applySafeDeleteAtSelection(),
      'inlineVariable' => editorController.applyInlineVariableAtSelection(),
      _ => throw ArgumentError.value(
        suggestion.commandId,
        'suggestion.commandId',
        'Unsupported agent refactor command.',
      ),
    };
    final label = suggestion.commandId;
    final unavailable = label == 'safeDelete'
        ? 'no safe delete available'
        : 'no inline variable available';
    final message = applied
        ? 'Agent command $label applied at editor selection.'
        : 'Agent command $label skipped: $unavailable.';
    if (applied) {
      final documentId = activeDocumentPath();
      cacheDocument(documentId, editorController.document);
      editorWorkspaceState.markDirty(documentId);
    }
    log(message);
    _record(suggestion, applied: applied, message: message);
    notify();
    return applied;
  }

  bool executeEditorCommand(AppCommandId commandId) {
    final applied = switch (commandId) {
      AppCommandId.safeDelete => editorController.applySafeDeleteAtSelection(),
      AppCommandId.inlineVariable =>
        editorController.applyInlineVariableAtSelection(),
      _ => throw ArgumentError.value(
        commandId,
        'commandId',
        'Unsupported editor refactor command.',
      ),
    };
    final label = commandId == AppCommandId.safeDelete
        ? 'Safe delete'
        : 'Inline variable';
    final unavailable = commandId == AppCommandId.safeDelete
        ? 'no safe delete available'
        : 'no inline variable available';
    if (applied) {
      final documentId = activeDocumentPath();
      cacheDocument(documentId, editorController.document);
      editorWorkspaceState.markDirty(documentId);
      log('$label applied at editor selection.');
    } else {
      log('$label skipped: $unavailable at selection.');
    }
    notify();
    return applied;
  }

  void _record(
    AgentIdeCommandSuggestion suggestion, {
    required bool applied,
    required String message,
  }) {
    final metadata = <String, Object?>{};
    final prerequisite = suggestion.prerequisiteForCommandId;
    if (prerequisite != null && prerequisite.isNotEmpty) {
      metadata['completedRequiredCommandFor'] = prerequisite;
    }
    agentController.recordCommandResult(
      AgentCommandResultContext(
        commandId: suggestion.commandId,
        input: suggestion.input,
        applied: applied,
        message: message,
        metadata: metadata,
        completedAt: DateTime.now().toUtc(),
      ),
    );
  }
}
