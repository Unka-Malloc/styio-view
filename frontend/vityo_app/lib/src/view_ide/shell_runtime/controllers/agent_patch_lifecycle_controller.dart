import '../../agent/agent.dart';
import '../../editor/editor.dart';
import '../../workspace/workspace.dart';
import 'editor_workspace_state_controller.dart';

/// Owns Agent workspace patch application and authoritative cache reconciliation.
final class AgentPatchLifecycleController {
  const AgentPatchLifecycleController({
    required this.sessionController,
    required this.editorController,
    required this.workspaceDocumentStore,
    required this.workspaceController,
    required this.editorWorkspaceState,
    required this.dirtyDocumentIds,
    required this.sampledDocumentIds,
    required this.activeDocumentPath,
    required this.log,
  });

  final AgentCodingSessionController sessionController;
  final EditorSessionController editorController;
  final WorkspaceDocumentStore workspaceDocumentStore;
  final WorkspaceController workspaceController;
  final EditorWorkspaceStateController editorWorkspaceState;
  final List<String> Function() dirtyDocumentIds;
  final Iterable<String> Function() sampledDocumentIds;
  final String Function() activeDocumentPath;
  final void Function(String message) log;

  Future<AgentCodePatchApplicationResult?> applyPending() async {
    final result = await sessionController.applyPendingWorkspacePatch(
      _applier(),
    );
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

  AgentWorkspaceCodePatchApplier _applier() => AgentWorkspaceCodePatchApplier(
    editorController: editorController,
    workspaceDocumentStore: workspaceDocumentStore,
    dirtyDocumentIds: dirtyDocumentIds(),
    sampledDocumentIds: sampledDocumentIds(),
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
