import '../../commands/commands.dart';

/// Owns diagnostic, definition, and reference navigation command routing.
final class EditorNavigationCommandController {
  const EditorNavigationCommandController({
    required this.selectNextDiagnostic,
    required this.selectPreviousDiagnostic,
    required this.selectLocalDefinition,
    required this.selectProjectDefinition,
    required this.selectNextLocalReference,
    required this.selectPreviousLocalReference,
    required this.selectProjectReference,
    required this.log,
    required this.notify,
  });

  final bool Function() selectNextDiagnostic;
  final bool Function() selectPreviousDiagnostic;
  final bool Function() selectLocalDefinition;
  final Future<bool> Function() selectProjectDefinition;
  final bool Function() selectNextLocalReference;
  final bool Function() selectPreviousLocalReference;
  final Future<bool> Function({required bool forward}) selectProjectReference;
  final void Function(String message) log;
  final void Function() notify;

  Future<void> execute(AppCommandId commandId) async {
    switch (commandId) {
      case AppCommandId.nextDiagnostic:
        log(
          selectNextDiagnostic()
              ? 'Next diagnostic selected in editor.'
              : 'Next diagnostic skipped: no diagnostics available.',
        );
        break;
      case AppCommandId.previousDiagnostic:
        log(
          selectPreviousDiagnostic()
              ? 'Previous diagnostic selected in editor.'
              : 'Previous diagnostic skipped: no diagnostics available.',
        );
        break;
      case AppCommandId.goToDefinition:
        if (selectLocalDefinition()) {
          log('Definition selected in editor.');
        } else if (await selectProjectDefinition()) {
          log('Project definition selected in editor.');
        } else {
          log('Definition skipped: no resolved definition at selection.');
        }
        break;
      case AppCommandId.nextReference:
        await _selectReference(forward: true);
        break;
      case AppCommandId.previousReference:
        await _selectReference(forward: false);
        break;
      default:
        throw ArgumentError.value(
          commandId,
          'commandId',
          'Unsupported editor navigation command.',
        );
    }
    notify();
  }

  Future<void> _selectReference({required bool forward}) async {
    final selectedLocally = forward
        ? selectNextLocalReference()
        : selectPreviousLocalReference();
    if (selectedLocally) {
      log('${forward ? 'Next' : 'Previous'} reference selected in editor.');
      return;
    }
    if (await selectProjectReference(forward: forward)) {
      log(
        'Project ${forward ? 'next' : 'previous'} reference selected in editor.',
      );
      return;
    }
    log(
      '${forward ? 'Next' : 'Previous'} reference skipped: '
      'no resolved references at selection.',
    );
  }
}
