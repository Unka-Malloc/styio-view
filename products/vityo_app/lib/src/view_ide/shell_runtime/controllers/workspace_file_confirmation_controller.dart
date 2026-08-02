import '../../../ide/workspace/workspace.dart';
import 'workspace_file_command_controller.dart';

/// Owns confirmation and cancellation for staged workspace file commands.
final class WorkspaceFileConfirmationController {
  const WorkspaceFileConfirmationController({
    required this.fileCommands,
    required this.log,
    required this.notify,
  });

  final WorkspaceFileCommandController fileCommands;
  final void Function(String message) log;
  final void Function() notify;

  Future<WorkspaceFileCommandRouteResult?> confirm() async {
    final result = await fileCommands.confirm();
    final operationResult = result?.operationResult;
    if (result == null || operationResult == null) {
      return null;
    }
    log(result.message);
    notify();
    return result;
  }

  WorkspaceFileCommandRouteResult? cancel() {
    final result = fileCommands.cancel();
    if (result == null) {
      return null;
    }
    log(result.message);
    notify();
    return result;
  }
}
