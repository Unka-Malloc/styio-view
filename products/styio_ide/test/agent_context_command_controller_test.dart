import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/agent_client/agent.dart';
import 'package:styio_ide/src/view_ide/commands/commands.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/agent_context_command_controller.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/agent_controller.dart';

void main() {
  test('coding checkpoint preserves collected capability facts', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    await fixture.commands.apply(
      const AgentIdeCommandSuggestion(
        commandId: 'collectAgentCodingCheckpoint',
      ),
    );

    expect(fixture.agent.lastCommandResult?.metadata['schemaVersion'], 2);
  });

  test('project language facts retain their typed metadata scope', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    await fixture.commands.apply(
      const AgentIdeCommandSuggestion(
        commandId: 'collectProjectLanguageContext',
      ),
    );

    final facts =
        fixture.agent.lastCommandResult!.metadata['projectLanguage']!
            as Map<String, Object?>;
    expect(facts['factSource'], 'compiler');
  });

  test(
    'ordinary context collection preserves non-agent receipt wording',
    () async {
      final fixture = _fixture();
      addTearDown(fixture.dispose);

      await fixture.commands.executeOrdinary(
        AppCommandId.collectAgentCodingCheckpoint,
      );

      expect(
        fixture.agent.lastCommandResult?.message,
        'Agent coding checkpoint collected.',
      );
      expect(fixture.agent.lastCommandResult?.metadata['schemaVersion'], 2);
    },
  );

  test(
    'module refresh executes before collecting refreshed host facts',
    () async {
      final fixture = _fixture();
      addTearDown(fixture.dispose);

      await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'refreshModules'),
      );

      expect(fixture.actions, <String>[
        'execute:refreshModules',
        'collect:modules',
      ]);
      expect(
        fixture.agent.lastCommandResult?.metadata['moduleHostRefresh'],
        isNotNull,
      );
    },
  );
}

_Fixture _fixture() {
  final agent = AgentController();
  final fixture = _Fixture(agent: agent);
  fixture.commands = AgentContextCommandController(
    agentController: agent,
    collectCodingCheckpoint: () async => <String, Object?>{'schemaVersion': 2},
    collectProjectLanguageContext: () async => <String, Object?>{
      'factSource': 'compiler',
    },
    executeCommand: (command) async =>
        fixture.actions.add('execute:${command.name}'),
    collectModuleRefreshMetadata: () async {
      fixture.actions.add('collect:modules');
      return <String, Object?>{'moduleCount': 1};
    },
  );
  return fixture;
}

final class _Fixture {
  _Fixture({required this.agent});
  final AgentController agent;
  late AgentContextCommandController commands;
  final List<String> actions = <String>[];

  void dispose() => agent.dispose();
}
