import '../../agent_client/agent.dart';
import '../../../ide/workspace/workspace.dart';
import 'editor_workspace_state_controller.dart';

/// Owns Agent workspace patch application and authoritative cache reconciliation.
final class AgentPatchLifecycleController {
  const AgentPatchLifecycleController({
    required this.sessionController,
    required this.transactionService,
    required this.revisionService,
    required this.workspaceController,
    required this.editorWorkspaceState,
    required this.activeDocumentPath,
    required this.log,
  });

  final AgentCodingSessionController sessionController;
  final WorkspaceTransactionService transactionService;
  final InMemoryWorkspaceRevisionService revisionService;
  final WorkspaceController workspaceController;
  final EditorWorkspaceStateController editorWorkspaceState;
  final String Function() activeDocumentPath;
  final void Function(String message) log;

  Future<AgentCodePatchApplicationResult?> applyPending() async {
    final result = await sessionController.applyPendingPatch(_applier());
    _reconcile(result);
    log(result?.message ?? 'No pending agent patch is available.');
    return result;
  }

  Future<AgentCodePatchApplicationResult> apply(AgentCodePatch patch) async {
    final result = await _applier().apply(patch);
    _reconcile(result);
    log(result.message);
    return result;
  }

  AgentCodePatchApplier _applier() => AgentCodePatchApplier(
    transactionService: transactionService,
    revisionService: revisionService,
  );

  void _reconcile(AgentCodePatchApplicationResult? result) {
    if (result == null || !result.applied) {
      return;
    }
    for (final documentId in result.createdDocumentIds) {
      workspaceController.registerFile(documentId);
    }
    for (final documentId in result.deletedDocumentIds) {
      if (documentId == activeDocumentPath()) {
        continue;
      }
      workspaceController.unregisterFile(documentId);
      editorWorkspaceState.clearDirty(documentId);
    }
    for (final documentId in result.appliedDocumentIds) {
      if (documentId != activeDocumentPath()) {
        editorWorkspaceState.removeDocument(documentId);
      }
    }
  }
}
