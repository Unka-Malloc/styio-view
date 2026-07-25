import '../../agent/agent.dart';
import '../../commands/commands.dart';
import 'agent_controller.dart';
import 'workspace_file_command_controller.dart';

/// Owns routing for commands that may carry caller-provided text input.
final class ShellInputCommandController {
  const ShellInputCommandController({
    required this.agentController,
    required this.workspaceFileCommands,
    required this.blockedReasonForCommand,
    required this.applyAgentSuggestion,
    required this.failoverAgentProviderProfile,
    required this.executeCommand,
    required this.log,
    required this.notify,
  });

  final AgentController agentController;
  final WorkspaceFileCommandController workspaceFileCommands;
  final String? Function(AppCommandId commandId) blockedReasonForCommand;
  final Future<bool> Function(AgentIdeCommandSuggestion suggestion)
  applyAgentSuggestion;
  final Future<AgentProviderConfigurationResult?> Function(String profileKey)
  failoverAgentProviderProfile;
  final Future<void> Function(AppCommandId commandId) executeCommand;
  final void Function(String message) log;
  final void Function() notify;

  Future<void> execute(AppCommandId commandId, String input) async {
    final normalizedInput = input.trim();
    final blockedReason = blockedReasonForCommand(commandId);
    if (blockedReason != null) {
      log(
        '${StyioCommandRegistry.descriptorFor(commandId).label} blocked: '
        '$blockedReason',
      );
      return;
    }
    switch (commandId) {
      case AppCommandId.openWorkspaceFile:
      case AppCommandId.searchWorkspace:
      case AppCommandId.previewWorkspaceReplace:
      case AppCommandId.renameSymbol:
      case AppCommandId.previewSourceControlDiff:
      case AppCommandId.stageSourceControl:
      case AppCommandId.unstageSourceControl:
      case AppCommandId.planSourceControlBranchSwitch:
      case AppCommandId.planSourceControlCommitDraft:
      case AppCommandId.selectClangCppVersion:
      case AppCommandId.runTestConfiguration:
      case AppCommandId.debugTestConfiguration:
        await applyAgentSuggestion(
          AgentIdeCommandSuggestion(
            commandId: commandId.name,
            input: normalizedInput,
          ),
        );
        return;
      case AppCommandId.failoverAgentProvider:
        await _failover(normalizedInput);
        return;
      case AppCommandId.createWorkspaceFile:
      case AppCommandId.renameWorkspaceFile:
      case AppCommandId.deleteWorkspaceFile:
      case AppCommandId.revealWorkspaceFile:
        await _workspaceFile(commandId, input, normalizedInput);
        return;
      default:
        await executeCommand(commandId);
        return;
    }
  }

  Future<void> _failover(String profileKey) async {
    final suggestion = AgentIdeCommandSuggestion(
      commandId: AppCommandId.failoverAgentProvider.name,
      input: profileKey,
    );
    final result = await failoverAgentProviderProfile(profileKey);
    _record(
      suggestion,
      applied: result?.mounted ?? false,
      message:
          result?.message ??
          'Agent provider failover unavailable: no configurator is wired.',
      metadata: <String, Object?>{
        'targetProviderProfileId': result?.profile.profileId,
        'targetProviderProfileKey': profileKey,
        'adapterKind': result?.adapterKind.wireValue,
        'adapterId': result?.adapterId,
        'retryEnabled': result?.retryEnabled,
      },
    );
  }

  Future<void> _workspaceFile(
    AppCommandId commandId,
    String originalInput,
    String normalizedInput,
  ) async {
    final result = await workspaceFileCommands.execute(
      commandId: commandId,
      input: normalizedInput,
    );
    final operationResult = result.operationResult;
    _record(
      AgentIdeCommandSuggestion(
        commandId: commandId.name,
        input: originalInput,
      ),
      applied: operationResult?.applied ?? false,
      message: result.message,
      metadata: result.toJson(),
    );
    log(result.message);
    notify();
  }

  void _record(
    AgentIdeCommandSuggestion suggestion, {
    required bool applied,
    required String message,
    required Map<String, Object?> metadata,
  }) {
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
