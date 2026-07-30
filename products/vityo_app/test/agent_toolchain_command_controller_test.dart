import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent_client/agent.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_toolchain_command_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/toolchain_controller.dart';

void main() {
  test('version selection reports registered input facts', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    expect(
      await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'selectClangCppVersion'),
      ),
      isFalse,
    );
    expect(
      fixture.agent.lastCommandResult?.metadata['inputContract'],
      isNotEmpty,
    );
  });

  test('unknown toolchain commands are rejected', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    expect(
      () => fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'unknownToolchainCommand'),
      ),
      throwsArgumentError,
    );
  });
}

_Fixture _fixture() {
  final agent = AgentController();
  final toolchain = ToolchainController(
    projectGraph: () => ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/fixture',
      activeFilePath: 'main.styio',
      title: 'fixture',
      notes: const <String>[],
    ),
    manager: null,
    statusReport: null,
    log: (_) {},
  );
  final commands = AgentToolchainCommandController(
    agentController: agent,
    toolchainController: toolchain,
    selectClangCppVersion: (versionId, {cppStandard}) async => null,
    executeLastInstallPlan: () async => null,
    notify: () {},
  );
  return _Fixture(agent: agent, toolchain: toolchain, commands: commands);
}

final class _Fixture {
  _Fixture({
    required this.agent,
    required this.toolchain,
    required this.commands,
  });

  final AgentController agent;
  final ToolchainController toolchain;
  final AgentToolchainCommandController commands;

  void dispose() {
    toolchain.dispose();
    agent.dispose();
  }
}
