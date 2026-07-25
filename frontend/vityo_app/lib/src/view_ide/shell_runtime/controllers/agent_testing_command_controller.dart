import '../../agent/agent.dart';
import '../../commands/commands.dart';
import '../../testing/testing.dart';
import 'agent_controller.dart';
import 'testing_controller.dart';

/// Owns agent-facing failed-test and named-configuration command routing.
final class AgentTestingCommandController {
  const AgentTestingCommandController({
    required this.testingController,
    required this.agentController,
    required this.blockWhenDirty,
  });

  final ShellTestingController testingController;
  final AgentController agentController;
  final bool Function(AgentIdeCommandSuggestion suggestion) blockWhenDirty;

  Future<bool> apply(AgentIdeCommandSuggestion suggestion) async {
    if (blockWhenDirty(suggestion)) {
      return false;
    }
    return switch (suggestion.commandId) {
      'rerunFailedTests' => _failed(suggestion, debug: false),
      'debugFailedTests' => _failed(suggestion, debug: true),
      'runTestConfiguration' => _configuration(suggestion, debug: false),
      'debugTestConfiguration' => _configuration(suggestion, debug: true),
      _ => throw ArgumentError.value(
        suggestion.commandId,
        'suggestion.commandId',
        'Unsupported agent testing command.',
      ),
    };
  }

  Future<bool> executeOrdinary(AppCommandId commandId) async {
    switch (commandId) {
      case AppCommandId.rerunFailedTests:
      case AppCommandId.debugFailedTests:
        final debug = commandId == AppCommandId.debugFailedTests;
        if (debug) {
          await testingController.debugFailed();
        } else {
          await testingController.rerunFailed();
        }
        final result = testingController.lastRun;
        final action = debug ? 'Debug Failed Tests' : 'Rerun Failed Tests';
        final applied = testingController.agentCommandApplied(result);
        _record(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: applied,
          message: result == null
              ? '$action skipped: no test result is available.'
              : testingController.resultMessage(action, result),
          metadata: testingController.agentCommandMetadata(result),
        );
        return applied;
      case AppCommandId.runTestConfiguration:
      case AppCommandId.debugTestConfiguration:
        _record(
          AgentIdeCommandSuggestion(commandId: commandId.name),
          applied: false,
          message:
              '${StyioCommandRegistry.descriptorFor(commandId).label} requires test configuration id input.',
          metadata: testingController.configurationCommandMetadata(),
        );
        return false;
      default:
        throw ArgumentError.value(
          commandId,
          'commandId',
          'Unsupported ordinary testing command.',
        );
    }
  }

  Future<bool> _failed(
    AgentIdeCommandSuggestion suggestion, {
    required bool debug,
  }) async {
    if (debug) {
      await testingController.debugFailed();
    } else {
      await testingController.rerunFailed();
    }
    final result = testingController.lastRun;
    final applied = testingController.agentCommandApplied(result);
    final action = debug ? 'debugFailedTests' : 'rerunFailedTests';
    _record(
      suggestion,
      applied: applied,
      message: result == null
          ? 'Agent command $action skipped: no test result is available.'
          : testingController.resultMessage('Agent command $action', result),
      metadata: testingController.agentCommandMetadata(result),
    );
    return applied;
  }

  Future<bool> _configuration(
    AgentIdeCommandSuggestion suggestion, {
    required bool debug,
  }) async {
    final input = suggestion.input?.trim() ?? '';
    final configuration = testingController.configurationForId(input);
    if (configuration == null) {
      _record(
        suggestion,
        applied: false,
        message:
            'Agent command ${suggestion.commandId} skipped: valid test configuration id input is required.',
        metadata: testingController.configurationCommandMetadata(),
      );
      return false;
    }
    if (debug) {
      await testingController.debugConfiguration(configuration);
    } else {
      await testingController.runConfiguration(configuration);
    }
    return _recordConfigurationResult(suggestion, configuration);
  }

  bool _recordConfigurationResult(
    AgentIdeCommandSuggestion suggestion,
    TestRunConfiguration configuration,
  ) {
    final result = testingController.lastRun;
    final applied = testingController.agentCommandApplied(result);
    _record(
      suggestion,
      applied: applied,
      message: result == null
          ? 'Agent command ${suggestion.commandId} skipped: no test result is available.'
          : testingController.resultMessage(
              'Agent command ${suggestion.commandId}',
              result,
            ),
      metadata: testingController.configurationCommandMetadata(
        configuration: configuration,
        result: result,
      ),
    );
    return applied;
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
