import '../../agent/agent.dart';
import '../../commands/commands.dart';
import 'agent_controller.dart';

/// Owns agent-facing settings recovery and IDE surface focus routing.
final class AgentSurfaceCommandController {
  const AgentSurfaceCommandController({
    required this.agentController,
    required this.executeCommand,
  });

  final AgentController agentController;
  final Future<void> Function(AppCommandId commandId) executeCommand;

  Future<bool> apply(AgentIdeCommandSuggestion suggestion) async {
    if (suggestion.commandId == 'openSettings') {
      await executeCommand(AppCommandId.openSettings);
      final section = _settingsSection(suggestion.prerequisiteForCommandId);
      _record(
        suggestion,
        message: 'Agent command openSettings requested settings route.',
        metadata: <String, Object?>{
          'settingsRoute': 'settings',
          if (section != null) 'settingsSection': section,
        },
      );
      return true;
    }
    final (commandId, surface) = switch (suggestion.commandId) {
      'showRuntime' => (AppCommandId.showRuntime, 'runtime'),
      'showAgent' => (AppCommandId.showAgent, 'agent'),
      'showDebug' => (AppCommandId.showDebug, 'debug'),
      _ => throw ArgumentError.value(
        suggestion.commandId,
        'suggestion.commandId',
        'Unsupported agent surface command.',
      ),
    };
    await executeCommand(commandId);
    _record(
      suggestion,
      message:
          'Agent command ${suggestion.commandId} focused the requested IDE surface.',
      metadata: <String, Object?>{
        'surfaceCommand': <String, Object?>{
          'commandId': suggestion.commandId,
          'targetSurface': surface,
        },
      },
    );
    return true;
  }

  void _record(
    AgentIdeCommandSuggestion suggestion, {
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
        applied: true,
        message: message,
        metadata: effectiveMetadata,
        completedAt: DateTime.now().toUtc(),
      ),
    );
  }
}

String? _settingsSection(String? prerequisite) => switch (prerequisite) {
  'selectClangCppVersion' ||
  'runBuild' ||
  'runStaticAnalysis' ||
  'runTests' ||
  'formatActiveDocument' => 'toolchain',
  _ => null,
};
