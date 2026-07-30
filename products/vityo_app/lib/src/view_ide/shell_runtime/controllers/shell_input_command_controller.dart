import '../../commands/commands.dart';
import 'workspace_file_command_controller.dart';

/// Owns routing for commands that may carry caller-provided text input.
final class ShellInputCommandController {
  const ShellInputCommandController({
    required this.workspaceFileCommands,
    required this.blockedReasonForCommand,
    required this.executeCommand,
    required this.searchWorkspace,
    required this.openWorkspaceFile,
    required this.log,
    required this.notify,
  });

  final WorkspaceFileCommandController workspaceFileCommands;
  final String? Function(AppCommandId commandId) blockedReasonForCommand;
  final Future<void> Function(AppCommandId commandId) executeCommand;
  final Future<bool> Function(String query) searchWorkspace;
  final Future<bool> Function(String filePath) openWorkspaceFile;
  final void Function(String message) log;
  final void Function() notify;

  Future<void> execute(AppCommandId commandId, String input) async {
    final normalizedInput = input.trim();
    final blockedReason = blockedReasonForCommand(commandId);
    if (blockedReason != null) {
      log(
        '${VityoCommandRegistry.descriptorFor(commandId).label} blocked: '
        '$blockedReason',
      );
      return;
    }
    switch (commandId) {
      case AppCommandId.openWorkspaceFile:
        await openWorkspaceFile(normalizedInput);
        return;
      case AppCommandId.searchWorkspace:
        await searchWorkspace(normalizedInput);
        return;
      case AppCommandId.createWorkspaceFile:
      case AppCommandId.renameWorkspaceFile:
      case AppCommandId.deleteWorkspaceFile:
      case AppCommandId.revealWorkspaceFile:
        await _workspaceFile(commandId, normalizedInput);
        return;
      case AppCommandId.failoverAgentProvider:
      case AppCommandId.retryAgentProvider:
      case AppCommandId.replayAgentPrompt:
      case AppCommandId.collectAgentCodingCheckpoint:
        log(
          '${VityoCommandRegistry.descriptorFor(commandId).label} is unavailable: '
          'Vityo no longer owns model/provider or coding-loop control surfaces.',
        );
        return;
      default:
        await executeCommand(commandId);
        return;
    }
  }

  Future<void> _workspaceFile(AppCommandId commandId, String input) async {
    final result = await workspaceFileCommands.execute(
      commandId: commandId,
      input: input,
    );
    log(result.message);
    notify();
  }
}
