import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_project_lifecycle_command_controller.dart';

void main() {
  test('dirty workspace blocks dependency side effects', () async {
    final fixture = _fixture(blockDirty: true);
    addTearDown(fixture.dispose);

    expect(
      await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'fetchDependencies'),
      ),
      isFalse,
    );
    expect(fixture.actions, isEmpty);
  });

  test('dependency success preserves authoritative payload facts', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    expect(
      await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'vendorDependencies'),
      ),
      isTrue,
    );
    final metadata =
        fixture.agent.lastCommandResult!.metadata['dependencySourceCommand']!
            as Map<String, Object?>;
    expect(metadata['status'], 'succeeded');
    expect((metadata['payload']! as Map)['packages'], 2);
  });

  test('deployment failure is recorded and fails closed', () async {
    final fixture = _fixture(deploymentSucceeds: false);
    addTearDown(fixture.dispose);

    expect(
      await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'preparePublish'),
      ),
      isFalse,
    );
    final metadata =
        fixture.agent.lastCommandResult!.metadata['deploymentCommand']!
            as Map<String, Object?>;
    expect(metadata['succeeded'], isFalse);
    expect(metadata['statusMessage'], 'blocked');
  });
}

_Fixture _fixture({bool blockDirty = false, bool deploymentSucceeds = true}) {
  final agent = AgentController();
  final fixture = _Fixture(agent: agent);
  fixture.commands = AgentProjectLifecycleCommandController(
    agentController: agent,
    blockWhenDirty: (_) => blockDirty,
    fetchDependencies: () => fixture.dependency('fetch'),
    vendorDependencies: () => fixture.dependency('vendor'),
    packProject: () => fixture.deployment('pack', deploymentSucceeds),
    preparePublish: () => fixture.deployment('publish', deploymentSucceeds),
  );
  return fixture;
}

final class _Fixture {
  _Fixture({required this.agent});

  final AgentController agent;
  late AgentProjectLifecycleCommandController commands;
  final List<String> actions = <String>[];

  Future<DependencySourceCommandResult> dependency(String command) async {
    actions.add(command);
    return DependencySourceCommandResult(
      command: command,
      status: DependencySourceCommandStatus.succeeded,
      statusMessage: 'completed',
      stdout: '',
      stderr: '',
      payload: const <String, Object?>{'packages': 2},
    );
  }

  Future<DeploymentCommandResult> deployment(
    String command,
    bool succeeds,
  ) async {
    actions.add(command);
    return DeploymentCommandResult(
      command: command,
      status: succeeds
          ? DeploymentCommandStatus.succeeded
          : DeploymentCommandStatus.blocked,
      statusMessage: succeeds ? 'completed' : 'blocked',
      stdout: '',
      stderr: '',
    );
  }

  void dispose() => agent.dispose();
}
