import '../../agent_client/agent.dart';
import '../../commands/commands.dart';
import 'agent_controller.dart';

/// Owns agent context checkpoint collection and module-fact refresh routing.
final class AgentContextCommandController {
  const AgentContextCommandController({
    required this.agentController,
    required this.collectCodingCheckpoint,
    required this.collectProjectLanguageContext,
    required this.executeCommand,
    required this.collectModuleRefreshMetadata,
  });

  final AgentController agentController;
  final Future<Map<String, Object?>> Function() collectCodingCheckpoint;
  final Future<Map<String, Object?>> Function() collectProjectLanguageContext;
  final Future<void> Function(AppCommandId commandId) executeCommand;
  final Future<Map<String, Object?>> Function() collectModuleRefreshMetadata;

  Future<void> executeOrdinary(AppCommandId commandId) async {
    final suggestion = AgentIdeCommandSuggestion(commandId: commandId.name);
    switch (commandId) {
      case AppCommandId.collectAgentCodingCheckpoint:
        _record(
          suggestion,
          message: 'Agent coding checkpoint collected.',
          metadata: await collectCodingCheckpoint(),
        );
        return;
      case AppCommandId.collectProjectLanguageContext:
        _record(
          suggestion,
          message: 'Project language context collected.',
          metadata: <String, Object?>{
            'projectLanguage': await collectProjectLanguageContext(),
          },
        );
        return;
      default:
        throw ArgumentError.value(
          commandId,
          'commandId',
          'Unsupported ordinary context command.',
        );
    }
  }

  Future<bool> apply(AgentIdeCommandSuggestion suggestion) async {
    return switch (suggestion.commandId) {
      'collectAgentCodingCheckpoint' => _codingCheckpoint(suggestion),
      'collectProjectLanguageContext' => _projectLanguage(suggestion),
      'refreshModules' => _refreshModules(suggestion),
      _ => throw ArgumentError.value(
        suggestion.commandId,
        'suggestion.commandId',
        'Unsupported agent context command.',
      ),
    };
  }

  Future<bool> _codingCheckpoint(AgentIdeCommandSuggestion suggestion) async {
    final metadata = await collectCodingCheckpoint();
    _record(
      suggestion,
      message: 'Agent command collectAgentCodingCheckpoint completed.',
      metadata: metadata,
    );
    return true;
  }

  Future<bool> _projectLanguage(AgentIdeCommandSuggestion suggestion) async {
    final metadata = await collectProjectLanguageContext();
    _record(
      suggestion,
      message: 'Agent command collectProjectLanguageContext completed.',
      metadata: <String, Object?>{'projectLanguage': metadata},
    );
    return true;
  }

  Future<bool> _refreshModules(AgentIdeCommandSuggestion suggestion) async {
    await executeCommand(AppCommandId.refreshModules);
    final metadata = await collectModuleRefreshMetadata();
    _record(
      suggestion,
      message: 'Agent command refreshModules refreshed module host facts.',
      metadata: <String, Object?>{'moduleHostRefresh': metadata},
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
