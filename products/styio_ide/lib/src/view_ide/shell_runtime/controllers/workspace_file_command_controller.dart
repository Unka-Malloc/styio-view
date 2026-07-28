import '../../commands/commands.dart';
import '../../../ide/workspace/workspace.dart';

/// Owns workspace-file command routing, destructive confirmation, and I/O.
final class WorkspaceFileCommandController {
  WorkspaceFileCommandController({
    required this.workspaceController,
    required this.documentStore,
    required this.openWorkspaceFile,
    required this.reloadActiveDocument,
  });

  final WorkspaceController workspaceController;
  final WorkspaceDocumentStore documentStore;
  final Future<bool> Function(String filePath) openWorkspaceFile;
  final Future<void> Function() reloadActiveDocument;

  WorkspaceFileCommandRouteResult? _pendingConfirmation;

  WorkspaceFileCommandRouteResult? get pendingConfirmation =>
      _pendingConfirmation;

  Future<WorkspaceFileCommandRouteResult> execute({
    required AppCommandId commandId,
    required String input,
  }) async {
    final routed = const WorkspaceFileCommandRouter().route(
      commandId: commandId,
      input: input,
      context: WorkspaceFileCommandRouteContext(
        activeFilePath: workspaceController.activeFilePath,
        selectedFilePath: workspaceController.activeFilePath,
        openCreatedFiles: true,
      ),
    );
    final request = routed.request;
    if (request == null) {
      return routed;
    }
    if (routed.confirmationPlan?.destructive ?? false) {
      final staged = WorkspaceFileCommandRouteResult(
        commandId: commandId,
        status: WorkspaceFileCommandRouteStatus.routed,
        input: input,
        request: request,
        confirmationPlan: routed.confirmationPlan,
        message:
            '${routed.confirmationPlan!.title} staged for confirmation. Use the workspace file confirmation controls to apply or cancel it.',
      );
      _pendingConfirmation = staged;
      return staged;
    }
    final operationResult = await _run(request);
    return routed.withOperationResult(operationResult);
  }

  Future<WorkspaceFileCommandRouteResult?> confirm() async {
    final pending = _pendingConfirmation;
    final request = pending?.request;
    if (pending == null || request == null) {
      return null;
    }
    _pendingConfirmation = null;
    return pending.withOperationResult(await _run(request));
  }

  WorkspaceFileCommandRouteResult? cancel() {
    final pending = _pendingConfirmation;
    if (pending == null) {
      return null;
    }
    _pendingConfirmation = null;
    return WorkspaceFileCommandRouteResult(
      commandId: pending.commandId,
      status: WorkspaceFileCommandRouteStatus.blocked,
      input: pending.input,
      request: pending.request,
      confirmationPlan: pending.confirmationPlan,
      message:
          '${pending.confirmationPlan?.title ?? 'Workspace file command'} cancelled.',
    );
  }

  Future<WorkspaceFileOperationResult> _run(
    WorkspaceFileExplorerActionRequest request,
  ) async {
    if (request.kind == WorkspaceFileOperationKind.reveal) {
      final opened = await openWorkspaceFile(request.path);
      return WorkspaceFileOperationResult(
        kind: WorkspaceFileOperationKind.reveal,
        applied: opened,
        path: request.path,
        message: opened
            ? 'Workspace file revealed.'
            : 'Workspace file reveal failed.',
      );
    }
    final service = WorkspaceFileOperationService(
      workspaceController: workspaceController,
      documentStore: documentStore,
    );
    final result = switch (request.kind) {
      WorkspaceFileOperationKind.create => await service.createFile(
        path: request.path,
        text: request.text,
        open: request.open,
      ),
      WorkspaceFileOperationKind.rename => await service.renameFile(
        path: request.path,
        nextPath: request.nextPath,
        open: request.open,
      ),
      WorkspaceFileOperationKind.delete => await service.deleteFile(
        request.path,
      ),
      WorkspaceFileOperationKind.reveal => service.revealFile(request.path),
    };
    if (result.applied &&
        (workspaceController.activeFilePath == result.nextPath ||
            workspaceController.activeFilePath == result.path)) {
      await reloadActiveDocument();
    }
    return result;
  }
}
