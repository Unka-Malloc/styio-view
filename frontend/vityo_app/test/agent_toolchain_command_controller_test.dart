import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
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

  test('dirty workspace blocks compiler mutation before dispatch', () async {
    final fixture = _fixture(blockDirty: true);
    addTearDown(fixture.dispose);

    expect(
      await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'pinActiveCompiler'),
      ),
      isFalse,
    );
    expect(fixture.executed, isEmpty);
  });

  test('missing bootstrap dispatch fails closed with typed receipt', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    expect(
      await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'bootstrapStyioToolchain'),
      ),
      isFalse,
    );
    expect(
      fixture.agent.lastCommandResult?.message,
      contains('no bootstrap result'),
    );
  });
}

_Fixture _fixture({bool blockDirty = false}) {
  final agent = AgentController();
  final toolchain = ToolchainController(
    managementAdapter: const _UnexpectedAdapter(),
    projectGraph: () => ProjectGraphSnapshot.scratch(
      workspaceRoot: '/workspace/fixture',
      activeFilePath: 'main.styio',
      title: 'fixture',
      notes: const <String>[],
    ),
    refreshProjectGraph: ({String? reason}) async {},
    manager: null,
    statusReport: null,
    log: (_) {},
  );
  final fixture = _Fixture(agent: agent, toolchain: toolchain);
  fixture.commands = AgentToolchainCommandController(
    agentController: agent,
    toolchainController: toolchain,
    blockedReasonForCommand: (_) => null,
    executeCommand: (command) async => fixture.executed.add(command.name),
    selectClangCppVersion: (versionId, {cppStandard}) async => null,
    handleBootstrapAction: (_) async => null,
    executeLastInstallPlan: () async => null,
    blockWhenDirty: (_) => blockDirty,
    log: (_) {},
    notify: () {},
  );
  return fixture;
}

final class _Fixture {
  _Fixture({required this.agent, required this.toolchain});
  final AgentController agent;
  final ToolchainController toolchain;
  late AgentToolchainCommandController commands;
  final List<String> executed = <String>[];

  void dispose() {
    toolchain.dispose();
    agent.dispose();
  }
}

final class _UnexpectedAdapter implements ToolchainManagementAdapter {
  const _UnexpectedAdapter();

  Never _unexpected() =>
      throw StateError('Toolchain adapter was not expected.');

  @override
  Future<ToolchainCommandResult> clearPinnedCompiler({
    required ProjectGraphSnapshot projectGraph,
  }) async => _unexpected();

  @override
  Future<ToolchainCommandResult> installManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String styioBinaryPath,
  }) async => _unexpected();

  @override
  Future<ToolchainCommandResult> pinManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async => _unexpected();

  @override
  Future<ToolchainCommandResult> useManagedCompiler({
    required ProjectGraphSnapshot projectGraph,
    required String compilerVersion,
    String? channel,
  }) async => _unexpected();
}
