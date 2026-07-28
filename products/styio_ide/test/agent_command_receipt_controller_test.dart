import 'package:flutter_test/flutter_test.dart';
import 'package:styio_ide/src/view_ide/agent_client/agent.dart';
import 'package:styio_ide/src/view_ide/commands/commands.dart';
import 'package:styio_ide/src/view_ide/interaction/interaction.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/agent_command_receipt_controller.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/controllers/agent_controller.dart';
import 'package:styio_ide/src/view_ide/shell_runtime/workspace_file_lifecycle.dart';

void main() {
  test('settings prerequisite is recorded as recovery, not completion', () {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    fixture.receipts.record(
      const AgentIdeCommandSuggestion(
        commandId: 'openSettings',
        prerequisiteForCommandId: 'runBuild',
      ),
      applied: true,
      message: 'opened',
    );

    expect(
      fixture.agent.lastCommandResult?.metadata['recoveryForCommandId'],
      'runBuild',
    );
    expect(
      fixture.agent.lastCommandResult?.metadata,
      isNot(contains('completedRequiredCommandFor')),
    );
  });

  test('dirty disk-backed command fails closed with save-all recovery', () {
    final fixture = _Fixture(dirty: <String>['src/main.styio']);
    addTearDown(fixture.dispose);

    final blocked = fixture.receipts.blockDiskBackedCommandWhenDirty(
      const AgentIdeCommandSuggestion(commandId: 'runBuild'),
    );

    expect(blocked, isTrue);
    expect(
      fixture.agent.lastCommandResult?.metadata['requiredCommand'],
      'saveAll',
    );
    expect(fixture.logs.single, contains('save dirty workspace'));
  });

  test('missing input metadata is sourced from command registry', () {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);

    final metadata = fixture.receipts.missingInputMetadata(
      AppCommandId.renameSymbol,
    );

    expect(metadata['reason'], 'missing-input');
    expect(metadata['inputContract'], isNotNull);
  });

  test('save all preserves recovery completion receipt', () async {
    final fixture = _Fixture();
    addTearDown(fixture.dispose);
    fixture.receipts.record(
      const AgentIdeCommandSuggestion(commandId: 'runBuild'),
      applied: false,
      message: 'save first',
      metadata: const <String, Object?>{'requiredCommand': 'saveAll'},
    );

    final applied = await fixture.receipts.executeSave(
      const AgentIdeCommandSuggestion(commandId: 'saveAll'),
    );

    expect(applied, isTrue);
    expect(
      fixture.agent.lastCommandResult?.metadata['completedRequiredCommandFor'],
      'runBuild',
    );
  });
}

final class _Fixture {
  _Fixture({this.dirty = const <String>[]}) {
    receipts = AgentCommandReceiptController(
      agentController: agent,
      dirtyDocumentIds: () => dirty,
      activeDocumentPath: () => 'src/main.styio',
      saveActive: () async => const DocumentResourceBindingSnapshot(
        state: DocumentResourceBindingState.boundClean,
      ),
      saveAll: () async => const WorkspaceSaveAllResult(
        savedDocumentIds: <String>['src/main.styio'],
        skippedDocumentIds: <String>[],
        message: 'Saved all workspace files.',
      ),
      log: logs.add,
    );
  }

  final AgentController agent = AgentController();
  final List<String> dirty;
  final List<String> logs = <String>[];
  late final AgentCommandReceiptController receipts;

  void dispose() => agent.dispose();
}
