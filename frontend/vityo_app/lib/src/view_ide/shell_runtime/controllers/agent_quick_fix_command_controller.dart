import '../../agent/agent.dart';
import '../../editor/editor.dart';
import '../../workspace/workspace.dart';
import 'agent_controller.dart';
import 'editor_workspace_state_controller.dart';
import 'semantic_telemetry_controller.dart';
import 'workspace_quick_fix_controller.dart';

/// Owns agent quick-fix discovery, review, and application routing.
final class AgentQuickFixCommandController {
  const AgentQuickFixCommandController({
    required this.editorController,
    required this.workspaceQuickFixController,
    required this.editorWorkspaceState,
    required this.semanticTelemetry,
    required this.agentController,
    required this.activeDocumentPath,
    required this.cacheDocument,
    required this.log,
    required this.notify,
  });

  final EditorSessionController editorController;
  final WorkspaceQuickFixController workspaceQuickFixController;
  final EditorWorkspaceStateController editorWorkspaceState;
  final SemanticTelemetryController semanticTelemetry;
  final AgentController agentController;
  final String Function() activeDocumentPath;
  final void Function(String documentId, DocumentState document) cacheDocument;
  final void Function(String message) log;
  final void Function() notify;

  Future<bool> apply(AgentIdeCommandSuggestion suggestion) =>
      suggestion.commandId == 'previewQuickFix'
      ? _preview(suggestion)
      : _apply(suggestion);

  Future<bool> _apply(AgentIdeCommandSuggestion suggestion) async {
    final input = suggestion.input?.trim();
    final selected = editorController.quickFixAtSelectionForInput(input);
    if (selected != null) {
      editorController.applyDiagnosticQuickFix(selected);
      final message = input == null || input.isEmpty
          ? 'Agent command applyQuickFix applied at editor selection.'
          : 'Agent command applyQuickFix applied matching "$input" at editor selection.';
      final metadata = <String, Object?>{
        'scope': 'selection',
        'selectionMode': input == null || input.isEmpty ? 'first' : 'input',
        if (input != null && input.isNotEmpty) 'input': input,
        'quickFixLabel': selected.label,
        'quickFixDetail': selected.detail,
        'quickFixEditCount': selected.edits.length,
      };
      final documentId = activeDocumentPath();
      cacheDocument(documentId, editorController.document);
      editorWorkspaceState.markDirty(documentId);
      log(message);
      _publish('agent.applyQuickFix', true, message, metadata);
      _record(suggestion, true, message, metadata);
      notify();
      return true;
    }
    if (input != null &&
        input.isNotEmpty &&
        editorController.contextActionsAtSelection.isNotEmpty) {
      const message =
          'Agent command applyQuickFix skipped: no editor quick fix matched input.';
      final metadata = <String, Object?>{
        'scope': 'selection',
        'selectionMode': 'input',
        'input': input,
        'reason': 'no-matching-quick-fix',
      };
      log('$message input="$input"');
      _publish('agent.applyQuickFix', false, message, metadata);
      _record(suggestion, false, message, metadata);
      notify();
      return false;
    }
    var preview = workspaceQuickFixController.lastPreview;
    if (preview == null) {
      preview = await workspaceQuickFixController.previewFirst();
      final message = preview == null
          ? 'Agent command applyQuickFix skipped: no quick fix available.'
          : 'Agent command applyQuickFix requires previewQuickFix before applying project workspace fix.';
      final metadata = <String, Object?>{
        'scope': 'workspace',
        if (preview != null) 'requiredCommand': 'previewQuickFix',
        if (preview != null) 'workspaceEditPreview': preview.toJson(),
      };
      log(message);
      _publish('agent.applyQuickFix', false, message, metadata);
      _record(suggestion, false, message, metadata);
      notify();
      return false;
    }
    final confirmation = WorkspaceEditConfirmationPlan.fromPreview(preview);
    if (!confirmation.ready) {
      final message =
          'Agent command applyQuickFix blocked by workspace edit preview: ${confirmation.message}';
      final metadata = <String, Object?>{
        'scope': 'workspace',
        'workspaceEditPreview': preview.toJson(),
        'workspaceEditConfirmation': confirmation.toJson(),
      };
      log(message);
      _publish('agent.applyQuickFix', false, message, metadata);
      _record(suggestion, false, message, metadata);
      notify();
      return false;
    }
    if (await workspaceQuickFixController.applyFirst(
      expectedPreviewPlanId: preview.planId,
    )) {
      const message =
          'Agent command applyQuickFix applied project workspace fix.';
      _publish('agent.applyQuickFix', true, message, const <String, Object?>{
        'scope': 'workspace',
      });
      _record(suggestion, true, message);
      return true;
    }
    final failed = workspaceQuickFixController.lastApplyResult;
    if (failed != null && !failed.successful) {
      final message = 'Agent command applyQuickFix skipped: ${failed.message}';
      final metadata = <String, Object?>{
        'scope': 'workspace',
        if (failed.message.contains('preview is stale'))
          'requiredCommand': 'previewQuickFix',
        if (workspaceQuickFixController.lastPreview != null)
          'workspaceEditPreview': workspaceQuickFixController.lastPreview!
              .toJson(),
        'workspaceEditApplyResult': failed.toJson(),
      };
      log(message);
      _publish('agent.applyQuickFix', false, message, metadata);
      _record(suggestion, false, message, metadata);
      notify();
      return false;
    }
    const message =
        'Agent command applyQuickFix skipped: no quick fix available.';
    log(message);
    _publish('agent.applyQuickFix', false, message, const <String, Object?>{
      'scope': 'selection',
    });
    _record(suggestion, false, message);
    notify();
    return false;
  }

  Future<bool> _preview(AgentIdeCommandSuggestion suggestion) async {
    final preview = await workspaceQuickFixController.previewFirst();
    final applied = preview?.canApply ?? false;
    final message = applied
        ? 'Agent command previewQuickFix collected workspace edit preview.'
        : 'Agent command previewQuickFix skipped: no quick fix available.';
    final metadata = <String, Object?>{
      if (preview != null) 'workspaceEditPreview': preview.toJson(),
    };
    _publish('agent.previewQuickFix', applied, message, metadata);
    _record(suggestion, applied, message, metadata);
    notify();
    return applied;
  }

  void _publish(
    String action,
    bool succeeded,
    String message,
    Map<String, Object?> metadata,
  ) => semanticTelemetry.publishDiagnosticAction(
    action: action,
    succeeded: succeeded,
    message: message,
    metadata: metadata,
  );

  void _record(
    AgentIdeCommandSuggestion suggestion,
    bool applied,
    String message, [
    Map<String, Object?> metadata = const <String, Object?>{},
  ]) {
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
