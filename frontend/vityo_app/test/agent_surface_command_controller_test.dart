import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_surface_command_controller.dart';

void main() {
  test('settings recovery routes toolchain prerequisite facts', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    expect(
      await fixture.commands.apply(
        const AgentIdeCommandSuggestion(
          commandId: 'openSettings',
          prerequisiteForCommandId: 'runBuild',
        ),
      ),
      isTrue,
    );
    expect(fixture.executed, <AppCommandId>[AppCommandId.openSettings]);
    expect(
      fixture.agent.lastCommandResult?.metadata['settingsSection'],
      'toolchain',
    );
  });

  test('debug surface command records exact target', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    await fixture.commands.apply(
      const AgentIdeCommandSuggestion(commandId: 'showDebug'),
    );

    final surface =
        fixture.agent.lastCommandResult!.metadata['surfaceCommand']!
            as Map<String, Object?>;
    expect(surface['targetSurface'], 'debug');
    expect(fixture.executed, <AppCommandId>[AppCommandId.showDebug]);
  });
}

_Fixture _fixture() {
  final agent = AgentController();
  final fixture = _Fixture(agent: agent);
  fixture.commands = AgentSurfaceCommandController(
    agentController: agent,
    executeCommand: (command) async => fixture.executed.add(command),
  );
  return fixture;
}

final class _Fixture {
  _Fixture({required this.agent});
  final AgentController agent;
  late AgentSurfaceCommandController commands;
  final List<AppCommandId> executed = <AppCommandId>[];

  void dispose() => agent.dispose();
}
