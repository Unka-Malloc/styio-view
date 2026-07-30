import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent_client/agent.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_debug_command_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/debug_controller.dart';

void main() {
  test(
    'start debug is blocked before dispatch when workspace is dirty',
    () async {
      final fixture = _fixture(blockDirty: true);
      addTearDown(fixture.dispose);

      expect(
        await fixture.commands.apply(
          const AgentIdeCommandSuggestion(commandId: 'startDebugging'),
        ),
        isFalse,
      );
      expect(fixture.actions, isEmpty);
    },
  );

  test('thread selection reports registered input contract', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    expect(
      await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'selectDebugThread'),
      ),
      isFalse,
    );
    expect(
      fixture.agent.lastCommandResult?.metadata['inputContract'],
      isNotEmpty,
    );
  });

  test('debug result records status and selected frame facts', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    expect(
      await fixture.commands.apply(
        const AgentIdeCommandSuggestion(
          commandId: 'selectDebugStackFrame',
          input: ' frame-7 ',
        ),
      ),
      isTrue,
    );
    expect(fixture.actions, <String>['frame:frame-7']);
    expect(fixture.agent.lastCommandResult?.metadata['frameId'], 'frame-7');
  });
}

_Fixture _fixture({bool blockDirty = false}) {
  final agent = AgentController();
  final fixture = _Fixture(agent: agent);
  const success = DebugCommandResult(applied: true, message: 'Applied.');
  fixture.commands = AgentDebugCommandController(
    agentController: agent,
    toggleBreakpoint: () => success,
    start: () {
      fixture.actions.add('start');
      return success;
    },
    stop: () => success,
    resume: () => success,
    stepOver: () => success,
    selectThread: (id) {
      fixture.actions.add('thread:$id');
      return success;
    },
    selectStackFrame: (id) {
      fixture.actions.add('frame:$id');
      return success;
    },
    debugStatus: () => 'paused',
    blockWhenDirty: (_) => blockDirty,
    log: fixture.logs.add,
  );
  return fixture;
}

final class _Fixture {
  _Fixture({required this.agent});

  final AgentController agent;
  late AgentDebugCommandController commands;
  final List<String> actions = <String>[];
  final List<String> logs = <String>[];

  void dispose() => agent.dispose();
}
