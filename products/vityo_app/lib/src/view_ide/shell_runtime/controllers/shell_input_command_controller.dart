import '../../../ide/editor/selection/selection_interaction.dart';
import '../../commands/commands.dart';
import 'workspace_file_command_controller.dart';

/// Owns routing for commands that may carry caller-provided text input.
final class ShellInputCommandController {
  const ShellInputCommandController({
    required this.workspaceFileCommands,
    required this.blockedReasonForCommand,
    required this.executeCommand,
    this.requestEditorSelectionCommand,
    required this.searchWorkspace,
    required this.openWorkspaceFile,
    required this.previewWorkspaceReplace,
    required this.renameSymbol,
    required this.previewSourceControlDiff,
    required this.stageSourceControlPaths,
    required this.unstageSourceControlPaths,
    required this.planSourceControlBranchSwitch,
    required this.planSourceControlCommitDraft,
    required this.selectClangCppVersion,
    required this.selectDebugThread,
    required this.selectDebugStackFrame,
    required this.runTestConfiguration,
    required this.log,
    required this.notify,
  });

  final WorkspaceFileCommandController workspaceFileCommands;
  final String? Function(AppCommandId commandId) blockedReasonForCommand;
  final Future<void> Function(AppCommandId commandId) executeCommand;
  final void Function(EditorSelectionCommand command)?
  requestEditorSelectionCommand;
  final Future<bool> Function(String query) searchWorkspace;
  final Future<bool> Function(String filePath) openWorkspaceFile;
  final Future<void> Function({
    required String query,
    required String replacement,
  })
  previewWorkspaceReplace;
  final Future<void> Function(String newName) renameSymbol;
  final Future<void> Function(String path) previewSourceControlDiff;
  final Future<void> Function(List<String> paths) stageSourceControlPaths;
  final Future<void> Function(List<String> paths) unstageSourceControlPaths;
  final Future<void> Function(String targetBranch)
  planSourceControlBranchSwitch;
  final void Function({required String message, List<String>? selectedPaths})
  planSourceControlCommitDraft;
  final Future<void> Function(String versionId, {String? cppStandard})
  selectClangCppVersion;
  final Future<void> Function(String threadId) selectDebugThread;
  final Future<void> Function(String frameId) selectDebugStackFrame;
  final Future<bool> Function(String configurationId, {required bool debug})
  runTestConfiguration;
  final void Function(String message) log;
  final void Function() notify;

  Future<void> execute(AppCommandId commandId, String input) async {
    final normalizedInput = input.trim();
    final blockedReason = blockedReasonForCommand(commandId);
    if (blockedReason != null) {
      log(
        '${VityoCommandRegistry.descriptorFor(commandId).label} blocked: '
        '$blockedReason',
      );
      return;
    }
    switch (commandId) {
      case AppCommandId.addCursorAbove:
      case AppCommandId.addCursorBelow:
      case AppCommandId.removeSecondaryCursors:
      case AppCommandId.moveCursorsLeft:
      case AppCommandId.moveCursorsRight:
      case AppCommandId.moveCursorsUp:
      case AppCommandId.moveCursorsDown:
      case AppCommandId.extendSelectionsLeft:
      case AppCommandId.extendSelectionsRight:
      case AppCommandId.extendSelectionsUp:
      case AppCommandId.extendSelectionsDown:
      case AppCommandId.extendColumnSelectionLeft:
      case AppCommandId.extendColumnSelectionRight:
      case AppCommandId.extendColumnSelectionUp:
      case AppCommandId.extendColumnSelectionDown:
        final requestSelection = requestEditorSelectionCommand;
        if (requestSelection == null) {
          await executeCommand(commandId);
          return;
        }
        requestSelection(_selectionCommandFor(commandId));
        return;
      case AppCommandId.openWorkspaceFile:
        await openWorkspaceFile(normalizedInput);
        return;
      case AppCommandId.searchWorkspace:
        await searchWorkspace(normalizedInput);
        return;
      case AppCommandId.previewWorkspaceReplace:
        final replacement = _parseReplacement(normalizedInput);
        if (replacement == null) {
          _logMissingInput(commandId);
          return;
        }
        await previewWorkspaceReplace(
          query: replacement.query,
          replacement: replacement.replacement,
        );
        return;
      case AppCommandId.renameSymbol:
        if (normalizedInput.isEmpty) {
          _logMissingInput(commandId);
          return;
        }
        await renameSymbol(normalizedInput);
        return;
      case AppCommandId.previewSourceControlDiff:
        if (normalizedInput.isEmpty) {
          _logMissingInput(commandId);
          return;
        }
        await previewSourceControlDiff(normalizedInput);
        return;
      case AppCommandId.stageSourceControl:
      case AppCommandId.unstageSourceControl:
        final paths = _parsePaths(normalizedInput);
        if (paths.isEmpty) {
          _logMissingInput(commandId);
          return;
        }
        if (commandId == AppCommandId.stageSourceControl) {
          await stageSourceControlPaths(paths);
        } else {
          await unstageSourceControlPaths(paths);
        }
        return;
      case AppCommandId.planSourceControlBranchSwitch:
        if (normalizedInput.isEmpty) {
          _logMissingInput(commandId);
          return;
        }
        await planSourceControlBranchSwitch(normalizedInput);
        return;
      case AppCommandId.planSourceControlCommitDraft:
        final draft = _parseCommitDraft(normalizedInput);
        if (draft == null) {
          _logMissingInput(commandId);
          return;
        }
        planSourceControlCommitDraft(
          message: draft.message,
          selectedPaths: draft.paths.isEmpty ? null : draft.paths,
        );
        return;
      case AppCommandId.selectClangCppVersion:
        final version = _parseVersion(normalizedInput);
        if (version == null) {
          _logMissingInput(commandId);
          return;
        }
        await selectClangCppVersion(
          version.versionId,
          cppStandard: version.cppStandard,
        );
        return;
      case AppCommandId.selectDebugThread:
      case AppCommandId.selectDebugStackFrame:
        if (normalizedInput.isEmpty) {
          _logMissingInput(commandId);
          return;
        }
        if (commandId == AppCommandId.selectDebugThread) {
          await selectDebugThread(normalizedInput);
        } else {
          await selectDebugStackFrame(normalizedInput);
        }
        return;
      case AppCommandId.runTestConfiguration:
      case AppCommandId.debugTestConfiguration:
        if (normalizedInput.isEmpty ||
            !await runTestConfiguration(
              normalizedInput,
              debug: commandId == AppCommandId.debugTestConfiguration,
            )) {
          _logMissingInput(commandId);
        }
        return;
      case AppCommandId.createWorkspaceFile:
      case AppCommandId.renameWorkspaceFile:
      case AppCommandId.deleteWorkspaceFile:
      case AppCommandId.revealWorkspaceFile:
        await _workspaceFile(commandId, normalizedInput);
        return;
      default:
        await executeCommand(commandId);
        return;
    }
  }

  Future<void> _workspaceFile(AppCommandId commandId, String input) async {
    final result = await workspaceFileCommands.execute(
      commandId: commandId,
      input: input,
    );
    log(result.message);
    notify();
  }

  void _logMissingInput(AppCommandId commandId) {
    final descriptor = VityoCommandRegistry.descriptorFor(commandId);
    final inputLabel = descriptor.inputLabel.isEmpty
        ? 'valid command'
        : descriptor.inputLabel;
    log(
      '${descriptor.label} skipped: '
      '$inputLabel input is required.',
    );
    notify();
  }
}

EditorSelectionCommand _selectionCommandFor(AppCommandId commandId) {
  return switch (commandId) {
    AppCommandId.addCursorAbove => EditorSelectionCommand.addCursorAbove,
    AppCommandId.addCursorBelow => EditorSelectionCommand.addCursorBelow,
    AppCommandId.removeSecondaryCursors =>
      EditorSelectionCommand.removeSecondaryCursors,
    AppCommandId.moveCursorsLeft => EditorSelectionCommand.moveCursorsLeft,
    AppCommandId.moveCursorsRight => EditorSelectionCommand.moveCursorsRight,
    AppCommandId.moveCursorsUp => EditorSelectionCommand.moveCursorsUp,
    AppCommandId.moveCursorsDown => EditorSelectionCommand.moveCursorsDown,
    AppCommandId.extendSelectionsLeft =>
      EditorSelectionCommand.extendSelectionsLeft,
    AppCommandId.extendSelectionsRight =>
      EditorSelectionCommand.extendSelectionsRight,
    AppCommandId.extendSelectionsUp =>
      EditorSelectionCommand.extendSelectionsUp,
    AppCommandId.extendSelectionsDown =>
      EditorSelectionCommand.extendSelectionsDown,
    AppCommandId.extendColumnSelectionLeft =>
      EditorSelectionCommand.extendColumnSelectionLeft,
    AppCommandId.extendColumnSelectionRight =>
      EditorSelectionCommand.extendColumnSelectionRight,
    AppCommandId.extendColumnSelectionUp =>
      EditorSelectionCommand.extendColumnSelectionUp,
    AppCommandId.extendColumnSelectionDown =>
      EditorSelectionCommand.extendColumnSelectionDown,
    _ => throw ArgumentError.value(
      commandId,
      'commandId',
      'is not an editor selection command',
    ),
  };
}

final class _WorkspaceReplacementInput {
  const _WorkspaceReplacementInput(this.query, this.replacement);

  final String query;
  final String replacement;
}

_WorkspaceReplacementInput? _parseReplacement(String input) {
  final arrowIndex = input.indexOf('->');
  if (arrowIndex <= 0) {
    return null;
  }
  final query = input.substring(0, arrowIndex).trim();
  if (query.isEmpty) {
    return null;
  }
  return _WorkspaceReplacementInput(
    query,
    input.substring(arrowIndex + 2).trim(),
  );
}

final class _SourceControlCommitDraftInput {
  const _SourceControlCommitDraftInput(this.message, this.paths);

  final String message;
  final List<String> paths;
}

_SourceControlCommitDraftInput? _parseCommitDraft(String input) {
  if (input.isEmpty) {
    return null;
  }
  final arrowIndex = input.indexOf('->');
  if (arrowIndex < 0) {
    return _SourceControlCommitDraftInput(input, const <String>[]);
  }
  final message = input.substring(0, arrowIndex).trim();
  if (message.isEmpty) {
    return null;
  }
  return _SourceControlCommitDraftInput(
    message,
    _parsePaths(input.substring(arrowIndex + 2)),
  );
}

List<String> _parsePaths(String input) => input
    .split(RegExp(r'[\n,]+'))
    .map((path) => path.trim())
    .where((path) => path.isNotEmpty)
    .toList(growable: false);

final class _ClangCppVersionInput {
  const _ClangCppVersionInput(this.versionId, this.cppStandard);

  final String versionId;
  final String? cppStandard;
}

_ClangCppVersionInput? _parseVersion(String input) {
  if (input.isEmpty) {
    return null;
  }
  final parts = input.split(RegExp(r'\s+'));
  final standard = parts.length == 1 ? null : parts.skip(1).join(' ').trim();
  return _ClangCppVersionInput(
    parts.first,
    standard == null || standard.isEmpty ? null : standard,
  );
}
