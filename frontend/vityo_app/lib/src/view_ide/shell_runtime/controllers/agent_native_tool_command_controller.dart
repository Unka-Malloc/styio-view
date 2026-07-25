import '../../agent/agent.dart';
import '../../commands/commands.dart';
import 'agent_controller.dart';
import 'execution_controller.dart';

/// Owns agent-facing native build, format, analysis, and test routing.
final class AgentNativeToolCommandController {
  const AgentNativeToolCommandController({
    required this.agentController,
    required this.runNativeToolCommand,
    required this.blockWhenDirty,
  });

  final AgentController agentController;
  final Future<NativeToolCommandResult> Function(NativeToolCommand command)
  runNativeToolCommand;
  final bool Function(AgentIdeCommandSuggestion suggestion) blockWhenDirty;

  Future<void> executeOrdinary(AppCommandId commandId) async {
    final suggestion = AgentIdeCommandSuggestion(commandId: commandId.name);
    final result = await runNativeToolCommand(_commandFor(commandId.name));
    _record(
      suggestion,
      applied: result.applied,
      message: result.message,
      metadata: result.metadata,
    );
  }

  Future<bool> apply(AgentIdeCommandSuggestion suggestion) async {
    final command = _commandFor(suggestion.commandId);
    if (command != NativeToolCommand.formatDocument &&
        blockWhenDirty(suggestion)) {
      return false;
    }
    final result = await runNativeToolCommand(command);
    _record(
      suggestion,
      applied: result.applied,
      message: result.message,
      metadata: result.metadata,
    );
    return result.applied;
  }

  NativeToolCommand _commandFor(String commandId) => switch (commandId) {
    'runBuild' => NativeToolCommand.build,
    'formatActiveDocument' => NativeToolCommand.formatDocument,
    'runStaticAnalysis' => NativeToolCommand.staticAnalysis,
    'runTests' => NativeToolCommand.tests,
    _ => throw ArgumentError.value(
      commandId,
      'commandId',
      'Unsupported native-tool command.',
    ),
  };

  void _record(
    AgentIdeCommandSuggestion suggestion, {
    required bool applied,
    required String message,
    required Map<String, Object?> metadata,
  }) {
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
