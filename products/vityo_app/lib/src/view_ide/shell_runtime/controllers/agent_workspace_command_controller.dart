import '../../agent_client/agent.dart';
import '../../commands/commands.dart';
import '../../../ide/editor/editor.dart';
import 'agent_controller.dart';
import 'workspace_file_command_controller.dart';
import 'workspace_search_controller.dart';

/// Owns agent-facing workspace file and search command routing.
final class AgentWorkspaceCommandController {
  const AgentWorkspaceCommandController({
    required this.agentController,
    required this.fileCommands,
    required this.searchController,
    required this.openWorkspaceFile,
    required this.renameSymbol,
    required this.editorController,
    required this.goToProjectDefinition,
    required this.selectProjectReference,
    required this.log,
    required this.notify,
  });

  final AgentController agentController;
  final WorkspaceFileCommandController fileCommands;
  final WorkspaceSearchController searchController;
  final Future<bool> Function(String filePath) openWorkspaceFile;
  final Future<bool> Function(String newName) renameSymbol;
  final EditorSessionController editorController;
  final Future<bool> Function() goToProjectDefinition;
  final Future<bool> Function({required bool forward}) selectProjectReference;
  final void Function(String message) log;
  final void Function() notify;

  Future<bool> apply(AgentIdeCommandSuggestion suggestion) async {
    return switch (suggestion.commandId) {
      'openWorkspaceFile' => _open(suggestion),
      'createWorkspaceFile' => _runFileCommand(
        suggestion,
        AppCommandId.createWorkspaceFile,
      ),
      'renameWorkspaceFile' => _runFileCommand(
        suggestion,
        AppCommandId.renameWorkspaceFile,
      ),
      'deleteWorkspaceFile' => _runFileCommand(
        suggestion,
        AppCommandId.deleteWorkspaceFile,
      ),
      'revealWorkspaceFile' => _runFileCommand(
        suggestion,
        AppCommandId.revealWorkspaceFile,
      ),
      'searchWorkspace' => _search(suggestion),
      'renameSymbol' => _renameSymbol(suggestion),
      'nextDiagnostic' => _diagnostic(suggestion, forward: true),
      'previousDiagnostic' => _diagnostic(suggestion, forward: false),
      'goToDefinition' => _definition(suggestion),
      'nextReference' => _reference(suggestion, forward: true),
      'previousReference' => _reference(suggestion, forward: false),
      _ => throw ArgumentError.value(
        suggestion.commandId,
        'suggestion.commandId',
        'Unsupported agent workspace command.',
      ),
    };
  }

  Future<bool> _open(AgentIdeCommandSuggestion suggestion) async {
    final input = suggestion.input?.trim() ?? '';
    if (input.isEmpty) {
      return _missingInput(suggestion, AppCommandId.openWorkspaceFile);
    }
    final applied = await openWorkspaceFile(input);
    _record(
      suggestion,
      applied: applied,
      message: applied
          ? 'Agent command openWorkspaceFile opened $input.'
          : 'Agent command openWorkspaceFile failed for $input.',
    );
    return applied;
  }

  Future<bool> _search(AgentIdeCommandSuggestion suggestion) async {
    final input = suggestion.input?.trim() ?? '';
    if (input.isEmpty) {
      return _missingInput(suggestion, AppCommandId.searchWorkspace);
    }
    final applied = await searchController.search(input);
    _record(
      suggestion,
      applied: applied,
      message: applied
          ? 'Agent command searchWorkspace completed for $input.'
          : 'Agent command searchWorkspace failed for $input.',
    );
    return applied;
  }

  Future<bool> _renameSymbol(AgentIdeCommandSuggestion suggestion) async {
    final input = suggestion.input?.trim() ?? '';
    if (input.isEmpty) {
      return _missingInput(suggestion, AppCommandId.renameSymbol);
    }
    final applied = await renameSymbol(input);
    _record(
      suggestion,
      applied: applied,
      message: applied
          ? 'Agent command renameSymbol applied.'
          : 'Agent command renameSymbol skipped.',
    );
    return applied;
  }

  Future<bool> _diagnostic(
    AgentIdeCommandSuggestion suggestion, {
    required bool forward,
  }) async {
    final applied = forward
        ? editorController.selectNextDiagnosticAtSelection()
        : editorController.selectPreviousDiagnosticAtSelection();
    final direction = forward ? 'nextDiagnostic' : 'previousDiagnostic';
    final message = applied
        ? 'Agent command $direction selected in editor.'
        : 'Agent command $direction skipped: no diagnostics.';
    log(message);
    _record(suggestion, applied: applied, message: message);
    notify();
    return applied;
  }

  Future<bool> _definition(AgentIdeCommandSuggestion suggestion) async {
    if (editorController.selectDefinitionAtSelection()) {
      const message = 'Agent command goToDefinition selected in editor.';
      log(message);
      _record(suggestion, applied: true, message: message);
      notify();
      return true;
    }
    if (await goToProjectDefinition()) {
      _record(
        suggestion,
        applied: true,
        message: 'Agent command goToDefinition opened project definition.',
      );
      return true;
    }
    const message =
        'Agent command goToDefinition skipped: no resolved definition.';
    log(message);
    _record(suggestion, applied: false, message: message);
    notify();
    return false;
  }

  Future<bool> _reference(
    AgentIdeCommandSuggestion suggestion, {
    required bool forward,
  }) async {
    final local = forward
        ? editorController.selectNextReferenceAtSelection()
        : editorController.selectPreviousReferenceAtSelection();
    final direction = forward ? 'nextReference' : 'previousReference';
    if (local) {
      final message = 'Agent command $direction selected in editor.';
      log(message);
      _record(suggestion, applied: true, message: message);
      notify();
      return true;
    }
    if (await selectProjectReference(forward: forward)) {
      _record(
        suggestion,
        applied: true,
        message: 'Agent command $direction opened project reference.',
      );
      return true;
    }
    final message = 'Agent command $direction skipped: no references.';
    log(message);
    _record(suggestion, applied: false, message: message);
    notify();
    return false;
  }

  Future<bool> _runFileCommand(
    AgentIdeCommandSuggestion suggestion,
    AppCommandId commandId,
  ) async {
    final input = suggestion.input?.trim() ?? '';
    if (input.isEmpty) {
      return _missingInput(suggestion, commandId);
    }
    final result = await fileCommands.execute(
      commandId: commandId,
      input: input,
    );
    _record(
      suggestion,
      applied: result.applied,
      message: result.message,
      metadata: result.toJson(),
    );
    log(result.message);
    notify();
    return result.applied;
  }

  bool _missingInput(
    AgentIdeCommandSuggestion suggestion,
    AppCommandId commandId,
  ) {
    final descriptor = VityoCommandRegistry.descriptorFor(commandId);
    final message =
        commandId == AppCommandId.openWorkspaceFile ||
            commandId == AppCommandId.searchWorkspace ||
            commandId == AppCommandId.renameSymbol
        ? 'Agent command ${commandId.name} skipped: missing input.'
        : 'Agent command ${commandId.name} skipped: ${descriptor.inputLabel} input is required.';
    _record(
      suggestion,
      applied: false,
      message: message,
      metadata: <String, Object?>{
        'reason': 'missing-input',
        'requiredInput': descriptor.inputLabel,
        'inputLabel': descriptor.inputLabel,
        'inputContract': descriptor.inputContract,
        'inputExamples': descriptor.inputExamples,
      },
    );
    log(message);
    return false;
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
