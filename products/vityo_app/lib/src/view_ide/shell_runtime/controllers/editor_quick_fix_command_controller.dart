import '../../commands/commands.dart';
import '../../../ide/workspace/workspace.dart';

typedef DiagnosticActionTelemetryRecorder =
    void Function(
      String action,
      bool succeeded,
      String message,
      Map<String, Object?> metadata,
    );

/// Owns editor quick-fix preview/application and diagnostic telemetry.
final class EditorQuickFixCommandController {
  const EditorQuickFixCommandController({
    required this.previewProjectQuickFix,
    required this.applyLocalQuickFix,
    required this.applyProjectQuickFix,
    required this.markActiveDocumentDirty,
    required this.recordTelemetry,
    required this.log,
    required this.notify,
  });

  final Future<WorkspaceEditPreview?> Function() previewProjectQuickFix;
  final bool Function() applyLocalQuickFix;
  final Future<bool> Function() applyProjectQuickFix;
  final void Function() markActiveDocumentDirty;
  final DiagnosticActionTelemetryRecorder recordTelemetry;
  final void Function(String message) log;
  final void Function() notify;

  Future<void> execute(AppCommandId commandId) async {
    switch (commandId) {
      case AppCommandId.previewQuickFix:
        await _preview();
        return;
      case AppCommandId.applyQuickFix:
        await _apply();
        return;
      default:
        throw ArgumentError.value(
          commandId,
          'commandId',
          'Unsupported editor quick-fix command.',
        );
    }
  }

  Future<void> _preview() async {
    final preview = await previewProjectQuickFix();
    final succeeded = preview?.canApply ?? false;
    final message = succeeded
        ? 'Quick fix preview collected.'
        : 'Quick fix preview skipped: no action available.';
    final metadata = <String, Object?>{
      if (preview != null) 'workspaceEditPreview': preview.toJson(),
    };
    recordTelemetry('previewQuickFix', succeeded, message, metadata);
    notify();
  }

  Future<void> _apply() async {
    if (applyLocalQuickFix()) {
      markActiveDocumentDirty();
      const message = 'Quick fix applied at editor selection.';
      log(message);
      recordTelemetry('applyQuickFix', true, message, const <String, Object?>{
        'scope': 'selection',
      });
    } else if (await applyProjectQuickFix()) {
      const message =
          'Project workspace quick fix applied from editor command.';
      log(message);
      recordTelemetry('applyQuickFix', true, message, const <String, Object?>{
        'scope': 'workspace',
      });
    } else {
      const message = 'Quick fix skipped: no action available at selection.';
      log(message);
      recordTelemetry('applyQuickFix', false, message, const <String, Object?>{
        'scope': 'selection',
      });
    }
    notify();
  }
}
