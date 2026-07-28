import '../../agent_client/agent.dart';
import '../../commands/commands.dart';
import '../../../ide/workspace/workspace.dart';
import 'agent_controller.dart';
import 'source_control_controller.dart';

/// Owns fail-closed agent source-control command routing.
final class AgentSourceControlCommandController {
  const AgentSourceControlCommandController({
    required this.sourceControlController,
    required this.agentController,
    required this.activeFilePath,
    required this.log,
  });

  final SourceControlController sourceControlController;
  final AgentController agentController;
  final String Function() activeFilePath;
  final void Function(String message) log;

  Future<void> executeOrdinary(AppCommandId commandId) async {
    final suggestion = AgentIdeCommandSuggestion(commandId: commandId.name);
    switch (commandId) {
      case AppCommandId.refreshSourceControl:
        await _refresh(suggestion);
        return;
      case AppCommandId.previewSourceControlDiff:
        await _previewDiff(suggestion);
        return;
      case AppCommandId.stageSourceControl:
      case AppCommandId.unstageSourceControl:
        _recordOrdinaryMissingInput(suggestion, commandId, 'changed file path');
        return;
      case AppCommandId.planSourceControlBranchSwitch:
        _recordOrdinaryMissingInput(suggestion, commandId, 'target branch');
        return;
      case AppCommandId.planSourceControlCommitDraft:
        _recordOrdinaryMissingInput(suggestion, commandId, 'commit message');
        return;
      default:
        throw ArgumentError.value(
          commandId,
          'commandId',
          'Unsupported ordinary source-control command.',
        );
    }
  }

  Future<bool> apply(AgentIdeCommandSuggestion suggestion) async {
    return switch (suggestion.commandId) {
      'refreshSourceControl' => _refresh(suggestion),
      'previewSourceControlDiff' => _previewDiff(suggestion),
      'stageSourceControl' => _changeStage(suggestion, stage: true),
      'unstageSourceControl' => _changeStage(suggestion, stage: false),
      'planSourceControlBranchSwitch' => _planBranchSwitch(suggestion),
      'planSourceControlCommitDraft' => _planCommitDraft(suggestion),
      _ => throw ArgumentError.value(
        suggestion.commandId,
        'suggestion.commandId',
        'Unsupported agent source-control command.',
      ),
    };
  }

  Future<bool> _refresh(AgentIdeCommandSuggestion suggestion) async {
    final snapshot = await sourceControlController.refreshStatus();
    _record(
      suggestion,
      applied: snapshot.available,
      message: sourceControlController.refreshMessage(snapshot),
      metadata: <String, Object?>{'sourceControl': snapshot.toJson()},
    );
    return snapshot.available;
  }

  Future<bool> _previewDiff(AgentIdeCommandSuggestion suggestion) async {
    final input = suggestion.input?.trim();
    final path = input == null || input.isEmpty ? activeFilePath() : input;
    final snapshot = await sourceControlController.previewDiff(path);
    _record(
      suggestion,
      applied: snapshot.available,
      message: sourceControlController.diffPreviewMessage(snapshot),
      metadata: <String, Object?>{'sourceControlDiff': snapshot.toJson()},
    );
    return snapshot.available;
  }

  Future<bool> _changeStage(
    AgentIdeCommandSuggestion suggestion, {
    required bool stage,
  }) async {
    final paths = _parsePaths(suggestion.input);
    final commandId = stage
        ? AppCommandId.stageSourceControl
        : AppCommandId.unstageSourceControl;
    if (paths.isEmpty) {
      return _missingInput(suggestion, commandId, 'changed file path');
    }
    final result = await sourceControlController.runAction(
      SourceControlActionRequest(
        kind: stage
            ? SourceControlActionKind.stage
            : SourceControlActionKind.unstage,
        paths: paths,
      ),
    );
    _record(
      suggestion,
      applied: result.applied,
      message: sourceControlController.actionMessage(result),
      metadata: <String, Object?>{
        'pathCount': paths.length,
        'sourceControlAction': result.toJson(),
        ..._sourceControlContext(),
      },
    );
    return result.applied;
  }

  Future<bool> _planBranchSwitch(AgentIdeCommandSuggestion suggestion) async {
    final targetBranch = suggestion.input?.trim() ?? '';
    if (targetBranch.isEmpty) {
      return _missingInput(
        suggestion,
        AppCommandId.planSourceControlBranchSwitch,
        'target branch',
      );
    }
    final plan = await sourceControlController.planBranchSwitch(targetBranch);
    final message = plan.canRun
        ? 'Agent command planSourceControlBranchSwitch prepared ${plan.targetBranch}.'
        : 'Agent command planSourceControlBranchSwitch blocked: ${plan.blockedReason}';
    _record(
      suggestion,
      applied: plan.canRun,
      message: message,
      metadata: <String, Object?>{
        'sourceControlBranchSwitchPlan': plan.toJson(),
        ..._sourceControlContext(),
      },
    );
    return plan.canRun;
  }

  bool _planCommitDraft(AgentIdeCommandSuggestion suggestion) {
    final input = _parseCommitDraftInput(suggestion.input);
    if (input == null) {
      return _missingInput(
        suggestion,
        AppCommandId.planSourceControlCommitDraft,
        'commit message',
      );
    }
    final draft = sourceControlController.planCommitDraft(
      message: input.message,
      selectedPaths: input.paths.isEmpty ? null : input.paths,
    );
    final dialogState = sourceControlController.commitDialogState;
    final plan = draft.toCommitActionPlan();
    final message = plan.canRun
        ? 'Agent command planSourceControlCommitDraft prepared a commit draft.'
        : 'Agent command planSourceControlCommitDraft blocked: ${plan.blockedReason}';
    _record(
      suggestion,
      applied: plan.canRun,
      message: message,
      metadata: <String, Object?>{
        'sourceControlCommitDraft': draft.toJson(),
        if (dialogState != null)
          'sourceControlCommitDialog': dialogState.toJson(),
      },
    );
    return plan.canRun;
  }

  bool _missingInput(
    AgentIdeCommandSuggestion suggestion,
    AppCommandId commandId,
    String inputName,
  ) {
    final descriptor = VityoCommandRegistry.descriptorFor(commandId);
    final message =
        'Agent command ${suggestion.commandId} skipped: $inputName input is required.';
    final metadata = <String, Object?>{
      'reason': 'missing-input',
      'requiredInput': descriptor.inputLabel,
      'inputLabel': descriptor.inputLabel,
      'inputContract': descriptor.inputContract,
      'inputExamples': descriptor.inputExamples,
    };
    log(message);
    _record(suggestion, applied: false, message: message, metadata: metadata);
    return false;
  }

  void _recordOrdinaryMissingInput(
    AgentIdeCommandSuggestion suggestion,
    AppCommandId commandId,
    String inputName,
  ) {
    final descriptor = VityoCommandRegistry.descriptorFor(commandId);
    _record(
      suggestion,
      applied: false,
      message: '${descriptor.label} requires $inputName input.',
      metadata: _missingInputMetadata(descriptor),
    );
  }

  Map<String, Object?> _missingInputMetadata(AppCommandDescriptor descriptor) =>
      <String, Object?>{
        'reason': 'missing-input',
        'requiredInput': descriptor.inputLabel,
        'inputLabel': descriptor.inputLabel,
        'inputContract': descriptor.inputContract,
        'inputExamples': descriptor.inputExamples,
      };

  Map<String, Object?> _sourceControlContext() {
    final context = sourceControlController
        .statusController
        ?.agentContextSnapshot
        .toJson();
    return context == null
        ? const <String, Object?>{}
        : <String, Object?>{'sourceControlContext': context};
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

final class _SourceControlCommitDraftInput {
  const _SourceControlCommitDraftInput({
    required this.message,
    this.paths = const <String>[],
  });

  final String message;
  final List<String> paths;
}

_SourceControlCommitDraftInput? _parseCommitDraftInput(String? input) {
  final trimmed = input?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  final arrowIndex = trimmed.indexOf('->');
  if (arrowIndex < 0) {
    return _SourceControlCommitDraftInput(message: trimmed);
  }
  final message = trimmed.substring(0, arrowIndex).trim();
  if (message.isEmpty) {
    return null;
  }
  return _SourceControlCommitDraftInput(
    message: message,
    paths: _parsePaths(trimmed.substring(arrowIndex + 2)),
  );
}

List<String> _parsePaths(String? input) => (input ?? '')
    .split(RegExp(r'[\n,]+'))
    .map((path) => path.trim())
    .where((path) => path.isNotEmpty)
    .toList(growable: false);
