import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/shell_command_fallback_controller.dart';

void main() {
  test('input command reports caller-provided input requirement', () {
    final fixture = _Fixture();

    fixture.controller.execute(AppCommandId.selectDebugThread);

    expect(fixture.logs.single, contains('caller-provided input'));
    expect(fixture.notifications, 0);
  });

  test('unwired route reports explicit capability gap', () {
    final fixture = _Fixture();

    fixture.controller.execute(AppCommandId.runSelectedTarget);

    expect(fixture.logs.single, contains('capability gap'));
    expect(fixture.notifications, 1);
  });

  test('surface focus commands remain side-effect free', () {
    final fixture = _Fixture();

    fixture.controller.execute(AppCommandId.showRuntime);

    expect(fixture.logs, isEmpty);
    expect(fixture.notifications, 0);
  });
}

final class _Fixture {
  _Fixture() {
    controller = ShellCommandFallbackController(
      log: logs.add,
      notify: () => notifications += 1,
    );
  }

  final List<String> logs = <String>[];
  late final ShellCommandFallbackController controller;
  int notifications = 0;
}
