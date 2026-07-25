import '../../agent/agent.dart';
import '../../backend_toolchain/backend_toolchain.dart';
import 'agent_controller.dart';

/// Owns agent-facing dependency and deployment lifecycle routing.
final class AgentProjectLifecycleCommandController {
  const AgentProjectLifecycleCommandController({
    required this.agentController,
    required this.fetchDependencies,
    required this.vendorDependencies,
    required this.packProject,
    required this.preparePublish,
    required this.blockWhenDirty,
  });

  final AgentController agentController;
  final Future<DependencySourceCommandResult> Function() fetchDependencies;
  final Future<DependencySourceCommandResult> Function() vendorDependencies;
  final Future<DeploymentCommandResult> Function() packProject;
  final Future<DeploymentCommandResult> Function() preparePublish;
  final bool Function(AgentIdeCommandSuggestion suggestion) blockWhenDirty;

  Future<bool> apply(AgentIdeCommandSuggestion suggestion) async {
    if (blockWhenDirty(suggestion)) {
      return false;
    }
    return switch (suggestion.commandId) {
      'fetchDependencies' => _dependency(suggestion, fetchDependencies),
      'vendorDependencies' => _dependency(suggestion, vendorDependencies),
      'packProject' => _deployment(suggestion, packProject),
      'preparePublish' => _deployment(suggestion, preparePublish),
      _ => throw ArgumentError.value(
        suggestion.commandId,
        'suggestion.commandId',
        'Unsupported agent project lifecycle command.',
      ),
    };
  }

  Future<bool> _dependency(
    AgentIdeCommandSuggestion suggestion,
    Future<DependencySourceCommandResult> Function() action,
  ) async {
    final result = await action();
    _record(
      suggestion,
      applied: result.succeeded,
      message:
          'Agent command ${suggestion.commandId} ${result.status.name}: ${result.statusMessage}',
      metadata: <String, Object?>{
        'dependencySourceCommand': _dependencyMetadata(result),
      },
    );
    return result.succeeded;
  }

  Future<bool> _deployment(
    AgentIdeCommandSuggestion suggestion,
    Future<DeploymentCommandResult> Function() action,
  ) async {
    final result = await action();
    _record(
      suggestion,
      applied: result.succeeded,
      message:
          'Agent command ${suggestion.commandId} ${result.status.name}: ${result.statusMessage}',
      metadata: <String, Object?>{
        'deploymentCommand': _deploymentMetadata(result),
      },
    );
    return result.succeeded;
  }

  Map<String, Object?> _dependencyMetadata(
    DependencySourceCommandResult result,
  ) => <String, Object?>{
    'command': result.command,
    'status': result.status.name,
    'statusMessage': result.statusMessage,
    'succeeded': result.succeeded,
    if (result.payload != null) 'payload': result.payload,
    if (result.errorPayload != null) 'errorPayload': result.errorPayload,
  };

  Map<String, Object?> _deploymentMetadata(DeploymentCommandResult result) =>
      <String, Object?>{
        'command': result.command,
        'status': result.status.name,
        'statusMessage': result.statusMessage,
        'succeeded': result.succeeded,
        if (result.payload != null) 'payload': result.payload,
        if (result.errorPayload != null) 'errorPayload': result.errorPayload,
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
