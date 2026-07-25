import '../../agent/agent.dart';
import '../../commands/commands.dart';
import '../../interaction/interaction.dart';
import '../workspace_file_lifecycle.dart';
import 'agent_controller.dart';

/// Owns shared Agent command receipts, prerequisites, and dirty-workspace guards.
final class AgentCommandReceiptController {
  const AgentCommandReceiptController({
    required this.agentController,
    required this.dirtyDocumentIds,
    required this.activeDocumentPath,
    required this.saveActive,
    required this.saveAll,
    required this.log,
  });

  final AgentController agentController;
  final List<String> Function() dirtyDocumentIds;
  final String Function() activeDocumentPath;
  final Future<DocumentResourceBindingSnapshot> Function() saveActive;
  final Future<WorkspaceSaveAllResult> Function() saveAll;
  final void Function(String message) log;

  Future<bool> executeSave(AgentIdeCommandSuggestion suggestion) async {
    switch (suggestion.commandId) {
      case 'save':
        final path = activeDocumentPath();
        final snapshot = await saveActive();
        final applied =
            snapshot.state == DocumentResourceBindingState.boundClean;
        record(
          suggestion,
          applied: applied,
          message: applied
              ? 'Agent command save completed for $path.'
              : 'Agent command save failed for $path.',
          metadata: <String, Object?>{
            'activeFilePath': path,
            'bindingState': snapshot.state.name,
          },
        );
        return applied;
      case 'saveAll':
        final completedCommand = completedRequiredCommandFor('saveAll');
        final result = await saveAll();
        final applied = result.skippedDocumentIds.isEmpty;
        record(
          suggestion,
          applied: applied,
          message: result.message,
          metadata: <String, Object?>{
            'savedCount': result.savedDocumentIds.length,
            'skippedCount': result.skippedDocumentIds.length,
            'savedDocumentIds': result.savedDocumentIds,
            'skippedDocumentIds': result.skippedDocumentIds,
            if (completedCommand != null)
              'completedRequiredCommandFor': completedCommand,
          },
        );
        return applied;
      default:
        throw ArgumentError.value(
          suggestion.commandId,
          'suggestion.commandId',
          'Unsupported save receipt command.',
        );
    }
  }

  Map<String, Object?> missingInputMetadata(AppCommandId commandId) {
    final descriptor = StyioCommandRegistry.descriptorFor(commandId);
    return <String, Object?>{
      'reason': 'missing-input',
      'requiredInput': descriptor.inputLabel,
      'inputLabel': descriptor.inputLabel,
      'inputContract': descriptor.inputContract,
      'inputExamples': descriptor.inputExamples,
    };
  }

  void record(
    AgentIdeCommandSuggestion suggestion, {
    required bool applied,
    required String message,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    final effectiveMetadata = <String, Object?>{...metadata};
    final prerequisite = suggestion.prerequisiteForCommandId;
    if (prerequisite != null && prerequisite.isNotEmpty) {
      effectiveMetadata[suggestion.commandId == AppCommandId.openSettings.name
              ? 'recoveryForCommandId'
              : 'completedRequiredCommandFor'] =
          prerequisite;
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

  String? completedRequiredCommandFor(String commandId) {
    final previousResult = agentController.lastCommandResult;
    if (previousResult == null || previousResult.commandId == commandId) {
      return null;
    }
    return requiredCommandIdFromAgentMetadata(previousResult.metadata) ==
            commandId
        ? previousResult.commandId
        : null;
  }

  bool blockDiskBackedCommandWhenDirty(AgentIdeCommandSuggestion suggestion) {
    final dirtyDocuments = dirtyDocumentIds();
    if (dirtyDocuments.isEmpty) {
      return false;
    }
    final message =
        'Agent command ${suggestion.commandId} blocked: save dirty workspace documents before running disk-backed IDE tools.';
    record(
      suggestion,
      applied: false,
      message: message,
      metadata: <String, Object?>{
        'dirtyDocumentIds': dirtyDocuments,
        'requiredCommand': AppCommandId.saveAll.name,
      },
    );
    log(message);
    return true;
  }
}
