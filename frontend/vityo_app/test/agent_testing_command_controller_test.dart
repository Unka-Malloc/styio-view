import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/runtime/runtime.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_testing_command_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/testing_controller.dart';

void main() {
  test('rerun fails closed when no test result is available', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    final applied = await fixture.commands.apply(
      const AgentIdeCommandSuggestion(commandId: 'rerunFailedTests'),
    );

    expect(applied, isFalse);
    expect(fixture.fallbackRuns, 1);
    expect(
      fixture.agent.lastCommandResult?.message,
      contains('no test result'),
    );
  });

  test('configuration command exposes authoritative available ids', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    final applied = await fixture.commands.apply(
      const AgentIdeCommandSuggestion(
        commandId: 'runTestConfiguration',
        input: 'unknown',
      ),
    );

    expect(applied, isFalse);
    expect(
      fixture.agent.lastCommandResult?.metadata['availableConfigurationIds'],
      <String>['all-tests'],
    );
  });

  test('dirty workspace guard blocks before testing side effects', () async {
    final fixture = _fixture(blockDirty: true);
    addTearDown(fixture.dispose);

    final applied = await fixture.commands.apply(
      const AgentIdeCommandSuggestion(commandId: 'debugFailedTests'),
    );

    expect(applied, isFalse);
    expect(fixture.fallbackRuns, 0);
  });

  test(
    'ordinary rerun preserves user route without Agent dirty guard',
    () async {
      final fixture = _fixture(blockDirty: true);
      addTearDown(fixture.dispose);

      final applied = await fixture.commands.executeOrdinary(
        AppCommandId.rerunFailedTests,
      );

      expect(applied, isFalse);
      expect(fixture.fallbackRuns, 1);
      expect(
        fixture.agent.lastCommandResult?.message,
        'Rerun Failed Tests skipped: no test result is available.',
      );
    },
  );
}

_Fixture _fixture({bool blockDirty = false}) {
  final agent = AgentController();
  final buffer = RuntimeOutputLiveBuffer();
  late final _Fixture fixture;
  final testing = ShellTestingController(
    sessionController: null,
    workspaceRoot: () => '/workspace/fixture',
    runTestsFallback: () async => fixture.fallbackRuns += 1,
    runtimeOutputBuffer: buffer,
    log: (_) {},
  );
  fixture = _Fixture(agent: agent, testing: testing, buffer: buffer);
  fixture.commands = AgentTestingCommandController(
    testingController: testing,
    agentController: agent,
    blockWhenDirty: (_) => blockDirty,
  );
  return fixture;
}

final class _Fixture {
  _Fixture({required this.agent, required this.testing, required this.buffer});

  final AgentController agent;
  final ShellTestingController testing;
  final RuntimeOutputLiveBuffer buffer;
  late AgentTestingCommandController commands;
  int fallbackRuns = 0;

  void dispose() {
    testing.dispose();
    buffer.dispose();
    agent.dispose();
  }
}
