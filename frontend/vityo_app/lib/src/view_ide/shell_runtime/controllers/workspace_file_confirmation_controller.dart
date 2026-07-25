import '../../agent/agent.dart';
import '../../workspace/workspace.dart';
import 'agent_controller.dart';
import 'workspace_file_command_controller.dart';

/// Owns confirmation and cancellation receipts for staged workspace file commands.
final class WorkspaceFileConfirmationController {
  const WorkspaceFileConfirmationController({
    required this.fileCommands,
    required this.agentController,
    required this.log,
    required this.notify,
  });

  final WorkspaceFileCommandController fileCommands;
  final AgentController agentController;
  final void Function(String message) log;
  final void Function() notify;

  Future<WorkspaceFileCommandRouteResult?> confirm() async {
    final result = await fileCommands.confirm();
    final operationResult = result?.operationResult;
    if (result == null || operationResult == null) {
      return null;
    }
    _record(
      result,
      applied: operationResult.applied,
      metadata: <String, Object?>{
        ...result.toJson(),
        'confirmationAccepted': true,
      },
    );
    return result;
  }

  WorkspaceFileCommandRouteResult? cancel() {
    final result = fileCommands.cancel();
    if (result == null) {
      return null;
    }
    _record(
      result,
      applied: false,
      metadata: <String, Object?>{
        ...result.toJson(),
        'confirmationAccepted': false,
      },
    );
    return result;
  }

  void _record(
    WorkspaceFileCommandRouteResult result, {
    required bool applied,
    required Map<String, Object?> metadata,
  }) {
    agentController.recordCommandResult(
      AgentCommandResultContext(
        commandId: result.commandId.name,
        input: result.input,
        applied: applied,
        message: result.message,
        metadata: metadata,
        completedAt: DateTime.now().toUtc(),
      ),
    );
    log(result.message);
    notify();
  }
}
