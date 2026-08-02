import '../../commands/commands.dart';

/// Owns honest fallback UX for commands without a direct no-input executor.
final class ShellCommandFallbackController {
  const ShellCommandFallbackController({
    required this.log,
    required this.notify,
  });

  final void Function(String message) log;
  final void Function() notify;

  void execute(AppCommandId commandId) {
    switch (commandId) {
      case AppCommandId.showRuntime:
      case AppCommandId.showAgent:
      case AppCommandId.showDebug:
        return;
      case AppCommandId.selectDebugThread:
        log('Select Debug Thread requires caller-provided input.');
        return;
      case AppCommandId.selectDebugStackFrame:
        log('Select Debug Stack Frame requires caller-provided input.');
        return;
      case AppCommandId.selectClangCppVersion:
        log('Select Clang/C++ Version requires caller-provided input.');
        return;
      case AppCommandId.openWorkspaceFile:
        log('Open Workspace File requires caller-provided input.');
        return;
      case AppCommandId.searchWorkspace:
        log('Search Workspace requires caller-provided input.');
        return;
      case AppCommandId.previewWorkspaceReplace:
        log('Preview Workspace Replace requires caller-provided input.');
        return;
      case AppCommandId.renameSymbol:
        log('Rename Symbol requires caller-provided input.');
        return;
      case AppCommandId.openSettings:
        log('Settings route is reserved for M7 theme/profile system.');
        return;
      case AppCommandId.createWorkspaceFile:
      case AppCommandId.renameWorkspaceFile:
      case AppCommandId.deleteWorkspaceFile:
      case AppCommandId.revealWorkspaceFile:
        log(
          '${VityoCommandRegistry.descriptorFor(commandId).label} '
          'requires a File Explorer dialog route.',
        );
        return;
      default:
        log(
          '${VityoCommandRegistry.labelFor(commandId)} route requested; '
          'capability gap: command is not wired yet.',
        );
        notify();
        return;
    }
  }
}
