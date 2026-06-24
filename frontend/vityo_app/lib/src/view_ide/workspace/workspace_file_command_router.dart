import '../commands/commands.dart';
import 'workspace_file_explorer_controller.dart';
import 'workspace_file_operations.dart';

enum WorkspaceFileCommandRouteStatus { routed, unsupported, blocked }

class WorkspaceFileCommandRouteContext {
  const WorkspaceFileCommandRouteContext({
    this.activeFilePath = '',
    this.selectedFilePath = '',
    this.defaultText = '',
    this.openCreatedFiles = true,
  });

  final String activeFilePath;
  final String selectedFilePath;
  final String defaultText;
  final bool openCreatedFiles;

  String get fallbackPath {
    final selected = selectedFilePath.trim();
    if (selected.isNotEmpty) {
      return selected;
    }
    return activeFilePath.trim();
  }
}

class WorkspaceFileCommandRouteResult {
  const WorkspaceFileCommandRouteResult({
    required this.commandId,
    required this.status,
    required this.message,
    this.input = '',
    this.request,
    this.confirmationPlan,
    this.operationResult,
  });

  final AppCommandId commandId;
  final WorkspaceFileCommandRouteStatus status;
  final String message;
  final String input;
  final WorkspaceFileExplorerActionRequest? request;
  final WorkspaceFileExplorerConfirmationPlan? confirmationPlan;
  final WorkspaceFileOperationResult? operationResult;

  bool get routed => status == WorkspaceFileCommandRouteStatus.routed;
  bool get applied => operationResult?.applied ?? false;
  bool get staged => confirmationPlan != null && operationResult == null;

  WorkspaceFileCommandRouteResult withConfirmationPlan(
    WorkspaceFileExplorerConfirmationPlan plan,
  ) {
    return WorkspaceFileCommandRouteResult(
      commandId: commandId,
      status: status,
      message: message,
      input: input,
      request: request,
      confirmationPlan: plan,
      operationResult: operationResult,
    );
  }

  WorkspaceFileCommandRouteResult withOperationResult(
    WorkspaceFileOperationResult result,
  ) {
    return WorkspaceFileCommandRouteResult(
      commandId: commandId,
      status: status,
      message: result.message,
      input: input,
      request: request,
      confirmationPlan: confirmationPlan,
      operationResult: result,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'commandId': commandId.name,
      'status': status.name,
      'routed': routed,
      'applied': applied,
      'staged': staged,
      'message': message,
      if (input.trim().isNotEmpty) 'input': input.trim(),
      if (request != null) 'request': request!.toJson(),
      if (confirmationPlan != null)
        'confirmationPlan': confirmationPlan!.toJson(),
      if (operationResult != null) 'operationResult': operationResult!.toJson(),
    };
  }
}

class WorkspaceFileCommandRouter {
  const WorkspaceFileCommandRouter();

  static const Set<AppCommandId> supportedCommandIds = <AppCommandId>{
    AppCommandId.openWorkspaceFile,
    AppCommandId.createWorkspaceFile,
    AppCommandId.renameWorkspaceFile,
    AppCommandId.deleteWorkspaceFile,
    AppCommandId.revealWorkspaceFile,
  };

  bool supports(AppCommandId commandId) {
    return supportedCommandIds.contains(commandId);
  }

  WorkspaceFileCommandRouteResult route({
    required AppCommandId commandId,
    String input = '',
    WorkspaceFileCommandRouteContext context =
        const WorkspaceFileCommandRouteContext(),
  }) {
    if (!supports(commandId)) {
      return WorkspaceFileCommandRouteResult(
        commandId: commandId,
        status: WorkspaceFileCommandRouteStatus.unsupported,
        input: input,
        message: 'Command is not a workspace file command.',
      );
    }
    final request = _requestFor(commandId, input.trim(), context);
    if (request == null) {
      return WorkspaceFileCommandRouteResult(
        commandId: commandId,
        status: WorkspaceFileCommandRouteStatus.blocked,
        input: input,
        message: _blockedMessageFor(commandId),
      );
    }
    final plan = WorkspaceFileExplorerConfirmationPlan.fromRequest(request);
    return WorkspaceFileCommandRouteResult(
      commandId: commandId,
      status: WorkspaceFileCommandRouteStatus.routed,
      input: input,
      request: request,
      confirmationPlan: plan,
      message: plan.canRunWithoutDialog
          ? 'Workspace file command can run without confirmation.'
          : 'Workspace file command staged for confirmation.',
    );
  }

  WorkspaceFileExplorerActionRequest? _requestFor(
    AppCommandId commandId,
    String input,
    WorkspaceFileCommandRouteContext context,
  ) {
    return switch (commandId) {
      AppCommandId.openWorkspaceFile ||
      AppCommandId.revealWorkspaceFile => _pathRequest(
        kind: WorkspaceFileOperationKind.reveal,
        input: input,
        fallbackPath: context.fallbackPath,
      ),
      AppCommandId.createWorkspaceFile =>
        input.isEmpty
            ? null
            : WorkspaceFileExplorerActionRequest(
                kind: WorkspaceFileOperationKind.create,
                path: input,
                text: context.defaultText,
                open: context.openCreatedFiles,
              ),
      AppCommandId.renameWorkspaceFile => _renameRequest(input, context),
      AppCommandId.deleteWorkspaceFile => _pathRequest(
        kind: WorkspaceFileOperationKind.delete,
        input: input,
        fallbackPath: context.fallbackPath,
      ),
      _ => null,
    };
  }

  WorkspaceFileExplorerActionRequest? _pathRequest({
    required WorkspaceFileOperationKind kind,
    required String input,
    required String fallbackPath,
  }) {
    final path = input.isEmpty ? fallbackPath.trim() : input;
    if (path.isEmpty) {
      return null;
    }
    return WorkspaceFileExplorerActionRequest(kind: kind, path: path);
  }

  WorkspaceFileExplorerActionRequest? _renameRequest(
    String input,
    WorkspaceFileCommandRouteContext context,
  ) {
    final parsed = _parseRenameInput(input);
    final path = parsed.path.isEmpty ? context.fallbackPath : parsed.path;
    if (path.trim().isEmpty || parsed.nextPath.trim().isEmpty) {
      return null;
    }
    return WorkspaceFileExplorerActionRequest(
      kind: WorkspaceFileOperationKind.rename,
      path: path.trim(),
      nextPath: parsed.nextPath.trim(),
      open: true,
    );
  }

  _WorkspaceFileRenameInput _parseRenameInput(String input) {
    final arrowIndex = input.indexOf('->');
    if (arrowIndex >= 0) {
      return _WorkspaceFileRenameInput(
        path: input.substring(0, arrowIndex).trim(),
        nextPath: input.substring(arrowIndex + 2).trim(),
      );
    }
    return _WorkspaceFileRenameInput(path: '', nextPath: input.trim());
  }

  String _blockedMessageFor(AppCommandId commandId) {
    return switch (commandId) {
      AppCommandId.openWorkspaceFile || AppCommandId.revealWorkspaceFile =>
        'Workspace file command needs a path.',
      AppCommandId.createWorkspaceFile =>
        'Create workspace file command needs a new path.',
      AppCommandId.renameWorkspaceFile =>
        'Rename workspace file command needs a source and target path.',
      AppCommandId.deleteWorkspaceFile =>
        'Delete workspace file command needs a path.',
      _ => 'Command is not a workspace file command.',
    };
  }
}

class WorkspaceFileCommandPaletteAdapter {
  const WorkspaceFileCommandPaletteAdapter({
    required this.controller,
    this.router = const WorkspaceFileCommandRouter(),
  });

  final WorkspaceFileExplorerController controller;
  final WorkspaceFileCommandRouter router;

  Future<WorkspaceFileCommandRouteResult> execute({
    required AppCommandId commandId,
    String input = '',
    WorkspaceFileCommandRouteContext context =
        const WorkspaceFileCommandRouteContext(),
  }) async {
    final routed = router.route(
      commandId: commandId,
      input: input,
      context: context,
    );
    final request = routed.request;
    if (request == null) {
      return routed;
    }
    final plan = controller.stageAction(request);
    final staged = routed.withConfirmationPlan(plan);
    if (!plan.canRunWithoutDialog) {
      return staged;
    }
    final operationResult = await controller.runPendingAction(confirmed: true);
    if (operationResult == null) {
      return staged;
    }
    return staged.withOperationResult(operationResult);
  }
}

class _WorkspaceFileRenameInput {
  const _WorkspaceFileRenameInput({required this.path, required this.nextPath});

  final String path;
  final String nextPath;
}
