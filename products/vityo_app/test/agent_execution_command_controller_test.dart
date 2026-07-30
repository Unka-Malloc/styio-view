import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent_client/agent.dart';
import 'package:vityo_app/src/view_ide/backend_toolchain/backend_toolchain.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/language/language_contract.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_execution_command_controller.dart';

void main() {
  test('dirty workspace blocks run before execution dispatch', () async {
    final fixture = _fixture(blockDirty: true);
    addTearDown(fixture.dispose);

    expect(
      await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'run'),
      ),
      isFalse,
    );
    expect(fixture.executed, isEmpty);
  });

  test('missing execution session fails closed', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    expect(
      await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'run'),
      ),
      isFalse,
    );
    expect(
      fixture.agent.lastCommandResult?.message,
      contains('no execution session'),
    );
  });

  test('run records typed session and bounded runtime event kinds', () async {
    final fixture = _fixture(
      session: const ExecutionSession(
        sessionId: 'run-1',
        kind: 'run',
        status: ExecutionSessionStatus.succeeded,
        statusMessage: 'completed',
        diagnostics: <Diagnostic>[],
        stdoutEvents: <ExecutionLogEvent>[],
        stderrEvents: <ExecutionLogEvent>[],
      ),
      events: <RuntimeEventEnvelope>[
        RuntimeEventEnvelope(
          schemaVersion: 1,
          sessionId: 'run-1',
          sequence: 1,
          timestamp: DateTime.utc(2026),
          eventKind: 'run.finished',
          origin: 'styio.runtime',
          payload: const <String, Object?>{},
        ),
      ],
    );
    addTearDown(fixture.dispose);

    expect(
      await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'run'),
      ),
      isTrue,
    );
    final metadata = fixture.agent.lastCommandResult!.metadata;
    expect(metadata['runtimeEventCount'], 1);
    expect(metadata['runtimeEventKinds'], <String>['run.finished']);
    expect((metadata['executionSession']! as Map)['sessionId'], 'run-1');
  });
}

_Fixture _fixture({
  bool blockDirty = false,
  ExecutionSession? session,
  List<RuntimeEventEnvelope> events = const <RuntimeEventEnvelope>[],
}) {
  final agent = AgentController();
  final fixture = _Fixture(agent: agent);
  fixture.commands = AgentExecutionCommandController(
    agentController: agent,
    executeCommand: (command) async => fixture.executed.add(command),
    executionSession: () => session,
    runtimeEvents: () => events,
    blockWhenDirty: (_) => blockDirty,
  );
  return fixture;
}

final class _Fixture {
  _Fixture({required this.agent});
  final AgentController agent;
  late AgentExecutionCommandController commands;
  final List<AppCommandId> executed = <AppCommandId>[];

  void dispose() => agent.dispose();
}
