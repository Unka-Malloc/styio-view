import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent_client/agent.dart';
import 'package:vityo_app/src/view_ide/platform/platform.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_provider_recovery_command_controller.dart';

void main() {
  test('retry fails closed when no recovery draft exists', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    final applied = await fixture.commands.apply(
      const AgentIdeCommandSuggestion(commandId: 'retryAgentProvider'),
    );

    expect(applied, isFalse);
    expect(
      fixture.agent.lastCommandResult?.message,
      contains('no recovery draft'),
    );
    final dispatch =
        fixture.agent.lastCommandResult!.metadata['recoveryDispatch']!
            as Map<String, Object?>;
    expect(dispatch['status'], 'blocked');
    expect(fixture.notifications, 1);
  });

  test('failover rejects a missing provider profile key', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    final applied = await fixture.commands.apply(
      const AgentIdeCommandSuggestion(commandId: 'failoverAgentProvider'),
    );

    expect(applied, isFalse);
    expect(
      fixture.agent.lastCommandResult?.metadata['reason'],
      'missing-input',
    );
    expect(fixture.failoverKeys, isEmpty);
  });

  test(
    'failover trims the key and records unavailable configurator facts',
    () async {
      final fixture = _fixture();
      addTearDown(fixture.dispose);

      final applied = await fixture.commands.apply(
        const AgentIdeCommandSuggestion(
          commandId: 'failoverAgentProvider',
          input: '  saved-profile  ',
          prerequisiteForCommandId: 'runBuild',
        ),
      );

      expect(applied, isFalse);
      expect(fixture.failoverKeys, <String>['saved-profile']);
      final result = fixture.agent.lastCommandResult!;
      expect(result.message, contains('no configurator'));
      expect(result.metadata['targetProviderProfileKey'], 'saved-profile');
      expect(result.metadata['completedRequiredCommandFor'], 'runBuild');
    },
  );
}

_Fixture _fixture() {
  final agent = AgentController();
  final session = AgentCodingSessionController(
    profile: AgentPromptProfile.defaultForPlatform(PlatformTarget.web),
    adapter: const LocalOnlyAgentProviderAdapter(),
    contextProvider: () =>
        throw StateError('Context is not needed by this test.'),
  );
  final fixture = _Fixture(agent: agent, session: session);
  fixture.commands = AgentProviderRecoveryCommandController(
    sessionController: session,
    agentController: agent,
    failoverProviderProfile: (key) async {
      fixture.failoverKeys.add(key);
      return null;
    },
    log: fixture.logs.add,
    notify: () => fixture.notifications += 1,
  );
  return fixture;
}

final class _Fixture {
  _Fixture({required this.agent, required this.session});

  final AgentController agent;
  final AgentCodingSessionController session;
  late AgentProviderRecoveryCommandController commands;
  final List<String> failoverKeys = <String>[];
  final List<String> logs = <String>[];
  int notifications = 0;

  void dispose() {
    session.dispose();
    agent.dispose();
  }
}
