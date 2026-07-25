import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent/agent.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_native_tool_command_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/execution_controller.dart';

void main() {
  test(
    'build is blocked before native-tool dispatch when workspace is dirty',
    () async {
      final fixture = _fixture(blockDirty: true);
      addTearDown(fixture.dispose);

      final applied = await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'runBuild'),
      );

      expect(applied, isFalse);
      expect(fixture.dispatched, isEmpty);
    },
  );

  test('format remains available for the dirty active document', () async {
    final fixture = _fixture(blockDirty: true);
    addTearDown(fixture.dispose);

    final applied = await fixture.commands.apply(
      const AgentIdeCommandSuggestion(commandId: 'formatActiveDocument'),
    );

    expect(applied, isTrue);
    expect(fixture.dispatched, <NativeToolCommand>[
      NativeToolCommand.formatDocument,
    ]);
  });

  test('native-tool receipt metadata and prerequisite are preserved', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    final applied = await fixture.commands.apply(
      const AgentIdeCommandSuggestion(
        commandId: 'runStaticAnalysis',
        prerequisiteForCommandId: 'runBuild',
      ),
    );

    expect(applied, isTrue);
    final result = fixture.agent.lastCommandResult!;
    expect(result.metadata['receiptId'], 'native-receipt');
    expect(result.metadata['completedRequiredCommandFor'], 'runBuild');
  });

  test(
    'ordinary native tool dispatch does not use Agent dirty guard',
    () async {
      final fixture = _fixture(blockDirty: true);
      addTearDown(fixture.dispose);

      await fixture.commands.executeOrdinary(AppCommandId.runBuild);

      expect(fixture.dispatched, <NativeToolCommand>[NativeToolCommand.build]);
      expect(
        fixture.agent.lastCommandResult?.metadata['receiptId'],
        'native-receipt',
      );
    },
  );
}

_Fixture _fixture({bool blockDirty = false}) {
  final agent = AgentController();
  final fixture = _Fixture(agent: agent);
  fixture.commands = AgentNativeToolCommandController(
    agentController: agent,
    blockWhenDirty: (_) => blockDirty,
    runNativeToolCommand: (command) async {
      fixture.dispatched.add(command);
      return const NativeToolCommandResult(
        applied: true,
        message: 'Native tool completed.',
        metadata: <String, Object?>{'receiptId': 'native-receipt'},
      );
    },
  );
  return fixture;
}

final class _Fixture {
  _Fixture({required this.agent});

  final AgentController agent;
  late AgentNativeToolCommandController commands;
  final List<NativeToolCommand> dispatched = <NativeToolCommand>[];

  void dispose() => agent.dispose();
}
