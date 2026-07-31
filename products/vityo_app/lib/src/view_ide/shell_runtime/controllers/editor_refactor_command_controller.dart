import '../../commands/commands.dart';

/// Routes editor-owned refactors without coupling them to an Agent runtime.
final class EditorRefactorCommandController {
  const EditorRefactorCommandController({
    required this.applySafeDelete,
    required this.applyInlineVariable,
    required this.markActiveDocumentDirty,
    required this.log,
    required this.notify,
  });

  final bool Function() applySafeDelete;
  final bool Function() applyInlineVariable;
  final void Function() markActiveDocumentDirty;
  final void Function(String message) log;
  final void Function() notify;

  bool execute(AppCommandId commandId) {
    final applied = switch (commandId) {
      AppCommandId.safeDelete => applySafeDelete(),
      AppCommandId.inlineVariable => applyInlineVariable(),
      _ => throw ArgumentError.value(
        commandId,
        'commandId',
        'Unsupported editor refactor command.',
      ),
    };
    final label = commandId == AppCommandId.safeDelete
        ? 'Safe delete'
        : 'Inline variable';
    final unavailable = commandId == AppCommandId.safeDelete
        ? 'no safe delete available'
        : 'no inline variable available';
    if (applied) {
      markActiveDocumentDirty();
      log('$label applied at editor selection.');
    } else {
      log('$label skipped: $unavailable at selection.');
    }
    notify();
    return applied;
  }
}
