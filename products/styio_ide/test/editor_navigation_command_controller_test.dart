import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/commands/commands.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/editor_navigation_command_controller.dart';

void main() {
  test(
    'definition falls back from local to authoritative project facts',
    () async {
      final fixture = _Fixture(localDefinition: false, projectDefinition: true);

      await fixture.controller.execute(AppCommandId.goToDefinition);

      expect(fixture.logs.single, 'Project definition selected in editor.');
      expect(fixture.notifications, 1);
    },
  );

  test(
    'reference navigation reports honest absence after both routes',
    () async {
      final fixture = _Fixture();

      await fixture.controller.execute(AppCommandId.nextReference);

      expect(fixture.logs.single, contains('no resolved references'));
      expect(fixture.projectReferenceDirections, <bool>[true]);
    },
  );

  test('local diagnostic navigation does not invoke project routes', () async {
    final fixture = _Fixture(nextDiagnostic: true);

    await fixture.controller.execute(AppCommandId.nextDiagnostic);

    expect(fixture.logs.single, 'Next diagnostic selected in editor.');
    expect(fixture.projectReferenceDirections, isEmpty);
  });
}

final class _Fixture {
  _Fixture({
    this.nextDiagnostic = false,
    this.localDefinition = false,
    this.projectDefinition = false,
  }) {
    controller = EditorNavigationCommandController(
      selectNextDiagnostic: () => nextDiagnostic,
      selectPreviousDiagnostic: () => false,
      selectLocalDefinition: () => localDefinition,
      selectProjectDefinition: () async => projectDefinition,
      selectNextLocalReference: () => false,
      selectPreviousLocalReference: () => false,
      selectProjectReference: ({required forward}) async {
        projectReferenceDirections.add(forward);
        return false;
      },
      log: logs.add,
      notify: () => notifications += 1,
    );
  }

  final bool nextDiagnostic;
  final bool localDefinition;
  final bool projectDefinition;
  late final EditorNavigationCommandController controller;
  final List<String> logs = <String>[];
  final List<bool> projectReferenceDirections = <bool>[];
  int notifications = 0;
}
