import '../../agent/agent.dart';
import '../../interaction/language_service_status_surface.dart';
import 'agent_controller.dart';

/// Owns explicit language-service refresh and its honest Agent receipt.
final class LanguageRefreshCommandController {
  const LanguageRefreshCommandController({
    required this.agentController,
    required this.refreshAvailable,
    required this.refresh,
    required this.status,
    required this.log,
  });

  final AgentController agentController;
  final bool Function() refreshAvailable;
  final Future<void> Function() refresh;
  final LanguageServiceStatusSurface Function() status;
  final void Function(String message) log;

  Future<bool> execute({AgentIdeCommandSuggestion? suggestion}) async {
    if (!refreshAvailable()) {
      const message =
          'Language service refresh skipped: no refresh callback is configured.';
      log(message);
      if (suggestion != null) {
        _record(
          suggestion,
          applied: false,
          message: 'Agent command refreshLanguageService skipped.',
          metadata: const <String, Object?>{
            'reason': 'missing-refresh-callback',
          },
        );
      }
      return false;
    }
    try {
      await refresh();
      final currentStatus = status();
      final metadata = <String, Object?>{
        'languageServiceSeverity': currentStatus.severity.name,
        'languageServiceUsableCapabilityCount':
            currentStatus.usableCapabilityCount,
        'languageServiceFreshCapabilityCount':
            currentStatus.freshCapabilityCount,
        'languageServicePrimaryCapabilityStates':
            currentStatus.primaryCapabilityStates,
        if (currentStatus.parserEngine != null)
          'languageServiceParserEngine': currentStatus.parserEngine,
        if (currentStatus.grammarVersion != null)
          'languageServiceGrammarVersion': currentStatus.grammarVersion,
      };
      log('Language service refresh requested.');
      if (suggestion != null) {
        _record(
          suggestion,
          applied: true,
          message: 'Agent command refreshLanguageService completed.',
          metadata: metadata,
        );
      }
      return true;
    } on Object catch (error) {
      log('Language service refresh failed: $error');
      if (suggestion != null) {
        _record(
          suggestion,
          applied: false,
          message: 'Agent command refreshLanguageService failed.',
          metadata: <String, Object?>{'error': error.toString()},
        );
      }
      return false;
    }
  }

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
