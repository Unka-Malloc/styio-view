import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/commands/app_commands.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/editor_refactor_command_controller.dart';

void main() {
  test('editor refactors preserve dirty state and honest results', () {
    var dirtyCount = 0;
    var notificationCount = 0;
    final logs = <String>[];
    final controller = EditorRefactorCommandController(
      applySafeDelete: () => true,
      applyInlineVariable: () => false,
      markActiveDocumentDirty: () => dirtyCount += 1,
      log: logs.add,
      notify: () => notificationCount += 1,
    );

    expect(controller.execute(AppCommandId.safeDelete), isTrue);
    expect(controller.execute(AppCommandId.inlineVariable), isFalse);
    expect(dirtyCount, 1);
    expect(notificationCount, 2);
    expect(logs, <String>[
      'Safe delete applied at editor selection.',
      'Inline variable skipped: no inline variable available at selection.',
    ]);
  });
}
