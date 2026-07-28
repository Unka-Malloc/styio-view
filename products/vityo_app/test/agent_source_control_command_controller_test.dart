import 'package:flutter_test/flutter_test.dart';
import 'package:vityo_app/src/view_ide/agent_client/agent.dart';
import 'package:vityo_app/src/view_ide/commands/commands.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/agent_source_control_command_controller.dart';
import 'package:vityo_app/src/view_ide/shell_runtime/controllers/source_control_controller.dart';

void main() {
  test('refresh reports authoritative local dirty-document facts', () async {
    final fixture = _fixture(dirtyPaths: const <String>['src/main.styio']);
    addTearDown(fixture.dispose);

    final applied = await fixture.commands.apply(
      const AgentIdeCommandSuggestion(commandId: 'refreshSourceControl'),
    );

    expect(applied, isTrue);
    final sourceControl =
        fixture.agent.lastCommandResult!.metadata['sourceControl']!
            as Map<String, Object?>;
    expect(sourceControl['providerKind'], 'local-dirty-documents');
    expect(sourceControl['changeCount'], 1);
  });

  test('diff preview fails closed without a source-control provider', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    final applied = await fixture.commands.apply(
      const AgentIdeCommandSuggestion(commandId: 'previewSourceControlDiff'),
    );

    expect(applied, isFalse);
    expect(
      fixture.agent.lastCommandResult?.message,
      contains('no source control'),
    );
    final diff =
        fixture.agent.lastCommandResult!.metadata['sourceControlDiff']!
            as Map<String, Object?>;
    expect(diff['path'], 'src/main.styio');
    expect(diff['available'], isFalse);
  });

  test(
    'stage reports the registered input contract when paths are absent',
    () async {
      final fixture = _fixture();
      addTearDown(fixture.dispose);

      final applied = await fixture.commands.apply(
        const AgentIdeCommandSuggestion(commandId: 'stageSourceControl'),
      );

      expect(applied, isFalse);
      final result = fixture.agent.lastCommandResult!;
      expect(result.metadata['reason'], 'missing-input');
      expect(result.metadata['inputContract'], isNotEmpty);
    },
  );

  test('ordinary missing-input receipt preserves command wording', () async {
    final fixture = _fixture();
    addTearDown(fixture.dispose);

    await fixture.commands.executeOrdinary(
      AppCommandId.planSourceControlBranchSwitch,
    );

    final result = fixture.agent.lastCommandResult!;
    expect(
      result.message,
      'Plan Source Control Branch Switch requires target branch input.',
    );
    expect(result.metadata['reason'], 'missing-input');
    expect(result.metadata['inputContract'], isNotEmpty);
  });

  test(
    'commit draft parses selected paths and preserves prerequisite receipt',
    () async {
      final fixture = _fixture();
      addTearDown(fixture.dispose);

      final applied = await fixture.commands.apply(
        const AgentIdeCommandSuggestion(
          commandId: 'planSourceControlCommitDraft',
          input: 'Ship trustworthy loop -> src/main.styio, test/main_test.dart',
          prerequisiteForCommandId: 'runBuild',
        ),
      );

      expect(applied, isTrue);
      final result = fixture.agent.lastCommandResult!;
      expect(result.metadata['completedRequiredCommandFor'], 'runBuild');
      final draft =
          result.metadata['sourceControlCommitDraft']! as Map<String, Object?>;
      expect(draft['message'], 'Ship trustworthy loop');
      expect(draft['selectedPaths'], <String>[
        'src/main.styio',
        'test/main_test.dart',
      ]);
    },
  );
}

_Fixture _fixture({List<String> dirtyPaths = const <String>[]}) {
  final agent = AgentController();
  final sourceControl = SourceControlController(
    statusController: null,
    workspaceId: () => '/workspace/fixture',
    dirtyDocumentPaths: () => dirtyPaths,
    log: (_) {},
  );
  return _Fixture(
    agent: agent,
    sourceControl: sourceControl,
    commands: AgentSourceControlCommandController(
      sourceControlController: sourceControl,
      agentController: agent,
      activeFilePath: () => 'src/main.styio',
      log: (_) {},
    ),
  );
}

final class _Fixture {
  const _Fixture({
    required this.agent,
    required this.sourceControl,
    required this.commands,
  });

  final AgentController agent;
  final SourceControlController sourceControl;
  final AgentSourceControlCommandController commands;

  void dispose() {
    sourceControl.dispose();
    agent.dispose();
  }
}
