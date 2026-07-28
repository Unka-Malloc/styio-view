import '../../agent_client/agent.dart';
import 'agent_controller.dart';

/// Owns agent-facing provider retry, replay, and failover recovery routing.
final class AgentProviderRecoveryCommandController {
  const AgentProviderRecoveryCommandController({
    required this.sessionController,
    required this.agentController,
    required this.failoverProviderProfile,
    required this.log,
    required this.notify,
  });

  final AgentCodingSessionController sessionController;
  final AgentController agentController;
  final Future<AgentProviderConfigurationResult?> Function(String profileKey)
  failoverProviderProfile;
  final void Function(String message) log;
  final void Function() notify;

  Future<bool> apply(AgentIdeCommandSuggestion suggestion) async {
    return switch (suggestion.commandId) {
      'retryAgentProvider' => _dispatch(
        suggestion,
        AgentCodingSessionRecoveryAction.retrySameProvider,
      ),
      'replayAgentPrompt' => _dispatch(
        suggestion,
        AgentCodingSessionRecoveryAction.replayPrompt,
      ),
      'failoverAgentProvider' => _failover(suggestion),
      _ => throw ArgumentError.value(
        suggestion.commandId,
        'suggestion.commandId',
        'Unsupported agent provider recovery command.',
      ),
    };
  }

  Future<bool> _dispatch(
    AgentIdeCommandSuggestion suggestion,
    AgentCodingSessionRecoveryAction action,
  ) async {
    final result = await sessionController.dispatchRecoveryRequestDraft(
      action,
      confirmed: true,
    );
    _record(
      suggestion,
      applied: result.dispatched,
      message: result.message,
      metadata: <String, Object?>{'recoveryDispatch': result.toJson()},
    );
    log(result.message);
    notify();
    return result.dispatched;
  }

  Future<bool> _failover(AgentIdeCommandSuggestion suggestion) async {
    final profileKey = suggestion.input?.trim() ?? '';
    if (profileKey.isEmpty) {
      const message =
          'Agent provider failover skipped: missing provider profile key.';
      _record(
        suggestion,
        applied: false,
        message: message,
        metadata: const <String, Object?>{'reason': 'missing-input'},
      );
      log(message);
      notify();
      return false;
    }
    final result = await failoverProviderProfile(profileKey);
    final message =
        result?.message ??
        'Agent provider failover unavailable: no configurator is wired.';
    _record(
      suggestion,
      applied: result?.mounted ?? false,
      message: message,
      metadata: <String, Object?>{
        'targetProviderProfileId': result?.profile.profileId,
        'targetProviderProfileKey': profileKey,
        'adapterKind': result?.adapterKind.wireValue,
        'adapterId': result?.adapterId,
        'retryEnabled': result?.retryEnabled,
      },
    );
    notify();
    return result?.mounted ?? false;
  }

  void _record(
    AgentIdeCommandSuggestion suggestion, {
    required bool applied,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
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
