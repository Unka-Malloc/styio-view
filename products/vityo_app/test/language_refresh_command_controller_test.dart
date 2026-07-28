import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent_client/agent.dart';
import 'package:vityo_app/src/view_ide/interaction/interaction.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/language_refresh_command_controller.dart';

void main() {
  test(
    'missing refresh callback fails closed with an explicit receipt',
    () async {
      final agent = AgentController();
      addTearDown(agent.dispose);
      final logs = <String>[];
      final controller = LanguageRefreshCommandController(
        agentController: agent,
        refreshAvailable: () => false,
        refresh: () async => throw StateError('must not run'),
        status: LanguageServiceStatusSurface.unavailable,
        log: logs.add,
      );

      final applied = await controller.execute(
        suggestion: const AgentIdeCommandSuggestion(
          commandId: 'refreshLanguageService',
        ),
      );

      expect(applied, isFalse);
      expect(agent.lastCommandResult?.applied, isFalse);
      expect(
        agent.lastCommandResult?.metadata['reason'],
        'missing-refresh-callback',
      );
      expect(logs.single, contains('skipped'));
    },
  );

  test(
    'successful refresh records current language facts and prerequisite',
    () async {
      final agent = AgentController();
      addTearDown(agent.dispose);
      var refreshCount = 0;
      final controller = LanguageRefreshCommandController(
        agentController: agent,
        refreshAvailable: () => true,
        refresh: () async => refreshCount += 1,
        status: () => const LanguageServiceStatusSurface(
          runtimeState: 'active',
          severity: LanguageServiceStatusSeverity.ready,
          title: 'ready',
          message: 'ready',
          usableCapabilityCount: 2,
          freshCapabilityCount: 1,
          primaryCapabilityStates: <String, String>{'diagnostics': 'available'},
          capabilities: <LanguageServiceCapabilityStatusItem>[],
          parserEngine: 'styio',
          grammarVersion: 'pinned',
        ),
        log: (_) {},
      );

      final applied = await controller.execute(
        suggestion: const AgentIdeCommandSuggestion(
          commandId: 'refreshLanguageService',
          prerequisiteForCommandId: 'run',
        ),
      );

      expect(applied, isTrue);
      expect(refreshCount, 1);
      expect(
        agent.lastCommandResult?.metadata,
        containsPair('languageServiceParserEngine', 'styio'),
      );
      expect(
        agent.lastCommandResult?.metadata['completedRequiredCommandFor'],
        'run',
      );
    },
  );

  test('refresh exception is contained and recorded', () async {
    final agent = AgentController();
    addTearDown(agent.dispose);
    final controller = LanguageRefreshCommandController(
      agentController: agent,
      refreshAvailable: () => true,
      refresh: () async => throw StateError('offline'),
      status: LanguageServiceStatusSurface.unavailable,
      log: (_) {},
    );

    final applied = await controller.execute(
      suggestion: const AgentIdeCommandSuggestion(
        commandId: 'refreshLanguageService',
      ),
    );

    expect(applied, isFalse);
    expect(agent.lastCommandResult?.metadata['error'], contains('offline'));
  });
}
