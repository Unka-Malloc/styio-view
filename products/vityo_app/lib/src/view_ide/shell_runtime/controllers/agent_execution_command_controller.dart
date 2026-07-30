import '../../agent_client/agent.dart';
import '../../backend_toolchain/backend_toolchain.dart';
import '../../commands/commands.dart';
import 'agent_controller.dart';

/// Owns agent-facing execution dispatch and typed runtime receipt projection.
final class AgentExecutionCommandController {
  const AgentExecutionCommandController({
    required this.agentController,
    required this.executeCommand,
    required this.executionSession,
    required this.runtimeEvents,
    required this.blockWhenDirty,
  });

  final AgentController agentController;
  final Future<void> Function(AppCommandId commandId) executeCommand;
  final ExecutionSession? Function() executionSession;
  final List<RuntimeEventEnvelope> Function() runtimeEvents;
  final bool Function(AgentIdeCommandSuggestion suggestion) blockWhenDirty;

  Future<bool> apply(AgentIdeCommandSuggestion suggestion) async {
    if (suggestion.commandId != 'run') {
      throw ArgumentError.value(
        suggestion.commandId,
        'suggestion.commandId',
        'Unsupported agent execution command.',
      );
    }
    if (blockWhenDirty(suggestion)) {
      return false;
    }
    await executeCommand(AppCommandId.run);
    final session = executionSession();
    final events = runtimeEvents();
    final applied =
        session != null && session.status != ExecutionSessionStatus.blocked;
    final metadata = <String, Object?>{
      if (session != null) 'executionSession': session.toJson(),
      'runtimeEventCount': events.length,
      if (events.isNotEmpty)
        'runtimeEventKinds': events
            .take(4)
            .map((event) => event.eventKind)
            .toList(growable: false),
    };
    final message = session == null
        ? 'Agent command run skipped: no execution session was produced.'
        : 'Agent command run ${session.status.name}: ${session.statusMessage}';
    final prerequisite = suggestion.prerequisiteForCommandId;
    if (prerequisite != null && prerequisite.isNotEmpty) {
      metadata['completedRequiredCommandFor'] = prerequisite;
    }
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
    return applied;
  }
}
